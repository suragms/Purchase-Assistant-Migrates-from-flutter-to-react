import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/notifications_provider.dart';
import '../../../../core/theme/hexa_colors.dart';

/// Compact operational header: warehouse identity, sync, alerts, settings.
class HomeCompactHeader extends ConsumerWidget {
  const HomeCompactHeader({
    super.key,
    required this.offline,
    this.onSettingsLongPress,
  });

  final bool offline;
  final VoidCallback? onSettingsLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final bellCount = ref.watch(notificationsUnreadCountProvider);
    final title = _shortWarehouseName(
      session?.primaryBusiness.effectiveDisplayTitle ?? 'Warehouse',
    );
    final code = _warehouseCode(session?.primaryBusiness.id);
    final initial = title.trim().isNotEmpty ? title.trim()[0].toUpperCase() : 'H';
    final role = (session?.primaryBusiness.role ?? 'owner').toUpperCase();
    final syncColor = offline ? const Color(0xFFC62828) : const Color(0xFF2E7D32);
    final syncLabel = offline ? 'Offline' : 'Synced';

    return SizedBox(
      height: 56,
      child: Row(
        children: [
          GestureDetector(
            onLongPress: onSettingsLongPress,
            child: CircleAvatar(
              radius: 20,
              backgroundColor: HexaColors.brandPrimary.withValues(alpha: 0.12),
              child: Text(
                initial,
                style: HexaDsType.heading(16, color: HexaColors.brandPrimary),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HexaDsType.heading(15, color: HexaDsColors.textPrimary),
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HexaDsType.labelCaps(context).copyWith(
                          fontSize: 10,
                          color: HexaDsColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: HexaColors.brandPrimary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        role,
                        style: HexaDsType.labelCaps(context).copyWith(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: HexaColors.brandPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: syncColor,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                syncLabel,
                style: HexaDsType.labelCaps(context).copyWith(
                  fontSize: 10,
                  color: syncColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
            icon: Badge(
              isLabelVisible: bellCount > 0,
              label: Text(
                bellCount > 99 ? '99+' : '$bellCount',
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
              ),
              child: const Icon(Icons.notifications_outlined, size: 22),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined, size: 22),
          ),
        ],
      ),
    );
  }

  static String _warehouseCode(String? businessId) {
    if (businessId == null || businessId.isEmpty) return 'WH';
    final clean = businessId.replaceAll('-', '');
    if (clean.length >= 4) return 'WH-${clean.substring(0, 4).toUpperCase()}';
    return 'WH-${clean.toUpperCase()}';
  }

  static String _shortWarehouseName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'\b(Purchase|Purchases|Assistant|Agency)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return raw;
    if (cleaned.length <= 18) return cleaned;
    return cleaned.substring(0, 18).trim();
  }
}
