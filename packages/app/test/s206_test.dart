import 'dart:io' show Directory;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/item_images.dart';
import 'package:diqqah_app/items_screen.dart';
import 'package:diqqah_app/orders_screen.dart';
import 'package:diqqah_app/parties_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات دفعة س206 — ختام فحص الواجهات وفق M3 بأمر المالك
/// «تابع النطاق 11 - 18»: م11 آخر باقٍ حي من طابور توحيد المكونات
/// الموثق بس198 (بحث الأطراف بنصه الإرشادي الوحيد وباركود نموذج
/// الصنف بإطاره المحدد) وم18 إقفال الصقل (المحاذاة الفيزيائية
/// الثلاثة بأوامر الشاشة — طابور م14 الموثق بس198).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا
/// pumpAndSettle (درس س22..س26) — والوصول بالتمرير لا الافتراض
/// (درس D-098) — والصعود إلى الزر قبل Align غلافه (درس الجولة #381).
void main() {
  // المهلة الحارسة قبل أي تسجيل اختبار — dart_test.yaml لا يسري على
  // testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  // مؤشر الكتابة الوامض يجعل pumpAndSettle تدور إلى مهلتها (علّة CI
  // 2026-10-29) — التثبيت التجريبي للمؤشر يقضي على المصدر.
  EditableText.debugDeterministicCursor = true;

  /// IO متزامن حصراً — createTemp غير المتزامن داخل الزمن الوهمي لا
  /// يكتمل أبداً فعلِقت به سبعة اختبارات 10 دقائق (الجولة 128).
  Directory useTempImagesRoot() {
    final root = Directory.systemTemp.createTempSync('diqqah_s206_');
    ItemImagesStore.root = root.path;
    return root;
  }

  Future<Item> itemBySku(DiqqahDatabase db, String sku) async {
    return (db.select(db.items)..where((t) => t.sku.equals(sku)))
        .getSingle();
  }

  Future<void> scrollToText(WidgetTester tester, String text) async {
    for (var i = 0; i < 14 && find.text(text).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -260));
      await tester.pump();
    }
    final f = find.text(text);
    if (f.evaluate().isNotEmpty) {
      await tester.ensureVisible(f.last);
      await tester.pump();
    }
  }

  testWidgets('م11/س206: بحث الأطراف بعنوانه الدائم على نمط العائلة '
      'الممتلئة — بلا إطار محدد ولا نص إرشادي وحيد', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: PartiesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الحقل الأول بشاشة الأطراف هو حقل البحث الوحيد بجسمها (نموذج
    // الطرف حوار لا يُفتح إلا بضغطة «إضافة طرف»).
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.decoration!.labelText, 'بحث بالاسم أو الرقم أو الهاتف',
        reason: 'م11: العنوان الدائم بنفس اللسان الموثق حرفاً');
    expect(field.decoration!.hintText, isNull,
        reason: 'م11: لا نص إرشادي وحيد بعد التوحيد — نمط م13');
    expect(field.decoration!.border, isNot(isA<OutlineInputBorder>()),
        reason: 'م11: نزع الإطار المحدد بنمط العائلة الممتلئة الافتراضي');
    expect(field.decoration!.prefixIcon, isA<Icon>(),
        reason: 'م11: أيقونة البحث المسبقة باقية كما هي');
  });

  testWidgets('م11/س206: باركود نموذج الصنف على العائلة الممتلئة — '
      'الإطار المزال والعنوان الدائم والإرشاد الثانوي الباقي',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    useTempImagesRoot();

    final oil = await itemBySku(db, 'Z-100');
    await tester.pumpWidget(
        MaterialApp(home: ItemEditScreen(db: db, existing: oil)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الخانة أسفل الطيّة فتُمرر أولاً (درس السرد الكسول — نمط batch10).
    await scrollToText(tester, 'رمز الباركود');
    await tester.pump(const Duration(milliseconds: 100));

    final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'رمز الباركود'));
    expect(field.decoration!.labelText, 'رمز الباركود',
        reason: 'م11: العنوان الدائم باقٍ');
    expect(field.decoration!.hintText, 'اكتب الرمز أو امسحه ثم أضف',
        reason: 'م11: الإرشاد الثانوي باقٍ — لم يكن وحيداً ليُنزع');
    expect(field.decoration!.border, isNot(isA<OutlineInputBorder>()),
        reason: 'م11: الإطار المحدد مُزال بنمط العائلة الممتلئة');
    // زر المسح بالكاميرا بذاته شرطه Platform.isAndroid فغائب بالفحص
    // المكتبي (عرف الدفعة الموثق batch10) — فلا توقع عليه هنا.
  });

  testWidgets('م18/س206: أوامر الشاشة الثلاثة كله اتجاهية — المكافئ '
      'وقيمة السطر وإضافة البند لبداية السطر العربية دومًا', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(
        home: OrderEditScreen(db: db, direction: OrderDirection.sale)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // دورة س123-2 حرفاً: الطرف أولاً بأهليته ثم الصنف فتظهر بطاقة
    // السطر بعناصرها الثانوية الثلاثة.
    await tester.tap(find.text('الزبون'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('0001 عميل الأمل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('Z-100 زيت محلي').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // الوصول بالتمرير لا الافتراض (درس D-098): البطاقة أسفل النموذج
    // الكسول قد تكون خارج مدى البناء عند الجدول الأول.
    await scrollToText(tester, 'المكافئ بالأساسية');
    final baseAlign = find.ancestor(
        of: find.textContaining('المكافئ بالأساسية'),
        matching: find.byType(Align)).first;
    expect(tester.widget<Align>(baseAlign).alignment,
        AlignmentDirectional.centerStart,
        reason: 'م18: المكافئ بالأساسية اتجاهي (طابور م14 الموثق)');

    final valueAlign = find.ancestor(
        of: find.textContaining('قيمة السطر المرجعية'),
        matching: find.byType(Align)).first;
    expect(tester.widget<Align>(valueAlign).alignment,
        AlignmentDirectional.centerStart,
        reason: 'م18: قيمة السطر المرجعية اتجاهية');

    // درس الجولة #381: الصعود إلى الزر أولاً (فالزر الداخلي يغلف نصه
    // بـAlign نمطه) ثم أول Align فوقه وهو غلافنا الاتجاهي.
    final addBtn = find.ancestor(
        of: find.text('إضافة بند'),
        matching: find.byWidgetPredicate((w) => w is TextButton)).first;
    final addAlign =
        find.ancestor(of: addBtn, matching: find.byType(Align)).first;
    expect(tester.widget<Align>(addAlign).alignment,
        AlignmentDirectional.centerStart,
        reason: 'م18: إضافة البند اتجاهية بنمط م14 حرفاً');
  });
}
