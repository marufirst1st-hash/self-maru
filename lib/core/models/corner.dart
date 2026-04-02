import 'dart:ui';
import 'package:uuid/uuid.dart';

/// 방의 코너 (두 벽이 만나는 점)
class Corner {
  final String id;
  Offset position; // (x, y) 미터
  double angle; // 인접 벽 사이 각도 (도)
  double confidence; // 0~1
  String source; // 'arcore','marker','lidar','flash','sonar','inferred'

  Corner({
    String? id,
    required this.position,
    this.angle = 90.0,
    this.confidence = 0.0,
    this.source = 'inferred',
  }) : id = id ?? const Uuid().v4();

  Corner copyWith({
    Offset? position,
    double? angle,
    double? confidence,
    String? source,
  }) {
    return Corner(
      id: id,
      position: position ?? this.position,
      angle: angle ?? this.angle,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'x': position.dx,
        'y': position.dy,
        'angle': angle,
        'confidence': confidence,
        'source': source,
      };

  factory Corner.fromMap(Map<String, dynamic> map) {
    return Corner(
      id: map['id'] as String,
      position: Offset(
        (map['x'] as num).toDouble(),
        (map['y'] as num).toDouble(),
      ),
      angle: (map['angle'] as num?)?.toDouble() ?? 90.0,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      source: map['source'] as String? ?? 'inferred',
    );
  }
}
