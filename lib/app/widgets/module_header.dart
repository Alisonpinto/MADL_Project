import 'package:flutter/material.dart';

import '../services/app_announcer.dart';

class ModuleHeader extends StatelessWidget {
  const ModuleHeader({
    super.key,
    required this.title,
    required this.accent,
    this.trailing,
  });

  final String title;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 14),
      decoration: BoxDecoration(color: accent),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'HandTalk',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: AppAnnouncer.instance.enabledListenable,
              builder: (context, enabled, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: enabled
                          ? 'Turn off voice announcements'
                          : 'Turn on voice announcements',
                      onPressed: () => AppAnnouncer.instance.toggleEnabled(),
                      icon: Icon(
                        enabled
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        color: Colors.white,
                      ),
                    ),
                    if (trailing case final Widget trailingWidget)
                      trailingWidget,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
