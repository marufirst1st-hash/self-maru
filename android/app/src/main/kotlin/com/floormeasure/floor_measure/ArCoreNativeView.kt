package com.floormeasure.floor_measure

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.opengl.GLSurfaceView
import android.opengl.GLES20
import android.view.MotionEvent
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
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

class ArCoreNativeView(
    private val context: Context,
    private val activity: Activity,
    private val id: Int,
    private val messenger: BinaryMessenger,
) : PlatformView {

    private val channel = MethodChannel(messenger, "com.floormeasure/arcore_$id")
    private val container = FrameLayout(context)
    private var glView: GLSurfaceView? = null
    private var session: Session? = null
    private var installed = false
    private var planeDetected = false
    private var tapX = -1f
    private var tapY = -1f

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "dispose" -> { disposeSession(); result.success(true) }
                else -> result.notImplemented()
            }
        }

        // 카메라 권한 체크 후 시작
        if (hasCameraPermission()) {
            initAr()
        } else {
            requestCameraPermission()
            // 권한 요청 후 잠시 대기 → 재시도
            container.postDelayed({
                if (hasCameraPermission()) {
                    initAr()
                } else {
                    showMessage("카메라 권한이 필요합니다")
                    channel.invokeMethod("onArError", "카메라 권한 거부")
                }
            }, 2000)
        }
    }

    private fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestCameraPermission() {
        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.CAMERA), 1001)
    }

    private fun initAr() {
        try {
            // ARCore 설치 확인
            val availability = ArCoreApk.getInstance().checkAvailability(context)
            if (!availability.isSupported) {
                showMessage("이 기기는 ARCore를 지원하지 않습니다")
                channel.invokeMethod("onArError", "ARCore not supported")
                return
            }

            when (ArCoreApk.getInstance().requestInstall(activity, !installed)) {
                ArCoreApk.InstallStatus.INSTALLED -> { installed = true }
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                    showMessage("Google Play Services for AR 설치 중...")
                    return
                }
            }

            // Session 생성
            session = Session(activity)
            val config = Config(session!!)
            config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
            config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            config.focusMode = Config.FocusMode.AUTO
            session!!.configure(config)

            // GL 뷰 설정
            glView = GLSurfaceView(context).apply {
                preserveEGLContextOnPause = true
                setEGLContextClientVersion(2)
                setRenderer(ArRenderer())
                renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY

                setOnTouchListener { _, event ->
                    if (event.action == MotionEvent.ACTION_DOWN) {
                        tapX = event.x
                        tapY = event.y
                    }
                    true
                }
            }

            container.removeAllViews()
            container.addView(glView)

            session!!.resume()
            channel.invokeMethod("onArSessionCreated", null)

        } catch (e: Exception) {
            showMessage("AR 초기화 실패: ${e.message}")
            channel.invokeMethod("onArError", e.message ?: "AR init failed")
        }
    }

    private fun showMessage(msg: String) {
        container.removeAllViews()
        val tv = TextView(context).apply {
            text = msg
            setTextColor(Color.WHITE)
            textSize = 16f
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0A0E1A"))
        }
        container.addView(tv)
    }

    private fun handleTap(frame: Frame) {
        if (tapX < 0) return
        val x = tapX
        val y = tapY
        tapX = -1f
        tapY = -1f

        try {
            val hits = frame.hitTest(x, y)
            for (hit in hits) {
                val trackable = hit.trackable
                if (trackable is Plane && trackable.isPoseInPolygon(hit.hitPose)) {
                    val pose = hit.hitPose
                    val data = mapOf(
                        "x" to pose.tx().toDouble(),
                        "y" to pose.ty().toDouble(),
                        "z" to pose.tz().toDouble(),
                        "distance" to hit.distance.toDouble(),
                    )
                    activity.runOnUiThread {
                        channel.invokeMethod("onPlaneTap", data)
                    }
                    break
                }
            }
        } catch (_: Exception) {}
    }

    private inner class ArRenderer : GLSurfaceView.Renderer {
        private var backgroundTexture = 0

        override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
            GLES20.glClearColor(0.1f, 0.1f, 0.1f, 1.0f)

            // 카메라 배경 텍스처 생성
            val textures = IntArray(1)
            GLES20.glGenTextures(1, textures, 0)
            backgroundTexture = textures[0]
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, backgroundTexture)

            try {
                session?.setCameraTextureName(backgroundTexture)
            } catch (_: Exception) {}
        }

        override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
            GLES20.glViewport(0, 0, width, height)
            val display = activity.windowManager.defaultDisplay
            session?.setDisplayGeometry(display.rotation, width, height)
        }

        override fun onDrawFrame(gl: GL10?) {
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

            val s = session ?: return

            try {
                val frame = s.update()
                val camera = frame.camera

                // 탭 처리
                handleTap(frame)

                // 평면 감지 알림
                if (!planeDetected) {
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

                // 카메라 포즈
                if (camera.trackingState == TrackingState.TRACKING) {
                    val pose = camera.pose
                    activity.runOnUiThread {
                        channel.invokeMethod("onCameraPose", mapOf(
                            "x" to pose.tx().toDouble(),
                            "y" to pose.ty().toDouble(),
                            "z" to pose.tz().toDouble(),
                        ))
                    }
                }
            } catch (_: Exception) {}
        }
    }

    private fun disposeSession() {
        glView?.onPause()
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
