import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/room.dart';
import '../models/photo.dart';
import 'dxf_exporter.dart';
import '../../services/aws_s3_service.dart';

/// S3 업로드 + ERP 전송
class ErpUploader {
  final AwsS3Service _s3 = AwsS3Service();
  final DxfExporter _dxf = DxfExporter();

  /// 프로젝트 업로드 (DXF + 사진 → S3)
  Future<UploadResult> uploadProject({
    required String projectId,
    required String projectName,
    required List<Room> rooms,
    required List<Photo> photos,
    String mode = 'B',
  }) async {
    final List<String> photoUrls = [];
    String? dxfUrl;
    final List<String> errors = [];

    // 1. 사진 업로드
    for (int i = 0; i < photos.length; i++) {
      final photo = photos[i];
      if (photo.imageBytes == null) continue;

      final fileName = 'photo_${i + 1}_${photo.id.substring(0, 8)}.jpg';
      final url = await _s3.uploadFile(
        projectId: projectId,
        fileName: fileName,
        fileBytes: photo.imageBytes!,
        contentType: 'image/jpeg',
        fileType: S3FileType.photo,
      );

      if (url != null) {
        photo.s3Url = url;
        photoUrls.add(url);
      } else {
        errors.add('Photo upload failed: $fileName');
      }
    }

    // 2. DXF 생성 + 업로드
    if (rooms.isNotEmpty) {
      final dxfBytes = _dxf.exportRooms(
        rooms,
        title: projectName,
        totalArea: rooms.fold<double>(0.0, (sum, r) => sum + r.area),
      );
      final dxfFileName = _dxf.generateFileName(projectName);

      dxfUrl = await _s3.uploadFile(
        projectId: projectId,
        fileName: dxfFileName,
        fileBytes: dxfBytes,
        contentType: 'application/dxf',
        fileType: S3FileType.drawing,
      );

      if (dxfUrl == null) {
        errors.add('DXF upload failed');
      }
    }

    return UploadResult(
      projectId: projectId,
      photoUrls: photoUrls,
      dxfUrl: dxfUrl,
      errors: errors,
    );
  }

  /// ERP JSON 데이터 생성
  Map<String, dynamic> buildErpJson({
    required String projectId,
    required List<Room> rooms,
    required UploadResult uploadResult,
    required String mode,
    List<String> sensorsUsed = const [],
    String? deviceName,
    int? tier,
  }) {
    return {
      'room': rooms.map((r) => {
        'id': r.id,
        'mode': r.mode,
        'area_sqm': r.area,
        'perimeter_m': r.perimeter,
        'confidence': r.confidence,
        'corners': r.corners.map((c) => {
          'x': c.position.dx,
          'y': c.position.dy,
          'angle': c.angle,
        }).toList(),
        'walls': r.walls.asMap().entries.map((e) => {
          'from': e.key,
          'to': (e.key + 1) % r.corners.length,
          'length': e.value.length,
          'source': e.value.source,
        }).toList(),
      }).toList(),
      'photos': uploadResult.photoUrls.map((url) => {
        'url': url,
      }).toList(),
      'dxf_url': uploadResult.dxfUrl,
      'device': deviceName,
      'tier': tier,
      'sensors_used': sensorsUsed,
    };
  }

  /// ERP API 전송
  /// POST /api/sites/{siteId}/measurement
  Future<bool> sendToErp({
    required String baseUrl,
    required String siteId,
    required Map<String, dynamic> erpJson,
    String? authToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sites/$siteId/measurement'),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode(erpJson),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  /// ERP 텍스트 포맷 (클립보드 복사용)
  String formatForClipboard({
    required List<Room> rooms,
    required String mode,
    required UploadResult uploadResult,
    DateTime? measuredAt,
  }) {
    final sb = StringBuffer();
    sb.writeln('[Floor Measure 측정 데이터]');

    final totalArea = rooms.fold(0.0, (sum, r) => sum + r.area);
    sb.writeln('총 면적: ${totalArea.toStringAsFixed(2)} m²');
    sb.writeln('방 수: ${rooms.length}개');

    final roomDetails = rooms.map((r) => '${r.id.substring(0, 6)}: ${r.area.toStringAsFixed(2)}m²').join(' / ');
    sb.writeln('방별 면적: $roomDetails');

    final methodLabel = mode == 'A'
        ? 'Marker Precision (±1%)'
        : mode == 'C'
            ? 'LiDAR Precision (±1%)'
            : 'Smart Scan (±3%)';
    sb.writeln('측정 방식: $methodLabel');

    final dt = measuredAt ?? DateTime.now();
    sb.writeln('측정일: ${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}');

    if (uploadResult.photoUrls.isNotEmpty) {
      sb.writeln('');
      sb.writeln('[현장 사진]');
      for (int i = 0; i < uploadResult.photoUrls.length; i++) {
        sb.writeln('사진${i + 1}: ${uploadResult.photoUrls[i]}');
      }
    }

    if (uploadResult.dxfUrl != null) {
      sb.writeln('');
      sb.writeln('[도면]');
      sb.writeln('DXF 도면: ${uploadResult.dxfUrl}');
    }

    return sb.toString();
  }
}

/// 업로드 결과
class UploadResult {
  final String projectId;
  final List<String> photoUrls;
  final String? dxfUrl;
  final List<String> errors;

  bool get success => errors.isEmpty;

  const UploadResult({
    required this.projectId,
    required this.photoUrls,
    this.dxfUrl,
    required this.errors,
  });
}
