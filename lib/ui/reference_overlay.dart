import 'package:flutter/material.dart';
import '../services/references.dart';

/// Viewfinder-only artwork. Photo rendering never reads this layer.
class ReferenceOverlay extends StatelessWidget {
  const ReferenceOverlay({super.key, required this.library});
  final ReferenceLibrary library;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final asset = library.selected;
      if (asset == null) return const SizedBox.shrink();
      return IgnorePointer(
        child: ClipRect(
          child: Opacity(
            opacity: library.visible ? library.opacity : 0,
            child: Transform.flip(
              flipX: library.mirror,
              child: SizedBox.expand(
                child: Image.memory(
                  asset.bytes,
                  key: ValueKey(asset.id),
                  fit: BoxFit.fitHeight,
                  alignment: Alignment.center,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
