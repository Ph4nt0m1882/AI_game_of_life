import 'package:flutter/material.dart';

class AvatarPreviewWidget extends StatelessWidget {
  final String shape;
  final String coin;
  final String orientation;
  final Color color;

  const AvatarPreviewWidget({
    super.key,
    required this.shape,
    required this.coin,
    required this.orientation,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.black45,
        border: Border.all(color: Colors.teal.shade800),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        painter: AvatarPreviewPainter(
          shape: shape,
          coin: coin,
          orientation: orientation,
          color: color,
        ),
      ),
    );
  }
}

class AvatarPreviewPainter extends CustomPainter {
  final String shape;
  final String coin;
  final String orientation;
  final Color color;

  AvatarPreviewPainter({
    required this.shape,
    required this.coin,
    required this.orientation,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final Rect rect = Rect.fromLTWH(10, 10, size.width - 20, size.height - 20);
    final double cellSize = size.width - 20;
    
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    
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
    
    final String sh = shape.toLowerCase();
    final String cn = coin.toLowerCase();
    
    switch (sh) {
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
        if (cn == "arrondi") {
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
        if (cn == "arrondi") {
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
