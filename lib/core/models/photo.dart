import 'dart:typed_data';
import 'dart:ui';
import 'package:uuid/uuid.dart';

/// AR 세션 중 촬영한 현장 사진
class Photo {
  final String id;
  final Uint8List? imageBytes;
  final Offset worldPosition; // (x, y) 미터
  final double heading; // 라디안
  final DateTime timestamp;
  String? nearestWallId;
  String? note;
  String? s3Url;

  Photo({
    String? id,
    this.imageBytes,
    required this.worldPosition,
    this.heading = 0.0,
    DateTime? timestamp,
    this.nearestWallId,
    this.note,
    this.s3Url,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'x': worldPosition.dx,
        'y': worldPosition.dy,
        'heading': heading,
        'timestamp': timestamp.toIso8601String(),
        'nearestWallId': nearestWallId,
        'note': note,
        's3Url': s3Url,
      };

  factory Photo.fromMap(Map<String, dynamic> map) {
    return Photo(
      id: map['id'] as String,
      worldPosition: Offset(
        (map['x'] as num).toDouble(),
        (map['y'] as num).toDouble(),
      ),
      heading: (map['heading'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.parse(map['timestamp'] as String),
      nearestWallId: map['nearestWallId'] as String?,
      note: map['note'] as String?,
      s3Url: map['s3Url'] as String?,
    );
  }
}
