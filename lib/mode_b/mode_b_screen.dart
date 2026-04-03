import 'dart:async';
import 'package:flutter/material.dart';
import '../core/models/corner.dart';
import '../core/models/room.dart';
import '../core/engines/arcore_view.dart';
import '../core/engines/ar_availability.dart';
import '../core/engines/pdr_engine.dart';
import '../core/engines/sensor_bridge.dart';
import '../core/output/floor_plan_renderer.dart';
import '../core/workers/wall_constraint.dart';
import '../core/workers/merger.dart';
import '../screens/result_screen.dart';

/// Mode B: 스마트 측정
/// ARCore 전체화면 → 평면 감지 → 탭으로 코너 → 실시간 도면
/// AR 불가 시 수동 입력 fallback
class ModeBScreen extends StatefulWidget {
  final String projectName;
  final String? siteName;
  final String? address;

  const ModeBScreen({
    super.key,
    required this.projectName,
    this.siteName,
    this.address,
  });

  @override
  State<ModeBScreen> createState() => _ModeBScreenState();
}

class _ModeBScreenState extends State<ModeBScreen> {
  // AR
  ArCoreController? _arController;
  bool _arAvailable = false;
  bool _arReady = false;

  // 코너
  final List<Corner> _corners = [];
  double _totalArea = 0;
  double _totalPerimeter = 0;

  // PDR
  final PdrEngine _pdrEngine = PdrEngine();
  final SensorBridge _sensorBridge = SensorBridge();
  int _stepCount = 0;

  // 보정
  final WallConstraint _wallConstraint = WallConstraint();
  final Merger _merger = Merger();
  final List<Room> _completedRooms = [];

  // 구독
  final List<StreamSubscription> _subs = [];

  String _statusText = '초기화 중...';
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _arAvailable = await ArAvailability.isAvailable();

    // PDR 시작
    _pdrEngine.start();
    _sensorBridge.connect(_pdrEngine);
    _subs.add(_pdrEngine.onStep.listen((step) {
      if (mounted) setState(() => _stepCount = step.stepNumber);
    }));

    setState(() {
      _initialized = true;
      _statusText = _arAvailable
          ? '바닥을 비추며 천천히 움직이세요'
          : '벽 추가 버튼으로 측정하세요';
    });
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _arController?.dispose();
    _sensorBridge.dispose();
    _pdrEngine.dispose();
    super.dispose();
  }

  /// AR 뷰 생성 콜백
  void _onArCreated(ArCoreController controller) {
    _arController = controller;

    _subs.add(controller.onPlaneDetected.listen((_) {
      if (!_arReady && mounted) {
        setState(() {
          _arReady = true;
          _statusText = '평면 감지! 코너 위치를 탭하세요';
        });
      }
    }));

    _subs.add(controller.onPlaneTap.listen((hit) {
      _addCorner(hit.floorPosition);
    }));

    _subs.add(controller.onError.listen((error) {
      if (mounted) {
        setState(() {
          _statusText = 'AR: $error. 벽 추가 버튼으로 수동 입력 가능';
        });
      }
    }));
  }

  /// 코너 추가
  void _addCorner(Offset worldPos) {
    final corner = Corner(
      position: worldPos,
      confidence: _arAvailable ? 0.9 : 0.85,
      source: _arAvailable ? 'arcore' : 'manual',
    );

    setState(() {
      _corners.add(corner);
      _recalculate();
      if (_corners.length < 3) {
        _statusText = '코너 ${_corners.length}개. ${3 - _corners.length}개 더 필요';
      } else {
        _statusText = '${_corners.length}코너 / ${_totalArea.toStringAsFixed(2)}m²';
      }
    });
  }

  /// 수동 벽 입력
  void _showDistanceInput() {
    final lengthCtrl = TextEditingController();
    final angleCtrl = TextEditingController(text: '90');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        decoration: const BoxDecoration(
          color: Color(0xFF151926),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('벽 길이 입력', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: lengthCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                labelText: '벽 길이 (m)', suffixText: 'm',
                filled: true, fillColor: const Color(0xFF1E2235),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: angleCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                labelText: '회전 각도 (°)', suffixText: '°',
                filled: true, fillColor: const Color(0xFF1E2235),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: () {
                  final length = double.tryParse(lengthCtrl.text);
                  if (length == null || length <= 0) return;
                  final angle = double.tryParse(angleCtrl.text) ?? 90;
                  Navigator.pop(ctx);
                  _addCornerByDistance(length, angle);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF26C6DA),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('추가', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addCornerByDistance(double length, double angleDeg) {
    Offset newPos;
    if (_corners.isEmpty) {
      newPos = Offset.zero;
    } else if (_corners.length == 1) {
      newPos = Offset(_corners[0].position.dx + length, _corners[0].position.dy);
    } else {
      final prev = _corners.last.position;
      final prevPrev = _corners[_corners.length - 2].position;
      final prevAngle = (prev - prevPrev).direction;
      final angleRad = angleDeg * 3.14159 / 180;
      final newAngle = prevAngle + (3.14159 - angleRad);
      newPos = Offset(
        prev.dx + length * Offset.fromDirection(newAngle).dx,
        prev.dy + length * Offset.fromDirection(newAngle).dy,
      );
    }
    _addCorner(newPos);
  }

  void _recalculate() {
    if (_corners.length < 3) { _totalArea = 0; _totalPerimeter = 0; return; }
    final pts = _corners.map((c) => c.position).toList();
    double a = 0, p = 0;
    for (int i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      a += pts[i].dx * pts[j].dy - pts[j].dx * pts[i].dy;
      p += (pts[j] - pts[i]).distance;
    }
    _totalArea = a.abs() / 2.0;
    _totalPerimeter = p;
  }

  void _undoLastCorner() {
    if (_corners.isEmpty) return;
    _corners.removeLast();
    setState(() { _recalculate(); _statusText = '코너 ${_corners.length}개'; });
  }

  void _completeRoom() {
    if (_corners.length < 3) return;
    final corrected = _corners.map((c) => c.copyWith()).toList();
    _merger.addAll(_wallConstraint.constrainedOptimize(corrected));
    final room = Room(corners: corrected, confidence: 0.9, mode: 'B');
    _merger.applyToRoom(room); room.rebuildWalls();
    _completedRooms.add(room);

    for (final s in _subs) s.cancel();
    _sensorBridge.disconnect();
    _arController?.dispose();

    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => ResultScreen(rooms: _completedRooms, projectName: widget.projectName,
        siteName: widget.siteName, address: widget.address, mode: 'B'),
    ));
  }

  void _nextRoom() {
    if (_corners.length < 3) return;
    final corrected = _corners.map((c) => c.copyWith()).toList();
    _merger.addAll(_wallConstraint.constrainedOptimize(corrected));
    final room = Room(corners: corrected, confidence: 0.9, mode: 'B');
    _merger.applyToRoom(room); room.rebuildWalls();
    _completedRooms.add(room);

    setState(() { _corners.clear(); _totalArea = 0; _totalPerimeter = 0;
      _statusText = 'Room ${_completedRooms.length + 1}'; });
    _merger.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Room ${_completedRooms.length} 저장'), backgroundColor: const Color(0xFF66BB6A)),
    );
  }

  void _cancelScan() {
    for (final s in _subs) s.cancel();
    _sensorBridge.disconnect();
    _arController?.dispose();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF26C6DA);

    if (!_initialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E1A),
        body: Center(child: CircularProgressIndicator(color: color)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Stack(
        children: [
          // === 배경: AR 또는 검정 ===
          if (_arAvailable)
            Positioned.fill(
              child: ArCoreNativeView(onCreated: _onArCreated),
            )
          else
            Container(color: const Color(0xFF0A0E1A)),

          // === 도면 ===
          if (_corners.isNotEmpty)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 100, 20, 180),
                child: CustomPaint(
                  painter: FloorPlanRenderer(
                    corners: _corners,
                    showDimensions: true,
                    showArea: _corners.length >= 3,
                    lineColor: color,
                    cornerColor: const Color(0xFFFF5252),
                    fillColor: color.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),

          // === 상단 바 ===
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                GestureDetector(onTap: _cancelScan, child: const Icon(Icons.arrow_back, color: Colors.white, size: 22)),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(4)),
                  child: Text(_arAvailable ? 'B-AR' : 'B', style: const TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.projectName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                if (_arReady) Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF66BB6A))),
                if (_stepCount > 0) Padding(padding: const EdgeInsets.only(left: 8), child: Text('$_stepCount걸음', style: const TextStyle(color: Colors.white54, fontSize: 11))),
              ]),
            )),
          ),

          // === 하단 패널 ===
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_statusText, style: const TextStyle(color: Colors.white, fontSize: 13), textAlign: TextAlign.center),
                if (_corners.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, children: [
                    _chip('코너 ${_corners.length}', color),
                    if (_totalArea > 0) _chip('${_totalArea.toStringAsFixed(2)} m²', const Color(0xFFFFD54F)),
                    if (_totalPerimeter > 0) _chip('둘레 ${_totalPerimeter.toStringAsFixed(1)}m', Colors.white54),
                    if (_completedRooms.isNotEmpty) _chip('${_completedRooms.length}방 완료', const Color(0xFF66BB6A)),
                  ]),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  if (_corners.isNotEmpty)
                    GestureDetector(onTap: _undoLastCorner, child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.undo, color: Colors.white54, size: 20), SizedBox(width: 4),
                      Text('되돌리기', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ])),
                  const Spacer(),
                  Padding(padding: const EdgeInsets.only(right: 8), child: SizedBox(height: 40, child: ElevatedButton.icon(
                      onPressed: _showDistanceInput,
                      icon: const Icon(Icons.straighten, size: 16),
                      label: const Text('벽 추가', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ))),
                  if (_corners.length >= 3)
                    Padding(padding: const EdgeInsets.only(right: 8), child: SizedBox(height: 40, child: OutlinedButton(
                      onPressed: _nextRoom,
                      style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: const Text('다음 방', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ))),
                  SizedBox(height: 40, child: ElevatedButton(
                    onPressed: _corners.length >= 3 ? _completeRoom : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _corners.length >= 3 ? const Color(0xFF66BB6A) : Colors.grey.withValues(alpha: 0.3),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: const Text('완료', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  )),
                ]),
              ]),
            )),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}
