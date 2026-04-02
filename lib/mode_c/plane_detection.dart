import 'dart:math' as math;
import 'dart:ui';
import 'lidar_engine.dart';
import '../core/models/wall.dart';
import '../core/models/corner.dart';

/// RANSAC 평면 검출 + 평면 교차 → 코너
/// 공식 C②C③
class PlaneDetection {
  final int maxIterations;
  final double distanceThreshold;

  PlaneDetection({
    this.maxIterations = 100,
    this.distanceThreshold = 0.05, // 5cm
  });

  /// 포인트 클라우드에서 벽(수직 평면) 추출
  /// 공식 C②: RANSAC
  List<DetectedPlane> detectWallPlanes(PointCloud cloud) {
    final planes = <DetectedPlane>[];
    var remaining = List<Point3D>.from(cloud.points);

    // 반복적으로 평면 추출 (최대 10개)
    for (int p = 0; p < 10 && remaining.length > 50; p++) {
      final result = _ransacPlane(remaining);
      if (result == null) break;

      // 수직 평면만 (법선의 z 성분이 작은 것)
      if (result.normalZ.abs() < 0.3) {
        planes.add(result);
      }

      // inlier 제거
      remaining = remaining.where((pt) {
        final dist = _pointPlaneDistance(pt, result);
        return dist > distanceThreshold;
      }).toList();
    }

    return planes;
  }

  /// 두 벽 평면의 교차 → 코너 (바닥 z=0)
  /// 공식 C③
  List<Corner> findCorners(List<DetectedPlane> planes) {
    final corners = <Corner>[];

    for (int i = 0; i < planes.length; i++) {
      for (int j = i + 1; j < planes.length; j++) {
        final corner = _planeIntersectionAtFloor(planes[i], planes[j]);
        if (corner != null) {
          // 중복 체크
          final isDuplicate = corners.any(
            (c) => (c.position - corner).distance < 0.3,
          );
          if (!isDuplicate) {
            corners.add(Corner(
              position: corner,
              confidence: 0.9,
              source: 'lidar',
            ));
          }
        }
      }
    }

    // 반시계 방향 정렬
    if (corners.length >= 3) {
      _sortCounterClockwise(corners);
    }

    return corners;
  }

  /// 평면 검출 + 코너 추출 한번에
  PlaneDetectionResult process(PointCloud cloud) {
    final planes = detectWallPlanes(cloud);
    final corners = findCorners(planes);

    final walls = <Wall>[];
    for (int i = 0; i < corners.length; i++) {
      final j = (i + 1) % corners.length;
      walls.add(Wall(
        start: corners[i].position,
        end: corners[j].position,
        confidence: 0.9,
        source: 'lidar',
      ));
    }

    return PlaneDetectionResult(
      planes: planes,
      corners: corners,
      walls: walls,
    );
  }

  DetectedPlane? _ransacPlane(List<Point3D> points) {
    if (points.length < 3) return null;
    final rng = math.Random();

    DetectedPlane? bestPlane;
    int bestInliers = 0;

    for (int iter = 0; iter < maxIterations; iter++) {
      // 무작위 3점 선택
      final i1 = rng.nextInt(points.length);
      int i2 = rng.nextInt(points.length);
      while (i2 == i1) {
        i2 = rng.nextInt(points.length);
      }
      int i3 = rng.nextInt(points.length);
      while (i3 == i1 || i3 == i2) {
        i3 = rng.nextInt(points.length);
      }

      final p1 = points[i1], p2 = points[i2], p3 = points[i3];

      // 평면 방정식: ax + by + cz + d = 0
      final v1x = p2.x - p1.x, v1y = p2.y - p1.y, v1z = p2.z - p1.z;
      final v2x = p3.x - p1.x, v2y = p3.y - p1.y, v2z = p3.z - p1.z;

      // 법선 = v1 × v2
      var nx = v1y * v2z - v1z * v2y;
      var ny = v1z * v2x - v1x * v2z;
      var nz = v1x * v2y - v1y * v2x;
      final norm = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (norm < 1e-10) continue;
      nx /= norm;
      ny /= norm;
      nz /= norm;
      final d = -(nx * p1.x + ny * p1.y + nz * p1.z);

      final plane = DetectedPlane(
        normalX: nx,
        normalY: ny,
        normalZ: nz,
        d: d,
      );

      // inlier 카운트
      int inliers = 0;
      for (final pt in points) {
        if (_pointPlaneDistance(pt, plane) < distanceThreshold) {
          inliers++;
        }
      }

      if (inliers > bestInliers) {
        bestInliers = inliers;
        bestPlane = plane;
      }
    }

    return bestInliers > points.length * 0.1 ? bestPlane : null;
  }

  double _pointPlaneDistance(Point3D pt, DetectedPlane plane) {
    return (plane.normalX * pt.x +
            plane.normalY * pt.y +
            plane.normalZ * pt.z +
            plane.d)
        .abs();
  }

  /// 두 벽 평면 + 바닥(z=0) 교차점
  Offset? _planeIntersectionAtFloor(DetectedPlane p1, DetectedPlane p2) {
    // z=0 대입: a1*x + b1*y + d1 = 0, a2*x + b2*y + d2 = 0
    final det = p1.normalX * p2.normalY - p2.normalX * p1.normalY;
    if (det.abs() < 1e-10) return null;

    final x = (-p1.d * p2.normalY + p2.d * p1.normalY) / det;
    final y = (-p1.normalX * p2.d + p2.normalX * p1.d) / det;

    // 합리적 범위
    if (x.abs() > 50 || y.abs() > 50) return null;

    return Offset(x, y);
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

class DetectedPlane {
  final double normalX, normalY, normalZ;
  final double d; // ax + by + cz + d = 0

  const DetectedPlane({
    required this.normalX,
    required this.normalY,
    required this.normalZ,
    required this.d,
  });

  bool get isVertical => normalZ.abs() < 0.3;
}

class PlaneDetectionResult {
  final List<DetectedPlane> planes;
  final List<Corner> corners;
  final List<Wall> walls;

  const PlaneDetectionResult({
    required this.planes,
    required this.corners,
    required this.walls,
  });
}
