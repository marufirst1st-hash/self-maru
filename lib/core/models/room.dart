import 'package:uuid/uuid.dart';
import 'wall.dart';
import 'corner.dart';
import 'photo.dart';
import '../utils/math_utils.dart';

/// 측정된 방 하나
class Room {
  final String id;
  List<Wall> walls;
  List<Corner> corners;
  List<Photo> photos;
  double confidence; // 0~1
  String mode; // 'A', 'B', 'C'
  DateTime measuredAt;

  double get area =>
      MathUtils.shoelace(corners.map((c) => c.position).toList());

  double get perimeter =>
      walls.fold(0.0, (sum, w) => sum + w.length);

  Room({
    String? id,
    List<Wall>? walls,
    List<Corner>? corners,
    List<Photo>? photos,
    this.confidence = 0.0,
    this.mode = 'B',
    DateTime? measuredAt,
  })  : id = id ?? const Uuid().v4(),
        walls = walls ?? [],
        corners = corners ?? [],
        photos = photos ?? [],
        measuredAt = measuredAt ?? DateTime.now();

  /// 코너 목록으로부터 벽 자동 생성 (순서대로 연결)
  void rebuildWalls() {
    walls.clear();
    for (int i = 0; i < corners.length; i++) {
      final j = (i + 1) % corners.length;
      walls.add(Wall(
        start: corners[i].position,
        end: corners[j].position,
        confidence: (corners[i].confidence + corners[j].confidence) / 2,
        source: corners[i].source,
      ));
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'corners': corners.map((c) => c.toMap()).toList(),
        'walls': walls.map((w) => w.toMap()).toList(),
        'photos': photos.map((p) => p.toMap()).toList(),
        'area': area,
        'perimeter': perimeter,
        'confidence': confidence,
        'mode': mode,
        'measuredAt': measuredAt.toIso8601String(),
      };

  factory Room.fromMap(Map<String, dynamic> map) {
    return Room(
      id: map['id'] as String,
      corners: (map['corners'] as List)
          .map((c) => Corner.fromMap(c as Map<String, dynamic>))
          .toList(),
      walls: (map['walls'] as List)
          .map((w) => Wall.fromMap(w as Map<String, dynamic>))
          .toList(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      mode: map['mode'] as String? ?? 'B',
      measuredAt: DateTime.parse(map['measuredAt'] as String),
    );
  }
}
