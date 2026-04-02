import 'dart:async';
import 'package:flutter/material.dart';
import '../core/models/corner.dart';
import '../core/models/room.dart';
import '../core/output/floor_plan_renderer.dart';
import '../core/workers/wall_constraint.dart';
import '../core/workers/merger.dart';
import '../screens/result_screen.dart';

/// Mode C 스캔 화면: LiDAR 측정 (iOS 전용)
class ModeCScreen extends StatefulWidget {
  final String projectName;
  final String? siteName;
  final String? address;

  const ModeCScreen({
    super.key,
    required this.projectName,
    this.siteName,
    this.address,
  });

  @override
  State<ModeCScreen> createState() => _ModeCScreenState();
}

class _ModeCScreenState extends State<ModeCScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scanController;

  bool _isScanning = false;
  bool _isCompleted = false;
  double _scanProgress = 0;
  double _confidence = 0;
  final List<Corner> _detectedCorners = [];
  int _pointCount = 0;
  int _planeCount = 0;

  final WallConstraint _wallConstraint = WallConstraint();
  final Merger _merger = Merger();

  Timer? _simTimer;
  int _simStep = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanController.dispose();
    _simTimer?.cancel();
    super.dispose();
  }

  void _startScan() {
    setState(() => _isScanning = true);
    _runSimulation();
  }

  void _runSimulation() {
    final demoCorners = [
      Corner(position: const Offset(0, 0), confidence: 0.95, source: 'lidar'),
      Corner(position: const Offset(5.1, 0), confidence: 0.94, source: 'lidar'),
      Corner(position: const Offset(5.1, 3.8), confidence: 0.93, source: 'lidar'),
      Corner(position: const Offset(0, 3.8), confidence: 0.96, source: 'lidar'),
    ];

    _simStep = 0;
    _simTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _scanProgress = ((_simStep + 1) / 15.0).clamp(0.0, 1.0);
        _pointCount = (_simStep + 1) * 2400;
        _planeCount = (_simStep / 4).floor().clamp(0, 6);
        _confidence = (_scanProgress * 97).clamp(0.0, 97.0);

        if (_simStep < demoCorners.length) {
          _detectedCorners.add(demoCorners[_simStep]);
        }
      });

      _simStep++;
      if (_simStep >= 15) {
        timer.cancel();
        _completeScan();
      }
    });
  }

  void _completeScan() {
    final corrections = _wallConstraint.constrainedOptimize(_detectedCorners);
    _merger.addAll(corrections);

    final room = Room(
      corners: List.from(_detectedCorners),
      confidence: 0.96,
      mode: 'C',
    );
    _merger.applyToRoom(room);

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
              mode: 'C',
            ),
          ),
        );
      }
    });
  }

  void _cancelScan() {
    _simTimer?.cancel();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF7C4DFF);

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
              child: const Text('C', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.projectName,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                _detectedCorners.isEmpty
                    ? _buildEmptyView(color)
                    : CustomPaint(
                        size: Size.infinite,
                        painter: FloorPlanRenderer(
                          corners: _detectedCorners,
                          isScanning: _isScanning,
                          lineColor: color,
                          cornerColor: color,
                        ),
                      ),
                if (_isScanning)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: _buildPointCloudInfo(color),
                  ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: _buildStatusBadge(color),
                ),
              ],
            ),
          ),
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
                  _buildProgress(color),
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
              Icons.radar,
              color: color.withValues(alpha: 0.5 + _pulseController.value * 0.3),
              size: 64,
            ),
          ),
          const SizedBox(height: 24),
          Text('방을 천천히 둘러보세요', style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('LiDAR가 자동으로 3D 스캔합니다', style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildPointCloudInfo(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF151926).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Points: $_pointCount', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          Text('Planes: $_planeCount', style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(Color color) {
    final label = _isCompleted ? '완료' : _isScanning ? 'LiDAR 스캔 중' : '대기';
    final badgeColor = _isCompleted ? const Color(0xFF66BB6A) : _isScanning ? color : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
      ),
      child: Text(
        _isScanning || _isCompleted ? '$label ${_confidence.toStringAsFixed(0)}%' : label,
        style: TextStyle(color: badgeColor, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildProgress(Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('스캔 진행률', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const Spacer(),
          Text('${(_scanProgress * 100).toInt()}%', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: _scanProgress, backgroundColor: const Color(0xFF1E2235), valueColor: AlwaysStoppedAnimation(color), minHeight: 6),
        ),
      ],
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
        icon: const Icon(Icons.radar),
        label: const Text('LiDAR 스캔 시작', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
