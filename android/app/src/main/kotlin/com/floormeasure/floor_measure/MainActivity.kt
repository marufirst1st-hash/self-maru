package com.floormeasure.floor_measure

import com.google.ar.core.ArCoreApk
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val INSTALLER_CHANNEL = "com.floormeasure/installer"
    private val AR_CHECK_CHANNEL = "com.floormeasure/ar_check"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ARCore PlatformView 등록
        flutterEngine.platformViewsController.registry
            .registerViewFactory(
                "com.floormeasure/arcore_view",
                ArCoreViewFactory(this, flutterEngine.dartExecutor.binaryMessenger)
            )

        // APK 설치 채널
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath != null) {
                            result.success(ApkInstaller.install(this, filePath))
                        } else {
                            result.error("INVALID_PATH", "filePath is null", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ARCore 체크 채널
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AR_CHECK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isArCoreAvailable" -> {
                        result.success(checkArCoreAvailability())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun checkArCoreAvailability(): Boolean {
        return try {
            val availability = ArCoreApk.getInstance().checkAvailability(this)
            availability.isSupported
        } catch (e: Exception) {
            false
        }
    }
}
