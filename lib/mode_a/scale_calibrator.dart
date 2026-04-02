import 'apriltag_detector.dart';

/// 스케일 보정: 두 태그 간 실측 거리 vs 계산 거리
/// 공식 A②
class ScaleCalibrator {
  double _scaleFactor = 1.0;
  bool _calibrated = false;

  double get scaleFactor => _scaleFactor;
  bool get isCalibrated => _calibrated;

  /// 두 태그와 막대 실측 길이로 스케일 팩터 계산
  /// rodLengthM: 막대 실제 길이 (미터)
  double calibrate(TagResult tag1, TagResult tag2, double rodLengthM) {
    final measured = _distance3D(tag1.tvec, tag2.tvec) / 100; // cm→m
    if (measured < 0.01) return _scaleFactor; // 너무 가까우면 무시

    _scaleFactor = rodLengthM / measured;
    _calibrated = true;
    return _scaleFactor;
  }

  /// 스케일 팩터를 거리에 적용
  double applyScale(double rawDistance) {
    return rawDistance * _scaleFactor;
  }

  /// 수동 설정
  void setScaleFactor(double factor) {
    _scaleFactor = factor;
    _calibrated = true;
  }

  void reset() {
    _scaleFactor = 1.0;
    _calibrated = false;
  }

  double _distance3D(List<double> a, List<double> b) {
    if (a.length < 3 || b.length < 3) return 0;
    final dx = a[0] - b[0];
    final dy = a[1] - b[1];
    final dz = a[2] - b[2];
    return (dx * dx + dy * dy + dz * dz).abs();
  }
}
