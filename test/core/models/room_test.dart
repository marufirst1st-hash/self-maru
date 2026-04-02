import 'dart:convert';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:floor_measure/core/models/corner.dart';
import 'package:floor_measure/core/models/room.dart';

void main() {
  group('Room', () {
    test('calculates area via Shoelace', () {
      final room = Room(
        corners: [
          Corner(position: const Offset(0, 0)),
          Corner(position: const Offset(5, 0)),
          Corner(position: const Offset(5, 4)),
          Corner(position: const Offset(0, 4)),
        ],
      );
      expect(room.area, closeTo(20.0, 0.01));
    });

    test('calculates perimeter', () {
      final room = Room(corners: [
        Corner(position: const Offset(0, 0)),
        Corner(position: const Offset(3, 0)),
        Corner(position: const Offset(3, 4)),
        Corner(position: const Offset(0, 4)),
      ]);
      room.rebuildWalls();
      expect(room.perimeter, closeTo(14.0, 0.01));
    });

    test('rebuildWalls creates correct number of walls', () {
      final room = Room(corners: [
        Corner(position: const Offset(0, 0)),
        Corner(position: const Offset(3, 0)),
        Corner(position: const Offset(3, 4)),
        Corner(position: const Offset(0, 4)),
      ]);
      room.rebuildWalls();
      expect(room.walls.length, 4);
    });

    test('serializes and deserializes via Map', () {
      final room = Room(
        corners: [
          Corner(position: const Offset(1, 2), confidence: 0.9, source: 'arcore'),
          Corner(position: const Offset(3, 4), confidence: 0.8, source: 'pdr'),
        ],
        mode: 'B',
        confidence: 0.85,
      );
      room.rebuildWalls();

      final map = room.toMap();
      final json = jsonEncode(map);
      final decoded = Room.fromMap(jsonDecode(json) as Map<String, dynamic>);

      expect(decoded.corners.length, 2);
      expect(decoded.corners[0].position.dx, closeTo(1, 0.001));
      expect(decoded.corners[1].position.dy, closeTo(4, 0.001));
      expect(decoded.mode, 'B');
      expect(decoded.confidence, closeTo(0.85, 0.01));
    });
  });
}
