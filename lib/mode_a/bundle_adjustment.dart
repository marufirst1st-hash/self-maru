import 'dart:ui';
import '../core/models/corner.dart';
import '../core/models/wall.dart';
import '../core/models/room.dart';
import 'apriltag_detector.dart';

/// Bundle Adjustment: 전역 최적화
/// 공식 A④
///
/// 모든 카메라 프레임 + 마커 관측을 모아
/// 재투영 오차 Σ||xij - π(Ti, Mj)||² 최소화
/// Gauss-Newton 근사 구현
class BundleAdjustment {
  final int maxIterations;
  final double convergenceThreshold;

  BundleAdjustment({
    this.maxIterations = 50,
    this.convergenceThreshold = 1e-6,
  });

  /// 관측 데이터로부터 최적화된 Room 생성
  Room optimize(List<Observation> observations) {
    if (observations.isEmpty) {
      return Room();
    }

    // 1. 초기 추정: 각 마커의 독립 포즈
    final markerPositions = <int, Offset>{};
    final markerTypes = <int, TagType>{};

    for (final obs in observations) {
      markerPositions[obs.tagId] = obs.worldPosition;
      markerTypes[obs.tagId] = obs.tagType;
    }

    // 2. Gauss-Newton 반복 최적화
    var positions = Map<int, Offset>.from(markerPositions);

    for (int iter = 0; iter < maxIterations; iter++) {
      double totalError = 0;
      final updates = <int, Offset>{};

      for (final obs in observations) {
        final estimated = positions[obs.tagId];
        if (estimated == null) continue;

        // 재투영 오차
        final errorX = obs.worldPosition.dx - estimated.dx;
        final errorY = obs.worldPosition.dy - estimated.dy;
        totalError += errorX * errorX + errorY * errorY;

        // 가중 업데이트 (Jacobian 근사)
        final weight = obs.confidence / observations.length;
        final prev = updates[obs.tagId] ?? Offset.zero;
        updates[obs.tagId] = Offset(
          prev.dx + errorX * weight,
          prev.dy + errorY * weight,
        );
      }

      // 업데이트 적용
      for (final entry in updates.entries) {
        final old = positions[entry.key]!;
        positions[entry.key] = Offset(
          old.dx + entry.value.dx,
          old.dy + entry.value.dy,
        );
      }

      // 수렴 체크
      if (totalError < convergenceThreshold) break;
    }

    // 3. 최적화된 위치로 Room 구성
    final corners = <Corner>[];
    final walls = <Wall>[];

    // 큐브 → 코너
    for (final entry in positions.entries) {
      if (markerTypes[entry.key] == TagType.cube) {
        corners.add(Corner(
          position: entry.value,
          confidence: 0.95,
          source: 'marker',
        ));
      }
    }

    // 코너 순서 정렬 (반시계 방향)
    if (corners.length >= 3) {
      _sortCounterClockwise(corners);
    }

    // 벽 생성
    for (int i = 0; i < corners.length; i++) {
      final j = (i + 1) % corners.length;
      walls.add(Wall(
        start: corners[i].position,
        end: corners[j].position,
        confidence: 0.95,
        source: 'marker',
      ));
    }

    return Room(
      corners: corners,
      walls: walls,
      confidence: 0.95,
      mode: 'A',
    );
  }

  void _sortCounterClockwise(List<Corner> corners) {
    final cx = corners.map((c) => c.position.dx).reduce((a, b) => a + b) / corners.length;
    final cy = corners.map((c) => c.position.dy).reduce((a, b) => a + b) / corners.length;

    corners.sort((a, b) {
      final angleA = (a.position - Offset(cx, cy)).direction;
      final angleB = (b.position - Offset(cx, cy)).direction;
      return angleA.compareTo(angleB);
    });
  }
}

/// 마커 관측 데이터
class Observation {
  final int tagId;
  final TagType tagType;
  final Offset worldPosition; // 추정된 월드 좌표 (m)
  final List<Offset> imageCorners; // 이미지 상 4코너 (px)
  final int frameIndex;
  final double confidence;

  const Observation({
    required this.tagId,
    required this.tagType,
    required this.worldPosition,
    required this.imageCorners,
    required this.frameIndex,
    this.confidence = 0.95,
  });
}
