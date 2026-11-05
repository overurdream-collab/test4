import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../state/app_state.dart';
import 'tokens.dart';

class QScope extends InheritedNotifier<AppState> {
  const QScope({required AppState state, required super.child, super.key})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<QScope>();
    assert(scope != null, 'QScope is missing above this widget');
    return scope!.notifier!;
  }
}

class QStatusVisual {
  const QStatusVisual(this.background, this.foreground, this.icon);

  final Color background;
  final Color foreground;
  final IconData icon;
}

QStatusVisual statusVisual(TxStatus status) => switch (status) {
  TxStatus.pending => const QStatusVisual(
    QColors.pendingBg,
    QColors.pendingFg,
    Icons.schedule_rounded,
  ),
  TxStatus.approved => const QStatusVisual(
    QColors.approvedBg,
    QColors.approvedFg,
    Icons.check_circle_outline_rounded,
  ),
  TxStatus.rejected => const QStatusVisual(
    QColors.rejectedBg,
    QColors.rejectedFg,
    Icons.cancel_outlined,
  ),
  TxStatus.editRequested => const QStatusVisual(
    QColors.editBg,
    QColors.editFg,
    Icons.edit_note_rounded,
  ),
  TxStatus.local => const QStatusVisual(
    QColors.localBg,
    QColors.localFg,
    Icons.offline_pin_outlined,
  ),
  TxStatus.syncing => const QStatusVisual(
    QColors.localBg,
    QColors.localFg,
    Icons.sync_rounded,
  ),
};

class QLogoMark extends StatelessWidget {
  const QLogoMark({super.key, this.size = 52, this.showGlow = false});

  final double size;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: QColors.gradient,
        borderRadius: BorderRadius.circular(size * 0.29),
        boxShadow: showGlow ? QColors.brandGlow : null,
      ),
      child: CustomPaint(painter: _LeafLinkPainter()),
    );
  }
}

class _LeafLinkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width;
    final leaf = Path()
      ..moveTo(unit * 0.50, unit * 0.18)
      ..cubicTo(
        unit * 0.25,
        unit * 0.30,
        unit * 0.19,
        unit * 0.58,
        unit * 0.40,
        unit * 0.69,
      )
      ..cubicTo(
        unit * 0.32,
        unit * 0.56,
        unit * 0.38,
        unit * 0.38,
        unit * 0.50,
        unit * 0.31,
      )
      ..cubicTo(
        unit * 0.63,
        unit * 0.38,
        unit * 0.68,
        unit * 0.56,
        unit * 0.60,
        unit * 0.69,
      )
      ..cubicTo(
        unit * 0.81,
        unit * 0.58,
        unit * 0.75,
        unit * 0.30,
        unit * 0.50,
        unit * 0.18,
      )
      ..close();
    canvas.drawPath(
      leaf,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );

    final lower = Path()
      ..moveTo(unit * 0.50, unit * 0.82)
      ..cubicTo(
        unit * 0.75,
        unit * 0.70,
        unit * 0.81,
        unit * 0.42,
        unit * 0.60,
        unit * 0.31,
      )
      ..cubicTo(
        unit * 0.68,
        unit * 0.44,
        unit * 0.62,
        unit * 0.62,
        unit * 0.50,
        unit * 0.69,
      )
      ..cubicTo(
        unit * 0.37,
        unit * 0.62,
        unit * 0.32,
        unit * 0.44,
        unit * 0.40,
        unit * 0.31,
      )
      ..cubicTo(
        unit * 0.19,
        unit * 0.42,
        unit * 0.25,
        unit * 0.70,
        unit * 0.50,
        unit * 0.82,
      )
      ..close();
    canvas.drawPath(
      lower,
      Paint()..color = QColors.charcoal.withValues(alpha: 0.88),
    );

    final linkPaint = Paint()
      ..color = QColors.charcoal.withValues(alpha: 0.72)
      ..strokeWidth = unit * 0.06
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(unit * 0.5, unit * 0.33),
      Offset(unit * 0.5, unit * 0.67),
      linkPaint,
    );
    canvas.drawCircle(
      Offset(unit * 0.5, unit * 0.31),
      unit * 0.045,
      Paint()..color = QColors.charcoal.withValues(alpha: 0.72),
    );
    canvas.drawCircle(
      Offset(unit * 0.5, unit * 0.69),
      unit * 0.045,
      Paint()..color = QColors.charcoal.withValues(alpha: 0.72),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class QGradientButton extends StatelessWidget {
  const QGradientButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.expand = true,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: onPressed == null
              ? LinearGradient(
                  colors: [
                    QColors.neutralGray.withValues(alpha: 0.2),
                    QColors.neutralGray.withValues(alpha: 0.12),
                  ],
                )
              : QColors.gradient,
          borderRadius: BorderRadius.circular(QRadius.md),
          boxShadow: onPressed == null ? null : QColors.brandGlow,
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(QRadius.md),
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: QColors.charcoal),
                  const SizedBox(width: QSpace.sm),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: QColors.charcoal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!expand) return child;
    return SizedBox(width: double.infinity, child: child);
  }
}

class QStatusBadge extends StatelessWidget {
  const QStatusBadge({required this.status, super.key, this.compact = false});

  final TxStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visual = statusVisual(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? QSpace.sm : QSpace.md,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: visual.background,
        borderRadius: BorderRadius.circular(QRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: compact ? 13 : 15, color: visual.foreground),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: visual.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class QMoney extends StatelessWidget {
  const QMoney({
    required this.minor,
    super.key,
    this.currency = 'YER',
    this.style,
    this.color,
    this.hidden,
  });

  final int minor;
  final String currency;
  final TextStyle? style;
  final Color? color;
  final bool? hidden;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final isHidden = hidden ?? state.hideAmounts;
    return Text(
      formatMoney(minor, currency: currency, hidden: isHidden),
      style: (style ?? Theme.of(context).textTheme.titleMedium)?.copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class QCard extends StatelessWidget {
  const QCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(QSpace.lg),
    this.onTap,
    this.gradient,
    this.borderColor,
    this.radius = QRadius.lg,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(
        color:
            borderColor ??
            (isDark ? const Color(0xFF243A2E) : const Color(0xFFE7F1EB)),
      ),
    );
    final content = Ink(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(padding: padding, child: child),
    );
    return Material(
      color: gradient == null
          ? (isDark ? QColors.nightCard : QColors.pureWhite)
          : Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class QSectionHeader extends StatelessWidget {
  const QSectionHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.only(bottom: QSpace.md),
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class QAvatar extends StatelessWidget {
  const QAvatar({
    required this.label,
    super.key,
    this.size = 48,
    this.gradient = QColors.gradient,
    this.icon,
  });

  final String label;
  final double size;
  final Gradient gradient;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, color: QColors.charcoal, size: size * 0.46)
          : Text(
              initials(label),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: QColors.charcoal,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class QOfflineBanner extends StatelessWidget {
  const QOfflineBanner({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: QSpace.md,
        vertical: QSpace.sm,
      ),
      decoration: BoxDecoration(
        color: QColors.pendingBg,
        borderRadius: BorderRadius.circular(QRadius.md),
        border: Border.all(color: QColors.premiumGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: QColors.pendingFg,
          ),
          const SizedBox(width: QSpace.sm),
          Expanded(
            child: Text(
              'يعمل دون اتصال • العمليات تُحفظ محلياً ولن تُعتمد قبل المزامنة',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: QColors.pendingFg),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: QColors.pendingFg,
                minimumSize: const Size(40, 32),
                padding: const EdgeInsets.symmetric(horizontal: QSpace.sm),
              ),
              child: const Text('إعادة'),
            ),
        ],
      ),
    );
  }
}

class QBalanceRing extends StatelessWidget {
  const QBalanceRing({
    required this.amountMinor,
    super.key,
    this.label = 'الرصيد المعتمد',
    this.currency = 'YER',
    this.progress = 0.72,
    this.size = 190,
    this.hidden = false,
    this.secondaryLabel,
    this.secondaryAmountMinor,
  });

  final int amountMinor;
  final String label;
  final String currency;
  final double progress;
  final double size;
  final bool hidden;
  final String? secondaryLabel;
  final int? secondaryAmountMinor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress: progress),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: QSpace.xs),
              Text(
                formatMoney(amountMinor, currency: currency, hidden: hidden),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (secondaryAmountMinor != null) ...[
                const SizedBox(height: QSpace.xs),
                Text(
                  '${secondaryLabel ?? 'معلق'}: ${formatMoney(secondaryAmountMinor!, currency: currency, hidden: hidden)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: QColors.pendingFg),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final background = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = QColors.neutralGray.withValues(alpha: 0.15);
    canvas.drawCircle(center, radius, background);

    final gradient = const SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: math.pi * 1.5,
      colors: [QColors.brightGreen, QColors.freshGreen, QColors.lightGreen],
      transform: GradientRotation(-math.pi / 2),
    ).createShader(rect);
    final foreground = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..shader = gradient;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      foreground,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class QBarChart extends StatelessWidget {
  const QBarChart({
    required this.values,
    super.key,
    this.labels = const ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'],
    this.height = 170,
  });

  final List<double> values;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _BarsPainter(
          values: values,
          labels: labels,
          textColor: Theme.of(context).colorScheme.onSurfaceVariant,
          gridColor: Theme.of(context).colorScheme.outlineVariant,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.labels,
    required this.textColor,
    required this.gridColor,
  });

  final List<double> values;
  final List<String> labels;
  final Color textColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const chartBottom = 28.0;
    final chartHeight = size.height - chartBottom;
    final maxValue = values.reduce(math.max);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var line = 0; line < 4; line++) {
      final y = chartHeight * line / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final gap = size.width / values.length;
    final barWidth = math.min(30.0, gap * 0.46);
    for (var index = 0; index < values.length; index++) {
      final normalized = maxValue == 0 ? 0.0 : values[index] / maxValue;
      final barHeight = (chartHeight - 16) * normalized;
      final left = gap * index + (gap - barWidth) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, chartHeight - barHeight, barWidth, barHeight),
        const Radius.circular(8),
      );
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [QColors.freshGreen, QColors.brightGreen],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[index % labels.length],
          style: TextStyle(color: textColor, fontSize: 11),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(gap * index + (gap - textPainter.width) / 2, chartHeight + 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter oldDelegate) =>
      oldDelegate.values != values;
}

class QEntryTile extends StatelessWidget {
  const QEntryTile({
    required this.entry,
    super.key,
    this.title,
    this.onTap,
    this.trailing,
    this.showStatus = true,
  });

  final LedgerEntry entry;
  final String? title;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final isPayment =
        entry.type == OperationType.payment ||
        entry.type == OperationType.refund ||
        entry.type == OperationType.salesReturn;
    final sign = isPayment ? '−' : '+';
    final amountColor = isPayment ? QColors.approvedFg : QColors.charcoal;
    final displayTitle =
        title ??
        entry.productName ??
        (entry.type == OperationType.payment ? 'دفعة' : entry.type.label);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(QRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: QSpace.sm,
          vertical: QSpace.md,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isPayment ? QColors.approvedBg : QColors.softMint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isPayment ? Icons.south_west_rounded : Icons.north_east_rounded,
                size: 20,
                color: isPayment ? QColors.approvedFg : QColors.brightGreen,
              ),
            ),
            const SizedBox(width: QSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          formatDateTime(entry.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      if (entry.photoCount > 0) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.photo_outlined,
                          size: 13,
                          color: QColors.neutralGray,
                        ),
                        Text(
                          '${entry.photoCount}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: QSpace.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$sign ${formatMoney(entry.amountMinor, hidden: state.hideAmounts)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: amountColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (showStatus) ...[
                  const SizedBox(height: 4),
                  QStatusBadge(status: entry.status, compact: true),
                ],
              ],
            ),
            if (trailing != null) ...[
              const SizedBox(width: QSpace.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class QContactTile extends StatelessWidget {
  const QContactTile({
    required this.contact,
    super.key,
    this.onTap,
    this.showPhone = true,
    this.trailing,
  });

  final Contact contact;
  final VoidCallback? onTap;
  final bool showPhone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(QRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: QSpace.sm,
          vertical: QSpace.md,
        ),
        child: Row(
          children: [
            QAvatar(
              label: contact.displayName,
              gradient: contact.favorite
                  ? QColors.gradient
                  : LinearGradient(
                      colors: [
                        QColors.softMint,
                        QColors.lightGreen.withValues(alpha: 0.55),
                      ],
                    ),
            ),
            const SizedBox(width: QSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          contact.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (contact.favorite) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.star_rounded,
                          size: 15,
                          color: QColors.premiumGold,
                        ),
                      ],
                      if (!contact.hasApp) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 14,
                          color: QColors.neutralGray,
                        ),
                      ],
                    ],
                  ),
                  if (showPhone)
                    Text(
                      contact.phone,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: QSpace.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMoney(contact.balanceMinor, hidden: state.hideAmounts),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: QColors.approvedFg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (contact.pendingMinor > 0)
                  Text(
                    'معلق ${formatMoney(contact.pendingMinor, hidden: state.hideAmounts)}',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: QColors.pendingFg),
                  ),
              ],
            ),
            if (trailing != null) ...[
              const SizedBox(width: QSpace.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class QStateView extends StatelessWidget {
  const QStateView({
    required this.state,
    super.key,
    this.title,
    this.message,
    this.onRetry,
    this.compact = false,
  });

  final QDataState state;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final spec = _stateSpec(state, title, message);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? QSpace.lg : QSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 56 : 72,
              height: compact ? 56 : 72,
              decoration: BoxDecoration(
                color: spec.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(QRadius.lg),
              ),
              child: Icon(
                spec.icon,
                size: compact ? 26 : 34,
                color: spec.color,
              ),
            ),
            const SizedBox(height: QSpace.lg),
            Text(
              spec.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: QSpace.xs),
            Text(
              spec.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: QSpace.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum QDataState {
  empty,
  loading,
  error,
  success,
  offline,
  local,
  syncing,
  subscriptionExpired,
  creditLimitExceeded,
}

class _StateSpec {
  const _StateSpec(this.title, this.message, this.icon, this.color);

  final String title;
  final String message;
  final IconData icon;
  final Color color;
}

_StateSpec _stateSpec(QDataState state, String? title, String? message) {
  final base = switch (state) {
    QDataState.empty => const _StateSpec(
      'لا توجد بيانات بعد',
      'ابدأ بإضافة أول عميل أو عملية لتظهر هنا.',
      Icons.inbox_outlined,
      QColors.neutralGray,
    ),
    QDataState.loading => const _StateSpec(
      'جارٍ التحميل',
      'نجهز أحدث الحركات والأرصدة.',
      Icons.hourglass_top_rounded,
      QColors.brightGreen,
    ),
    QDataState.error => const _StateSpec(
      'تعذر تحميل البيانات',
      'تحقق من الاتصال ثم أعد المحاولة.',
      Icons.error_outline_rounded,
      QColors.rejectedFg,
    ),
    QDataState.success => const _StateSpec(
      'تمت العملية بنجاح',
      'تم حفظ التغييرات وإشعار الطرف الآخر.',
      Icons.check_circle_outline_rounded,
      QColors.approvedFg,
    ),
    QDataState.offline => const _StateSpec(
      'أنت دون اتصال',
      'يمكنك الاستمرار بالتسجيل، وستُزامن العمليات لاحقاً.',
      Icons.cloud_off_rounded,
      QColors.pendingFg,
    ),
    QDataState.local => const _StateSpec(
      'محفوظة محلياً',
      'لم تصل إلى الطرف الآخر بعد، وستبقى معلقة حتى المزامنة.',
      Icons.offline_pin_outlined,
      QColors.localFg,
    ),
    QDataState.syncing => const _StateSpec(
      'بانتظار المزامنة',
      'نحاول إرسال العملية إلى الخادم بأمان.',
      Icons.sync_rounded,
      QColors.brightGreen,
    ),
    QDataState.subscriptionExpired => const _StateSpec(
      'انتهى الاشتراك',
      'كشف الحساب والتصدير متاحان، والعمليات الجديدة متوقفة مؤقتاً.',
      Icons.workspace_premium_outlined,
      QColors.premiumGold,
    ),
    QDataState.creditLimitExceeded => const _StateSpec(
      'تجاوز الحد الائتماني',
      'يتطلب متابعة العملية تأكيد التاجر قبل الحفظ.',
      Icons.speed_rounded,
      QColors.editFg,
    ),
  };
  return _StateSpec(
    title ?? base.title,
    message ?? base.message,
    base.icon,
    base.color,
  );
}

class QLoadingCard extends StatelessWidget {
  const QLoadingCard({super.key, this.height = 92});

  final double height;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(QRadius.lg),
      ),
    );
  }
}

class QCreditLimitBar extends StatelessWidget {
  const QCreditLimitBar({
    required this.usedMinor,
    required this.limitMinor,
    super.key,
    this.currency = 'YER',
    this.hidden = false,
  });

  final int usedMinor;
  final int limitMinor;
  final String currency;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final ratio = limitMinor == 0
        ? 0.0
        : (usedMinor / limitMinor).clamp(0.0, 1.4);
    final exceeded = usedMinor > limitMinor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'الحد الائتماني',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(width: QSpace.sm),
            Expanded(
              child: Text(
                '${formatMoney(usedMinor, currency: currency, hidden: hidden)} / ${formatMoney(limitMinor, currency: currency, hidden: hidden)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: exceeded ? QColors.rejectedFg : QColors.neutralGray,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: QSpace.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(QRadius.pill),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 9,
            backgroundColor: QColors.neutralGray.withValues(alpha: 0.16),
            valueColor: AlwaysStoppedAnimation(
              exceeded ? QColors.rejectedFg : QColors.brightGreen,
            ),
          ),
        ),
      ],
    );
  }
}

class QFilterPills extends StatelessWidget {
  const QFilterPills({
    required this.items,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<String> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            ChoiceChip(
              label: Text(items[index]),
              selected: selected == index,
              onSelected: (_) => onSelected(index),
            ),
            if (index != items.length - 1) const SizedBox(width: QSpace.sm),
          ],
        ],
      ),
    );
  }
}

class QToast {
  static void show(BuildContext context, String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? QColors.rejectedFg : QColors.charcoal,
        ),
      );
  }
}

class QSheetHeader extends StatelessWidget {
  const QSheetHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(QRadius.pill),
            ),
          ),
        ),
        const SizedBox(height: QSpace.lg),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ],
    );
  }
}

class QResponsiveBody extends StatelessWidget {
  const QResponsiveBody({
    required this.child,
    super.key,
    this.maxWidth = 1180,
    this.padding = const EdgeInsets.all(QSpace.lg),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class QPhotoTile extends StatelessWidget {
  const QPhotoTile({required this.photo, super.key, this.height = 150});

  final DayPhoto photo;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(QRadius.md),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              HSLColor.fromAHSL(1, photo.hue, 0.55, 0.82).toColor(),
              HSLColor.fromAHSL(
                1,
                (photo.hue + 28) % 360,
                0.65,
                0.95,
              ).toColor(),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -18,
              bottom: -22,
              child: Icon(
                Icons.eco_rounded,
                size: 110,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
            Positioned(
              right: -12,
              top: -12,
              child: Icon(
                Icons.local_florist_rounded,
                size: 88,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(QSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    photo.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: QColors.charcoal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    photo.audience,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: QColors.charcoal.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
