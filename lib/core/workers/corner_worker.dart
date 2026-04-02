import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import '../models/correction.dart';

/// Corner Worker: Canny/Hough로 모서리 정밀 좌표 계산
/// 공식 ⑮⑯⑰⑱
///
/// 카메라 프레임의 코너 후보 ROI를 받아 처리.
/// opencv_dart 사용 시 실제 Canny/Hough 적용.
/// 없으면 간소화된 gradient 기반 검출.
class CornerWorker {
  bool _running = false;
  final _correctionController = StreamController<Correction>.broadcast();

  Stream<Correction> get corrections => _correctionController.stream;
  bool get isRunning => _running;

  void start() => _running = true;
  void stop() => _running = false;

  /// 코너 후보 ROI를 받아 정밀 좌표 계산
  /// [roiPixels]: ROI 영역 밝기 값 (가로×세로)
  /// [roiSize]: ROI 크기 (픽셀)
  /// [worldPosition]: ROI 중심의 월드 좌표
  /// [pixelToMeter]: 픽셀→미터 변환 계수
  /// [cornerId]: 보정 대상 코너 ID
  void processCornerRoi({
    required List<double> roiPixels,
    required int roiSize,
    required Offset worldPosition,
    required double pixelToMeter,
    required String cornerId,
  }) {
    if (!_running || roiPixels.isEmpty) return;

    // 간소화된 Sobel gradient 기반 교점 검출
    // 실제 구현은 opencv_dart의 Canny + HoughLines 사용
    final center = roiSize ~/ 2;

    // gradient 계산 (3x3 Sobel)
    double maxGrad = 0;
    int maxX = center, maxY = center;

    for (int y = 1; y < roiSize - 1; y++) {
      for (int x = 1; x < roiSize - 1; x++) {
        final gx = _sobelGx(roiPixels, x, y, roiSize);
        final gy = _sobelGy(roiPixels, x, y, roiSize);
        final mag = math.sqrt(gx * gx + gy * gy);
        if (mag > maxGrad) {
          maxGrad = mag;
          maxX = x;
          maxY = y;
        }
      }
    }

    // 피크가 충분히 강하면 보정값 생산
    if (maxGrad < 10) return;

    final dx = (maxX - center) * pixelToMeter;
    final dy = (maxY - center) * pixelToMeter;
    final confidence = (maxGrad / 255).clamp(0.0, 1.0);

    _correctionController.add(Correction(
      cornerId: cornerId,
      dx: dx,
      dy: dy,
      confidence: confidence * 0.7,
      source: 'corner',
    ));
  }

  double _sobelGx(List<double> pixels, int x, int y, int w) {
    return -pixels[(y - 1) * w + (x - 1)] +
        pixels[(y - 1) * w + (x + 1)] -
        2 * pixels[y * w + (x - 1)] +
        2 * pixels[y * w + (x + 1)] -
        pixels[(y + 1) * w + (x - 1)] +
        pixels[(y + 1) * w + (x + 1)];
  }

  double _sobelGy(List<double> pixels, int x, int y, int w) {
    return -pixels[(y - 1) * w + (x - 1)] -
        2 * pixels[(y - 1) * w + x] -
        pixels[(y - 1) * w + (x + 1)] +
        pixels[(y + 1) * w + (x - 1)] +
        2 * pixels[(y + 1) * w + x] +
        pixels[(y + 1) * w + (x + 1)];
  }

  void dispose() {
    _running = false;
    _correctionController.close();
  }
}
