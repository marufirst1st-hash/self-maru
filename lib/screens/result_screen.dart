import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../core/models/room.dart';
import '../core/output/floor_plan_renderer.dart';
import '../core/output/erp_uploader.dart';
import '../core/storage/project_model.dart';
import '../main.dart' show storageService;

/// 측정 결과 화면 (A/B/C 공용)
class ResultScreen extends StatefulWidget {
  final List<Room> rooms;
  final String projectName;
  final String? siteName;
  final String? address;
  final String mode; // 'A', 'B', 'C'

  const ResultScreen({
    super.key,
    required this.rooms,
    required this.projectName,
    this.siteName,
    this.address,
    required this.mode,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ErpUploader _erpUploader = ErpUploader();

  bool _isUploading = false;
  bool _isUploaded = false;
  String? _uploadError;
  UploadResult? _uploadResult;

  double get _totalArea =>
      widget.rooms.fold<double>(0.0, (sum, r) => sum + r.area);

  String get _modeLabel {
    switch (widget.mode) {
      case 'A':
        return 'Marker Precision (±1%)';
      case 'C':
        return 'LiDAR Precision (±1%)';
      default:
        return 'Smart Scan (±3%)';
    }
  }

  Color get _modeColor {
    switch (widget.mode) {
      case 'A':
        return const Color(0xFFFF6B35);
      case 'C':
        return const Color(0xFF7C4DFF);
      default:
        return const Color(0xFF26C6DA);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _saveToLocal();
  }

  /// 측정 결과를 Hive에 자동 저장
  Future<void> _saveToLocal() async {
    final project = ProjectModel(
      id: widget.rooms.isNotEmpty ? widget.rooms.first.id : const Uuid().v4(),
      name: widget.projectName,
      siteName: widget.siteName,
      address: widget.address,
      mode: widget.mode,
    );
    project.complete(widget.rooms);
    await storageService.saveProject(project);
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
      final result = await _erpUploader.uploadProject(
        projectId: widget.rooms.isNotEmpty ? widget.rooms.first.id : 'unknown',
        projectName: widget.projectName,
        rooms: widget.rooms,
        photos: widget.rooms.expand((r) => r.photos).toList(),
        mode: widget.mode,
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
    final text = _erpUploader.formatForClipboard(
      rooms: widget.rooms,
      mode: widget.mode,
      uploadResult: _uploadResult!,
      measuredAt: widget.rooms.isNotEmpty ? widget.rooms.first.measuredAt : null,
    );
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ERP 데이터가 클립보드에 복사됐습니다'),
        backgroundColor: Color(0xFF66BB6A),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151926),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.projectName,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            if (widget.address != null)
              Text(widget.address!,
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
        actions: [
          if (_isUploaded)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.cloud_done, color: Color(0xFF66BB6A)),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _modeColor,
          labelColor: _modeColor,
          unselectedLabelColor: Colors.grey,
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

  // 탭 1: 도면
  Widget _buildFloorPlanTab() {
    if (widget.rooms.isEmpty) {
      return const Center(
        child: Text('측정된 방이 없습니다', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      children: [
        // 방 선택 탭
        if (widget.rooms.length > 1)
          Container(
            height: 44,
            color: const Color(0xFF151926),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: widget.rooms.length,
              itemBuilder: (context, index) {
                final room = widget.rooms[index];
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2235),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _modeColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Room ${index + 1} (${room.area.toStringAsFixed(1)}m²)',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                );
              },
            ),
          ),

        // 도면
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF151926),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1E2235)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CustomPaint(
                painter: FloorPlanRenderer(
                  room: widget.rooms.first,
                  showDimensions: true,
                  showArea: true,
                  lineColor: _modeColor,
                ),
                child: Container(),
              ),
            ),
          ),
        ),

        // 요약
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF151926),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E2235)),
          ),
          child: Row(
            children: [
              Expanded(child: _infoItem('총 면적', '${_totalArea.toStringAsFixed(2)} m²', _modeColor)),
              Container(width: 1, height: 40, color: const Color(0xFF1E2235)),
              Expanded(child: _infoItem('방 수', '${widget.rooms.length}개', const Color(0xFF448AFF))),
              Container(width: 1, height: 40, color: const Color(0xFF1E2235)),
              Expanded(child: _infoItem('측정 방식', widget.mode, _modeColor)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
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
          _sectionCard(
            title: '프로젝트 정보',
            icon: Icons.folder_outlined,
            child: Column(
              children: [
                _dataRow('프로젝트명', widget.projectName),
                if (widget.siteName != null) _dataRow('현장명', widget.siteName!),
                if (widget.address != null) _dataRow('주소', widget.address!),
                _dataRow('측정 방식', _modeLabel),
                _dataRow('측정일', _formatDate(widget.rooms.isNotEmpty ? widget.rooms.first.measuredAt : DateTime.now())),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: '측정 결과',
            icon: Icons.square_foot,
            child: Column(
              children: [
                _dataRow('총 면적', '${_totalArea.toStringAsFixed(2)} m²', valueColor: _modeColor),
                _dataRow('방 수', '${widget.rooms.length}개'),
                ...widget.rooms.asMap().entries.map((entry) {
                  final room = entry.value;
                  return Column(
                    children: [
                      const Divider(color: Color(0xFF1E2235), height: 16),
                      _dataRow('Room ${entry.key + 1}', '${room.area.toStringAsFixed(2)} m²', valueColor: const Color(0xFF448AFF)),
                      _dataRow('  둘레', '${room.perimeter.toStringAsFixed(2)} m'),
                      _dataRow('  코너 수', '${room.corners.length}개'),
                    ],
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (widget.rooms.isNotEmpty)
            _sectionCard(
              title: '코너 좌표 (Room 1)',
              icon: Icons.crop_square,
              child: Column(
                children: widget.rooms.first.corners.asMap().entries.map((entry) {
                  final c = entry.value;
                  return _dataRow(
                    'P${entry.key + 1}',
                    'X: ${c.position.dx.toStringAsFixed(3)}m  Y: ${c.position.dy.toStringAsFixed(3)}m'
                    '  (${(c.confidence * 100).toStringAsFixed(0)}%)',
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
          _sectionCard(
            title: 'S3 업로드',
            icon: Icons.cloud_upload_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('도면(DXF)을 AWS S3에 업로드하고 링크를 생성합니다.',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 16),
                if (_uploadResult?.dxfUrl != null) ...[
                  _linkRow('DXF 도면', _uploadResult!.dxfUrl!),
                  const SizedBox(height: 12),
                ],
                if (_uploadError != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                    ),
                    child: Text(_uploadError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _isUploading ? null : _uploadToS3,
                    icon: _isUploading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_isUploaded ? Icons.cloud_done : Icons.cloud_upload),
                    label: Text(
                      _isUploading ? '업로드 중...' : _isUploaded ? 'S3 업로드 완료' : 'S3에 DXF 업로드',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isUploaded ? const Color(0xFF66BB6A) : _modeColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'ERP 주문서 데이터',
            icon: Icons.description_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ERP 주문서에 입력할 데이터입니다.',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0E1A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1E2235)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _erpField('총 면적', '${_totalArea.toStringAsFixed(2)} m²'),
                      _erpField('방별 면적', widget.rooms.asMap().entries.map((e) => 'Room${e.key + 1}: ${e.value.area.toStringAsFixed(2)}m²').join(' / ')),
                      _erpField('측정 방식', _modeLabel),
                      _erpField('측정일', _formatDate(DateTime.now())),
                      if (_uploadResult?.dxfUrl != null) ...[
                        const Divider(color: Color(0xFF1E2235), height: 16),
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
                      foregroundColor: _modeColor,
                      side: BorderSide(color: _isUploaded ? _modeColor : Colors.grey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                if (!_isUploaded)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('* S3 업로드 후 도면 링크가 포함됩니다',
                        style: TextStyle(color: Colors.grey, fontSize: 11)),
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
        color: const Color(0xFF151926),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: _modeColor, size: 18),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
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
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(
            child: Text(value,
                style: TextStyle(color: valueColor ?? Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _linkRow(String label, String url) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF66BB6A).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF66BB6A).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.link, color: Color(0xFF66BB6A), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                Text(url, style: const TextStyle(color: Color(0xFF66BB6A), fontSize: 12), overflow: TextOverflow.ellipsis),
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
            icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
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
          SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
          Expanded(
            child: Text(value,
                style: TextStyle(
                  color: isLink ? const Color(0xFF448AFF) : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
