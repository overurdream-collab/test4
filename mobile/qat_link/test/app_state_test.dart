import 'package:flutter_test/flutter_test.dart';
import 'package:qat_link/src/models.dart';
import 'package:qat_link/src/state/app_state.dart';

void main() {
  group('AppState ledger', () {
    test('adds a pending debt and approves it into the balance', () {
      final state = AppState(seed: false);
      state.addCustomer(
        name: 'عميل تجريبي',
        phone: '+967 700 000 000',
        hasApp: true,
      );
      final customer = state.customers.single;

      state.addDebt(
        customerId: customer.id,
        amountMinor: 1500000,
        date: DateTime(2026, 11, 4),
        productName: 'قات رطب',
      );

      expect(state.customers.single.pendingMinor, 1500000);
      expect(state.merchantEntries.single.status, TxStatus.pending);

      state.approveEntry(state.merchantEntries.single.id);

      expect(state.customers.single.balanceMinor, 1500000);
      expect(state.customers.single.pendingMinor, 0);
      expect(state.merchantEntries.single.status, TxStatus.approved);
    });

    test('rejects a pending debt without changing the balance', () {
      final state = AppState(seed: false);
      state.addCustomer(
        name: 'عميل تجريبي',
        phone: '+967 700 000 001',
        hasApp: true,
      );
      final customer = state.customers.single;

      state.addDebt(
        customerId: customer.id,
        amountMinor: 900000,
        date: DateTime(2026, 11, 4),
      );
      state.rejectEntry(state.merchantEntries.single.id);

      expect(state.customers.single.balanceMinor, 0);
      expect(state.customers.single.pendingMinor, 0);
      expect(state.merchantEntries.single.status, TxStatus.rejected);
    });

    test('accepts an edit with the proposed amount only', () {
      final state = AppState(seed: false);
      state.addCustomer(
        name: 'عميل تجريبي',
        phone: '+967 700 000 002',
        hasApp: true,
      );
      final customer = state.customers.single;

      state.addDebt(
        customerId: customer.id,
        amountMinor: 2000000,
        date: DateTime(2026, 11, 4),
      );
      final id = state.merchantEntries.single.id;
      state.requestEdit(id, 1700000, 'خصم فرق الوزن');
      state.acceptEdit(id);

      expect(state.customers.single.balanceMinor, 1700000);
      expect(state.customers.single.pendingMinor, 0);
      expect(state.merchantEntries.single.status, TxStatus.approved);
    });

    test('declining an edit rejects it and clears the pending amount', () {
      final state = AppState(seed: false);
      state.addCustomer(
        name: 'عميل تجريبي',
        phone: '+967 700 000 003',
        hasApp: true,
      );
      final customer = state.customers.single;

      state.addDebt(
        customerId: customer.id,
        amountMinor: 400000,
        date: DateTime(2026, 11, 4),
      );
      final id = state.merchantEntries.single.id;
      state.requestEdit(id, 300000, 'بديل');
      state.declineEdit(id);

      expect(state.customers.single.balanceMinor, 0);
      expect(state.customers.single.pendingMinor, 0);
      expect(state.merchantEntries.single.status, TxStatus.rejected);
      expect(state.merchantEntries.single.proposedAmountMinor, isNull);
    });

    test('limits settlement requests to one per merchant per day', () {
      final state = AppState();
      final merchant = state.customerMerchants.first;

      state.requestSettlement(merchant.id);
      state.requestSettlement(merchant.id);

      expect(state.settlementFor(merchant.id), hasLength(1));
      expect(state.hasSettlementToday(merchant.id), isTrue);
    });

    test('enforces the daily photo limit', () {
      final state = AppState(seed: false);
      state.dailyPhotoLimit = 2;

      state.addPhoto('صورة أولى', 'جميع العملاء');
      state.addPhoto('صورة ثانية', 'جميع العملاء');
      state.addPhoto('صورة ثالثة', 'جميع العملاء');

      expect(state.photos, hasLength(2));
    });

    test('switching persona and theme notifies listeners', () {
      final state = AppState(seed: false);
      var notifications = 0;
      final initialTheme = state.themeMode;
      state.addListener(() => notifications++);

      state.setPersona(AppPersona.customer);
      state.toggleTheme();
      state.toggleOffline();

      expect(state.persona, AppPersona.customer);
      expect(state.themeMode, isNot(initialTheme));
      expect(state.offline, isTrue);
      expect(notifications, 3);
    });
  });
}
