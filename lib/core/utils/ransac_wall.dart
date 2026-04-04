import 'dart:math' as math;
import 'dart:ui';

/// 3D 점
class Point3D {
  final double x, y, z;
  const Point3D(this.x, this.y, this.z);
  Offset get xz => Offset(x, z);
}

/// 수직 평면(벽): XZ 평면에서 직선 ax + bz + c = 0
class WallPlane {
  final double a, b, c;
  final List<Point3D> inliers;

  WallPlane(this.a, this.b, this.c, this.inliers);

  double get direction => math.atan2(-a, b);

  /// 벽 inlier의 XZ 범위
  ({double minX, double maxX, double minZ, double maxZ}) get bounds {
    double minX = double.infinity, maxX = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;
    for (final p in inliers) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.z < minZ) minZ = p.z;
      if (p.z > maxZ) maxZ = p.z;
    }
    return (minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ);
  }

  /// 두 벽의 교차점 (범위 체크 포함)
  static Offset? intersect(WallPlane w1, WallPlane w2) {
    final det = w1.a * w2.b - w2.a * w1.b;
    if (det.abs() < 0.01) return null;

    final x = (w1.b * w2.c - w2.b * w1.c) / det;
    final z = (w2.a * w1.c - w1.a * w2.c) / det;

    // 교차점이 각 벽 inlier 범위 근처(margin)에 있는지
    final b1 = w1.bounds;
    final b2 = w2.bounds;
    const margin = 0.5;

    final inRange1 = x >= b1.minX - margin && x <= b1.maxX + margin &&
                     z >= b1.minZ - margin && z <= b1.maxZ + margin;
    final inRange2 = x >= b2.minX - margin && x <= b2.maxX + margin &&
                     z >= b2.minZ - margin && z <= b2.maxZ + margin;

    if (!inRange1 || !inRange2) return null;
    return Offset(x, z);
  }
}

/// RANSAC으로 3D 점군에서 수직 벽(XZ 직선) 추출
List<WallPlane> findWallsRANSAC(
  List<Point3D> points, {
  int maxIterations = 200,
  double distanceThreshold = 0.08,
  int minInliers = 5,
}) {
  final walls = <WallPlane>[];
  var remaining = List<Point3D>.from(points);
  final rng = math.Random(42);

  while (remaining.length >= minInliers) {
    WallPlane? bestPlane;
    int bestCount = 0;

    for (int iter = 0; iter < maxIterations; iter++) {
      final i1 = rng.nextInt(remaining.length);
      var i2 = rng.nextInt(remaining.length);
      while (i2 == i1) i2 = rng.nextInt(remaining.length);

      final p1 = remaining[i1];
      final p2 = remaining[i2];

      final dx = p2.x - p1.x;
      final dz = p2.z - p1.z;
      final len = math.sqrt(dx * dx + dz * dz);
      if (len < 0.1) continue;

      final a = dz / len;
      final b = -dx / len;
      final c = -(a * p1.x + b * p1.z);

      final inliers = <Point3D>[];
      for (final pt in remaining) {
        final dist = (a * pt.x + b * pt.z + c).abs();
        if (dist < distanceThreshold) inliers.add(pt);
      }

      if (inliers.length > bestCount) {
        bestCount = inliers.length;
        bestPlane = WallPlane(a, b, c, inliers);
      }
    }

    if (bestPlane == null || bestCount < minInliers) break;
    walls.add(bestPlane);
    final inlierSet = bestPlane.inliers.toSet();
    remaining = remaining.where((p) => !inlierSet.contains(p)).toList();
  }

  return walls;
}

/// 벽들의 교차점에서 코너 추출 + 정렬
List<Offset> findCorners(List<WallPlane> walls) {
  final corners = <Offset>[];
  for (int i = 0; i < walls.length; i++) {
    for (int j = i + 1; j < walls.length; j++) {
      final pt = WallPlane.intersect(walls[i], walls[j]);
      if (pt != null) {
        final isDup = corners.any((c) => (c - pt).distance < 0.3);
        if (!isDup) corners.add(pt);
      }
    }
  }

  // 중심 기준 반시계 정렬
  if (corners.length >= 3) {
    final cx = corners.map((c) => c.dx).reduce((a, b) => a + b) / corners.length;
    final cy = corners.map((c) => c.dy).reduce((a, b) => a + b) / corners.length;
    corners.sort((a, b) =>
      math.atan2(a.dy - cy, a.dx - cx).compareTo(math.atan2(b.dy - cy, b.dx - cx)));
  }

  return corners;
}

/// Shoelace 면적 (XZ → Offset dx=x, dy=z)
double calcAreaFromCorners(List<Offset> corners) {
  if (corners.length < 3) return 0;
  double area = 0;
  for (int i = 0; i < corners.length; i++) {
    final j = (i + 1) % corners.length;
    area += corners[i].dx * corners[j].dy - corners[j].dx * corners[i].dy;
  }
  return area.abs() / 2;
}
