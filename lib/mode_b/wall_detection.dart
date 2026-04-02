import 'dart:ui';
import '../core/engines/ar_engine.dart';
import '../core/models/wall.dart';
import '../core/models/corner.dart';

/// 벽 감지 파이프라인 (Mode B)
/// AR 수직평면 → 벽 등록 → 교차 → 코너 자동 계산
class WallDetection {
  final List<Wall> _detectedWalls = [];
  final List<Corner> _detectedCorners = [];

  List<Wall> get walls => List.unmodifiable(_detectedWalls);
  List<Corner> get corners => List.unmodifiable(_detectedCorners);

  /// AR 평면으로부터 벽 등록
  void onPlaneDetected(ArPlane plane) {
    if (!plane.isVertical) return;

    // 수직 평면 → 벽 (center ± width/2 방향으로 양 끝점 계산)
    final halfW = plane.width / 2;
    // 법선에 수직인 방향이 벽 방향
    final wallDirX = -plane.normalY;
    final wallDirY = plane.normalX;
    final norm = (wallDirX * wallDirX + wallDirY * wallDirY);
    if (norm < 0.01) return;
    final len = norm > 0 ? 1.0 / norm : 1.0;

    final start = Offset(
      plane.center.dx - wallDirX * len * halfW,
      plane.center.dy - wallDirY * len * halfW,
    );
    final end = Offset(
      plane.center.dx + wallDirX * len * halfW,
      plane.center.dy + wallDirY * len * halfW,
    );

    // 중복 체크 (기존 벽과 가까운지)
    final isDuplicate = _detectedWalls.any((w) {
      final d1 = (w.start - start).distance + (w.end - end).distance;
      final d2 = (w.start - end).distance + (w.end - start).distance;
      return d1 < 0.5 || d2 < 0.5;
    });

    if (!isDuplicate) {
      _detectedWalls.add(Wall(
        start: start,
        end: end,
        confidence: 0.7,
        source: 'arcore',
      ));
      _updateCorners();
    }
  }

  /// 두 벽의 교차점 → 코너
  void _updateCorners() {
    _detectedCorners.clear();
    for (int i = 0; i < _detectedWalls.length; i++) {
      for (int j = i + 1; j < _detectedWalls.length; j++) {
        final intersection = _wallIntersection(_detectedWalls[i], _detectedWalls[j]);
        if (intersection != null) {
          final isDuplicate = _detectedCorners.any(
            (c) => (c.position - intersection).distance < 0.3,
          );
          if (!isDuplicate) {
            _detectedCorners.add(Corner(
              position: intersection,
              confidence: 0.6,
              source: 'arcore',
            ));
          }
        }
      }
    }
  }

  /// 두 벽(선분)의 연장 교차점
  Offset? _wallIntersection(Wall w1, Wall w2) {
    final d1 = w1.end - w1.start;
    final d2 = w2.end - w2.start;
    final cross = d1.dx * d2.dy - d1.dy * d2.dx;
    if (cross.abs() < 1e-10) return null; // 평행

    final d = w2.start - w1.start;
    final t = (d.dx * d2.dy - d.dy * d2.dx) / cross;

    final point = Offset(
      w1.start.dx + t * d1.dx,
      w1.start.dy + t * d1.dy,
    );

    // 합리적 범위 내인지 (방 크기 이내)
    if (point.dx.abs() > 50 || point.dy.abs() > 50) return null;

    return point;
  }

  /// 수동 코너 추가
  void addManualCorner(Offset position) {
    _detectedCorners.add(Corner(
      position: position,
      confidence: 1.0,
      source: 'manual',
    ));
  }

  void clear() {
    _detectedWalls.clear();
    _detectedCorners.clear();
  }
}
