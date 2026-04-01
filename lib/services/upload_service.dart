import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'aws_s3_service.dart';
import 'dxf_service.dart';
import '../models/measurement.dart';

class UploadService {
  final AwsS3Service _s3 = AwsS3Service();
  final DxfService _dxf = DxfService();

  // 프로젝트 전체 업로드 (사진 + DXF)
  Future<ProjectUploadResult> uploadProject({
    required MeasurementProject project,
    required List<Uint8List> photoBytes,
    required List<String> photoFileNames,
  }) async {
    final projectId = project.id;
    final List<String> photoUrls = [];
    String? dxfUrl;
    final List<String> errors = [];

    // 1. 사진 업로드
    for (int i = 0; i < photoBytes.length; i++) {
      final fileName = photoFileNames.length > i
          ? photoFileNames[i]
          : 'photo_${i + 1}_${const Uuid().v4().substring(0, 8)}.jpg';

      final url = await _s3.uploadFile(
        projectId: projectId,
        fileName: fileName,
        fileBytes: photoBytes[i],
        contentType: 'image/jpeg',
        fileType: S3FileType.photo,
      );

      if (url != null) {
        photoUrls.add(url);
      } else {
        errors.add('사진 업로드 실패: $fileName');
      }
    }

    // 2. DXF 도면 생성 및 업로드
    if (project.rooms.isNotEmpty) {
      final dxfBytes = _dxf.generateDxf(project);
      final dxfFileName = _dxf.generateFileName(project);

      dxfUrl = await _s3.uploadFile(
        projectId: projectId,
        fileName: dxfFileName,
        fileBytes: dxfBytes,
        contentType: 'application/dxf',
        fileType: S3FileType.drawing,
      );

      if (dxfUrl == null) {
        errors.add('DXF 도면 업로드 실패');
      }
    }

    return ProjectUploadResult(
      projectId: projectId,
      photoUrls: photoUrls,
      dxfUrl: dxfUrl,
      errors: errors,
      success: errors.isEmpty,
    );
  }

  // ERP 전송용 데이터 패키지 생성
  ErpDataPackage buildErpPackage({
    required MeasurementProject project,
    required ProjectUploadResult uploadResult,
  }) {
    // 방별 면적 텍스트
    final roomDetails = project.rooms.map((room) {
      final area = room.area ?? room.calculateArea();
      return '${room.name}: ${area.toStringAsFixed(2)}m²';
    }).join(' / ');

    // 측정 방식
    final method = project.system == MeasurementSystem.systemA
        ? 'Marker Precision (±1~2%)'
        : 'Quick Scan (±3%)';

    return ErpDataPackage(
      projectId: project.id,
      projectName: project.name,
      siteName: project.siteName,
      address: project.address,

      // 텍스트 데이터 (ERP 필드에 직접 입력)
      totalArea: project.totalArea ?? 0,
      roomCount: project.rooms.length,
      roomDetails: roomDetails,
      measurementMethod: method,
      measuredAt: project.updatedAt,

      // 링크 데이터
      photoUrls: uploadResult.photoUrls,
      dxfUrl: uploadResult.dxfUrl,
    );
  }

  // ERP 텍스트 필드 포맷 (복사해서 붙여넣기용)
  String formatForErp(ErpDataPackage data) {
    final sb = StringBuffer();
    sb.writeln('[Floor Measure 측정 데이터]');
    sb.writeln('총 면적: ${data.totalArea.toStringAsFixed(2)} m²');
    sb.writeln('방 수: ${data.roomCount}개');
    sb.writeln('방별 면적: ${data.roomDetails}');
    sb.writeln('측정 방식: ${data.measurementMethod}');
    sb.writeln('측정일: ${_formatDate(data.measuredAt)}');

    if (data.photoUrls.isNotEmpty) {
      sb.writeln('');
      sb.writeln('[현장 사진]');
      for (int i = 0; i < data.photoUrls.length; i++) {
        sb.writeln('사진${i + 1}: ${data.photoUrls[i]}');
      }
    }

    if (data.dxfUrl != null) {
      sb.writeln('');
      sb.writeln('[도면]');
      sb.writeln('DXF 도면: ${data.dxfUrl}');
    }

    return sb.toString();
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// 업로드 결과 모델
class ProjectUploadResult {
  final String projectId;
  final List<String> photoUrls;
  final String? dxfUrl;
  final List<String> errors;
  final bool success;

  const ProjectUploadResult({
    required this.projectId,
    required this.photoUrls,
    this.dxfUrl,
    required this.errors,
    required this.success,
  });
}

// ERP 전송 데이터 패키지
class ErpDataPackage {
  final String projectId;
  final String projectName;
  final String? siteName;
  final String? address;

  // 텍스트 데이터
  final double totalArea;
  final int roomCount;
  final String roomDetails;
  final String measurementMethod;
  final DateTime measuredAt;

  // 링크 데이터
  final List<String> photoUrls;
  final String? dxfUrl;

  const ErpDataPackage({
    required this.projectId,
    required this.projectName,
    this.siteName,
    this.address,
    required this.totalArea,
    required this.roomCount,
    required this.roomDetails,
    required this.measurementMethod,
    required this.measuredAt,
    required this.photoUrls,
    this.dxfUrl,
  });
}
