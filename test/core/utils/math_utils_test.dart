import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:floor_measure/core/utils/math_utils.dart';

void main() {
  group('MathUtils.shoelace', () {
    test('returns 0 for fewer than 3 points', () {
      expect(MathUtils.shoelace([]), 0);
      expect(MathUtils.shoelace([const Offset(0, 0)]), 0);
      expect(MathUtils.shoelace([const Offset(0, 0), const Offset(1, 0)]), 0);
    });

    test('calculates area of unit square', () {
      final square = [
        const Offset(0, 0),
        const Offset(1, 0),
        const Offset(1, 1),
        const Offset(0, 1),
      ];
      expect(MathUtils.shoelace(square), closeTo(1.0, 0.001));
    });

    test('calculates area of 4.8×3.6 rectangle', () {
      final rect = [
        const Offset(0, 0),
        const Offset(4.8, 0),
        const Offset(4.8, 3.6),
        const Offset(0, 3.6),
      ];
      expect(MathUtils.shoelace(rect), closeTo(17.28, 0.01));
    });

    test('calculates area of L-shaped room', () {
      final lShape = [
        const Offset(0, 0),
        const Offset(6, 0),
        const Offset(6, 2.5),
        const Offset(3, 2.5),
        const Offset(3, 5),
        const Offset(0, 5),
      ];
      expect(MathUtils.shoelace(lShape), closeTo(22.5, 0.1));
    });

    test('works regardless of winding order', () {
      final cw = [
        const Offset(0, 0),
        const Offset(3, 0),
        const Offset(3, 4),
        const Offset(0, 4),
      ];
      final ccw = cw.reversed.toList();
      expect(MathUtils.shoelace(cw), closeTo(MathUtils.shoelace(ccw), 0.001));
    });
  });

  group('MathUtils.perimeter', () {
    test('calculates perimeter of unit square', () {
      final square = [
        const Offset(0, 0),
        const Offset(1, 0),
        const Offset(1, 1),
        const Offset(0, 1),
      ];
      expect(MathUtils.perimeter(square), closeTo(4.0, 0.001));
    });
  });

  group('MathUtils.weinbergStepLength', () {
    test('returns positive value for valid input', () {
      final length = MathUtils.weinbergStepLength(12.0, 8.0);
      expect(length, greaterThan(0));
      expect(length, lessThan(2.0)); // 합리적 보폭 범위
    });

    test('returns 0 for equal aMax and aMin', () {
      expect(MathUtils.weinbergStepLength(10.0, 10.0), 0);
    });
  });

  group('MathUtils.updatePosition', () {
    test('moves north when heading is 0', () {
      final pos = MathUtils.updatePosition(Offset.zero, 1.0, 0);
      expect(pos.dx, closeTo(0, 0.001));
      expect(pos.dy, closeTo(1.0, 0.001));
    });

    test('moves east when heading is π/2', () {
      final pos = MathUtils.updatePosition(Offset.zero, 1.0, math.pi / 2);
      expect(pos.dx, closeTo(1.0, 0.001));
      expect(pos.dy, closeTo(0, 0.001));
    });
  });

  group('MathUtils.lineIntersection', () {
    test('finds intersection of perpendicular lines', () {
      // x = 2 → 1*x + 0*y - 2 = 0
      // y = 3 → 0*x + 1*y - 3 = 0
      final p = MathUtils.lineIntersection(1, 0, -2, 0, 1, -3);
      expect(p, isNotNull);
      expect(p!.dx, closeTo(2, 0.001));
      expect(p.dy, closeTo(3, 0.001));
    });

    test('returns null for parallel lines', () {
      final p = MathUtils.lineIntersection(1, 0, -1, 1, 0, -2);
      expect(p, isNull);
    });
  });

  group('MathUtils.inverseSquareDistance', () {
    test('returns finite for positive intensity', () {
      final d = MathUtils.inverseSquareDistance(100, K: 10);
      expect(d, closeTo(1.0, 0.001));
    });

    test('returns infinity for zero intensity', () {
      expect(MathUtils.inverseSquareDistance(0), double.infinity);
    });
  });

  group('MathUtils.complementaryFilter', () {
    test('weights gyro more with high alpha', () {
      final result = MathUtils.complementaryFilter(1.0, 0.0, alpha: 0.96);
      expect(result, closeTo(0.96, 0.001));
    });
  });
}
