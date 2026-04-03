package com.floormeasure.floor_measure

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
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

            // Android 8+ 에서 알 수 없는 소스 설치 권한 확인
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (!packageManager.canRequestPackageInstalls()) {
                    // 설정으로 보내서 권한 허용하게 함
                    val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    intent.data = Uri.parse("package:$packageName")
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    // 권한 허용 후 다시 시도해야 하므로 일단 false
                    return false
                }
            }

            val intent = Intent(Intent.ACTION_VIEW)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION

            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(
                    this,
                    "${applicationContext.packageName}.fileprovider",
                    file
                )
            } else {
                Uri.fromFile(file)
            }

            intent.setDataAndType(uri, "application/vnd.android.package-archive")
            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
