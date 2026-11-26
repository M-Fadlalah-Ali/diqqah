import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/parties_screen.dart';
import 'package:diqqah_app/items_screen.dart';
import 'package:diqqah_app/roles_screen.dart';
import 'package:diqqah_app/boxes_screen.dart';
import 'test_guard.dart';

/// دخان RTL وطول النص — س167 بقرار المالك الحرفي «أوافق على اقتراحك
/// بالنسبة للاختبارات» (من نقاش الاختبارات المقترح: «أسماء عربية
/// طويلة جداً وأرقام عريضة على البطاقات الرئيسية، يصادق عدم الفيض
/// (overflow) — رخيص، ويحمي ما يراه المالك يومياً بعينه»).
///
/// الحزام هو حزام التطبيق ذاته (س-135/D-129): locale عربي بمفوضات
/// الجاهزية الثلاث فيصير كل العرض من اليمين كما يرى المالك. العقد:
/// أسماء أطراف وأصناف تتجاوز 100 حرفاً وأسعار بملايين الوحدات الصغرى
/// تُضخّ على الشاشات الأربع الرئيسية فلا يظهر أي خطأ — والفيض
/// (RenderFlex overflow) في بيئة الاختبار يبلغ FlutterError فيفشل
/// الاختبار آلياً، فصمتُ الجولة هنا هو الفيضُ الذي لم يقع.
///
/// نمط القاعدة `inMemorySyncClose` حصراً وبضخّات محدودة لا
/// pumpAndSettle — عرف parties_screen_test الموثق (مؤشر الانتظار
/// يظل يتحرك حتى يصدر التدفق فلا تستقر pumpAndSettle قبله أبداً).
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  // مؤشر الكتابة الوامض مصدر إطارات لا نهائية لأي ضخّ غير محدود.
  EditableText.debugDeterministicCursor = true;

  /// حزام RTL نفسه حزام DiqqahApp حرفاً — لا بديل أخف ولا أثقل.
  Widget rtlHarness(Widget child) => MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      );

  /// الأسماء المبالغ فيها عمداً — كل اسم يتجاوز 100 حرفاً.
  const longPartyName =
      'شركة النور للتجارة العامة والمقاولات والمشاريع الإنشائية الكبرى '
      'المحدودة المساهمة المملوكة للورثة والشركاء بأمانة';
  const longPartyName2 =
      'مؤسسة الفجر الحديثة لاستيراد وتوزيع المواد الغذائية والتوابل '
      'والحبوب والبقوليات بجميع فروعها الإقليمية والولائية';
  const longItemName =
      'برتقال أبو سرة المستورد من الأحواض الساحلية الممتاز درجة أولى '
      'منعّأ ومغلف للجملة بالصناديق الكرتونية الكبيرة';
  const longItemName2 =
      'بطاطس حمراء محلية من محصول الخريف الجديد مفرزات يدوية ممتازة '
      'معبأة بأكياس الشباك الهوائية للأسواق اليومية';

  Future<DiqqahDatabase> seedExtreme() async {
    final db = DiqqahDatabase.inMemorySyncClose();
    await db.insertParty(
        number: '0001', name: longPartyName, kind: 'customer', defaultCurrencyId: 1);
    await db.insertParty(
        number: '0002',
        name: longPartyName2,
        kind: 'supplier',
        defaultCurrencyId: 1);
    final unitId = await db.insertUnit(name: 'كيلوغرام');
    // أسعار بملايين الوحدات الصغرى — الأرقام العريضة التي تكسر البطاقات.
    await db.insertItem(
        sku: 'A-0001',
        name: longItemName,
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 999999999,
        salePriceMinor: 999999999,
        priceCurrencyId: 1);
    await db.insertItem(
        sku: 'A-0002',
        name: longItemName2,
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 750000000,
        salePriceMinor: 899999999,
        priceCurrencyId: 1);
    return db;
  }

  testWidgets('شاشة الأطراف بأسماء تتجاوز المئة حرفاً — لا فيض ولا '
      'انكسار، والاسم كاملُه محفوظ ومعروض', (tester) async {
    final db = await seedExtreme();
    addTearDown(db.close);

    await tester.pumpWidget(rtlHarness(PartiesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull,
        reason: 'الأسماء المبالغة لا تفيض بمحاور العرض');
    expect(find.textContaining('شركة النور للتجارة العامة'), findsOneWidget);
    expect(find.textContaining('مؤسسة الفجر الحديثة'), findsOneWidget);
    // الاتجاه العربي الموحد موروث من الحزام نفسه (س-135/D-129) —
    // فالعقد هنا صمتُ الفيض وظهور الأسماء لا قياس هندسة القوائم.
  });

  testWidgets('شاشة الأصناف بأسماء طويلة وأسعار بمئات الملايين من '
      'الوحدة الصغرى — لا فيض في البطاقات ولا في البحث', (tester) async {
    final db = await seedExtreme();
    addTearDown(db.close);

    await tester.pumpWidget(rtlHarness(ItemsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull,
        reason: 'الأصناف المبالغة لا تفيض');
    expect(find.textContaining('برتقال أبو سرة المستورد'), findsOneWidget);

    // البحث بكلمة وسط الاسم الطويل يعمل ويعرض النتيجة بلا فيض.
    await tester.enterText(find.byType(TextField).first, 'بطاطس');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: 'البحث لا يفيض');
    expect(find.textContaining('بطاطس حمراء محلية'), findsOneWidget);
  });

  testWidgets('شاشة الصلاحيات بأدوارها الافتراضية الخمسة وبوابتها '
      'الفرعية — لسان عربي طويل بشبكة الوحدات لا يفيض', (tester) async {
    final db = await seedExtreme();
    addTearDown(db.close);

    await tester.pumpWidget(rtlHarness(RolesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull,
        reason: 'شبكة الوحدات بالأدوار لا تفيض');
    expect(find.textContaining('محاسب'), findsWidgets);
    expect(find.textContaining('أمين مستودع'), findsWidgets);
    expect(find.textContaining('مندوب'), findsWidgets);
  });

  testWidgets('شاشة الصناديق بتقريرها المالي — أرقام وصيغ بالاتجاه '
      'العربي لا تفيض على البطاقة الرئيسية', (tester) async {
    final db = await seedExtreme();
    addTearDown(db.close);

    await tester.pumpWidget(rtlHarness(BoxesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull,
        reason: 'بطاقات الصناديق لا تفيض');
  });
}
