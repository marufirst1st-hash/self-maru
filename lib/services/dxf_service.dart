import 'dart:typed_data';
import '../models/measurement.dart';

class DxfService {
  // FloorPlan 데이터로 DXF 파일 생성
  Uint8List generateDxf(MeasurementProject project) {
    final buffer = StringBuffer();

    _writeHeader(buffer, project);
    _writeTables(buffer);
    _writeBlocks(buffer);
    _writeEntities(buffer, project);
    _writeObjects(buffer);
    _writeEof(buffer);

    return Uint8List.fromList(buffer.toString().codeUnits);
  }

  void _writeHeader(StringBuffer buf, MeasurementProject project) {
    // 전체 바운딩 박스 계산
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;

    for (final room in project.rooms) {
      for (final corner in room.corners) {
        if (corner.position.x < minX) minX = corner.position.x;
        if (corner.position.y < minY) minY = corner.position.y;
        if (corner.position.x > maxX) maxX = corner.position.x;
        if (corner.position.y > maxY) maxY = corner.position.y;
      }
    }
    if (minX == double.infinity) { minX = 0; minY = 0; maxX = 10; maxY = 10; }

    buf.writeln('  0\nSECTION');
    buf.writeln('  2\nHEADER');
    buf.writeln('  9\n\$ACADVER');
    buf.writeln('  1\nAC1015');
    buf.writeln('  9\n\$INSBASE');
    buf.writeln(' 10\n0.0');
    buf.writeln(' 20\n0.0');
    buf.writeln(' 30\n0.0');
    buf.writeln('  9\n\$EXTMIN');
    buf.writeln(' 10\n${minX.toStringAsFixed(4)}');
    buf.writeln(' 20\n${minY.toStringAsFixed(4)}');
    buf.writeln(' 30\n0.0');
    buf.writeln('  9\n\$EXTMAX');
    buf.writeln(' 10\n${maxX.toStringAsFixed(4)}');
    buf.writeln(' 20\n${maxY.toStringAsFixed(4)}');
    buf.writeln(' 30\n0.0');
    buf.writeln('  9\n\$LUNITS');
    buf.writeln(' 70\n4'); // 미터 단위
    buf.writeln('  9\n\$LUPREC');
    buf.writeln(' 70\n4');
    buf.writeln('  0\nENDSEC');
  }

  void _writeTables(StringBuffer buf) {
    buf.writeln('  0\nSECTION');
    buf.writeln('  2\nTABLES');

    // LTYPE 테이블
    buf.writeln('  0\nTABLE');
    buf.writeln('  2\nLTYPE');
    buf.writeln(' 70\n1');
    buf.writeln('  0\nLTYPE');
    buf.writeln('  2\nCONTINUOUS');
    buf.writeln(' 70\n0');
    buf.writeln('  3\nSolid line');
    buf.writeln(' 72\n65');
    buf.writeln(' 73\n0');
    buf.writeln(' 40\n0.0');
    buf.writeln('  0\nENDTAB');

    // LAYER 테이블
    buf.writeln('  0\nTABLE');
    buf.writeln('  2\nLAYER');
    buf.writeln(' 70\n3');

    // 레이어: 벽
    buf.writeln('  0\nLAYER');
    buf.writeln('  2\nWALLS');
    buf.writeln(' 70\n0');
    buf.writeln(' 62\n5'); // 파란색
    buf.writeln('  6\nCONTINUOUS');

    // 레이어: 치수
    buf.writeln('  0\nLAYER');
    buf.writeln('  2\nDIMENSIONS');
    buf.writeln(' 70\n0');
    buf.writeln(' 62\n3'); // 초록색
    buf.writeln('  6\nCONTINUOUS');

    // 레이어: 텍스트
    buf.writeln('  0\nLAYER');
    buf.writeln('  2\nTEXT');
    buf.writeln(' 70\n0');
    buf.writeln(' 62\n7'); // 흰색
    buf.writeln('  6\nCONTINUOUS');

    buf.writeln('  0\nENDTAB');
    buf.writeln('  0\nENDSEC');
  }

  void _writeBlocks(StringBuffer buf) {
    buf.writeln('  0\nSECTION');
    buf.writeln('  2\nBLOCKS');
    buf.writeln('  0\nBLOCK');
    buf.writeln('  8\n0');
    buf.writeln('  2\n*MODEL_SPACE');
    buf.writeln(' 70\n0');
    buf.writeln(' 10\n0.0');
    buf.writeln(' 20\n0.0');
    buf.writeln(' 30\n0.0');
    buf.writeln('  3\n*MODEL_SPACE');
    buf.writeln('  1\n');
    buf.writeln('  0\nENDBLK');
    buf.writeln('  8\n0');
    buf.writeln('  0\nENDSEC');
  }

  void _writeEntities(StringBuffer buf, MeasurementProject project) {
    buf.writeln('  0\nSECTION');
    buf.writeln('  2\nENTITIES');

    // 방별 오프셋 (여러 방을 나란히 배치)
    double offsetX = 0;

    for (int roomIdx = 0; roomIdx < project.rooms.length; roomIdx++) {
      final room = project.rooms[roomIdx];
      if (room.corners.isEmpty) continue;

      // 방 경계 계산
      double roomMinX = room.corners.map((c) => c.position.x).reduce((a, b) => a < b ? a : b);
      double roomMaxX = room.corners.map((c) => c.position.x).reduce((a, b) => a > b ? a : b);

      // 벽 그리기 (LWPOLYLINE)
      buf.writeln('  0\nLWPOLYLINE');
      buf.writeln('  8\nWALLS');
      buf.writeln(' 90\n${room.corners.length}');
      buf.writeln(' 70\n1'); // 닫힌 폴리라인
      buf.writeln(' 43\n0.1'); // 선 두께 0.1m

      for (final corner in room.corners) {
        buf.writeln(' 10\n${(corner.position.x + offsetX).toStringAsFixed(4)}');
        buf.writeln(' 20\n${corner.position.y.toStringAsFixed(4)}');
      }

      // 치수선 그리기
      for (int i = 0; i < room.corners.length; i++) {
        final j = (i + 1) % room.corners.length;
        final c1 = room.corners[i];
        final c2 = room.corners[j];
        final dist = c1.position.distanceTo(c2.position);

        final midX = (c1.position.x + c2.position.x) / 2 + offsetX;
        final midY = (c1.position.y + c2.position.y) / 2;

        // 치수 텍스트
        buf.writeln('  0\nTEXT');
        buf.writeln('  8\nDIMENSIONS');
        buf.writeln(' 10\n${midX.toStringAsFixed(4)}');
        buf.writeln(' 20\n${(midY + 0.15).toStringAsFixed(4)}');
        buf.writeln(' 30\n0.0');
        buf.writeln(' 40\n0.15'); // 텍스트 높이
        buf.writeln(' 62\n3');
        buf.writeln('  1\n${dist.toStringAsFixed(2)}m');
        buf.writeln(' 72\n1'); // 가운데 정렬
        buf.writeln(' 73\n0');
      }

      // 방 이름 텍스트
      double centerX = room.corners.map((c) => c.position.x).reduce((a, b) => a + b) / room.corners.length + offsetX;
      double centerY = room.corners.map((c) => c.position.y).reduce((a, b) => a + b) / room.corners.length;

      buf.writeln('  0\nTEXT');
      buf.writeln('  8\nTEXT');
      buf.writeln(' 10\n${centerX.toStringAsFixed(4)}');
      buf.writeln(' 20\n${(centerY + 0.2).toStringAsFixed(4)}');
      buf.writeln(' 30\n0.0');
      buf.writeln(' 40\n0.2');
      buf.writeln(' 62\n7');
      buf.writeln('  1\n${room.name}');
      buf.writeln(' 72\n1');
      buf.writeln(' 73\n0');

      // 면적 텍스트
      final area = room.area ?? room.calculateArea();
      buf.writeln('  0\nTEXT');
      buf.writeln('  8\nTEXT');
      buf.writeln(' 10\n${centerX.toStringAsFixed(4)}');
      buf.writeln(' 20\n${(centerY - 0.1).toStringAsFixed(4)}');
      buf.writeln(' 30\n0.0');
      buf.writeln(' 40\n0.15');
      buf.writeln(' 62\n2');
      buf.writeln('  1\n${area.toStringAsFixed(2)} m2');
      buf.writeln(' 72\n1');
      buf.writeln(' 73\n0');

      // 다음 방 오프셋
      offsetX += (roomMaxX - roomMinX) + 2.0;
    }

    // 프로젝트 제목
    buf.writeln('  0\nTEXT');
    buf.writeln('  8\nTEXT');
    buf.writeln(' 10\n0.0');
    buf.writeln(' 20\n-1.5');
    buf.writeln(' 30\n0.0');
    buf.writeln(' 40\n0.3');
    buf.writeln(' 62\n7');
    buf.writeln('  1\n${project.name}');
    buf.writeln(' 72\n0');

    // 총 면적
    if (project.totalArea != null) {
      buf.writeln('  0\nTEXT');
      buf.writeln('  8\nTEXT');
      buf.writeln(' 10\n0.0');
      buf.writeln(' 20\n-2.0');
      buf.writeln(' 30\n0.0');
      buf.writeln(' 40\n0.2');
      buf.writeln(' 62\n3');
      buf.writeln('  1\nTotal: ${project.totalArea!.toStringAsFixed(2)} m2');
      buf.writeln(' 72\n0');
    }

    buf.writeln('  0\nENDSEC');
  }

  void _writeObjects(StringBuffer buf) {
    buf.writeln('  0\nSECTION');
    buf.writeln('  2\nOBJECTS');
    buf.writeln('  0\nDICTIONARY');
    buf.writeln('  5\nC');
    buf.writeln('100\nAcDbDictionary');
    buf.writeln('  0\nENDSEC');
  }

  void _writeEof(StringBuffer buf) {
    buf.writeln('  0\nEOF');
  }

  // DXF 파일명 생성
  String generateFileName(MeasurementProject project) {
    final sanitized = project.name.replaceAll(RegExp(r'[^\w가-힣]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${sanitized}_$timestamp.dxf';
  }
}
