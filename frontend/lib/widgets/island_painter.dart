import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class InteractiveIslandPainterWidget extends StatelessWidget {
  final Map<String, dynamic> gameState;
  final Function(int x, int y) onTapCell;
  final Map<String, ui.Image> iconCache;

  const InteractiveIslandPainterWidget({
    super.key,
    required this.gameState,
    required this.onTapCell,
    required this.iconCache,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) {
            final int width = gameState['width'] ?? 80;
            final int height = gameState['height'] ?? 80;

            final double cellWidth = constraints.maxWidth / width;
            final double cellHeight = constraints.maxHeight / height;
            final double cellSize = cellWidth < cellHeight ? cellWidth : cellHeight;

            final double offsetX = (constraints.maxWidth - (width * cellSize)) / 2;
            final double offsetY = (constraints.maxHeight - (height * cellSize)) / 2;

            final double localX = details.localPosition.dx - offsetX;
            final double localY = details.localPosition.dy - offsetY;

            if (localX >= 0 && localY >= 0) {
              final int cellX = (localX / cellSize).floor();
              final int cellY = (localY / cellSize).floor();

              if (cellX >= 0 && cellX < width && cellY >= 0 && cellY < height) {
                onTapCell(cellX, cellY);
              }
            }
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: IslandPainter(gameState: gameState, iconCache: iconCache),
          ),
        );
      },
    );
  }
}

class IslandPainter extends CustomPainter {
  final Map<String, dynamic> gameState;
  final Map<String, ui.Image> iconCache;

  IslandPainter({required this.gameState, required this.iconCache});

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

    final double cellWidth = size.width / width;
    final double cellHeight = size.height / height;
    final double cellSize = cellWidth < cellHeight ? cellWidth : cellHeight;
    
    final double offsetX = (size.width - (width * cellSize)) / 2;
    final double offsetY = (size.height - (height * cellSize)) / 2;

    final Paint waterPaint = Paint()..color = const Color(0xFF001F24);
    final Paint landPaint = Paint()..color = Colors.teal.shade700;

    // Dessin de l'île
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final Rect rect = Rect.fromLTWH(
          offsetX + x * cellSize,
          offsetY + y * cellSize,
          cellSize,
          cellSize,
        );
        canvas.drawRect(rect, grille[y][x] == 1 ? landPaint : waterPaint);
      }
    }

    // Dessin des composants vivants
    for (var comp in composants) {
      if (comp['vivant']) {
        final Rect rect = Rect.fromLTWH(
          offsetX + comp['x'] * cellSize + 1,
          offsetY + comp['y'] * cellSize + 1,
          cellSize - 2,
          cellSize - 2,
        );

        // Toujours afficher l'avatar visuel (forme, coin, orientation, couleur) sur la grille de simulation
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
