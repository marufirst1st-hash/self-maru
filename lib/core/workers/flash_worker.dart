import 'dart:async';
import '../models/correction.dart';
import '../utils/math_utils.dart';

/// Flash Worker: 플래시 ON/OFF → 프레임 차분 → 벽 거리
/// 공식 ⑨⑩⑪⑭
///
/// 실제 카메라 연동은 mode_b/auto_measure.dart에서 프레임을 주입.
/// 이 클래스는 프레임 차분 데이터를 받아 보정값을 생산.
class FlashWorker {
  bool _running = false;
  final _correctionController = StreamController<Correction>.broadcast();
  Duration interval;
  double calibrationK;

  FlashWorker({
    this.interval = const Duration(seconds: 2),
    this.calibrationK = 1.0,
  });

  Stream<Correction> get corrections => _correctionController.stream;
  bool get isRunning => _running;

  void start() {
    _running = true;
  }

  void stop() {
    _running = false;
  }

  /// 프레임 차분 결과를 받아 보정값 생산
  /// [meanIntensity]: ON-OFF 차분 평균 밝기
  /// [nearestCornerId]: 가장 가까운 코너 ID
  /// [direction]: 벽 방향 (dx, dy) 단위벡터
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
      dx: directionX * dist * 0.01, // 미세 보정
      dy: directionY * dist * 0.01,
      confidence: confidence,
      source: 'flash',
    ));
  }

  void dispose() {
    _running = false;
    _correctionController.close();
  }
}
