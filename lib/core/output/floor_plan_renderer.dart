import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/corner.dart';
import '../models/room.dart';
import '../utils/math_utils.dart';

/// Canvas 2D 도면 실시간 렌더링
/// 확정 벽=실선, 추론 벽=점선, 코너=빨간점, 현재위치=파란화살표
class FloorPlanRenderer extends CustomPainter {
  final Room? room;
  final List<Corner>? corners; // room 없이 코너만 그릴 때
  final Offset? currentPosition;
  final double? currentHeading;
  final bool showDimensions;
  final bool showArea;
  final bool isScanning;
  final double scanProgress;
  final Color lineColor;
  final Color fillColor;
  final Color cornerColor;
  final Color currentPosColor;
  final Color dimensionColor;

  FloorPlanRenderer({
    this.room,
    this.corners,
    this.currentPosition,
    this.currentHeading,
    this.showDimensions = true,
    this.showArea = true,
    this.isScanning = false,
    this.scanProgress = 0,
    this.lineColor = const Color(0xFF4FC3F7),
    this.fillColor = const Color(0x154FC3F7),
    this.cornerColor = const Color(0xFFFF5252),
    this.currentPosColor = const Color(0xFF448AFF),
    this.dimensionColor = const Color(0xFF66BB6A),
  });

  List<Corner> get _corners => room?.corners ?? corners ?? [];

  @override
  void paint(Canvas canvas, Size size) {
    if (_corners.isEmpty) return;

    // 좌표 변환: 미터 → 캔버스 픽셀
    final bounds = _getBounds();
    final scale = _calculateScale(bounds, size);
    final offset = _calculateOffset(bounds, size, scale);

    // 채우기
    _drawFill(canvas, scale, offset);
    // 벽
    _drawWalls(canvas, scale, offset);
    // 코너
    _drawCorners(canvas, scale, offset);
    // 치수
    if (showDimensions) _drawDimensions(canvas, scale, offset);
    // 면적
    if (showArea && _corners.length >= 3) _drawArea(canvas, size, scale, offset);
    // 현재 위치
    if (currentPosition != null) _drawCurrentPosition(canvas, scale, offset);
  }

  Rect _getBounds() {
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final c in _corners) {
      minX = math.min(minX, c.position.dx);
      minY = math.min(minY, c.position.dy);
      maxX = math.max(maxX, c.position.dx);
      maxY = math.max(maxY, c.position.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  double _calculateScale(Rect bounds, Size size) {
    final padding = 60.0;
    final availW = size.width - padding * 2;
    final availH = size.height - padding * 2;
    final dataW = bounds.width == 0 ? 1 : bounds.width;
    final dataH = bounds.height == 0 ? 1 : bounds.height;
    return math.min(availW / dataW, availH / dataH);
  }

  Offset _calculateOffset(Rect bounds, Size size, double scale) {
    final centerX = size.width / 2 - (bounds.left + bounds.width / 2) * scale;
    final centerY = size.height / 2 + (bounds.top + bounds.height / 2) * scale;
    return Offset(centerX, centerY);
  }

  Offset _toCanvas(Offset world, double scale, Offset offset) {
    return Offset(
      world.dx * scale + offset.dx,
      -world.dy * scale + offset.dy,
    );
  }

  void _drawFill(Canvas canvas, double scale, Offset offset) {
    if (_corners.length < 3) return;
    final path = Path();
    final first = _toCanvas(_corners[0].position, scale, offset);
    path.moveTo(first.dx, first.dy);
    for (int i = 1; i < _corners.length; i++) {
      final p = _toCanvas(_corners[i].position, scale, offset);
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fillColor);
  }

  void _drawWalls(Canvas canvas, double scale, Offset offset) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // 추론 벽용 점선 페인트
    final inferredPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    if (room != null) {
      for (final wall in room!.walls) {
        final p1 = _toCanvas(wall.start, scale, offset);
        final p2 = _toCanvas(wall.end, scale, offset);
        final usePaint = wall.source == 'inferred' ? inferredPaint : paint;
        canvas.drawLine(p1, p2, usePaint);
      }
    } else {
      // 코너만 있을 때 순서대로 연결
      for (int i = 0; i < _corners.length; i++) {
        final j = (i + 1) % _corners.length;
        final p1 = _toCanvas(_corners[i].position, scale, offset);
        final p2 = _toCanvas(_corners[j].position, scale, offset);
        canvas.drawLine(p1, p2, paint);
      }
    }
  }

  void _drawCorners(Canvas canvas, double scale, Offset offset) {
    for (final c in _corners) {
      final p = _toCanvas(c.position, scale, offset);
      // 외부 원
      canvas.drawCircle(
        p, 6,
        Paint()
          ..color = cornerColor.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill,
      );
      // 내부 원
      canvas.drawCircle(
        p, 3,
        Paint()
          ..color = cornerColor
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawDimensions(Canvas canvas, double scale, Offset offset) {
    for (int i = 0; i < _corners.length; i++) {
      final j = (i + 1) % _corners.length;
      final c1 = _corners[i].position;
      final c2 = _corners[j].position;
      final dist = (c2 - c1).distance;

      final mid = _toCanvas(
        Offset((c1.dx + c2.dx) / 2, (c1.dy + c2.dy) / 2),
        scale,
        offset,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${dist.toStringAsFixed(2)}m',
          style: TextStyle(color: dimensionColor, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height - 4));
    }
  }

  void _drawArea(Canvas canvas, Size size, double scale, Offset offset) {
    final points = _corners.map((c) => c.position).toList();
    final area = MathUtils.shoelace(points);

    final center = Offset(
      points.map((p) => p.dx).reduce((a, b) => a + b) / points.length,
      points.map((p) => p.dy).reduce((a, b) => a + b) / points.length,
    );
    final canvasCenter = _toCanvas(center, scale, offset);

    final tp = TextPainter(
      text: TextSpan(
        text: '${area.toStringAsFixed(2)} m²',
        style: const TextStyle(
          color: Color(0xFFFFD54F),
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(canvasCenter.dx - tp.width / 2, canvasCenter.dy - tp.height / 2));
  }

  void _drawCurrentPosition(Canvas canvas, double scale, Offset offset) {
    if (currentPosition == null) return;
    final p = _toCanvas(currentPosition!, scale, offset);

    // 방향 화살표
    if (currentHeading != null) {
      final arrowLen = 20.0;
      final tip = Offset(
        p.dx + arrowLen * math.sin(currentHeading!),
        p.dy - arrowLen * math.cos(currentHeading!),
      );
      canvas.drawLine(
        p, tip,
        Paint()
          ..color = currentPosColor
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // 현재 위치 점
    canvas.drawCircle(p, 8, Paint()..color = currentPosColor.withValues(alpha: 0.3));
    canvas.drawCircle(p, 4, Paint()..color = currentPosColor);
  }

  @override
  bool shouldRepaint(covariant FloorPlanRenderer oldDelegate) {
    return true; // 실시간 업데이트
  }
}
