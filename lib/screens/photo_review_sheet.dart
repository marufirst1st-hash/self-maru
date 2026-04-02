import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/models/photo.dart';

/// 사진 촬영/확인 바텀시트
/// 스캔 중 사진 촬영 결과를 확인하고 메모를 추가
class PhotoReviewSheet extends StatefulWidget {
  final Uint8List imageBytes;
  final Offset worldPosition;
  final double heading;

  const PhotoReviewSheet({
    super.key,
    required this.imageBytes,
    required this.worldPosition,
    this.heading = 0,
  });

  /// 바텀시트로 표시하고 Photo를 반환 (null이면 취소)
  static Future<Photo?> show(
    BuildContext context, {
    required Uint8List imageBytes,
    required Offset worldPosition,
    double heading = 0,
  }) {
    return showModalBottomSheet<Photo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PhotoReviewSheet(
        imageBytes: imageBytes,
        worldPosition: worldPosition,
        heading: heading,
      ),
    );
  }

  @override
  State<PhotoReviewSheet> createState() => _PhotoReviewSheetState();
}

class _PhotoReviewSheetState extends State<PhotoReviewSheet> {
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF151926),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('현장 사진',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // 사진 프리뷰
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E2235)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                widget.imageBytes,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 위치 정보
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.location_on, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'X: ${widget.worldPosition.dx.toStringAsFixed(2)}m  Y: ${widget.worldPosition.dy.toStringAsFixed(2)}m',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 메모
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _noteCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: '메모 (선택)',
                hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
                prefixIcon: const Icon(Icons.note_outlined, color: Colors.grey, size: 18),
                filled: true,
                fillColor: const Color(0xFF1E2235),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2A2F45)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2A2F45)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 버튼
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: const BorderSide(color: Colors.grey),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('삭제', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final photo = Photo(
                          imageBytes: widget.imageBytes,
                          worldPosition: widget.worldPosition,
                          heading: widget.heading,
                          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
                        );
                        Navigator.pop(context, photo);
                      },
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('저장', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4FC3F7),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
