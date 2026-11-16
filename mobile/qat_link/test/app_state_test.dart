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

    test('keeps an overpayment unapplied until allocation', () {
      final state = AppState(seed: false);
      state.addCustomer(
        name: 'عميل تجريبي',
        phone: '+967 700 000 004',
        hasApp: true,
      );
      final customer = state.customers.single;

      state.addDebt(
        customerId: customer.id,
        amountMinor: 1000000,
        date: DateTime(2026, 11, 4),
      );
      state.approveEntry(state.merchantEntries.single.id);
      expect(state.customers.single.balanceMinor, 1000000);

      addPendingEntry(
        state,
        LedgerEntry(
          id: 'overpayment',
          customerId: customer.id,
          merchantId: AppState.merchantId,
          type: OperationType.payment,
          amountMinor: 1500000,
          status: TxStatus.pending,
          createdAt: DateTime(2026, 11, 4, 1),
          createdByMe: false,
        ),
      );
      state.approveEntry('overpayment');

      expect(state.customers.single.balanceMinor, 1000000);
      expect(state.customers.single.pendingMinor, 0);
      expect(state.unappliedPaymentTotals(), {'YER': 1500000});

      addPendingEntry(
        state,
        LedgerEntry(
          id: 'allocation-1',
          customerId: customer.id,
          merchantId: AppState.merchantId,
          type: OperationType.allocation,
          amountMinor: 1000000,
          status: TxStatus.pending,
          createdAt: DateTime(2026, 11, 4, 2),
          createdByMe: false,
        ),
      );
      state.approveEntry('allocation-1');

      expect(state.customers.single.balanceMinor, 0);
      expect(state.unappliedPaymentTotals(), {'YER': 500000});
    });

    test('allocates partial and full payments without double counting', () {
      final state = AppState(seed: false);
      state.addCustomer(
        name: 'عميل تجريبي',
        phone: '+967 700 000 006',
        hasApp: true,
      );
      final customer = state.customers.single;

      state.addDebt(
        customerId: customer.id,
        amountMinor: 1000000,
        date: DateTime(2026, 11, 4),
      );
      state.approveEntry(state.merchantEntries.single.id);

      addPendingEntry(
        state,
        LedgerEntry(
          id: 'payment-full',
          customerId: customer.id,
          merchantId: AppState.merchantId,
          type: OperationType.payment,
          amountMinor: 1000000,
          status: TxStatus.pending,
          createdAt: DateTime(2026, 11, 4, 1),
        ),
      );
      state.approveEntry('payment-full');

      expect(state.customers.single.balanceMinor, 1000000);
      expect(state.unappliedPaymentTotals(), {'YER': 1000000});

      addPendingEntry(
        state,
        LedgerEntry(
          id: 'allocation-partial',
          customerId: customer.id,
          merchantId: AppState.merchantId,
          type: OperationType.allocation,
          amountMinor: 400000,
          status: TxStatus.pending,
          createdAt: DateTime(2026, 11, 4, 2),
        ),
      );
      state.approveEntry('allocation-partial');

      expect(state.customers.single.balanceMinor, 600000);
      expect(state.unappliedPaymentTotals(), {'YER': 600000});

      addPendingEntry(
        state,
        LedgerEntry(
          id: 'allocation-rest',
          customerId: customer.id,
          merchantId: AppState.merchantId,
          type: OperationType.allocation,
          amountMinor: 600000,
          status: TxStatus.pending,
          createdAt: DateTime(2026, 11, 4, 3),
        ),
      );
      state.approveEntry('allocation-rest');

      expect(state.customers.single.balanceMinor, 0);
      expect(state.unappliedPaymentTotals(), isEmpty);
    });

    test('separates payments and allocations by currency', () {
      final state = AppState(seed: false);
      state.addCustomer(
        name: 'عميل تجريبي',
        phone: '+967 700 000 007',
        hasApp: true,
      );
      final customer = state.customers.single;

      state.addDebt(
        customerId: customer.id,
        amountMinor: 1000000,
        date: DateTime(2026, 11, 4),
        currency: 'YER',
      );
      state.addDebt(
        customerId: customer.id,
        amountMinor: 200000,
        date: DateTime(2026, 11, 4),
        currency: 'SAR',
      );
      for (final entry in [...state.merchantEntries]) {
        state.approveEntry(entry.id);
      }

      addPendingEntry(
        state,
        LedgerEntry(
          id: 'payment-yer',
          customerId: customer.id,
          merchantId: AppState.merchantId,
          type: OperationType.payment,
          amountMinor: 1500000,
          currency: 'YER',
          status: TxStatus.pending,
          createdAt: DateTime(2026, 11, 4, 1),
        ),
      );
      addPendingEntry(
        state,
        LedgerEntry(
          id: 'payment-sar',
          customerId: customer.id,
          merchantId: AppState.merchantId,
          type: OperationType.payment,
          amountMinor: 50000,
          currency: 'SAR',
          status: TxStatus.pending,
          createdAt: DateTime(2026, 11, 4, 1),
        ),
      );
      state.approveEntry('payment-yer');
      state.approveEntry('payment-sar');

      expect(state.customers.single.balanceFor('YER'), 1000000);
      expect(state.customers.single.balanceFor('SAR'), 200000);
      expect(state.unappliedPaymentTotals(), {'YER': 1500000, 'SAR': 50000});

      addPendingEntry(
        state,
        LedgerEntry(
          id: 'allocation-yer',
          customerId: customer.id,
          merchantId: AppState.merchantId,
          type: OperationType.allocation,
          amountMinor: 1000000,
          currency: 'YER',
          status: TxStatus.pending,
          createdAt: DateTime(2026, 11, 4, 2),
        ),
      );
      addPendingEntry(
        state,
        LedgerEntry(
          id: 'allocation-sar',
          customerId: customer.id,
          merchantId: AppState.merchantId,
          type: OperationType.allocation,
          amountMinor: 50000,
          currency: 'SAR',
          status: TxStatus.pending,
          createdAt: DateTime(2026, 11, 4, 2),
        ),
      );
      state.approveEntry('allocation-yer');
      state.approveEntry('allocation-sar');

      expect(state.customers.single.balanceFor('YER'), 0);
      expect(state.customers.single.balanceFor('SAR'), 150000);
      expect(state.unappliedPaymentTotals(), {'YER': 500000});
    });

    test(
      'reverses payments and allocations without touching other currencies',
      () {
        final state = AppState(seed: false);
        state.addCustomer(
          name: 'عميل تجريبي',
          phone: '+967 700 000 008',
          hasApp: true,
        );
        final customer = state.customers.single;

        state.addDebt(
          customerId: customer.id,
          amountMinor: 1000000,
          date: DateTime(2026, 11, 4),
          currency: 'YER',
        );
        state.addDebt(
          customerId: customer.id,
          amountMinor: 200000,
          date: DateTime(2026, 11, 4),
          currency: 'SAR',
        );
        final chargeYer = state.merchantEntries.firstWhere(
          (entry) => entry.currency == 'YER',
        );
        final chargeSar = state.merchantEntries.firstWhere(
          (entry) => entry.currency == 'SAR',
        );
        state.approveEntry(chargeYer.id);
        state.approveEntry(chargeSar.id);

        addPendingEntry(
          state,
          LedgerEntry(
            id: 'payment-yer',
            customerId: customer.id,
            merchantId: AppState.merchantId,
            type: OperationType.payment,
            amountMinor: 1000000,
            currency: 'YER',
            status: TxStatus.pending,
            createdAt: DateTime(2026, 11, 4, 1),
          ),
        );
        addPendingEntry(
          state,
          LedgerEntry(
            id: 'allocation-yer',
            customerId: customer.id,
            merchantId: AppState.merchantId,
            type: OperationType.allocation,
            amountMinor: 1000000,
            currency: 'YER',
            status: TxStatus.pending,
            createdAt: DateTime(2026, 11, 4, 2),
          ),
        );
        state.approveEntry('payment-yer');
        state.approveEntry('allocation-yer');

        expect(state.customers.single.balanceFor('YER'), 0);
        expect(state.unappliedPaymentTotals(), isEmpty);

        addPendingEntry(
          state,
          LedgerEntry(
            id: 'reverse-allocation',
            customerId: customer.id,
            merchantId: AppState.merchantId,
            type: OperationType.reversal,
            amountMinor: 0,
            currency: 'YER',
            status: TxStatus.pending,
            createdAt: DateTime(2026, 11, 4, 3),
            originalOperationId: 'allocation-yer',
          ),
        );
        state.approveEntry('reverse-allocation');

        expect(state.customers.single.balanceFor('YER'), 1000000);
        expect(state.unappliedPaymentTotals(), {'YER': 1000000});

        addPendingEntry(
          state,
          LedgerEntry(
            id: 'reverse-payment',
            customerId: customer.id,
            merchantId: AppState.merchantId,
            type: OperationType.reversal,
            amountMinor: 0,
            currency: 'YER',
            status: TxStatus.pending,
            createdAt: DateTime(2026, 11, 4, 4),
            originalOperationId: 'payment-yer',
          ),
        );
        state.approveEntry('reverse-payment');

        expect(state.customers.single.balanceFor('YER'), 1000000);
        expect(state.unappliedPaymentTotals(), isEmpty);
        expect(state.customers.single.balanceFor('SAR'), 200000);

        addPendingEntry(
          state,
          LedgerEntry(
            id: 'reverse-charge',
            customerId: customer.id,
            merchantId: AppState.merchantId,
            type: OperationType.reversal,
            amountMinor: 0,
            currency: 'YER',
            status: TxStatus.pending,
            createdAt: DateTime(2026, 11, 4, 5),
            originalOperationId: chargeYer.id,
          ),
        );
        state.approveEntry('reverse-charge');

        expect(state.customers.single.balanceFor('YER'), 0);
        expect(state.customers.single.balanceFor('SAR'), 200000);
      },
    );

    test(
      'computes gross approved effects per currency without neutral payments',
      () {
        final state = AppState(seed: false);
        state.entries.addAll([
          LedgerEntry(
            id: 'charge-yer',
            customerId: 'c-1',
            merchantId: AppState.merchantId,
            type: OperationType.charge,
            amountMinor: 100000,
            currency: 'YER',
            status: TxStatus.approved,
            createdAt: DateTime(2026, 11, 4),
          ),
          LedgerEntry(
            id: 'payment-yer',
            customerId: 'c-1',
            merchantId: AppState.merchantId,
            type: OperationType.payment,
            amountMinor: 100000,
            currency: 'YER',
            status: TxStatus.approved,
            createdAt: DateTime(2026, 11, 4),
          ),
          LedgerEntry(
            id: 'allocation-yer',
            customerId: 'c-1',
            merchantId: AppState.merchantId,
            type: OperationType.allocation,
            amountMinor: 50000,
            currency: 'YER',
            status: TxStatus.approved,
            createdAt: DateTime(2026, 11, 4),
          ),
          LedgerEntry(
            id: 'charge-sar',
            customerId: 'c-1',
            merchantId: AppState.merchantId,
            type: OperationType.charge,
            amountMinor: 200000,
            currency: 'SAR',
            status: TxStatus.approved,
            createdAt: DateTime(2026, 11, 4),
          ),
        ]);

        expect(state.grossApprovedEffectByCurrency(), {
          'YER': 150000,
          'SAR': 200000,
        });
        expect(state.unappliedPaymentTotals(), {'YER': 50000});
      },
    );

    test('classifies operation effects using server ledger semantics', () {
      final state = AppState(seed: false);
      final original = LedgerEntry(
        id: 'original-charge',
        customerId: 'c-1',
        merchantId: AppState.merchantId,
        type: OperationType.charge,
        amountMinor: 500000,
        status: TxStatus.approved,
        createdAt: DateTime(2026, 11, 4),
      );
      state.entries.add(original);

      LedgerEntry entry(OperationType type, {int amountMinor = 100000}) {
        return LedgerEntry(
          id: 'entry-${type.name}',
          customerId: 'c-1',
          merchantId: AppState.merchantId,
          type: type,
          amountMinor: amountMinor,
          status: TxStatus.approved,
          createdAt: DateTime(2026, 11, 4),
        );
      }

      expect(
        state.effectOf(entry(OperationType.charge)),
        OperationEffect.increase,
      );
      expect(
        state.effectOf(entry(OperationType.payment)),
        OperationEffect.neutral,
      );
      expect(
        state.effectOf(entry(OperationType.salesReturn)),
        OperationEffect.decrease,
      );
      expect(
        state.effectOf(entry(OperationType.refund)),
        OperationEffect.increase,
      );
      expect(
        state.effectOf(entry(OperationType.allocation)),
        OperationEffect.decrease,
      );
      expect(
        state.effectOf(entry(OperationType.creditApplication)),
        OperationEffect.neutral,
      );
      expect(
        state.effectOf(entry(OperationType.supply)),
        OperationEffect.neutral,
      );

      final reversal = LedgerEntry(
        id: 'reversal-1',
        customerId: 'c-1',
        merchantId: AppState.merchantId,
        type: OperationType.reversal,
        amountMinor: 0,
        status: TxStatus.approved,
        createdAt: DateTime(2026, 11, 4),
        originalOperationId: original.id,
      );
      expect(state.effectOf(reversal), OperationEffect.decrease);
      expect(state.effectAmountOf(reversal), original.amountMinor);
      expect(state.signedEffectOf(reversal), -original.amountMinor);
    });

    test('separates pending amounts by currency, type and direction', () {
      final state = AppState(seed: false);
      LedgerEntry pending(
        String id,
        OperationType type,
        String currency,
        int amount,
      ) {
        return LedgerEntry(
          id: id,
          customerId: 'c-1',
          merchantId: AppState.merchantId,
          type: type,
          amountMinor: amount,
          currency: currency,
          status: TxStatus.pending,
          createdAt: DateTime(2026, 11, 4),
        );
      }

      state.entries.addAll([
        pending('charge-yer', OperationType.charge, 'YER', 100000),
        pending('refund-yer', OperationType.refund, 'YER', 20000),
        pending('return-yer', OperationType.salesReturn, 'YER', 30000),
        pending('payment-sar', OperationType.payment, 'SAR', 40000),
        pending('supply-usd', OperationType.supply, 'USD', 5000),
      ]);

      final lines = state.pendingBreakdown(state.entries);
      expect(lines, hasLength(5));
      expect(
        lines
            .where((line) => line.currency == 'YER')
            .fold<int>(0, (sum, line) => sum + line.signedAmountMinor),
        90000,
      );
      expect(state.pendingNetByCurrency(state.entries), {'YER': 90000});
      expect(
        lines.where((line) => line.effect == OperationEffect.neutral),
        hasLength(2),
      );
    });

    test('keeps independent credit limits per currency', () {
      final contact = Contact(
        id: 'c-1',
        name: 'عميل',
        phone: '+967700000000',
        kind: ContactKind.customer,
        balancesMinor: {'YER': 30000},
        pendingByCurrencyMinor: {'YER': 10000},
        creditLimitsMinor: {'YER': 100000, 'SAR': 50000},
      );

      expect(contact.creditLimitMinor, 100000);
      expect(contact.creditLimitFor('SAR'), 50000);
      expect(contact.availableFor('YER'), 60000);
      expect(contact.availableFor('SAR'), 50000);
      expect(contact.availableFor('USD'), 0);

      final updated = contact.copyWith(creditLimitMinor: 200000);
      expect(updated.creditLimitFor('YER'), 200000);
      expect(updated.creditLimitFor('SAR'), 50000);
    });

    test('keeps balances and pending amounts separate per currency', () {
      final state = AppState(seed: false);
      state.addCustomer(
        name: 'عميل تجريبي',
        phone: '+967 700 000 005',
        hasApp: true,
      );
      final customer = state.customers.single;

      state.addDebt(
        customerId: customer.id,
        amountMinor: 1000000,
        date: DateTime(2026, 11, 4),
        currency: 'YER',
      );
      state.addDebt(
        customerId: customer.id,
        amountMinor: 200000,
        date: DateTime(2026, 11, 4),
        currency: 'SAR',
      );

      expect(state.customers.single.pendingFor('YER'), 1000000);
      expect(state.customers.single.pendingFor('SAR'), 200000);
      expect(state.customers.single.pendingMinor, 1000000);

      final yerEntry = state.merchantEntries.firstWhere(
        (entry) => entry.currency == 'YER',
      );
      final sarEntry = state.merchantEntries.firstWhere(
        (entry) => entry.currency == 'SAR',
      );
      state.approveEntry(yerEntry.id);
      state.approveEntry(sarEntry.id);

      expect(state.customers.single.balanceFor('YER'), 1000000);
      expect(state.customers.single.balanceFor('SAR'), 200000);
      expect(state.customers.single.pendingFor('YER'), 0);
      expect(state.customers.single.pendingFor('SAR'), 0);
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
      expect(state.customers.single.balanceMinor, 0);
      expect(state.customers.single.pendingMinor, 2000000);
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

void addPendingEntry(AppState state, LedgerEntry entry) {
  state.entries.add(entry);
  final contact = state.contactById(entry.customerId);
  if (contact == null) return;
  final index = state.contacts.indexWhere((item) => item.id == contact.id);
  if (index == -1) return;
  final pending = Map<String, int>.from(contact.pendingByCurrencyMinor);
  final next = (pending[entry.currency] ?? 0) + state.signedEffectOf(entry);
  if (next == 0) {
    pending.remove(entry.currency);
  } else {
    pending[entry.currency] = next;
  }
  state.contacts[index] = contact.copyWith(pendingByCurrencyMinor: pending);
}
