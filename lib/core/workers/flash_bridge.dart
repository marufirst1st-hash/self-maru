import 'dart:async';
import 'package:camera/camera.dart';
import '../engines/camera_bridge.dart';
import '../models/corner.dart';
import 'flash_worker.dart';

/// Flash Worker ↔ 실제 카메라 플래시 연결
/// 주기적으로 플래시 ON/OFF → 프레임 차분 → FlashWorker에 전달
class FlashBridge {
  final CameraBridge camera;
  final FlashWorker flashWorker;
  Timer? _timer;
  bool _running = false;
  double? _lastOnBrightness;
  double? _lastOffBrightness;
  bool _flashState = false;

  /// 현재 보정 대상 코너 (외부에서 업데이트)
  Corner? nearestCorner;
  double directionX = 0;
  double directionY = 0;

  FlashBridge({
    required this.camera,
    required this.flashWorker,
  });

  void start({Duration interval = const Duration(seconds: 2)}) {
    if (_running) return;
    _running = true;
    flashWorker.start();

    _timer = Timer.periodic(interval, (_) => _cycle());
  }

  Future<void> _cycle() async {
    if (!_running || !camera.isInitialized) return;
    if (nearestCorner == null) return;

    // 1. 플래시 ON → 밝기 측정
    await camera.flashOn();
    await Future.delayed(const Duration(milliseconds: 50));
    _flashState = true;

    // 현재 프레임 밝기를 캡처하기 위해 스트리밍에서 한 프레임 받기
    // (스트리밍이 이미 돌고 있으면 _lastOnBrightness가 onFrame에서 갱신됨)
    await Future.delayed(const Duration(milliseconds: 100));
    final onBrightness = _lastOnBrightness ?? 0;

    // 2. 플래시 OFF → 밝기 측정
    await camera.flashOff();
    _flashState = false;
    await Future.delayed(const Duration(milliseconds: 100));
    final offBrightness = _lastOffBrightness ?? 0;

    // 3. 차분 → FlashWorker에 전달
    final diff = (onBrightness - offBrightness).abs();
    if (diff > 1 && nearestCorner != null) {
      flashWorker.processDiff(
        meanIntensity: diff,
        nearestCornerId: nearestCorner!.id,
        directionX: directionX,
        directionY: directionY,
      );
    }
  }

  /// 카메라 프레임 스트리밍 콜백에서 호출
  void onFrame(CameraImage image) {
    final brightness = CameraBridge.meanBrightness(image);
    if (_flashState) {
      _lastOnBrightness = brightness;
    } else {
      _lastOffBrightness = brightness;
    }
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    flashWorker.stop();
    camera.flashOff();
  }

  void dispose() {
    stop();
  }
}
