import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qat_link/src/app.dart';
import 'package:qat_link/src/models.dart';
import 'package:qat_link/src/state/app_state.dart';

Future<void> pumpApp(WidgetTester tester, AppState state) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(QatLinkApp(state: state));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('merchant home renders the main dashboard', (tester) async {
    final state = AppState();
    await pumpApp(tester, state);

    expect(find.textContaining('أهلاً، أحمد'), findsOneWidget);
    expect(find.text('أنت تسجل.. وأنا أعتمد.'), findsOneWidget);
    expect(find.text('العملاء'), findsWidgets);
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  testWidgets('bottom navigation opens the customers screen', (tester) async {
    final state = AppState();
    await pumpApp(tester, state);

    await tester.tap(find.byIcon(Icons.people_alt_rounded));
    await tester.pumpAndSettle();

    expect(find.text('ابحث بالاسم أو رقم الجوال'), findsOneWidget);
    expect(find.text('أضف عميلاً وادعُه للتطبيق'), findsOneWidget);
  });

  testWidgets('center add button opens the quick add menu', (tester) async {
    final state = AppState();
    await pumpApp(tester, state);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.text('اختيار نوع الإضافة'), findsOneWidget);
    expect(find.text('تسجيل دين جديد'), findsOneWidget);
    expect(find.text('إضافة عميل جديد'), findsOneWidget);
  });

  testWidgets('center label opens the store screen', (tester) async {
    final state = AppState();
    await pumpApp(tester, state);

    await tester.tap(find.text('متجري'));
    await tester.pumpAndSettle();

    expect(find.text('متجري'), findsWidgets);
    expect(find.text('نشاط أخير'), findsOneWidget);
    expect(find.text('الموظفون'), findsOneWidget);
  });

  testWidgets('switching to the customer persona shows customer home', (
    tester,
  ) async {
    final state = AppState();
    await pumpApp(tester, state);

    state.setPersona(AppPersona.customer);
    await tester.pumpAndSettle();

    expect(find.text('أحمد الصبري'), findsWidgets);
    expect(find.text('770 123 456'), findsOneWidget);
    expect(find.text('إجمالي المستحق'), findsOneWidget);
    expect(find.text('طلب سداد'), findsWidgets);
  });

  testWidgets('settings shows subscription and device entry points', (
    tester,
  ) async {
    final state = AppState();
    await pumpApp(tester, state);

    await tester.tap(find.byIcon(Icons.settings_outlined).last);
    await tester.pumpAndSettle();

    expect(find.text('الباقة الحالية'), findsOneWidget);
    expect(find.text('الأجهزة والجلسات'), findsOneWidget);
    expect(find.text('مفاهيم الشعار'), findsNothing);

    state.isAdmin = true;
    state.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('مفاهيم الشعار'), findsOneWidget);
    expect(find.text('معاينة لوحة الإدارة'), findsOneWidget);
  });

  testWidgets('logout returns to the login screen', (tester) async {
    final state = AppState();
    await pumpApp(tester, state);

    state.logout();
    await tester.pumpAndSettle();

    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('دخول تجريبي سريع'), findsOneWidget);
  });
}
