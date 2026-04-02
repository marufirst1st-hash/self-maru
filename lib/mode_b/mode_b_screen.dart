import 'dart:async';
import 'package:flutter/material.dart';
import '../core/models/corner.dart';
import '../core/models/photo.dart';
import '../core/models/room.dart';
import '../core/engines/pdr_engine.dart';
import '../core/engines/sensor_bridge.dart';
import '../core/engines/camera_bridge.dart';
import '../core/output/floor_plan_renderer.dart';
import '../core/workers/wall_constraint.dart';
import '../core/workers/merger.dart';
import '../core/workers/flash_worker.dart';
import '../core/workers/flash_bridge.dart';
import '../core/utils/tier_detector.dart';
import '../screens/result_screen.dart';
import '../screens/photo_review_sheet.dart';

/// Mode B 스캔 화면: 스마트 측정 (걷기만)
/// 실제 센서 연동: 가속도계+자이로(PDR) + 카메라(Flash Worker)
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

class _ModeBScreenState extends State<ModeBScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scanLineController;

  // 측정 상태
  bool _isScanning = false;
  bool _isCompleted = false;
  double _scanProgress = 0;
  int _layerActive = 1;
  double _confidence = 0;
  final List<Corner> _detectedCorners = [];
  Offset _currentPosition = Offset.zero;
  double _currentHeading = 0;
  int _stepCount = 0;

  // 실제 센서
  final PdrEngine _pdrEngine = PdrEngine();
  final SensorBridge _sensorBridge = SensorBridge();
  final CameraBridge _cameraBridge = CameraBridge();
  FlashWorker? _flashWorker;
  FlashBridge? _flashBridge;
  bool _sensorsAvailable = false;
  bool _cameraAvailable = false;

  // 보정
  final WallConstraint _wallConstraint = WallConstraint();
  final Merger _merger = Merger();

  // PDR → 벽 추론 (걸은 경로에서 코너 추론)
  final List<Offset> _walkPath = [];
  DateTime? _lastCornerTime;

  // 구독
  final List<StreamSubscription> _subscriptions = [];

  // 사진
  final List<Photo> _photos = [];

  // 다중 방
  final List<Room> _completedRooms = [];

  // 시뮬레이션 fallback
  Timer? _simTimer;
  int _simStep = 0;

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
    _initSensors();
  }

  Future<void> _initSensors() async {
    // 카메라 초기화 (권한 거부 시 false → 사진/Flash 비활성)
    try {
      _cameraAvailable = await _cameraBridge.initialize();
    } catch (_) {
      _cameraAvailable = false;
    }

    // 센서 사용 가능 여부 체크
    try {
      _sensorsAvailable = true;
    } catch (_) {
      _sensorsAvailable = false;
    }

    if (mounted) {
      setState(() {});
      if (!_cameraAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('카메라를 사용할 수 없습니다. 사진/Flash 기능이 비활성됩니다.'),
            backgroundColor: Color(0xFFFF9800),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanLineController.dispose();
    _simTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _sensorBridge.dispose();
    _pdrEngine.dispose();
    _cameraBridge.dispose();
    _flashBridge?.dispose();
    _flashWorker?.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() => _isScanning = true);

    if (_sensorsAvailable) {
      _startRealScan();
    } else {
      _runSimulation();
    }
  }

  void _startRealScan() {
    // PDR 시작
    _pdrEngine.start();
    _sensorBridge.connect(_pdrEngine);

    // PDR 이벤트 수신
    _subscriptions.add(
      _pdrEngine.onStep.listen((step) {
        if (!mounted) return;
        setState(() {
          _currentPosition = step.position;
          _currentHeading = step.heading;
          _stepCount = step.stepNumber;
          _walkPath.add(step.position);
          _scanProgress = (_stepCount / 40).clamp(0.0, 0.95); // ~40걸음이면 방 한 바퀴
          _layerActive = _scanProgress < 0.25 ? 1 : _scanProgress < 0.5 ? 2 : _scanProgress < 0.75 ? 3 : 4;
          _confidence = (_scanProgress * 90).clamp(0.0, 90.0);
        });

        // 걸음 패턴에서 코너 추론 (방향 급변 = 코너)
        _detectCornerFromWalk(step);
      }),
    );

    _subscriptions.add(
      _pdrEngine.onPositionUpdate.listen((state) {
        if (!mounted) return;
        setState(() {
          _currentPosition = state.position;
          _currentHeading = state.heading;
        });
      }),
    );

    // Flash Worker (Tier에 따라)
    if (_cameraAvailable && TierDetector.isWorkerEnabled('flash')) {
      _flashWorker = FlashWorker();
      _flashBridge = FlashBridge(
        camera: _cameraBridge,
        flashWorker: _flashWorker!,
      );

      _subscriptions.add(
        _flashWorker!.corrections.listen((c) => _merger.onCorrection(c)),
      );

      // 카메라 프레임 스트리밍 (Flash 밝기 측정용)
      _cameraBridge.startImageStream((image) {
        _flashBridge?.onFrame(image);
      });

      _flashBridge!.start(interval: const Duration(seconds: 3));
    }
  }

  /// 걸음 방향 급변 감지 → 코너 추론
  void _detectCornerFromWalk(PdrStep step) {
    if (_walkPath.length < 5) return;

    // 최근 5걸음의 방향 변화량
    final recent = _walkPath.length;
    final p1 = _walkPath[recent - 5];
    final p2 = _walkPath[recent - 3];
    final p3 = _walkPath[recent - 1];

    final dir1 = (p2 - p1).direction;
    final dir2 = (p3 - p2).direction;
    var angleDiff = (dir2 - dir1).abs();
    if (angleDiff > 3.14) angleDiff = 6.28 - angleDiff;

    // 45° 이상 방향 변화 = 코너 후보
    if (angleDiff > 0.78) {
      final now = DateTime.now();
      // 최소 2초 간격
      if (_lastCornerTime == null ||
          now.difference(_lastCornerTime!).inMilliseconds > 2000) {
        _lastCornerTime = now;
        final newCorner = Corner(
          position: step.position,
          confidence: 0.7,
          source: 'pdr',
        );
        setState(() {
          _detectedCorners.add(newCorner);
        });
      }
    }

    // 출발점 근처로 돌아오면 (폐합) → 자동 완료
    if (_stepCount > 10 && _detectedCorners.length >= 3) {
      final startPos = _walkPath.first;
      final currentPos = step.position;
      if ((currentPos - startPos).distance < 0.8) {
        _completeScan();
      }
    }
  }

  void _runSimulation() {
    final demoCorners = [
      Corner(position: const Offset(0, 0), confidence: 0.85, source: 'arcore'),
      Corner(position: const Offset(4.8, 0), confidence: 0.82, source: 'arcore'),
      Corner(position: const Offset(4.8, 3.6), confidence: 0.80, source: 'arcore'),
      Corner(position: const Offset(0, 3.6), confidence: 0.88, source: 'arcore'),
    ];

    _simStep = 0;
    _simTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _scanProgress = ((_simStep + 1) / 20.0).clamp(0.0, 1.0);
        _layerActive = _scanProgress < 0.25 ? 1 : _scanProgress < 0.5 ? 2 : _scanProgress < 0.75 ? 3 : 4;
        _confidence = (_scanProgress * 95).clamp(0.0, 95.0);

        if (_simStep < demoCorners.length) {
          _detectedCorners.add(demoCorners[_simStep]);
        }
      });

      _simStep++;
      if (_simStep >= 20) {
        timer.cancel();
        _completeScan();
      }
    });
  }

  void _completeScan() {
    if (_isCompleted) return;

    // 센서 정지
    _sensorBridge.disconnect();
    _flashBridge?.stop();
    _cameraBridge.stopImageStream();

    // Wall Constraint 적용
    if (_detectedCorners.length >= 3) {
      final corrections = _wallConstraint.constrainedOptimize(_detectedCorners);
      _merger.addAll(corrections);
    }

    final room = Room(
      corners: List.from(_detectedCorners),
      photos: List.from(_photos),
      confidence: _confidence / 100,
      mode: 'B',
    );

    if (_detectedCorners.length >= 3) {
      _merger.applyToRoom(room);
      room.rebuildWalls();
    }

    _completedRooms.add(room);

    setState(() {
      _isScanning = false;
      _isCompleted = true;
      _confidence = 92;
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
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
    });
  }

  void _manualComplete() {
    if (_detectedCorners.length >= 3) {
      _completeScan();
    }
  }

  /// 사진 촬영
  Future<void> _takePhoto() async {
    final bytes = await _cameraBridge.capturePhoto();
    if (bytes == null || !mounted) return;

    final photo = await PhotoReviewSheet.show(
      context,
      imageBytes: bytes,
      worldPosition: _currentPosition,
      heading: _currentHeading,
    );

    if (photo != null) {
      setState(() => _photos.add(photo));
      // Flash용 스트리밍 재개
      if (_flashBridge != null && _isScanning) {
        _cameraBridge.startImageStream((image) {
          _flashBridge?.onFrame(image);
        });
      }
    }
  }

  /// 현재 방 저장 후 다음 방 시작
  void _nextRoom() {
    if (_detectedCorners.length < 3) return;

    // 현재 방 완성
    final room = Room(
      corners: List.from(_detectedCorners),
      photos: List.from(_photos),
      confidence: _confidence / 100,
      mode: 'B',
    );
    _merger.applyToRoom(room);
    room.rebuildWalls();
    _completedRooms.add(room);

    // 상태 리셋 (센서는 유지)
    setState(() {
      _detectedCorners.clear();
      _photos.clear();
      _walkPath.clear();
      _scanProgress = 0;
      _confidence = 0;
      _stepCount = 0;
      _layerActive = 1;
    });
    _merger.clear();
    _pdrEngine.reset();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Room ${_completedRooms.length} 저장됨. 다음 방으로 이동하세요.'),
        backgroundColor: const Color(0xFF66BB6A),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addManualCorner() {
    setState(() {
      _detectedCorners.add(Corner(
        position: _currentPosition,
        confidence: 0.9,
        source: 'manual',
      ));
    });
  }

  void _cancelScan() {
    _simTimer?.cancel();
    _sensorBridge.disconnect();
    _flashBridge?.stop();
    _cameraBridge.stopImageStream();
    _pdrEngine.stop();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF26C6DA);

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
              child: const Text('B', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.projectName,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          if (_isScanning && _detectedCorners.length >= 3)
            TextButton(
              onPressed: _manualComplete,
              child: const Text('완료', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Column(
        children: [
          // 뷰파인더 / 도면
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                // 카메라 프리뷰 배경 (사용 가능할 때)
                if (_cameraAvailable && _isScanning && _cameraBridge.controller != null)
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.3,
                      child: _cameraBridge.getPreview() ?? const SizedBox(),
                    ),
                  ),

                // 도면 오버레이
                if (_detectedCorners.isNotEmpty)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: FloorPlanRenderer(
                        corners: _detectedCorners,
                        currentPosition: _isScanning ? _currentPosition : null,
                        currentHeading: _isScanning ? _currentHeading : null,
                        isScanning: _isScanning,
                        lineColor: color,
                        cornerColor: color,
                      ),
                    ),
                  )
                else if (!_isScanning)
                  _buildEmptyView(color),

                // 스캔라인 애니메이션
                if (_isScanning)
                  AnimatedBuilder(
                    animation: _scanLineController,
                    builder: (_, __) => Positioned(
                      top: 300 * _scanLineController.value,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.transparent,
                            color.withValues(alpha: 0.8),
                            color,
                            color.withValues(alpha: 0.8),
                            Colors.transparent,
                          ]),
                        ),
                      ),
                    ),
                  ),

                // 상태 배지
                Positioned(
                  top: 16,
                  right: 16,
                  child: _buildStatusBadge(color),
                ),

                // 센서 상태
                if (_isScanning)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: _buildSensorInfo(color),
                  ),
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
                  _buildProgress(color),
                  const SizedBox(height: 12),
                  _buildLayerIndicator(),
                  const SizedBox(height: 16),
                ],
                if (_isScanning)
                  _buildScanControls(color)
                else
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
              Icons.directions_walk,
              color: color.withValues(alpha: 0.5 + _pulseController.value * 0.3),
              size: 64,
            ),
          ),
          const SizedBox(height: 24),
          Text('방 주위를 걸어다니세요', style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('천천히 걸으며 방 전체를 스캔하세요', style: TextStyle(color: Colors.grey, fontSize: 13)),
          if (_sensorsAvailable)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sensors, size: 14, color: Color(0xFF66BB6A)),
                  SizedBox(width: 4),
                  Text('센서 준비됨', style: TextStyle(color: Color(0xFF66BB6A), fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(Color color) {
    final label = _isCompleted ? '완료' : _isScanning ? '스캔 중' : '대기';
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

  Widget _buildSensorInfo(Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF151926).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.directions_walk, size: 12, color: color),
              const SizedBox(width: 4),
              Text('$_stepCount 걸음', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.crop_square, size: 12, color: Colors.grey),
              const SizedBox(width: 4),
              Text('코너 ${_detectedCorners.length}개', style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
          if (_flashBridge != null)
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.flash_on, size: 12, color: Color(0xFFFFD54F)),
                SizedBox(width: 4),
                Text('Flash ON', style: TextStyle(color: Color(0xFFFFD54F), fontSize: 11)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildProgress(Color color) {
    final area = _detectedCorners.length >= 3 ? _calculateArea() : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('측정 진행률', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const Spacer(),
          Text('${(_scanProgress * 100).toInt()}%', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: _scanProgress, backgroundColor: const Color(0xFF1E2235), valueColor: AlwaysStoppedAnimation(color), minHeight: 6),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.crop_square, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Text('코너: ${_detectedCorners.length}개', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          if (area > 0) ...[
            const SizedBox(width: 16),
            Icon(Icons.square_foot, size: 14, color: color),
            const SizedBox(width: 4),
            Text('면적: ${area.toStringAsFixed(2)} m²', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ]),
      ],
    );
  }

  Widget _buildLayerIndicator() {
    final layers = ['PDR', 'Flash', 'Wall', 'Corner'];
    return Row(
      children: layers.asMap().entries.map((entry) {
        final isActive = entry.key < _layerActive;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: entry.key < 3 ? 4 : 0),
            height: 4,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF26C6DA) : const Color(0xFF1E2235),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildScanControls(Color color) {
    return Column(
      children: [
        // 도구 버튼 행
        Row(
          children: [
            // 코너 추가
            Expanded(
              child: SizedBox(
                height: 42,
                child: OutlinedButton.icon(
                  onPressed: _addManualCorner,
                  icon: const Icon(Icons.add_location_alt, size: 16),
                  label: const Text('코너', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 사진 촬영
            Expanded(
              child: SizedBox(
                height: 42,
                child: OutlinedButton.icon(
                  onPressed: _cameraAvailable ? _takePhoto : null,
                  icon: Icon(Icons.camera_alt, size: 16, color: _cameraAvailable ? const Color(0xFFFFD54F) : Colors.grey),
                  label: Text('사진${_photos.isNotEmpty ? ' (${_photos.length})' : ''}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFD54F),
                    side: BorderSide(color: const Color(0xFFFFD54F).withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 스캔 중단
            SizedBox(
              height: 42,
              width: 42,
              child: IconButton(
                onPressed: _cancelScan,
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent, size: 22),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_detectedCorners.length >= 3) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              // 다음 방
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _nextRoom,
                    icon: const Icon(Icons.add_home_outlined, size: 18),
                    label: Text('다음 방${_completedRooms.isNotEmpty ? ' (${_completedRooms.length}완료)' : ''}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 전체 완료
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _manualComplete,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('측정 완료', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF66BB6A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildActionButton(Color color) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _startScan,
        icon: const Icon(Icons.directions_walk),
        label: const Text('스마트 스캔 시작', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  double _calculateArea() {
    if (_detectedCorners.length < 3) return 0;
    double sum = 0;
    for (int i = 0; i < _detectedCorners.length; i++) {
      final j = (i + 1) % _detectedCorners.length;
      final pi = _detectedCorners[i].position;
      final pj = _detectedCorners[j].position;
      sum += pi.dx * pj.dy - pj.dx * pi.dy;
    }
    return sum.abs() / 2.0;
  }
}
