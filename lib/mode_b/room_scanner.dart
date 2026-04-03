import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import '../core/engines/arcore_view.dart';
import '../core/models/corner.dart';
import '../core/models/room.dart';
import '../core/workers/wall_constraint.dart';
import '../core/workers/merger.dart';

/// 방 스캐너
///
/// AR은 면의 종류만 판별 (바닥/벽/꺾임)
/// 면이 만나면 모서리, 모서리가 이어지면 도면
///
/// 과정:
/// 1. 바닥 감지 → 수평면 확인
/// 2. 벽 감지 → 수직면 확인 → 바닥+벽 = 첫 모서리 시작
/// 3. 벽이 꺾임 (새 방향 벽) → 꺾인 지점 = 코너
/// 4. 반복 → 코너들이 이어지면 도면
/// 5. 처음 벽까지 돌아오면 완성
class RoomScanner {
  bool _hasFloor = false;

  // 감지된 벽들 (방향으로 구분)
  final List<_Wall> _walls = [];

  // 벽 순서대로의 코너 (꺾임점)
  final List<Offset> _corners = [];

  // 첫 벽 방향 (돌아왔는지 판단)
  double? _firstWallDir;

  bool _closed = false;

  final _onUpdate = StreamController<ScanState>.broadcast();
  Stream<ScanState> get onUpdate => _onUpdate.stream;

  bool get hasFloor => _hasFloor;
  bool get isClosed => _closed;

  /// 바닥 감지
  void onFloorDetected() {
    if (_hasFloor) return;
    _hasFloor = true;
    _emit();
  }

  /// 벽 감지
  void onWallDetected(ArWall wall) {
    if (!_hasFloor) return; // 바닥 먼저

    // 벽 방향 (법선에서 계산)
    final wallDir = math.atan2(wall.nz, wall.nx);

    // 기존 벽과 같은 방향인지 체크 (±20°)
    for (final w in _walls) {
      var diff = (w.direction - wallDir).abs();
      if (diff > math.pi) diff = 2 * math.pi - diff;
      // 같은 방향이거나 반대 방향이면 같은 벽
      if (diff < 0.35 || (diff - math.pi).abs() < 0.35) {
        // 기존 벽 업데이트 (중심 위치)
        w.lastCenter = Offset(wall.cx, wall.cz);
        w.extent = math.max(w.extent, wall.width);
        _emit();
        return;
      }
    }

    // 새 벽 (꺾임!)
    final newWall = _Wall(
      direction: wallDir,
      center: Offset(wall.cx, wall.cz),
      extent: wall.width,
    );
    _walls.add(newWall);

    // 첫 벽 기록
    _firstWallDir ??= wallDir;

    // 벽이 2개 이상이면 → 꺾인 지점 = 코너
    if (_walls.length >= 2) {
      final prev = _walls[_walls.length - 2];
      final curr = _walls[_walls.length - 1];

      // 두 벽이 만나는 지점 계산 (대략적 - 센서가 보정)
      final corner = _estimateCorner(prev, curr);
      if (corner != null) {
        _corners.add(corner);
      }
    }

    // 벽이 4개 이상이고 첫 벽과 비슷한 방향 → 한 바퀴 돌아옴
    if (_walls.length >= 4 && _firstWallDir != null) {
      var diff = (wallDir - _firstWallDir!).abs();
      if (diff > math.pi) diff = 2 * math.pi - diff;
      if (diff < 0.35 || (diff - math.pi).abs() < 0.35) {
        // 마지막 코너 (현재 벽과 첫 벽이 만나는 점)
        final first = _walls.first;
        final last = _walls.last;
        final closingCorner = _estimateCorner(last, first);
        if (closingCorner != null) {
          _corners.add(closingCorner);
        }
        _closed = true;
      }
    }

    _emit();
  }

  /// 두 벽이 만나는 지점 추정
  Offset? _estimateCorner(_Wall w1, _Wall w2) {
    // 벽 방향 (법선에 수직)
    final d1 = w1.direction + math.pi / 2;
    final d2 = w2.direction + math.pi / 2;

    final d1x = math.cos(d1), d1y = math.sin(d1);
    final d2x = math.cos(d2), d2y = math.sin(d2);

    final cross = d1x * d2y - d1y * d2x;
    if (cross.abs() < 0.1) return null;

    final dx = w2.center.dx - w1.center.dx;
    final dy = w2.center.dy - w1.center.dy;
    final t = (dx * d2y - dy * d2x) / cross;

    return Offset(w1.center.dx + t * d1x, w1.center.dy + t * d1y);
  }

  /// Room 생성
  Room buildRoom() {
    final corners = _corners.map((p) => Corner(position: p, confidence: 0.75, source: 'arcore')).toList();
    if (corners.length < 3) return Room(corners: corners, mode: 'B');

    final wc = WallConstraint();
    final m = Merger();
    final corrected = corners.map((c) => c.copyWith()).toList();
    m.addAll(wc.constrainedOptimize(corrected));
    final room = Room(corners: corrected, confidence: 0.75, mode: 'B');
    m.applyToRoom(room);
    room.rebuildWalls();
    return room;
  }

  double get area {
    if (_corners.length < 3) return 0;
    double a = 0;
    for (int i = 0; i < _corners.length; i++) {
      final j = (i + 1) % _corners.length;
      a += _corners[i].dx * _corners[j].dy - _corners[j].dx * _corners[i].dy;
    }
    return a.abs() / 2;
  }

  void _emit() {
    _onUpdate.add(ScanState(
      hasFloor: _hasFloor,
      wallCount: _walls.length,
      corners: List.unmodifiable(_corners),
      area: area,
      isClosed: _closed,
      walls: _walls.map((w) => WallInfo(direction: w.direction, center: w.center, extent: w.extent)).toList(),
    ));
  }

  void reset() {
    _hasFloor = false;
    _walls.clear();
    _corners.clear();
    _firstWallDir = null;
    _closed = false;
  }

  void dispose() => _onUpdate.close();
}

class _Wall {
  double direction; // 법선 방향 (라디안)
  Offset center;
  Offset lastCenter;
  double extent;

  _Wall({required this.direction, required this.center, required this.extent})
      : lastCenter = center;
}

class WallInfo {
  final double direction;
  final Offset center;
  final double extent;
  const WallInfo({required this.direction, required this.center, required this.extent});
}

class ScanState {
  final bool hasFloor;
  final int wallCount;
  final List<Offset> corners;
  final double area;
  final bool isClosed;
  final List<WallInfo> walls;

  const ScanState({
    required this.hasFloor, required this.wallCount, required this.corners,
    required this.area, required this.isClosed, required this.walls,
  });
}
