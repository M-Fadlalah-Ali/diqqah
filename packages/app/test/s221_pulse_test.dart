import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/main.dart';
import 'package:diqqah_app/follow_ups_screen.dart';

/// جذر المستودع: الاختبارات تعمل من packages/app في CI ومحلياً
/// بعرف الدورة — فالصعود درجتين يصل المستودع (نمط s218/s219).
Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    if (File('${dir.path}/worklog.md').existsSync()) return dir;
    dir = dir.parent;
  }
  fail('جذر المستودع غير موجود من ${Directory.current.path}');
}

/// س221 — دفعة اتساق نبض العمل بأمر المالك («ابدأ بتنفيذ الدفعات
/// الخمسة بالتسلسل الذي عرضته» — دفعة نبض العمل والتنقل):
///
/// 1. قرار المالك الموثق: «أفضل قسماً واحداً فقط وهو نبض العمل» —
///    الشريط الأحمر للمتابعات أُزيل من لافتات الرئيسية فنبض العمل
///    هو المصدر الواحد لمتابعات الإدارة (لا ازدواج ولا لسان متكرر).
/// 2. قرار المالك الموثق: «التصميم يوحي بأن كل واحدة من هذه الأمور
///    الثلاثة مستقلة عن الأخرى» — فكل بطاقة نبض وجهها الحقيقي:
///    الأصناف بشاشة الأصناف والذمم بشاشة الذمم فلا بطاقة ميتة النقر.
/// 3. علاج خطأ المسار الموثق بلسان المالك: زرّا «أصناف المخزون»
///    و«أعمار الذمم» بشاشة المتابعات كانا يفتحان استيراد البيانات
///    بسقوطهما في default — فوجّها المدخلات اليومية الثلاثة إلى
///    شاشات مصادرها الحقيقية.
void main() {
  test('س221: الحرس البنيوي — بند المتابعات الأحمر لا أثر له '
      'والبطاقات الثلاث بأفعالها والوجهات اليومية بموضعها', () {
    final home = File(
            '${_repoRoot().path}/packages/app/lib/home_screen.dart')
        .readAsStringSync();
    expect(home.contains('int followUpsCount'), isFalse,
        reason: 'باراميتر بند اللافتة المزال لا أثر له');
    expect(home.contains('HomeAlertAction.followUps'), isFalse,
        reason: 'قيمة الفعل المزالة لا أثر لها');
    expect(home.contains('افتح المتابعات'), isFalse,
        reason: 'لسان البند المزال لا أثر له');
    expect(home.contains('_openItems'), isTrue,
        reason: 'وجه بطاقة الأصناف: شاشة الأصناف');
    expect(home.contains('_openReceivables'), isTrue,
        reason: 'وجه بطاقتا الذمم: شاشة الذمم');

    final follow = File(
            '${_repoRoot().path}/packages/app/lib/follow_ups_screen.dart')
        .readAsStringSync();
    expect(follow.contains("case 'daily_below_minimum':"), isTrue,
        reason: 'المدخل اليومي الأول بوجهه الصريح');
    expect(follow.contains("case 'daily_over_credit_cap':"), isTrue,
        reason: 'المدخل اليومي الثاني بوجهه الصريح');
    expect(follow.contains("case 'daily_over_term':"), isTrue,
        reason: 'المدخل اليومي الثالث بوجهه الصريح');
    expect(follow.contains('onOpenItems'), isTrue);
    expect(follow.contains('onOpenReceivables'), isTrue);
  });

  Future<void> _seedBelowMinimum(DiqqahDatabase db) async {
    final unitId = await db.insertUnit(name: 'قطعة');
    await db.insertItem(
      sku: 'N-1',
      name: 'صنف تحت الحد س221',
      kind: 'good',
      baseUnitId: unitId,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
      minQty: 5,
    );
  }

  testWidgets('س221: بطاقة نبض الأصناف تفتح شاشة الأصناف المصدر — '
      'استقلال البطاقات بقرار المالك فلا ميت النقر', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await _seedBelowMinimum(db);

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    expect(find.text('أصناف تحت الحد الأدنى'), findsOneWidget,
        reason: 'البطاقة بالوجود (مصنف تحت حد والد اللقطة)');
    await tester.tap(find.text('أصناف تحت الحد الأدنى'));
    await tester.pumpAndSettle();

    // شاشة الأصناف بألسنتها القائمة (بحث م13 الموثق) — لا شاشة أخرى.
    expect(find.textContaining('بحث بالاسم'), findsOneWidget,
        reason: 'وجه البطاقة شاشة الأصناف المصدر');
  });

  testWidgets('س221: أزرار المدخلات اليومية بوجهها الحقيقي — الأصناف '
      'بشاشتها والذمم بشاشتها لا الاستيراد', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    var itemsOpened = 0;
    var receivablesOpened = 0;
    const snapshot = FollowUpsSnapshot(
      FollowUpsInput(),
      [
        FollowUpEntry(
          id: 'daily_below_minimum',
          severity: FollowUpSeverity.attention,
          title: 'أصناف تحت الحد الأدنى',
          description: 'صنف تجريبي دون حد الأدنى',
          actionLabel: 'أصناف المخزون',
        ),
        FollowUpEntry(
          id: 'daily_over_term',
          severity: FollowUpSeverity.attention,
          title: 'أطراف تجاوزت مدة السداد',
          description: 'طرف تجريبي تجاوز المدة',
          actionLabel: 'أعمار الذمم',
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: FollowUpsScreen(
        db: db,
        loadOverride: () async => snapshot,
        onOpenItems: () => itemsOpened++,
        onOpenReceivables: () => receivablesOpened++,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('أصناف المخزون'));
    await tester.pump();
    await tester.tap(find.text('أعمار الذمم'));
    await tester.pump();

    expect(itemsOpened, 1,
        reason: 'وجهه شاشة الأصناف لا الاستيراد (علاج خطأ المسار)');
    expect(receivablesOpened, 1,
        reason: 'وجهه شاشة الذمم لا الاستيراد (علاج خطأ المسار)');
  });
}
