import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../data/api_models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../models.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _phoneController;
  final _otpController = TextEditingController();
  int _step = 0;
  bool _busy = false;
  AccountType _accountType = AccountType.customer;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(
      text: AppConfig.useDemoData ? '+967 770 123 456' : '',
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 8) {
      QToast.show(context, 'أدخل رقم جوال صحيح', error: true);
      return;
    }
    final state = QScope.of(context);
    setState(() => _busy = true);
    try {
      if (state.isRemote) {
        await state.requestOtp(phone);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 550));
      }
      if (!mounted) return;
      setState(() => _step = 1);
    } on ApiException catch (error) {
      if (mounted) QToast.show(context, _message(error), error: true);
    } on Object {
      if (mounted) {
        QToast.show(
          context,
          'تعذر الاتصال بالخادم. تحقق من الشبكة.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _otpController.text.trim();
    final state = QScope.of(context);
    final minimum = state.isRemote ? 6 : 4;
    if (code.length < minimum) {
      QToast.show(
        context,
        state.isRemote
            ? 'أدخل رمز التحقق المكوّن من 6 أرقام'
            : 'أدخل رمز التحقق',
        error: true,
      );
      return;
    }
    if (!state.isRemote &&
        AppConfig.hasUatOtp &&
        code != AppConfig.uatOtpCode) {
      QToast.show(
        context,
        'رمز UAT غير صحيح. استخدم الرمز المعروض.',
        error: true,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (state.isRemote) {
        await state.verifyOtp(
          phone: _phoneController.text,
          code: code,
          accountType: _accountType,
        );
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (!mounted) return;
        state.selectAccountType(_accountType);
        state.login();
      }
    } on ApiException catch (error) {
      if (mounted) QToast.show(context, _message(error), error: true);
    } on Object {
      if (mounted) {
        QToast.show(
          context,
          'تعذر الاتصال بالخادم. تحقق من الشبكة.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(ApiException error) {
    return switch (error.code) {
      'invalid_or_expired_otp' => 'رمز التحقق غير صحيح أو منتهي الصلاحية.',
      'invalid_phone' => 'رقم الجوال غير صحيح.',
      'rate_limited' => 'محاولات كثيرة. انتظر قليلاً ثم أعد المحاولة.',
      'device_unavailable' => 'تعذر تسجيل هذا الجهاز. جرّب جهازاً آخر.',
      'account_suspended' => 'الحساب موقوف. تواصل مع الدعم.',
      _ =>
        error.statusCode >= 500
            ? 'الخادم غير متاح حالياً. أعد المحاولة.'
            : 'تعذر إكمال الطلب (${error.code}).',
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? QColors.night : QColors.pearlWhite,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [QColors.night, QColors.nightSurface]
                : const [QColors.pearlWhite, QColors.softMint],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(QSpace.lg),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - QSpace.xxl,
                  ),
                  child: Center(
                    child: QResponsiveBody(
                      maxWidth: 480,
                      padding: EdgeInsets.zero,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: QColors.softMint,
                              border: Border.all(
                                color: QColors.freshGreen,
                                width: 4,
                              ),
                              boxShadow: QColors.brandGlow,
                            ),
                            child: const QBrandAvatar(size: 104),
                          ),
                          const SizedBox(height: QSpace.lg),
                          Text(
                            'مرحباً بك في QAT LINK',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: QColors.brightGreen,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: QSpace.xs),
                          Text(
                            'التطبيق المالي الذكي لإدارة الديون والتحصيلات في اليمن',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: QSpace.xl),
                          QCard(
                            padding: const EdgeInsets.all(QSpace.xl),
                            child: AnimatedSwitcher(
                              duration: QDuration.normal,
                              child: _step == 0 ? _phoneStep() : _otpStep(),
                            ),
                          ),
                          const SizedBox(height: QSpace.lg),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.shield_outlined,
                                size: 15,
                                color: QColors.neutralGray,
                              ),
                              const SizedBox(width: QSpace.xs),
                              Flexible(
                                child: Text(
                                  'بياناتك المالية مشفرة ولا تظهر إلا لك ولأطراف علاقاتك.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: QSpace.sm),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: QSpace.lg,
                            runSpacing: QSpace.sm,
                            children: [
                              if (!QScope.of(context).isRemote)
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
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _phoneStep() {
    return Column(
      key: const ValueKey('phone'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'تسجيل الدخول',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: QSpace.xs),
        Text(
          'أدخل رقم جوالك وسنرسل لك رمز تحقق. لا نحتاج كلمة مرور.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: QSpace.lg),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            labelText: 'رقم الجوال',
            hintText: '+967 7xx xxx xxx',
            prefixIcon: Icon(Icons.phone_iphone_rounded),
          ),
        ),
        const SizedBox(height: QSpace.lg),
        Text('نوع الحساب', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: QSpace.xs),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: QSpace.sm,
          runSpacing: QSpace.sm,
          children: AccountType.values.map((type) {
            final selected = _accountType == type;
            return ChoiceChip(
              label: Text(type.label),
              avatar: Icon(switch (type) {
                AccountType.customer => Icons.person_outline_rounded,
                AccountType.merchant => Icons.storefront_outlined,
                AccountType.supplier => Icons.local_shipping_outlined,
              }, size: 18),
              selected: selected,
              onSelected: _busy
                  ? null
                  : (_) => setState(() => _accountType = type),
            );
          }).toList(),
        ),
        const SizedBox(height: QSpace.xs),
        Text(
          'يُثبّت نوع الحساب عند أول تسجيل.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'رمز التحقق',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: QSpace.xs),
        Text(
          'أرسلنا رمزاً إلى ${_phoneController.text}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: QSpace.lg),
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
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : () => setState(() => _step = 0),
            child: const Text('تغيير الرقم'),
          ),
        ),
        QGradientButton(
          label: _busy ? 'جارٍ التحقق...' : 'تأكيد الدخول',
          icon: Icons.check_rounded,
          onPressed: _busy ? null : _verify,
        ),
        if (AppConfig.hasUatOtp) ...[
          const SizedBox(height: QSpace.sm),
          Center(
            child: Text(
              'وضع UAT — رمز الدخول الثابت: ${AppConfig.uatOtpCode}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: QColors.brightGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ] else if (!QScope.of(context).isRemote) ...[
          const SizedBox(height: QSpace.sm),
          Center(
            child: Text(
              'رمز تجريبي: أي 4 أرقام أو أكثر',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ],
    );
  }
}
