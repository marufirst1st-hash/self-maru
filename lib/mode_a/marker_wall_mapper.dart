import 'apriltag_detector.dart';
import '../core/models/wall.dart';
import '../core/models/corner.dart';

/// 마커→벽/코너 매핑
/// 공식 A③
class MarkerWallMapper {
  /// 큐브 태그 → 코너 (이미지 좌표 기반, 실제 월드 좌표는 solvePnP 후 사용)
  Corner cornerFromTag(TagResult tag, {TagPose? pose}) {
    // pose가 있으면 월드 좌표 사용, 없으면 이미지 좌표를 임시로
    final pos = pose?.worldPosition ?? tag.position2D;
    return Corner(
      position: pos,
      confidence: tag.confidence,
      source: 'marker',
    );
  }

  /// 감지된 태그 목록을 분류하여 코너로 변환
  MapperResult processDetections(List<TagResult> detections, {List<TagPose>? poses}) {
    final corners = <Corner>[];
    final walls = <Wall>[];

    for (int i = 0; i < detections.length; i++) {
      final tag = detections[i];
      final pose = poses != null && i < poses.length ? poses[i] : null;

      if (tag.type == TagType.cube) {
        corners.add(cornerFromTag(tag, pose: pose));
      }
    }

    // 인접 코너 쌍 → 벽
    for (int i = 0; i < corners.length; i++) {
      final j = (i + 1) % corners.length;
      if (corners.length >= 2) {
        walls.add(Wall(
          start: corners[i].position,
          end: corners[j].position,
          confidence: 0.9,
          source: 'marker',
        ));
      }
    }

    return MapperResult(corners: corners, walls: walls);
  }
}

class MapperResult {
  final List<Corner> corners;
  final List<Wall> walls;

  const MapperResult({required this.corners, required this.walls});
}
