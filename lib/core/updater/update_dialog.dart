import 'package:flutter/material.dart';
import 'update_service.dart';

/// 업데이트 바텀시트 (다이얼로그 대신 바텀시트로 변경 - 터치 문제 해결)
class UpdateDialog {
  /// 업데이트 확인 → 바텀시트 표시
  static Future<void> checkAndShow(BuildContext context) async {
    final service = UpdateService();
    final release = await service.checkForUpdate();

    if (release != null && release.isNewer && context.mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        builder: (_) => _UpdateSheet(release: release),
      );
    }
  }
}

class _UpdateSheet extends StatefulWidget {
  final ReleaseInfo release;
  const _UpdateSheet({required this.release});

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
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
    setState(() { _downloading = true; _progress = 0; _error = null; });

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
      setState(() { _downloading = false; _downloadedPath = path; });
      await _installApk(path);
    } else {
      setState(() { _downloading = false; _error = '다운로드 실패. 네트워크를 확인해주세요.'; });
    }
  }

  Future<void> _installApk(String path) async {
    final success = await _service.installApk(path);
    if (!success && mounted) {
      setState(() => _error = '설치 버튼을 다시 눌러주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF151926),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),

          // 제목
          const Row(children: [
            Icon(Icons.system_update, color: Color(0xFF4FC3F7), size: 24),
            SizedBox(width: 10),
            Text('업데이트 가능', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 16),

          // 버전
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF0A0E1A), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Text('v${widget.release.currentVersion}', style: const TextStyle(color: Colors.grey, fontSize: 14)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.arrow_forward, color: Colors.grey, size: 16)),
              Text('v${widget.release.version}', style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${widget.release.apkSizeMB} MB', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 12),

          // 릴리즈 노트
          if (widget.release.releaseNotes.isNotEmpty)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 80),
              child: SingleChildScrollView(
                child: Text(widget.release.releaseNotes, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ),

          // 진행률
          if (_downloading) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: _progress, backgroundColor: const Color(0xFF1E2235), valueColor: const AlwaysStoppedAnimation(Color(0xFF4FC3F7)), minHeight: 6),
            ),
            const SizedBox(height: 6),
            Text('다운로드 중... ${(_progress * 100).toInt()}%', style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 12)),
          ],

          // 에러
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ],

          // 완료
          if (_downloadedPath != null && !_downloading) ...[
            const SizedBox(height: 10),
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_circle, color: Color(0xFF66BB6A), size: 16),
              SizedBox(width: 6),
              Text('다운로드 완료', style: TextStyle(color: Color(0xFF66BB6A), fontSize: 12)),
            ]),
          ],

          const SizedBox(height: 20),

          // 버튼
          Row(children: [
            Expanded(
              child: SizedBox(height: 50, child: OutlinedButton(
                onPressed: _downloading ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.grey, side: const BorderSide(color: Colors.grey), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('나중에', style: TextStyle(fontSize: 15)),
              )),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SizedBox(height: 50, child: ElevatedButton(
                onPressed: _downloading ? null : (_downloadedPath != null ? () => _installApk(_downloadedPath!) : _startDownload),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _downloadedPath != null ? const Color(0xFF66BB6A) : const Color(0xFF4FC3F7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _downloading ? '다운로드 중...' : _downloadedPath != null ? '설치' : '업데이트',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              )),
            ),
          ]),

          // 하단 여백 (SafeArea)
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
