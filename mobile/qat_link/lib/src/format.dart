const currencyLabels = <String, String>{
  'YER': 'ر.ي',
  'SAR': 'ر.س',
  'USD': '\$',
};

String formatNumber(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }
  return negative ? '-${buffer.toString()}' : buffer.toString();
}

String formatMoney(int minor, {String currency = 'YER', bool hidden = false}) {
  if (hidden) return '••••••';
  final major = (minor / 100).round();
  return '${formatNumber(major)} ${currencyLabels[currency] ?? currency}';
}

String formatCompactMoney(int minor, {String currency = 'YER'}) {
  final major = (minor / 100).round();
  if (major >= 1000000) {
    final value = major / 1000000;
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)}م ${currencyLabels[currency] ?? currency}';
  }
  if (major >= 1000) {
    final value = major / 1000;
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)}ألف ${currencyLabels[currency] ?? currency}';
  }
  return formatMoney(minor, currency: currency);
}

const _weekdays = <String>[
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

const _months = <String>[
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

String formatDate(DateTime value) {
  final now = DateTime.now();
  final day = DateTime(value.year, value.month, value.day);
  final today = DateTime(now.year, now.month, now.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'اليوم';
  if (difference == 1) return 'أمس';
  if (difference > 1 && difference < 7) return _weekdays[value.weekday - 1];
  return '${value.day} ${_months[value.month - 1]} ${value.year}';
}

String formatDateTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${formatDate(value)} • $hour:$minute';
}

String monthLabel(DateTime value) =>
    '${_months[value.month - 1]} ${value.year}';

String initials(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '؟';
  if (parts.length == 1) return parts.first.substring(0, 1);
  return '${parts.first.substring(0, 1)}${parts[1].substring(0, 1)}';
}
