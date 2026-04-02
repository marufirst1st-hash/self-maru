import 'dart:async';
import 'dart:ui';

/// LiDAR Engine: ARKit SceneReconstruction → 포인트 클라우드
/// 공식 C①
///
/// iPhone/iPad Pro의 LiDAR 센서 → 깊이맵(256×192) → 3D 점군
/// arkit_plugin 또는 네이티브 Swift 채널 사용
class LidarEngine {
  bool _initialized = false;
  bool _running = false;

  final _pointCloudController = StreamController<PointCloud>.broadcast();
  final _depthMapController = StreamController<DepthMap>.broadcast();

  Stream<PointCloud> get onPointCloud => _pointCloudController.stream;
  Stream<DepthMap> get onDepthMap => _depthMapController.stream;
  bool get isRunning => _running;
  bool get isAvailable => _initialized;

  /// LiDAR 사용 가능 여부 체크 (iOS + LiDAR 하드웨어)
  Future<bool> checkAvailability() async {
    // TODO: 플랫폼 체크 + ARKit LiDAR 지원 확인
    // iOS만 지원, LiDAR 있는 기기만
    return false;
  }

  Future<bool> initialize() async {
    final available = await checkAvailability();
    if (!available) return false;
    // TODO: ARKit SceneReconstruction 초기화
    _initialized = true;
    return true;
  }

  void start() {
    if (!_initialized) return;
    _running = true;
    // TODO: LiDAR 깊이 프레임 콜백 등록
  }

  void stop() {
    _running = false;
  }

  /// 포인트 클라우드 주입 (테스트용)
  void injectPointCloud(PointCloud cloud) {
    if (_running) _pointCloudController.add(cloud);
  }

  void dispose() {
    _running = false;
    _initialized = false;
    _pointCloudController.close();
    _depthMapController.close();
  }
}

/// 3D 포인트 클라우드
class PointCloud {
  final List<Point3D> points;
  final DateTime timestamp;

  const PointCloud({required this.points, required this.timestamp});
}

/// 깊이맵
class DepthMap {
  final int width;
  final int height;
  final List<double> depths; // width × height
  final DateTime timestamp;

  const DepthMap({
    required this.width,
    required this.height,
    required this.depths,
    required this.timestamp,
  });
}

/// 3D 점
class Point3D {
  final double x, y, z;
  final double confidence;

  const Point3D({
    required this.x,
    required this.y,
    required this.z,
    this.confidence = 1.0,
  });

  Offset get xy => Offset(x, y);
}
