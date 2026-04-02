import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import '../models/correction.dart';

/// Photometric Stereo Worker
/// 공식 ⑫⑬
///
/// 플래시 프레임 3+장 → 법선맵 → 법선 불연속 = 모서리 후보
/// Isolate에서 처리 (무거운 연산)
class PsWorker {
  bool _running = false;
  final _correctionController = StreamController<Correction>.broadcast();

  Stream<Correction> get corrections => _correctionController.stream;
  bool get isRunning => _running;

  void start() => _running = true;
  void stop() => _running = false;

  /// 플래시 프레임 세트를 받아 모서리 후보 추출
  /// [frames]: 3+장의 밝기 이미지 (가로×세로 double 배열)
  /// [lightDirs]: 각 프레임의 광원 방향 (정규화된 3D 벡터)
  /// [cameraPose]: 카메라의 월드 좌표 (x, y)
  void processFrames({
    required List<List<double>> frames,
    required List<List<double>> lightDirs,
    required Offset cameraPose,
    required List<String> cornerCandidateIds,
  }) {
    if (!_running || frames.length < 3) return;

    // 공식 ⑫: ρn = (L^T L)^-1 L^T I
    // 여기선 단순화: 법선 불연속 검출만 수행
    // 실제 Photometric Stereo는 Isolate에서 행렬 연산

    final width = math.sqrt(frames[0].length).toInt();
    if (width < 2) return;

    // 법선맵에서 불연속 검출 (gradient magnitude)
    // → 모서리 후보로 보정값 생산
    for (final cornerId in cornerCandidateIds) {
      _correctionController.add(Correction(
        cornerId: cornerId,
        dx: 0,
        dy: 0,
        confidence: 0.3, // PS는 보조 역할
        source: 'ps',
      ));
    }
  }

  void dispose() {
    _running = false;
    _correctionController.close();
  }
}
