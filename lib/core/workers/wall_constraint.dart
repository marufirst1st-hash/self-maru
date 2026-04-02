import 'dart:math' as math;
import 'dart:ui';
import '../models/corner.dart';
import '../models/correction.dart';

/// Wall Constraint Worker
/// 공식 ㉔㉕㉖㉗㉘
/// 코너 추가/변경 시 즉시 적용. 부하 거의 0.
class WallConstraint {
  /// ㉔ 직각 보정: 각 벽 각도를 90° 배수로 스냅
  List<Correction> snapToRightAngles(List<Corner> corners) {
    if (corners.length < 3) return [];
    final corrections = <Correction>[];

    for (int i = 0; i < corners.length; i++) {
      final curr = corners[i];
      final next = corners[(i + 1) % corners.length];

      // 현재→다음 벽 각도
      final angle2 = math.atan2(
        next.position.dy - curr.position.dy,
        next.position.dx - curr.position.dx,
      );

      // 스냅된 각도
      final halfPi = math.pi / 2;
      final snappedAngle2 = (angle2 / halfPi).round() * halfPi;
      final angleDiff = snappedAngle2 - angle2;

      if (angleDiff.abs() > 0.001) {
        // 다음 코너를 회전시켜 직각 만들기
        final dist = (next.position - curr.position).distance;
        final newNext = Offset(
          curr.position.dx + dist * math.cos(snappedAngle2),
          curr.position.dy + dist * math.sin(snappedAngle2),
        );
        corrections.add(Correction(
          cornerId: next.id,
          dx: newNext.dx - next.position.dx,
          dy: newNext.dy - next.position.dy,
          confidence: 0.8,
          source: 'wall',
        ));
      }
    }
    return corrections;
  }

  /// ㉕ Bowditch 폐합 보정: 시작점으로 정확히 돌아오게
  List<Correction> bowditchCorrection(List<Corner> corners) {
    if (corners.length < 3) return [];

    // 폐합 오차
    final first = corners.first.position;
    final last = corners.last.position;
    final ex = last.dx - first.dx;
    final ey = last.dy - first.dy;

    if (ex.abs() < 0.001 && ey.abs() < 0.001) return []; // 이미 폐합

    // 누적 거리 계산
    final cumDist = <double>[0];
    for (int i = 1; i < corners.length; i++) {
      cumDist.add(cumDist.last +
          (corners[i].position - corners[i - 1].position).distance);
    }
    final totalDist = cumDist.last;
    if (totalDist < 0.001) return [];

    final corrections = <Correction>[];
    for (int i = 1; i < corners.length; i++) {
      final ratio = cumDist[i] / totalDist;
      corrections.add(Correction(
        cornerId: corners[i].id,
        dx: -ex * ratio,
        dy: -ey * ratio,
        confidence: 0.9,
        source: 'wall',
      ));
    }
    return corrections;
  }

  /// ㉖ SVD 직선 피팅: 점들을 최적 직선에 맞춤
  /// 간소화 버전 (least squares)
  Offset fitLineDirection(List<Offset> points) {
    if (points.length < 2) return const Offset(1, 0);

    final cx = points.map((p) => p.dx).reduce((a, b) => a + b) / points.length;
    final cy = points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;

    double sxx = 0, sxy = 0, syy = 0;
    for (final p in points) {
      final dx = p.dx - cx;
      final dy = p.dy - cy;
      sxx += dx * dx;
      sxy += dx * dy;
      syy += dy * dy;
    }

    // 공분산 행렬의 주축 → 직선 방향
    final angle = 0.5 * math.atan2(2 * sxy, sxx - syy);
    return Offset(math.cos(angle), math.sin(angle));
  }

  /// ㉗ 직사각형 보정 (4코너 전용)
  List<Correction> rectifyRectangle(List<Corner> corners) {
    if (corners.length != 4) return [];

    // 대변 평균으로 직사각형 만들기
    final d12 = (corners[1].position - corners[0].position).distance;
    final d23 = (corners[2].position - corners[1].position).distance;
    final d34 = (corners[3].position - corners[2].position).distance;
    final d41 = (corners[0].position - corners[3].position).distance;

    final L = (d12 + d34) / 2; // 평균 가로
    final W = (d23 + d41) / 2; // 평균 세로

    // 중심 + 첫 번째 벽 방향 기준으로 이상적 직사각형 계산
    final cx = corners.map((c) => c.position.dx).reduce((a, b) => a + b) / 4;
    final cy = corners.map((c) => c.position.dy).reduce((a, b) => a + b) / 4;
    final angle = math.atan2(
      corners[1].position.dy - corners[0].position.dy,
      corners[1].position.dx - corners[0].position.dx,
    );

    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final halfL = L / 2;
    final halfW = W / 2;

    final ideal = [
      Offset(cx - halfL * cosA + halfW * sinA, cy - halfL * sinA - halfW * cosA),
      Offset(cx + halfL * cosA + halfW * sinA, cy + halfL * sinA - halfW * cosA),
      Offset(cx + halfL * cosA - halfW * sinA, cy + halfL * sinA + halfW * cosA),
      Offset(cx - halfL * cosA - halfW * sinA, cy - halfL * sinA + halfW * cosA),
    ];

    final corrections = <Correction>[];
    for (int i = 0; i < 4; i++) {
      final dx = ideal[i].dx - corners[i].position.dx;
      final dy = ideal[i].dy - corners[i].position.dy;
      if (dx.abs() > 0.001 || dy.abs() > 0.001) {
        corrections.add(Correction(
          cornerId: corners[i].id,
          dx: dx,
          dy: dy,
          confidence: 0.7,
          source: 'wall',
        ));
      }
    }
    return corrections;
  }

  /// ㉘ 제약 최적화: 직각→폐합→직선 반복 적용
  List<Correction> constrainedOptimize(
    List<Corner> corners, {
    int maxIterations = 5,
  }) {
    var current = corners.map((c) => c.copyWith()).toList();
    final allCorrections = <Correction>[];

    for (int iter = 0; iter < maxIterations; iter++) {
      // 1. 직각 보정
      final snap = snapToRightAngles(current);
      _applyCorrections(current, snap);
      allCorrections.addAll(snap);

      // 2. 폐합 보정
      final bow = bowditchCorrection(current);
      _applyCorrections(current, bow);
      allCorrections.addAll(bow);

      // 3. 직사각형 보정 (4코너일 때)
      if (current.length == 4) {
        final rect = rectifyRectangle(current);
        _applyCorrections(current, rect);
        allCorrections.addAll(rect);
      }

      // 수렴 체크
      final totalDelta = allCorrections.isEmpty
          ? 0.0
          : allCorrections
              .map((c) => c.dx.abs() + c.dy.abs())
              .reduce((a, b) => a + b);
      if (totalDelta < 0.001) break;
    }

    // 최종 보정값: 원본 대비 차이
    final finalCorrections = <Correction>[];
    for (int i = 0; i < corners.length; i++) {
      final dx = current[i].position.dx - corners[i].position.dx;
      final dy = current[i].position.dy - corners[i].position.dy;
      if (dx.abs() > 0.001 || dy.abs() > 0.001) {
        finalCorrections.add(Correction(
          cornerId: corners[i].id,
          dx: dx,
          dy: dy,
          confidence: 0.85,
          source: 'wall',
        ));
      }
    }
    return finalCorrections;
  }

  void _applyCorrections(List<Corner> corners, List<Correction> corrections) {
    for (final c in corrections) {
      final idx = corners.indexWhere((corner) => corner.id == c.cornerId);
      if (idx >= 0) {
        corners[idx] = corners[idx].copyWith(
          position: Offset(
            corners[idx].position.dx + c.dx,
            corners[idx].position.dy + c.dy,
          ),
        );
      }
    }
  }
}
