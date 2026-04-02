import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// AprilTag 검출 + 6DoF 포즈 추출
/// 공식 A①
///
/// opencv_dart의 ArUco 모듈로 AprilTag 36h11 검출
/// solvePnP → 6DoF (위치+회전)
class AprilTagDetector {
  final double markerSizeCm;
  cv.ArucoDetector? _detector;
  bool _initialized = false;

  AprilTagDetector({this.markerSizeCm = 15.0});

  void initialize() {
    if (_initialized) return;
    final dict = cv.ArucoDictionary.predefined(
      cv.PredefinedDictionaryType.DICT_APRILTAG_36h11,
    );
    final params = cv.ArucoDetectorParameters.empty();
    _detector = cv.ArucoDetector.create(dict, params);
    _initialized = true;
  }

  /// BGR Mat에서 태그 검출
  List<TagResult> detectFromMat(cv.Mat image) {
    if (!_initialized) initialize();

    final (corners, ids, _) = _detector!.detectMarkers(image);
    if (ids.length == 0) return [];

    final results = <TagResult>[];
    for (int i = 0; i < ids.length; i++) {
      final tagId = ids[i];
      final markerCorners = corners[i]; // VecPoint2f

      final tagCorners = <Offset>[];
      for (int j = 0; j < markerCorners.length; j++) {
        final pt = markerCorners[j]; // Point2f
        tagCorners.add(Offset(pt.x, pt.y));
      }

      final centerX = tagCorners.map((c) => c.dx).reduce((a, b) => a + b) / 4;
      final centerY = tagCorners.map((c) => c.dy).reduce((a, b) => a + b) / 4;

      results.add(TagResult(
        tagId: tagId,
        position2D: Offset(centerX, centerY),
        imageCorners: tagCorners,
        confidence: 0.95,
        type: _classifyTag(tagId),
      ));
    }

    corners.dispose();
    ids.dispose();
    return results;
  }

  /// CameraImage Y채널 → 검출
  List<TagResult> detectFromYuv(
    Uint8List yBytes,
    int width,
    int height,
  ) {
    if (!_initialized) initialize();

    final mat = cv.Mat.fromList(height, width, cv.MatType.CV_8UC1, yBytes);
    final bgr = cv.cvtColor(mat, cv.COLOR_GRAY2BGR);
    final results = detectFromMat(bgr);
    mat.dispose();
    bgr.dispose();
    return results;
  }

  /// solvePnP: 이미지 코너 + 카메라 파라미터 → 3D 포즈
  TagPose? estimatePose({
    required List<Offset> imageCorners,
    required CameraIntrinsics camera,
    double? markerSize,
  }) {
    final size = (markerSize ?? markerSizeCm) / 2.0;

    final objPoints = cv.Mat.fromList(4, 1, cv.MatType.CV_64FC3, [
      -size, -size, 0.0,
       size, -size, 0.0,
       size,  size, 0.0,
      -size,  size, 0.0,
    ]);

    final imgPoints = cv.Mat.fromList(4, 1, cv.MatType.CV_64FC2, [
      imageCorners[0].dx, imageCorners[0].dy,
      imageCorners[1].dx, imageCorners[1].dy,
      imageCorners[2].dx, imageCorners[2].dy,
      imageCorners[3].dx, imageCorners[3].dy,
    ]);

    final camMat = cv.Mat.fromList(3, 3, cv.MatType.CV_64FC1, [
      camera.fx, 0.0, camera.cx,
      0.0, camera.fy, camera.cy,
      0.0, 0.0, 1.0,
    ]);

    final distCoeffs = cv.Mat.fromList(1, 5, cv.MatType.CV_64FC1, camera.distCoeffs);

    try {
      final (success, rvec, tvec) = cv.solvePnP(
        objPoints, imgPoints, camMat, distCoeffs,
      );

      if (!success) {
        _disposeAll([objPoints, imgPoints, camMat, distCoeffs]);
        return null;
      }

      final tx = tvec.at<double>(0, 0);
      final ty = tvec.at<double>(1, 0);
      final tz = tvec.at<double>(2, 0);
      final distance = math.sqrt(tx * tx + ty * ty + tz * tz) / 100;

      final result = TagPose(
        rvec: [rvec.at<double>(0, 0), rvec.at<double>(1, 0), rvec.at<double>(2, 0)],
        tvec: [tx, ty, tz],
        distance: distance,
        worldPosition: Offset(tx / 100, ty / 100),
      );

      _disposeAll([objPoints, imgPoints, camMat, distCoeffs, rvec, tvec]);
      return result;
    } catch (_) {
      _disposeAll([objPoints, imgPoints, camMat, distCoeffs]);
      return null;
    }
  }

  void _disposeAll(List<cv.Mat> mats) {
    for (final m in mats) {
      m.dispose();
    }
  }

  TagType _classifyTag(int tagId) {
    if (tagId < 100) return TagType.cube;
    if (tagId < 200) return TagType.sticker;
    return TagType.rod;
  }

  void dispose() {
    _detector?.dispose();
    _detector = null;
    _initialized = false;
  }
}

class TagResult {
  final int tagId;
  final Offset position2D;
  final List<Offset> imageCorners;
  final double confidence;
  final TagType type;

  const TagResult({
    required this.tagId,
    required this.position2D,
    this.imageCorners = const [],
    this.confidence = 0.95,
    this.type = TagType.unknown,
  });
}

class TagPose {
  final List<double> rvec;
  final List<double> tvec;
  final double distance;
  final Offset worldPosition;

  const TagPose({
    required this.rvec,
    required this.tvec,
    required this.distance,
    required this.worldPosition,
  });
}

enum TagType { cube, sticker, rod, unknown }

class CameraIntrinsics {
  final double fx, fy;
  final double cx, cy;
  final List<double> distCoeffs;

  const CameraIntrinsics({
    required this.fx,
    required this.fy,
    required this.cx,
    required this.cy,
    this.distCoeffs = const [0, 0, 0, 0, 0],
  });

  factory CameraIntrinsics.estimate(int imageWidth, int imageHeight) {
    final fx = imageWidth * 0.8;
    return CameraIntrinsics(
      fx: fx,
      fy: fx,
      cx: imageWidth / 2.0,
      cy: imageHeight / 2.0,
    );
  }
}
