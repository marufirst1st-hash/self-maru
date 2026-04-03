import 'dart:math' as math;
import 'dart:ui';
import '../core/engines/arcore_view.dart';
import '../core/models/corner.dart';

/// ARCore가 감지한 수직 평면 조각들을 벽으로 병합하고
/// 벽 교차점에서 코너를 자동 계산
class WallMerger {
  final List<_MergedWall> _walls = [];

  List<_MergedWall> get walls => List.unmodifiable(_walls);

  /// ARCore 벽 조각 추가 → 기존 벽에 병합하거나 새 벽 생성
  void addWallSegment(ArWall segment) {
    // 2D 좌표 (x, z - ARCore에서 y는 높이)
    final center = Offset(segment.cx, segment.cz);
    final direction = math.atan2(segment.nz, segment.nx); // 법선의 수평 방향

    // 같은 벽인지 판단: 법선 방향이 비슷하고(±20°) + 거리가 가까우면(1m)
    _MergedWall? match;
    for (final wall in _walls) {
      final angleDiff = _angleDiff(wall.direction, direction);
      // 법선이 같거나 반대 방향이면 같은 벽 (±20° 또는 ±160~200°)
      final isSameDir = angleDiff < 0.35 || (angleDiff - math.pi).abs() < 0.35;
      if (!isSameDir) continue;

      // 벽까지 거리 (법선 방향 투영)
      final dx = center.dx - wall.center.dx;
      final dy = center.dy - wall.center.dy;
      final distToWall = (dx * math.cos(wall.direction) + dy * math.sin(wall.direction)).abs();

      if (distToWall < 0.5) { // 50cm 이내면 같은 벽
        match = wall;
        break;
      }
    }

    if (match != null) {
      // 기존 벽에 병합 (중심 업데이트, 범위 확장)
      match.addSegment(center, segment.width);
    } else {
      // 새 벽
      _walls.add(_MergedWall(
        center: center,
        direction: direction,
        extent: segment.width,
      ));
    }
  }

  /// 모든 벽 쌍의 교차점 → 코너 계산
  List<Corner> calculateCorners() {
    final corners = <Corner>[];

    for (int i = 0; i < _walls.length; i++) {
      for (int j = i + 1; j < _walls.length; j++) {
        final intersection = _wallIntersection(_walls[i], _walls[j]);
        if (intersection != null) {
          // 중복 제거 (50cm 이내)
          final isDup = corners.any((c) => (c.position - intersection).distance < 0.5);
          if (!isDup) {
            corners.add(Corner(position: intersection, confidence: 0.85, source: 'arcore'));
          }
        }
      }
    }

    // 반시계 정렬
    if (corners.length >= 3) {
      final cx = corners.map((c) => c.position.dx).reduce((a, b) => a + b) / corners.length;
      final cy = corners.map((c) => c.position.dy).reduce((a, b) => a + b) / corners.length;
      corners.sort((a, b) {
        final aa = math.atan2(a.position.dy - cy, a.position.dx - cx);
        final ab = math.atan2(b.position.dy - cy, b.position.dx - cx);
        return aa.compareTo(ab);
      });
    }

    return corners;
  }

  /// 두 벽의 교차점
  Offset? _wallIntersection(_MergedWall w1, _MergedWall w2) {
    // 벽의 방향 (법선에 수직 = 벽 자체의 방향)
    final d1x = -math.sin(w1.direction);
    final d1y = math.cos(w1.direction);
    final d2x = -math.sin(w2.direction);
    final d2y = math.cos(w2.direction);

    final cross = d1x * d2y - d1y * d2x;
    if (cross.abs() < 0.1) return null; // 거의 평행 → 교차 안 함

    // 직선 교차: P1 + t * D1 = P2 + s * D2
    final dx = w2.center.dx - w1.center.dx;
    final dy = w2.center.dy - w1.center.dy;
    final t = (dx * d2y - dy * d2x) / cross;

    final ix = w1.center.dx + t * d1x;
    final iy = w1.center.dy + t * d1y;

    // 합리적 범위 (벽에서 너무 멀면 무시)
    final distFromW1 = t.abs();
    final distFromW2 = ((ix - w2.center.dx) * d2x + (iy - w2.center.dy) * d2y).abs();
    if (distFromW1 > 10 || distFromW2 > 10) return null;

    return Offset(ix, iy);
  }

  double _angleDiff(double a, double b) {
    var diff = (a - b).abs();
    while (diff > math.pi) diff -= 2 * math.pi;
    return diff.abs();
  }

  void clear() => _walls.clear();
}

/// 병합된 벽 (여러 ARCore 평면 조각이 합쳐진 것)
class _MergedWall {
  Offset center;
  double direction; // 법선 방향 (라디안)
  double extent; // 벽 길이
  int segmentCount = 1;

  _MergedWall({
    required this.center,
    required this.direction,
    required this.extent,
  });

  void addSegment(Offset newCenter, double newExtent) {
    // 가중 평균으로 중심 업데이트
    center = Offset(
      (center.dx * segmentCount + newCenter.dx) / (segmentCount + 1),
      (center.dy * segmentCount + newCenter.dy) / (segmentCount + 1),
    );
    // 범위 확장
    extent = math.max(extent, newExtent);
    segmentCount++;
  }

  /// 벽의 시작/끝 점 (2D)
  Offset get start {
    final dx = -math.sin(direction);
    final dy = math.cos(direction);
    return Offset(center.dx - dx * extent / 2, center.dy - dy * extent / 2);
  }

  Offset get end {
    final dx = -math.sin(direction);
    final dy = math.cos(direction);
    return Offset(center.dx + dx * extent / 2, center.dy + dy * extent / 2);
  }
}
