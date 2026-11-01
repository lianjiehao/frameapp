import 'dart:typed_data';
import 'package:flutter/material.dart';

class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('photo-viewer'),
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        InteractiveViewer(
          key: const Key('photo-viewer-zoom'),
          minScale: 1,
          maxScale: 4,
          child: SizedBox.expand(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              semanticLabel: '已拍摄照片',
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: IconButton.filledTonal(
                key: const Key('close-photo'),
                tooltip: '关闭照片',
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black.withValues(alpha: .65),
                ),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
