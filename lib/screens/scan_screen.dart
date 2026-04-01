import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/measurement.dart';
import '../providers/app_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/common_widgets.dart';
import '../widgets/floor_plan_painter.dart';
import 'result_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scanLineController;
  Timer? _simulationTimer;
  bool _isSimulating = false;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanLineController.dispose();
    _simulationTimer?.cancel();
    super.dispose();
  }

  void _startSimulation(AppProvider provider) {
    if (_isSimulating) return;
    setState(() => _isSimulating = true);
    provider.startScanning();

    final demoCorners = [
      Corner(position: const Point3D(x: 0, y: 0), confidence: 97),
      Corner(position: const Point3D(x: 4.8, y: 0), confidence: 96),
      Corner(position: const Point3D(x: 4.8, y: 3.6), confidence: 95),
      Corner(position: const Point3D(x: 0, y: 3.6), confidence: 98),
    ];

    int step = 0;
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (!mounted) { timer.cancel(); return; }

      final progress = (step + 1) / 20.0;
      provider.updateScanProgress(progress.clamp(0.0, 1.0));

      if (step < demoCorners.length) {
        provider.addDetectedCorner(demoCorners[step]);
      }

      if (provider.selectedSystem == MeasurementSystem.systemA && step % 3 == 0) {
        provider.addDetectedMarker(Marker(
          tagId: step,
          type: MarkerType.cube,
          position: Point3D(
            x: _random.nextDouble() * 5,
            y: _random.nextDouble() * 4,
          ),
          confidence: 90 + _random.nextDouble() * 9,
        ));
      }

      step++;
      if (step >= 20) {
        timer.cancel();
        provider.completeScan();
        setState(() => _isSimulating = false);
        if (mounted && provider.activeProject != null) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => ResultScreen(project: provider.activeProject!),
                ),
              );
            }
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final isSystemA = provider.selectedSystem == MeasurementSystem.systemA;
        final color = isSystemA ? AppColors.systemA : AppColors.systemB;
        final isScanning = provider.measurementStatus == MeasurementStatus.scanning;
        final isCompleted = provider.measurementStatus == MeasurementStatus.completed;

        return Scaffold(
          backgroundColor: AppColors.bgDark,
          appBar: AppBar(
            backgroundColor: AppColors.bgCard,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () {
                _simulationTimer?.cancel();
                provider.cancelScan();
                Navigator.pop(context);
              },
            ),
            title: Row(
              children: [
                SystemBadge(isSystemA: isSystemA, isLarge: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    provider.activeProject?.name ?? 'Scanning',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              Expanded(
                flex: 5,
                child: _buildViewfinder(provider, isSystemA, color, isScanning),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isScanning || isCompleted) ...[
                      _buildProgressSection(provider, color),
                      const SizedBox(height: 16),
                    ],
                    if (!isSystemA && (isScanning || isCompleted)) ...[
                      LayerIndicator(
                        activeLayer: provider.layerActive,
                        confidence: provider.confidenceLevel,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (isSystemA && (isScanning || isCompleted)) ...[
                      _buildMarkerStatus(provider),
                      const SizedBox(height: 16),
                    ],
                    _buildActionButton(provider, isSystemA, color, isScanning, isCompleted),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildViewfinder(AppProvider provider, bool isSystemA, Color color, bool isScanning) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFF0A0E1A),
          child: provider.detectedCorners.isEmpty
              ? _buildEmptyViewfinder(isSystemA, color)
              : CustomPaint(
                  painter: FloorPlanPainter(
                    corners: provider.detectedCorners,
                    isScanning: isScanning,
                    scanProgress: provider.scanProgress,
                    showDimensions: true,
                    showArea: provider.detectedCorners.length >= 3,
                  ),
                ),
        ),
        if (isScanning)
          AnimatedBuilder(
            animation: _scanLineController,
            builder: (_, __) {
              return Positioned(
                top: 300 * _scanLineController.value,
                left: 0,
                right: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        color.withValues(alpha: 0.8),
                        color,
                        color.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        Positioned(
          top: 16,
          right: 16,
          child: _buildStatusBadge(provider, color),
        ),
      ],
    );
  }

  Widget _buildEmptyViewfinder(bool isSystemA, Color color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Container(
              width: 120 + _pulseController.value * 10,
              height: 120 + _pulseController.value * 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.3 + _pulseController.value * 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                isSystemA ? Icons.qr_code_scanner : Icons.directions_walk,
                color: color.withValues(alpha: 0.5 + _pulseController.value * 0.3),
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isSystemA ? '마커를 카메라에 비추세요' : '방 주위를 걸어다니세요',
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            isSystemA ? 'AprilTag 마커를 각 코너에 배치하세요' : '천천히 걷으며 방 전체를 스캔하세요',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(AppProvider provider, Color color) {
    final isScanning = provider.measurementStatus == MeasurementStatus.scanning;
    final isCompleted = provider.measurementStatus == MeasurementStatus.completed;
    String label;
    Color badgeColor;
    if (isCompleted) {
      label = '완료';
      badgeColor = AppColors.success;
    } else if (isScanning) {
      label = '스캔 중';
      badgeColor = color;
    } else {
      label = '대기';
      badgeColor = AppColors.textMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isScanning)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) => Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: badgeColor.withValues(alpha: 0.5 + _pulseController.value * 0.5),
                ),
              ),
            )
          else
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(shape: BoxShape.circle, color: badgeColor),
            ),
          Text(label, style: TextStyle(color: badgeColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildProgressSection(AppProvider provider, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('측정 진행률', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const Spacer(),
            Text(
              '${(provider.scanProgress * 100).toInt()}%',
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: provider.scanProgress,
            backgroundColor: AppColors.bgElevated,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.crop_square, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              '감지된 코너: ${provider.detectedCorners.length}개',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            if (provider.currentArea > 0) ...[
              const SizedBox(width: 16),
              const Icon(Icons.square_foot, size: 14, color: AppColors.accent),
              const SizedBox(width: 4),
              Text(
                '현재 면적: ${provider.currentArea.toStringAsFixed(2)} m²',
                style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildMarkerStatus(AppProvider provider) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.systemA.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.qr_code, color: AppColors.systemA, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AprilTag 마커 감지', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              Text('${provider.detectedMarkers.length}개 마커 인식됨', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          const Spacer(),
          Text(
            '${provider.confidenceLevel.toStringAsFixed(1)}%',
            style: const TextStyle(color: AppColors.systemA, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(AppProvider provider, bool isSystemA, Color color, bool isScanning, bool isCompleted) {
    if (isCompleted) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: () {
            if (provider.activeProject != null) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => ResultScreen(project: provider.activeProject!)),
              );
            }
          },
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('결과 보기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
    }
    if (isScanning) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          onPressed: () {
            _simulationTimer?.cancel();
            provider.cancelScan();
            setState(() => _isSimulating = false);
          },
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('스캔 중단', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => _startSimulation(provider),
        icon: Icon(isSystemA ? Icons.qr_code_scanner : Icons.directions_walk),
        label: Text(
          isSystemA ? '마커 스캔 시작' : '빠른 스캔 시작',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
