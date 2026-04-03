package com.floormeasure.floor_measure

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import java.io.File
import java.io.FileInputStream

/**
 * PackageInstaller API를 사용한 APK 설치
 * FileProvider/Intent 방식보다 안정적
 */
object ApkInstaller {

    fun install(context: Context, filePath: String): Boolean {
        return try {
            val file = File(filePath)
            if (!file.exists()) return false

            val packageInstaller = context.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL
            )
            params.setSize(file.length())

            val sessionId = packageInstaller.createSession(params)
            val session = packageInstaller.openSession(sessionId)

            // APK 파일을 세션에 쓰기
            session.openWrite("floor_measure_update", 0, file.length()).use { outputStream ->
                FileInputStream(file).use { inputStream ->
                    inputStream.copyTo(outputStream)
                }
                session.fsync(outputStream)
            }

            // 설치 완료 콜백 Intent
            val intent = Intent(context, MainActivity::class.java)
            intent.action = "com.floormeasure.INSTALL_COMPLETE"

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val pendingIntent = PendingIntent.getActivity(context, 0, intent, flags)
            session.commit(pendingIntent.intentSender)

            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
