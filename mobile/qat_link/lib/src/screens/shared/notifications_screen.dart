import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final notifications = state.notifications.where((notification) {
      return switch (_filter) {
        1 => notification.kind == NotificationKind.app,
        2 => notification.kind == NotificationKind.reminder,
        3 => notification.kind == NotificationKind.admin,
        _ => true,
      };
    }).toList()..sort((a, b) => b.at.compareTo(a.at));

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          TextButton(
            onPressed: state.unreadNotifications == 0
                ? null
                : state.markAllNotificationsRead,
            child: const Text('قراءة الكل'),
          ),
          const SizedBox(width: QSpace.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: QSpace.xxl),
        children: [
          QResponsiveBody(
            padding: const EdgeInsets.fromLTRB(
              QSpace.lg,
              QSpace.sm,
              QSpace.lg,
              QSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                QFilterPills(
                  items: const ['الكل', 'التطبيق', 'التذكيرات', 'الإدارة'],
                  selected: _filter,
                  onSelected: (value) => setState(() => _filter = value),
                ),
                const SizedBox(height: QSpace.md),
                QCard(
                  gradient: const LinearGradient(
                    colors: [QColors.softMint, QColors.pureWhite],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        color: QColors.brightGreen,
                      ),
                      const SizedBox(width: QSpace.md),
                      Expanded(
                        child: Text(
                          'إشعارات الإدارة الأمنية والسياسية لا يمكن إيقافها.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                if (notifications.isEmpty)
                  const QStateView(
                    state: QDataState.empty,
                    title: 'لا توجد إشعارات',
                    message:
                        'ستظهر هنا العمليات التي تحتاج موافقتك والتذكيرات المهمة.',
                  )
                else
                  for (final notification in notifications) ...[
                    _NotificationCard(notification: notification),
                    const SizedBox(height: QSpace.sm),
                  ],
                const SizedBox(height: QSpace.lg),
                QSectionHeader(
                  title: 'إعدادات التنبيه',
                  subtitle: 'يمكنك ضبط الإشعارات من الإعدادات.',
                  actionLabel: 'الإعدادات',
                  onAction: () => Navigator.of(context).pop(),
                ),
                QCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: state.appNotificationsEnabled,
                        onChanged: state.toggleAppNotifications,
                        title: const Text('إشعارات التطبيق'),
                        subtitle: const Text('العمليات الجديدة والموافقات'),
                      ),
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: state.reminderNotificationsEnabled,
                        onChanged: state.toggleReminderNotifications,
                        title: const Text('تذكيرات الديون'),
                        subtitle: const Text('تنبيه بالمبالغ المعلقة'),
                      ),
                    ],
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final (icon, color) = switch (notification.kind) {
      NotificationKind.app => (
        Icons.receipt_long_outlined,
        QColors.brightGreen,
      ),
      NotificationKind.reminder => (Icons.alarm_rounded, QColors.pendingFg),
      NotificationKind.admin => (Icons.shield_outlined, QColors.charcoal),
    };
    return QCard(
      onTap: () => state.markNotificationRead(notification.id),
      borderColor: notification.read
          ? null
          : QColors.brightGreen.withValues(alpha: 0.45),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: QSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (!notification.read)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: QColors.brightGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  notification.body,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: QSpace.sm),
                Text(
                  formatDateTime(notification.at),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
