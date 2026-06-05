import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/router/shell_navigation.dart';
import '../../shell/shell_branch_provider.dart';

class HelpGuidePage extends StatelessWidget {
  const HelpGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('How to use this app'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/settings'),
        ),
      ),
      body: HexaResponsiveCenter(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(
              'Harisree warehouse guide',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Plain steps for owners and staff. Tap Try it to open each feature.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 16),
            const _GuideSection(
              role: 'Owner',
              icon: Icons.home_rounded,
              titleEn: 'Home dashboard',
              titleAr: 'لوحة الرئيسية',
              bodyEn:
                  'See today\'s purchases, low stock alerts, pending deliveries, and recent activity.',
              bodyAr: 'شاهد مشتريات اليوم وتنبيهات المخزون والتسليمات والنشاط الأخير.',
              actionLabel: 'Go to Home',
              route: '/home',
              shellBranch: ShellBranch.home,
            ),
            const _GuideSection(
              role: 'Owner',
              icon: Icons.add_shopping_cart_outlined,
              titleEn: 'Add a purchase',
              titleAr: 'إضافة شراء',
              bodyEn:
                  'Tap + → Add purchase. Choose supplier, add items, qty and price, then preview and save.',
              bodyAr: 'اضغط + ثم أضف شراء. اختر المورد والأصناف والكمية والسعر ثم احفظ.',
              actionLabel: 'New purchase',
              route: '/purchase/new',
            ),
            const _GuideSection(
              role: 'All',
              icon: Icons.qr_code_scanner_rounded,
              titleEn: 'Scan barcode',
              titleAr: 'مسح الباركود',
              bodyEn:
                  'Tap + → Scan barcode or use the quick action. Hold steady over the label. '
                  'On Safari, upload a photo if live camera is unavailable.',
              bodyAr: 'امسح الباركود من القائمة السريعة. ثبّت الكاميرا على الملصق.',
              actionLabel: 'Open scanner',
              route: '/barcode/scan',
            ),
            const _GuideSection(
              role: 'All',
              icon: Icons.inventory_2_outlined,
              titleEn: 'Stock update',
              titleAr: 'تحديث المخزون',
              bodyEn:
                  'Stock tab → tap a row → update physical count or system stock. '
                  'Changes save immediately on the list.',
              bodyAr: 'تبويب المخزون → اختر صنفًا → حدّث العدد الفعلي أو مخزون النظام.',
              actionLabel: 'Go to Stock',
              route: '/stock',
              shellBranch: ShellBranch.stock,
            ),
            const _GuideSection(
              role: 'Owner',
              icon: Icons.qr_code_2_outlined,
              titleEn: 'Print barcode labels',
              titleAr: 'طباعة ملصقات',
              bodyEn:
                  'Tap + → Print labels. Select items, then download or share the PDF.',
              bodyAr: 'اختر الأصناف ثم حمّل أو اطبع ملف PDF للملصقات.',
              actionLabel: 'Print labels',
              route: '/barcode/bulk-print',
            ),
            const _GuideSection(
              role: 'Owner',
              icon: Icons.backup_outlined,
              titleEn: 'Backup and export',
              titleAr: 'النسخ الاحتياطي',
              bodyEn:
                  'Settings → Export & Backup. Download stock Excel, monthly purchases PDF, or ZIP backup.',
              bodyAr: 'الإعدادات → تصدير ونسخ احتياطي. Excel و PDF و ZIP.',
              actionLabel: 'Export & Backup',
              route: '/settings/backup',
            ),
            const _GuideSection(
              role: 'Owner',
              icon: Icons.share_outlined,
              titleEn: 'Share purchase on WhatsApp',
              titleAr: 'مشاركة الشراء',
              bodyEn:
                  'Open a purchase → Share. Set Accounts WhatsApp in Settings → Business profile first.',
              bodyAr: 'افتح الشراء ثم شارك. أضف رقم واتساب الحسابات في الإعدادات أولاً.',
              actionLabel: 'Settings',
              route: '/settings',
            ),
            const _GuideSection(
              role: 'Owner',
              icon: Icons.people_outline,
              titleEn: 'Add staff user',
              titleAr: 'إضافة موظف',
              bodyEn:
                  'Settings → Users → add name, phone, and role. Staff can scan, receive deliveries, and count stock.',
              bodyAr: 'الإعدادات → المستخدمون → أضف الموظف والدور.',
              actionLabel: 'Users',
              route: '/settings/users',
            ),
            const _GuideSection(
              role: 'Staff',
              icon: Icons.local_shipping_outlined,
              titleEn: 'Receive delivery',
              titleAr: 'استلام الشحنة',
              bodyEn:
                  'Staff home → pending delivery → Arrive & verify. Truck and damage fields are optional.',
              bodyAr: 'الصفحة الرئيسية للموظف → استلام → تأكيد الكميات.',
              actionLabel: 'Staff home',
              route: '/staff/home',
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.role,
    required this.icon,
    required this.titleEn,
    required this.titleAr,
    required this.bodyEn,
    required this.bodyAr,
    required this.actionLabel,
    required this.route,
    this.shellBranch,
  });

  final String role;
  final IconData icon;
  final String titleEn;
  final String titleAr;
  final String bodyEn;
  final String bodyAr;
  final String actionLabel;
  final String route;
  final int? shellBranch;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(icon, color: cs.primary),
        title: Text(titleEn, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '$role · $titleAr',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(bodyEn, style: const TextStyle(height: 1.4)),
                const SizedBox(height: 6),
                Text(
                  bodyAr,
                  style: TextStyle(
                    height: 1.4,
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      if (shellBranch != null) {
                        goShellTabFromContext(
                          context,
                          branch: shellBranch!,
                          location: route,
                        );
                        return;
                      }
                      context.push(route);
                    },
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text('Try it → $actionLabel'),
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
