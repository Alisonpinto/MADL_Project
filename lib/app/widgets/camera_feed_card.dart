import 'package:flutter/material.dart';

class CameraFeedCard extends StatelessWidget {
  const CameraFeedCard({
    super.key,
    required this.label,
    required this.accent,
    this.showPlaceholder = true,
  });

  final String label;
  final Color accent;
  final bool showPlaceholder;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111827),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1F2937).withValues(alpha: 0.8),
                    const Color(0xFF111827).withValues(alpha: 0.8),
                    const Color(0xFF000000).withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(height: 2, color: accent),
          ),
          if (showPlaceholder)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam_outlined,
                    size: 68,
                    color: Color(0xFF6B7280),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
