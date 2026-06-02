import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class InteractiveIslandPainterWidget extends StatefulWidget {
  final Map<String, dynamic> gameState;
  final Function(int x, int y) onTapCell;
  final Function(int x, int y)? onPaintCell;
  final Map<String, ui.Image> iconCache;
  final String activeTool;
  final ui.Image? bubbleImage;

  const InteractiveIslandPainterWidget({
    super.key,
    required this.gameState,
    required this.onTapCell,
    this.onPaintCell,
    required this.iconCache,
    required this.activeTool,
    this.bubbleImage,
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
                bubbleImage: widget.bubbleImage,
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
  final ui.Image? bubbleImage;

  IslandPainter({
    required this.gameState,
    required this.iconCache,
    required this.cellSize,
    this.bubbleImage,
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

    // Dessin des zones d'intimité (Lueur d'arrière-plan verte/rouge)
    final List<dynamic> aliveComps = composants.where((c) => c['vivant'] == true).toList();
    final List<List<dynamic>> clusters = _findClusters(aliveComps);
    for (var cluster in clusters) {
      if (_isIntimacyZone(cluster, aliveComps)) {
        final bool isNegative = _isNegativeGroup(cluster);
        final Color glowColor = isNegative ? Colors.redAccent : Colors.greenAccent;
        
        final Paint glowPaint = Paint()
          ..color = glowColor.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15.0)
          ..style = PaintingStyle.fill;

        final Path glowPath = Path();
        for (var member in cluster) {
          final double cx = (member['x'] ?? 0) * cellSize + cellSize / 2;
          final double cy = (member['y'] ?? 0) * cellSize + cellSize / 2;
          glowPath.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: 3.5 * cellSize));
        }

        canvas.save();
        canvas.drawPath(glowPath, glowPaint);
        canvas.restore();
      }
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

    // Dessin des bulles de dialogue si l'image des bulles est chargée
    if (bubbleImage != null && gameState['dialogues'] != null) {
      final List<dynamic> dialogues = gameState['dialogues'];
      final int currentTick = gameState['tick'] ?? 0;

      for (var dialogue in dialogues) {
        final int dialogueTick = dialogue['tick'] ?? 0;
        final int ageTicks = currentTick - dialogueTick;

        // Afficher si la bulle est dans sa fenêtre de durée (75 ticks)
        if (ageTicks >= 0 && ageTicks < 75) {
          final int x = dialogue['x'] ?? 0;
          final int y = dialogue['y'] ?? 0;
          final String phrase = dialogue['phrase'] ?? '';
          
          if (phrase.isEmpty) continue;

          // Calculer l'opacité (1.0 pendant 50 ticks, puis fondu linéaire sur les 25 suivants)
          double opacity = 1.0;
          if (ageTicks > 50) {
            opacity = 1.0 - (ageTicks - 50) / 25.0;
            if (opacity < 0.0) opacity = 0.0;
            if (opacity > 1.0) opacity = 1.0;
          }

          // Coordonnées du locuteur sur le canevas
          final double centerX = x * cellSize + cellSize / 2;
          final double targetY = y * cellSize; // Haut de la case

          // Peindre le texte avec la police Minecraft et l'opacité calculée
          final TextPainter textPainter = TextPainter(
            text: TextSpan(
              text: phrase,
              style: TextStyle(
                fontFamily: 'Minecraft',
                fontSize: 9.0,
                color: Colors.black.withValues(alpha: opacity),
                fontWeight: FontWeight.normal,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: 120.0);

          const double tailH = 16.0;
          const double cornerW = 32.0;
          const double cornerH = 24.0;

          // Dimensions de la bulle adaptées au texte
          final double dstW = (textPainter.width + 24.0).clamp(2 * cornerW, 200.0);
          final double dstH = (textPainter.height + 16.0).clamp(2 * cornerH, 150.0);

          // Positionner la bulle en haut à gauche du composant (le coin bas-droite de la bulle s'aligne sur le haut-milieu de l'entité)
          final double dstX = centerX - dstW;
          final double dstY = targetY - dstH;

          final Paint bubblePaint = Paint()
            ..color = Colors.white.withValues(alpha: opacity)
            ..filterQuality = FilterQuality.medium;

          const double o = 1.5; // overlap offset to prevent sub-pixel seams

          // Découper et dessiner en 9-split (Style 1 de la bulle)
          final Rect srcTL = const Rect.fromLTWH(251, 91, 246, 134);
          final Rect srcTM = const Rect.fromLTWH(564, 97, 243, 128);
          final Rect srcTR = const Rect.fromLTWH(873, 92, 241, 133);
          final Rect srcML = const Rect.fromLTWH(255, 265, 242, 167);
          final Rect srcMM = const Rect.fromLTWH(564, 265, 243, 167);
          final Rect srcMR = const Rect.fromLTWH(873, 265, 241, 167);
          final Rect srcBL = const Rect.fromLTWH(260, 470, 237, 134);
          final Rect srcBM = const Rect.fromLTWH(564, 470, 243, 131);
          final Rect srcBR = const Rect.fromLTWH(873, 470, 252, 266); // Inclut la pointe/queue de la bulle

          // TL
          canvas.drawImageRect(bubbleImage!, srcTL, Rect.fromLTWH(dstX, dstY, cornerW + o, cornerH + o), bubblePaint);
          // TR
          canvas.drawImageRect(bubbleImage!, srcTR, Rect.fromLTWH(dstX + dstW - cornerW - o, dstY, cornerW + o, cornerH + o), bubblePaint);
          // BL
          canvas.drawImageRect(bubbleImage!, srcBL, Rect.fromLTWH(dstX, dstY + dstH - cornerH - o, cornerW + o, cornerH + o), bubblePaint);
          // BR (dessiné plus grand verticalement pour y inclure la pointe)
          canvas.drawImageRect(bubbleImage!, srcBR, Rect.fromLTWH(dstX + dstW - cornerW - o, dstY + dstH - cornerH - o, cornerW + o, cornerH + tailH + o), bubblePaint);
          // TM
          canvas.drawImageRect(bubbleImage!, srcTM, Rect.fromLTWH(dstX + cornerW - o, dstY, dstW - 2 * cornerW + 2 * o, cornerH + o), bubblePaint);
          // BM
          canvas.drawImageRect(bubbleImage!, srcBM, Rect.fromLTWH(dstX + cornerW - o, dstY + dstH - cornerH - o, dstW - 2 * cornerW + 2 * o, cornerH + o), bubblePaint);
          // ML
          canvas.drawImageRect(bubbleImage!, srcML, Rect.fromLTWH(dstX, dstY + cornerH - o, cornerW + o, dstH - 2 * cornerH + 2 * o), bubblePaint);
          // MR
          canvas.drawImageRect(bubbleImage!, srcMR, Rect.fromLTWH(dstX + dstW - cornerW - o, dstY + cornerH - o, cornerW + o, dstH - 2 * cornerH + 2 * o), bubblePaint);
          // MM
          canvas.drawImageRect(bubbleImage!, srcMM, Rect.fromLTWH(dstX + cornerW - o, dstY + cornerH - o, dstW - 2 * cornerW + 2 * o, dstH - 2 * cornerH + 2 * o), bubblePaint);

          // Dessiner le texte centré dans la bulle
          final double textX = dstX + (dstW - textPainter.width) / 2;
          final double textY = dstY + (dstH - textPainter.height) / 2;
          textPainter.paint(canvas, Offset(textX, textY));
        }
      }
    }
  }

  List<List<dynamic>> _findClusters(List<dynamic> components) {
    final List<List<dynamic>> clusters = [];
    final Set<String> visited = {};

    for (var comp in components) {
      final String id = comp['id'];
      if (visited.contains(id)) continue;

      // Commencer un nouveau cluster
      final List<dynamic> cluster = [];
      final List<dynamic> queue = [comp];
      visited.add(id);

      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        cluster.add(current);

        final int cx = (current['x'] ?? 0) as int;
        final int cy = (current['y'] ?? 0) as int;

        for (var other in components) {
          final String otherId = other['id'];
          if (visited.contains(otherId)) continue;

          final int ox = (other['x'] ?? 0) as int;
          final int oy = (other['y'] ?? 0) as int;

          // Adjacence de Chebyshev (distance <= 1)
          if ((ox - cx).abs() <= 1 && (oy - cy).abs() <= 1) {
            visited.add(otherId);
            queue.add(other);
          }
        }
      }

      if (cluster.length >= 2) {
        clusters.add(cluster);
      }
    }
    return clusters;
  }

  bool _isIntimacyZone(List<dynamic> cluster, List<dynamic> allAliveComponents) {
    final Set<String> clusterIds = cluster.map((c) => c['id'] as String).toSet();

    for (var member in cluster) {
      final int mx = (member['x'] ?? 0) as int;
      final int my = (member['y'] ?? 0) as int;

      for (var other in allAliveComponents) {
        final String otherId = other['id'] as String;
        if (clusterIds.contains(otherId)) continue;

        final int ox = (other['x'] ?? 0) as int;
        final int oy = (other['y'] ?? 0) as int;

        // Rayon de 3 cases (distance de Chebyshev <= 3)
        if ((ox - mx).abs() <= 3 && (oy - my).abs() <= 3) {
          return false; // Intrus détecté
        }
      }
    }
    return true;
  }

  bool _isNegativeGroup(List<dynamic> cluster) {
    // 1. Vérifier si un membre X est détesté par TOUS les autres membres Y (relation Y -> X < 50)
    for (var X in cluster) {
      final String xId = X['id'];
      bool hatedByAll = true;
      for (var Y in cluster) {
        if (Y['id'] == xId) continue;
        final Map<String, dynamic> relations = Y['relations'] ?? {};
        final int score = relations[xId] ?? 50;
        if (score >= 50) {
          hatedByAll = false;
          break;
        }
      }
      if (hatedByAll) return true;
    }

    // 2. Vérifier si la moyenne des relations est négative (< 50)
    double totalScore = 0;
    int count = 0;
    for (var A in cluster) {
      final Map<String, dynamic> relations = A['relations'] ?? {};
      for (var B in cluster) {
        if (A['id'] == B['id']) continue;
        final int score = relations[B['id']] ?? 50;
        totalScore += score;
        count++;
      }
    }
    if (count > 0 && (totalScore / count) < 50) {
      return true;
    }

    return false;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
