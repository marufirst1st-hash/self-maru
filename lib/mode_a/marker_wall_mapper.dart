import 'apriltag_detector.dart';
import '../core/models/wall.dart';
import '../core/models/corner.dart';

/// 마커→벽/코너 매핑
/// 공식 A③
///
/// 스티커(벽 위) → 벽의 한 점 + 법선
/// 큐브(코너) → 코너 좌표
class MarkerWallMapper {
  /// 두 스티커 태그 → 벽
  Wall wallFromStickers(TagResult sticker1, TagResult sticker2) {
    return Wall(
      start: sticker1.worldPosition,
      end: sticker2.worldPosition,
      confidence: 0.95,
      source: 'marker',
    );
  }

  /// 큐브 태그 → 코너
  Corner cornerFromCube(TagResult cube) {
    return Corner(
      position: cube.worldPosition,
      confidence: 0.95,
      source: 'marker',
    );
  }

  /// 감지된 태그 목록을 분류하여 벽/코너로 변환
  MapperResult processDetections(List<TagResult> detections) {
    final corners = <Corner>[];
    final walls = <Wall>[];
    final stickers = <TagResult>[];

    for (final tag in detections) {
      if (tag.type == TagType.cube) {
        corners.add(cornerFromCube(tag));
      } else if (tag.type == TagType.sticker) {
        stickers.add(tag);
      }
    }

    // 인접 스티커 쌍 → 벽
    for (int i = 0; i < stickers.length - 1; i++) {
      for (int j = i + 1; j < stickers.length; j++) {
        final dist = (stickers[i].worldPosition - stickers[j].worldPosition).distance;
        // 같은 벽의 스티커: 0.5m ~ 10m 사이
        if (dist > 0.5 && dist < 10.0) {
          walls.add(wallFromStickers(stickers[i], stickers[j]));
        }
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
