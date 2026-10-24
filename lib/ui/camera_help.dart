import 'package:flutter/material.dart';
import 'guides.dart';

class CameraHelpSheet extends StatelessWidget {
  const CameraHelpSheet({super.key, required this.onPrivacy, this.onPractice});

  final VoidCallback onPrivacy;
  final VoidCallback? onPractice;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text('拍照指南', style: TextStyle(fontSize: 24)),
              ),
              TextButton.icon(
                onPressed: onPrivacy,
                style: TextButton.styleFrom(foregroundColor: muted),
                icon: const Icon(Icons.privacy_tip_outlined, size: 15),
                label: const Text('隐私与权限', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            key: const Key('help-content'),
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _step('01', '点选主体', '点一下想拍的人或物体，再点击「推荐构图」。'),
                const SizedBox(height: 20),
                _step('02', '选择构图', '选好构图，点击「开始调整构图」。'),
                const SizedBox(height: 20),
                _step('03', '调整并拍照', '按提示移动手机，出现「可以拍照了」后点击快门。'),
                const SizedBox(height: 24),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: paper.withValues(alpha: .035),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '拍摄提示',
                          style: TextStyle(fontSize: 12, color: paper),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '白框跟随主体，让绿圈中心留在框内一秒。\n'
                          '主体跟丢时，重新点一下主体。\n'
                          '右下角的角度接近 0°，画面更水平。',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.8,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.camera_alt_outlined,
                        size: 15,
                        color: muted,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '想保留当前画面？也可以点击「直接拍照」。',
                        style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          height: 1.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (onPractice != null)
          Container(
            key: const Key('help-footer'),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: paper.withValues(alpha: .08)),
              ),
            ),
            child: FilledButton(
              key: const Key('help-practice'),
              onPressed: onPractice,
              style: FilledButton.styleFrom(
                backgroundColor: acid,
                foregroundColor: ink,
                minimumSize: const Size.fromHeight(50),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.touch_app_outlined, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('试试练习模式', style: TextStyle(fontSize: 13)),
                  ),
                  Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _step(String number, String title, String description) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 36,
        child: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            number,
            style: const TextStyle(fontSize: 11, color: acid),
          ),
        ),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, color: paper)),
            const SizedBox(height: 5),
            Text(
              description,
              style: const TextStyle(fontSize: 12, height: 1.7, color: muted),
            ),
          ],
        ),
      ),
    ],
  );
}
