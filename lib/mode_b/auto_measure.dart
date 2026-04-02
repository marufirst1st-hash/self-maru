import 'dart:async';
import '../core/engines/ar_engine.dart';
import '../core/engines/pdr_engine.dart';
import '../core/engines/fusion_engine.dart';
import '../core/workers/wall_constraint.dart';
import '../core/workers/merger.dart';
import '../core/workers/flash_worker.dart';
import '../core/workers/sonar_worker.dart';
import '../core/workers/corner_worker.dart';
import '../core/models/room.dart';
import '../core/utils/tier_detector.dart';
import 'wall_detection.dart';

/// Mode B 자동 측정 메인 루프
/// 걸으면 자동 측정 (AR+PDR → 벽→코너→도면)
class AutoMeasure {
  // 엔진
  final ArEngine arEngine;
  final PdrEngine pdrEngine;
  late final FusionEngine fusionEngine;

  // 벽 감지
  final WallDetection wallDetection = WallDetection();

  // Workers
  final WallConstraint wallConstraint = WallConstraint();
  final Merger merger = Merger();
  FlashWorker? flashWorker;
  SonarWorker? sonarWorker;
  CornerWorker? cornerWorker;

  // 구독
  final List<StreamSubscription> _subscriptions = [];

  // 상태
  bool _running = false;
  Room _currentRoom = Room(mode: 'B');
  final _roomController = StreamController<Room>.broadcast();

  Stream<Room> get onRoomUpdate => _roomController.stream;
  Room get currentRoom => _currentRoom;
  bool get isRunning => _running;

  AutoMeasure({
    ArEngine? arEngine,
    PdrEngine? pdrEngine,
  })  : arEngine = arEngine ?? ArEngine(),
        pdrEngine = pdrEngine ?? PdrEngine() {
    fusionEngine = FusionEngine(
      arEngine: this.arEngine,
      pdrEngine: this.pdrEngine,
    );
  }

  /// 측정 시작
  Future<void> start() async {
    if (_running) return;
    _running = true;

    // AR 초기화
    await arEngine.initialize();
    arEngine.start();
    pdrEngine.start();
    fusionEngine.start();

    // Tier에 따라 Worker 활성화
    if (TierDetector.isWorkerEnabled('flash')) {
      flashWorker = FlashWorker();
      flashWorker!.start();
      _subscriptions.add(
        flashWorker!.corrections.listen((c) => merger.onCorrection(c)),
      );
    }

    if (TierDetector.isWorkerEnabled('sonar')) {
      sonarWorker = SonarWorker();
      sonarWorker!.start();
      _subscriptions.add(
        sonarWorker!.corrections.listen((c) => merger.onCorrection(c)),
      );
    }

    if (TierDetector.isWorkerEnabled('corner')) {
      cornerWorker = CornerWorker();
      cornerWorker!.start();
      _subscriptions.add(
        cornerWorker!.corrections.listen((c) => merger.onCorrection(c)),
      );
    }

    // AR 평면 → 벽 감지
    _subscriptions.add(
      arEngine.onPlaneDetected.listen((plane) {
        wallDetection.onPlaneDetected(plane);
        _updateRoom();
      }),
    );

    // PDR 걸음 → 위치 업데이트 (Room은 Fusion 기준)
    _subscriptions.add(
      fusionEngine.onPosition.listen((_) => _updateRoom()),
    );
  }

  void _updateRoom() {
    final corners = wallDetection.corners;
    if (corners.isEmpty) return;

    // Wall Constraint 적용
    final mutableCorners = corners.map((c) => c.copyWith()).toList();
    final corrections = wallConstraint.constrainedOptimize(mutableCorners);
    merger.addAll(corrections);

    // 보정 적용
    _currentRoom = Room(
      corners: mutableCorners,
      confidence: merger.averageConfidence,
      mode: 'B',
    );
    merger.applyToRoom(_currentRoom);
    _currentRoom.rebuildWalls();

    _roomController.add(_currentRoom);
  }

  /// 측정 완료
  Room complete() {
    _running = false;

    // 최종 Wall Constraint
    if (_currentRoom.corners.length >= 3) {
      final finalCorr = wallConstraint.constrainedOptimize(_currentRoom.corners);
      merger.addAll(finalCorr);
      merger.applyToRoom(_currentRoom);
      _currentRoom.rebuildWalls();
    }

    return _currentRoom;
  }

  /// 취소
  void cancel() {
    _running = false;
    _cleanup();
  }

  void _cleanup() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    fusionEngine.stop();
    arEngine.pause();
    pdrEngine.stop();
    flashWorker?.stop();
    sonarWorker?.stop();
    cornerWorker?.stop();
  }

  void dispose() {
    _cleanup();
    arEngine.dispose();
    pdrEngine.dispose();
    fusionEngine.dispose();
    flashWorker?.dispose();
    sonarWorker?.dispose();
    cornerWorker?.dispose();
    wallDetection.clear();
    merger.clear();
    _roomController.close();
  }
}
