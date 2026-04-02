import 'dart:async';

/// 발열 모니터링
/// Worker 부하가 과도할 때 자동으로 Tier를 낮추거나 Worker를 중단
class TemperatureMonitor {
  double _currentLoad = 0;
  bool _isThrottled = false;
  final _throttleController = StreamController<bool>.broadcast();

  Stream<bool> get onThrottleChanged => _throttleController.stream;
  bool get isThrottled => _isThrottled;
  double get currentLoad => _currentLoad;

  /// Worker 부하 갱신 (0~1)
  void updateLoad(double load) {
    _currentLoad = load.clamp(0.0, 1.0);
    final shouldThrottle = _currentLoad > 0.85;
    if (shouldThrottle != _isThrottled) {
      _isThrottled = shouldThrottle;
      _throttleController.add(_isThrottled);
    }
  }

  void dispose() {
    _throttleController.close();
  }
}
