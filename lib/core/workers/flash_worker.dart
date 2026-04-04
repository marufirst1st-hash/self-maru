import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import '../models/correction.dart';
import '../utils/math_utils.dart';

/// Flash 추론 벽: 명암 경계에서 추론된 벽 방향+위치
class FlashInferredWall {
  final double direction; // 벽 법선 각도 (라디안)
  final Offset center;    // 추정 벽 중심 (world XZ)
  final double confidence;
  final double distance;  // 카메라로부터 추정 거리

  const FlashInferredWall({
    required this.direction,
    required this.center,
    required this.confidence,
    required this.distance,
  });
}

/// Flash Worker: 플래시 ON/OFF → 프레임 차분 → 벽 거리 + 벽 발견
/// 공식 ⑨⑩⑪⑭
///
/// 두 가지 역할:
/// 1. 기존: 코너가 있으면 보정값 생산
/// 2. 신규: 코너 없이도 명암 경계에서 벽 자체를 추론 (닭-달걀 해결)
class FlashWorker {
  bool _running = false;
  final _correctionController = StreamController<Correction>.broadcast();
  final _wallController = StreamController<FlashInferredWall>.broadcast();
  Duration interval;
  double calibrationK;

  /// 최근 Flash 경계 히스토리 (안정적 추론용)
  final List<_FlashEdgeHistory> _edgeHistory = [];
  static const _maxHistory = 10;
  static const _stableThreshold = 3; // 같은 방향 3회 이상이면 벽으로 확정

  FlashWorker({
    this.interval = const Duration(seconds: 2),
    this.calibrationK = 1.0,
  });

  Stream<Correction> get corrections => _correctionController.stream;
  Stream<FlashInferredWall> get inferredWalls => _wallController.stream;
  bool get isRunning => _running;

  void start() {
    _running = true;
  }

  void stop() {
    _running = false;
  }

  /// 프레임 차분 결과를 받아 보정값 생산 (기존 역할: 코너 보정)
  void processDiff({
    required double meanIntensity,
    required String nearestCornerId,
    required double directionX,
    required double directionY,
    double maxSnr = 100,
    double snr = 50,
  }) {
    if (!_running) return;

    // 공식 ⑩: 거리 = K / √(밝기)
    final dist = MathUtils.inverseSquareDistance(
      meanIntensity,
      K: calibrationK,
    );
    if (dist.isInfinite || dist.isNaN) return;

    final confidence = (snr / maxSnr).clamp(0.0, 1.0);

    _correctionController.add(Correction(
      cornerId: nearestCornerId,
      dx: directionX * dist * 0.01,
      dy: directionY * dist * 0.01,
      confidence: confidence,
      source: 'flash',
    ));
  }

  /// 명암 경계에서 벽 추론 (신규 역할: 벽 발견)
  ///
  /// AR이 벽을 못 찾을 때 Flash가 벽을 찾아줌.
  /// 플래시 깜박임 → 벽마다 밝기가 다름 → 면 구분 → 경계 = 모서리
  ///
  /// [edges]: 네이티브에서 온 경계 데이터 [{strength, direction}]
  /// [cameraPos]: 현재 카메라 위치 (world XZ)
  /// [cameraHeading]: 현재 카메라 방향 (라디안)
  void inferWallsFromEdges({
    required List<Map<String, dynamic>> edges,
    required Offset cameraPos,
    required double cameraHeading,
  }) {
    if (!_running || edges.isEmpty) return;

    for (final edge in edges) {
      final strength = (edge['strength'] as num?)?.toDouble() ?? 0;
      if (strength < 8) continue; // 약한 경계는 무시

      final dirStr = edge['direction'] as String?;
      final isVertical = dirStr == 'vertical';

      // 경계 방향으로부터 벽 법선 추정
      // vertical 경계 → 좌우 벽 (법선이 카메라 좌우)
      // horizontal 경계 → 전후 벽 (법선이 카메라 전후)
      final wallNormalAngle = isVertical
          ? cameraHeading + math.pi / 2 // 수직 경계 → 벽은 카메라 옆
          : cameraHeading;               // 수평 경계 → 벽은 카메라 앞

      // 밝기 강도로 거리 추정 (역제곱 법칙)
      final dist = MathUtils.inverseSquareDistance(strength, K: calibrationK);
      if (dist.isInfinite || dist.isNaN || dist > 8) continue; // 8m 이상은 무시

      // 벽 중심 위치 = 카메라 위치 + 법선 방향 × 거리
      final wallCenter = Offset(
        cameraPos.dx + math.cos(wallNormalAngle) * dist,
        cameraPos.dy + math.sin(wallNormalAngle) * dist,
      );

      // 히스토리에 추가
      _edgeHistory.add(_FlashEdgeHistory(
        direction: wallNormalAngle,
        center: wallCenter,
        strength: strength,
        timestamp: DateTime.now(),
      ));
      if (_edgeHistory.length > _maxHistory) {
        _edgeHistory.removeAt(0);
      }

      // 같은 방향의 경계가 반복되면 벽으로 확정
      final similar = _edgeHistory.where((h) {
        var angleDiff = (h.direction - wallNormalAngle).abs();
        if (angleDiff > math.pi) angleDiff = (angleDiff - 2 * math.pi).abs();
        return angleDiff < 0.5 && (h.center - wallCenter).distance < 1.0;
      }).length;

      if (similar >= _stableThreshold) {
        final confidence = (strength / 50).clamp(0.3, 0.7);
        _wallController.add(FlashInferredWall(
          direction: wallNormalAngle,
          center: wallCenter,
          confidence: confidence,
          distance: dist,
        ));
      }
    }
  }

  void clearHistory() => _edgeHistory.clear();

  void dispose() {
    _running = false;
    _correctionController.close();
    _wallController.close();
  }
}

class _FlashEdgeHistory {
  final double direction;
  final Offset center;
  final double strength;
  final DateTime timestamp;

  _FlashEdgeHistory({
    required this.direction,
    required this.center,
    required this.strength,
    required this.timestamp,
  });
}
