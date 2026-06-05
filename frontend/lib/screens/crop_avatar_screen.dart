import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class CropAvatarScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String filename;

  const CropAvatarScreen({
    super.key,
    required this.imageBytes,
    required this.filename,
  });

  @override
  State<CropAvatarScreen> createState() => _CropAvatarScreenState();
}

class _CropAvatarScreenState extends State<CropAvatarScreen> {
  final GlobalKey _cropKey = GlobalKey();
  final TransformationController _transformationController = TransformationController();

  Future<Uint8List?> _cropImage() async {
    try {
      RenderRepaintBoundary? boundary =
          _cropKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint("Error cropping image: $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Adjust Profile Picture"),
        backgroundColor: const Color(0xFF2F3136),
        actions: [
          TextButton(
            onPressed: () async {
              final croppedBytes = await _cropImage();
              if (croppedBytes != null && mounted) {
                Navigator.pop(context, croppedBytes);
              }
            },
            child: const Text("SAVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // The cropping area
                  RepaintBoundary(
                    key: _cropKey,
                    child: Container(
                      width: 300,
                      height: 300,
                      color: Colors.grey[900],
                      child: InteractiveViewer(
                        transformationController: _transformationController,
                        boundaryMargin: const EdgeInsets.all(150),
                        minScale: 0.1,
                        maxScale: 5.0,
                        child: Image.memory(
                          widget.imageBytes,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  // The overlay mask (circular)
                  IgnorePointer(
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                      ),
                    ),
                  ),
                  // Darken areas outside the circle
                  IgnorePointer(
                    child: CustomPaint(
                      size: const Size(300, 300),
                      painter: _CropOverlayPainter(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              "Pinch to zoom and drag to move",
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    final outerPath = Path()..addRect(Rect.fromLTWH(-1000, -1000, 3000, 3000));
    final innerPath = Path()..addOval(Rect.fromLTWH(0, 0, size.width, size.height));

    final combinedPath = Path.combine(PathOperation.difference, outerPath, innerPath);
    canvas.drawPath(combinedPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
