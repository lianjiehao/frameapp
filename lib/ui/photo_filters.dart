import 'package:flutter/material.dart';
import '../core/photo_filter.dart';
import '../services/coach.dart';
import 'guides.dart';

class PhotoFilterIcon extends StatelessWidget {
  const PhotoFilterIcon({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 15,
    child: CustomPaint(
      painter: _FilterIconPainter(IconTheme.of(context).color ?? paper),
    ),
  );
}

class _FilterIconPainter extends CustomPainter {
  const _FilterIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    for (final center in const [
      Offset(5, 5),
      Offset(10, 5),
      Offset(7.5, 9.5),
    ]) {
      canvas.drawCircle(center, 3.6, paint);
    }
  }

  @override
  bool shouldRepaint(_FilterIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

extension PhotoStyleLabel on PhotoStyle {
  String get label => switch (this) {
    PhotoStyle.original => '原图',
    PhotoStyle.warm => '暖光',
    PhotoStyle.clear => '清透',
    PhotoStyle.film => '胶片',
    PhotoStyle.monochrome => '黑白',
  };
}

extension PhotoAdjustmentLabel on PhotoAdjustment {
  String get label => switch (this) {
    PhotoAdjustment.brightness => '亮度',
    PhotoAdjustment.contrast => '对比度',
    PhotoAdjustment.saturation => '饱和度',
    PhotoAdjustment.warmth => '冷暖',
  };
}

class FilteredPhoto extends StatelessWidget {
  const FilteredPhoto({super.key, required this.filter, required this.child});
  final PhotoFilter filter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (filter.isOriginal) return child;
    return ClipRect(
      child: CustomPaint(
        foregroundPainter: _PhotoTexturePainter(filter),
        child: ColorFiltered(colorFilter: filter.colorFilter!, child: child),
      ),
    );
  }
}

class _PhotoTexturePainter extends CustomPainter {
  const _PhotoTexturePainter(this.filter);
  final PhotoFilter filter;

  @override
  void paint(Canvas canvas, Size size) =>
      paintPhotoTexture(canvas, size, filter);

  @override
  bool shouldRepaint(_PhotoTexturePainter oldDelegate) =>
      filter != oldDelegate.filter;
}

class PhotoFilterSheet extends StatefulWidget {
  const PhotoFilterSheet({super.key, required this.coach});
  final CameraCoach coach;

  @override
  State<PhotoFilterSheet> createState() => _PhotoFilterSheetState();
}

class _PhotoFilterSheetState extends State<PhotoFilterSheet> {
  PhotoAdjustment _adjustment = PhotoAdjustment.brightness;
  CameraCoach get coach => widget.coach;

  String _adjustmentValue(double value) {
    final amount = (value * 100).round();
    return amount > 0 ? '+$amount' : '$amount';
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: AnimatedBuilder(
        animation: coach,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('滤镜', style: TextStyle(fontSize: 22)),
                  ),
                  TextButton(
                    key: const Key('reset-photo-adjustments'),
                    onPressed:
                        coach.canChangePhotoFilter &&
                            coach.photoFilter.hasAdjustments
                        ? coach.resetPhotoAdjustments
                        : null,
                    child: const Text('重置调节', style: TextStyle(fontSize: 12)),
                  ),
                  IconButton(
                    tooltip: '完成',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final style in PhotoStyle.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: ValueKey('filter-${style.name}'),
                          label: Text(style.label),
                          selected: coach.photoFilter.style == style,
                          onSelected: coach.canChangePhotoFilter
                              ? (_) => coach.selectPhotoStyle(style)
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text('强度', style: TextStyle(color: muted)),
                  Expanded(
                    child: Slider(
                      key: const Key('filter-intensity'),
                      value: coach.photoFilter.intensity,
                      divisions: 100,
                      label: '${(coach.photoFilter.intensity * 100).round()}%',
                      onChanged:
                          coach.canChangePhotoFilter &&
                              coach.photoFilter.style != PhotoStyle.original
                          ? coach.setPhotoFilterIntensity
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      coach.photoFilter.style == PhotoStyle.original
                          ? '—'
                          : '${(coach.photoFilter.intensity * 100).round()}%',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final adjustment in PhotoAdjustment.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: ValueKey('adjustment-${adjustment.name}'),
                          label: Text(adjustment.label),
                          selected: _adjustment == adjustment,
                          onSelected: coach.canChangePhotoFilter
                              ? (_) => setState(() => _adjustment = adjustment)
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Text('调节', style: TextStyle(color: muted)),
                  Expanded(
                    child: Slider(
                      key: const Key('photo-adjustment'),
                      value: coach.photoFilter.adjustment(_adjustment),
                      min: -1,
                      max: 1,
                      divisions: 200,
                      label: _adjustmentValue(
                        coach.photoFilter.adjustment(_adjustment),
                      ),
                      semanticFormatterCallback: (value) =>
                          '${_adjustment.label} ${_adjustmentValue(value)}',
                      onChanged: coach.canChangePhotoFilter
                          ? (value) =>
                                coach.setPhotoAdjustment(_adjustment, value)
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      _adjustmentValue(
                        coach.photoFilter.adjustment(_adjustment),
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '取景时预览效果，拍下后保留到照片中。',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
