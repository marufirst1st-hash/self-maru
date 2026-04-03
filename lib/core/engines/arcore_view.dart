import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ARCore Flutter Texture 기반 뷰
/// PlatformView 대신 Flutter TextureRegistry로 카메라 프리뷰 렌더링
class ArCoreNativeView extends StatefulWidget {
  final void Function(ArCoreController controller)? onCreated;

  const ArCoreNativeView({super.key, this.onCreated});

  @override
  State<ArCoreNativeView> createState() => _ArCoreNativeViewState();
}

class _ArCoreNativeViewState extends State<ArCoreNativeView> {
  static const _channel = MethodChannel('com.floormeasure/arcore');
  int? _textureId;
  late ArCoreController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ArCoreController._(_channel);
    _startAr();
  }

  Future<void> _startAr() async {
    // 화면 크기를 다음 프레임에서 가져옴
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final size = MediaQuery.of(context).size;
      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final width = (size.width * pixelRatio).toInt();
      final height = (size.height * pixelRatio).toInt();

      try {
        debugPrint('ArCore: starting with ${width}x$height');
        final id = await _channel.invokeMethod<int>('start', {
          'width': width,
          'height': height,
        });
        debugPrint('ArCore: textureId=$id');

        if (id != null && id >= 0 && mounted) {
          setState(() => _textureId = id);
          widget.onCreated?.call(_controller);
        } else {
          debugPrint('ArCore: failed to get textureId');
        }
      } catch (e) {
        debugPrint('ArCore: error=$e');
        _controller._errorController.add(e.toString());
      }
    });
  }

  @override
  void dispose() {
    _channel.invokeMethod('stop');
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_textureId == null) {
      return Container(
        color: const Color(0xFF0A0E1A),
        child: const Center(child: CircularProgressIndicator(color: Color(0xFF26C6DA))),
      );
    }
    return GestureDetector(
      onTapDown: (_) {
        // 항상 화면 중앙으로 hitTest (조준점)
        final size = MediaQuery.of(context).size;
        final ratio = MediaQuery.of(context).devicePixelRatio;
        _channel.invokeMethod('tap', {
          'x': size.width / 2 * ratio,
          'y': size.height / 2 * ratio,
        });
      },
      child: Texture(textureId: _textureId!),
    );
  }
}

/// ARCore 컨트롤러
class ArCoreController {
  final MethodChannel _channel;
  final _planeTapController = StreamController<ArHitResult>.broadcast();
  final _planeDetectedController = StreamController<bool>.broadcast();
  final _wallDetectedController = StreamController<ArWall>.broadcast();
  final _floorDetectedController = StreamController<Map<String, double>>.broadcast();
  final _planesUpdatedController = StreamController<List<ArPlaneData>>.broadcast();
  final _flashEdgesController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _cornerCandidatesController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _cameraPoseController = StreamController<Offset>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<ArHitResult> get onPlaneTap => _planeTapController.stream;
  Stream<bool> get onPlaneDetected => _planeDetectedController.stream;
  Stream<ArWall> get onWallDetected => _wallDetectedController.stream;
  Stream<Map<String, double>> get onFloorDetected => _floorDetectedController.stream;
  Stream<List<ArPlaneData>> get onPlanesUpdated => _planesUpdatedController.stream;
  Stream<List<Map<String, dynamic>>> get onFlashEdges => _flashEdgesController.stream;
  Stream<List<Map<String, dynamic>>> get onCornerCandidates => _cornerCandidatesController.stream;
  Stream<Offset> get onCameraPose => _cameraPoseController.stream;
  Stream<String> get onError => _errorController.stream;

  ArCoreController._(this._channel) {
    _channel.setMethodCallHandler(_handle);
  }

  Future<dynamic> _handle(MethodCall call) async {
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
        _planeDetectedController.add(true);
      case 'onWallDetected':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        _wallDetectedController.add(ArWall(
          id: data['id'] as String,
          cx: (data['cx'] as num).toDouble(),
          cy: (data['cy'] as num).toDouble(),
          cz: (data['cz'] as num).toDouble(),
          nx: (data['nx'] as num).toDouble(),
          ny: (data['ny'] as num).toDouble(),
          nz: (data['nz'] as num).toDouble(),
          width: (data['width'] as num).toDouble(),
          height: (data['height'] as num).toDouble(),
        ));
      case 'onFloorDetected':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        _floorDetectedController.add({
          'cx': (data['cx'] as num).toDouble(),
          'cy': (data['cy'] as num).toDouble(),
          'cz': (data['cz'] as num).toDouble(),
        });
      case 'onFlashEdges':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        final edges = (data['edges'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _flashEdgesController.add(edges);
      case 'onCornerCandidates':
        final list = (call.arguments as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _cornerCandidatesController.add(list);
      case 'onPlanesUpdated':
        final list = call.arguments as List;
        final planes = list.map((item) {
          final data = Map<String, dynamic>.from(item as Map);
          final polyRaw = (data['polygon'] as List).cast<num>().map((n) => n.toDouble()).toList();
          // x,y,z,x,y,z,... → List<Offset> (x,z만 사용)
          final poly = <Offset>[];
          for (int i = 0; i < polyRaw.length - 2; i += 3) {
            poly.add(Offset(polyRaw[i], polyRaw[i + 2]));
          }
          return ArPlaneData(
            id: data['id'] as String,
            type: data['type'] as String,
            cx: (data['cx'] as num).toDouble(),
            cy: (data['cy'] as num).toDouble(),
            cz: (data['cz'] as num).toDouble(),
            nx: (data['nx'] as num).toDouble(),
            ny: (data['ny'] as num).toDouble(),
            nz: (data['nz'] as num).toDouble(),
            extentX: (data['extentX'] as num).toDouble(),
            extentZ: (data['extentZ'] as num).toDouble(),
            polygon: poly,
          );
        }).toList();
        _planesUpdatedController.add(planes);
      case 'onCameraPose':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        final x = (data['x'] as num).toDouble();
        final z = (data['z'] as num).toDouble();
        _cameraPoseController.add(Offset(x, z));
      case 'onError':
        _errorController.add(call.arguments?.toString() ?? 'Unknown error');
    }
  }

  void dispose() {
    _planeTapController.close();
    _planeDetectedController.close();
    _wallDetectedController.close();
    _floorDetectedController.close();
    _planesUpdatedController.close();
    _flashEdgesController.close();
    _cornerCandidatesController.close();
    _cameraPoseController.close();
    _errorController.close();
  }
}

class ArHitResult {
  final double x, y, z, distance;
  const ArHitResult({required this.x, required this.y, required this.z, required this.distance});
  Offset get floorPosition => Offset(x, z);
}

/// ARCore가 감지한 수직 평면(벽)
class ArWall {
  final String id;
  final double cx, cy, cz; // 중심 좌표
  final double nx, ny, nz; // 법선 벡터
  final double width, height; // 크기

  const ArWall({
    required this.id, required this.cx, required this.cy, required this.cz,
    required this.nx, required this.ny, required this.nz,
    required this.width, required this.height,
  });

  /// 벽의 2D 시작/끝점 (법선에 수직 방향으로 width/2만큼)
  Offset get start {
    final dx = -nz; final dz = nx; // 법선에 수직
    final len = (dx * dx + dz * dz);
    if (len < 0.001) return Offset(cx, cz);
    final norm = 1.0 / len;
    return Offset(cx - dx * norm * width / 2, cz - dz * norm * width / 2);
  }

  Offset get end {
    final dx = -nz; final dz = nx;
    final len = (dx * dx + dz * dz);
    if (len < 0.001) return Offset(cx, cz);
    final norm = 1.0 / len;
    return Offset(cx + dx * norm * width / 2, cz + dz * norm * width / 2);
  }
}

/// ARCore가 감지한 평면 (바닥/벽/천장)
class ArPlaneData {
  final String id;
  final String type; // 'floor', 'wall', 'ceiling'
  final double cx, cy, cz;
  final double nx, ny, nz;
  final double extentX, extentZ;
  final List<Offset> polygon; // 2D 경계 (x, z)

  const ArPlaneData({
    required this.id, required this.type,
    required this.cx, required this.cy, required this.cz,
    required this.nx, required this.ny, required this.nz,
    required this.extentX, required this.extentZ,
    required this.polygon,
  });

  bool get isFloor => type == 'floor';
  bool get isWall => type == 'wall';
  Offset get center2D => Offset(cx, cz);
}
