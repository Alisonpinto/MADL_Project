import 'package:flutter/material.dart';

class ModuleBottomSheet extends StatefulWidget {
  const ModuleBottomSheet({
    super.key,
    required this.title,
    required this.accent,
    required this.child,
    this.hasData = false,
    this.onLevelChanged,
  });

  final String title;
  final Color accent;
  final Widget child;
  final bool hasData;
  final ValueChanged<int>? onLevelChanged;

  static const double collapsedHeight = 120;

  @override
  State<ModuleBottomSheet> createState() => _ModuleBottomSheetState();
}

class _ModuleBottomSheetState extends State<ModuleBottomSheet> {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  late bool _previousHasData = widget.hasData;
  bool _didFirstBuild = false;
  int? _reportedLevel;

  double _lastLevel1 = 0.18;
  double _lastLevel2 = 0.42;

  double _level1(double screenHeight) => (96 / screenHeight).clamp(0.11, 0.17);

  double _level2(double screenHeight, double level1) =>
      (330 / screenHeight).clamp(level1 + 0.08, 0.56);

  double _level3(double screenHeight, double level2) =>
      ((screenHeight - 110) / screenHeight).clamp(level2 + 0.10, 0.92);

  Future<void> _animateTo(double target) async {
    if (!_sheetController.isAttached) {
      return;
    }
    await _sheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  int _resolveLevel(
    double extent,
    double level1,
    double level2,
    double level3,
  ) {
    final l1ToL2 = (level1 + level2) / 2;
    final l2ToL3 = (level2 + level3) / 2;
    if (extent < l1ToL2) {
      return 1;
    }
    if (extent < l2ToL3) {
      return 2;
    }
    return 3;
  }

  void _notifyLevel(int level) {
    if (_reportedLevel == level) {
      return;
    }
    _reportedLevel = level;
    widget.onLevelChanged?.call(level);
  }

  @override
  void didUpdateWidget(covariant ModuleBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_previousHasData == widget.hasData) {
      return;
    }
    _previousHasData = widget.hasData;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _animateTo(widget.hasData ? _lastLevel2 : _lastLevel1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final level1 = _level1(screenHeight);
    final level2 = _level2(screenHeight, level1);
    final level3 = _level3(screenHeight, level2);

    _lastLevel1 = level1;
    _lastLevel2 = level2;
    final initialSize = level1;
    if (!_didFirstBuild) {
      _didFirstBuild = true;
      _previousHasData = widget.hasData;
    }

    final minSize = level1;
    final maxSize = level3;
    final snapSizes = <double>[level1, level2, level3];

    if (_reportedLevel == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _notifyLevel(1);
      });
    }

    return Positioned.fill(
      child: NotificationListener<DraggableScrollableNotification>(
        onNotification: (notification) {
          _notifyLevel(
            _resolveLevel(notification.extent, level1, level2, level3),
          );
          return false;
        },
        child: DraggableScrollableSheet(
          controller: _sheetController,
          expand: false,
          initialChildSize: initialSize,
          minChildSize: minSize,
          maxChildSize: maxSize,
          snap: true,
          snapSizes: snapSizes,
          snapAnimationDuration: const Duration(milliseconds: 260),
          builder: (context, scrollController) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                border: Border.all(
                  color: widget.accent.withValues(alpha: 0.25),
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 14,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
                children: [
                  Align(
                    child: Container(
                      width: 48,
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  widget.child,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
