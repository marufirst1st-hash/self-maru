import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:floor_measure/core/models/corner.dart';
import 'package:floor_measure/core/models/correction.dart';
import 'package:floor_measure/core/models/room.dart';
import 'package:floor_measure/core/workers/merger.dart';

void main() {
  late Merger merger;

  setUp(() {
    merger = Merger();
  });

  group('getCorrectedPosition', () {
    test('returns original position when no corrections', () {
      final corner = Corner(position: const Offset(1, 2));
      final result = merger.getCorrectedPosition(corner);
      expect(result, const Offset(1, 2));
    });

    test('applies single correction', () {
      final corner = Corner(position: const Offset(1, 2));
      merger.onCorrection(Correction(
        cornerId: corner.id,
        dx: 0.1,
        dy: -0.05,
        confidence: 1.0,
        source: 'flash',
      ));
      final result = merger.getCorrectedPosition(corner);
      expect(result.dx, closeTo(1.1, 0.001));
      expect(result.dy, closeTo(1.95, 0.001));
    });

    test('weighted merge of multiple corrections', () {
      final corner = Corner(position: const Offset(0, 0));

      // 높은 신뢰도: dx = 1.0
      merger.onCorrection(Correction(
        cornerId: corner.id,
        dx: 1.0,
        dy: 0,
        confidence: 0.9,
        source: 'flash',
      ));

      // 낮은 신뢰도: dx = -1.0
      merger.onCorrection(Correction(
        cornerId: corner.id,
        dx: -1.0,
        dy: 0,
        confidence: 0.1,
        source: 'sonar',
      ));

      final result = merger.getCorrectedPosition(corner);
      // (1.0*0.9 + -1.0*0.1) / (0.9+0.1) = 0.8
      expect(result.dx, closeTo(0.8, 0.001));
    });
  });

  group('applyToRoom', () {
    test('applies corrections and rebuilds walls', () {
      final c1 = Corner(position: const Offset(0, 0));
      final c2 = Corner(position: const Offset(5, 0));
      final c3 = Corner(position: const Offset(5, 4));
      final room = Room(corners: [c1, c2, c3]);
      room.rebuildWalls();

      merger.onCorrection(Correction(
        cornerId: c2.id,
        dx: 0.1,
        dy: 0,
        confidence: 1.0,
        source: 'wall',
      ));

      merger.applyToRoom(room);
      expect(room.corners[1].position.dx, closeTo(5.1, 0.001));
      expect(room.walls.length, 3);
    });
  });

  group('averageConfidence', () {
    test('returns 0 when empty', () {
      expect(merger.averageConfidence, 0);
    });

    test('calculates average', () {
      final corner = Corner(position: Offset.zero);
      merger.onCorrection(Correction(
        cornerId: corner.id,
        dx: 0,
        dy: 0,
        confidence: 0.8,
        source: 'flash',
      ));
      merger.onCorrection(Correction(
        cornerId: corner.id,
        dx: 0,
        dy: 0,
        confidence: 0.6,
        source: 'sonar',
      ));
      expect(merger.averageConfidence, closeTo(0.7, 0.001));
    });
  });

  group('clear', () {
    test('resets all corrections', () {
      final corner = Corner(position: Offset.zero);
      merger.onCorrection(Correction(
        cornerId: corner.id,
        dx: 1,
        dy: 1,
        confidence: 1,
        source: 'test',
      ));
      merger.clear();
      expect(merger.averageConfidence, 0);
      expect(merger.getCorrectedPosition(corner), Offset.zero);
    });
  });
}
