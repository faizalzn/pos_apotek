import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/clock.dart';
import '../../../core/database/app_database.dart';
import '../../auth/data/user_repository.dart' show UserRuleException;

/// Kas masuk/keluar beserta nama pencatatnya.
class CashEntryView {
  const CashEntryView({required this.entry, required this.userName});
  final CashEntry entry;
  final String userName;

  int get signedAmount =>
      entry.type == CashEntryType.cashIn ? entry.amount : -entry.amount;
}

/// Ringkasan uang dalam satu shift.
class ShiftSummary {
  const ShiftSummary({
    required this.shift,
    required this.openedByName,
    required this.closedByName,
    required this.saleCount,
    required this.cashSales,
    required this.qrisSales,
    required this.voidCount,
    required this.refunds,
    required this.entries,
  });

  final Shift shift;
  final String openedByName;
  final String? closedByName;

  /// Transaksi selesai (tidak dibatalkan) dalam shift ini.
  final int saleCount;
  final int cashSales;
  final int qrisSales;

  /// Transaksi shift ini yang dibatalkan.
  final int voidCount;

  /// Uang tunai yang dikembalikan selama shift ini untuk transaksi dari shift
  /// lain yang dibatalkan.
  final int refunds;
  final List<CashEntryView> entries;

  bool get isOpen => shift.status == ShiftStatus.open;
  int get totalSales => cashSales + qrisSales;
  int get cashIn => entries
      .where((e) => e.entry.type == CashEntryType.cashIn)
      .fold(0, (s, e) => s + e.entry.amount);
  int get cashOut => entries
      .where((e) => e.entry.type == CashEntryType.cashOut)
      .fold(0, (s, e) => s + e.entry.amount);

  /// Uang yang seharusnya ada di laci sekarang (shift terbuka) atau saat
  /// ditutup (tersimpan).
  int get expectedCash =>
      shift.expectedCash ??
      shift.openingCash + cashSales + cashIn - cashOut - refunds;

  /// Hitungan − seharusnya. Positif = lebih, negatif = kurang.
  int? get difference =>
      shift.countedCash == null ? null : shift.countedCash! - expectedCash;
}

class ShiftService {
  ShiftService(this._db, this._now);

  final AppDatabase _db;
  final Clock _now;

  static const _uuid = Uuid();

  /// Shift yang sedang terbuka (paling banyak satu).
  Stream<Shift?> watchOpen() =>
      (_db.select(_db.shifts)
            ..where((s) => s.status.equalsValue(ShiftStatus.open))
            ..limit(1))
          .watchSingleOrNull();

  Future<Shift?> getOpen() =>
      (_db.select(_db.shifts)
            ..where((s) => s.status.equalsValue(ShiftStatus.open))
            ..limit(1))
          .getSingleOrNull();

  /// Uang laci saat shift terakhir ditutup — saran modal awal shift berikut.
  Future<int?> lastCountedCash() async {
    final last =
        await (_db.select(_db.shifts)
              ..where((s) => s.status.equalsValue(ShiftStatus.closed))
              ..orderBy([(s) => OrderingTerm.desc(s.closedAt)])
              ..limit(1))
            .getSingleOrNull();
    return last?.countedCash;
  }

  Future<Shift> open({required AppUser by, required int openingCash}) async {
    if (openingCash < 0) {
      throw const UserRuleException('Modal awal tidak boleh minus');
    }
    return _db.transaction(() async {
      final current = await getOpen();
      if (current != null) {
        throw const UserRuleException(
          'Masih ada shift yang terbuka. Tutup dulu sebelum membuka shift baru.',
        );
      }
      final now = _now();
      final shift = ShiftsCompanion.insert(
        id: _uuid.v4(),
        openedBy: by.id,
        openedAt: now,
        openingCash: openingCash,
        status: ShiftStatus.open,
        createdAt: now,
        updatedAt: now,
      );
      await _db.into(_db.shifts).insert(shift);
      return (_db.select(
        _db.shifts,
      )..where((s) => s.id.equals(shift.id.value))).getSingle();
    });
  }

  Future<void> addCashEntry({
    required CashEntryType type,
    required int amount,
    required String note,
    required AppUser by,
  }) async {
    if (amount <= 0) throw const UserRuleException('Jumlah harus lebih dari 0');
    if (note.trim().isEmpty) {
      throw const UserRuleException('Keterangan wajib diisi');
    }
    final shift = await getOpen();
    if (shift == null) {
      throw const UserRuleException('Belum ada shift yang dibuka');
    }
    final now = _now();
    if (type == CashEntryType.cashOut) {
      final available = (await summary(shift.id)).expectedCash;
      if (amount > available) {
        throw UserRuleException(
          'Uang di laci seharusnya hanya Rp$available, tidak cukup untuk dikeluarkan',
        );
      }
    }
    await _db
        .into(_db.cashEntries)
        .insert(
          CashEntriesCompanion.insert(
            id: _uuid.v4(),
            shiftId: shift.id,
            type: type,
            amount: amount,
            note: note.trim(),
            userId: by.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// Menutup shift: uang seharusnya dihitung & disimpan bersama hitungan kasir.
  Future<ShiftSummary> close({
    required String shiftId,
    required int countedCash,
    required AppUser by,
    String note = '',
  }) async {
    if (countedCash < 0) {
      throw const UserRuleException('Jumlah uang tidak boleh minus');
    }
    await _db.transaction(() async {
      final s = await summary(shiftId);
      if (!s.isOpen) throw const UserRuleException('Shift ini sudah ditutup');
      if (countedCash != s.expectedCash && note.trim().isEmpty) {
        throw const UserRuleException(
          'Ada selisih uang. Tulis keterangannya (mis. "kurang kembalian").',
        );
      }
      final now = _now();
      await (_db.update(_db.shifts)..where((x) => x.id.equals(shiftId))).write(
        ShiftsCompanion(
          status: const Value(ShiftStatus.closed),
          closedBy: Value(by.id),
          closedAt: Value(now),
          expectedCash: Value(s.expectedCash),
          countedCash: Value(countedCash),
          closingNote: Value(note.trim()),
          updatedAt: Value(now),
        ),
      );
    });
    return summary(shiftId);
  }

  Future<ShiftSummary> summary(String shiftId) async {
    final shift = await (_db.select(
      _db.shifts,
    )..where((s) => s.id.equals(shiftId))).getSingle();
    final end = shift.closedAt ?? _now();

    final totals = await _db
        .customSelect(
          '''
      SELECT
        COALESCE(SUM(CASE WHEN status = 'completed' AND payment_method = 'cash' THEN total END), 0) AS cash,
        COALESCE(SUM(CASE WHEN status = 'completed' AND payment_method = 'qris' THEN total END), 0) AS qris,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) AS done,
        COUNT(CASE WHEN status = 'voided' THEN 1 END) AS voided
      FROM sales WHERE shift_id = ?
      ''',
          variables: [Variable.withString(shiftId)],
          readsFrom: {_db.sales},
        )
        .getSingle();

    // Pembatalan transaksi tunai dari shift lain, terjadi selama shift ini.
    final refunds = await _db
        .customSelect(
          '''
      SELECT COALESCE(SUM(total), 0) AS refunds FROM sales
      WHERE status = 'voided' AND payment_method = 'cash'
        AND (shift_id IS NULL OR shift_id <> ?)
        AND voided_at >= ? AND voided_at <= ?
      ''',
          variables: [
            Variable.withString(shiftId),
            Variable.withDateTime(shift.openedAt),
            Variable.withDateTime(end),
          ],
          readsFrom: {_db.sales},
        )
        .getSingle();

    final entryRows =
        await (_db.select(_db.cashEntries).join([
                innerJoin(
                  _db.users,
                  _db.users.id.equalsExp(_db.cashEntries.userId),
                ),
              ])
              ..where(_db.cashEntries.shiftId.equals(shiftId))
              ..orderBy([OrderingTerm.asc(_db.cashEntries.createdAt)]))
            .get();

    Future<String?> nameOf(String? id) async => id == null
        ? null
        : (await (_db.select(
            _db.users,
          )..where((u) => u.id.equals(id))).getSingleOrNull())?.name;

    return ShiftSummary(
      shift: shift,
      openedByName: await nameOf(shift.openedBy) ?? '-',
      closedByName: await nameOf(shift.closedBy),
      saleCount: totals.read<int>('done'),
      cashSales: totals.read<int>('cash'),
      qrisSales: totals.read<int>('qris'),
      voidCount: totals.read<int>('voided'),
      refunds: refunds.read<int>('refunds'),
      entries: [
        for (final r in entryRows)
          CashEntryView(
            entry: r.readTable(_db.cashEntries),
            userName: r.readTable(_db.users).name,
          ),
      ],
    );
  }

  /// Ringkasan yang ikut berubah saat ada transaksi / kas masuk-keluar.
  Stream<ShiftSummary> watchSummary(String shiftId) async* {
    yield await summary(shiftId);
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([_db.sales, _db.cashEntries, _db.shifts]),
    )) {
      yield await summary(shiftId);
    }
  }

  /// Shift yang dibuka dalam rentang [from, to), terbaru lebih dulu.
  Future<List<ShiftSummary>> inRange(DateTime from, DateTime to) async {
    final shifts =
        await (_db.select(_db.shifts)
              ..where(
                (s) =>
                    s.openedAt.isBiggerOrEqualValue(from) &
                    s.openedAt.isSmallerThanValue(to),
              )
              ..orderBy([(s) => OrderingTerm.desc(s.openedAt)]))
            .get();
    return [for (final s in shifts) await summary(s.id)];
  }

  Stream<List<ShiftSummary>> watchRecent({int limit = 30}) async* {
    Future<List<ShiftSummary>> load() async {
      final shifts =
          await (_db.select(_db.shifts)
                ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
                ..limit(limit))
              .get();
      return [for (final s in shifts) await summary(s.id)];
    }

    yield await load();
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([_db.shifts, _db.cashEntries, _db.sales]),
    )) {
      yield await load();
    }
  }
}

final shiftServiceProvider = Provider<ShiftService>(
  (ref) => ShiftService(ref.watch(databaseProvider), ref.watch(clockProvider)),
);

final openShiftProvider = StreamProvider<Shift?>(
  (ref) => ref.watch(shiftServiceProvider).watchOpen(),
);

final shiftSummaryProvider = StreamProvider.family<ShiftSummary, String>(
  (ref, id) => ref.watch(shiftServiceProvider).watchSummary(id),
);

final recentShiftsProvider = StreamProvider<List<ShiftSummary>>(
  (ref) => ref.watch(shiftServiceProvider).watchRecent(),
);
