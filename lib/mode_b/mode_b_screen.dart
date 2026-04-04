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

  // === 기준점 (바닥 감지 후 도면 원점) ===
  Offset? _origin;         // 기준점 (world XZ)

  // === Flash 추론 벽 (AR이 벽 못 찾을 때 Flash가 발견) ===
  final List<_WallDir> _flashWalls = [];

  // === 벽 추적 시스템 (기울기 기반) ===
  // 사용자가 벽을 비추면서 걷는 경로 = 벽 선분
  // 벽 선분 2개의 교차점 = 코너
  final List<_WallSegment> _wallSegments = []; // 완성된 벽 선분
  _WallSegmentBuilder? _activeWall; // 현재 추적 중인 벽
  bool _wasLookingAtWall = false;

  // === 도면 시작점 (사용자 탭으로 설정) ===
  Offset? _startPoint;       // 시작 코너 (world XZ)
  double? _startPointY;      // 시작점 Y (3D)
  bool _nearStart = false;   // 시작점 근처로 돌아왔는지

  // === 화면 중앙 상태 표시 (바닥/벽 전환 알림) ===
  String? _centerNotice;
  Timer? _centerNoticeTimer;

  final List<StreamSubscription> _subs = [];

  int _arWaitSeconds = 0;
  Timer? _arWaitTimer;

  String get _statusText {
    if (!_arReady) {
      if (_arWaitSeconds > 15) return 'AR 초기화 중... 밝은 곳에서 바닥을 비추며 흔들어주세요';
      return '바닥을 비추면서 폰을 좌우로 흔들어주세요';
    }
    final floors = _planes.where((p) => p.isFloor).length;
    if (floors == 0) return '바닥을 비춰주세요';
    if (_origin == null) return '바닥 감지 중... 잠시만 기다려주세요';
    if (_startPoint == null) return '코너를 탭해서 시작점을 설정하세요';
    if (_nearStart && _wallSegments.length >= 3) return '시작점 근처! 탭하면 도면 완성';
    if (_wallSegments.isEmpty) return '벽을 천천히 비춰주세요';
    if (_closed) return '도면 완성! ${_area.toStringAsFixed(1)}m²';
    return '벽 ${_wallSegments.length}개 / 코너 ${_corners.length}개';
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
    _centerNoticeTimer?.cancel();
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

    // 탭 → 시작점 설정 / 도면 완성
    _subs.add(controller.onPlaneTap.listen((hit) {
      if (_origin == null) return;
      final tapPt = hit.floorPosition; // (x, z)

      if (_startPoint == null) {
        // 시작점 설정
        setState(() {
          _startPoint = tapPt;
          _startPointY = hit.y;
        });
        _showCenterNotice('시작점 설정!');
        ScanLogger.log('시작점: (${tapPt.dx.toStringAsFixed(2)}, ${tapPt.dy.toStringAsFixed(2)})');
      } else if (_nearStart && _wallSegments.length >= 3) {
        // 시작점 근처에서 탭 → 도면 완성
        _completeRoom();
      }
    }));

    // 매 프레임: 모든 평면 업데이트
    _subs.add(controller.onPlanesUpdated.listen((planes) {
      if (!mounted) return;
      final f = planes.where((p) => p.isFloor).length;
      final w = planes.where((p) => p.isWall).length;
      ScanLogger.logAr('planes', data: {'floors': f, 'walls': w, 'total': planes.length});

      // 기준점 설정: 첫 바닥 평면의 중심 = 도면 원점
      if (_origin == null && f > 0) {
        final floor = planes.firstWhere((p) => p.isFloor);
        _origin = floor.center2D;
        ScanLogger.log('기준점 설정: (${_origin!.dx.toStringAsFixed(2)}, ${_origin!.dy.toStringAsFixed(2)})');
      }

      setState(() {
        _planes = planes;
        _recalculate();
      });
    }));

    // AR 카메라 포즈 → PDR 보정 + Sonar + 벽 추적
    _subs.add(controller.onCameraPose.listen((pos) {
      _pdr.correctPosition(pos);
      _currentPos = pos;
      if (_sonarBridge != null) {
        _sonarBridge!.cameraPos = pos;
        _sonarBridge!.cameraHeading = _currentHeading;
      }

      // === 벽 추적: 폰이 벽을 비추면서 걷는 경로 = 벽 선분 ===
      if (_origin == null) return;
      final lookingAtWall = _pdr.isLookingAtWall;

      if (lookingAtWall && !_wasLookingAtWall) {
        // 바닥→벽 전환: 새 벽 추적 시작
        _activeWall = _WallSegmentBuilder(startPos: pos, startHeading: _currentHeading);
        _showCenterNotice('벽 추적 중...');
        ScanLogger.log('벽추적 시작: pos=(${pos.dx.toStringAsFixed(2)},${pos.dy.toStringAsFixed(2)})');
      } else if (lookingAtWall && _activeWall != null) {
        // 벽 비추는 중: 경로 점 추가
        _activeWall!.addPoint(pos);
      } else if (!lookingAtWall && _wasLookingAtWall && _activeWall != null) {
        // 벽→바닥 전환: 벽 선분 완성
        final seg = _activeWall!.finish(pos);
        if (seg != null && seg.length > 0.3) {
          // 기존 벽과 중복 체크
          final isDup = _wallSegments.any((s) =>
            (s.midpoint - seg.midpoint).distance < 0.5 &&
            _angleDiffAbs(s.direction, seg.direction) < 0.4);
          if (!isDup) {
            _wallSegments.add(seg);
            _showCenterNotice('벽 감지! (${seg.length.toStringAsFixed(1)}m)');
            ScanLogger.log('벽완성: len=${seg.length.toStringAsFixed(2)}m, dir=${seg.direction.toStringAsFixed(2)}');
            if (mounted) setState(() => _recalculate());
          }
        }
        _activeWall = null;
      }
      _wasLookingAtWall = lookingAtWall;

      // 시작점 근처 복귀 감지 (1.0m 이내)
      if (_startPoint != null && _wallSegments.length >= 3) {
        final distToStart = (pos - _startPoint!).distance;
        final wasNear = _nearStart;
        _nearStart = distToStart < 1.0;
        if (_nearStart && !wasNear) {
          _showCenterNotice('시작점 근처! 탭하면 도면 완성');
        }
      }
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

      // 2. Flash 벽 추론: AR이 벽 못 찾아도 Flash가 벽을 발견
      _flashWorker!.inferWallsFromEdges(
        edges: edges,
        cameraPos: _currentPos,
        cameraHeading: _currentHeading,
      );
    }));

    // Flash 추론 벽 수신 → _flashWalls에 추가 → _recalculate
    if (_flashWorker != null) {
      _subs.add(_flashWorker!.inferredWalls.listen((wall) {
        // 기존 Flash 벽과 중복 체크
        final isDup = _flashWalls.any((w) {
          var angleDiff = (w.direction - wall.direction).abs();
          if (angleDiff > math.pi) angleDiff = (angleDiff - 2 * math.pi).abs();
          final sameDir = angleDiff < 0.35 || (angleDiff - math.pi).abs() < 0.35;
          if (!sameDir) return false;
          final dx = w.center.dx - wall.center.dx;
          final dy = w.center.dy - wall.center.dy;
          final perpDist = (dx * math.cos(w.direction) + dy * math.sin(w.direction)).abs();
          return perpDist < 0.5;
        });

        if (!isDup) {
          _flashWalls.add(_WallDir(
            direction: wall.direction,
            center: wall.center,
            extent: wall.distance * 0.5, // 추정 extent
          ));
          ScanLogger.logFlash('벽 추론 성공: dir=${wall.direction.toStringAsFixed(2)}, dist=${wall.distance.toStringAsFixed(2)}m');
          if (mounted) setState(() => _recalculate());
        }
      }));
    }

    // Corner Worker: 네이티브에서 Sobel gradient 분석 결과
    // 코너가 없어도 카메라 위치 기반으로 후보 처리 (닭-달걀 해결)
    _subs.add(controller.onCornerCandidates.listen((candidates) {
      if (_cornerWorker == null) return;
      for (final c in candidates) {
        final grad = (c['gradient'] as num?)?.toDouble() ?? 0;
        final targetCorner = _cornerModels.isNotEmpty ? _cornerModels.first : null;
        _cornerWorker!.processCornerRoi(
          roiPixels: [grad],
          roiSize: 1,
          worldPosition: targetCorner?.position ?? _currentPos,
          pixelToMeter: 0.001,
          cornerId: targetCorner?.id ?? '__camera__',
        );
      }
    }));

    // 연속 hitTest 결과 → 벽/바닥 구분 (디버그 패널용)
    _subs.add(controller.onCenterHit.listen((hit) {
      // 현재 비추는 곳이 벽인지 바닥인지 상태 업데이트
      if (mounted) setState(() {});
    }));

    _subs.add(controller.onError.listen((e) {
      if (mounted) setState(() {});
    }));
  }

  /// 도면 계산: 바닥 폴리곤에서 직접 코너를 추출
  ///
  /// 핵심: 바닥 폴리곤의 "꺾이는 점" = 벽-바닥 코너.
  /// 직선 구간을 벽 법선으로 변환하는 우회 없이, 폴리곤 꺾임점을 바로 코너로 사용.
  /// 오각형이든 L자든 ARCore 바닥 폴리곤 형태 그대로 도면이 됨.
  void _recalculate() {
    final floors = _planes.where((p) => p.isFloor).toList();

    if (floors.isEmpty || _origin == null) {
      if (_cornerModels.isEmpty) _area = 0;
      return;
    }

    // 가장 큰 바닥 폴리곤을 기준으로 코너 추출
    // (여러 바닥 패치 중 가장 넓은 것 = 주 바닥)
    ArPlaneData? mainFloor;
    double maxArea = 0;
    for (final f in floors) {
      final a = f.extentX * f.extentZ;
      if (a > maxArea) { maxArea = a; mainFloor = f; }
    }
    if (mainFloor == null || mainFloor.polygon.length < 3) {
      if (_cornerModels.isEmpty) _area = 0;
      return;
    }

    // 바닥 폴리곤에서 꺾이는 점(코너) 추출
    // 연속 3점의 각도 변화가 클수록 확실한 코너
    final poly = mainFloor.polygon;
    final newCorners = <Offset>[];

    for (int i = 0; i < poly.length; i++) {
      final prev = poly[(i - 1 + poly.length) % poly.length];
      final curr = poly[i];
      final next = poly[(i + 1) % poly.length];

      // 이전→현재, 현재→다음 방향의 각도 차이
      final a1 = math.atan2(curr.dy - prev.dy, curr.dx - prev.dx);
      final a2 = math.atan2(next.dy - curr.dy, next.dx - curr.dx);
      var angleDiff = (a2 - a1).abs();
      if (angleDiff > math.pi) angleDiff = (2 * math.pi - angleDiff);

      // 꺾임이 20도 이상이면 코너 후보
      if (angleDiff > 0.35) { // ~20도
        // 이전 코너와 너무 가까우면(0.3m) 스킵
        final isDup = newCorners.any((c) => (c - curr).distance < 0.3);
        if (!isDup) newCorners.add(curr);
      }
    }

    // 벽 선분 교차점 = 코너 (사용자가 벽을 비추면서 걸은 경로 기반)
    for (int i = 0; i < _wallSegments.length; i++) {
      for (int j = i + 1; j < _wallSegments.length; j++) {
        final pt = _wallSegments[i].intersect(_wallSegments[j]);
        if (pt != null) {
          final isDup = newCorners.any((c) => (c - pt).distance < 0.3);
          if (!isDup) newCorners.add(pt);
        }
      }
    }

    // 벽 선분 끝점도 코너 후보 (벽 1개만 감지된 경우 보조)
    for (final ws in _wallSegments) {
      for (final pt in [ws.start, ws.end]) {
        // 바닥 폴리곤 경계 근처의 끝점만 (1m 이내)
        final nearPoly = poly.any((p) => (p - pt).distance < 1.0);
        if (nearPoly) {
          final isDup = newCorners.any((c) => (c - pt).distance < 0.3);
          if (!isDup) newCorners.add(pt);
        }
      }
    }

    // 코너가 부족하면 직선 구간 끝점도 추가 (보조)
    if (newCorners.length < 3) {
      final segments = _extractStraightSegments(poly);
      for (final seg in segments) {
        if ((seg.end - seg.start).distance < 0.4) continue;
        for (final pt in [seg.start, seg.end]) {
          final isDup = newCorners.any((c) => (c - pt).distance < 0.3);
          if (!isDup) newCorners.add(pt);
        }
      }
    }

    ScanLogger.log('코너추출: poly=${poly.length}점, 꺾임코너=${newCorners.length}개, 벽선분=${_wallSegments.length}개');

    // 정렬 (중심 기준 반시계)
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

  /// Worker에 현재 상태 전달 (코너 있으면 코너 기준, 없으면 카메라 기준)
  void _updateWorkerTargets() {
    if (_sonarBridge != null) {
      // 항상 카메라 위치 갱신
      _sonarBridge!.cameraPos = _currentPos;
      _sonarBridge!.cameraHeading = _currentHeading;

      if (_cornerModels.isNotEmpty) {
        // 코너가 있으면 가장 가까운 코너 기준
        Corner? nearest;
        double minDist = double.infinity;
        for (final c in _cornerModels) {
          final d = (c.position - _currentPos).distance;
          if (d < minDist) { minDist = d; nearest = c; }
        }
        _sonarBridge!.nearestCorner = nearest;
        if (_corners.length >= 2) {
          final dir = _corners[1] - _corners[0];
          final len = dir.distance;
          if (len > 0) {
            _sonarBridge!.directionX = dir.dx / len;
            _sonarBridge!.directionY = dir.dy / len;
          }
        }
      } else {
        // 코너 없으면 카메라 heading 방향으로 측정
        _sonarBridge!.nearestCorner = null;
      }
    }
  }

  /// 바닥 폴리곤에서 직선 구간 추출
  /// 연속된 점들이 같은 방향이면 하나의 직선(벽-바닥 모서리)
  List<_LineSegment> _extractStraightSegments(List<Offset> poly) {
    if (poly.length < 3) return [];
    final segments = <_LineSegment>[];

    Offset segStart = poly[0];
    double segDir = math.atan2(poly[1].dy - poly[0].dy, poly[1].dx - poly[0].dx);

    for (int i = 1; i < poly.length; i++) {
      final next = i + 1 < poly.length ? poly[i + 1] : poly[0];
      final dir = math.atan2(next.dy - poly[i].dy, next.dx - poly[i].dx);

      var angleDiff = (dir - segDir).abs();
      if (angleDiff > math.pi) angleDiff = (angleDiff - 2 * math.pi).abs();

      if (angleDiff > 0.3) {
        // 방향 변경 → 이전 직선 구간 저장
        final len = (poly[i] - segStart).distance;
        if (len > 0.3) {
          segments.add(_LineSegment(segStart, poly[i]));
        }
        segStart = poly[i];
        segDir = dir;
      }
    }
    // 마지막 구간
    final lastPt = poly.last;
    final len = (lastPt - segStart).distance;
    if (len > 0.3) {
      segments.add(_LineSegment(segStart, lastPt));
    }

    return segments;
  }

  void _showCenterNotice(String text) {
    _centerNoticeTimer?.cancel();
    if (mounted) setState(() => _centerNotice = text);
    _centerNoticeTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _centerNotice = null);
    });
  }

  double _angleDiffAbs(double a, double b) {
    var d = (a - b).abs();
    if (d > math.pi) d = (d - 2 * math.pi).abs();
    return d;
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
    // 바닥은 높이가 비슷한 평면을 하나로 간주 (ARCore 패치 여러 개 → 논리적 1개)
    final floorPlanes = _planes.where((p) => p.isFloor).toList();
    final floors = floorPlanes.isEmpty ? 0 : _countLogicalFloors(floorPlanes);
    final walls = _planes.where((p) => p.isWall).length;

    return Scaffold(
      body: Stack(children: [
        // AR 카메라
        Positioned.fill(child: ArCoreNativeView(onCreated: _onArCreated)),

        // 바닥/벽 색칠은 네이티브 GL에서 직접 렌더링

        // === 중앙 상태 알림 (바닥↔벽 전환 시 게임처럼 표시) ===
        if (_centerNotice != null)
          Center(child: IgnorePointer(child: AnimatedOpacity(
            opacity: _centerNotice != null ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: _pdr.isLookingAtWall
                  ? const Color(0xFF448AFF).withValues(alpha: 0.85)
                  : const Color(0xFF66BB6A).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  _pdr.isLookingAtWall ? Icons.vertical_distribute : Icons.grid_on,
                  color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(_centerNotice!, style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
            ),
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
            _debugRow('기울기', _pdr.isLookingAtWall ? '벽' : '바닥', _pdr.isLookingAtWall ? Colors.blue : Colors.green),
            _debugRow('벽선분', '${_wallSegments.length}개', _wallSegments.isNotEmpty ? Colors.purple : Colors.grey),
            _debugRow('기준점', _origin != null ? '설정됨' : '대기', _origin != null ? Colors.green : Colors.grey),
            _debugRow('바닥', '$floors면', floors > 0 ? Colors.green : Colors.grey),
            _debugRow('AR벽', '$walls면', walls > 0 ? Colors.blue : Colors.grey),
            _debugRow('Flash벽', '${_flashWalls.length}면', _flashWalls.isNotEmpty ? Colors.purple : Colors.grey),
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
            _led(_origin != null, '기준'), const SizedBox(width: 3),
            _led(floors > 0, '바닥'), const SizedBox(width: 3),
            _led(walls > 0 || _flashWalls.isNotEmpty, '벽'), const SizedBox(width: 3),
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
                if (walls > 0) _chip('AR벽$walls', const Color(0xFF448AFF)),
                if (_flashWalls.isNotEmpty) _chip('Flash벽${_flashWalls.length}', const Color(0xFFAB47BC)),
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

  /// 높이가 비슷한(0.15m 이내) 바닥 패치를 하나의 논리적 바닥으로 합산
  int _countLogicalFloors(List<ArPlaneData> floorPlanes) {
    if (floorPlanes.isEmpty) return 0;
    final heights = floorPlanes.map((p) => p.cy).toList()..sort();
    int count = 1;
    for (int i = 1; i < heights.length; i++) {
      if ((heights[i] - heights[i - 1]).abs() > 0.15) count++;
    }
    return count;
  }

class _LineSegment {
  final Offset start;
  final Offset end;
  const _LineSegment(this.start, this.end);
}

/// 완성된 벽 선분: 사용자가 벽을 비추면서 걸은 경로
class _WallSegment {
  final Offset start;
  final Offset end;
  final double direction; // 벽 방향 (라디안)
  final double length;

  _WallSegment({required this.start, required this.end})
    : direction = math.atan2(end.dy - start.dy, end.dx - start.dx),
      length = (end - start).distance;

  Offset get midpoint => Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);

  /// 두 벽 선분의 연장 교차점
  Offset? intersect(_WallSegment other) {
    final d1 = end - start;
    final d2 = other.end - other.start;
    final cross = d1.dx * d2.dy - d1.dy * d2.dx;
    if (cross.abs() < 0.05) return null; // 거의 평행

    final d = other.start - start;
    final t = (d.dx * d2.dy - d.dy * d2.dx) / cross;
    final pt = Offset(start.dx + t * d1.dx, start.dy + t * d1.dy);

    // 교차점이 두 선분 근처(8m 이내)에 있어야
    if ((pt - midpoint).distance > 8 || (pt - other.midpoint).distance > 8) return null;
    return pt;
  }
}

/// 벽 선분 빌더: 벽을 비추면서 걷는 동안 경로점 수집
class _WallSegmentBuilder {
  final Offset startPos;
  final double startHeading;
  final List<Offset> _points = [];

  _WallSegmentBuilder({required this.startPos, required this.startHeading}) {
    _points.add(startPos);
  }

  void addPoint(Offset pos) {
    // 이전 점과 0.1m 이상 차이나면 추가
    if (_points.isEmpty || (pos - _points.last).distance > 0.1) {
      _points.add(pos);
    }
  }

  /// 벽 추적 종료 → 벽 선분 생성 (최소제곱 직선 피팅)
  _WallSegment? finish(Offset endPos) {
    _points.add(endPos);
    if (_points.length < 2) return null;

    // 경로가 너무 짧으면 스킵
    final totalLen = (endPos - startPos).distance;
    if (totalLen < 0.3) return null;

    // 최소제곱법으로 직선 피팅 (점들의 주 방향 = 벽 방향)
    // 간단히 시작점과 끝점 사용 (경로가 직선에 가까우므로)
    // 나중에 SVD로 교체 가능
    return _WallSegment(start: _points.first, end: _points.last);
  }
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
