import 'dart:math' as math;
import 'package:uuid/uuid.dart';

enum MeasurementSystem { systemA, systemB }
enum MeasurementStatus { idle, scanning, processing, completed, error }
enum MarkerType { cube, sticker, rod }

class Point3D {
  final double x;
  final double y;
  final double z;

  const Point3D({required this.x, required this.y, this.z = 0});

  double distanceTo(Point3D other) {
    return math.sqrt(
      math.pow(x - other.x, 2) +
      math.pow(y - other.y, 2) +
      math.pow(z - other.z, 2),
    );
  }

  Map<String, dynamic> toMap() => {'x': x, 'y': y, 'z': z};

  factory Point3D.fromMap(Map<String, dynamic> map) {
    return Point3D(
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
      z: (map['z'] as num?)?.toDouble() ?? 0,
    );
  }
}

class Corner {
  final String id;
  final Point3D position;
  final double confidence;
  final bool isAutoDetected;

  Corner({
    String? id,
    required this.position,
    this.confidence = 0.0,
    this.isAutoDetected = true,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toMap() => {
    'id': id,
    'position': position.toMap(),
    'confidence': confidence,
    'isAutoDetected': isAutoDetected,
  };

  factory Corner.fromMap(Map<String, dynamic> map) {
    return Corner(
      id: map['id'] as String,
      position: Point3D.fromMap(map['position'] as Map<String, dynamic>),
      confidence: (map['confidence'] as num).toDouble(),
      isAutoDetected: map['isAutoDetected'] as bool,
    );
  }
}

class Wall {
  final Corner start;
  final Corner end;
  final double? height;

  const Wall({required this.start, required this.end, this.height});

  double get length => start.position.distanceTo(end.position);
}

class Marker {
  final String id;
  final int tagId;
  final MarkerType type;
  final Point3D position;
  final double confidence;
  final DateTime detectedAt;

  Marker({
    String? id,
    required this.tagId,
    required this.type,
    required this.position,
    this.confidence = 0.0,
    DateTime? detectedAt,
  }) : id = id ?? const Uuid().v4(),
       detectedAt = detectedAt ?? DateTime.now();
}

class FloorPlan {
  final String id;
  final String name;
  final List<Corner> corners;
  final List<Wall> walls;
  final double? area;
  final double? perimeter;

  FloorPlan({
    String? id,
    required this.name,
    required this.corners,
    required this.walls,
    this.area,
    this.perimeter,
  }) : id = id ?? const Uuid().v4();

  double calculateArea() {
    if (corners.length < 3) return 0;
    // Shoelace formula
    double sum = 0;
    for (int i = 0; i < corners.length; i++) {
      final j = (i + 1) % corners.length;
      sum += corners[i].position.x * corners[j].position.y;
      sum -= corners[j].position.x * corners[i].position.y;
    }
    return sum.abs() / 2.0;
  }

  double calculatePerimeter() {
    if (corners.length < 2) return 0;
    double total = 0;
    for (int i = 0; i < corners.length; i++) {
      final j = (i + 1) % corners.length;
      total += corners[i].position.distanceTo(corners[j].position);
    }
    return total;
  }
}

class MeasurementProject {
  final String id;
  final String name;
  final String? siteName;
  final String? address;
  final MeasurementSystem system;
  final DateTime createdAt;
  final DateTime updatedAt;
  final MeasurementStatus status;
  final List<FloorPlan> rooms;
  final List<Marker> markers;
  final double? totalArea;
  final String? notes;

  MeasurementProject({
    String? id,
    required this.name,
    this.siteName,
    this.address,
    required this.system,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.status = MeasurementStatus.idle,
    List<FloorPlan>? rooms,
    List<Marker>? markers,
    this.totalArea,
    this.notes,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       rooms = rooms ?? [],
       markers = markers ?? [];

  MeasurementProject copyWith({
    String? name,
    String? siteName,
    String? address,
    MeasurementSystem? system,
    MeasurementStatus? status,
    List<FloorPlan>? rooms,
    List<Marker>? markers,
    double? totalArea,
    String? notes,
  }) {
    return MeasurementProject(
      id: id,
      name: name ?? this.name,
      siteName: siteName ?? this.siteName,
      address: address ?? this.address,
      system: system ?? this.system,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      status: status ?? this.status,
      rooms: rooms ?? this.rooms,
      markers: markers ?? this.markers,
      totalArea: totalArea ?? this.totalArea,
      notes: notes ?? this.notes,
    );
  }
}
