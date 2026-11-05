import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController(text: '+967 770 123 456');
  final _otpController = TextEditingController();
  int _step = 0;
  bool _busy = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_phoneController.text.trim().length < 8) {
      QToast.show(context, 'أدخل رقم جوال صحيح', error: true);
      return;
    }
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = 1;
    });
  }

  Future<void> _verify() async {
    if (_otpController.text.trim().length < 4) {
      QToast.show(context, 'أدخل رمز التحقق', error: true);
      return;
    }
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    QScope.of(context).login();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: isDark
                ? const [QColors.night, QColors.nightSurface]
                : const [
                    Color(0xFFF2FFF7),
                    QColors.pearlWhite,
                    Color(0xFFE6FBEF),
                  ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(QSpace.xl),
            child: QResponsiveBody(
              maxWidth: 520,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: QSpace.xxl),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: QLogoMark(size: 76, showGlow: true),
                  ),
                  const SizedBox(height: QSpace.xl),
                  Text(
                    'QAT LINK',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  Text(
                    'قات لينك • دفتر التجارة المشترك',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: QColors.brightGreen,
                    ),
                  ),
                  const SizedBox(height: QSpace.sm),
                  Text(
                    'أنت تسجل.. وأنا أعتمد.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: QColors.neutralGray),
                  ),
                  const SizedBox(height: QSpace.huge),
                  AnimatedSwitcher(
                    duration: QDuration.normal,
                    child: _step == 0 ? _phoneStep() : _otpStep(),
                  ),
                  const SizedBox(height: QSpace.xl),
                  Row(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: QColors.neutralGray,
                      ),
                      const SizedBox(width: QSpace.sm),
                      Expanded(
                        child: Text(
                          'بياناتك المالية مشفرة، ولا تظهر إلا لك ولأطراف علاقاتك.',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: QSpace.lg),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: QSpace.lg,
                    runSpacing: QSpace.sm,
                    children: [
                      TextButton(
                        onPressed: () => QScope.of(context).login(),
                        child: const Text('دخول تجريبي سريع'),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: const Text('الشروط والخصوصية'),
                      ),
                    ],
                  ),
                  const SizedBox(height: QSpace.xxl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneStep() {
    return Column(
      key: const ValueKey('phone'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('تسجيل الدخول', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: QSpace.sm),
        Text(
          'أدخل رقم جوالك وسنرسل لك رمز تحقق. لا نحتاج كلمة مرور.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: QColors.neutralGray),
        ),
        const SizedBox(height: QSpace.xl),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'رقم الجوال',
            hintText: '+967 7xx xxx xxx',
            prefixIcon: Icon(Icons.phone_iphone_rounded),
          ),
        ),
        const SizedBox(height: QSpace.lg),
        QGradientButton(
          label: _busy ? 'جارٍ إرسال الرمز...' : 'إرسال رمز التحقق',
          icon: Icons.arrow_back_rounded,
          onPressed: _busy ? null : _sendCode,
        ),
      ],
    );
  }

  Widget _otpStep() {
    return Column(
      key: const ValueKey('otp'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('رمز التحقق', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: QSpace.sm),
        Text(
          'أرسلنا رمزاً إلى ${_phoneController.text}. أدخل الرمز للمتابعة.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: QColors.neutralGray),
        ),
        const SizedBox(height: QSpace.xl),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(letterSpacing: 14),
          decoration: const InputDecoration(
            counterText: '',
            hintText: '••••••',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        const SizedBox(height: QSpace.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : () => setState(() => _step = 0),
            child: const Text('تغيير الرقم'),
          ),
        ),
        const SizedBox(height: QSpace.lg),
        QGradientButton(
          label: _busy ? 'جارٍ التحقق...' : 'تأكيد الدخول',
          icon: Icons.check_rounded,
          onPressed: _busy ? null : _verify,
        ),
        const SizedBox(height: QSpace.sm),
        Center(
          child: Text(
            'رمز تجريبي: أي 4 أرقام أو أكثر',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}
