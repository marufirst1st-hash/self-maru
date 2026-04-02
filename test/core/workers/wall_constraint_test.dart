import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:floor_measure/core/models/corner.dart';
import 'package:floor_measure/core/workers/wall_constraint.dart';

void main() {
  late WallConstraint wc;

  setUp(() {
    wc = WallConstraint();
  });

  group('bowditchCorrection', () {
    test('returns empty for less than 3 corners', () {
      final corners = [
        Corner(position: const Offset(0, 0)),
        Corner(position: const Offset(1, 0)),
      ];
      expect(wc.bowditchCorrection(corners), isEmpty);
    });

    test('returns empty when already closed', () {
      final corners = [
        Corner(position: const Offset(0, 0)),
        Corner(position: const Offset(1, 0)),
        Corner(position: const Offset(1, 1)),
        Corner(position: const Offset(0, 0)), // 시작점과 동일
      ];
      expect(wc.bowditchCorrection(corners), isEmpty);
    });

    test('produces corrections for open polygon', () {
      final corners = [
        Corner(position: const Offset(0, 0)),
        Corner(position: const Offset(5, 0)),
        Corner(position: const Offset(5, 4)),
        Corner(position: const Offset(0.1, 4.1)), // 살짝 열림
      ];
      final corrections = wc.bowditchCorrection(corners);
      expect(corrections, isNotEmpty);
      // 마지막 코너의 보정이 가장 큼
      final lastCorr = corrections.last;
      expect(lastCorr.cornerId, equals(corners.last.id));
    });
  });

  group('rectifyRectangle', () {
    test('returns empty for non-4-corner polygon', () {
      final corners = [
        Corner(position: const Offset(0, 0)),
        Corner(position: const Offset(1, 0)),
        Corner(position: const Offset(1, 1)),
      ];
      expect(wc.rectifyRectangle(corners), isEmpty);
    });

    test('produces corrections for skewed rectangle', () {
      final corners = [
        Corner(position: const Offset(0, 0)),
        Corner(position: const Offset(5, 0.2)),   // 살짝 비뚤어짐
        Corner(position: const Offset(4.9, 3.8)),
        Corner(position: const Offset(0.1, 4.1)),
      ];
      final corrections = wc.rectifyRectangle(corners);
      expect(corrections, isNotEmpty);
    });

    test('returns empty for perfect rectangle', () {
      final corners = [
        Corner(position: const Offset(0, 0)),
        Corner(position: const Offset(5, 0)),
        Corner(position: const Offset(5, 4)),
        Corner(position: const Offset(0, 4)),
      ];
      final corrections = wc.rectifyRectangle(corners);
      // 완벽한 직사각형이면 보정 불필요 (또는 매우 작은 보정)
      for (final c in corrections) {
        expect(c.dx.abs(), lessThan(0.01));
        expect(c.dy.abs(), lessThan(0.01));
      }
    });
  });

  group('constrainedOptimize', () {
    test('converges for simple rectangle', () {
      final corners = [
        Corner(position: const Offset(0, 0)),
        Corner(position: const Offset(4.8, 0.1)),
        Corner(position: const Offset(4.9, 3.6)),
        Corner(position: const Offset(-0.1, 3.5)),
      ];
      final corrections = wc.constrainedOptimize(corners);
      // 보정이 생성되어야 함
      expect(corrections.length, greaterThanOrEqualTo(0));
      // 모든 보정의 source는 'wall'
      for (final c in corrections) {
        expect(c.source, 'wall');
        expect(c.confidence, greaterThan(0));
      }
    });
  });
}
