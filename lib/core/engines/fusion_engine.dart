import 'dart:async';
import 'dart:ui';
import 'ar_engine.dart';
import 'pdr_engine.dart';

/// Fusion Engine: AR + PDR 가중평균 합산
/// AR 신뢰도가 높으면 AR 우세, 낮으면 PDR 우세
class FusionEngine {
  final ArEngine arEngine;
  final PdrEngine pdrEngine;

  final _positionController = StreamController<FusedPosition>.broadcast();
  Stream<FusedPosition> get onPosition => _positionController.stream;

  StreamSubscription? _arSub;
  StreamSubscription? _pdrSub;

  ArPose? _lastArPose;
  PdrState? _lastPdrState;

  /// AR 가중치 기본값 (0~1, 높을수록 AR 우세)
  double arWeight;

  FusionEngine({
    required this.arEngine,
    required this.pdrEngine,
    this.arWeight = 0.7,
  });

  void start() {
    _arSub = arEngine.onPoseUpdate.listen((pose) {
      _lastArPose = pose;
      // AR heading으로 PDR 보정
      pdrEngine.correctHeading(pose.heading, arConfidence: pose.confidence);
      pdrEngine.correctPosition(pose.position, arConfidence: pose.confidence);
      _fuse();
    });

    _pdrSub = pdrEngine.onPositionUpdate.listen((state) {
      _lastPdrState = state;
      _fuse();
    });
  }

  void _fuse() {
    final ar = _lastArPose;
    final pdr = _lastPdrState;

    if (ar == null && pdr == null) return;

    Offset position;
    double heading;
    double confidence;

    if (ar != null && pdr != null) {
      // 가중 평균
      final w = arWeight * ar.confidence;
      final pdrW = (1 - arWeight);
      final totalW = w + pdrW;

      position = Offset(
        (ar.position.dx * w + pdr.position.dx * pdrW) / totalW,
        (ar.position.dy * w + pdr.position.dy * pdrW) / totalW,
      );
      heading = ar.heading * w / totalW + pdr.heading * pdrW / totalW;
      confidence = (ar.confidence * arWeight + 0.5 * (1 - arWeight));
    } else if (ar != null) {
      position = ar.position;
      heading = ar.heading;
      confidence = ar.confidence;
    } else {
      position = pdr!.position;
      heading = pdr.heading;
      confidence = 0.4; // PDR only
    }

    _positionController.add(FusedPosition(
      position: position,
      heading: heading,
      confidence: confidence,
      source: ar != null && pdr != null
          ? 'fused'
          : ar != null
              ? 'ar'
              : 'pdr',
      timestamp: DateTime.now(),
    ));
  }

  void stop() {
    _arSub?.cancel();
    _pdrSub?.cancel();
  }

  void dispose() {
    stop();
    _positionController.close();
  }
}

class FusedPosition {
  final Offset position;
  final double heading;
  final double confidence;
  final String source; // 'fused', 'ar', 'pdr'
  final DateTime timestamp;

  const FusedPosition({
    required this.position,
    required this.heading,
    required this.confidence,
    required this.source,
    required this.timestamp,
  });
}
