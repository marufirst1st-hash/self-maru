import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:floor_measure/core/utils/fft_utils.dart';

void main() {
  group('FftUtils.generateFmcwChirp', () {
    test('generates correct number of samples', () {
      final chirp = FftUtils.generateFmcwChirp(
        duration: 0.05,
        sampleRate: 48000,
      );
      expect(chirp.length, 2400); // 0.05 * 48000
    });

    test('values are in [-1, 1] range', () {
      final chirp = FftUtils.generateFmcwChirp();
      for (final v in chirp) {
        expect(v, greaterThanOrEqualTo(-1.0));
        expect(v, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('FftUtils.dechirp', () {
    test('produces beat signal of correct length', () {
      final a = Float64List.fromList([1, 2, 3, 4, 5]);
      final b = Float64List.fromList([0.5, 0.5, 0.5, 0.5, 0.5]);
      final beat = FftUtils.dechirp(a, b);
      expect(beat.length, 5);
      expect(beat[0], closeTo(0.5, 0.001));
      expect(beat[2], closeTo(1.5, 0.001));
    });
  });

  group('FftUtils.fftMagnitude', () {
    test('detects single frequency', () {
      // 생성: 100Hz 사인파 at 1000Hz 샘플레이트
      const sampleRate = 1000;
      const freq = 100.0;
      const n = 256;
      final signal = Float64List(n);
      for (int i = 0; i < n; i++) {
        signal[i] = math.sin(2 * math.pi * freq * i / sampleRate);
      }

      final mag = FftUtils.fftMagnitude(signal);
      final peakFreq = FftUtils.findPeakFrequency(
        mag,
        sampleRate: sampleRate,
        minFreq: 50,
        maxFreq: 200,
      );

      // 100Hz 근처에 피크가 있어야 함
      expect(peakFreq, closeTo(freq, 10));
    });
  });

  group('FftUtils.removeDirect', () {
    test('subtracts chirp from recording', () {
      final rec = Float64List.fromList([1, 2, 3]);
      final chirp = Float64List.fromList([0.5, 0.5, 0.5]);
      final cleaned = FftUtils.removeDirect(rec, chirp);
      expect(cleaned[0], closeTo(0.5, 0.001));
      expect(cleaned[1], closeTo(1.5, 0.001));
      expect(cleaned[2], closeTo(2.5, 0.001));
    });
  });
}
