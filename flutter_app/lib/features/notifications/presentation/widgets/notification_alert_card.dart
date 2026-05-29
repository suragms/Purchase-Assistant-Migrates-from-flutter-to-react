import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/notifications_provider.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/theme/theme_context_ext.dart';

/// Operational notification row with priority bar, icon, and optional actions.
class NotificationAlertCard extends StatelessWidget {
  const NotificationAlertCard({
    super.key,
    required this.item,
    required this.timeLabel,
    this.onTap,
    this.onApprove,
    this.onReject,
  });

  final NotificationItem item;
  final String timeLabel;
  final VoidCallback? onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  Color _priorityColor(BuildContext context) {
    switch (item.priority) {
      case 'critical':
        return HexaColors.loss;
      case 'high':
        return HexaColors.warning;
      case 'info':
        return Theme.of(context).colorScheme.onSurfaceVariant;
      default:
        return HexaColors.primaryMid;
    }
  }

  IconData _icon() {
    final kind = item.serverKind ?? '';
    if (kind == 'low_stock' || kind == 'stock_variance') {
      return Icons.inventory_2_outlined;
    }
    if (kind == 'stock_mismatch') {
      return Icons.warning_amber_rounded;
    }
    if (kind == 'supplier_delayed') {
      return Icons.hourglass_bottom_rounded;
    }
    if (kind == 'delivery_pending' || kind == 'delivery_received') {
      return Icons.local_shipping_outlined;
    }
    if (kind == 'export_failed') return Icons.picture_as_pdf_outlined;
    if (kind == 'approval_required') return Icons.rule_rounded;
    return switch (item.type) {
      NotificationType.purchaseDue || NotificationType.purchaseOverdue =>
        Icons.receipt_long_outlined,
      NotificationType.priceAlert => Icons.warning_amber_rounded,
      _ => Icons.notifications_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pri = _priorityColor(context);
    final needsApproval = item.serverKind == 'approval_required';
    final title = item.title.trim().isEmpty ? 'Warehouse alert' : item.title;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.adaptiveCard,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: item.isRead ? 2 : 4,
                    color: item.isRead ? cs.outlineVariant : pri,
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_icon(), size: 22, color: pri),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              if (item.subtitle.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  item.subtitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                    height: 1.3,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                timeLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              if (needsApproval &&
                                  (onApprove != null || onReject != null)) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    if (onApprove != null)
                                      TextButton(
                                        onPressed: onApprove,
                                        child: const Text('Approve'),
                                      ),
                                    if (onReject != null)
                                      TextButton(
                                        onPressed: onReject,
                                        child: const Text('Review'),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!item.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 4, left: 6),
                            decoration: BoxDecoration(
                              color: pri,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String relativeTime(DateTime created, DateFormat rel) {
    final now = DateTime.now();
    final diff = now.difference(created);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return rel.format(created);
  }
}
