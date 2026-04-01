import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/measurement.dart';
import '../providers/app_provider.dart';
import '../services/upload_service.dart';
import '../utils/app_colors.dart';
import '../widgets/floor_plan_painter.dart';

class ResultScreen extends StatefulWidget {
  final MeasurementProject project;
  const ResultScreen({super.key, required this.project});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final UploadService _uploadService = UploadService();

  bool _isUploading = false;
  bool _isUploaded = false;
  String? _uploadError;
  ProjectUploadResult? _uploadResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _uploadToS3() async {
    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      final result = await _uploadService.uploadProject(
        project: widget.project,
        photoBytes: [],
        photoFileNames: [],
      );

      setState(() {
        _isUploading = false;
        _isUploaded = result.dxfUrl != null;
        _uploadResult = result;
        if (!result.success && result.dxfUrl == null) {
          _uploadError = result.errors.isNotEmpty ? result.errors.first : '업로드 실패';
        }
      });
    } catch (e) {
      setState(() {
        _isUploading = false;
        _uploadError = '업로드 중 오류: $e';
      });
    }
  }

  void _copyErpText() {
    if (_uploadResult == null) return;
    final erpData = _uploadService.buildErpPackage(
      project: widget.project,
      uploadResult: _uploadResult!,
    );
    final text = _uploadService.formatForErp(erpData);
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ERP 데이터가 클립보드에 복사됐습니다'),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.project.name,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            if (widget.project.address != null)
              Text(widget.project.address!,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
        actions: [
          if (_isUploaded)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.cloud_done, color: AppColors.success),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: '도면'),
            Tab(text: '측정 데이터'),
            Tab(text: 'ERP 전송'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFloorPlanTab(),
          _buildDataTab(),
          _buildErpTab(),
        ],
      ),
    );
  }

  // 탭 1: 도면 뷰어
  Widget _buildFloorPlanTab() {
    if (widget.project.rooms.isEmpty) {
      return const Center(
        child: Text('측정된 방이 없습니다', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        return Column(
          children: [
            // 방 선택 탭
            if (widget.project.rooms.length > 1)
              Container(
                height: 44,
                color: AppColors.bgCard,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  itemCount: widget.project.rooms.length,
                  itemBuilder: (context, index) {
                    final room = widget.project.rooms[index];
                    final area = room.area ?? room.calculateArea();
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.bgElevated,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '${room.name} (${area.toStringAsFixed(1)}m²)',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                      ),
                    );
                  },
                ),
              ),

            // 도면 뷰어
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.bgElevated),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CustomPaint(
                    painter: FloorPlanPainter(
                      corners: widget.project.rooms.first.corners,
                      showDimensions: true,
                      showArea: true,
                    ),
                    child: Container(),
                  ),
                ),
              ),
            ),

            // 요약 정보
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.bgElevated),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _infoItem('총 면적', '${widget.project.totalArea?.toStringAsFixed(2) ?? "0"} m²', AppColors.accent),
                  ),
                  Container(width: 1, height: 40, color: AppColors.bgElevated),
                  Expanded(
                    child: _infoItem('방 수', '${widget.project.rooms.length}개', AppColors.info),
                  ),
                  Container(width: 1, height: 40, color: AppColors.bgElevated),
                  Expanded(
                    child: _infoItem(
                      '측정 방식',
                      widget.project.system == MeasurementSystem.systemA ? 'Marker' : 'Quick',
                      widget.project.system == MeasurementSystem.systemA ? AppColors.systemA : AppColors.systemB,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _infoItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }

  // 탭 2: 측정 데이터
  Widget _buildDataTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 프로젝트 정보
          _sectionCard(
            title: '프로젝트 정보',
            icon: Icons.folder_outlined,
            child: Column(
              children: [
                _dataRow('프로젝트명', widget.project.name),
                if (widget.project.siteName != null)
                  _dataRow('현장명', widget.project.siteName!),
                if (widget.project.address != null)
                  _dataRow('주소', widget.project.address!),
                _dataRow('측정 방식', widget.project.system == MeasurementSystem.systemA
                    ? 'System A - Marker Precision (±1~2%)' : 'System B - Quick Scan (±3%)'),
                _dataRow('측정일', _formatDate(widget.project.updatedAt)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 측정 결과 요약
          _sectionCard(
            title: '측정 결과',
            icon: Icons.square_foot,
            child: Column(
              children: [
                _dataRow('총 면적', '${widget.project.totalArea?.toStringAsFixed(2) ?? "0"} m²',
                    valueColor: AppColors.accent),
                _dataRow('방 수', '${widget.project.rooms.length}개'),
                ...widget.project.rooms.map((room) {
                  final area = room.area ?? room.calculateArea();
                  final perimeter = room.perimeter ?? room.calculatePerimeter();
                  return Column(
                    children: [
                      const Divider(color: AppColors.bgElevated, height: 16),
                      _dataRow(room.name, '${area.toStringAsFixed(2)} m²', valueColor: AppColors.info),
                      _dataRow('  둘레', '${perimeter.toStringAsFixed(2)} m'),
                      _dataRow('  코너 수', '${room.corners.length}개'),
                    ],
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 코너 좌표
          if (widget.project.rooms.isNotEmpty)
            _sectionCard(
              title: '코너 좌표 (${widget.project.rooms.first.name})',
              icon: Icons.crop_square,
              child: Column(
                children: widget.project.rooms.first.corners.asMap().entries.map((entry) {
                  final i = entry.key;
                  final corner = entry.value;
                  return _dataRow(
                    'P${i + 1}',
                    'X: ${corner.position.x.toStringAsFixed(3)}m  Y: ${corner.position.y.toStringAsFixed(3)}m'
                    '  (신뢰도 ${corner.confidence.toStringAsFixed(0)}%)',
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // 탭 3: ERP 전송
  Widget _buildErpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // S3 업로드 섹션
          _sectionCard(
            title: 'S3 업로드',
            icon: Icons.cloud_upload_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '도면(DXF)을 AWS S3에 업로드하고 링크를 생성합니다.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),

                if (_uploadResult != null) ...[
                  if (_uploadResult!.dxfUrl != null) ...[
                    _linkRow('DXF 도면', _uploadResult!.dxfUrl!),
                    const SizedBox(height: 8),
                  ],
                  if (_uploadError != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Text(_uploadError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                    ),
                  const SizedBox(height: 12),
                ],

                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _isUploading ? null : _uploadToS3,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(_isUploaded ? Icons.cloud_done : Icons.cloud_upload),
                    label: Text(
                      _isUploading ? '업로드 중...' : _isUploaded ? 'S3 업로드 완료' : 'S3에 DXF 업로드',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isUploaded ? AppColors.success : AppColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ERP 데이터 미리보기
          _sectionCard(
            title: 'ERP 주문서 데이터',
            icon: Icons.description_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ERP 주문서에 입력할 데이터입니다. 복사 후 붙여넣기 하세요.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),

                // 텍스트 데이터
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.bgElevated),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _erpField('총 면적', '${widget.project.totalArea?.toStringAsFixed(2) ?? "0"} m²'),
                      _erpField('방별 면적', widget.project.rooms.map((r) {
                        final area = r.area ?? r.calculateArea();
                        return '${r.name}: ${area.toStringAsFixed(2)}m²';
                      }).join(' / ')),
                      _erpField('측정 방식', widget.project.system == MeasurementSystem.systemA
                          ? 'Marker Precision (±1~2%)' : 'Quick Scan (±3%)'),
                      _erpField('측정일', _formatDate(widget.project.updatedAt)),
                      if (_uploadResult?.dxfUrl != null) ...[
                        const Divider(color: AppColors.bgElevated, height: 16),
                        _erpField('DXF 도면', _uploadResult!.dxfUrl!, isLink: true),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _isUploaded ? _copyErpText : null,
                    icon: const Icon(Icons.copy),
                    label: const Text('ERP 데이터 복사', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: BorderSide(
                        color: _isUploaded ? AppColors.accent : AppColors.textMuted,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                if (!_isUploaded)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '* S3 업로드 후 도면 링크가 포함됩니다',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.bgElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _dataRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: valueColor ?? AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkRow(String label, String url) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.link, color: AppColors.success, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                Text(
                  url,
                  style: const TextStyle(color: AppColors.success, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('링크 복사됨'), duration: Duration(seconds: 1)),
              );
            },
            icon: const Icon(Icons.copy, size: 16, color: AppColors.textSecondary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _erpField(String label, String value, {bool isLink = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isLink ? AppColors.info : AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
