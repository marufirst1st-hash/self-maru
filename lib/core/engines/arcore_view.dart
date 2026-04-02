import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ARCore 네이티브 뷰 (Sceneform 없이 직접 ARCore SDK 사용)
/// 카메라 프리뷰 + 평면 감지 + 탭 히트테스트
class ArCoreNativeView extends StatefulWidget {
  final void Function(ArCoreController controller)? onCreated;

  const ArCoreNativeView({super.key, this.onCreated});

  @override
  State<ArCoreNativeView> createState() => _ArCoreNativeViewState();
}

class _ArCoreNativeViewState extends State<ArCoreNativeView> {
  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'com.floormeasure/arcore_view',
      onPlatformViewCreated: (id) {
        final controller = ArCoreController(id);
        widget.onCreated?.call(controller);
      },
    );
  }
}

/// ARCore 컨트롤러 - MethodChannel로 네이티브와 통신
class ArCoreController {
  late final MethodChannel _channel;
  final _planeTapController = StreamController<ArHitResult>.broadcast();
  final _planeDetectedController = StreamController<ArPlaneInfo>.broadcast();
  final _cameraPoseController = StreamController<ArCameraPose>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  bool _sessionCreated = false;

  /// 평면 탭 이벤트 스트림
  Stream<ArHitResult> get onPlaneTap => _planeTapController.stream;

  /// 평면 감지 이벤트 스트림
  Stream<ArPlaneInfo> get onPlaneDetected => _planeDetectedController.stream;

  /// 카메라 포즈 스트림
  Stream<ArCameraPose> get onCameraPose => _cameraPoseController.stream;

  /// AR 에러 스트림
  Stream<String> get onError => _errorController.stream;

  bool get isSessionCreated => _sessionCreated;

  ArCoreController(int viewId) {
    _channel = MethodChannel('com.floormeasure/arcore_$viewId');
    _channel.setMethodCallHandler(_handleMethod);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onPlaneTap':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        _planeTapController.add(ArHitResult(
          x: (data['x'] as num).toDouble(),
          y: (data['y'] as num).toDouble(),
          z: (data['z'] as num).toDouble(),
          distance: (data['distance'] as num).toDouble(),
        ));
      case 'onPlaneDetected':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        _planeDetectedController.add(ArPlaneInfo(
          centerX: (data['centerX'] as num).toDouble(),
          centerY: (data['centerY'] as num).toDouble(),
          centerZ: (data['centerZ'] as num).toDouble(),
          width: (data['width'] as num).toDouble(),
          height: (data['height'] as num).toDouble(),
        ));
      case 'onCameraPose':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        _cameraPoseController.add(ArCameraPose(
          x: (data['x'] as num).toDouble(),
          y: (data['y'] as num).toDouble(),
          z: (data['z'] as num).toDouble(),
        ));
      case 'onArSessionCreated':
        _sessionCreated = true;
      case 'onArError':
        _errorController.add(call.arguments?.toString() ?? 'Unknown AR error');
    }
  }

  Future<void> resume() => _channel.invokeMethod('resume');
  Future<void> pause() => _channel.invokeMethod('pause');

  void dispose() {
    _channel.invokeMethod('dispose');
    _planeTapController.close();
    _planeDetectedController.close();
    _cameraPoseController.close();
    _errorController.close();
  }
}

/// AR 히트 테스트 결과
class ArHitResult {
  final double x, y, z; // 월드 좌표 (미터)
  final double distance; // 카메라까지 거리

  const ArHitResult({
    required this.x,
    required this.y,
    required this.z,
    required this.distance,
  });

  /// 바닥 평면 좌표 (x, z를 2D로)
  Offset get floorPosition => Offset(x, z);
}

/// AR 평면 정보
class ArPlaneInfo {
  final double centerX, centerY, centerZ;
  final double width, height;

  const ArPlaneInfo({
    required this.centerX,
    required this.centerY,
    required this.centerZ,
    required this.width,
    required this.height,
  });
}

/// AR 카메라 포즈
class ArCameraPose {
  final double x, y, z;

  const ArCameraPose({required this.x, required this.y, required this.z});

  Offset get floorPosition => Offset(x, z);
}
