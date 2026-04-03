package com.floormeasure.floor_measure

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.SurfaceTexture
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.view.MotionEvent
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import android.graphics.Color
import android.view.Gravity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.ar.core.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.*
import javax.microedition.khronos.opengles.GL10
import android.opengl.EGL14

class ArCoreNativeView(
    private val context: Context,
    private val activity: Activity,
    private val id: Int,
    private val messenger: BinaryMessenger,
) : PlatformView {

    private val channel = MethodChannel(messenger, "com.floormeasure/arcore_$id")
    private val container = FrameLayout(context)
    private var session: Session? = null
    private var installed = false
    private var planeDetected = false
    private var tapX = -1f
    private var tapY = -1f

    // TextureView + 별도 GL 스레드
    private var textureView: TextureView? = null
    private var renderThread: RenderThread? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "dispose" -> { disposeSession(); result.success(true) }
                else -> result.notImplemented()
            }
        }

        if (hasCameraPermission()) {
            initAr()
        } else {
            requestCameraPermission()
            container.postDelayed({
                if (hasCameraPermission()) initAr()
                else {
                    showMessage("카메라 권한이 필요합니다")
                    channel.invokeMethod("onArError", "카메라 권한 거부")
                }
            }, 2000)
        }
    }

    private fun hasCameraPermission() =
        ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    private fun requestCameraPermission() =
        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.CAMERA), 1001)

    private fun initAr() {
        try {
            val availability = ArCoreApk.getInstance().checkAvailability(context)
            if (!availability.isSupported) {
                showMessage("ARCore 미지원 기기")
                channel.invokeMethod("onArError", "ARCore not supported")
                return
            }

            when (ArCoreApk.getInstance().requestInstall(activity, !installed)) {
                ArCoreApk.InstallStatus.INSTALLED -> installed = true
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                    showMessage("Google Play Services for AR 설치 중...")
                    return
                }
            }

            session = Session(activity)
            val config = Config(session!!)
            config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
            config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            config.focusMode = Config.FocusMode.AUTO
            session!!.configure(config)

            // TextureView 기반 렌더링
            textureView = TextureView(context)
            textureView!!.isOpaque = false
            textureView!!.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) {
                    renderThread = RenderThread(st, w, h)
                    renderThread!!.start()
                }
                override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) {
                    renderThread?.updateSize(w, h)
                }
                override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
                    renderThread?.stopRendering()
                    return true
                }
                override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
            }

            textureView!!.setOnTouchListener { _, event ->
                if (event.action == MotionEvent.ACTION_DOWN) {
                    tapX = event.x; tapY = event.y
                }
                true
            }

            container.removeAllViews()
            container.addView(textureView)

            session!!.resume()
            channel.invokeMethod("onArSessionCreated", null)

        } catch (e: Exception) {
            showMessage("AR 오류: ${e.message}")
            channel.invokeMethod("onArError", e.message ?: "AR init failed")
        }
    }

    private fun showMessage(msg: String) {
        container.removeAllViews()
        container.addView(TextView(context).apply {
            text = msg; setTextColor(Color.WHITE); textSize = 16f
            gravity = Gravity.CENTER; setBackgroundColor(Color.parseColor("#0A0E1A"))
        })
    }

    /**
     * 별도 GL 스레드 - TextureView의 Surface에 ARCore 카메라를 렌더링
     */
    private inner class RenderThread(
        private val surfaceTexture: SurfaceTexture,
        private var width: Int,
        private var height: Int,
    ) : Thread("ArRenderThread") {

        @Volatile private var running = true
        private var cameraTextureId = -1

        // GL 리소스
        private var eglDisplay: javax.microedition.khronos.egl.EGLDisplay? = null
        private var eglSurface: javax.microedition.khronos.egl.EGLSurface? = null
        private var eglContext: javax.microedition.khronos.egl.EGLContext? = null
        private var program = 0

        private val QUAD_COORDS = floatArrayOf(-1f, -1f, -1f, 1f, 1f, -1f, 1f, 1f)
        private val QUAD_TEXCOORDS = floatArrayOf(0f, 1f, 0f, 0f, 1f, 1f, 1f, 0f)

        private val VS = """
            attribute vec4 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() { gl_Position = a_Position; v_TexCoord = a_TexCoord; }
        """.trimIndent()

        private val FS = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_TexCoord;
            uniform samplerExternalOES u_Texture;
            void main() { gl_FragColor = texture2D(u_Texture, v_TexCoord); }
        """.trimIndent()

        fun updateSize(w: Int, h: Int) { width = w; height = h }
        fun stopRendering() { running = false }

        override fun run() {
            initEgl()
            initGl()

            session?.setCameraTextureName(cameraTextureId)

            while (running) {
                try {
                    val s = session ?: break
                    val frame = s.update()

                    // 카메라 렌더링
                    GLES20.glViewport(0, 0, width, height)
                    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

                    val display = activity.windowManager.defaultDisplay
                    s.setDisplayGeometry(display.rotation, width, height)

                    drawCamera(frame)
                    handleTap(frame)
                    checkPlanes(s)
                    sendCameraPose(frame)

                    val egl = (javax.microedition.khronos.egl.EGLContext.getEGL() as EGL10)
                    egl.eglSwapBuffers(eglDisplay, eglSurface)

                    sleep(16) // ~60fps
                } catch (_: Exception) {}
            }

            cleanupEgl()
        }

        private fun drawCamera(frame: Frame) {
            GLES20.glDepthMask(false)
            GLES20.glUseProgram(program)

            val posLoc = GLES20.glGetAttribLocation(program, "a_Position")
            val texLoc = GLES20.glGetAttribLocation(program, "a_TexCoord")

            val vertBuf = makeBuf(QUAD_COORDS)
            val texBuf = makeBuf(QUAD_TEXCOORDS)

            // ARCore UV 변환
            val transformed = FloatArray(8)
            frame.transformDisplayUvCoords(texBuf, FloatBuffer.wrap(transformed))
            val uvBuf = makeBuf(transformed)

            GLES20.glEnableVertexAttribArray(posLoc)
            GLES20.glEnableVertexAttribArray(texLoc)
            GLES20.glVertexAttribPointer(posLoc, 2, GLES20.GL_FLOAT, false, 0, vertBuf)
            GLES20.glVertexAttribPointer(texLoc, 2, GLES20.GL_FLOAT, false, 0, uvBuf)

            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

            GLES20.glDisableVertexAttribArray(posLoc)
            GLES20.glDisableVertexAttribArray(texLoc)
            GLES20.glDepthMask(true)
        }

        private fun handleTap(frame: Frame) {
            if (tapX < 0) return
            val x = tapX; val y = tapY; tapX = -1f; tapY = -1f
            try {
                for (hit in frame.hitTest(x, y)) {
                    val trackable = hit.trackable
                    if (trackable is Plane && trackable.isPoseInPolygon(hit.hitPose)) {
                        val pose = hit.hitPose
                        activity.runOnUiThread {
                            channel.invokeMethod("onPlaneTap", mapOf(
                                "x" to pose.tx().toDouble(), "y" to pose.ty().toDouble(),
                                "z" to pose.tz().toDouble(), "distance" to hit.distance.toDouble(),
                            ))
                        }
                        break
                    }
                }
            } catch (_: Exception) {}
        }

        private fun checkPlanes(s: Session) {
            if (planeDetected) return
            for (plane in s.getAllTrackables(Plane::class.java)) {
                if (plane.trackingState == TrackingState.TRACKING) {
                    planeDetected = true
                    activity.runOnUiThread {
                        channel.invokeMethod("onPlaneDetected", mapOf(
                            "centerX" to plane.centerPose.tx().toDouble(),
                            "centerY" to plane.centerPose.ty().toDouble(),
                            "centerZ" to plane.centerPose.tz().toDouble(),
                        ))
                    }
                    break
                }
            }
        }

        private fun sendCameraPose(frame: Frame) {
            val camera = frame.camera
            if (camera.trackingState == TrackingState.TRACKING) {
                val pose = camera.pose
                activity.runOnUiThread {
                    channel.invokeMethod("onCameraPose", mapOf(
                        "x" to pose.tx().toDouble(), "y" to pose.ty().toDouble(), "z" to pose.tz().toDouble(),
                    ))
                }
            }
        }

        private fun initEgl() {
            val egl = javax.microedition.khronos.egl.EGLContext.getEGL() as EGL10
            eglDisplay = egl.eglGetDisplay(EGL10.EGL_DEFAULT_DISPLAY)
            egl.eglInitialize(eglDisplay, IntArray(2))

            val configAttribs = intArrayOf(
                EGL10.EGL_RENDERABLE_TYPE, 4, // EGL_OPENGL_ES2_BIT
                EGL10.EGL_RED_SIZE, 8, EGL10.EGL_GREEN_SIZE, 8,
                EGL10.EGL_BLUE_SIZE, 8, EGL10.EGL_ALPHA_SIZE, 8,
                EGL10.EGL_DEPTH_SIZE, 16, EGL10.EGL_NONE,
            )
            val configs = arrayOfNulls<javax.microedition.khronos.egl.EGLConfig>(1)
            egl.eglChooseConfig(eglDisplay, configAttribs, configs, 1, IntArray(1))

            val contextAttribs = intArrayOf(0x3098, 2, EGL10.EGL_NONE) // EGL_CONTEXT_CLIENT_VERSION
            eglContext = egl.eglCreateContext(eglDisplay, configs[0], EGL10.EGL_NO_CONTEXT, contextAttribs)
            eglSurface = egl.eglCreateWindowSurface(eglDisplay, configs[0], surfaceTexture, null)
            egl.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)
        }

        private fun initGl() {
            val textures = IntArray(1)
            GLES20.glGenTextures(1, textures, 0)
            cameraTextureId = textures[0]
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)

            val vs = loadShader(GLES20.GL_VERTEX_SHADER, VS)
            val fs = loadShader(GLES20.GL_FRAGMENT_SHADER, FS)
            program = GLES20.glCreateProgram()
            GLES20.glAttachShader(program, vs); GLES20.glAttachShader(program, fs)
            GLES20.glLinkProgram(program)
        }

        private fun cleanupEgl() {
            val egl = javax.microedition.khronos.egl.EGLContext.getEGL() as EGL10
            egl.eglMakeCurrent(eglDisplay, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_CONTEXT)
            egl.eglDestroySurface(eglDisplay, eglSurface)
            egl.eglDestroyContext(eglDisplay, eglContext)
            egl.eglTerminate(eglDisplay)
        }

        private fun loadShader(type: Int, src: String): Int {
            val s = GLES20.glCreateShader(type); GLES20.glShaderSource(s, src); GLES20.glCompileShader(s); return s
        }

        private fun makeBuf(arr: FloatArray): FloatBuffer =
            ByteBuffer.allocateDirect(arr.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(arr); position(0) }
    }

    private fun disposeSession() {
        renderThread?.stopRendering()
        session?.pause()
        session?.close()
        session = null
    }

    override fun getView(): View = container
    override fun dispose() { disposeSession() }
}

class ArCoreViewFactory(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return ArCoreNativeView(context, activity, viewId, messenger)
    }
}
