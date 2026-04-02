import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

/// 카메라 브릿지: 카메라 초기화/프리뷰/캡처/플래시 제어
class CameraBridge {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _initialized = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _initialized;
  bool get isStreaming => _controller?.value.isStreamingImages ?? false;

  /// 카메라 초기화
  Future<bool> initialize({
    ResolutionPreset resolution = ResolutionPreset.medium,
    bool enableAudio = false,
  }) async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) return false;

      // 후면 카메라 우선
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        resolution,
        enableAudio: enableAudio,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      _initialized = true;
      return true;
    } catch (e) {
      _initialized = false;
      return false;
    }
  }

  /// 카메라 프리뷰 위젯
  Widget? getPreview() {
    if (!_initialized || _controller == null) return null;
    return CameraPreview(_controller!);
  }

  /// 프레임 스트리밍 시작
  /// [onFrame]에 각 프레임의 YUV 데이터 전달
  Future<void> startImageStream(void Function(CameraImage image) onFrame) async {
    if (!_initialized || _controller == null) return;
    if (_controller!.value.isStreamingImages) return;
    await _controller!.startImageStream(onFrame);
  }

  /// 프레임 스트리밍 중단
  Future<void> stopImageStream() async {
    if (_controller?.value.isStreamingImages ?? false) {
      await _controller!.stopImageStream();
    }
  }

  /// 고해상도 사진 캡처
  Future<Uint8List?> capturePhoto() async {
    if (!_initialized || _controller == null) return null;
    try {
      // 스트리밍 중이면 잠시 중단
      final wasStreaming = _controller!.value.isStreamingImages;
      if (wasStreaming) {
        await _controller!.stopImageStream();
      }

      final file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();

      // 스트리밍 재개는 호출자가 결정
      return bytes;
    } catch (e) {
      return null;
    }
  }

  /// 플래시 ON
  Future<void> flashOn() async {
    if (!_initialized || _controller == null) return;
    await _controller!.setFlashMode(FlashMode.torch);
  }

  /// 플래시 OFF
  Future<void> flashOff() async {
    if (!_initialized || _controller == null) return;
    await _controller!.setFlashMode(FlashMode.off);
  }

  /// CameraImage → 밝기 평균 (Y 채널)
  /// Flash Worker의 프레임 차분에 사용
  static double meanBrightness(CameraImage image) {
    if (image.planes.isEmpty) return 0;
    final yPlane = image.planes[0]; // Y (luminance)
    final bytes = yPlane.bytes;
    if (bytes.isEmpty) return 0;

    int sum = 0;
    // 성능을 위해 4px마다 샘플링
    final step = 4;
    int count = 0;
    for (int i = 0; i < bytes.length; i += step) {
      sum += bytes[i];
      count++;
    }
    return count > 0 ? sum / count.toDouble() : 0;
  }

  void dispose() {
    _controller?.dispose();
    _controller = null;
    _initialized = false;
  }
}
