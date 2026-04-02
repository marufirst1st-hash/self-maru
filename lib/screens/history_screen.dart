import 'package:flutter/material.dart';
import '../core/storage/project_model.dart';
import '../main.dart' show storageService;
import 'result_screen.dart';

/// 측정 이력 화면
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<ProjectModel> _projects = [];

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  void _loadProjects() {
    setState(() {
      _projects = storageService.getAllProjects();
    });
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'A':
        return const Color(0xFFFF6B35);
      case 'C':
        return const Color(0xFF7C4DFF);
      default:
        return const Color(0xFF26C6DA);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const Text('측정 이력',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${_projects.length}개 프로젝트',
                      style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 통계 바
            if (_projects.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildStats(),
              ),
            if (_projects.isNotEmpty) const SizedBox(height: 16),

            // 프로젝트 리스트
            Expanded(
              child: _projects.isEmpty
                  ? _buildEmpty()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _projects.length,
                      itemBuilder: (context, index) =>
                          _buildProjectCard(_projects[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    final completed = _projects.where((p) => p.status == 'completed').length;
    final totalArea = _projects.fold<double>(0, (sum, p) => sum + p.totalArea);
    final modeACnt = _projects.where((p) => p.mode == 'A').length;
    final modeBCnt = _projects.where((p) => p.mode == 'B').length;
    final modeCCnt = _projects.where((p) => p.mode == 'C').length;

    return Row(
      children: [
        _statChip('완료 $completed', const Color(0xFF66BB6A)),
        const SizedBox(width: 8),
        _statChip('${totalArea.toStringAsFixed(1)} m²', const Color(0xFF4FC3F7)),
        const SizedBox(width: 8),
        if (modeACnt > 0) _statChip('A:$modeACnt', const Color(0xFFFF6B35)),
        if (modeACnt > 0) const SizedBox(width: 8),
        if (modeBCnt > 0) _statChip('B:$modeBCnt', const Color(0xFF26C6DA)),
        if (modeBCnt > 0) const SizedBox(width: 8),
        if (modeCCnt > 0) _statChip('C:$modeCCnt', const Color(0xFF7C4DFF)),
      ],
    );
  }

  Widget _statChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64,
              color: Colors.grey.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('측정 이력이 없습니다',
              style: TextStyle(color: Colors.grey, fontSize: 15)),
          const SizedBox(height: 8),
          const Text('새 스캔을 시작하면 여기에 기록됩니다',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildProjectCard(ProjectModel project) {
    final color = _modeColor(project.mode);
    final isCompleted = project.status == 'completed';

    return GestureDetector(
      onTap: () {
        if (isCompleted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ResultScreen(
                rooms: project.toRooms(),
                projectName: project.name,
                siteName: project.siteName,
                address: project.address,
                mode: project.mode,
              ),
            ),
          ).then((_) => _loadProjects());
        }
      },
      onLongPress: () => _showDeleteDialog(project),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF151926),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E2235)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 모드 배지
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(project.mode,
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(project.name,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                _statusChip(project.status),
              ],
            ),
            if (project.address != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(project.address!,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (project.totalArea > 0) ...[
                  const Icon(Icons.square_foot, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('${project.totalArea.toStringAsFixed(1)} m²',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(width: 16),
                ],
                const Icon(Icons.meeting_room_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${project.roomCount} rooms',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const Spacer(),
                Text(_formatDate(project.updatedAt),
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
                if (isCompleted)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(ProjectModel project) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151926),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('프로젝트 삭제', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text('${project.name}을(를) 삭제하시겠습니까?',
            style: const TextStyle(color: Colors.grey, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await storageService.deleteProject(project.id);
              _loadProjects();
            },
            child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color chipColor;
    String label;
    switch (status) {
      case 'completed':
        chipColor = const Color(0xFF66BB6A);
        label = 'Done';
      case 'scanning':
        chipColor = const Color(0xFFFFCA28);
        label = 'Scanning';
      default:
        chipColor = Colors.grey;
        label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(color: chipColor, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
