import 'dart:typed_data';
import 'dart:ui';
import '../models/photo.dart';

/// AR 세션 중 사진 촬영
/// AR 중단 없이 현재 프레임 고해상도 캡처
/// 메타데이터: 위치, 방향, 가장 가까운 벽/코너
class PhotoCapture {
  final List<Photo> _capturedPhotos = [];

  List<Photo> get photos => List.unmodifiable(_capturedPhotos);
  int get photoCount => _capturedPhotos.length;

  /// 사진 캡처
  /// [imageBytes]: 캡처된 이미지 바이트
  /// [position]: 촬영 시점의 월드 좌표
  /// [heading]: 촬영 방향 (라디안)
  /// [nearestWallId]: 가장 가까운 벽 ID
  Photo capture({
    required Uint8List imageBytes,
    required Offset position,
    double heading = 0,
    String? nearestWallId,
    String? note,
  }) {
    final photo = Photo(
      imageBytes: imageBytes,
      worldPosition: position,
      heading: heading,
      nearestWallId: nearestWallId,
      note: note,
    );
    _capturedPhotos.add(photo);
    return photo;
  }

  /// 코너 감지 시 자동 촬영 트리거
  /// 코너가 새로 감지되면 자동으로 호출
  Photo? autoCapture({
    Uint8List? currentFrame,
    required Offset position,
    required double heading,
    String? nearestWallId,
  }) {
    if (currentFrame == null) return null;
    return capture(
      imageBytes: currentFrame,
      position: position,
      heading: heading,
      nearestWallId: nearestWallId,
      note: 'Auto-captured at corner detection',
    );
  }

  /// 특정 사진 삭제
  void remove(String photoId) {
    _capturedPhotos.removeWhere((p) => p.id == photoId);
  }

  /// 전체 초기화
  void clear() {
    _capturedPhotos.clear();
  }
}
