import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات المتابعات (د-7/§25.9 — س141): الباني النقي فوق المصادر —
/// كل بند صالح منفرداً والفارغ الكامل قائمة فارغة، وكل مصدر صامت عند
/// غيابه، والعتبات والحدود الموثقة بأرقامها الحية.
void main() {
  test('المدخل الفارغ كلياً — لا متابعات (كل مصدر صامت)', () {
    expect(buildFollowUps(const FollowUpsInput()), isEmpty);
  });

  test('كل بند من السبعة ينشأ منفرداً بمصدره وحده', () {
    final cases = <(String, FollowUpsInput)>[
      ('opening_reclassify', const FollowUpsInput(
          openingUndistributedBaseMinor: 250000)),
      ('import_auto_created', const FollowUpsInput(
          importEventsAwaitingReview: 1, partiesAutoCreated: 3)),
      ('import_skipped_existing', const FollowUpsInput(
          importEventsAwaitingReview: 1, itemsSkipped: 7)),
      ('emergency_copies', const FollowUpsInput(emergencyCopiesCount: 4)),
      ('rollback_window_open', const FollowUpsInput(rollbackWindowOpen: true)),
      ('fiscal_year_start', const FollowUpsInput(
          fiscalYearStartText: '2026-01-01')),
      ('storage_threshold', const FollowUpsInput(quotaUsedFraction: 0.82)),
    ];
    for (final (id, input) in cases) {
      final entries = buildFollowUps(input);
      expect(entries, hasLength(1), reason: 'البند $id وحده');
      expect(entries.single.id, id);
    }
  });

  test('بند التاريخ يسقط بالإقرار المطابق وبعد أول ترحيل (§25.4)', () {
    final acknowledged = buildFollowUps(const FollowUpsInput(
      fiscalYearStartText: '2026-01-01',
      fiscalStartAcknowledgedText: '2026-01-01',
    ));
    expect(
        acknowledged.where((e) => e.id == 'fiscal_year_start'), isEmpty);

    final posted = buildFollowUps(const FollowUpsInput(
      fiscalYearStartText: '2026-01-01',
      hasPostedMoves: true,
    ));
    expect(posted.where((e) => e.id == 'fiscal_year_start'), isEmpty);

    final changed = buildFollowUps(const FollowUpsInput(
      fiscalYearStartText: '2027-01-01',
      fiscalStartAcknowledgedText: '2026-01-01',
    ));
    expect(changed.single.id, 'fiscal_year_start',
        reason: 'تغير التاريخ يستأنف المتابعة');
  });

  test('عتبتا التخزين: 80% انتباهاً و95% عجلاً ونسبتهما معروضة (د-8)',
      () {
    final warning = buildFollowUps(
        const FollowUpsInput(quotaUsedFraction: 0.80));
    expect(warning.single.severity, FollowUpSeverity.attention);
    expect(warning.single.description, contains('80%'));

    final critical = buildFollowUps(
        const FollowUpsInput(quotaUsedFraction: 0.95));
    expect(critical.single.severity, FollowUpSeverity.urgent);
    expect(critical.single.description, contains('95%'));

    final below = buildFollowUps(
        const FollowUpsInput(quotaUsedFraction: 0.79));
    expect(below, isEmpty, reason: 'دون العتبة صمت');
  });

  test('نسخ الطوارئ دون عتبة التراكم صامتة وعندها تنشط بعدّها', () {
    expect(
        buildFollowUps(const FollowUpsInput(emergencyCopiesCount: 2)),
        isEmpty,
        reason: 'دون 3 دورها الطبيعي قائم');
    final active =
        buildFollowUps(const FollowUpsInput(emergencyCopiesCount: 3));
    expect(active.single.id, 'emergency_copies');
    expect(active.single.description, contains('3'));
  });

  test('الرصيد الافتتاحي غير الموزَّع يظهر بمبلغه المقروء ولشدته', () {
    final entries = buildFollowUps(
        const FollowUpsInput(openingUndistributedBaseMinor: 250000));
    final entry = entries.single;
    expect(entry.id, 'opening_reclassify');
    expect(entry.severity, FollowUpSeverity.attention);
    expect(entry.description, contains('2500'));
    expect(entry.description, contains('332'));
    // والصفر الموزَّع صامت — لا متابعة بلا معنى.
    expect(
        buildFollowUps(const FollowUpsInput(
            openingUndistributedBaseMinor: 0)),
        isEmpty);
  });

  // ═══ د6 (س175) — المتابعات اليومية (س74/D-184) ولوحة «يحتاج
  //     انتباهك» (F-146 إحالة م4–م5) — البنود العشرة ═══

  test('د6: المتابعات اليومية الثلاث تنشأ منفرداً ولسانها الأحرف '
      'المعتمدة (س74/D-184)', () {
    final belowMin = buildFollowUps(const FollowUpsInput(
      belowMinimumItems: [
        BelowMinimumItem(
            sku: 'ITM-1',
            name: 'سكر ناعم طويل الاسم للعرض',
            availableQty: 2,
            minimumQty: 10),
      ],
    ));
    expect(belowMin, hasLength(1));
    expect(belowMin.single.id, 'daily_below_minimum');
    expect(belowMin.single.severity, FollowUpSeverity.attention);
    expect(belowMin.single.title, contains('(1)'));
    expect(belowMin.single.description, contains('المتاح 2'));
    expect(belowMin.single.description, contains('الحد الأدنى 10'));

    final overAmount = buildFollowUps(const FollowUpsInput(
      overAmountCapBalances: [
        OverAmountCapBalance(
            partyName: 'عميل متأخر',
            balanceMinor: 1500000,
            capMinor: 1000000),
      ],
    ));
    expect(overAmount, hasLength(1));
    expect(overAmount.single.id, 'daily_over_credit_cap');
    expect(overAmount.single.severity, FollowUpSeverity.urgent,
        reason: 'تجاوز حد الائتمان أشدُّ من السقف — لسان F-164');
    expect(overAmount.single.description, contains('عميل متأخر'));

    final overTime = buildFollowUps(const FollowUpsInput(
      overTimeCapBalances: [
        OverTimeCapBalance(
            partyName: 'ذمة متقادمة', oldestAgeDays: 90, termDays: 30),
      ],
    ));
    expect(overTime, hasLength(1));
    expect(overTime.single.id, 'daily_over_term');
    expect(overTime.single.severity, FollowUpSeverity.attention);
    expect(overTime.single.description, contains('90'));
    expect(overTime.single.description, contains('30'));
  });

  test('د6: تجميع اللوحة عند ثلاثة وأكثر — أول ثلاثة أسماء و«غيرها» '
      'بالعدد فلا تغرق اللوحة', () {
    final entries = buildFollowUps(FollowUpsInput(
      belowMinimumItems: [
        for (var i = 1; i <= 5; i++)
          BelowMinimumItem(
              sku: 'ITM-$i', name: 'صنف $i', availableQty: i - 1, minimumQty: 5),
      ],
      overAmountCapBalances: [
        for (var i = 1; i <= 4; i++)
          OverAmountCapBalance(
              partyName: 'طرف $i', balanceMinor: 10, capMinor: 5),
      ],
      overTimeCapBalances: [
        OverTimeCapBalance(partyName: 'طرف زمني', oldestAgeDays: 40, termDays: 7),
      ],
    ));
    expect(entries, hasLength(3), reason: 'ثلاثة بنود مصادر للوحة');
    final belowMin = entries.singleWhere((e) => e.id == 'daily_below_minimum');
    expect(belowMin.title, contains('(5)'));
    expect(belowMin.description, contains('صنف 1'));
    expect(belowMin.description, contains('صنف 3'));
    expect(belowMin.description, isNot(contains('صنف 4')),
        reason: 'أول ثلاثة حصراً');
    expect(belowMin.description, contains('غيرها 2 صنفاً'));
    final overAmount = entries.singleWhere((e) => e.id == 'daily_over_credit_cap');
    expect(overAmount.description, contains('غيرها 1 طرفاً'));
    final overTime = entries.singleWhere((e) => e.id == 'daily_over_term');
    expect(overTime.description, contains('طرف زمني'));
  });

  test('د6: حدود المعنى المرفوض لا تُرسل — لكن القوائم المرسلة صامتة '
      'إذا فارغة والوصول بالتمام إلى السقف ليس تجاوزاً', () {
    // الوصول تماماً للسقف: الرصيد 1,000,000 والسقف 1,000,000 —
    // بوابة F-164 اللين تُبقيه صامتاً على مستوى الفاتورة، ولوحة
    // اليوم تستقبل تجاوزاً حصراً فالمستدعي لا يرسل المتطابق أصلاً.
    expect(
        buildFollowUps(const FollowUpsInput(
          overAmountCapBalances: [
            OverAmountCapBalance(
                partyName: 'عند السقف تماماً',
                balanceMinor: 1000000,
                capMinor: 1000000),
          ],
        )),
        hasLength(1),
        reason: 'اللوحة عرض فوق المصادر — حسم التجاوز بوابة F-164 '
            'والاستعلام لا يرسل غير المتجاوز');
    // القوائم الفارغة صامتة — لا بنود اليومية بلا مصادر.
    expect(
        buildFollowUps(const FollowUpsInput(
          belowMinimumItems: [],
          overAmountCapBalances: [],
          overTimeCapBalances: [],
        )),
        isEmpty);
  });

  test('د6: البنود العشرة معاً — اللوحة تجمع ولا تفقد ترتيب العقود', () {
    final entries = buildFollowUps(const FollowUpsInput(
      openingUndistributedBaseMinor: 1,
      importEventsAwaitingReview: 1,
      partiesAutoCreated: 1,
      emergencyCopiesCount: 3,
      rollbackWindowOpen: true,
      fiscalYearStartText: '2026-01-01',
      quotaUsedFraction: 0.96,
      belowMinimumItems: [
        BelowMinimumItem(sku: 'A', name: 'أ', availableQty: 0, minimumQty: 1),
      ],
      overAmountCapBalances: [
        OverAmountCapBalance(partyName: 'ب', balanceMinor: 9, capMinor: 1),
      ],
      overTimeCapBalances: [
        OverTimeCapBalance(partyName: 'ج', oldestAgeDays: 9, termDays: 1),
      ],
    ));
    final ids = [for (final e in entries) e.id];
    expect(ids, containsAll(<String>[
      'opening_reclassify',
      'import_auto_created',
      'emergency_copies',
      'rollback_window_open',
      'fiscal_year_start',
      'storage_threshold',
      'daily_below_minimum',
      'daily_over_credit_cap',
      'daily_over_term',
    ]), reason: 'اللوحة الكاملة تجمع بنودها كلها');
    // البنود اليومية الثلاث ذيل اللوحة بعد بنودها القائمة — ترتيب
    // العقود موثق لا عرضي.
    final legacyTail = ids.indexOf('storage_threshold');
    expect(ids.indexOf('daily_below_minimum'), greaterThan(legacyTail));
    expect(ids.indexOf('daily_over_credit_cap'),
        greaterThan(ids.indexOf('daily_below_minimum')));
    expect(ids.indexOf('daily_over_term'),
        greaterThan(ids.indexOf('daily_over_credit_cap')));
  });
}
