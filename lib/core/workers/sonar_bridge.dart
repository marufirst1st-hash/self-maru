import 'dart:async';
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

  SonarBridge({required this.sonarWorker});

  Future<void> start({Duration interval = const Duration(seconds: 3)}) async {
    if (_running) return;
    _running = true;
    sonarWorker.start();
    _timer = Timer.periodic(interval, (_) => _cycle());
  }

  Future<void> _cycle() async {
    if (!_running || nearestCorner == null) return;

    try {
      // 네이티브 녹음 (100ms, 48kHz)
      final result = await _channel.invokeMethod<List<dynamic>>('record', {'durationMs': 100});
      if (result == null || result.isEmpty) return;

      final recording = Float64List.fromList(result.map((e) => (e as num).toDouble()).toList());

      sonarWorker.processRecording(
        recording: recording,
        nearestCornerId: nearestCorner!.id,
        directionX: directionX,
        directionY: directionY,
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
