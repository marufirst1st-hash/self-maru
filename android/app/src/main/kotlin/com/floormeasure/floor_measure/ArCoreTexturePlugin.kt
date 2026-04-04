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
    private var lastHitTestMs = 0L
    // 누적된 벽/바닥 hit 점 (월드 좌표)
    private val wallPaintPoints = mutableListOf<FloatArray>() // [x,y,z]
    private val floorPaintPoints = mutableListOf<FloatArray>() // [x,y,z]
    // RANSAC으로 찾은 3D 벽 면 (GL quad로 렌더링)
    // 각 벽: [x1,y1,z1, x2,y2,z2, x3,y3,z3, x4,y4,z4] (4꼭지점)
    private val wallQuads = mutableListOf<FloatArray>()
    private var lastRansacMs = 0L
    private var floorY = 0f // 바닥 높이

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

                // === 카메라 셰이더 ===
                val vs = "attribute vec4 a_P; attribute vec2 a_T; varying vec2 v_T; void main(){gl_Position=a_P; v_T=a_T;}"
                val fs = "#extension GL_OES_EGL_image_external : require\nprecision mediump float; varying vec2 v_T; uniform samplerExternalOES u_Tex; void main(){gl_FragColor=texture2D(u_Tex,v_T);}"
                val vsh = GLES20.glCreateShader(GLES20.GL_VERTEX_SHADER); GLES20.glShaderSource(vsh, vs); GLES20.glCompileShader(vsh)
                val fsh = GLES20.glCreateShader(GLES20.GL_FRAGMENT_SHADER); GLES20.glShaderSource(fsh, fs); GLES20.glCompileShader(fsh)
                val prog = GLES20.glCreateProgram(); GLES20.glAttachShader(prog, vsh); GLES20.glAttachShader(prog, fsh); GLES20.glLinkProgram(prog)

                // === 오버레이 셰이더 (구글 PlaneRenderer 방식) ===
                // 로컬 좌표(x,z,alpha) → model*view*proj 변환, alpha로 가장자리 페이딩
                val ovVs = """
                    attribute vec3 a_XZAlpha;
                    uniform mat4 u_ModelViewProjection;
                    varying float v_Alpha;
                    void main(){
                        vec4 pos = vec4(a_XZAlpha.x, 0.0, a_XZAlpha.y, 1.0);
                        v_Alpha = a_XZAlpha.z;
                        gl_Position = u_ModelViewProjection * pos;
                    }
                """.trimIndent()
                val ovFs = """
                    precision mediump float;
                    uniform vec4 u_Color;
                    varying float v_Alpha;
                    void main(){
                        gl_FragColor = vec4(u_Color.rgb, u_Color.a * v_Alpha);
                    }
                """.trimIndent()
                val ovVsh = GLES20.glCreateShader(GLES20.GL_VERTEX_SHADER); GLES20.glShaderSource(ovVsh, ovVs); GLES20.glCompileShader(ovVsh)
                val ovFsh = GLES20.glCreateShader(GLES20.GL_FRAGMENT_SHADER); GLES20.glShaderSource(ovFsh, ovFs); GLES20.glCompileShader(ovFsh)
                val ovProg = GLES20.glCreateProgram(); GLES20.glAttachShader(ovProg, ovVsh); GLES20.glAttachShader(ovProg, ovFsh); GLES20.glLinkProgram(ovProg)
                val ovPosLoc = GLES20.glGetAttribLocation(ovProg, "a_XZAlpha")
                val ovMvpLoc = GLES20.glGetUniformLocation(ovProg, "u_ModelViewProjection")
                val ovColorLoc = GLES20.glGetUniformLocation(ovProg, "u_Color")
                val FADE_RADIUS = 0.25f

                // === 3D 점 셰이더 (누적 hitTest 색칠용, 월드 좌표 직접) ===
                val ptVs = "attribute vec3 a_Pos; uniform mat4 u_VP; void main(){gl_Position = u_VP * vec4(a_Pos, 1.0);}"
                val ptFs = "precision mediump float; uniform vec4 u_Color; void main(){gl_FragColor = u_Color;}"
                val ptVsh = GLES20.glCreateShader(GLES20.GL_VERTEX_SHADER); GLES20.glShaderSource(ptVsh, ptVs); GLES20.glCompileShader(ptVsh)
                val ptFsh = GLES20.glCreateShader(GLES20.GL_FRAGMENT_SHADER); GLES20.glShaderSource(ptFsh, ptFs); GLES20.glCompileShader(ptFsh)
                val ptProg = GLES20.glCreateProgram(); GLES20.glAttachShader(ptProg, ptVsh); GLES20.glAttachShader(ptProg, ptFsh); GLES20.glLinkProgram(ptProg)
                val ptPosLoc = GLES20.glGetAttribLocation(ptProg, "a_Pos")
                val ptVpLoc = GLES20.glGetUniformLocation(ptProg, "u_VP")
                val ptColorLoc = GLES20.glGetUniformLocation(ptProg, "u_Color")

                val quadV = floatArrayOf(-1f,-1f, -1f,1f, 1f,-1f, 1f,1f)
                val quadT = floatArrayOf(0f,1f, 0f,0f, 1f,1f, 1f,0f)

                fun buf(a: FloatArray): FloatBuffer = ByteBuffer.allocateDirect(a.size*4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(a); position(0) }

                // MVP 행렬 곱셈 (4x4 column-major)
                fun multiplyMM(a: FloatArray, b: FloatArray): FloatArray {
                    val r = FloatArray(16)
                    android.opengl.Matrix.multiplyMM(r, 0, a, 0, b, 0)
                    return r
                }

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

                        // === 오버레이: 구글 PlaneRenderer 방식으로 바닥/벽 색칠 ===
                        val cam = frame.camera
                        if (cam.trackingState == TrackingState.TRACKING) {
                            val viewMat = FloatArray(16)
                            val projMat = FloatArray(16)
                            cam.getViewMatrix(viewMat, 0)
                            cam.getProjectionMatrix(projMat, 0, 0.05f, 50.0f)

                            GLES20.glUseProgram(ovProg)
                            GLES20.glEnable(GLES20.GL_BLEND)
                            GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
                            GLES20.glDepthMask(false)

                            for (plane in s.getAllTrackables(Plane::class.java)) {
                                if (plane.trackingState != TrackingState.TRACKING) continue
                                if (plane.subsumedBy != null) continue

                                val boundary = plane.polygon
                                boundary.rewind()
                                val numPts = boundary.limit() / 2
                                if (numPts < 3) continue

                                val isFloor = plane.type == Plane.Type.HORIZONTAL_UPWARD_FACING
                                val isWall = plane.type == Plane.Type.VERTICAL
                                if (!isFloor && !isWall) continue

                                // 색상
                                if (isFloor) {
                                    GLES20.glUniform4f(ovColorLoc, 0.4f, 0.8f, 0.4f, 0.25f)
                                } else {
                                    GLES20.glUniform4f(ovColorLoc, 0.27f, 0.54f, 1.0f, 0.20f)
                                }

                                // Model matrix = plane의 centerPose (구글 방식)
                                val modelMat = FloatArray(16)
                                plane.centerPose.toMatrix(modelMat, 0)
                                // MVP = proj * view * model
                                val mvMat = multiplyMM(viewMat, modelMat)
                                val mvpMat = multiplyMM(projMat, mvMat)
                                GLES20.glUniformMatrix4fv(ovMvpLoc, 1, false, mvpMat, 0)

                                // 구글 방식: boundary 폴리곤 복제 + 안쪽 축소 → 페이딩 엣지
                                val xScale = Math.max((plane.extentX - 2*FADE_RADIUS) / plane.extentX, 0f)
                                val zScale = Math.max((plane.extentZ - 2*FADE_RADIUS) / plane.extentZ, 0f)

                                // 정점 버퍼: 각 boundary 점마다 2개 (바깥 alpha=0, 안쪽 alpha=1)
                                val verts = FloatArray(numPts * 2 * 3) // (x, z, alpha) * 2 per point
                                boundary.rewind()
                                for (i in 0 until numPts) {
                                    val x = boundary.get()
                                    val z = boundary.get()
                                    // 바깥 (원래 위치, alpha=0)
                                    verts[i*6]   = x;  verts[i*6+1] = z;  verts[i*6+2] = 0f
                                    // 안쪽 (축소, alpha=1)
                                    verts[i*6+3] = x*xScale; verts[i*6+4] = z*zScale; verts[i*6+5] = 1f
                                }

                                // 인덱스: TRIANGLE_STRIP - perimeter + interior
                                val numIdx = numPts * 3
                                val indices = ShortArray(numIdx)
                                var idx = 0
                                // perimeter
                                indices[idx++] = ((numPts-1)*2).toShort()
                                for (i in 0 until numPts) {
                                    indices[idx++] = (i*2).toShort()
                                    indices[idx++] = (i*2+1).toShort()
                                }

                                val vertBuf = buf(verts)
                                val idxBuf = ByteBuffer.allocateDirect(idx*2).order(ByteOrder.nativeOrder()).asShortBuffer()
                                idxBuf.put(indices, 0, idx); idxBuf.position(0)

                                GLES20.glEnableVertexAttribArray(ovPosLoc)
                                GLES20.glVertexAttribPointer(ovPosLoc, 3, GLES20.GL_FLOAT, false, 0, vertBuf)
                                GLES20.glDrawElements(GLES20.GL_TRIANGLE_STRIP, idx, GLES20.GL_UNSIGNED_SHORT, idxBuf)
                                GLES20.glDisableVertexAttribArray(ovPosLoc)
                            }

                            // === 3D 벽/바닥 면 렌더링 (월드 좌표 고정) ===
                            GLES20.glUseProgram(ptProg)
                            val vpMat = multiplyMM(projMat, viewMat)
                            GLES20.glUniformMatrix4fv(ptVpLoc, 1, false, vpMat, 0)

                            // 벽 quad (RANSAC으로 생성된 3D 사각형)
                            for (quad in wallQuads) {
                                if (quad.size < 12) continue
                                // 파란 반투명 벽면
                                GLES20.glUniform4f(ptColorLoc, 0.2f, 0.4f, 0.9f, 0.25f)
                                // 2 triangles: (0,1,2), (0,2,3)
                                val triVerts = floatArrayOf(
                                    quad[0],quad[1],quad[2], quad[3],quad[4],quad[5], quad[6],quad[7],quad[8],
                                    quad[0],quad[1],quad[2], quad[6],quad[7],quad[8], quad[9],quad[10],quad[11],
                                )
                                val vb = buf(triVerts)
                                GLES20.glEnableVertexAttribArray(ptPosLoc)
                                GLES20.glVertexAttribPointer(ptPosLoc, 3, GLES20.GL_FLOAT, false, 0, vb)
                                GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, 6)

                                // 벽 외곽선 (좀 더 진하게)
                                GLES20.glUniform4f(ptColorLoc, 0.2f, 0.5f, 1.0f, 0.6f)
                                val edgeVerts = buf(quad)
                                GLES20.glVertexAttribPointer(ptPosLoc, 3, GLES20.GL_FLOAT, false, 0, edgeVerts)
                                GLES20.glLineWidth(2.0f)
                                GLES20.glDrawArrays(GLES20.GL_LINE_LOOP, 0, 4)
                                GLES20.glDisableVertexAttribArray(ptPosLoc)
                            }

                            // 바닥 hit 점 (초록 수평 사각형, 작게)
                            if (floorPaintPoints.isNotEmpty()) {
                                GLES20.glUniform4f(ptColorLoc, 0.3f, 0.9f, 0.3f, 0.3f)
                                val size = 0.03f
                                val maxPts = Math.min(floorPaintPoints.size, 200)
                                val verts = FloatArray(maxPts * 6 * 3)
                                for (idx in 0 until maxPts) {
                                    val pt = floorPaintPoints[idx]
                                    val x = pt[0]; val y = pt[1]; val z = pt[2]
                                    val i = idx * 18
                                    verts[i]=x-size; verts[i+1]=y; verts[i+2]=z-size
                                    verts[i+3]=x+size; verts[i+4]=y; verts[i+5]=z-size
                                    verts[i+6]=x-size; verts[i+7]=y; verts[i+8]=z+size
                                    verts[i+9]=x+size; verts[i+10]=y; verts[i+11]=z-size
                                    verts[i+12]=x+size; verts[i+13]=y; verts[i+14]=z+size
                                    verts[i+15]=x-size; verts[i+16]=y; verts[i+17]=z+size
                                }
                                val vb = buf(verts)
                                GLES20.glEnableVertexAttribArray(ptPosLoc)
                                GLES20.glVertexAttribPointer(ptPosLoc, 3, GLES20.GL_FLOAT, false, 0, vb)
                                GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, maxPts * 6)
                                GLES20.glDisableVertexAttribArray(ptPosLoc)
                            }

                            // 벽 hit 점도 작게 표시 (스캔 진행 상태 보여줌)
                            if (wallPaintPoints.isNotEmpty()) {
                                GLES20.glUniform4f(ptColorLoc, 0.3f, 0.5f, 1.0f, 0.5f)
                                val size = 0.02f
                                val maxPts = Math.min(wallPaintPoints.size, 300)
                                val verts = FloatArray(maxPts * 6 * 3)
                                for (idx in 0 until maxPts) {
                                    val pt = wallPaintPoints[idx]
                                    val x = pt[0]; val y = pt[1]; val z = pt[2]
                                    val i = idx * 18
                                    // 카메라를 향하는 수직 사각형
                                    verts[i]=x-size; verts[i+1]=y-size; verts[i+2]=z
                                    verts[i+3]=x+size; verts[i+4]=y-size; verts[i+5]=z
                                    verts[i+6]=x-size; verts[i+7]=y+size; verts[i+8]=z
                                    verts[i+9]=x+size; verts[i+10]=y-size; verts[i+11]=z
                                    verts[i+12]=x+size; verts[i+13]=y+size; verts[i+14]=z
                                    verts[i+15]=x-size; verts[i+16]=y+size; verts[i+17]=z
                                }
                                val vb = buf(verts)
                                GLES20.glEnableVertexAttribArray(ptPosLoc)
                                GLES20.glVertexAttribPointer(ptPosLoc, 3, GLES20.GL_FLOAT, false, 0, vb)
                                GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, maxPts * 6)
                                GLES20.glDisableVertexAttribArray(ptPosLoc)
                            }

                            GLES20.glDepthMask(true)
                            GLES20.glDisable(GLES20.GL_BLEND)
                        }

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

                        // 연속 hitTest: 화면 중앙의 3D 좌표 (200ms 간격)
                        // hit 좌표를 누적 → GL에서 색칠 (AR 앵커처럼 월드 고정)
                        val now = System.currentTimeMillis()
                        if (now - lastHitTestMs >= 200 && cam.trackingState == TrackingState.TRACKING) {
                            lastHitTestMs = now
                            val centerX = viewWidth / 2f
                            val centerY = viewHeight / 2f
                            val hits = frame.hitTest(centerX, centerY)
                            for (hit in hits) {
                                if (hit.trackable is Plane) {
                                    val plane = hit.trackable as Plane
                                    val p = hit.hitPose
                                    val pt = floatArrayOf(p.tx(), p.ty(), p.tz())
                                    val type = when (plane.type) {
                                        Plane.Type.VERTICAL -> "wall"
                                        Plane.Type.HORIZONTAL_UPWARD_FACING -> "floor"
                                        else -> "other"
                                    }

                                    // 누적 저장 (같은 위치 0.05m 이내면 스킵)
                                    val targetList = if (type == "wall") wallPaintPoints else if (type == "floor") floorPaintPoints else null
                                    if (targetList != null) {
                                        val isDup = targetList.any { prev ->
                                            val dx = prev[0] - pt[0]; val dy = prev[1] - pt[1]; val dz = prev[2] - pt[2]
                                            dx*dx + dy*dy + dz*dz < 0.0025f // 0.05m
                                        }
                                        if (!isDup && targetList.size < 500) {
                                            targetList.add(pt)
                                        }
                                    }

                                    activity.runOnUiThread {
                                        channel.invokeMethod("onCenterHit", mapOf(
                                            "x" to p.tx().toDouble(),
                                            "y" to p.ty().toDouble(),
                                            "z" to p.tz().toDouble(),
                                            "distance" to hit.distance.toDouble(),
                                            "type" to type,
                                        ))
                                    }
                                    break
                                }
                            }
                        }

                        // 2초마다 벽 점으로 RANSAC → 3D 벽 quad 생성
                        if (now - lastRansacMs >= 2000 && wallPaintPoints.size >= 6) {
                            lastRansacMs = now
                            // 바닥 높이 추정
                            if (floorPaintPoints.isNotEmpty()) {
                                floorY = floorPaintPoints.map { it[1] }.average().toFloat()
                            }
                            buildWallQuads()
                        }

                        // 500ms마다 평면 전송 (성능)
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

                        // 카메라 포즈 + view/projection 행렬 (AR 면 투영용)
                        val camera = frame.camera
                        if (camera.trackingState == TrackingState.TRACKING) {
                            val cp = camera.pose
                            val viewMat = FloatArray(16)
                            val projMat = FloatArray(16)
                            camera.getViewMatrix(viewMat, 0)
                            camera.getProjectionMatrix(projMat, 0, 0.05f, 50.0f)
                            activity.runOnUiThread {
                                channel.invokeMethod("onCameraPose", mapOf(
                                    "x" to cp.tx().toDouble(),
                                    "y" to cp.ty().toDouble(),
                                    "z" to cp.tz().toDouble(),
                                    "viewMatrix" to viewMat.map { it.toDouble() },
                                    "projMatrix" to projMat.map { it.toDouble() },
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
                        val flashNow = System.currentTimeMillis()
                        if (!flashOn && flashNow - lastFlashMs >= 2000) {
                            try {
                                val img = frame.acquireCameraImage()
                                flashGridOff = getGridBrightness(img.planes[0].buffer, img.width, img.height, img.planes[0].rowStride)
                                img.close()
                                flashOn = true
                                flashOnStartMs = flashNow
                                // ARCore Config.FlashMode로 토치 ON
                                try {
                                    val cfg = s.config
                                    cfg.flashMode = Config.FlashMode.TORCH
                                    s.configure(cfg)
                                } catch (_: Exception) {}
                                android.util.Log.d("ArCorePlugin", "Flash: torch ON")
                            } catch (e: Exception) { android.util.Log.e("ArCorePlugin", "Flash OFF err: ${e.message}") }
                        } else if (flashOn && flashNow - flashOnStartMs >= 150) {
                            try {
                                val img = frame.acquireCameraImage()
                                val gridOn = getGridBrightness(img.planes[0].buffer, img.width, img.height, img.planes[0].rowStride)
                                img.close()
                                flashOn = false
                                lastFlashMs = flashNow
                                // ARCore Config.FlashMode로 토치 OFF
                                try {
                                    val cfg = s.config
                                    cfg.flashMode = Config.FlashMode.OFF
                                    s.configure(cfg)
                                } catch (_: Exception) {}

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
                                    android.util.Log.d("ArCorePlugin", "Flash: edges=${edges.size} maxDiff=${gridDiff.max()}")
                                    if (edges.isNotEmpty()) {
                                        activity.runOnUiThread { channel.invokeMethod("onFlashEdges", mapOf("edges" to edges, "gridDiff" to gridDiff.toList())) }
                                    }
                                }
                            } catch (e: Exception) { android.util.Log.e("ArCorePlugin", "Flash ON err: ${e.message}") }
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

    /// 벽 점군 → RANSAC → 3D 벽 quad
    /// XZ 평면에서 직선(벽) 찾고, 바닥~천장 높이로 수직 quad 생성
    private fun buildWallQuads() {
        if (wallPaintPoints.size < 6) return

        wallQuads.clear()
        val ceilY = floorY + 2.5f // 천장 높이 추정 (바닥 + 2.5m)
        val remaining = wallPaintPoints.toMutableList()
        val rng = java.util.Random(42)

        // 간이 RANSAC: XZ 평면에서 직선 피팅
        while (remaining.size >= 4) {
            var bestA = 0f; var bestB = 0f; var bestC = 0f
            var bestInliers = mutableListOf<FloatArray>()

            for (iter in 0 until 100) {
                val i1 = rng.nextInt(remaining.size)
                var i2 = rng.nextInt(remaining.size)
                while (i2 == i1) i2 = rng.nextInt(remaining.size)

                val p1 = remaining[i1]; val p2 = remaining[i2]
                val dx = p2[0] - p1[0]; val dz = p2[2] - p1[2]
                val len = Math.sqrt((dx * dx + dz * dz).toDouble()).toFloat()
                if (len < 0.1f) continue

                val a = dz / len; val b = -dx / len
                val c = -(a * p1[0] + b * p1[2])

                val inliers = remaining.filter { pt ->
                    Math.abs(a * pt[0] + b * pt[2] + c) < 0.08f
                }.toMutableList()

                if (inliers.size > bestInliers.size) {
                    bestInliers = inliers; bestA = a; bestB = b; bestC = c
                }
            }

            if (bestInliers.size < 4) break

            // inlier 점들의 범위로 벽 quad 생성
            // 벽 방향 = 직선 방향 (법선에 수직)
            val dirX = -bestB; val dirZ = bestA // 벽 방향
            var minT = Float.MAX_VALUE; var maxT = -Float.MAX_VALUE
            val refX = bestInliers[0][0]; val refZ = bestInliers[0][2]

            for (pt in bestInliers) {
                val t = (pt[0] - refX) * dirX + (pt[2] - refZ) * dirZ
                if (t < minT) minT = t
                if (t > maxT) maxT = t
            }

            // 벽 양 끝점 (바닥 높이)
            val x1 = refX + dirX * minT; val z1 = refZ + dirZ * minT
            val x2 = refX + dirX * maxT; val z2 = refZ + dirZ * maxT

            // 4꼭지점 quad (반시계: 좌하, 우하, 우상, 좌상)
            wallQuads.add(floatArrayOf(
                x1, floorY, z1,    // 좌하
                x2, floorY, z2,    // 우하
                x2, ceilY, z2,     // 우상
                x1, ceilY, z1,     // 좌상
            ))

            // inlier 제거
            val inlierSet = bestInliers.toSet()
            remaining.removeAll(inlierSet)
        }

        android.util.Log.d("ArCorePlugin", "RANSAC: ${wallPaintPoints.size}pts → ${wallQuads.size} wall quads")
    }

    fun dispose() = stopAr()
}
