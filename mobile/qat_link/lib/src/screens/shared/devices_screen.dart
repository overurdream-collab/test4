import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الأجهزة والجلسات')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: QSpace.xxl),
        children: [
          QResponsiveBody(
            maxWidth: 760,
            padding: const EdgeInsets.fromLTRB(
              QSpace.lg,
              QSpace.sm,
              QSpace.lg,
              QSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                QCard(
                  gradient: const LinearGradient(
                    colors: [QColors.softMint, QColors.pureWhite],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.security_rounded,
                        color: QColors.brightGreen,
                      ),
                      const SizedBox(width: QSpace.md),
                      Expanded(
                        child: Text(
                          'راجع الأجهزة المرتبطة بحسابك. أنهِ أي جلسة لا تعرفها فوراً.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                const _SectionLabel(label: 'الجلسات النشطة'),
                QCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < state.sessions.length;
                        index++
                      ) ...[
                        _SessionTile(session: state.sessions[index]),
                        if (index != state.sessions.length - 1) const Divider(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                const _SectionLabel(label: 'إجراءات الأمان'),
                QCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.password_rounded,
                          color: QColors.brightGreen,
                        ),
                        title: const Text('تغيير كلمة المرور'),
                        subtitle: const Text('آخر تغيير قبل 3 أشهر'),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () => QToast.show(
                          context,
                          'سيُطلب رمز التحقق لتغيير كلمة المرور',
                        ),
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(
                          Icons.phonelink_erase_rounded,
                          color: QColors.rejectedFg,
                        ),
                        title: const Text('إنهاء كل الجلسات الأخرى'),
                        subtitle: const Text('يبقى هذا الجهاز فقط'),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () => _confirmRevokeAll(context, state),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                Text(
                  'لأسباب أمنية، لا يمكن حذف الجهاز الحالي من القائمة.',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRevokeAll(BuildContext context, AppState state) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إنهاء الجلسات الأخرى؟'),
        content: const Text(
          'ستحتاج إلى تسجيل الدخول مجدداً على الأجهزة الأخرى. '
          'هذا الجهاز سيبقى مرتبطاً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: QColors.rejectedFg),
            onPressed: () {
              state.revokeOtherSessions();
              Navigator.of(context).pop();
              QToast.show(context, 'تم إنهاء الجلسات الأخرى');
            },
            child: const Text('إنهاء الكل'),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final DeviceSession session;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: session.current ? QColors.softMint : QColors.pearlWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: session.current
                ? QColors.brightGreen
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Icon(
          session.platform.contains('iOS')
              ? Icons.phone_iphone_rounded
              : session.platform.contains('Windows')
              ? Icons.desktop_windows_outlined
              : Icons.phone_android_rounded,
          color: session.current ? QColors.brightGreen : QColors.neutralGray,
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(session.name)),
          if (session.current) ...[
            const SizedBox(width: QSpace.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: QColors.approvedBg,
                borderRadius: BorderRadius.circular(QRadius.pill),
              ),
              child: Text(
                'هذا الجهاز',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: QColors.approvedFg),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${session.platform} • ${session.location}\n${formatDateTime(session.lastActive)}',
      ),
      isThreeLine: true,
      trailing: session.current
          ? null
          : IconButton(
              tooltip: 'إنهاء الجلسة',
              onPressed: () => _confirm(context, state),
              icon: const Icon(Icons.logout_rounded, size: 20),
            ),
    );
  }

  Future<void> _confirm(BuildContext context, AppState state) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إنهاء الجلسة؟'),
        content: Text('سيتم تسجيل الخروج من ${session.name}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              state.revokeSession(session.id);
              Navigator.of(context).pop();
              QToast.show(context, 'تم إنهاء الجلسة');
            },
            child: const Text('إنهاء'),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: QSpace.sm),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: QColors.brightGreen,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
