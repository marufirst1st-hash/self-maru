import 'dart:async';
import 'dart:ui';
import '../utils/math_utils.dart';

/// PDR Engine: 보행 추측 항법
/// 공식 ③④⑤⑥⑦⑧
///
/// 가속도계+자이로 50Hz → 걸음 감지 → 보폭 추정 → 위치 갱신
/// sensors_plus 패키지로 센서 데이터 수신.
class PdrEngine {
  bool _running = false;

  final _positionController = StreamController<PdrState>.broadcast();
  final _stepController = StreamController<PdrStep>.broadcast();

  Stream<PdrState> get onPositionUpdate => _positionController.stream;
  Stream<PdrStep> get onStep => _stepController.stream;
  bool get isRunning => _running;

  // 상태
  Offset _position = Offset.zero;
  double _heading = 0; // 라디안
  int _stepCount = 0;
  double _pitch = 0; // 폰 기울기 (라디안). 0=수직(벽), -π/2=수평(바닥)

  // 중력 분리용
  double _gravX = 0, _gravY = 0, _gravZ = 9.8;

  // 걸음 감지용
  double _peakAccel = 0;
  double _minAccel = double.infinity;
  DateTime? _lastStepTime;
  final List<double> _recentMag = [];
  double _accelMean = 9.8;
  double _accelStd = 0.7;

  // 파라미터
  final double stepThresholdSigma;
  final int minStepIntervalMs;
  final double complementaryAlpha;
  final double weinbergK;

  Offset get position => _position;
  double get heading => _heading;
  int get stepCount => _stepCount;
  double get pitch => _pitch;
  /// 폰이 벽을 비추고 있는지 (-40도 이상이면 벽 방향)
  bool get isLookingAtWall => _pitch > -0.7; // ~-40도

  PdrEngine({
    this.stepThresholdSigma = 1.2,
    this.minStepIntervalMs = 400,
    this.complementaryAlpha = 0.96,
    this.weinbergK = 0.4,
  });

  void start({Offset? initialPosition, double? initialHeading}) {
    _running = true;
    _position = initialPosition ?? Offset.zero;
    _heading = initialHeading ?? 0;
    _stepCount = 0;
    _lastStepTime = null;
    _recentMag.clear();
  }

  void stop() {
    _running = false;
  }

  /// 가속도계 데이터 수신 (50Hz)
  /// sensors_plus의 accelerometerEventStream에서 호출
  void onAccelerometerData(double ax, double ay, double az) {
    if (!_running) return;

    // 공식 ② 중력 분리 LPF
    _gravX = MathUtils.lowPassFilter(ax, _gravX);
    _gravY = MathUtils.lowPassFilter(ay, _gravY);
    _gravZ = MathUtils.lowPassFilter(az, _gravZ);

    final linearX = ax - _gravX;
    final linearY = ay - _gravY;
    final linearZ = az - _gravZ;

    // 폰 기울기(pitch): 중력 Z 성분으로 판단
    // gravZ/|g| ≈ -1 → 바닥 비추는 중, ≈ 0 → 벽 비추는 중
    final gravMag = MathUtils.magnitude(_gravX, _gravY, _gravZ);
    if (gravMag > 0.1) {
      _pitch = -(_gravZ / gravMag).clamp(-1.0, 1.0);
    }

    // 공식 ① 벡터 크기
    final mag = MathUtils.magnitude(linearX, linearY, linearZ);

    // 통계 업데이트 (최근 100개)
    _recentMag.add(mag);
    if (_recentMag.length > 100) _recentMag.removeAt(0);
    _updateStats();

    // 피크/밸리 추적
    if (mag > _peakAccel) _peakAccel = mag;
    if (mag < _minAccel) _minAccel = mag;

    // 공식 ④ 걸음 감지
    // 최소 임계값 1.5m/s² (노이즈로 인한 오감지 방지)
    final threshold = (_accelMean + stepThresholdSigma * _accelStd).clamp(1.5, 20.0);
    final now = DateTime.now();
    final canStep = _lastStepTime == null ||
        now.difference(_lastStepTime!).inMilliseconds >= minStepIntervalMs;

    if (mag > threshold && canStep && _peakAccel > 0) {
      // 공식 ⑤ Weinberg 보폭
      final rawStepLen =
          MathUtils.weinbergStepLength(_peakAccel, _minAccel, K: weinbergK);
      // 보폭 상한 1.2m (비현실적 값 방지)
      final stepLen = rawStepLen.clamp(0.1, 1.2);

      // 공식 ⑦ 위치 갱신
      _position = MathUtils.updatePosition(_position, stepLen, _heading);
      _stepCount++;
      _lastStepTime = now;

      final step = PdrStep(
        position: _position,
        heading: _heading,
        stepLength: stepLen,
        stepNumber: _stepCount,
        timestamp: now,
      );

      _stepController.add(step);
      _positionController.add(PdrState(
        position: _position,
        heading: _heading,
        stepCount: _stepCount,
        timestamp: now,
      ));

      // 리셋
      _peakAccel = 0;
      _minAccel = double.infinity;
    }
  }

  /// 자이로스코프 데이터 수신 (50Hz)
  /// sensors_plus의 gyroscopeEventStream에서 호출
  void onGyroscopeData(double gx, double gy, double gz, double dt) {
    if (!_running) return;

    // 공식 ⑥ 상보필터 (heading만)
    final gyroHeading = _heading + gz * dt;

    // 가속도 기반 heading은 자기장 없이 직접 구하기 어려우므로
    // 자이로 적분을 주로 사용하고 AR 보정에 의존
    _heading = gyroHeading;

    _positionController.add(PdrState(
      position: _position,
      heading: _heading,
      stepCount: _stepCount,
      timestamp: DateTime.now(),
    ));
  }

  /// AR Engine에서 heading 보정 주입
  void correctHeading(double arHeading, {double arConfidence = 0.8}) {
    _heading = MathUtils.complementaryFilter(
      _heading,
      arHeading,
      alpha: complementaryAlpha,
    );
  }

  /// AR Engine에서 위치 보정 주입
  void correctPosition(Offset arPosition, {double arConfidence = 0.8}) {
    _position = Offset(
      _position.dx * complementaryAlpha +
          arPosition.dx * (1 - complementaryAlpha),
      _position.dy * complementaryAlpha +
          arPosition.dy * (1 - complementaryAlpha),
    );
  }

  void _updateStats() {
    if (_recentMag.isEmpty) return;
    _accelMean = _recentMag.reduce((a, b) => a + b) / _recentMag.length;
    double variance = 0;
    for (final m in _recentMag) {
      variance += (m - _accelMean) * (m - _accelMean);
    }
    _accelStd = variance > 0
        ? (variance / _recentMag.length).abs()
        : 0.7; // sqrt는 생략, 임계값에만 사용
  }

  void reset() {
    _position = Offset.zero;
    _heading = 0;
    _stepCount = 0;
    _peakAccel = 0;
    _minAccel = double.infinity;
    _lastStepTime = null;
    _recentMag.clear();
  }

  void dispose() {
    _running = false;
    _positionController.close();
    _stepController.close();
  }
}

class PdrState {
  final Offset position;
  final double heading;
  final int stepCount;
  final DateTime timestamp;

  const PdrState({
    required this.position,
    required this.heading,
    required this.stepCount,
    required this.timestamp,
  });
}

class PdrStep {
  final Offset position;
  final double heading;
  final double stepLength;
  final int stepNumber;
  final DateTime timestamp;

  const PdrStep({
    required this.position,
    required this.heading,
    required this.stepLength,
    required this.stepNumber,
    required this.timestamp,
  });
}
