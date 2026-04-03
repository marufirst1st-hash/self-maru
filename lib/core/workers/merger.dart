import 'dart:ui';
import '../models/corner.dart';
import '../models/correction.dart';
import '../models/room.dart';

/// Merger: 모든 Worker의 보정값을 신뢰도 가중 병합
/// 공식 ㉙
class Merger {
  final Map<String, List<Correction>> _corrections = {};

  /// 보정값 도착 시 호출
  void onCorrection(Correction correction) {
    final list = _corrections.putIfAbsent(correction.cornerId, () => []);
    list.add(correction);
    // 코너당 최대 50개 보정 유지 (메모리 + 최신 값 우선)
    if (list.length > 50) list.removeAt(0);
  }

  /// 여러 보정값 일괄 추가
  void addAll(List<Correction> corrections) {
    for (final c in corrections) {
      onCorrection(c);
    }
  }

  /// 특정 코너의 보정된 위치 계산
  /// corrected = raw + Σ(delta × confidence) / Σ(confidence)
  Offset getCorrectedPosition(Corner corner) {
    final corrs = _corrections[corner.id];
    if (corrs == null || corrs.isEmpty) return corner.position;

    double totalDx = 0, totalDy = 0, totalW = 0;
    for (final c in corrs) {
      totalDx += c.dx * c.confidence;
      totalDy += c.dy * c.confidence;
      totalW += c.confidence;
    }

    if (totalW < 1e-10) return corner.position;

    return Offset(
      corner.position.dx + totalDx / totalW,
      corner.position.dy + totalDy / totalW,
    );
  }

  /// Room의 모든 코너에 보정 적용
  void applyToRoom(Room room) {
    for (int i = 0; i < room.corners.length; i++) {
      final corrected = getCorrectedPosition(room.corners[i]);
      room.corners[i] = room.corners[i].copyWith(position: corrected);
    }
    // 벽 재생성
    room.rebuildWalls();
  }

  /// 특정 코너의 보정 이력 조회
  List<Correction> getCorrections(String cornerId) {
    return _corrections[cornerId] ?? [];
  }

  /// 전체 평균 신뢰도
  double get averageConfidence {
    final all = _corrections.values.expand((list) => list).toList();
    if (all.isEmpty) return 0;
    return all.map((c) => c.confidence).reduce((a, b) => a + b) / all.length;
  }

  /// 초기화
  void clear() {
    _corrections.clear();
  }
}
