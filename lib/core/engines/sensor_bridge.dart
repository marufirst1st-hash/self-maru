import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'pdr_engine.dart';

/// sensors_plus → PdrEngine 브릿지
/// 실제 가속도계/자이로 데이터를 PDR에 공급
class SensorBridge {
  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;
  DateTime? _lastGyroTime;
  bool _running = false;

  bool get isRunning => _running;

  /// PDR 엔진에 센서 스트림 연결
  void connect(PdrEngine pdr) {
    if (_running) return;
    _running = true;

    // 가속도계 (50Hz 목표)
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((event) {
      pdr.onAccelerometerData(event.x, event.y, event.z);
    });

    // 자이로스코프 (50Hz 목표)
    _lastGyroTime = DateTime.now();
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((event) {
      final now = DateTime.now();
      final dt = now.difference(_lastGyroTime!).inMicroseconds / 1e6;
      _lastGyroTime = now;

      if (dt > 0 && dt < 0.1) {
        pdr.onGyroscopeData(event.x, event.y, event.z, dt);
      }
    });
  }

  /// 센서 스트림 해제
  void disconnect() {
    _running = false;
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
  }

  void dispose() {
    disconnect();
  }
}
