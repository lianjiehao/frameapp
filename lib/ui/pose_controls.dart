import 'package:flutter/material.dart';
import '../services/references.dart';
import 'guides.dart';

class PoseControls extends StatelessWidget {
  const PoseControls({
    super.key,
    required this.library,
    required this.importLink,
    required this.enabled,
    required this.canCapture,
    required this.capturing,
    required this.onImport,
    required this.filterButton,
    required this.onCapture,
    required this.onRestart,
    required this.onShowPhoto,
  });

  final ReferenceLibrary library;
  final LayerLink importLink;
  final bool enabled, canCapture, capturing;
  final Widget filterButton;
  final VoidCallback onImport, onCapture, onRestart;
  final VoidCallback? onShowPhoto;

  @override
  Widget build(BuildContext context) => library.selected == null
      ? _selectionControls()
      : Column(
          key: const Key('pose-controls'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              key: const Key('pose-reference-tools'),
              children: [
                CompositedTransformTarget(
                  link: importLink,
                  child: Tooltip(
                    message: '更换参考图',
                    child: OutlinedButton(
                      key: const Key('open-references'),
                      onPressed: enabled ? onImport : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: paper,
                        backgroundColor: paper.withValues(alpha: .035),
                        minimumSize: const Size(76, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        side: BorderSide(color: paper.withValues(alpha: .14)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                        overlayColor: Colors.transparent,
                        splashFactory: NoSplash.splashFactory,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: Image.memory(
                              library.selected!.bytes,
                              key: const Key('reference-thumbnail'),
                              width: 24,
                              height: 32,
                              fit: BoxFit.cover,
                              cacheWidth:
                                  (32 * MediaQuery.devicePixelRatioOf(context))
                                      .ceil(),
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.image_outlined, size: 24),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.swap_horiz, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    key: const Key('reference-adjustment-bar'),
                    height: 48,
                    padding: const EdgeInsets.only(left: 10, right: 2),
                    decoration: BoxDecoration(
                      color: paper.withValues(alpha: .035),
                      border: Border.all(color: paper.withValues(alpha: .14)),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: ReferenceAdjustmentBar(
                      library: library,
                      enabled: enabled,
                    ),
                  ),
                ),
              ],
            ),
            if (library.error != null)
              Text(
                library.error!,
                style: const TextStyle(color: acid, fontSize: 11),
              ),
            const SizedBox(height: 12),
            Row(
              key: const Key('pose-shooting-controls'),
              children: [
                Expanded(
                  child: Center(
                    child: TextButton(
                      key: const Key('pose-restart'),
                      onPressed: enabled ? onRestart : null,
                      style: TextButton.styleFrom(
                        foregroundColor: muted,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: const Text('重新开始', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
                Semantics(
                  key: const Key('pose-shutter-accessibility'),
                  button: true,
                  enabled: enabled && canCapture && !capturing,
                  label: capturing ? '正在拍照' : '拍照',
                  child: GestureDetector(
                    key: const Key('shutter'),
                    onTap: enabled && canCapture && !capturing
                        ? onCapture
                        : null,
                    child: Container(
                      width: 67,
                      height: 67,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: canCapture ? acid : muted,
                          width: 2,
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: canCapture ? acid : const Color(0xFF333B2D),
                        ),
                        child: Icon(
                          Icons.camera_alt_outlined,
                          color: canCapture ? ink : muted,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: IconButton(
                      key: const Key('open-photo'),
                      tooltip: '查看最近照片',
                      onPressed: enabled && !capturing ? onShowPhoto : null,
                      color: muted,
                      icon: const Icon(Icons.photo_outlined),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

  Widget _selectionControls() => Column(
    key: const Key('pose-select-controls'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '选择一张参考图',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          filterButton,
        ],
      ),
      Text(
        library.error ?? '选好参考图后，对照摆姿拍照。',
        style: TextStyle(
          color: library.error == null ? muted : acid,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 15),
      CompositedTransformTarget(
        link: importLink,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            key: const Key('open-references'),
            onPressed: enabled ? onImport : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              backgroundColor: acid,
              foregroundColor: ink,
              overlayColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    '选择参考图',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.north_east, size: 16),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

/// Reference-only adjustments available alongside the shutter.
class ReferenceAdjustmentBar extends StatelessWidget {
  const ReferenceAdjustmentBar({
    super.key,
    required this.library,
    required this.enabled,
  });
  final ReferenceLibrary library;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        '${(library.opacity * 100).round()}%',
        style: const TextStyle(color: muted, fontSize: 10),
      ),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            key: const Key('reference-opacity'),
            label: '透明度',
            value: library.opacity,
            onChanged: enabled ? library.setOpacity : null,
            semanticFormatterCallback: (value) =>
                '参考图透明度 ${(value * 100).round()}%',
          ),
        ),
      ),
      _tool(
        key: const Key('mirror-reference'),
        tooltip: '镜像参考图',
        icon: Icons.flip,
        active: library.mirror,
        onPressed: library.toggleMirror,
      ),
    ],
  );

  Widget _tool({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool active = false,
  }) => SizedBox(
    width: 44,
    height: 44,
    child: IconButton(
      key: key,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      onPressed: enabled ? onPressed : null,
      color: active ? acid : paper,
      icon: Icon(icon, size: 18),
    ),
  );
}
