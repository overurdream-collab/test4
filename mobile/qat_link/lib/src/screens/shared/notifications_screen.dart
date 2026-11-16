import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';

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
                    _NotificationCard(
                      notification: notification,
                      onOpen: () =>
                          _openNotification(context, state, notification),
                    ),
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
                      const SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: true,
                        onChanged: null,
                        title: Text('إشعارات التطبيق'),
                        subtitle: Text('إلزامية لجميع الحسابات'),
                      ),
                      if (state.accountType == AccountType.merchant) ...[
                        const Divider(),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: state.reminderNotificationsEnabled,
                          onChanged: state.toggleReminderNotifications,
                          title: const Text('تنبيهات التاجر'),
                          subtitle: const Text(
                            'يمكن تعطيلها دون بقية الإشعارات',
                          ),
                        ),
                      ],
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

  Future<void> _openNotification(
    BuildContext context,
    AppState state,
    AppNotification notification,
  ) async {
    state.markNotificationRead(notification.id);
    final invitationId = notification.invitationId;
    if (invitationId != null) {
      final decision = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(QRadius.xl)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(QSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                QSheetHeader(
                  title: notification.title,
                  subtitle: notification.body,
                  onClose: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: QSpace.lg),
                QGradientButton(
                  label: 'قبول الدعوة',
                  icon: Icons.check_rounded,
                  onPressed: () => Navigator.of(context).pop('accepted'),
                ),
                const SizedBox(height: QSpace.sm),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop('rejected'),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('رفض الدعوة'),
                ),
              ],
            ),
          ),
        ),
      );
      if (decision == null) return;
      try {
        await state.decideInvitation(
          invitationId: invitationId,
          decision: decision,
        );
        if (context.mounted) {
          QToast.show(
            context,
            decision == 'accepted' ? 'تم قبول الدعوة' : 'تم رفض الدعوة',
          );
        }
      } on Object {
        if (context.mounted) {
          QToast.show(context, 'تعذر تنفيذ الطلب. أعد المحاولة.', error: true);
        }
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(notification.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.body),
            const SizedBox(height: QSpace.md),
            Text(
              formatDateTime(notification.at),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('تم'),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onOpen});

  final AppNotification notification;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (notification.kind) {
      NotificationKind.app => (
        Icons.receipt_long_outlined,
        QColors.brightGreen,
      ),
      NotificationKind.reminder => (Icons.alarm_rounded, QColors.pendingFg),
      NotificationKind.admin => (Icons.shield_outlined, QColors.charcoal),
    };
    return QCard(
      onTap: onOpen,
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
