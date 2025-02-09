import 'package:flutter/material.dart';

class BannerNotification extends StatelessWidget {
  final String message;
  
  const BannerNotification({
    super.key,
    required this.message,
  });

  static final List<OverlayEntry> _activeNotifications = [];
  static const double _notificationHeight = 50.0;
  static const double _stackOffset = 4.0; // How much of the previous banner peeks out

  static void show(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    
    // Calculate offset based on number of active notifications
    final stackIndex = _activeNotifications.length;
    final topOffset = MediaQuery.of(context).padding.top;

    late final OverlayEntry entry;
    
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: topOffset,
        left: 0,
        right: 0,
        child: SafeArea(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(
                  0, 
                  -50 * (1 - value) + (stackIndex * _stackOffset * value),
                ),
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Stack(
              children: [
                // Shadow banner for stacked effect
                if (stackIndex > 0)
                  Positioned(
                    top: _stackOffset,
                    left: 16 + (_stackOffset * 0.5),
                    right: 16 + (_stackOffset * 0.5),
                    child: Opacity(
                      opacity: 0.6,
                      child: Container(
                        height: _notificationHeight,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                // Main banner
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    elevation: 0,
                    color: Colors.transparent,
                    child: Container(
                      height: _notificationHeight,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              message,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _removeNotification(entry),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    _activeNotifications.add(entry);
    overlay.insert(entry);

    Future.delayed(const Duration(milliseconds: 1500), () {
      _removeNotification(entry);
    });
  }

  static void _removeNotification(OverlayEntry entry) {
    if (!entry.mounted) return;
    
    entry.markNeedsBuild();
    
    Future.delayed(const Duration(milliseconds: 150), () {
      if (entry.mounted) {
        entry.remove();
        _activeNotifications.remove(entry);
        
        // Rebuild remaining notifications to update stack effect
        for (final notification in _activeNotifications) {
          if (notification.mounted) {
            notification.markNeedsBuild();
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(); // This won't be used directly
  }
} 