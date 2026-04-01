import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/measurement.dart';
import '../utils/app_colors.dart';

class FloorPlanPainter extends CustomPainter {
  final List<Corner> corners;
  final bool showDimensions;
  final bool showArea;
  final bool isScanning;
  final double scanProgress;
  final Color lineColor;
  final Color fillColor;
  final Color cornerColor;

  FloorPlanPainter({
    required this.corners,
    this.showDimensions = true,
    this.showArea = true,
    this.isScanning = false,
    this.scanProgress = 0.0,
    this.lineColor = AppColors.wallLine,
    this.fillColor = const Color(0x2200BFA5),
    this.cornerColor = AppColors.cornerPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.isEmpty) return;

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final c in corners) {
      minX = math.min(minX, c.position.x);
      minY = math.min(minY, c.position.y);
      maxX = math.max(maxX, c.position.x);
      maxY = math.max(maxY, c.position.y);
    }

    final dataW = maxX - minX;
    final dataH = maxY - minY;
    if (dataW == 0 && dataH == 0) return;

    final padding = 50.0;
    final availW = size.width - padding * 2;
    final availH = size.height - padding * 2;
    final scale = math.min(availW / (dataW == 0 ? 1 : dataW), availH / (dataH == 0 ? 1 : dataH));
    final offsetX = padding + (availW - dataW * scale) / 2;
    final offsetY = padding + (availH - dataH * scale) / 2;

    Offset toScreen(Point3D p) {
      return Offset(offsetX + (p.x - minX) * scale, offsetY + (p.y - minY) * scale);
    }

    // Fill
    if (corners.length >= 3) {
      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      final path = Path();
      path.moveTo(toScreen(corners[0].position).dx, toScreen(corners[0].position).dy);
      for (int i = 1; i < corners.length; i++) {
        path.lineTo(toScreen(corners[i].position).dx, toScreen(corners[i].position).dy);
      }
      path.close();
      canvas.drawPath(path, fillPaint);
    }

    // Grid
    final gridPaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.1)
      ..strokeWidth = 0.5;
    for (double x = minX; x <= maxX; x += 1.0) {
      final s = toScreen(Point3D(x: x, y: minY));
      final e = toScreen(Point3D(x: x, y: maxY));
      canvas.drawLine(s, e, gridPaint);
    }
    for (double y = minY; y <= maxY; y += 1.0) {
      final s = toScreen(Point3D(x: minX, y: y));
      final e = toScreen(Point3D(x: maxX, y: y));
      canvas.drawLine(s, e, gridPaint);
    }

    // Walls
    final wallPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (isScanning) {
      final drawCount = (corners.length * scanProgress).ceil().clamp(0, corners.length);
      for (int i = 0; i < drawCount && i < corners.length; i++) {
        final j = (i + 1) % corners.length;
        if (j == 0 && drawCount < corners.length) continue;
        canvas.drawLine(toScreen(corners[i].position), toScreen(corners[j].position), wallPaint);
      }
    } else {
      for (int i = 0; i < corners.length; i++) {
        final j = (i + 1) % corners.length;
        canvas.drawLine(toScreen(corners[i].position), toScreen(corners[j].position), wallPaint);
      }
    }

    // Corners
    final cornerPaint = Paint()..color = cornerColor..style = PaintingStyle.fill;
    final cornerBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 0; i < corners.length; i++) {
      final pos = toScreen(corners[i].position);
      canvas.drawCircle(pos, 6, cornerPaint);
      canvas.drawCircle(pos, 6, cornerBorderPaint);
    }

    // Dimensions
    if (showDimensions && corners.length >= 2) {
      for (int i = 0; i < corners.length; i++) {
        final j = (i + 1) % corners.length;
        final p1 = toScreen(corners[i].position);
        final p2 = toScreen(corners[j].position);
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final dist = corners[i].position.distanceTo(corners[j].position);
        final text = '${dist.toStringAsFixed(2)}m';

        final angle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);
        final perpX = -math.sin(angle) * 20;
        final perpY = math.cos(angle) * 20;

        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final bgRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(mid.dx + perpX, mid.dy + perpY), width: tp.width + 12, height: tp.height + 6),
          const Radius.circular(4),
        );
        canvas.drawRRect(bgRect, Paint()..color = AppColors.bgCard.withValues(alpha: 0.9));
        tp.paint(canvas, Offset(mid.dx + perpX - tp.width / 2, mid.dy + perpY - tp.height / 2));
      }
    }

    // Area label
    if (showArea && corners.length >= 3) {
      double cx = 0, cy = 0;
      for (final c in corners) {
        final s = toScreen(c.position);
        cx += s.dx;
        cy += s.dy;
      }
      cx /= corners.length;
      cy /= corners.length;

      double areaVal = 0;
      for (int i = 0; i < corners.length; i++) {
        final j = (i + 1) % corners.length;
        areaVal += corners[i].position.x * corners[j].position.y;
        areaVal -= corners[j].position.x * corners[i].position.y;
      }
      areaVal = areaVal.abs() / 2.0;

      final areaText = '${areaVal.toStringAsFixed(2)} m\u00B2';
      final tp = TextPainter(
        text: TextSpan(
          text: areaText,
          style: const TextStyle(color: AppColors.accent, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final bgRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: tp.width + 20, height: tp.height + 12),
        const Radius.circular(8),
      );
      canvas.drawRRect(bgRect, Paint()..color = AppColors.bgDark.withValues(alpha: 0.85));
      canvas.drawRRect(bgRect, Paint()..color = AppColors.accent.withValues(alpha: 0.3)..style = PaintingStyle.stroke..strokeWidth = 1.5);
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant FloorPlanPainter oldDelegate) => true;
}
