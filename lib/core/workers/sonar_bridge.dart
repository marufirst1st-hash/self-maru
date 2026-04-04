import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'sonar_worker.dart';
import '../models/corner.dart';

/// Sonar Worker ↔ 네이티브 녹음 연결
/// chirp 재생 → 네이티브 녹음 → SonarWorker에 전달
class SonarBridge {
  static const _channel = MethodChannel('com.floormeasure/sonar');
  final SonarWorker sonarWorker;
  final AudioPlayer _player = AudioPlayer();
  Timer? _timer;
  bool _running = false;

  Corner? nearestCorner;
  double directionX = 0;
  double directionY = 0;

  /// 카메라 위치 기준 동작 (코너 없어도 됨)
  Offset cameraPos = Offset.zero;
  double cameraHeading = 0;

  SonarBridge({required this.sonarWorker});

  Future<void> start({Duration interval = const Duration(seconds: 3)}) async {
    if (_running) return;
    _running = true;
    sonarWorker.start();
    _timer = Timer.periodic(interval, (_) => _cycle());
  }

  Future<void> _cycle() async {
    if (!_running) return;

    // 코너가 없어도 카메라 위치 기준으로 동작 (닭-달걀 해결)
    final cornerId = nearestCorner?.id ?? '__camera__';
    final dx = nearestCorner != null ? directionX : math.cos(cameraHeading);
    final dy = nearestCorner != null ? directionY : math.sin(cameraHeading);

    try {
      final result = await _channel.invokeMethod<List<dynamic>>('record', {'durationMs': 100});
      if (result == null || result.isEmpty) return;

      final recording = Float64List.fromList(result.map((e) => (e as num).toDouble()).toList());

      sonarWorker.processRecording(
        recording: recording,
        nearestCornerId: cornerId,
        directionX: dx,
        directionY: dy,
      );
    } catch (_) {}
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    sonarWorker.stop();
    _player.stop();
  }

  void dispose() {
    stop();
    _player.dispose();
  }
}
