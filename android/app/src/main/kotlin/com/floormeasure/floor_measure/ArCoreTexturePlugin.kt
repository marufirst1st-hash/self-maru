package com.floormeasure.floor_measure

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.*
import android.media.ImageReader
import android.opengl.*
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.ar.core.*
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * ARCore + Flutter Texture
 * SharedCamera로 ARCore와 Flutter가 같은 카메라 공유
 */
class ArCoreTexturePlugin(
    private val activity: Activity,
    private val engine: FlutterEngine,
) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.floormeasure/arcore")
    private var session: Session? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var renderThread: Thread? = null
    private var installed = false
    private var planeDetected = false
    private val detectedWalls = mutableMapOf<String, FloatArray>() // planeId -> [cx, cy, cz, nx, ny, nz, extentX, extentZ]
    @Volatile private var tapX = -1f
    @Volatile private var tapY = -1f
    @Volatile private var running = false
    private var viewWidth = 1080
    private var viewHeight = 1920
    private var lastPlanesSentMs = 0L
    private var lastFlashMs = 0L
    private var flashOn = false
    private var flashGridOff: DoubleArray? = null
    private var flashOnStartMs = 0L
    private var lastCornerMs = 0L

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    viewWidth = call.argument<Int>("width") ?: 1080
                    viewHeight = call.argument<Int>("height") ?: 1920
                    result.success(startAr())
                }
                "tap" -> {
                    tapX = (call.argument<Double>("x") ?: -1.0).toFloat()
                    tapY = (call.argument<Double>("y") ?: -1.0).toFloat()
                    result.success(true)
                }
                "stop" -> { stopAr(); result.success(true) }
                else -> result.notImplemented()
            }
        }
    }

    private fun startAr(): Long {
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.CAMERA), 1001)
            return -1
        }

        try {
            val avail = ArCoreApk.getInstance().checkAvailability(activity)
            if (!avail.isSupported) {
                activity.runOnUiThread { channel.invokeMethod("onError", "ARCore 미지원") }
                return -1
            }
            when (ArCoreApk.getInstance().requestInstall(activity, !installed)) {
                ArCoreApk.InstallStatus.INSTALLED -> installed = true
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> return -1
            }

            session = Session(activity)
            val config = Config(session!!)
            config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
            config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            config.focusMode = Config.FocusMode.AUTO
            session!!.configure(config)

            // Flutter TextureRegistry → SurfaceTexture
            textureEntry = engine.renderer.createSurfaceTexture()
            val flutterST = textureEntry!!.surfaceTexture()
            flutterST.setDefaultBufferSize(viewWidth, viewHeight)

            // ARCore 카메라 텍스처 (OpenGL) - 별도
            // ARCore는 자체 GL 텍스처에 카메라를 그림
            // 우리는 ARCore 프레임에서 이미지를 가져와 Flutter SurfaceTexture에 복사

            // session.resume()는 렌더 스레드에서 호출 (setCameraTextureName 이후)
            android.util.Log.d("ArCorePlugin", "Starting render thread")

            running = true
            renderThread = Thread {
                val surface = Surface(flutterST)

                // EGL 초기화
                val eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
                EGL14.eglInitialize(eglDisplay, IntArray(1), 0, IntArray(1), 0)
                val cfgAttr = intArrayOf(EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT, EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8, EGL14.EGL_NONE)
                val configs = arrayOfNulls<android.opengl.EGLConfig>(1)
                EGL14.eglChooseConfig(eglDisplay, cfgAttr, 0, configs, 0, 1, IntArray(1), 0)
                val ctxAttr = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
                val eglContext = EGL14.eglCreateContext(eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT, ctxAttr, 0)
                val eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, configs[0], surface, intArrayOf(EGL14.EGL_NONE), 0)
                EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)

                // 카메라 텍스처 생성 → ARCore에 등록 → resume (이 순서 중요!)
                val tex = IntArray(1); GLES20.glGenTextures(1, tex, 0)
                GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, tex[0])
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
                session!!.setCameraTextureName(tex[0])

                // 텍스처 등록 후 세션 시작
                session!!.resume()
                android.util.Log.d("ArCorePlugin", "Session resumed on GL thread after setCameraTextureName")

                // 셰이더
                val vs = "attribute vec4 a_P; attribute vec2 a_T; varying vec2 v_T; void main(){gl_Position=a_P; v_T=a_T;}"
                val fs = "#extension GL_OES_EGL_image_external : require\nprecision mediump float; varying vec2 v_T; uniform samplerExternalOES u_Tex; void main(){gl_FragColor=texture2D(u_Tex,v_T);}"
                val vsh = GLES20.glCreateShader(GLES20.GL_VERTEX_SHADER); GLES20.glShaderSource(vsh, vs); GLES20.glCompileShader(vsh)
                val fsh = GLES20.glCreateShader(GLES20.GL_FRAGMENT_SHADER); GLES20.glShaderSource(fsh, fs); GLES20.glCompileShader(fsh)
                val prog = GLES20.glCreateProgram(); GLES20.glAttachShader(prog, vsh); GLES20.glAttachShader(prog, fsh); GLES20.glLinkProgram(prog)

                val quadV = floatArrayOf(-1f,-1f, -1f,1f, 1f,-1f, 1f,1f)
                val quadT = floatArrayOf(0f,1f, 0f,0f, 1f,1f, 1f,0f)

                fun buf(a: FloatArray): FloatBuffer = ByteBuffer.allocateDirect(a.size*4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(a); position(0) }

                val vBuf = buf(quadV)
                val tBuf = buf(quadT)

                android.util.Log.d("ArCorePlugin", "Render loop starting")

                while (running) {
                    try {
                        val s = session ?: break
                        val frame = s.update()
                        s.setDisplayGeometry(activity.windowManager.defaultDisplay.rotation, viewWidth, viewHeight)

                        GLES20.glViewport(0, 0, viewWidth, viewHeight)
                        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

                        // 카메라 프레임 그리기
                        GLES20.glUseProgram(prog)
                        val pL = GLES20.glGetAttribLocation(prog, "a_P")
                        val tL = GLES20.glGetAttribLocation(prog, "a_T")

                        val uvBuf = ByteBuffer.allocateDirect(8*4).order(ByteOrder.nativeOrder()).asFloatBuffer()
                        tBuf.position(0)
                        frame.transformDisplayUvCoords(tBuf, uvBuf)
                        tBuf.position(0)
                        uvBuf.position(0)

                        GLES20.glEnableVertexAttribArray(pL)
                        GLES20.glEnableVertexAttribArray(tL)
                        GLES20.glVertexAttribPointer(pL, 2, GLES20.GL_FLOAT, false, 0, vBuf)
                        GLES20.glVertexAttribPointer(tL, 2, GLES20.GL_FLOAT, false, 0, uvBuf)
                        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
                        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, tex[0])
                        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
                        GLES20.glDisableVertexAttribArray(pL)
                        GLES20.glDisableVertexAttribArray(tL)

                        EGL14.eglSwapBuffers(eglDisplay, eglSurface)

                        // 탭
                        if (tapX >= 0) {
                            val tx = tapX; val ty = tapY; tapX = -1f; tapY = -1f
                            android.util.Log.d("ArCorePlugin", "HitTest at pixel ($tx, $ty)")
                            val hits = frame.hitTest(tx, ty)
                            android.util.Log.d("ArCorePlugin", "HitTest results: ${hits.size}")
                            for (hit in hits) {
                                android.util.Log.d("ArCorePlugin", "Hit: trackable=${hit.trackable::class.simpleName} dist=${hit.distance} pose=(${hit.hitPose.tx()},${hit.hitPose.ty()},${hit.hitPose.tz()})")
                                if (hit.trackable is Plane) {
                                    val plane = hit.trackable as Plane
                                    val inPolygon = plane.isPoseInPolygon(hit.hitPose)
                                    android.util.Log.d("ArCorePlugin", "Plane type=${plane.type} inPolygon=$inPolygon")
                                    if (inPolygon) {
                                        val p = hit.hitPose
                                        activity.runOnUiThread {
                                            channel.invokeMethod("onPlaneTap", mapOf(
                                                "x" to p.tx().toDouble(), "y" to p.ty().toDouble(),
                                                "z" to p.tz().toDouble(), "distance" to hit.distance.toDouble()))
                                        }
                                        break
                                    }
                                }
                            }
                        }

                        // 500ms마다 평면 전송 (성능)
                        val now = System.currentTimeMillis()
                        val shouldSendPlanes = now - lastPlanesSentMs >= 500
                        if (shouldSendPlanes) lastPlanesSentMs = now

                        val detectedPlanes = mutableListOf<Map<String, Any>>()
                        for (plane in s.getAllTrackables(Plane::class.java)) {
                            if (plane.trackingState != TrackingState.TRACKING) continue
                            if (plane.subsumedBy != null) continue // 병합된 건 스킵

                            val pose = plane.centerPose
                            val type = when (plane.type) {
                                Plane.Type.VERTICAL -> "wall"
                                Plane.Type.HORIZONTAL_UPWARD_FACING -> "floor"
                                Plane.Type.HORIZONTAL_DOWNWARD_FACING -> "ceiling"
                                else -> "unknown"
                            }

                            // 평면 법선
                            val yAxis = pose.getYAxis()

                            // 평면 경계 폴리곤 (로컬 좌표 → 월드 좌표)
                            val polygon = plane.polygon // FloatBuffer: x,z,x,z,...
                            val worldPoly = mutableListOf<Double>()
                            val numPoints = polygon.limit() / 2
                            for (i in 0 until numPoints) {
                                val lx = polygon.get(i * 2)
                                val lz = polygon.get(i * 2 + 1)
                                // 로컬→월드 변환
                                val wp = pose.transformPoint(floatArrayOf(lx, 0f, lz))
                                worldPoly.add(wp[0].toDouble()) // x
                                worldPoly.add(wp[1].toDouble()) // y
                                worldPoly.add(wp[2].toDouble()) // z
                            }

                            detectedPlanes.add(mapOf(
                                "id" to plane.hashCode().toString(),
                                "type" to type,
                                "cx" to pose.tx().toDouble(),
                                "cy" to pose.ty().toDouble(),
                                "cz" to pose.tz().toDouble(),
                                "nx" to yAxis[0].toDouble(),
                                "ny" to yAxis[1].toDouble(),
                                "nz" to yAxis[2].toDouble(),
                                "extentX" to plane.extentX.toDouble(),
                                "extentZ" to plane.extentZ.toDouble(),
                                "polygon" to worldPoly,
                            ))
                        }

                        if (shouldSendPlanes && detectedPlanes.isNotEmpty()) {
                            if (!planeDetected) {
                                planeDetected = true
                                activity.runOnUiThread { channel.invokeMethod("onPlaneDetected", true) }
                            }
                            activity.runOnUiThread {
                                channel.invokeMethod("onPlanesUpdated", detectedPlanes.toList())
                            }
                        }

                        // 카메라 포즈
                        val camera = frame.camera
                        if (camera.trackingState == TrackingState.TRACKING) {
                            val cp = camera.pose
                            activity.runOnUiThread {
                                channel.invokeMethod("onCameraPose", mapOf(
                                    "x" to cp.tx().toDouble(),
                                    "y" to cp.ty().toDouble(),
                                    "z" to cp.tz().toDouble(),
                                ))
                            }
                        }

                        // Corner Worker: 5초마다 프레임에서 모서리 후보 분석
                        if (now - lastCornerMs >= 5000 && !flashOn) { // Flash와 겹침 방지
                            lastCornerMs = now
                            try {
                                val img = frame.acquireCameraImage()
                                val w = img.width; val h = img.height
                                val yBuf = img.planes[0].buffer
                                val stride = img.planes[0].rowStride

                                // 간단한 Sobel gradient: 4x4 그리드에서 수평/수직 엣지 강도
                                val cellW = w / 4; val cellH = h / 4
                                val cornerCandidates = mutableListOf<Map<String, Any>>()

                                for (row in 1 until 3) {
                                    for (col in 1 until 3) {
                                        // 셀 중심의 수평/수직 gradient
                                        val cy = row * cellH + cellH / 2
                                        val cx = col * cellW + cellW / 2
                                        var gx = 0; var gy = 0
                                        val step = 3
                                        for (dy in -step..step) {
                                            for (dx in -step..step) {
                                                val px = (cx + dx).coerceIn(1, w - 2)
                                                val py = (cy + dy).coerceIn(1, h - 2)
                                                val maxIdx = yBuf.limit() - 1
                                                val li = (py * stride + px - 1).coerceIn(0, maxIdx)
                                                val ri = (py * stride + px + 1).coerceIn(0, maxIdx)
                                                val ui = ((py - 1) * stride + px).coerceIn(0, maxIdx)
                                                val di = ((py + 1) * stride + px).coerceIn(0, maxIdx)
                                                val left = (yBuf.get(li).toInt() and 0xFF)
                                                val right = (yBuf.get(ri).toInt() and 0xFF)
                                                val up = (yBuf.get(ui).toInt() and 0xFF)
                                                val down = (yBuf.get(di).toInt() and 0xFF)
                                                gx += Math.abs(right - left)
                                                gy += Math.abs(down - up)
                                            }
                                        }
                                        val grad = Math.sqrt((gx * gx + gy * gy).toDouble())
                                        if (grad > 500) {
                                            cornerCandidates.add(mapOf(
                                                "x" to (col.toDouble() / 4.0),
                                                "y" to (row.toDouble() / 4.0),
                                                "gradient" to grad
                                            ))
                                        }
                                    }
                                }
                                img.close()

                                if (cornerCandidates.isNotEmpty()) {
                                    activity.runOnUiThread {
                                        channel.invokeMethod("onCornerCandidates", cornerCandidates)
                                    }
                                }
                            } catch (_: Exception) {}
                        }

                        // Flash Worker: 2초마다 플래시 사이클
                        // 단계: idle → off_captured → torch_on → on_captured → analyze
                        val flashNow = System.currentTimeMillis()
                        if (!flashOn && flashNow - lastFlashMs >= 2000) {
                            // Step 1: OFF 상태 밝기 캡처
                            try {
                                val img = frame.acquireCameraImage()
                                flashGridOff = getGridBrightness(img.planes[0].buffer, img.width, img.height, img.planes[0].rowStride)
                                img.close()
                                flashOn = true
                                flashOnStartMs = flashNow
                                // 토치 ON
                                val cm = activity.getSystemService(android.content.Context.CAMERA_SERVICE) as android.hardware.camera2.CameraManager
                                cm.setTorchMode(cm.cameraIdList[0], true)
                            } catch (_: Exception) {}
                        } else if (flashOn && flashNow - flashOnStartMs >= 150) {
                            try {
                                val img = frame.acquireCameraImage()
                                val gridOn = getGridBrightness(img.planes[0].buffer, img.width, img.height, img.planes[0].rowStride)
                                img.close()
                                flashOn = false
                                lastFlashMs = flashNow
                                val cm = activity.getSystemService(android.content.Context.CAMERA_SERVICE) as android.hardware.camera2.CameraManager
                                cm.setTorchMode(cm.cameraIdList[0], false)

                                if (flashGridOff != null) {
                                    val gridDiff = DoubleArray(16)
                                    for (i in 0 until 16) { gridDiff[i] = Math.abs(gridOn[i] - flashGridOff!![i]) }

                                    val edges = mutableListOf<Map<String, Any>>()
                                    for (row in 0 until 4) {
                                        for (col in 0 until 3) {
                                            val d = Math.abs(gridDiff[row * 4 + col] - gridDiff[row * 4 + col + 1])
                                            if (d > 5.0) edges.add(mapOf("x" to ((col + 1.0) / 4.0), "y" to ((row + 0.5) / 4.0), "strength" to d, "direction" to "vertical"))
                                        }
                                    }
                                    for (row in 0 until 3) {
                                        for (col in 0 until 4) {
                                            val d = Math.abs(gridDiff[row * 4 + col] - gridDiff[(row + 1) * 4 + col])
                                            if (d > 5.0) edges.add(mapOf("x" to ((col + 0.5) / 4.0), "y" to ((row + 1.0) / 4.0), "strength" to d, "direction" to "horizontal"))
                                        }
                                    }
                                    if (edges.isNotEmpty()) {
                                        activity.runOnUiThread { channel.invokeMethod("onFlashEdges", mapOf("edges" to edges, "gridDiff" to gridDiff.toList())) }
                                    }
                                }
                            } catch (_: Exception) {}
                        }

                        Thread.sleep(16)
                    } catch (e: Exception) {
                        android.util.Log.e("ArCorePlugin", "Render error", e)
                    }
                }

                EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                EGL14.eglDestroySurface(eglDisplay, eglSurface)
                EGL14.eglDestroyContext(eglDisplay, eglContext)
                EGL14.eglTerminate(eglDisplay)
            }
            renderThread!!.start()

            return textureEntry!!.id()

        } catch (e: Exception) {
            android.util.Log.e("ArCorePlugin", "AR init failed", e)
            activity.runOnUiThread { channel.invokeMethod("onError", e.message ?: "AR init failed") }
            return -1
        }
    }

    private fun stopAr() {
        running = false
        renderThread?.join(1000)
        session?.pause()
        session?.close()
        session = null
        textureEntry?.release()
        textureEntry = null
    }

    /// 4x4 그리드 영역별 평균 밝기
    private fun getGridBrightness(yBuffer: java.nio.ByteBuffer, width: Int, height: Int, rowStride: Int): DoubleArray {
        val grid = DoubleArray(16)
        val cellW = width / 4
        val cellH = height / 4

        for (row in 0 until 4) {
            for (col in 0 until 4) {
                var sum = 0L
                var count = 0
                val startY = row * cellH
                val startX = col * cellW
                // 셀 내 10x10 샘플링 (성능)
                val stepY = Math.max(cellH / 10, 1)
                val stepX = Math.max(cellW / 10, 1)
                for (y in startY until Math.min(startY + cellH, height) step stepY) {
                    for (x in startX until Math.min(startX + cellW, width) step stepX) {
                        val idx = y * rowStride + x
                        if (idx < yBuffer.limit()) {
                            sum += (yBuffer.get(idx).toInt() and 0xFF)
                            count++
                        }
                    }
                }
                grid[row * 4 + col] = if (count > 0) sum.toDouble() / count else 0.0
            }
        }
        return grid
    }

    fun dispose() = stopAr()
}
