import 'dart:typed_data';
import '../models/room.dart';

/// DXF 도면 출력
/// Room → DXF 문자열 (LINE + DIMENSION + TEXT)
/// AutoCAD/SketchUp 호환
class DxfExporter {
  /// 단일 Room → DXF bytes
  Uint8List exportRoom(Room room, {String? title}) {
    final buf = StringBuffer();
    _writeHeader(buf, room);
    _writeTables(buf);
    _writeBlocks(buf);
    _writeEntities(buf, room, title: title);
    _writeEof(buf);
    return Uint8List.fromList(buf.toString().codeUnits);
  }

  /// 여러 Room → DXF bytes (나란히 배치)
  Uint8List exportRooms(List<Room> rooms, {String? title, double? totalArea}) {
    final buf = StringBuffer();
    _writeHeaderMulti(buf, rooms);
    _writeTables(buf);
    _writeBlocks(buf);
    _writeEntitiesMulti(buf, rooms, title: title, totalArea: totalArea);
    _writeEof(buf);
    return Uint8List.fromList(buf.toString().codeUnits);
  }

  /// 파일명 생성
  String generateFileName(String projectName) {
    final sanitized = projectName.replaceAll(RegExp(r'[^\w가-힣]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${sanitized}_$timestamp.dxf';
  }

  void _writeHeader(StringBuffer buf, Room room) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final c in room.corners) {
      if (c.position.dx < minX) minX = c.position.dx;
      if (c.position.dy < minY) minY = c.position.dy;
      if (c.position.dx > maxX) maxX = c.position.dx;
      if (c.position.dy > maxY) maxY = c.position.dy;
    }
    if (minX == double.infinity) {
      minX = 0; minY = 0; maxX = 10; maxY = 10;
    }
    _writeHeaderSection(buf, minX, minY, maxX, maxY);
  }

  void _writeHeaderMulti(StringBuffer buf, List<Room> rooms) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final room in rooms) {
      for (final c in room.corners) {
        if (c.position.dx < minX) minX = c.position.dx;
        if (c.position.dy < minY) minY = c.position.dy;
        if (c.position.dx > maxX) maxX = c.position.dx;
        if (c.position.dy > maxY) maxY = c.position.dy;
      }
    }
    if (minX == double.infinity) {
      minX = 0; minY = 0; maxX = 10; maxY = 10;
    }
    _writeHeaderSection(buf, minX, minY, maxX + rooms.length * 2, maxY);
  }

  void _writeHeaderSection(StringBuffer buf, double minX, double minY, double maxX, double maxY) {
    buf.writeln('  0\nSECTION');
    buf.writeln('  2\nHEADER');
    buf.writeln('  9\n\$ACADVER\n  1\nAC1015');
    buf.writeln('  9\n\$INSBASE\n 10\n0.0\n 20\n0.0\n 30\n0.0');
    buf.writeln('  9\n\$EXTMIN\n 10\n${minX.toStringAsFixed(4)}\n 20\n${minY.toStringAsFixed(4)}\n 30\n0.0');
    buf.writeln('  9\n\$EXTMAX\n 10\n${maxX.toStringAsFixed(4)}\n 20\n${maxY.toStringAsFixed(4)}\n 30\n0.0');
    buf.writeln('  9\n\$LUNITS\n 70\n4');
    buf.writeln('  9\n\$LUPREC\n 70\n4');
    buf.writeln('  0\nENDSEC');
  }

  void _writeTables(StringBuffer buf) {
    buf.writeln('  0\nSECTION\n  2\nTABLES');
    // LTYPE
    buf.writeln('  0\nTABLE\n  2\nLTYPE\n 70\n1');
    buf.writeln('  0\nLTYPE\n  2\nCONTINUOUS\n 70\n0\n  3\nSolid line\n 72\n65\n 73\n0\n 40\n0.0');
    buf.writeln('  0\nENDTAB');
    // LAYER
    buf.writeln('  0\nTABLE\n  2\nLAYER\n 70\n3');
    buf.writeln('  0\nLAYER\n  2\nWALLS\n 70\n0\n 62\n5\n  6\nCONTINUOUS');
    buf.writeln('  0\nLAYER\n  2\nDIMENSIONS\n 70\n0\n 62\n3\n  6\nCONTINUOUS');
    buf.writeln('  0\nLAYER\n  2\nTEXT\n 70\n0\n 62\n7\n  6\nCONTINUOUS');
    buf.writeln('  0\nENDTAB\n  0\nENDSEC');
  }

  void _writeBlocks(StringBuffer buf) {
    buf.writeln('  0\nSECTION\n  2\nBLOCKS');
    buf.writeln('  0\nBLOCK\n  8\n0\n  2\n*MODEL_SPACE\n 70\n0\n 10\n0.0\n 20\n0.0\n 30\n0.0\n  3\n*MODEL_SPACE\n  1\n');
    buf.writeln('  0\nENDBLK\n  8\n0\n  0\nENDSEC');
  }

  void _writeEntities(StringBuffer buf, Room room, {String? title}) {
    buf.writeln('  0\nSECTION\n  2\nENTITIES');
    _writeRoomEntities(buf, room, 0);
    if (title != null) {
      _writeText(buf, 0, -1.5, title, height: 0.3);
    }
    _writeText(buf, 0, -2.0, '${room.area.toStringAsFixed(2)} m2', height: 0.2, color: 3);
    buf.writeln('  0\nENDSEC');
  }

  void _writeEntitiesMulti(StringBuffer buf, List<Room> rooms, {String? title, double? totalArea}) {
    buf.writeln('  0\nSECTION\n  2\nENTITIES');
    double offsetX = 0;
    for (final room in rooms) {
      if (room.corners.isEmpty) continue;
      _writeRoomEntities(buf, room, offsetX);
      final maxX = room.corners.map((c) => c.position.dx).reduce((a, b) => a > b ? a : b);
      final minX = room.corners.map((c) => c.position.dx).reduce((a, b) => a < b ? a : b);
      offsetX += (maxX - minX) + 2.0;
    }
    if (title != null) {
      _writeText(buf, 0, -1.5, title, height: 0.3);
    }
    if (totalArea != null) {
      _writeText(buf, 0, -2.0, 'Total: ${totalArea.toStringAsFixed(2)} m2', height: 0.2, color: 3);
    }
    buf.writeln('  0\nENDSEC');
  }

  void _writeRoomEntities(StringBuffer buf, Room room, double offsetX) {
    if (room.corners.isEmpty) return;

    // LWPOLYLINE (벽)
    buf.writeln('  0\nLWPOLYLINE\n  8\nWALLS\n 90\n${room.corners.length}\n 70\n1\n 43\n0.1');
    for (final c in room.corners) {
      buf.writeln(' 10\n${(c.position.dx + offsetX).toStringAsFixed(4)}\n 20\n${c.position.dy.toStringAsFixed(4)}');
    }

    // 치수 텍스트
    for (int i = 0; i < room.corners.length; i++) {
      final j = (i + 1) % room.corners.length;
      final c1 = room.corners[i].position;
      final c2 = room.corners[j].position;
      final dist = (c2 - c1).distance;
      final midX = (c1.dx + c2.dx) / 2 + offsetX;
      final midY = (c1.dy + c2.dy) / 2 + 0.15;
      _writeText(buf, midX, midY, '${dist.toStringAsFixed(2)}m', height: 0.15, color: 3, layer: 'DIMENSIONS', centered: true);
    }

    // 방 이름 + 면적
    final cx = room.corners.map((c) => c.position.dx).reduce((a, b) => a + b) / room.corners.length + offsetX;
    final cy = room.corners.map((c) => c.position.dy).reduce((a, b) => a + b) / room.corners.length;
    _writeText(buf, cx, cy + 0.2, 'Room', height: 0.2, centered: true);
    _writeText(buf, cx, cy - 0.1, '${room.area.toStringAsFixed(2)} m2', height: 0.15, color: 2, centered: true);
  }

  void _writeText(StringBuffer buf, double x, double y, String text, {double height = 0.2, int color = 7, String layer = 'TEXT', bool centered = false}) {
    buf.writeln('  0\nTEXT\n  8\n$layer\n 10\n${x.toStringAsFixed(4)}\n 20\n${y.toStringAsFixed(4)}\n 30\n0.0\n 40\n$height\n 62\n$color\n  1\n$text');
    if (centered) {
      buf.writeln(' 72\n1\n 73\n0');
    }
  }

  void _writeEof(StringBuffer buf) {
    buf.writeln('  0\nSECTION\n  2\nOBJECTS\n  0\nDICTIONARY\n  5\nC\n100\nAcDbDictionary\n  0\nENDSEC');
    buf.writeln('  0\nEOF');
  }
}
