import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/session.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/prefs_provider.dart'
    show localNotificationsOptInProvider, notificationKindTogglesProvider;
import '../../../core/router/navigation_ext.dart';
import '../../../core/router/post_auth_route.dart'
    show sessionCanAdminUsers, sessionIsStaff;
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../widgets/accounts_whatsapp_settings_card.dart';
import '../widgets/backup_monthly_banner.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  int _superAdminGestureCount = 0;
  DateTime? _superAdminGestureAnchor;

  void _handleVersionLongPress(Session? session) {
    if (session?.isSuperAdmin != true) return;
    final now = DateTime.now();
    final anchor = _superAdminGestureAnchor;
    if (anchor == null || now.difference(anchor) > const Duration(seconds: 4)) {
      _superAdminGestureCount = 0;
    }
    _superAdminGestureAnchor = now;
    setState(() => _superAdminGestureCount++);
    if (_superAdminGestureCount >= 3) {
      _superAdminGestureCount = 0;
      _superAdminGestureAnchor = null;
      context.push('/admin');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final pb = session?.primaryBusiness;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final role = pb?.role.toLowerCase();
    final isStaff = session != null && sessionIsStaff(session);
    final isManager = role == 'manager';
    final isOwner = role == 'owner' || session?.isSuperAdmin == true;
    final canManageUsers = session != null && sessionCanAdminUsers(session);
    final notifOptIn = ref.watch(localNotificationsOptInProvider);
    final notifKinds = ref.watch(notificationKindTogglesProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;

    final settingsList = ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      shrinkWrap: true,
      children: [
          if (isOwner) const BackupMonthlyBanner(),
          _SectionTitle('Account'),
          _SettingsCard(
            children: [
              ListTile(
                leading: Icon(Icons.person_outline_rounded, color: cs.primary),
                title: const Text('Session'),
                subtitle: Text(
                  session != null
                      ? 'Signed in · ${pb?.name ?? ''}'
                      : 'Not signed in',
                ),
              ),
            ],
          ),
          if (!isStaff) ...[
            _SectionTitle('Quick Actions'),
            _SettingsCard(
              children: [
                _NavTile(
                  icon: Icons.document_scanner_outlined,
                  title: 'Scan purchase bill',
                  onTap: () => context.pushNamed('purchase_scan'),
                ),
                _NavTile(
                  icon: Icons.add_shopping_cart_outlined,
                  title: 'New purchase',
                  onTap: () => context.go('/purchase/new'),
                ),
                _NavTile(
                  icon: Icons.history_rounded,
                  title: 'Purchase history',
                  onTap: () => context.go('/purchase'),
                ),
              ],
            ),
          ],
          _SectionTitle('Notifications'),
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: Icon(Icons.notifications_active_outlined,
                    color: cs.primary),
                title: const Text('Local notifications'),
                subtitle: const Text(
                    'Warehouse reminders and follow-ups on this device'),
                value: notifOptIn,
                onChanged: (v) => unawaited(_setNotificationsOptIn(v)),
              ),
              if (notifOptIn) ...[
                SwitchListTile(
                  title: const Text('Low stock alerts'),
                  value: notifKinds.contains('low_stock'),
                  onChanged: (v) => ref
                      .read(notificationKindTogglesProvider.notifier)
                      .setEnabled('low_stock', v),
                ),
                SwitchListTile(
                  title: const Text('Delivery updates'),
                  value: notifKinds.contains('delivery'),
                  onChanged: (v) => ref
                      .read(notificationKindTogglesProvider.notifier)
                      .setEnabled('delivery', v),
                ),
                SwitchListTile(
                  title: const Text('Stock variance'),
                  value: notifKinds.contains('stock_variance'),
                  onChanged: (v) => ref
                      .read(notificationKindTogglesProvider.notifier)
                      .setEnabled('stock_variance', v),
                ),
                SwitchListTile(
                  title: const Text('Staff requests & reorder'),
                  value: notifKinds.contains('staff_alert'),
                  onChanged: (v) => ref
                      .read(notificationKindTogglesProvider.notifier)
                      .setEnabled('staff_alert', v),
                ),
                SwitchListTile(
                  title: const Text('Opening stock reminders'),
                  value: notifKinds.contains('opening_stock'),
                  onChanged: (v) => ref
                      .read(notificationKindTogglesProvider.notifier)
                      .setEnabled('opening_stock', v),
                ),
                SwitchListTile(
                  title: const Text('Evening physical count'),
                  value: notifKinds.contains('physical_reminder'),
                  onChanged: (v) => ref
                      .read(notificationKindTogglesProvider.notifier)
                      .setEnabled('physical_reminder', v),
                ),
              ],
            ],
          ),
          _SectionTitle('Business'),
          if (isOwner) const AccountsWhatsappSettingsCard(),
          if (isOwner) const SizedBox(height: 12),
          _BusinessCard(
            session: session,
            canManageUsers: canManageUsers,
            businessProfileReadOnly: isManager,
          ),
          _SectionTitle('Operations'),
          _SettingsCard(
            children: [
              _NavTile(
                icon: Icons.playlist_add_check_rounded,
                title: 'Reorder list',
                subtitle: 'Items flagged for reorder',
                onTap: () => pushStockReorder(context),
              ),
              if (isOwner)
                _NavTile(
                  icon: Icons.inventory_rounded,
                  title: 'Opening stock setup',
                  subtitle: 'Set initial stock and lock setup values',
                  onTap: () => pushOpeningStockSetup(context),
                ),
              if (isOwner)
                _NavTile(
                  icon: Icons.receipt_long_rounded,
                  title: 'Staff cash purchases',
                  subtitle: 'Quick buys logged by floor staff',
                  onTap: () => pushOverlayRoute(context, '/stock/staff-purchases'),
                ),
              _NavTile(
                icon: Icons.print_outlined,
                title: 'Print barcodes (bulk)',
                onTap: () => pushOverlayRoute(context, '/barcode/bulk-print'),
              ),
              _NavTile(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Scan item',
                onTap: () => pushBarcodeScan(context),
              ),
            ],
          ),
          if (!isStaff) ...[
            _SectionTitle('Export & Backup'),
            _SettingsCard(
              children: [
                _NavTile(
                  icon: Icons.cloud_download_outlined,
                  title: 'Export & Backup',
                  subtitle:
                      'Stock Excel, purchases PDF (this month), ZIP trade data',
                  onTap: () => context.push('/settings/backup'),
                ),
              ],
            ),
          ],
          _SectionTitle('Data'),
          _SettingsCard(
            children: [
              _NavTile(
                icon: Icons.help_outline_rounded,
                title: 'Help & guide',
                subtitle: 'Daily stock, offline mode, backup steps',
                onTap: () => context.push('/settings/help'),
              ),
              _NavTile(
                icon: Icons.groups_outlined,
                title: 'Suppliers & brokers',
                subtitle: 'Contacts hub, categories, items, people',
                onTap: () => context.go('/contacts'),
              ),
              _NavTile(
                icon: Icons.category_outlined,
                title: 'Categories & subcategories',
                subtitle: 'Quick add Rice, Oil, and sub-types for items',
                onTap: () => context.push('/catalog/taxonomy'),
              ),
              if (!isStaff)
                _NavTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Item catalog',
                  subtitle: 'Full category tree and item editor',
                  onTap: () => context.push('/catalog'),
                ),
              _NavTile(
                icon: Icons.tune_rounded,
                title: 'Set reorder levels',
                subtitle: 'Thresholds for low-stock alerts',
                onTap: () => context.push('/catalog/setup-reorder-levels'),
              ),
              _NavTile(
                icon: Icons.qr_code_2_outlined,
                title: 'Missing item codes',
                subtitle: 'Assign codes and print barcodes',
                onTap: () => context.push('/catalog/missing-codes'),
              ),
              if (!isOwner)
                _NavTile(
                  icon: Icons.folder_zip_outlined,
                  title: 'Backup',
                  subtitle: 'Download purchase records for your files',
                  onTap: () => context.push('/settings/backup'),
                ),
              if (isOwner)
                _NavTile(
                  icon: Icons.checklist_rtl_outlined,
                  title: 'Owner tasks',
                  subtitle: 'Checklist progress and staff completion',
                  onTap: () => context.push('/operations/owner-tasks'),
                ),
            ],
          ),
          if (session?.isSuperAdmin == true) ...[
            _SectionTitle('Admin'),
            _SettingsCard(
              children: [
                _NavTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Super admin',
                  onTap: () => context.push('/admin'),
                ),
              ],
            ),
          ],
          _SectionTitle('Troubleshooting'),
          _SettingsCard(
            children: [
              ListTile(
                leading: Icon(Icons.sync_rounded, color: cs.primary),
                title: const Text('Refresh all stats'),
                subtitle: const Text(
                  'Reloads home, reports, contacts KPIs, and purchases from the server.',
                ),
                onTap: () {
                  invalidateBusinessAggregates(ref);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Refreshing numbers...')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: GestureDetector(
              onLongPress: () => _handleVersionLongPress(session),
              child: Text(
                'Version ${AppConfig.packageVersion}',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () async {
              await ref.read(sessionProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
    );

    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Settings',
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/home'),
        ),
      ),
      body: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsSidebar(
                  isOwner: isOwner,
                  canManageUsers: canManageUsers,
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: HexaResponsiveCenter(
                    maxWidth: 720,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    child: settingsList,
                  ),
                ),
              ],
            )
          : HexaResponsiveCenter(
              maxWidth: 720,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: settingsList,
            ),
    );
  }

  Future<void> _setNotificationsOptIn(bool enabled) async {
    await ref.read(localNotificationsOptInProvider.notifier).setValue(enabled);
    await LocalNotificationsService.instance.setOptIn(enabled);
  }
}

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.isOwner,
    required this.canManageUsers,
  });

  final bool isOwner;
  final bool canManageUsers;

  @override
  Widget build(BuildContext context) {
    final route = GoRouterState.of(context).uri.path;
    return SizedBox(
      width: 220,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
        children: [
          _SidebarTile(
            icon: Icons.business_rounded,
            label: 'Business profile',
            route: '/settings/business',
            currentRoute: route,
          ),
          if (canManageUsers)
            _SidebarTile(
              icon: Icons.people_outline_rounded,
              label: 'Users',
              route: '/settings/users',
              currentRoute: route,
            ),
          if (isOwner)
            _SidebarTile(
              icon: Icons.cloud_download_outlined,
              label: 'Backup & export',
              route: '/settings/backup',
              currentRoute: route,
            ),
          _SidebarTile(
            icon: Icons.help_outline_rounded,
            label: 'Help guide',
            route: '/settings/help',
            currentRoute: route,
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.route,
    required this.currentRoute,
  });

  final IconData icon;
  final String label;
  final String route;
  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    final selected = currentRoute == route || currentRoute.startsWith('$route/');
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: () => context.push(route),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({
    required this.session,
    required this.canManageUsers,
    this.businessProfileReadOnly = false,
  });

  final Session? session;
  final bool canManageUsers;
  final bool businessProfileReadOnly;

  @override
  Widget build(BuildContext context) {
    final pb = session?.primaryBusiness;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return _SettingsCard(
      children: [
        ListTile(
          leading: Icon(Icons.business_rounded, color: cs.primary),
          title: Text(pb?.name ?? 'No business selected'),
          subtitle: session != null
              ? Text(
                  'Role: ${pb!.role} · ${pb.effectiveDisplayTitle}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                )
              : null,
        ),
        _NavTile(
          icon: Icons.receipt_long_outlined,
          title: 'Purchase order / business profile',
          subtitle: businessProfileReadOnly
              ? 'View GSTIN, address, phone, accounts WhatsApp (read-only)'
              : 'GSTIN, address, phone, accounts WhatsApp for PO sharing',
          onTap: () => context.push(
            businessProfileReadOnly
                ? '/settings/business?readonly=1'
                : '/settings/business',
          ),
        ),
        if (canManageUsers)
          _NavTile(
            icon: Icons.group_outlined,
            title: 'Users & roles',
            subtitle: 'Staff and manager logins for this workspace',
            onTap: () => context.push('/settings/users'),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: context.adaptiveCard,
      clipBehavior: Clip.antiAlias,
      child: Column(children: _withDividers(children)),
    );
  }

  List<Widget> _withDividers(List<Widget> rows) {
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) out.add(const Divider(height: 1));
      out.add(rows[i]);
    }
    return out;
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
