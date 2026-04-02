import 'dart:math' as math;
import 'dart:typed_data';

/// FFT 유틸리티 (Sonar Worker용)
class FftUtils {
  FftUtils._();

  /// FMCW chirp 신호 생성
  /// 공식 ⑲
  /// s(t) = cos(2π(f₀t + μt²/2)), μ = B/T
  static Float64List generateFmcwChirp({
    double f0 = 18000, // 시작 주파수 Hz
    double f1 = 22000, // 종료 주파수 Hz
    double duration = 0.05, // 50ms
    int sampleRate = 48000,
  }) {
    final B = f1 - f0;
    final mu = B / duration;
    final numSamples = (duration * sampleRate).toInt();
    final chirp = Float64List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      chirp[i] = math.cos(2 * math.pi * (f0 * t + mu * t * t / 2));
    }
    return chirp;
  }

  /// Dechirp: 수신 신호 × chirp 참조 → beat 신호
  /// 공식 ⑳
  static Float64List dechirp(Float64List received, Float64List reference) {
    final len = math.min(received.length, reference.length);
    final beat = Float64List(len);
    for (int i = 0; i < len; i++) {
      beat[i] = received[i] * reference[i];
    }
    return beat;
  }

  /// 간단한 FFT (Cooley-Tukey radix-2 DIT)
  /// 입력 길이는 2의 거듭제곱이어야 함
  static List<double> fftMagnitude(Float64List signal) {
    // 2의 거듭제곱으로 패딩
    int n = 1;
    while (n < signal.length) {
      n <<= 1;
    }

    // 복소수 배열 (실수부, 허수부 교대)
    final data = Float64List(n * 2);
    for (int i = 0; i < signal.length; i++) {
      data[i * 2] = signal[i]; // 실수부
      data[i * 2 + 1] = 0; // 허수부
    }

    // bit-reversal
    int j = 0;
    for (int i = 0; i < n; i++) {
      if (j > i) {
        // swap
        final tmpR = data[j * 2];
        final tmpI = data[j * 2 + 1];
        data[j * 2] = data[i * 2];
        data[j * 2 + 1] = data[i * 2 + 1];
        data[i * 2] = tmpR;
        data[i * 2 + 1] = tmpI;
      }
      int m = n >> 1;
      while (m >= 1 && j >= m) {
        j -= m;
        m >>= 1;
      }
      j += m;
    }

    // FFT butterfly
    for (int step = 1; step < n; step <<= 1) {
      final angle = -math.pi / step;
      final wR = math.cos(angle);
      final wI = math.sin(angle);

      for (int group = 0; group < n; group += step * 2) {
        double curR = 1, curI = 0;
        for (int pair = 0; pair < step; pair++) {
          final i1 = (group + pair) * 2;
          final i2 = (group + pair + step) * 2;

          final tR = curR * data[i2] - curI * data[i2 + 1];
          final tI = curR * data[i2 + 1] + curI * data[i2];

          data[i2] = data[i1] - tR;
          data[i2 + 1] = data[i1 + 1] - tI;
          data[i1] += tR;
          data[i1 + 1] += tI;

          final newR = curR * wR - curI * wI;
          curI = curR * wI + curI * wR;
          curR = newR;
        }
      }
    }

    // 크기 스펙트럼 (절반만)
    final half = n ~/ 2;
    final magnitude = List<double>.filled(half, 0);
    for (int i = 0; i < half; i++) {
      final re = data[i * 2];
      final im = data[i * 2 + 1];
      magnitude[i] = math.sqrt(re * re + im * im);
    }
    return magnitude;
  }

  /// 스펙트럼에서 피크 주파수 찾기
  static double findPeakFrequency(
    List<double> magnitude, {
    required int sampleRate,
    double minFreq = 0,
    double maxFreq = double.infinity,
  }) {
    final n = magnitude.length * 2;
    final freqResolution = sampleRate / n;
    final minBin = (minFreq / freqResolution).ceil();
    final maxBin = math.min(
      magnitude.length - 1,
      (maxFreq / freqResolution).floor(),
    );

    int peakBin = minBin;
    double peakVal = 0;
    for (int i = minBin; i <= maxBin; i++) {
      if (magnitude[i] > peakVal) {
        peakVal = magnitude[i];
        peakBin = i;
      }
    }
    return peakBin * freqResolution;
  }

  /// 직접 신호 제거 (수신에서 송신 성분 빼기)
  /// 공식 ㉒
  static Float64List removeDirect(
    Float64List recording,
    Float64List chirp, {
    double scale = 1.0,
  }) {
    final len = math.min(recording.length, chirp.length);
    final cleaned = Float64List(len);
    for (int i = 0; i < len; i++) {
      cleaned[i] = recording[i] - chirp[i] * scale;
    }
    return cleaned;
  }
}
