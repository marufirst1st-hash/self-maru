import 'dart:convert';
import '../models/room.dart';

/// Hive에 저장되는 프로젝트 모델
class ProjectModel {
  final String id;
  String name;
  String? siteName;
  String? address;
  String mode; // 'A', 'B', 'C'
  String status; // 'idle', 'scanning', 'completed'
  double totalArea;
  int roomCount;
  String roomsJson; // Room 리스트를 JSON 문자열로 저장
  DateTime createdAt;
  DateTime updatedAt;
  String? dxfUrl;
  List<String> photoUrls;
  String? notes;

  ProjectModel({
    required this.id,
    required this.name,
    this.siteName,
    this.address,
    required this.mode,
    this.status = 'idle',
    this.totalArea = 0,
    this.roomCount = 0,
    this.roomsJson = '[]',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.dxfUrl,
    List<String>? photoUrls,
    this.notes,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        photoUrls = photoUrls ?? [];

  /// Room 리스트로 변환
  List<Room> toRooms() {
    try {
      final list = jsonDecode(roomsJson) as List;
      return list.map((m) => Room.fromMap(m as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Room 리스트를 JSON으로 저장
  void setRooms(List<Room> rooms) {
    roomsJson = jsonEncode(rooms.map((r) => r.toMap()).toList());
    roomCount = rooms.length;
    totalArea = rooms.fold<double>(0.0, (sum, r) => sum + r.area);
    updatedAt = DateTime.now();
  }

  /// 완료 처리
  void complete(List<Room> rooms) {
    setRooms(rooms);
    status = 'completed';
    updatedAt = DateTime.now();
  }

  /// Map 변환 (Hive 저장용)
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'siteName': siteName,
        'address': address,
        'mode': mode,
        'status': status,
        'totalArea': totalArea,
        'roomCount': roomCount,
        'roomsJson': roomsJson,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'dxfUrl': dxfUrl,
        'photoUrls': photoUrls,
        'notes': notes,
      };

  factory ProjectModel.fromMap(Map<dynamic, dynamic> map) {
    return ProjectModel(
      id: map['id'] as String,
      name: map['name'] as String,
      siteName: map['siteName'] as String?,
      address: map['address'] as String?,
      mode: map['mode'] as String? ?? 'B',
      status: map['status'] as String? ?? 'idle',
      totalArea: (map['totalArea'] as num?)?.toDouble() ?? 0,
      roomCount: (map['roomCount'] as num?)?.toInt() ?? 0,
      roomsJson: map['roomsJson'] as String? ?? '[]',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : null,
      dxfUrl: map['dxfUrl'] as String?,
      photoUrls: (map['photoUrls'] as List?)?.cast<String>() ?? [],
      notes: map['notes'] as String?,
    );
  }
}
