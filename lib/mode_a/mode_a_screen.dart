import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../core/models/corner.dart';
import '../core/models/room.dart';
import '../core/engines/camera_bridge.dart';
import '../core/output/floor_plan_renderer.dart';
import '../core/workers/wall_constraint.dart';
import '../core/workers/merger.dart';
import '../screens/result_screen.dart';

/// Mode A 스캔 화면: 마커 정밀 측정
/// 카메라 프리뷰 + AprilTag 인식 (현재는 시뮬레이션 fallback)
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

class _ModeAScreenState extends State<ModeAScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;

  // 카메라
  final CameraBridge _cameraBridge = CameraBridge();
  bool _cameraReady = false;

  // 측정 상태
  bool _isScanning = false;
  bool _isCompleted = false;
  final List<Corner> _detectedCorners = [];
  final List<_DetectedMarker> _detectedMarkers = [];
  double _confidence = 0;

  // 보정
  final WallConstraint _wallConstraint = WallConstraint();
  final Merger _merger = Merger();

  // 시뮬레이션
  Timer? _simTimer;
  int _simStep = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameraReady = await _cameraBridge.initialize(
      resolution: ResolutionPreset.high,
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _simTimer?.cancel();
    _cameraBridge.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() => _isScanning = true);
    // TODO: 실제 AprilTag 검출은 opencv_dart 연동 시 활성화
    // 현재는 시뮬레이션
    _runSimulation();
  }

  void _runSimulation() {
    final demoCorners = [
      Corner(position: const Offset(0, 0), confidence: 0.97, source: 'marker'),
      Corner(position: const Offset(4.8, 0), confidence: 0.96, source: 'marker'),
      Corner(position: const Offset(4.8, 3.6), confidence: 0.95, source: 'marker'),
      Corner(position: const Offset(0, 3.6), confidence: 0.98, source: 'marker'),
    ];

    _simStep = 0;
    _simTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_simStep < demoCorners.length) {
        setState(() {
          _detectedCorners.add(demoCorners[_simStep]);
          _detectedMarkers.add(_DetectedMarker(
            tagId: _simStep,
            type: 'cube',
            position: demoCorners[_simStep].position,
          ));
          _confidence = (_simStep + 1) / demoCorners.length * 95;
        });
      }

      _simStep++;
      if (_simStep >= 8) {
        timer.cancel();
        _completeScan();
      }
    });
  }

  void _completeScan() {
    if (_isCompleted) return;

    final corrections = _wallConstraint.constrainedOptimize(_detectedCorners);
    _merger.addAll(corrections);

    final room = Room(
      corners: List.from(_detectedCorners),
      confidence: _confidence / 100,
      mode: 'A',
    );
    _merger.applyToRoom(room);
    room.rebuildWalls();

    setState(() {
      _isScanning = false;
      _isCompleted = true;
      _confidence = 97;
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ResultScreen(
              rooms: [room],
              projectName: widget.projectName,
              siteName: widget.siteName,
              address: widget.address,
              mode: 'A',
            ),
          ),
        );
      }
    });
  }

  void _cancelScan() {
    _simTimer?.cancel();
    _cameraBridge.stopImageStream();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFFF6B35);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151926),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _cancelScan,
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('A', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.projectName,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 뷰파인더 (카메라 프리뷰 + 도면 오버레이)
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                // 카메라 프리뷰
                if (_cameraReady && _cameraBridge.controller != null)
                  Positioned.fill(
                    child: _cameraBridge.getPreview() ?? const SizedBox(),
                  )
                else
                  Container(color: const Color(0xFF0A0E1A)),

                // 도면 오버레이
                if (_detectedCorners.isNotEmpty)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: FloorPlanRenderer(
                        corners: _detectedCorners,
                        isScanning: _isScanning,
                        lineColor: color,
                        cornerColor: color,
                        fillColor: color.withValues(alpha: 0.08),
                      ),
                    ),
                  )
                else if (!_isScanning)
                  _buildEmptyView(color),

                // 마커 감지 표시
                ..._detectedMarkers.map((m) => Positioned(
                      left: 20,
                      top: 20.0 + _detectedMarkers.indexOf(m) * 28,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Tag #${m.tagId} (${m.type})',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    )),
              ],
            ),
          ),

          // 하단 패널
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF151926),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isScanning || _isCompleted) ...[
                  _buildMarkerStatus(color),
                  const SizedBox(height: 16),
                ],
                _buildActionButton(color),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView(Color color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Icon(
              Icons.qr_code_scanner,
              color: color.withValues(alpha: 0.5 + _pulseController.value * 0.3),
              size: 64,
            ),
          ),
          const SizedBox(height: 24),
          Text('마커를 카메라에 비추세요', style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('큐브를 코너에, 스티커를 벽에 배치하세요', style: TextStyle(color: Colors.grey, fontSize: 13)),
          if (_cameraReady)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 14, color: Color(0xFF66BB6A)),
                  SizedBox(width: 4),
                  Text('카메라 준비됨', style: TextStyle(color: Color(0xFF66BB6A), fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMarkerStatus(Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.qr_code, color: color, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AprilTag 마커 감지', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              Text('${_detectedMarkers.length}개 마커 / ${_detectedCorners.length}개 코너', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const Spacer(),
          Text('${_confidence.toStringAsFixed(0)}%', style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildActionButton(Color color) {
    if (_isScanning) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          onPressed: _cancelScan,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('스캔 중단', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.redAccent,
            side: const BorderSide(color: Colors.redAccent),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _startScan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('마커 스캔 시작', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _DetectedMarker {
  final int tagId;
  final String type;
  final Offset position;

  const _DetectedMarker({
    required this.tagId,
    required this.type,
    required this.position,
  });
}
