package com.floormeasure.floor_measure

import android.app.Activity
import android.content.Context
import android.opengl.GLSurfaceView
import android.view.MotionEvent
import android.view.View
import com.google.ar.core.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import android.opengl.GLES20

/**
 * ARCore PlatformView - Sceneform 없이 직접 ARCore Session 사용
 * 카메라 프리뷰 + 평면 감지 + 탭 히트 테스트
 */
class ArCoreNativeView(
    private val context: Context,
    private val activity: Activity,
    private val id: Int,
    private val messenger: BinaryMessenger,
) : PlatformView, GLSurfaceView.Renderer {

    private val channel = MethodChannel(messenger, "com.floormeasure/arcore_$id")
    private var session: Session? = null
    private val glSurfaceView = GLSurfaceView(context)
    private var displayRotationHelper: DisplayRotationHelper? = null
    private var installed = false
    private var planeDetected = false

    init {
        glSurfaceView.preserveEGLContextOnPause = true
        glSurfaceView.setEGLContextClientVersion(2)
        glSurfaceView.setRenderer(this)
        glSurfaceView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY

        // 탭 이벤트
        glSurfaceView.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_DOWN) {
                handleTap(event.x, event.y)
            }
            true
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    initArSession()
                    result.success(true)
                }
                "resume" -> {
                    resumeSession()
                    result.success(true)
                }
                "pause" -> {
                    pauseSession()
                    result.success(true)
                }
                "dispose" -> {
                    disposeSession()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 자동 초기화
        initArSession()
    }

    private fun initArSession() {
        try {
            // ARCore 설치 확인
            when (ArCoreApk.getInstance().requestInstall(activity, !installed)) {
                ArCoreApk.InstallStatus.INSTALLED -> { installed = true }
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                    installed = false
                    return
                }
            }

            session = Session(context)
            val config = Config(session!!)
            config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
            config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            config.focusMode = Config.FocusMode.AUTO
            session!!.configure(config)

            displayRotationHelper = DisplayRotationHelper(context)
            resumeSession()

            channel.invokeMethod("onArSessionCreated", null)
        } catch (e: Exception) {
            channel.invokeMethod("onArError", e.message ?: "AR init failed")
        }
    }

    private fun resumeSession() {
        try {
            session?.resume()
            glSurfaceView.onResume()
            displayRotationHelper?.onResume()
        } catch (e: Exception) {
            channel.invokeMethod("onArError", e.message)
        }
    }

    private fun pauseSession() {
        glSurfaceView.onPause()
        session?.pause()
        displayRotationHelper?.onPause()
    }

    private fun disposeSession() {
        session?.close()
        session = null
    }

    private fun handleTap(x: Float, y: Float) {
        val frame = session?.update() ?: return

        val hitResults = frame.hitTest(x, y)
        for (hit in hitResults) {
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
    }

    // GLSurfaceView.Renderer
    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.1f, 0.1f, 0.1f, 1.0f)
        try {
            session?.setCameraTextureName(0)
        } catch (_: Exception) {}
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        displayRotationHelper?.onSurfaceChanged(width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

        val s = session ?: return
        displayRotationHelper?.updateSessionIfNeeded(s)

        try {
            val frame = s.update()

            // 카메라 배경 그리기 (간소화)
            val camera = frame.camera

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
                                "width" to plane.extentX.toDouble(),
                                "height" to plane.extentZ.toDouble(),
                            ))
                        }
                        break
                    }
                }
            }

            // 카메라 포즈 전달
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

    override fun getView(): View = glSurfaceView

    override fun dispose() {
        disposeSession()
    }
}

/**
 * PlatformView Factory
 */
class ArCoreViewFactory(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return ArCoreNativeView(context, activity, viewId, messenger)
    }
}

/**
 * 화면 회전 헬퍼
 */
class DisplayRotationHelper(private val context: Context) {
    private var viewWidth = 0
    private var viewHeight = 0

    fun onResume() {}
    fun onPause() {}

    fun onSurfaceChanged(width: Int, height: Int) {
        viewWidth = width
        viewHeight = height
    }

    fun updateSessionIfNeeded(session: Session) {
        val display = (context as Activity).windowManager.defaultDisplay
        session.setDisplayGeometry(display.rotation, viewWidth, viewHeight)
    }
}
