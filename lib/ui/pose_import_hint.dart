import 'package:flutter/material.dart';
import 'guides.dart';

/// An anchored, nonmodal tip: it takes no layout space or preview gestures.
class PoseImportHint extends StatelessWidget {
  const PoseImportHint({
    super.key,
    required this.link,
    required this.onImport,
    required this.onDismiss,
  });
  final LayerLink link;
  final VoidCallback onImport, onDismiss;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: const Offset(0, -10),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 8),
              child: child,
            ),
          ),
          child: Semantics(
            liveRegion: true,
            child: SizedBox(
              key: const Key('pose-import-hint'),
              width: (MediaQuery.sizeOf(context).width - 44).clamp(0.0, 284.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Material(
                    color: acid,
                    borderRadius: BorderRadius.circular(12),
                    elevation: 10,
                    shadowColor: Colors.black.withValues(alpha: .5),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const Key('pose-import-hint-action'),
                      onTap: onImport,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '先选一张参考图',
                                    style: TextStyle(
                                      color: ink,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '点这里，选图后对照摆姿',
                                    style: TextStyle(
                                      color: Color(0xFF3B4529),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              key: const Key('dismiss-pose-import-hint'),
                              tooltip: '知道了',
                              onPressed: onDismiss,
                              icon: const Icon(
                                Icons.close,
                                color: ink,
                                size: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: CustomPaint(
                      size: const Size(16, 8),
                      painter: _TipArrowPainter(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _TipArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close(),
    Paint()..color = acid,
  );

  @override
  bool shouldRepaint(_TipArrowPainter oldDelegate) => false;
}
