import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub Releases 기반 OTA 업데이트 서비스
class UpdateService {
  static const String _owner = 'marufirst1st-hash';
  static const String _repo = 'self-maru';
  static const String _apiBase = 'https://api.github.com/repos/$_owner/$_repo';

  final Dio _dio = Dio();

  /// 최신 릴리즈 정보 조회
  Future<ReleaseInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"

      final response = await _dio.get(
        '$_apiBase/releases/latest',
        options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
      );

      if (response.statusCode != 200) return null;

      final data = response.data as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String?)?.replaceFirst('v', '') ?? '';
      final body = data['body'] as String? ?? '';
      final assets = data['assets'] as List? ?? [];

      // APK 에셋 찾기
      String? apkUrl;
      int? apkSize;
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          apkSize = asset['size'] as int?;
          break;
        }
      }

      if (tagName.isEmpty || apkUrl == null) return null;

      final isNewer = _isNewerVersion(tagName, currentVersion);

      return ReleaseInfo(
        version: tagName,
        currentVersion: currentVersion,
        releaseNotes: body,
        apkDownloadUrl: apkUrl,
        apkSizeBytes: apkSize ?? 0,
        isNewer: isNewer,
      );
    } catch (_) {
      return null;
    }
  }

  /// APK 다운로드 (진행률 콜백)
  Future<String?> downloadApk(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/floor_measure_update.apk';

      await _dio.download(
        url,
        filePath,
        onReceiveProgress: onProgress,
      );

      return filePath;
    } catch (_) {
      return null;
    }
  }

  /// 다운로드한 APK 설치
  /// MethodChannel로 네이티브 Android Intent 호출
  static const _channel = MethodChannel('com.floormeasure/installer');

  Future<bool> installApk(String filePath) async {
    try {
      final result = await _channel.invokeMethod<bool>('installApk', {
        'filePath': filePath,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 버전 비교: a > b이면 true
  bool _isNewerVersion(String a, String b) {
    final aParts = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final bParts = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av > bv) return true;
      if (av < bv) return false;
    }
    return false;
  }

  void dispose() {
    _dio.close();
  }
}

class ReleaseInfo {
  final String version;
  final String currentVersion;
  final String releaseNotes;
  final String apkDownloadUrl;
  final int apkSizeBytes;
  final bool isNewer;

  const ReleaseInfo({
    required this.version,
    required this.currentVersion,
    required this.releaseNotes,
    required this.apkDownloadUrl,
    required this.apkSizeBytes,
    required this.isNewer,
  });

  String get apkSizeMB => (apkSizeBytes / (1024 * 1024)).toStringAsFixed(1);
}
