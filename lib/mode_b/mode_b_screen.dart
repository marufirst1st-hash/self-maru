import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/engines/arcore_view.dart';
import '../core/engines/pdr_engine.dart';
import '../core/engines/sensor_bridge.dart';
import '../core/models/corner.dart';
import '../core/models/room.dart';
import '../core/workers/wall_constraint.dart';
import '../core/workers/merger.dart';
import '../core/workers/flash_worker.dart';
import '../core/workers/sonar_worker.dart';
import '../core/workers/sonar_bridge.dart';
import '../core/workers/corner_worker.dart';
import '../core/utils/tier_detector.dart';
import '../core/utils/scan_logger.dart';
import '../screens/result_screen.dart';

/// Mode B: 스마트 측정 (명세서 §7)
///
/// MAIN (30fps): AR + PDR → 벽 인식 → 코너 감지 → 도면 렌더링
/// WORKERS (비동기): Flash + Sonar + Wall + Corner
/// MERGER: 보정값 → 도면 실시간 갱신
class ModeBScreen extends StatefulWidget {
  final String projectName;
  final String? siteName;
  final String? address;

  const ModeBScreen({super.key, required this.projectName, this.siteName, this.address});

  @override
  State<ModeBScreen> createState() => _ModeBScreenState();
}

class _ModeBScreenState extends State<ModeBScreen> with WidgetsBindingObserver {
  // === MAIN: AR + PDR ===
  ArCoreController? _arController;
  bool _arReady = false;
  final PdrEngine _pdr = PdrEngine();
  final SensorBridge _sensorBridge = SensorBridge();

  // === WORKERS ===
  final WallConstraint _wallConstraint = WallConstraint();
  final Merger _merger = Merger();
  FlashWorker? _flashWorker;
  SonarWorker? _sonarWorker;
  SonarBridge? _sonarBridge;
  CornerWorker? _cornerWorker;

  // === 데이터 ===
  List<ArPlaneData> _planes = [];
  List<Corner> _cornerModels = []; // Corner 모델 유지 (id 고정)
  List<Offset> get _corners => _cornerModels.map((c) => c.position).toList();
  double _area = 0;
  bool _closed = false;
  Offset _currentPos = Offset.zero;
  double _currentHeading = 0;
  int _stepCount = 0;
  int _correctionCount = 0;

  final List<StreamSubscription> _subs = [];

  int _arWaitSeconds = 0;
  Timer? _arWaitTimer;

  String get _statusText {
    if (!_arReady) {
      if (_arWaitSeconds > 15) return 'AR 초기화 중... 밝은 곳에서 바닥을 비추며 흔들어주세요';
      return '폰을 들고 좌우로 흔들어주세요';
    }
    final floors = _planes.where((p) => p.isFloor).length;
    final walls = _planes.where((p) => p.isWall).length;
    if (floors == 0) return '바닥을 비춰주세요';
    if (walls == 0) return '바닥 감지! 벽을 비춰주세요';
    if (_corners.isEmpty) return '벽 $walls개. 다른 방향의 벽을 비춰주세요';
    if (_closed) return '도면 완성! ${_area.toStringAsFixed(1)}m²';
    return '코너 ${_corners.length}개 / ${_area.toStringAsFixed(1)}m²';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startWorkers();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _sensorBridge.disconnect();
      _sonarBridge?.stop();
      ScanLogger.log('앱 백그라운드');
    } else if (state == AppLifecycleState.resumed) {
      _pdr.start();
      _sensorBridge.connect(_pdr);
      _sonarBridge?.start();
      ScanLogger.log('앱 포그라운드 복귀');
    }
  }

  /// 명세서 §7: Workers 시작 (Tier에 따라 활성화)
  void _startWorkers() {
    ScanLogger.start();
    ScanLogger.log('Tier: ${TierDetector.detectTier()}');

    // AR 대기 타이머
    _arWaitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_arReady && mounted) setState(() => _arWaitSeconds++);
      if (_arReady) _arWaitTimer?.cancel();
    });

    // PDR 항상 시작
    _pdr.start();
    _sensorBridge.connect(_pdr);
    _subs.add(_pdr.onStep.listen((step) {
      if (!mounted) return;
      ScanLogger.logPdr(step.stepNumber, step.position.dx, step.position.dy);
      setState(() {
        _stepCount = step.stepNumber;
        _currentPos = step.position;
        _currentHeading = step.heading;
      });
    }));

    // Flash Worker (Tier 1,2)
    if (TierDetector.isWorkerEnabled('flash')) {
      _flashWorker = FlashWorker();
      _flashWorker!.start();
      _subs.add(_flashWorker!.corrections.listen((c) {
        _merger.onCorrection(c);
        _correctionCount++;
        _applyCorrections();
        if (mounted) setState(() {});
      }));

      // Flash는 네이티브 ARCore에서 직접 처리 (onFlashEdges)
    }

    // Sonar Worker (Tier 1)
    if (TierDetector.isWorkerEnabled('sonar')) {
      _sonarWorker = SonarWorker();
      _sonarBridge = SonarBridge(sonarWorker: _sonarWorker!);
      _sonarBridge!.start(interval: const Duration(seconds: 3));
      _subs.add(_sonarWorker!.corrections.listen((c) {
        _merger.onCorrection(c);
        _correctionCount++;
        _applyCorrections();
        if (mounted) setState(() {});
      }));
    }

    // Corner Worker (Tier 1,2)
    if (TierDetector.isWorkerEnabled('corner')) {
      _cornerWorker = CornerWorker();
      _cornerWorker!.start();
      _subs.add(_cornerWorker!.corrections.listen((c) {
        _merger.onCorrection(c);
        _correctionCount++;
        _applyCorrections();
        if (mounted) setState(() {});
      }));
    }

    // Wall Constraint: 코너 변경 시 즉시 적용 (아래 _recalculate에서)
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _arWaitTimer?.cancel();
    for (final s in _subs) { s.cancel(); }
    _arController?.dispose();
    _sensorBridge.dispose();
    _pdr.dispose();
    _flashWorker?.dispose();
    _sonarWorker?.dispose();
    _sonarBridge?.dispose();
    _cornerWorker?.dispose();
    super.dispose();
  }

  void _onArCreated(ArCoreController controller) {
    _arController = controller;

    _subs.add(controller.onPlaneDetected.listen((_) {
      if (!_arReady && mounted) { ScanLogger.logAr('평면감지 시작'); setState(() => _arReady = true); }
    }));

    // 매 프레임: 모든 평면 업데이트
    _subs.add(controller.onPlanesUpdated.listen((planes) {
      if (!mounted) return;
      final f = planes.where((p) => p.isFloor).length;
      final w = planes.where((p) => p.isWall).length;
      ScanLogger.logAr('planes', data: {'floors': f, 'walls': w, 'total': planes.length});
      setState(() {
        _planes = planes;
        _recalculate();
      });
    }));

    // AR 카메라 포즈 → PDR 보정
    _subs.add(controller.onCameraPose.listen((pos) {
      _pdr.correctPosition(pos);
    }));

    // Flash 경계 감지 (네이티브에서 명암 분석)
    _subs.add(controller.onFlashEdges.listen((edges) {
      if (edges.isEmpty || _flashWorker == null) return;

      // 1. 코너가 있으면 → 기존 코너 보정
      if (_cornerModels.isNotEmpty) {
        for (final edge in edges) {
          _flashWorker!.processDiff(
            meanIntensity: (edge['strength'] as num?)?.toDouble() ?? 0,
            nearestCornerId: _cornerModels.first.id,
            directionX: edge['direction'] == 'vertical' ? 1 : 0,
            directionY: edge['direction'] == 'horizontal' ? 1 : 0,
          );
        }
      }

      // 2. AR이 벽을 못 찾았는데 Flash가 강한 경계를 감지 → 벽 존재 추론
      final wallCount = _planes.where((p) => p.isWall).length;
      if (wallCount < 2) {
        final strongEdges = edges.where((e) => ((e['strength'] as num?)?.toDouble() ?? 0) > 15).toList();
        if (strongEdges.isNotEmpty) {
          ScanLogger.logFlash('강한 경계 ${strongEdges.length}개 감지 (AR 벽 ${wallCount}개)', diff: strongEdges.first['strength'] as double?);
        }
      }
    }));

    // Corner Worker: 네이티브에서 Sobel gradient 분석 결과
    _subs.add(controller.onCornerCandidates.listen((candidates) {
      if (_cornerWorker != null && _cornerModels.isNotEmpty) {
        for (final c in candidates) {
          final grad = (c['gradient'] as num?)?.toDouble() ?? 0;
          _cornerWorker!.processCornerRoi(
            roiPixels: [grad], // 간략화: gradient 값만 전달
            roiSize: 1,
            worldPosition: _cornerModels.first.position,
            pixelToMeter: 0.001,
            cornerId: _cornerModels.first.id,
          );
        }
      }
    }));

    _subs.add(controller.onError.listen((e) {
      if (mounted) setState(() {});
    }));
  }

  /// 벽 방향 병합 + 교차점 → 코너 + Wall Constraint 즉시 적용
  void _recalculate() {
    final walls = _planes.where((p) => p.isWall).toList();
    final floors = _planes.where((p) => p.isFloor).toList();

    if (floors.isEmpty || walls.length < 2) {
      // 이전 코너가 있으면 유지 (AR 일시적 감지 실패)
      if (_cornerModels.isEmpty) _area = 0;
      return;
    }

    // 작은 벽(0.3m 미만) 필터
    final validWalls = walls.where((w) => w.extentX > 0.3).toList();

    // 벽 방향+위치 병합 (방향이 같아도 위치가 다르면 다른 벽)
    final wallDirs = <_WallDir>[];
    for (final w in validWalls) {
      final dir = math.atan2(w.nz, w.nx);
      bool merged = false;
      for (final wd in wallDirs) {
        var angleDiff = (wd.direction - dir).abs();
        if (angleDiff > math.pi) angleDiff = (angleDiff - 2 * math.pi).abs();
        final sameDir = angleDiff < 0.35 || (angleDiff - math.pi).abs() < 0.35;
        if (!sameDir) continue;

        // 방향이 같아도 벽까지 수직 거리가 0.5m 이상이면 다른 벽 (마주보는 벽)
        final dx = w.center2D.dx - wd.center.dx;
        final dy = w.center2D.dy - wd.center.dy;
        final perpDist = (dx * math.cos(wd.direction) + dy * math.sin(wd.direction)).abs();
        if (perpDist < 0.5) {
          wd.update(w);
          merged = true;
          break;
        }
      }
      if (!merged) {
        wallDirs.add(_WallDir(direction: dir, center: w.center2D, extent: w.extentX));
      }
    }

    if (wallDirs.length < 2) {
      if (_cornerModels.isEmpty) _area = 0;
      return;
    }

    // 벽 너무 많으면 가장 큰 것만 유지 (성능 + 노이즈 방지)
    if (wallDirs.length > 8) {
      wallDirs.sort((a, b) => b.extent.compareTo(a.extent));
      wallDirs.removeRange(8, wallDirs.length);
    }

    // 교차점 = 코너
    final newCorners = <Offset>[];
    for (int i = 0; i < wallDirs.length; i++) {
      for (int j = i + 1; j < wallDirs.length; j++) {
        final pt = _wallIntersection(wallDirs[i], wallDirs[j]);
        if (pt != null) {
          final isDup = newCorners.any((c) => (c - pt).distance < 0.3);
          if (!isDup) newCorners.add(pt);
        }
      }
    }

    // 정렬
    if (newCorners.length >= 3) {
      final cx = newCorners.map((c) => c.dx).reduce((a, b) => a + b) / newCorners.length;
      final cy = newCorners.map((c) => c.dy).reduce((a, b) => a + b) / newCorners.length;
      newCorners.sort((a, b) =>
        math.atan2(a.dy - cy, a.dx - cx).compareTo(math.atan2(b.dy - cy, b.dx - cx)));
    }

    // 기존 코너와 매칭하여 id 유지, 새 코너는 생성
    final updated = <Corner>[];
    for (final pt in newCorners) {
      // 기존 코너 중 가장 가까운 것 (0.5m 이내면 동일)
      Corner? match;
      for (final existing in _cornerModels) {
        if ((existing.position - pt).distance < 0.5) { match = existing; break; }
      }
      if (match != null) {
        updated.add(match.copyWith(position: pt));
      } else {
        updated.add(Corner(position: pt, confidence: 0.8, source: 'arcore'));
      }
    }
    _cornerModels = updated;

    // Wall Constraint 즉시 적용
    if (_cornerModels.length >= 3) {
      final corrections = _wallConstraint.constrainedOptimize(_cornerModels);
      if (corrections.isNotEmpty) {
        _merger.addAll(corrections);
        _applyCorrections();
      }
    }

    // 면적
    _calcArea();

    // 닫힘 판단
    _closed = _corners.length >= 4 && _area > 0.5;

    // Flash/Sonar Worker에 현재 코너 정보 전달
    _updateWorkerTargets();
  }

  /// Merger 보정값 적용 → 코너 위치 갱신 (setState 안에서 호출되므로 setState 안 함)
  void _applyCorrections() {
    if (_cornerModels.isEmpty) return;
    final room = Room(corners: _cornerModels, mode: 'B');
    _merger.applyToRoom(room);
    _calcArea();
  }

  void _calcArea() {
    if (_corners.length < 3) { _area = 0; return; }
    double a = 0;
    for (int i = 0; i < _corners.length; i++) {
      final j = (i + 1) % _corners.length;
      a += _corners[i].dx * _corners[j].dy - _corners[j].dx * _corners[i].dy;
    }
    _area = a.abs() / 2;
  }

  /// Sonar에 가장 가까운 코너 정보 전달
  void _updateWorkerTargets() {
    if (_corners.isEmpty) return;
    if (_sonarBridge != null && _cornerModels.isNotEmpty) {
      _sonarBridge!.nearestCorner = _cornerModels.first;
      final dir = _corners.length >= 2 ? (_corners[1] - _corners[0]) : const Offset(1, 0);
      final len = dir.distance;
      if (len > 0) {
        _sonarBridge!.directionX = dir.dx / len;
        _sonarBridge!.directionY = dir.dy / len;
      }
    }
  }

  Offset? _wallIntersection(_WallDir w1, _WallDir w2) {
    final d1 = w1.direction + math.pi / 2;
    final d2 = w2.direction + math.pi / 2;
    final d1x = math.cos(d1), d1y = math.sin(d1);
    final d2x = math.cos(d2), d2y = math.sin(d2);
    final cross = d1x * d2y - d1y * d2x;
    if (cross.abs() < 0.1) return null;
    final dx = w2.center.dx - w1.center.dx;
    final dy = w2.center.dy - w1.center.dy;
    final t = (dx * d2y - dy * d2x) / cross;
    if (t.abs() > 8) return null; // 일반 방 크기 제한
    return Offset(w1.center.dx + t * d1x, w1.center.dy + t * d1y);
  }

  void _completeRoom() async {
    if (_corners.length < 3) return;

    // 먼저 모든 센서 정지
    for (final s in _subs) { s.cancel(); }
    _sensorBridge.disconnect();
    _flashWorker?.stop();
    _sonarBridge?.stop();
    _cornerWorker?.stop();
    _arController?.dispose();

    ScanLogger.logCorner(_corners.length, _area);
    ScanLogger.log('보정 총 $_correctionCount회');
    ScanLogger.save(); // 비동기지만 기다리지 않음 (네비게이션 우선)

    final room = Room(corners: List.from(_cornerModels), confidence: _merger.averageConfidence.clamp(0.5, 1.0), mode: 'B');
    room.rebuildWalls();

    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResultScreen(
        rooms: [room], projectName: widget.projectName,
        siteName: widget.siteName, address: widget.address, mode: 'B')));
    }
  }

  void _cancelScan() {
    for (final s in _subs) { s.cancel(); }
    _sensorBridge.disconnect();
    _flashWorker?.stop();
    _sonarBridge?.stop();
    _cornerWorker?.stop();
    _arController?.dispose();
    ScanLogger.log('스캔 취소');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF26C6DA);
    final floors = _planes.where((p) => p.isFloor).length;
    final walls = _planes.where((p) => p.isWall).length;

    return Scaffold(
      body: Stack(children: [
        // AR 카메라
        Positioned.fill(child: ArCoreNativeView(onCreated: _onArCreated)),

        // === 평면 오버레이 (바닥=초록, 벽=파랑, 모서리=빨강) ===
        if (_planes.isNotEmpty)
          Positioned.fill(child: IgnorePointer(child: CustomPaint(
            painter: _PlaneOverlayPainter(planes: _planes, corners: _corners, closed: _closed),
          ))),

        // === 디버그 정보 (좌상단, 테스트용) ===
        Positioned(top: 90, left: 12, child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('[ 센서 상태 ]', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _debugRow('AR', _arReady ? '활성' : '대기', _arReady ? Colors.green : Colors.grey),
            _debugRow('PDR', _stepCount > 0 ? '$_stepCount걸음' : '대기', _stepCount > 0 ? Colors.green : Colors.grey),
            _debugRow('Flash', _flashWorker != null ? (_flashWorker!.isRunning ? '측정중' : '대기') : 'OFF', _flashWorker?.isRunning == true ? Colors.orange : Colors.grey),
            _debugRow('Sonar', _sonarWorker != null ? (_sonarWorker!.isRunning ? '측정중' : '대기') : 'OFF', _sonarWorker?.isRunning == true ? Colors.orange : Colors.grey),
            _debugRow('Corner', _cornerWorker != null ? (_cornerWorker!.isRunning ? '분석중' : '대기') : 'OFF', _cornerWorker?.isRunning == true ? Colors.orange : Colors.grey),
            _debugRow('WallConst', '즉시적용', Colors.green),
            _debugRow('Merger', '$_correctionCount보정', _correctionCount > 0 ? Colors.orange : Colors.grey),
            _debugRow('Tier', 'T${TierDetector.detectTier()}', Colors.white),
            const Divider(color: Colors.grey, height: 8),
            _debugRow('바닥', '$floors면', floors > 0 ? Colors.green : Colors.grey),
            _debugRow('벽', '$walls면', walls > 0 ? Colors.blue : Colors.grey),
            _debugRow('코너', '${_corners.length}개', _corners.isNotEmpty ? Colors.red : Colors.grey),
            if (_area > 0) _debugRow('면적', '${_area.toStringAsFixed(2)}m²', Colors.yellow),
          ]),
        )),

        // 미니맵 (우상단)
        if (_corners.length >= 2)
          Positioned(top: 90, right: 12, child: Container(
            width: 140, height: 140,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.4))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(painter: _MiniMapPainter(
                corners: _corners, area: _area, closed: _closed,
                currentPos: _currentPos, color: color))),
          )),

        // 상단 바
        Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Container(
          margin: const EdgeInsets.all(12), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            GestureDetector(onTap: _cancelScan, child: const Icon(Icons.arrow_back, color: Colors.white, size: 22)),
            const SizedBox(width: 8),
            _led(floors > 0, '바닥'), const SizedBox(width: 3),
            _led(walls > 0, '벽'), const SizedBox(width: 3),
            _led(_corners.isNotEmpty, '코너'), const SizedBox(width: 3),
            _led(_stepCount > 0, 'PDR'), const SizedBox(width: 3),
            _led(_correctionCount > 0, '보정'),
            if (_closed) ...[const SizedBox(width: 3), _led(true, '완성')],
          ]),
        ))),

        // 하단
        Positioned(bottom: 0, left: 0, right: 0, child: SafeArea(child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_statusText, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
            if (_planes.isNotEmpty || _stepCount > 0) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 5, children: [
                if (floors > 0) _chip('바닥$floors', const Color(0xFF66BB6A)),
                if (walls > 0) _chip('벽$walls', const Color(0xFF448AFF)),
                if (_corners.isNotEmpty) _chip('코너${_corners.length}', color),
                if (_area > 0) _chip('${_area.toStringAsFixed(1)}m²', const Color(0xFFFFD54F)),
                if (_stepCount > 0) _chip('${_stepCount}걸음', Colors.white54),
                if (_correctionCount > 0) _chip('보정$_correctionCount', const Color(0xFFFF9800)),
              ]),
            ],
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, height: 46, child: ElevatedButton(
              onPressed: _corners.length >= 3 ? _completeRoom : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _closed ? const Color(0xFF66BB6A) : (_corners.length >= 3 ? const Color(0xFF66BB6A).withValues(alpha: 0.7) : Colors.grey.withValues(alpha: 0.3)),
                foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text(_closed ? '도면 완성! 확인하기' : (_corners.length >= 3 ? '현재 상태로 완료' : '방을 둘러보세요'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            )),
          ]),
        ))),
      ]),
    );
  }

  Widget _led(bool on, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: BoxDecoration(
      color: on ? const Color(0xFF66BB6A).withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: TextStyle(color: on ? const Color(0xFF66BB6A) : Colors.grey.withValues(alpha: 0.5), fontSize: 8, fontWeight: FontWeight.bold)),
  );

  Widget _chip(String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(5)),
    child: Text(text, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  Widget _debugRow(String label, String value, Color c) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
      const SizedBox(width: 4),
      Text('$label: ', style: const TextStyle(color: Colors.grey, fontSize: 8)),
      Text(value, style: TextStyle(color: c, fontSize: 8, fontWeight: FontWeight.bold)),
    ]),
  );
}

/// 평면 오버레이: 바닥=초록 반투명, 벽=파랑 반투명, 코너=빨간 점
/// TODO: ARCore 평면 폴리곤을 화면 좌표로 투영하려면 카메라 행렬이 필요
/// 현재는 감지 상태만 화면에 표시
class _PlaneOverlayPainter extends CustomPainter {
  final List<ArPlaneData> planes;
  final List<Offset> corners;
  final bool closed;

  _PlaneOverlayPainter({required this.planes, required this.corners, required this.closed});

  @override
  void paint(Canvas canvas, Size size) {
    // 바닥 감지 표시 (하단에 초록 바)
    final floors = planes.where((p) => p.isFloor).length;
    if (floors > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - 4, size.width, 4),
        Paint()..color = const Color(0xFF66BB6A).withValues(alpha: 0.6),
      );
    }

    // 벽 감지 표시 (벽 개수만큼 상단에 파란 바)
    final walls = planes.where((p) => p.isWall).toList();
    for (int i = 0; i < walls.length; i++) {
      final barWidth = size.width / math.max(walls.length, 4);
      canvas.drawRect(
        Rect.fromLTWH(i * barWidth, 0, barWidth - 2, 4),
        Paint()..color = const Color(0xFF448AFF).withValues(alpha: 0.6),
      );
    }

    // 코너 표시 (화면 가장자리에 빨간 점)
    if (corners.isNotEmpty && corners.length >= 2) {
      // 코너 위치를 화면 비율로 표시 (간략화)
      final allPts = corners;
      double minX = allPts.first.dx, maxX = minX, minY = allPts.first.dy, maxY = minY;
      for (final p in allPts) {
        if (p.dx < minX) minX = p.dx; if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy; if (p.dy > maxY) maxY = p.dy;
      }
      final dw = (maxX - minX).clamp(0.01, 999.0);
      final dh = (maxY - minY).clamp(0.01, 999.0);

      // 화면 중앙에 작게 도면 오버레이
      final cx = size.width / 2, cy = size.height / 2;
      final sc = math.min(size.width * 0.3 / dw, size.height * 0.3 / dh);
      final ox = cx - (minX + dw / 2) * sc;
      final oy = cy + (minY + dh / 2) * sc;
      Offset tc(Offset w) => Offset(w.dx * sc + ox, -w.dy * sc + oy);

      // 연결선
      for (int i = 0; i < corners.length - 1; i++) {
        canvas.drawLine(tc(corners[i]), tc(corners[i + 1]),
          Paint()..color = const Color(0xFF26C6DA).withValues(alpha: 0.5)..strokeWidth = 2);
      }
      if (closed && corners.length >= 3) {
        canvas.drawLine(tc(corners.last), tc(corners.first),
          Paint()..color = const Color(0xFF26C6DA).withValues(alpha: 0.5)..strokeWidth = 2);
      }

      // 코너 점
      for (final c in corners) {
        canvas.drawCircle(tc(c), 4, Paint()..color = const Color(0xFFFF5252).withValues(alpha: 0.7));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _WallDir {
  double direction;
  Offset center;
  double extent;
  int count = 1;
  _WallDir({required this.direction, required this.center, required this.extent});
  void update(ArPlaneData wall) {
    center = Offset((center.dx * count + wall.cx) / (count + 1), (center.dy * count + wall.cz) / (count + 1));
    extent = math.max(extent, wall.extentX);
    count++;
  }
}

/// 미니맵
class _MiniMapPainter extends CustomPainter {
  final List<Offset> corners;
  final double area;
  final bool closed;
  final Offset currentPos;
  final Color color;
  _MiniMapPainter({required this.corners, required this.area, required this.closed, required this.currentPos, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.isEmpty) return;
    final all = [...corners, currentPos];
    double minX = all.first.dx, maxX = minX, minY = all.first.dy, maxY = minY;
    for (final p in all) { if (p.dx < minX) minX = p.dx; if (p.dx > maxX) maxX = p.dx; if (p.dy < minY) minY = p.dy; if (p.dy > maxY) maxY = p.dy; }
    final dw = (maxX - minX).clamp(0.1, 999.0), dh = (maxY - minY).clamp(0.1, 999.0);
    final sc = math.min((size.width - 20) / dw, (size.height - 20) / dh);
    final ox = size.width / 2 - (minX + dw / 2) * sc;
    final oy = size.height / 2 + (minY + dh / 2) * sc;
    Offset tc(Offset w) => Offset(w.dx * sc + ox, -w.dy * sc + oy);

    // 벽
    for (int i = 0; i < corners.length - 1; i++) {
      canvas.drawLine(tc(corners[i]), tc(corners[i + 1]), Paint()..color = color..strokeWidth = 2);
    }
    if (closed && corners.length >= 3) {
      canvas.drawLine(tc(corners.last), tc(corners.first), Paint()..color = color..strokeWidth = 2);
      final path = Path()..moveTo(tc(corners[0]).dx, tc(corners[0]).dy);
      for (int i = 1; i < corners.length; i++) { path.lineTo(tc(corners[i]).dx, tc(corners[i]).dy); }
      path.close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.15));
    }
    // 코너
    for (final c in corners) { canvas.drawCircle(tc(c), 3, Paint()..color = const Color(0xFFFF5252)); }
    // 현재 위치 (파란)
    canvas.drawCircle(tc(currentPos), 4, Paint()..color = const Color(0xFF448AFF));
    // 면적
    if (area > 0) {
      final cx = corners.map((c) => c.dx).reduce((a, b) => a + b) / corners.length;
      final cy = corners.map((c) => c.dy).reduce((a, b) => a + b) / corners.length;
      final tp = TextPainter(text: TextSpan(text: '${area.toStringAsFixed(1)}m²', style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 10, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
      final c = tc(Offset(cx, cy));
      tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
