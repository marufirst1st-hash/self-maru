import 'dart:ui';
import 'package:uuid/uuid.dart';
import 'photo.dart';

/// 방의 벽 (두 코너를 잇는 선분)
class Wall {
  final String id;
  Offset start; // 코너1 (x, y) 미터
  Offset end; // 코너2 (x, y) 미터
  double get length => (end - start).distance;
  double confidence; // 0~1
  String source; // 'arcore','marker','lidar','flash','sonar','inferred'
  List<Photo> photos = [];

  Wall({
    String? id,
    required this.start,
    required this.end,
    this.confidence = 0.0,
    this.source = 'inferred',
    List<Photo>? photos,
  })  : id = id ?? const Uuid().v4(),
        photos = photos ?? [];

  Wall copyWith({
    Offset? start,
    Offset? end,
    double? confidence,
    String? source,
  }) {
    return Wall(
      id: id,
      start: start ?? this.start,
      end: end ?? this.end,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      photos: photos,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'startX': start.dx,
        'startY': start.dy,
        'endX': end.dx,
        'endY': end.dy,
        'length': length,
        'confidence': confidence,
        'source': source,
      };

  factory Wall.fromMap(Map<String, dynamic> map) {
    return Wall(
      id: map['id'] as String,
      start: Offset(
        (map['startX'] as num).toDouble(),
        (map['startY'] as num).toDouble(),
      ),
      end: Offset(
        (map['endX'] as num).toDouble(),
        (map['endY'] as num).toDouble(),
      ),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      source: map['source'] as String? ?? 'inferred',
    );
  }
}
