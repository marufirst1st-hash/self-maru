import 'package:flutter/material.dart';
import 'update_service.dart';

/// 업데이트 다이얼로그 + 다운로드 진행률
class UpdateDialog extends StatefulWidget {
  final ReleaseInfo release;

  const UpdateDialog({super.key, required this.release});

  /// 업데이트 확인 → 다이얼로그 표시 (앱 시작 시 호출)
  static Future<void> checkAndShow(BuildContext context) async {
    final service = UpdateService();
    final release = await service.checkForUpdate();

    if (release != null && release.isNewer && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateDialog(release: release),
      );
    }
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final UpdateService _service = UpdateService();
  bool _downloading = false;
  double _progress = 0;
  String? _error;
  String? _downloadedPath;

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    final path = await _service.downloadApk(
      widget.release.apkDownloadUrl,
      onProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      },
    );

    if (!mounted) return;

    if (path != null) {
      setState(() {
        _downloading = false;
        _downloadedPath = path;
      });
      // 자동 설치
      await _installApk(path);
    } else {
      setState(() {
        _downloading = false;
        _error = '다운로드 실패. 네트워크를 확인해주세요.';
      });
    }
  }

  Future<void> _installApk(String path) async {
    final success = await _service.installApk(path);
    if (!success && mounted) {
      setState(() => _error = 'APK 설치에 실패했습니다. 파일 관리자에서 직접 설치해주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF151926),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.system_update, color: Color(0xFF4FC3F7), size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('업데이트 가능',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 버전 정보
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E1A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(
                  'v${widget.release.currentVersion}',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.arrow_forward, color: Colors.grey, size: 16),
                ),
                Text(
                  'v${widget.release.version}',
                  style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${widget.release.apkSizeMB} MB',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 릴리즈 노트
          if (widget.release.releaseNotes.isNotEmpty) ...[
            const Text('변경사항', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Text(
                  widget.release.releaseNotes,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 다운로드 진행률
          if (_downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: const Color(0xFF1E2235),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF4FC3F7)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '다운로드 중... ${(_progress * 100).toInt()}%',
              style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 12),
            ),
          ],

          // 에러
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),

          // 다운로드 완료
          if (_downloadedPath != null && !_downloading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF66BB6A), size: 16),
                  SizedBox(width: 6),
                  Text('다운로드 완료. 설치 화면이 열립니다.',
                      style: TextStyle(color: Color(0xFF66BB6A), fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
      actions: [
        if (!_downloading) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('나중에', style: TextStyle(color: Colors.grey)),
          ),
          if (_downloadedPath == null)
            ElevatedButton.icon(
              onPressed: _startDownload,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('업데이트', style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4FC3F7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () => _installApk(_downloadedPath!),
              icon: const Icon(Icons.install_mobile, size: 18),
              label: const Text('설치', style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF66BB6A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ],
      ],
    );
  }
}
