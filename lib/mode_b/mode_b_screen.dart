import 'package:flutter/material.dart';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/models/corner.dart';
import '../core/models/room.dart';
import '../core/output/floor_plan_renderer.dart';
import '../core/workers/wall_constraint.dart';
import '../core/workers/merger.dart';
import '../core/engines/pdr_engine.dart';
import '../core/engines/sensor_bridge.dart';
import '../screens/result_screen.dart';

/// Mode B: 스마트 측정
/// ARCore 카메라(전체화면) → 평면 감지 → 탭으로 코너 → 실시간 도면
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
  ArCoreController? _arController;

  final List<Corner> _corners = [];
  double _totalArea = 0;
  double _totalPerimeter = 0;

  // 보조: PDR 걸음 추적
  final PdrEngine _pdrEngine = PdrEngine();
  final SensorBridge _sensorBridge = SensorBridge();
  int _stepCount = 0;

  // 보정
  final WallConstraint _wallConstraint = WallConstraint();
  final Merger _merger = Merger();

  // 다중 방
  final List<Room> _completedRooms = [];

  bool _arReady = false;
  String _statusText = 'AR 초기화 중... 바닥을 비추세요';

  @override
  void dispose() {
    _arController?.dispose();
    _sensorBridge.dispose();
    _pdrEngine.dispose();
    super.dispose();
  }

  void _onArCoreViewCreated(ArCoreController controller) {
    _arController = controller;

    // 평면 탭 → 코너 추가
    _arController!.onPlaneTap = _onPlaneTap;

    // 평면 감지 콜백
    _arController!.onPlaneDetected = (plane) {
      if (!_arReady && mounted) {
        setState(() {
          _arReady = true;
          _statusText = '평면 감지됨! 코너 위치를 탭하세요';
        });
      }
    };

    // PDR 보조 시작
    _pdrEngine.start();
    _sensorBridge.connect(_pdrEngine);
    _pdrEngine.onStep.listen((step) {
      if (mounted) setState(() => _stepCount = step.stepNumber);
    });
  }

  /// 사용자가 평면을 탭 → 3D 좌표 → 코너
  void _onPlaneTap(List<ArCoreHitTestResult> hits) {
    if (hits.isEmpty) return;
    final hit = hits.first;

    // 3D 좌표에서 x, z를 2D 평면 좌표로 사용 (y=높이)
    final pos3d = hit.pose.translation;
    final worldPos = Offset(pos3d.x.toDouble(), pos3d.z.toDouble());

    // 탭 위치에 빨간 구 노드 배치
    final sphere = ArCoreSphere(
      materials: [ArCoreMaterial(color: const Color(0xFFFF5252))],
      radius: 0.03,
    );
    final node = ArCoreNode(
      shape: sphere,
      position: pos3d,
    );
    _arController?.addArCoreNodeWithAnchor(node);

    // 이전 코너와의 거리선 표시 (벽)
    if (_corners.isNotEmpty) {
      final prev = _corners.last;
      final prevPos = vm.Vector3(prev.position.dx, pos3d.y.toDouble(), prev.position.dy);
      _addLine(prevPos, pos3d);
    }

    final corner = Corner(
      position: worldPos,
      confidence: 0.9,
      source: 'arcore',
    );

    setState(() {
      _corners.add(corner);
      _recalculate();

      if (_corners.length == 1) {
        _statusText = '1번 코너. 다음 코너를 탭하세요';
      } else if (_corners.length == 2) {
        _statusText = '2번 코너. 최소 1개 더 필요';
      } else {
        _statusText = '${_corners.length}번 코너 (${_totalArea.toStringAsFixed(2)}m²). 완료 가능!';
      }
    });
  }

  /// 두 점 사이에 얇은 실린더(선) 배치
  void _addLine(vm.Vector3 from, vm.Vector3 to) {
    final mid = (from + to) / 2.0;
    final length = (to - from).length;

    final cylinder = ArCoreCylinder(
      materials: [ArCoreMaterial(color: const Color(0xFF26C6DA).withValues(alpha: 0.8))],
      radius: 0.005,
      height: length,
    );

    // 방향 계산 (기본 실린더는 Y축 방향)
    final node = ArCoreNode(
      shape: cylinder,
      position: mid,
    );
    _arController?.addArCoreNodeWithAnchor(node);
  }

  void _recalculate() {
    if (_corners.length < 3) {
      _totalArea = 0;
      _totalPerimeter = 0;
      return;
    }
    final pts = _corners.map((c) => c.position).toList();
    double area = 0, peri = 0;
    for (int i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      area += pts[i].dx * pts[j].dy - pts[j].dx * pts[i].dy;
      peri += (pts[j] - pts[i]).distance;
    }
    _totalArea = area.abs() / 2.0;
    _totalPerimeter = peri;
  }

  void _undoLastCorner() {
    if (_corners.isEmpty) return;
    _corners.removeLast();
    // ArCore 노드 제거는 복잡하므로 시각적으로만 무시
    setState(() {
      _recalculate();
      _statusText = '코너 ${_corners.length}개';
    });
  }

  void _completeRoom() {
    if (_corners.length < 3) return;

    final corrected = _corners.map((c) => c.copyWith()).toList();
    final corrections = _wallConstraint.constrainedOptimize(corrected);
    _merger.addAll(corrections);

    final room = Room(corners: corrected, confidence: 0.9, mode: 'B');
    _merger.applyToRoom(room);
    room.rebuildWalls();
    _completedRooms.add(room);

    _sensorBridge.disconnect();
    _arController?.dispose();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          rooms: _completedRooms,
          projectName: widget.projectName,
          siteName: widget.siteName,
          address: widget.address,
          mode: 'B',
        ),
      ),
    );
  }

  void _nextRoom() {
    if (_corners.length < 3) return;

    final corrected = _corners.map((c) => c.copyWith()).toList();
    final corrections = _wallConstraint.constrainedOptimize(corrected);
    _merger.addAll(corrections);

    final room = Room(corners: corrected, confidence: 0.9, mode: 'B');
    _merger.applyToRoom(room);
    room.rebuildWalls();
    _completedRooms.add(room);

    setState(() {
      _corners.clear();
      _totalArea = 0;
      _totalPerimeter = 0;
      _statusText = 'Room ${_completedRooms.length + 1} - 코너를 탭하세요';
    });
    _merger.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Room ${_completedRooms.length} 저장됨'),
        backgroundColor: const Color(0xFF66BB6A),
      ),
    );
  }

  void _cancelScan() {
    _sensorBridge.disconnect();
    _arController?.dispose();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF26C6DA);

    return Scaffold(
      body: Stack(
        children: [
          // === ARCore 뷰 (전체화면) ===
          ArCoreView(
            onArCoreViewCreated: _onArCoreViewCreated,
            enableTapRecognizer: true,
            enableUpdateListener: true,
          ),

          // === 상단 바 ===
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _cancelScan,
                      child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('B', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(widget.projectName,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (_arReady)
                      Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF66BB6A))),
                    if (_stepCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text('$_stepCount걸음', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // === 실시간 도면 미니맵 (우상단) ===
          if (_corners.length >= 2)
            Positioned(
              top: 100, right: 12,
              child: Container(
                width: 150, height: 150,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CustomPaint(
                    painter: FloorPlanRenderer(
                      corners: _corners,
                      showDimensions: true,
                      showArea: _corners.length >= 3,
                      lineColor: color,
                      cornerColor: const Color(0xFFFF5252),
                    ),
                  ),
                ),
              ),
            ),

          // === 하단 패널 ===
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 상태
                    Text(_statusText,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textAlign: TextAlign.center),

                    // 정보 칩
                    if (_corners.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          _chip('코너 ${_corners.length}', color),
                          if (_totalArea > 0) _chip('${_totalArea.toStringAsFixed(2)} m²', const Color(0xFFFFD54F)),
                          if (_totalPerimeter > 0) _chip('둘레 ${_totalPerimeter.toStringAsFixed(1)}m', Colors.white54),
                          if (_completedRooms.isNotEmpty) _chip('${_completedRooms.length}방 완료', const Color(0xFF66BB6A)),
                        ],
                      ),
                    ],

                    const SizedBox(height: 10),

                    // 버튼
                    Row(
                      children: [
                        // 되돌리기
                        if (_corners.isNotEmpty)
                          _smallBtn(Icons.undo, '되돌리기', Colors.white54, _undoLastCorner),
                        const Spacer(),
                        // 다음 방
                        if (_corners.length >= 3)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _actionBtn('다음 방', color, _nextRoom),
                          ),
                        // 완료
                        _actionBtn('완료', const Color(0xFF66BB6A), _corners.length >= 3 ? _completeRoom : null),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _smallBtn(IconData icon, String label, Color c, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: c, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color c, VoidCallback? onTap) {
    return SizedBox(
      height: 40,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: onTap != null ? c : c.withValues(alpha: 0.3),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
