import 'dart:math' as math;
import 'dart:ui';

/// 공용 수학 유틸리티
class MathUtils {
  MathUtils._();

  /// Shoelace formula: 다각형 면적 계산 (m²)
  /// 공식 ㉛
  static double shoelace(List<Offset> points) {
    if (points.length < 3) return 0;
    double sum = 0;
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      sum += points[i].dx * points[j].dy;
      sum -= points[j].dx * points[i].dy;
    }
    return sum.abs() / 2.0;
  }

  /// 다각형 둘레 계산 (m)
  static double perimeter(List<Offset> points) {
    if (points.length < 2) return 0;
    double total = 0;
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      total += (points[j] - points[i]).distance;
    }
    return total;
  }

  /// 보상필터 (heading 계산용)
  /// 공식 ⑥
  /// alpha: 자이로 가중치 (기본 0.96)
  static double complementaryFilter(
    double gyroAngle,
    double accelAngle, {
    double alpha = 0.96,
  }) {
    return alpha * gyroAngle + (1 - alpha) * accelAngle;
  }

  /// Weinberg 보폭 추정
  /// 공식 ⑤
  /// K: 보폭 상수 (기본 0.4)
  static double weinbergStepLength(double aMax, double aMin, {double K = 0.4}) {
    final diff = (aMax - aMin).abs();
    return K * math.pow(diff, 0.25);
  }

  /// 가속도 벡터 크기
  /// 공식 ①
  static double magnitude(double ax, double ay, double az) {
    return math.sqrt(ax * ax + ay * ay + az * az);
  }

  /// 중력 분리 LPF
  /// 공식 ②
  static double lowPassFilter(double raw, double prev, {double alpha = 0.8}) {
    return alpha * prev + (1 - alpha) * raw;
  }

  /// 위치 갱신 (PDR)
  /// 공식 ⑦
  static Offset updatePosition(
    Offset current,
    double stepLength,
    double heading,
  ) {
    return Offset(
      current.dx + stepLength * math.sin(heading),
      current.dy + stepLength * math.cos(heading),
    );
  }

  /// 역제곱 법칙으로 거리 추정 (Flash Worker)
  /// 공식 ⑩
  /// K: 캘리브레이션 상수
  static double inverseSquareDistance(double intensity, {double K = 1.0}) {
    if (intensity <= 0) return double.infinity;
    return K / math.sqrt(intensity);
  }

  /// FMCW beat 주파수 → 거리 변환 (Sonar Worker)
  /// 공식 ⑳
  /// T: chirp 길이(초), B: 대역폭(Hz), v: 음속(m/s)
  static double beatFrequencyToDistance(
    double peakFreq, {
    double T = 0.05,
    double B = 4000,
    double v = 343.0,
  }) {
    return peakFreq * v * T / (2 * B);
  }

  /// 두 직선의 교점 (Cramer's rule)
  /// 공식 ⑰
  /// 직선: a*x + b*y + c = 0
  static Offset? lineIntersection(
    double a1, double b1, double c1,
    double a2, double b2, double c2,
  ) {
    final det = a1 * b2 - a2 * b1;
    if (det.abs() < 1e-10) return null; // 평행
    final x = (c1 * b2 - c2 * b1) / det;
    final y = (a1 * c2 - a2 * c1) / det;
    return Offset(x, y);
  }

  /// 각도를 90° 배수로 스냅
  /// 공식 ㉔
  static double snapToRightAngle(double angleRad) {
    final halfPi = math.pi / 2;
    return (angleRad / halfPi).round() * halfPi;
  }

  /// 두 점 사이 각도 (라디안)
  static double angleBetween(Offset from, Offset to) {
    return math.atan2(to.dy - from.dy, to.dx - from.dx);
  }

  /// 도→라디안
  static double degToRad(double deg) => deg * math.pi / 180.0;

  /// 라디안→도
  static double radToDeg(double rad) => rad * 180.0 / math.pi;
}
