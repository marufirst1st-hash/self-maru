/// 가상 공간 시뮬레이션: hitTest 3D 점군 → RANSAC → 벽 평면 → 코너 → 도면
///
/// 테스트 공간:
///   1) 4m x 3m 직사각형 방
///   2) L자형 방 (오각형)
///   3) 사선 벽이 있는 방
///
/// 각 벽에 3D 점을 뿌리고, RANSAC으로 벽을 찾고, 교차점=코너, 면적 계산.
import 'dart:math' as math;

// ==================== 3D 점 ====================
class Point3D {
  final double x, y, z;
  const Point3D(this.x, this.y, this.z);

  @override
  String toString() => '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

// ==================== 수직 평면 (벽) ====================
// 벽은 수직이므로 XZ 평면에서 직선: ax + bz + c = 0 (y는 무시)
class WallPlane {
  final double a, b, c; // ax + bz + c = 0
  final List<Point3D> inliers;

  WallPlane(this.a, this.b, this.c, this.inliers);

  /// 벽의 방향 (라디안)
  double get direction => math.atan2(-a, b);

  /// 벽 inlier의 XZ 범위 (벽 선분 범위)
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

  /// XZ 평면에서 두 벽의 교차점 (벽 선분 범위 안에 있는지 체크)
  static Point3D? intersect(WallPlane w1, WallPlane w2) {
    final det = w1.a * w2.b - w2.a * w1.b;
    if (det.abs() < 0.01) return null; // 거의 평행

    final x = (w1.b * w2.c - w2.b * w1.c) / det;
    final z = (w2.a * w1.c - w1.a * w2.c) / det;

    // 교차점이 각 벽의 inlier 범위 근처(마진 0.5m)에 있는지 체크
    // 범위 밖이면 가짜 교차점
    final b1 = w1.bounds;
    final b2 = w2.bounds;
    const margin = 0.5;

    final inRange1 = x >= b1.minX - margin && x <= b1.maxX + margin &&
                     z >= b1.minZ - margin && z <= b1.maxZ + margin;
    final inRange2 = x >= b2.minX - margin && x <= b2.maxX + margin &&
                     z >= b2.minZ - margin && z <= b2.maxZ + margin;

    if (!inRange1 || !inRange2) return null;

    return Point3D(x, 0, z);
  }

  @override
  String toString() => 'Wall(${a.toStringAsFixed(3)}x + ${b.toStringAsFixed(3)}z + ${c.toStringAsFixed(3)} = 0, ${inliers.length}pts)';
}

// ==================== RANSAC 수직 평면 피팅 ====================
/// 3D 점군에서 수직 평면(벽)을 찾는 RANSAC
/// 수직 = XZ 평면에서 직선 (y 무시)
List<WallPlane> findWallsRANSAC(List<Point3D> points, {
  int maxIterations = 200,
  double distanceThreshold = 0.08, // 8cm 이내 = inlier
  int minInliers = 5,
}) {
  final walls = <WallPlane>[];
  var remaining = List<Point3D>.from(points);
  final rng = math.Random(42); // 재현 가능

  while (remaining.length >= minInliers) {
    WallPlane? bestPlane;
    int bestInlierCount = 0;

    for (int iter = 0; iter < maxIterations; iter++) {
      // 무작위 2점 선택 (XZ 평면에서 직선)
      final i1 = rng.nextInt(remaining.length);
      var i2 = rng.nextInt(remaining.length);
      while (i2 == i1) i2 = rng.nextInt(remaining.length);

      final p1 = remaining[i1];
      final p2 = remaining[i2];

      // 두 점으로 직선: (z2-z1)*x - (x2-x1)*z + (x2-x1)*z1 - (z2-z1)*x1 = 0
      final dx = p2.x - p1.x;
      final dz = p2.z - p1.z;
      final len = math.sqrt(dx * dx + dz * dz);
      if (len < 0.1) continue;

      // 정규화된 직선 계수
      final a = dz / len;  // 법선 x
      final b = -dx / len; // 법선 z
      final c = -(a * p1.x + b * p1.z);

      // inlier 세기
      final inliers = <Point3D>[];
      for (final pt in remaining) {
        final dist = (a * pt.x + b * pt.z + c).abs();
        if (dist < distanceThreshold) inliers.add(pt);
      }

      if (inliers.length > bestInlierCount) {
        bestInlierCount = inliers.length;
        bestPlane = WallPlane(a, b, c, inliers);
      }
    }

    if (bestPlane == null || bestInlierCount < minInliers) break;

    walls.add(bestPlane);
    // inlier 제거
    final inlierSet = bestPlane.inliers.toSet();
    remaining = remaining.where((p) => !inlierSet.contains(p)).toList();
  }

  return walls;
}

// ==================== 도면 (코너 연결) ====================
double calcArea(List<Point3D> corners) {
  if (corners.length < 3) return 0;
  // Shoelace formula (XZ 평면)
  double area = 0;
  for (int i = 0; i < corners.length; i++) {
    final j = (i + 1) % corners.length;
    area += corners[i].x * corners[j].z - corners[j].x * corners[i].z;
  }
  return area.abs() / 2;
}

/// 코너를 중심 기준 반시계로 정렬
List<Point3D> sortCorners(List<Point3D> corners) {
  final cx = corners.map((c) => c.x).reduce((a, b) => a + b) / corners.length;
  final cz = corners.map((c) => c.z).reduce((a, b) => a + b) / corners.length;
  corners.sort((a, b) =>
    math.atan2(a.z - cz, a.x - cx).compareTo(math.atan2(b.z - cz, b.x - cx)));
  return corners;
}

// ==================== 가상 방 생성 ====================
/// 벽 위에 3D 점을 뿌림 (노이즈 포함)
List<Point3D> generateWallPoints(
  double x1, double z1, double x2, double z2, {
  int numPoints = 20,
  double noise = 0.03, // 3cm 노이즈
  double floorY = 0,
  double ceilY = 2.5,
}) {
  final rng = math.Random(42);
  final points = <Point3D>[];
  for (int i = 0; i < numPoints; i++) {
    final t = i / (numPoints - 1);
    final x = x1 + (x2 - x1) * t + (rng.nextDouble() - 0.5) * noise;
    final y = floorY + (ceilY - floorY) * rng.nextDouble(); // 높이는 랜덤
    final z = z1 + (z2 - z1) * t + (rng.nextDouble() - 0.5) * noise;
    points.add(Point3D(x, y, z));
  }
  return points;
}

// ==================== 테스트 실행 ====================
void main() {
  print('=' * 60);
  print('가상 공간 벽 인식 시뮬레이션');
  print('=' * 60);

  // ===== 테스트 1: 4m x 3m 직사각형 =====
  print('\n--- 테스트 1: 4m x 3m 직사각형 ---');
  print('실제 면적: 12.0 m²');
  print('실제 코너: (0,0), (4,0), (4,3), (0,3)');

  final rect = <Point3D>[];
  rect.addAll(generateWallPoints(0, 0, 4, 0, numPoints: 25)); // 남벽
  rect.addAll(generateWallPoints(4, 0, 4, 3, numPoints: 20)); // 동벽
  rect.addAll(generateWallPoints(4, 3, 0, 3, numPoints: 25)); // 북벽
  rect.addAll(generateWallPoints(0, 3, 0, 0, numPoints: 20)); // 서벽

  _runTest(rect, expectedArea: 12.0, expectedCorners: 4);

  // ===== 테스트 2: L자형 방 (6코너) =====
  print('\n--- 테스트 2: L자형 방 ---');
  // (0,0)-(4,0)-(4,2)-(2,2)-(2,3)-(0,3)
  print('실제 면적: ${4*2 + 2*1} = 10.0 m²');

  final lShape = <Point3D>[];
  lShape.addAll(generateWallPoints(0, 0, 4, 0, numPoints: 25));
  lShape.addAll(generateWallPoints(4, 0, 4, 2, numPoints: 15));
  lShape.addAll(generateWallPoints(4, 2, 2, 2, numPoints: 15));
  lShape.addAll(generateWallPoints(2, 2, 2, 3, numPoints: 10));
  lShape.addAll(generateWallPoints(2, 3, 0, 3, numPoints: 15));
  lShape.addAll(generateWallPoints(0, 3, 0, 0, numPoints: 20));

  _runTest(lShape, expectedArea: 10.0, expectedCorners: 6);

  // ===== 테스트 3: 사선 벽 (오각형) =====
  print('\n--- 테스트 3: 사선 벽이 있는 오각형 ---');
  // (0,0)-(3,0)-(4,2)-(2,4)-(0,3)
  final pentagon = <Point3D>[];
  pentagon.addAll(generateWallPoints(0, 0, 3, 0, numPoints: 20));
  pentagon.addAll(generateWallPoints(3, 0, 4, 2, numPoints: 15)); // 사선!
  pentagon.addAll(generateWallPoints(4, 2, 2, 4, numPoints: 15)); // 사선!
  pentagon.addAll(generateWallPoints(2, 4, 0, 3, numPoints: 15)); // 사선!
  pentagon.addAll(generateWallPoints(0, 3, 0, 0, numPoints: 20));

  // Shoelace로 실제 면적 계산
  final pentCorners = [Point3D(0,0,0), Point3D(3,0,0), Point3D(4,0,2), Point3D(2,0,4), Point3D(0,0,3)];
  final pentArea = calcArea(pentCorners);
  print('실제 면적: ${pentArea.toStringAsFixed(1)} m²');

  _runTest(pentagon, expectedArea: pentArea, expectedCorners: 5);

  // ===== 테스트 4: 노이즈 많은 직사각형 =====
  print('\n--- 테스트 4: 노이즈 많은 4x3 직사각형 (10cm 노이즈) ---');
  final noisy = <Point3D>[];
  noisy.addAll(generateWallPoints(0, 0, 4, 0, numPoints: 30, noise: 0.10));
  noisy.addAll(generateWallPoints(4, 0, 4, 3, numPoints: 25, noise: 0.10));
  noisy.addAll(generateWallPoints(4, 3, 0, 3, numPoints: 30, noise: 0.10));
  noisy.addAll(generateWallPoints(0, 3, 0, 0, numPoints: 25, noise: 0.10));

  _runTest(noisy, expectedArea: 12.0, expectedCorners: 4);

  // ===== 테스트 5: 긴 벽 (10m x 3m) =====
  print('\n--- 테스트 5: 긴 벽 10m x 3m ---');
  final longRoom = <Point3D>[];
  longRoom.addAll(generateWallPoints(0, 0, 10, 0, numPoints: 50));
  longRoom.addAll(generateWallPoints(10, 0, 10, 3, numPoints: 15));
  longRoom.addAll(generateWallPoints(10, 3, 0, 3, numPoints: 50));
  longRoom.addAll(generateWallPoints(0, 3, 0, 0, numPoints: 15));

  _runTest(longRoom, expectedArea: 30.0, expectedCorners: 4);

  // ============================================================
  // 하드코어 테스트: 꺾인 다각형 방
  // ============================================================
  print('\n${"=" * 60}');
  print('하드코어 테스트: 꺾인 다각형 방');
  print('=' * 60);

  // ===== 테스트 6: T자형 방 (8코너) =====
  //   (1,3)---(3,3)
  //     |       |
  // (0,2)-(1,2) (3,2)-(4,2)
  //   |               |
  // (0,0)-----------(4,0)
  print('\n--- 테스트 6: T자형 방 (8코너) ---');
  final tShape = <Point3D>[];
  tShape.addAll(generateWallPoints(0, 0, 4, 0, numPoints: 25));
  tShape.addAll(generateWallPoints(4, 0, 4, 2, numPoints: 15));
  tShape.addAll(generateWallPoints(4, 2, 3, 2, numPoints: 10));
  tShape.addAll(generateWallPoints(3, 2, 3, 3, numPoints: 10));
  tShape.addAll(generateWallPoints(3, 3, 1, 3, numPoints: 15));
  tShape.addAll(generateWallPoints(1, 3, 1, 2, numPoints: 10));
  tShape.addAll(generateWallPoints(1, 2, 0, 2, numPoints: 10));
  tShape.addAll(generateWallPoints(0, 2, 0, 0, numPoints: 15));
  final tArea = 4.0 * 2.0 + 2.0 * 1.0; // 8 + 2 = 10
  print('실제 면적: $tArea m²');
  _runTest(tShape, expectedArea: tArea, expectedCorners: 8);

  // ===== 테스트 7: ㄷ자형 방 (8코너) =====
  // (0,4)-----------(5,4)
  //   |               |
  // (0,3)-(3,3) (3,1)-(5,1)
  //         |     |
  // (0,0)-(3,0)-(3,0)
  // 실제: (0,0)-(5,0)-(5,1)-(3,1)-(3,3)-(5,3) 아님
  // 좀 더 정확히:
  // (0,0)-(5,0)-(5,4)-(0,4)-(0,3)-(3,3)-(3,1)-(0,1)
  print('\n--- 테스트 7: ㄷ자형 방 (8코너) ---');
  final uShape = <Point3D>[];
  uShape.addAll(generateWallPoints(0, 0, 5, 0, numPoints: 30));
  uShape.addAll(generateWallPoints(5, 0, 5, 4, numPoints: 25));
  uShape.addAll(generateWallPoints(5, 4, 0, 4, numPoints: 30));
  uShape.addAll(generateWallPoints(0, 4, 0, 3, numPoints: 10));
  uShape.addAll(generateWallPoints(0, 3, 3, 3, numPoints: 20));
  uShape.addAll(generateWallPoints(3, 3, 3, 1, numPoints: 15));
  uShape.addAll(generateWallPoints(3, 1, 0, 1, numPoints: 20));
  uShape.addAll(generateWallPoints(0, 1, 0, 0, numPoints: 10));
  // 면적 = 5*4 - 3*2 = 14
  _runTest(uShape, expectedArea: 14.0, expectedCorners: 8);

  // ===== 테스트 8: 45도 사선 벽이 여러 개인 팔각형 =====
  // 정팔각형 근사 (반지름 3m)
  print('\n--- 테스트 8: 정팔각형 (반지름 3m) ---');
  final octagon = <Point3D>[];
  final octCorners = <Point3D>[];
  for (int i = 0; i < 8; i++) {
    final angle = i * math.pi / 4;
    octCorners.add(Point3D(3 * math.cos(angle), 0, 3 * math.sin(angle)));
  }
  for (int i = 0; i < 8; i++) {
    final j = (i + 1) % 8;
    octagon.addAll(generateWallPoints(
      octCorners[i].x, octCorners[i].z,
      octCorners[j].x, octCorners[j].z,
      numPoints: 15));
  }
  final octArea = calcArea(octCorners);
  print('실제 면적: ${octArea.toStringAsFixed(1)} m²');
  _runTest(octagon, expectedArea: octArea, expectedCorners: 8);

  // ===== 테스트 9: 지그재그 복도형 (10코너) =====
  // (0,0)-(2,0)-(2,1)-(4,1)-(4,0)-(6,0)-(6,2)-(4,2)-(4,1.5 아님)
  // 단순화: 계단형
  // (0,0)-(2,0)-(2,1)-(4,1)-(4,2)-(0,2)
  print('\n--- 테스트 9: 계단형 방 (6코너, 사선 없는 꺾임) ---');
  final stair = <Point3D>[];
  stair.addAll(generateWallPoints(0, 0, 2, 0, numPoints: 15));
  stair.addAll(generateWallPoints(2, 0, 2, 1, numPoints: 10));
  stair.addAll(generateWallPoints(2, 1, 4, 1, numPoints: 15));
  stair.addAll(generateWallPoints(4, 1, 4, 2, numPoints: 10));
  stair.addAll(generateWallPoints(4, 2, 0, 2, numPoints: 25));
  stair.addAll(generateWallPoints(0, 2, 0, 0, numPoints: 15));
  // 면적 = 2*1 + 2*2 = 2+4 = 아님. 2*2 + 2*1 = 6
  // Shoelace: (0,0)(2,0)(2,1)(4,1)(4,2)(0,2) = 6
  final stairCorners = [Point3D(0,0,0), Point3D(2,0,0), Point3D(2,0,1), Point3D(4,0,1), Point3D(4,0,2), Point3D(0,0,2)];
  final stairArea = calcArea(stairCorners);
  print('실제 면적: ${stairArea.toStringAsFixed(1)} m²');
  _runTest(stair, expectedArea: stairArea, expectedCorners: 6);

  // ===== 테스트 10: 극심한 노이즈 (15cm) + 점 적음 =====
  print('\n--- 테스트 10: 극심한 노이즈 15cm + 점 적음 (4x3) ---');
  final extreme = <Point3D>[];
  extreme.addAll(generateWallPoints(0, 0, 4, 0, numPoints: 10, noise: 0.15));
  extreme.addAll(generateWallPoints(4, 0, 4, 3, numPoints: 8, noise: 0.15));
  extreme.addAll(generateWallPoints(4, 3, 0, 3, numPoints: 10, noise: 0.15));
  extreme.addAll(generateWallPoints(0, 3, 0, 0, numPoints: 8, noise: 0.15));
  _runTest(extreme, expectedArea: 12.0, expectedCorners: 4);

  // ===== 테스트 11: 아주 작은 방 1.5m x 1.2m (화장실) =====
  print('\n--- 테스트 11: 작은 방 1.5m x 1.2m (화장실) ---');
  final small = <Point3D>[];
  small.addAll(generateWallPoints(0, 0, 1.5, 0, numPoints: 12));
  small.addAll(generateWallPoints(1.5, 0, 1.5, 1.2, numPoints: 10));
  small.addAll(generateWallPoints(1.5, 1.2, 0, 1.2, numPoints: 12));
  small.addAll(generateWallPoints(0, 1.2, 0, 0, numPoints: 10));
  _runTest(small, expectedArea: 1.8, expectedCorners: 4);

  // ===== 테스트 12: 30도 사선 벽 + 직각 벽 혼합 (현실적) =====
  // (0,0)-(3,0)-(4.5,1)-(4.5,3)-(0,3) — 한쪽만 사선
  print('\n--- 테스트 12: 30도 사선 + 직각 혼합 ---');
  final mixed = <Point3D>[];
  mixed.addAll(generateWallPoints(0, 0, 3, 0, numPoints: 20));
  mixed.addAll(generateWallPoints(3, 0, 4.5, 1, numPoints: 12)); // 30도 사선
  mixed.addAll(generateWallPoints(4.5, 1, 4.5, 3, numPoints: 15));
  mixed.addAll(generateWallPoints(4.5, 3, 0, 3, numPoints: 25));
  mixed.addAll(generateWallPoints(0, 3, 0, 0, numPoints: 20));
  final mixCorners = [Point3D(0,0,0), Point3D(3,0,0), Point3D(4.5,0,1), Point3D(4.5,0,3), Point3D(0,0,3)];
  final mixArea = calcArea(mixCorners);
  print('실제 면적: ${mixArea.toStringAsFixed(1)} m²');
  _runTest(mixed, expectedArea: mixArea, expectedCorners: 5);

  // ===== 테스트 13: 짐이 많은 방 시뮬 (벽 일부만 보임) =====
  // 4x3 방인데 각 벽의 30%만 스캔됨 (짐에 가려서)
  print('\n--- 테스트 13: 짐이 많은 방 (벽 30%만 보임) ---');
  final partial = <Point3D>[];
  // 남벽: 0~1.2m 구간만 보임
  partial.addAll(generateWallPoints(0, 0, 1.2, 0, numPoints: 10));
  // 동벽: 0.5~1.5m 구간만 보임
  partial.addAll(generateWallPoints(4, 0.5, 4, 1.5, numPoints: 8));
  // 북벽: 2.5~4m 구간만 보임
  partial.addAll(generateWallPoints(2.5, 3, 4, 3, numPoints: 10));
  // 서벽: 1~2.5m 구간만 보임
  partial.addAll(generateWallPoints(0, 1, 0, 2.5, numPoints: 10));
  _runTest(partial, expectedArea: 12.0, expectedCorners: 4);

  // ===== 테스트 14: 실제 테스트 환경 (오각형 + 짐 + 노이즈) =====
  // 사용자의 실제 방: 오각형, 짐 많음, 노이즈 8cm
  // (0,0)-(3.5,0)-(4,1.5)-(2.5,3.5)-(0,2.8)
  print('\n--- 테스트 14: 실제 테스트 환경 시뮬 (오각형+짐+노이즈) ---');
  final real = <Point3D>[];
  real.addAll(generateWallPoints(0, 0, 3.5, 0, numPoints: 15, noise: 0.08));
  real.addAll(generateWallPoints(3.5, 0, 4, 1.5, numPoints: 8, noise: 0.08)); // 사선, 점 적음
  real.addAll(generateWallPoints(4, 1.5, 2.5, 3.5, numPoints: 10, noise: 0.08)); // 사선
  real.addAll(generateWallPoints(2.5, 3.5, 0, 2.8, numPoints: 12, noise: 0.08)); // 사선
  real.addAll(generateWallPoints(0, 2.8, 0, 0, numPoints: 12, noise: 0.08));
  final realCorners = [Point3D(0,0,0), Point3D(3.5,0,0), Point3D(4,0,1.5), Point3D(2.5,0,3.5), Point3D(0,0,2.8)];
  final realArea = calcArea(realCorners);
  print('실제 면적: ${realArea.toStringAsFixed(1)} m²');
  _runTest(real, expectedArea: realArea, expectedCorners: 5);
}

void _runTest(List<Point3D> points, {required double expectedArea, required int expectedCorners}) {
  print('입력 점 수: ${points.length}');

  // RANSAC으로 벽 찾기
  final walls = findWallsRANSAC(points);
  print('감지된 벽: ${walls.length}개');
  for (int i = 0; i < walls.length; i++) {
    print('  벽${i+1}: ${walls[i]}');
  }

  // 벽 교차점 = 코너
  final corners = <Point3D>[];
  for (int i = 0; i < walls.length; i++) {
    for (int j = i + 1; j < walls.length; j++) {
      final pt = WallPlane.intersect(walls[i], walls[j]);
      if (pt != null) {
        // 중복 체크
        final isDup = corners.any((c) {
          final dx = c.x - pt.x;
          final dz = c.z - pt.z;
          return dx * dx + dz * dz < 0.25; // 0.5m 이내
        });
        if (!isDup) corners.add(pt);
      }
    }
  }

  if (corners.length >= 3) {
    sortCorners(corners);
  }

  print('감지된 코너: ${corners.length}개 (기대: $expectedCorners)');
  for (int i = 0; i < corners.length; i++) {
    print('  코너${i+1}: ${corners[i]}');
  }

  final area = calcArea(corners);
  final error = ((area - expectedArea) / expectedArea * 100).abs();
  print('계산 면적: ${area.toStringAsFixed(2)} m² (기대: ${expectedArea.toStringAsFixed(1)} m²)');
  print('오차: ${error.toStringAsFixed(1)}%');
  print(error < 5 ? '✓ PASS' : '✗ FAIL (오차 5% 초과)');
}
