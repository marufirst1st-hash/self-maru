import 'dart:async';
import 'dart:ui';

/// AR Engine: ARCore(Android) / ARKit(iOS) SLAM
/// 공식 ①②
///
/// ar_flutter_plugin을 통해 6DoF 포즈 + 평면 감지.
/// 이 클래스는 AR 세션을 관리하고 이벤트를 스트림으로 노출.
class ArEngine {
  bool _initialized = false;
  bool _running = false;

  final _poseController = StreamController<ArPose>.broadcast();
  final _planeController = StreamController<ArPlane>.broadcast();

  Stream<ArPose> get onPoseUpdate => _poseController.stream;
  Stream<ArPlane> get onPlaneDetected => _planeController.stream;
  bool get isRunning => _running;

  /// AR 세션 초기화
  Future<bool> initialize() async {
    // TODO: ar_flutter_plugin 초기화
    // final arSession = ArSession(...)
    _initialized = true;
    return true;
  }

  /// AR 세션 시작
  void start() {
    if (!_initialized) return;
    _running = true;
    // TODO: AR 프레임 콜백 등록
    // onFrame → _poseController.add(pose)
    // onPlane → _planeController.add(plane)
  }

  /// AR 세션 중단 (재개 가능)
  void pause() {
    _running = false;
  }

  /// AR 포즈 업데이트 (외부에서 주입 가능 - 테스트/시뮬레이션용)
  void injectPose(ArPose pose) {
    if (_running) {
      _poseController.add(pose);
    }
  }

  /// AR 평면 감지 (외부에서 주입 가능)
  void injectPlane(ArPlane plane) {
    if (_running) {
      _planeController.add(plane);
    }
  }

  void dispose() {
    _running = false;
    _initialized = false;
    _poseController.close();
    _planeController.close();
  }
}

/// 6DoF 포즈 데이터
class ArPose {
  final Offset position; // (x, y) 미터 (2D 투영)
  final double z; // 높이 (미터)
  final double heading; // yaw (라디안)
  final double pitch;
  final double roll;
  final double confidence; // 0~1 (tracking quality)
  final DateTime timestamp;

  const ArPose({
    required this.position,
    this.z = 0,
    required this.heading,
    this.pitch = 0,
    this.roll = 0,
    this.confidence = 1.0,
    required this.timestamp,
  });
}

/// 감지된 평면
class ArPlane {
  final String id;
  final ArPlaneType type;
  final Offset center; // (x, y) 미터
  final double width;
  final double height;
  final double normalX, normalY, normalZ; // 법선 벡터

  const ArPlane({
    required this.id,
    required this.type,
    required this.center,
    required this.width,
    required this.height,
    this.normalX = 0,
    this.normalY = 0,
    this.normalZ = 1,
  });

  /// 수직 평면인지 (벽)
  bool get isVertical => normalZ.abs() < 0.3;

  /// 수평 평면인지 (바닥/천장)
  bool get isHorizontal => normalZ.abs() > 0.7;
}

enum ArPlaneType { horizontal, vertical, unknown }
