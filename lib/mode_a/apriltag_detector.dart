import 'dart:ui';

/// AprilTag 검출 + 6DoF 포즈 추출
/// 공식 A①
///
/// opencv_dart ArUco 모듈로 AprilTag 36h11 검출
/// solvePnP → 6DoF (위치+회전)
class AprilTagDetector {
  // 큐브 크기 (cm) → 마커 실제 크기
  final double cubeSize; // 기본 15cm
  final double stickerSize; // 기본 5cm

  AprilTagDetector({
    this.cubeSize = 15.0,
    this.stickerSize = 5.0,
  });

  /// 카메라 이미지에서 태그 검출
  /// TODO: opencv_dart 연동 시 실제 구현
  List<TagResult> detect(dynamic cameraImage) {
    // opencv_dart:
    // final dict = ArucoDictionary.DICT_APRILTAG_36h11;
    // final markers = detectMarkers(image, dict);
    // markers.map → solvePnP → TagResult
    return [];
  }

  /// solvePnP: 마커 4코너 → 6DoF 포즈
  /// objectPoints: 마커의 3D 좌표 (실제 크기 기준)
  /// imagePoints: 이미지에서의 2D 좌표
  TagResult? solvePnP({
    required int tagId,
    required List<Offset> imageCorners,
    required CameraIntrinsics camera,
    required double markerSizeCm,
  }) {
    if (imageCorners.length != 4) return null;

    // TODO: opencv_dart solvePnP 호출
    // final half = markerSizeCm / 2;
    // objectPoints = [(-half,-half,0), (half,-half,0), (half,half,0), (-half,half,0)]
    // rvec, tvec = solvePnP(objectPoints, imagePoints, K, dist)
    // distance = tvec.norm / 100 (cm→m)

    return null;
  }
}

/// 태그 검출 결과
class TagResult {
  final int tagId;
  final Offset position2D; // 이미지 상 중심 (픽셀)
  final List<double> rvec; // 회전 벡터
  final List<double> tvec; // 이동 벡터 (cm)
  final double distance; // 카메라→태그 거리 (m)
  final double confidence;
  final TagType type;

  const TagResult({
    required this.tagId,
    required this.position2D,
    required this.rvec,
    required this.tvec,
    required this.distance,
    this.confidence = 0.95,
    this.type = TagType.unknown,
  });

  /// 월드 2D 좌표 (미터)
  Offset get worldPosition => Offset(tvec[0] / 100, tvec[1] / 100);
}

enum TagType { cube, sticker, rod, unknown }

/// 카메라 내부 파라미터
class CameraIntrinsics {
  final double fx, fy; // 초점 거리 (픽셀)
  final double cx, cy; // 주점 (픽셀)
  final List<double> distCoeffs; // 왜곡 계수

  const CameraIntrinsics({
    required this.fx,
    required this.fy,
    required this.cx,
    required this.cy,
    this.distCoeffs = const [0, 0, 0, 0, 0],
  });
}
