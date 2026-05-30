import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class InteractiveIslandPainterWidget extends StatefulWidget {
  final Map<String, dynamic> gameState;
  final Function(int x, int y) onTapCell;
  final Function(int x, int y)? onPaintCell;
  final Map<String, ui.Image> iconCache;
  final String activeTool;

  const InteractiveIslandPainterWidget({
    super.key,
    required this.gameState,
    required this.onTapCell,
    this.onPaintCell,
    required this.iconCache,
    required this.activeTool,
  });

  @override
  State<InteractiveIslandPainterWidget> createState() => _InteractiveIslandPainterWidgetState();
}

class _InteractiveIslandPainterWidgetState extends State<InteractiveIslandPainterWidget> {
  int _lastPaintedX = -1;
  int _lastPaintedY = -1;

  void _handleGesture(Offset localPosition, bool isDrag) {
    final int width = widget.gameState['width'] ?? 80;
    final int height = widget.gameState['height'] ?? 80;
    const double cellSize = 24.0;

    final int cellX = (localPosition.dx / cellSize).floor();
    final int cellY = (localPosition.dy / cellSize).floor();

    if (cellX >= 0 && cellX < width && cellY >= 0 && cellY < height) {
      if (isDrag) {
        if (cellX != _lastPaintedX || cellY != _lastPaintedY) {
          _lastPaintedX = cellX;
          _lastPaintedY = cellY;
          if (widget.onPaintCell != null) {
            widget.onPaintCell!(cellX, cellY);
          }
        }
      } else {
        _lastPaintedX = cellX;
        _lastPaintedY = cellY;
        widget.onTapCell(cellX, cellY);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final int width = widget.gameState['width'] ?? 80;
    final int height = widget.gameState['height'] ?? 80;
    const double cellSize = 24.0;
    final double canvasWidth = width * cellSize;
    final double canvasHeight = height * cellSize;

    final bool isPainting = widget.activeTool == 'paint_land' || widget.activeTool == 'paint_water';

    return Center(
      child: InteractiveViewer(
        constrained: false,
        minScale: 0.1,
        maxScale: 5.0,
        boundaryMargin: const EdgeInsets.all(1000),
        child: Container(
          width: canvasWidth,
          height: canvasHeight,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF0A3E85), width: 2),
            color: const Color(0xFF0D47A1),
          ),
          child: GestureDetector(
            onTapDown: (details) {
              _handleGesture(details.localPosition, false);
            },
            onPanStart: isPainting
                ? (details) {
                    _lastPaintedX = -1;
                    _lastPaintedY = -1;
                    _handleGesture(details.localPosition, true);
                  }
                : null,
            onPanUpdate: isPainting
                ? (details) {
                    _handleGesture(details.localPosition, true);
                  }
                : null,
            child: CustomPaint(
              size: Size(canvasWidth, canvasHeight),
              painter: IslandPainter(
                gameState: widget.gameState,
                iconCache: widget.iconCache,
                cellSize: cellSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class IslandPainter extends CustomPainter {
  final Map<String, dynamic> gameState;
  final Map<String, ui.Image> iconCache;
  final double cellSize;

  IslandPainter({
    required this.gameState,
    required this.iconCache,
    required this.cellSize,
  });

  Color _parseHexColor(String hex) {
    try {
      String cleanHex = hex.toUpperCase().replaceAll('#', '');
      if (cleanHex.length == 6) {
        cleanHex = 'FF$cleanHex';
      }
      return Color(int.parse(cleanHex, radix: 16));
    } catch (e) {
      return Colors.black87;
    }
  }

  void _drawShape(Canvas canvas, Rect rect, String shape, String coin, String orientation, Paint paint, double cellSize) {
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    
    double angle = 0.0;
    if (orientation == "inversé") {
      angle = 180.0;
    } else if (orientation == "90°") {
      angle = 90.0;
    } else if (orientation == "180°") {
      angle = 180.0;
    } else if (orientation == "210°") {
      angle = 210.0;
    } else if (orientation == "270°") {
      angle = 270.0;
    }
    
    if (angle != 0.0) {
      canvas.rotate(angle * 3.141592653589793 / 180.0);
    }
    
    final Rect localRect = Rect.fromLTWH(
      -rect.width / 2,
      -rect.height / 2,
      rect.width,
      rect.height,
    );
    
    switch (shape) {
      case 'cercle':
        canvas.drawCircle(Offset.zero, rect.width / 2, paint);
        break;
      case 'triangle':
        final Path path = Path();
        path.moveTo(0, localRect.top);
        path.lineTo(localRect.right, localRect.bottom);
        path.lineTo(localRect.left, localRect.bottom);
        path.close();
        canvas.drawPath(path, paint);
        break;
      case 'rectangle':
        final Rect rRect = Rect.fromLTWH(
          -rect.width / 3,
          -rect.height / 2,
          (rect.width * 2) / 3,
          rect.height,
        );
        if (coin == "arrondi") {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rRect, Radius.circular(cellSize * 0.15)),
            paint,
          );
        } else {
          canvas.drawRect(rRect, paint);
        }
        break;
      case 'carré':
      default:
        if (coin == "arrondi") {
          canvas.drawRRect(
            RRect.fromRectAndRadius(localRect, Radius.circular(cellSize * 0.2)),
            paint,
          );
        } else {
          canvas.drawRect(localRect, paint);
        }
        break;
    }
    
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final int width = gameState['width'];
    final int height = gameState['height'];
    final List<dynamic> grille = gameState['grille'];
    final List<dynamic> composants = gameState['composants'];

    final Paint waterPaint = Paint()..color = const Color(0xFF0D47A1); // Bleu d'origine pour l'eau
    final Paint landPaint = Paint()..color = const Color(0xFF2E7D32); // Vert d'origine pour l'île

    // Dessin de l'île
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final Rect rect = Rect.fromLTWH(
          x * cellSize,
          y * cellSize,
          cellSize,
          cellSize,
        );
        canvas.drawRect(rect, grille[y][x] == 1 ? landPaint : waterPaint);
      }
    }

    // Dessin des voisins / grille de délimitation fine pour faciliter le dessin
    final Paint gridLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i <= width; i++) {
      canvas.drawLine(Offset(i * cellSize, 0), Offset(i * cellSize, height * cellSize), gridLinePaint);
    }
    for (int j = 0; j <= height; j++) {
      canvas.drawLine(Offset(0, j * cellSize), Offset(width * cellSize, j * cellSize), gridLinePaint);
    }

    // Dessin des composants vivants
    for (var comp in composants) {
      if (comp['vivant']) {
        final Rect rect = Rect.fromLTWH(
          comp['x'] * cellSize + 1,
          comp['y'] * cellSize + 1,
          cellSize - 2,
          cellSize - 2,
        );

        final String colorHex = (comp['couleur'] ?? '#000000').toString();
        final String shape = (comp['forme'] ?? 'carré').toString().toLowerCase();
        final String coin = (comp['coin'] ?? 'droit').toString().toLowerCase();
        final String orientation = (comp['orientation'] ?? 'standard').toString().toLowerCase();
        
        final Paint componentPaint = Paint()..color = _parseHexColor(colorHex);
        _drawShape(canvas, rect, shape, coin, orientation, componentPaint, cellSize);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
