import "dart:math" as math;
import "package:flutter/material.dart";

/// Universal Dynamic Canvas 2D Drawing Engine for Lynx Mini-Programs.
/// Allows Mini-Programs (TSX / JS) to emit standard 2D canvas drawing commands
/// (paths, curves, shapes, gradients, text) and renders them natively using
/// Flutter Canvas / GPU acceleration (Skia/Impeller) without requiring host recompilation.
class LynxDynamicCanvas extends StatelessWidget {
  final List<Map<String, dynamic>> commands;
  final double? width;
  final double? height;
  final Color backgroundColor;

  const LynxDynamicCanvas({
    super.key,
    required this.commands,
    this.width,
    this.height,
    this.backgroundColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: backgroundColor,
      child: CustomPaint(
        painter: LynxDynamicCanvasPainter(commands: commands),
        size: Size(width ?? double.infinity, height ?? double.infinity),
      ),
    );
  }
}

/// Painter that executes the command stream onto Flutter's Canvas.
class LynxDynamicCanvasPainter extends CustomPainter {
  final List<Map<String, dynamic>> commands;

  LynxDynamicCanvasPainter({required this.commands});

  @override
  void paint(Canvas canvas, Size size) {
    Paint strokePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Paint fillPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    Path currentPath = Path();

    for (final cmd in commands) {
      final String op = (cmd["op"] ?? "").toString();

      switch (op) {
        case "beginPath":
          currentPath = Path();
          break;

        case "moveTo":
          final x = _toDouble(cmd["x"]);
          final y = _toDouble(cmd["y"]);
          currentPath.moveTo(x, y);
          break;

        case "lineTo":
          final x = _toDouble(cmd["x"]);
          final y = _toDouble(cmd["y"]);
          currentPath.lineTo(x, y);
          break;

        case "cubicTo":
        case "bezierCurveTo":
          final cp1x = _toDouble(cmd["cp1x"]);
          final cp1y = _toDouble(cmd["cp1y"]);
          final cp2x = _toDouble(cmd["cp2x"]);
          final cp2y = _toDouble(cmd["cp2y"]);
          final x = _toDouble(cmd["x"]);
          final y = _toDouble(cmd["y"]);
          currentPath.cubicTo(cp1x, cp1y, cp2x, cp2y, x, y);
          break;

        case "quadraticCurveTo":
          final cpx = _toDouble(cmd["cpx"]);
          final cpy = _toDouble(cmd["cpy"]);
          final x = _toDouble(cmd["x"]);
          final y = _toDouble(cmd["y"]);
          currentPath.quadraticBezierTo(cpx, cpy, x, y);
          break;

        case "closePath":
          currentPath.close();
          break;

        case "stroke":
          canvas.drawPath(currentPath, strokePaint);
          break;

        case "fill":
          canvas.drawPath(currentPath, fillPaint);
          break;

        case "drawDashedLine":
        case "dashedLine":
          final x1 = _toDouble(cmd["x1"]);
          final y1 = _toDouble(cmd["y1"]);
          final x2 = _toDouble(cmd["x2"]);
          final y2 = _toDouble(cmd["y2"]);
          final dashW = _toDouble(cmd["dash"] ?? 4.0);
          final gapW = _toDouble(cmd["gap"] ?? 4.0);
          final dx = x2 - x1;
          final dy = y2 - y1;
          final dist = math.sqrt(dx * dx + dy * dy);
          if (dist > 0) {
            final step = dashW + gapW;
            final ux = dx / dist;
            final uy = dy / dist;
            double cur = 0.0;
            while (cur < dist) {
              final end = math.min(cur + dashW, dist);
              canvas.drawLine(
                Offset(x1 + ux * cur, y1 + uy * cur),
                Offset(x1 + ux * end, y1 + uy * end),
                strokePaint,
              );
              cur += step;
            }
          }
          break;

        case "rect":
        case "drawRect":
          final x = _toDouble(cmd["x"]);
          final y = _toDouble(cmd["y"]);
          final w = _toDouble(cmd["w"] ?? cmd["width"]);
          final h = _toDouble(cmd["h"] ?? cmd["height"]);
          final isFill = cmd["isFill"] ?? true;
          canvas.drawRect(
              Rect.fromLTWH(x, y, w, h), isFill ? fillPaint : strokePaint);
          break;

        case "roundRect":
        case "drawRRect":
          final x = _toDouble(cmd["x"]);
          final y = _toDouble(cmd["y"]);
          final w = _toDouble(cmd["w"] ?? cmd["width"]);
          final h = _toDouble(cmd["h"] ?? cmd["height"]);
          final r = _toDouble(cmd["r"] ?? cmd["radius"] ?? 4.0);
          final isFill = cmd["isFill"] ?? true;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
            isFill ? fillPaint : strokePaint,
          );
          break;

        case "circle":
        case "drawCircle":
          final x = _toDouble(cmd["x"]);
          final y = _toDouble(cmd["y"]);
          final r = _toDouble(cmd["r"] ?? cmd["radius"]);
          final isFill = cmd["isFill"] ?? true;
          canvas.drawCircle(Offset(x, y), r, isFill ? fillPaint : strokePaint);
          break;

        case "arc":
        case "drawArc":
          final x = _toDouble(cmd["x"]);
          final y = _toDouble(cmd["y"]);
          final r = _toDouble(cmd["r"] ?? cmd["radius"]);
          final startAngle = _toDouble(cmd["startAngle"]) * (math.pi / 180.0);
          final sweepAngle = _toDouble(cmd["sweepAngle"]) * (math.pi / 180.0);
          final isFill = cmd["isFill"] ?? false;
          canvas.drawArc(
            Rect.fromCircle(center: Offset(x, y), radius: r),
            startAngle,
            sweepAngle,
            false,
            isFill ? fillPaint : strokePaint,
          );
          break;

        case "setStrokeColor":
          strokePaint = Paint()
            ..color = _parseColor(cmd["color"])
            ..strokeWidth = strokePaint.strokeWidth
            ..style = PaintingStyle.stroke
            ..strokeCap = strokePaint.strokeCap
            ..strokeJoin = strokePaint.strokeJoin;
          break;

        case "setFillColor":
          fillPaint = Paint()
            ..color = _parseColor(cmd["color"])
            ..style = PaintingStyle.fill;
          break;

        case "setLineWidth":
          strokePaint.strokeWidth =
              _toDouble(cmd["width"] ?? cmd["lineWidth"] ?? 1.0);
          break;

        case "setLinearGradient":
          final colors = (cmd["colors"] as List? ?? [])
              .map((c) => _parseColor(c))
              .toList();
          final x0 = _toDouble(cmd["x0"]);
          final y0 = _toDouble(cmd["y0"]);
          final x1 = _toDouble(cmd["x1"]);
          final y1 = _toDouble(cmd["y1"]);
          final rect = Rect.fromPoints(Offset(x0, y0), Offset(x1, y1));
          fillPaint.shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors.isEmpty ? [Colors.blue, Colors.cyan] : colors,
          ).createShader(rect);
          break;

        case "drawText":
          final text = (cmd["text"] ?? "").toString();
          final x = _toDouble(cmd["x"]);
          final y = _toDouble(cmd["y"]);
          final fontSize = _toDouble(cmd["fontSize"] ?? 12.0);
          final color = _parseColor(cmd["color"] ?? "#000000");
          final isBold = cmd["isBold"] ?? false;

          final tp = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          tp.layout();
          tp.paint(canvas, Offset(x, y));
          break;

        case "save":
          canvas.save();
          break;

        case "restore":
          canvas.restore();
          break;

        case "translate":
          final tx = _toDouble(cmd["x"]);
          final ty = _toDouble(cmd["y"]);
          canvas.translate(tx, ty);
          break;

        case "rotate":
          final angle = _toDouble(cmd["angle"]) * (math.pi / 180.0);
          canvas.rotate(angle);
          break;

        case "scale":
          final sx = _toDouble(cmd["x"] ?? cmd["sx"] ?? 1.0);
          final sy = _toDouble(cmd["y"] ?? cmd["sy"] ?? 1.0);
          canvas.scale(sx, sy);
          break;

        case "clear":
          canvas.drawColor(Colors.transparent, BlendMode.clear);
          break;

        case "clipRect":
          final x = _toDouble(cmd["x"]);
          final y = _toDouble(cmd["y"]);
          final w = _toDouble(cmd["w"]);
          final h = _toDouble(cmd["h"]);
          canvas.clipRect(Rect.fromLTWH(x, y, w, h));
          break;
      }
    }
  }

  double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  Color _parseColor(dynamic colorVal) {
    if (colorVal == null) return Colors.black;
    if (colorVal is int) return Color(colorVal);
    if (colorVal is Color) return colorVal;

    String hex = colorVal.toString().trim().replaceAll("#", "");
    if (hex.length == 6) {
      hex = "FF$hex";
    } else if (hex.length == 3) {
      hex = "FF${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}";
    }
    final int? intVal = int.tryParse(hex, radix: 16);
    return intVal != null ? Color(intVal) : Colors.black;
  }

  @override
  bool shouldRepaint(covariant LynxDynamicCanvasPainter oldDelegate) {
    return oldDelegate.commands != commands;
  }
}
