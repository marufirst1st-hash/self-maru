import 'dart:async';
import 'dart:typed_data';
import '../models/correction.dart';
import '../utils/fft_utils.dart';
import '../utils/math_utils.dart';

/// Sonar Worker: FMCW chirp → 반사 → FFT → 벽 거리
/// 공식 ⑲⑳㉑㉒㉓
///
/// 실제 오디오 재생/녹음은 mode_b에서 주입.
/// 이 클래스는 녹음 데이터를 받아 거리를 계산하고 보정값 생산.
class SonarWorker {
  bool _running = false;
  final _correctionController = StreamController<Correction>.broadcast();
  Duration interval;

  // FMCW 파라미터
  final double f0;
  final double f1;
  final double chirpDuration;
  final int sampleRate;
  late final Float64List _chirpRef;

  SonarWorker({
    this.interval = const Duration(seconds: 3),
    this.f0 = 18000,
    this.f1 = 22000,
    this.chirpDuration = 0.05,
    this.sampleRate = 48000,
  }) {
    // chirp 참조 신호 미리 생성
    _chirpRef = FftUtils.generateFmcwChirp(
      f0: f0,
      f1: f1,
      duration: chirpDuration,
      sampleRate: sampleRate,
    );
  }

  Stream<Correction> get corrections => _correctionController.stream;
  bool get isRunning => _running;
  Float64List get chirpReference => _chirpRef;

  void start() {
    _running = true;
  }

  void stop() {
    _running = false;
  }

  /// 녹음 데이터를 받아 거리 계산 → 보정값 생산
  void processRecording({
    required Float64List recording,
    required String nearestCornerId,
    required double directionX,
    required double directionY,
  }) {
    if (!_running) return;

    // 1. 직접 신호 제거 (공식 ㉒)
    final cleaned = FftUtils.removeDirect(recording, _chirpRef);

    // 2. Dechirp (공식 ⑳)
    final beat = FftUtils.dechirp(cleaned, _chirpRef);

    // 3. FFT
    final spectrum = FftUtils.fftMagnitude(beat);

    // 4. 피크 주파수 → 거리 (공식 ⑳)
    final peakFreq = FftUtils.findPeakFrequency(
      spectrum,
      sampleRate: sampleRate,
      minFreq: 10,
      maxFreq: 2000,
    );

    final bandwidth = f1 - f0;
    final dist = MathUtils.beatFrequencyToDistance(
      peakFreq,
      T: chirpDuration,
      B: bandwidth,
    );

    // 유효 범위 체크 (0.1m ~ 10m)
    if (dist < 0.1 || dist > 10.0) return;

    // SNR 기반 신뢰도
    final maxMag = spectrum.reduce((a, b) => a > b ? a : b);
    final avgMag = spectrum.reduce((a, b) => a + b) / spectrum.length;
    final snr = maxMag / (avgMag + 1e-10);
    final confidence = (snr / 20).clamp(0.0, 1.0);

    _correctionController.add(Correction(
      cornerId: nearestCornerId,
      dx: directionX * dist * 0.01,
      dy: directionY * dist * 0.01,
      confidence: confidence,
      source: 'sonar',
    ));
  }

  void dispose() {
    _running = false;
    _correctionController.close();
  }
}
