import 'package:flutter/material.dart';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/models/corner.dart';
import '../core/models/room.dart';
import '../core/output/floor_plan_renderer.dart';
import '../core/workers/wall_constraint.dart';
import '../core/workers/merger.dart';
import '../screens/result_screen.dart';

/// Mode A: 마커 정밀 측정
/// ARCore 카메라 위에서 마커 코너를 탭 → 고정밀 코너 등록
class ModeAScreen extends StatefulWidget {
  final String projectName;
  final String? siteName;
  final String? address;

  const ModeAScreen({
    super.key,
    required this.projectName,
    this.siteName,
    this.address,
  });

  @override
  State<ModeAScreen> createState() => _ModeAScreenState();
}

class _ModeAScreenState extends State<ModeAScreen> {
  ArCoreController? _arController;

  final List<Corner> _corners = [];
  double _totalArea = 0;
  double _totalPerimeter = 0;

  final WallConstraint _wallConstraint = WallConstraint();
  final Merger _merger = Merger();
  final List<Room> _completedRooms = [];

  bool _arReady = false;
  String _statusText = 'AR 초기화 중... 바닥을 비추세요';

  @override
  void dispose() {
    _arController?.dispose();
    super.dispose();
  }

  void _onArCoreViewCreated(ArCoreController controller) {
    _arController = controller;

    _arController!.onPlaneTap = _onPlaneTap;
    _arController!.onPlaneDetected = (plane) {
      if (!_arReady && mounted) {
        setState(() {
          _arReady = true;
          _statusText = '마커(큐브/스티커) 위치를 탭하세요';
        });
      }
    };
  }

  void _onPlaneTap(List<ArCoreHitTestResult> hits) {
    if (hits.isEmpty) return;
    final hit = hits.first;
    final pos3d = hit.pose.translation;
    final worldPos = Offset(pos3d.x.toDouble(), pos3d.z.toDouble());

    // 주황색 구 (마커 표시)
    final sphere = ArCoreSphere(
      materials: [ArCoreMaterial(color: const Color(0xFFFF6B35))],
      radius: 0.04,
    );
    final node = ArCoreNode(shape: sphere, position: pos3d);
    _arController?.addArCoreNodeWithAnchor(node);

    // 벽 선 그리기
    if (_corners.isNotEmpty) {
      final prev = _corners.last;
      final prevPos = vm.Vector3(prev.position.dx, pos3d.y.toDouble(), prev.position.dy);
      final cyl = ArCoreCylinder(
        materials: [ArCoreMaterial(color: const Color(0xFFFF6B35).withValues(alpha: 0.7))],
        radius: 0.005,
        height: (pos3d - prevPos).length,
      );
      _arController?.addArCoreNodeWithAnchor(ArCoreNode(shape: cyl, position: (prevPos + pos3d) / 2));
    }

    final corner = Corner(position: worldPos, confidence: 0.95, source: 'marker');

    setState(() {
      _corners.add(corner);
      _recalculate();
      _statusText = '코너 ${_corners.length}개. ${_corners.length < 3 ? "최소 3개 필요" : "완료 가능"}';
    });
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
    final room = Room(corners: corrected, confidence: 0.95, mode: 'A');
    _merger.applyToRoom(room); room.rebuildWalls();
    _completedRooms.add(room);
    _arController?.dispose();
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => ResultScreen(
        rooms: _completedRooms, projectName: widget.projectName,
        siteName: widget.siteName, address: widget.address, mode: 'A',
      ),
    ));
  }

  void _cancelScan() { _arController?.dispose(); Navigator.pop(context); }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFFF6B35);
    return Scaffold(
      body: Stack(
        children: [
          ArCoreView(onArCoreViewCreated: _onArCoreViewCreated, enableTapRecognizer: true, enableUpdateListener: true),

          // 상단
          Positioned(top: 0, left: 0, right: 0,
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
                  child: const Text('A', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.projectName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                if (_arReady) Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF66BB6A))),
              ]),
            )),
          ),

          // 미니맵
          if (_corners.length >= 2)
            Positioned(top: 100, right: 12, child: Container(
              width: 150, height: 150,
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.4))),
              child: ClipRRect(borderRadius: BorderRadius.circular(12), child: CustomPaint(
                painter: FloorPlanRenderer(corners: _corners, showDimensions: true, showArea: _corners.length >= 3, lineColor: color, cornerColor: const Color(0xFFFF5252)),
              )),
            )),

          // 하단
          Positioned(bottom: 0, left: 0, right: 0,
            child: SafeArea(child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_statusText, style: const TextStyle(color: Colors.white, fontSize: 13), textAlign: TextAlign.center),
                if (_corners.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, children: [
                    _chip('코너 ${_corners.length}', color),
                    if (_totalArea > 0) _chip('${_totalArea.toStringAsFixed(2)} m²', const Color(0xFFFFD54F)),
                    if (_totalPerimeter > 0) _chip('둘레 ${_totalPerimeter.toStringAsFixed(1)}m', Colors.white54),
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
