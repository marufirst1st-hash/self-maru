package com.floormeasure.floor_measure

import android.content.Intent
import android.os.Build
import androidx.core.content.FileProvider
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
                            result.success(installApk(filePath))
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

    private fun installApk(filePath: String): Boolean {
        return try {
            val file = File(filePath)
            if (!file.exists()) return false

            val intent = Intent(Intent.ACTION_VIEW)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val uri = FileProvider.getUriForFile(
                    this,
                    "${applicationContext.packageName}.fileprovider",
                    file
                )
                intent.setDataAndType(uri, "application/vnd.android.package-archive")
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else {
                intent.setDataAndType(
                    android.net.Uri.fromFile(file),
                    "application/vnd.android.package-archive"
                )
            }

            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
