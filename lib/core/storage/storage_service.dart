import 'package:hive_flutter/hive_flutter.dart';
import 'project_model.dart';

/// Hive 로컬 저장소 서비스
class StorageService {
  static const String _boxName = 'projects';
  Box? _box;

  bool get isInitialized => _box?.isOpen ?? false;

  /// Hive 초기화 (앱 시작 시 1회)
  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
  }

  /// 프로젝트 저장 (생성 or 업데이트)
  Future<void> saveProject(ProjectModel project) async {
    if (_box == null) return;
    await _box!.put(project.id, project.toMap());
  }

  /// 프로젝트 조회
  ProjectModel? getProject(String id) {
    if (_box == null) return null;
    final data = _box!.get(id);
    if (data == null) return null;
    return ProjectModel.fromMap(data as Map<dynamic, dynamic>);
  }

  /// 전체 프로젝트 목록 (최신순)
  List<ProjectModel> getAllProjects() {
    if (_box == null) return [];
    final projects = <ProjectModel>[];
    for (final key in _box!.keys) {
      final data = _box!.get(key);
      if (data != null) {
        try {
          projects.add(ProjectModel.fromMap(data as Map<dynamic, dynamic>));
        } catch (_) {
          // 손상된 데이터 스킵
        }
      }
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  /// 완료된 프로젝트만
  List<ProjectModel> getCompletedProjects() {
    return getAllProjects().where((p) => p.status == 'completed').toList();
  }

  /// 프로젝트 삭제
  Future<void> deleteProject(String id) async {
    if (_box == null) return;
    await _box!.delete(id);
  }

  /// 전체 삭제
  Future<void> clearAll() async {
    if (_box == null) return;
    await _box!.clear();
  }

  /// 프로젝트 수
  int get count => _box?.length ?? 0;

  void dispose() {
    _box?.close();
  }
}
