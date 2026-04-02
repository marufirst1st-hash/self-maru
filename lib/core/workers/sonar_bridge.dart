import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'sonar_worker.dart';
import '../models/corner.dart';

/// Sonar Worker ↔ 실제 오디오 연결
/// chirp 재생은 just_audio, 녹음은 추후 record 패키지 복원 시 활성화
/// 현재는 chirp 재생만 지원 (녹음은 placeholder)
class SonarBridge {
  final SonarWorker sonarWorker;
  final AudioPlayer _player = AudioPlayer();
  Timer? _timer;
  bool _running = false;

  /// 현재 보정 대상 코너
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

    // 1. Chirp 재생
    // just_audio는 메모리 오디오 소스를 직접 지원하지 않으므로
    // 미리 생성된 chirp WAV 파일을 사용하거나,
    // AudioPlayer.setAudioSource로 커스텀 소스를 만들어야 함
    // 현재는 placeholder - 실제 녹음이 없으면 Worker에 데이터를 줄 수 없음

    // TODO: record 패키지 호환 시 아래 활성화
    // final recording = await _recorder.record(100ms, 48kHz);
    // sonarWorker.processRecording(
    //   recording: recording,
    //   nearestCornerId: nearestCorner!.id,
    //   directionX: directionX,
    //   directionY: directionY,
    // );
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
