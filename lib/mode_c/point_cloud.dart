import 'dart:math' as math;
import 'lidar_engine.dart';

/// 포인트 클라우드 전처리
/// 공식 C④: 노이즈 제거 + 평면 정렬 + 간소화
class PointCloudProcessor {
  /// Statistical Outlier Removal
  /// 각 점의 k-최근접 이웃 평균 거리를 구해, 표준편차 밖이면 제거
  PointCloud removeOutliers(
    PointCloud cloud, {
    int k = 10,
    double stdMultiplier = 2.0,
  }) {
    if (cloud.points.length <= k) return cloud;

    final distances = <double>[];

    for (final pt in cloud.points) {
      // k-최근접 이웃 거리
      final dists = cloud.points
          .where((other) => other != pt)
          .map((other) => _distance3D(pt, other))
          .toList()
        ..sort();
      final kDists = dists.take(k);
      final avgDist = kDists.reduce((a, b) => a + b) / k;
      distances.add(avgDist);
    }

    final mean = distances.reduce((a, b) => a + b) / distances.length;
    double variance = 0;
    for (final d in distances) {
      variance += (d - mean) * (d - mean);
    }
    final std = math.sqrt(variance / distances.length);
    final threshold = mean + stdMultiplier * std;

    final filtered = <Point3D>[];
    for (int i = 0; i < cloud.points.length; i++) {
      if (distances[i] <= threshold) {
        filtered.add(cloud.points[i]);
      }
    }

    return PointCloud(points: filtered, timestamp: cloud.timestamp);
  }

  /// 바닥 높이 추정 (z 좌표 히스토그램 기반)
  double estimateFloorHeight(PointCloud cloud) {
    if (cloud.points.isEmpty) return 0;
    final zValues = cloud.points.map((p) => p.z).toList()..sort();
    // 하위 10%의 평균 = 바닥 높이
    final count = (zValues.length * 0.1).ceil().clamp(1, zValues.length);
    return zValues.take(count).reduce((a, b) => a + b) / count;
  }

  /// 천장 높이 추정
  double estimateCeilingHeight(PointCloud cloud) {
    if (cloud.points.isEmpty) return 2.5;
    final zValues = cloud.points.map((p) => p.z).toList()..sort();
    final count = (zValues.length * 0.1).ceil().clamp(1, zValues.length);
    return zValues.reversed.take(count).reduce((a, b) => a + b) / count;
  }

  /// 벽 높이의 점들만 필터 (바닥~천장)
  PointCloud filterWallHeight(
    PointCloud cloud, {
    double minZ = 0.3,
    double maxZ = 2.2,
  }) {
    final filtered = cloud.points
        .where((p) => p.z >= minZ && p.z <= maxZ)
        .toList();
    return PointCloud(points: filtered, timestamp: cloud.timestamp);
  }

  /// 다운샘플링 (복셀 그리드)
  PointCloud downsample(PointCloud cloud, {double voxelSize = 0.05}) {
    final voxels = <String, Point3D>{};

    for (final pt in cloud.points) {
      final key = '${(pt.x / voxelSize).floor()}_${(pt.y / voxelSize).floor()}_${(pt.z / voxelSize).floor()}';
      voxels.putIfAbsent(key, () => pt);
    }

    return PointCloud(
      points: voxels.values.toList(),
      timestamp: cloud.timestamp,
    );
  }

  double _distance3D(Point3D a, Point3D b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}
