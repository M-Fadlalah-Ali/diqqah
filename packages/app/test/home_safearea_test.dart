import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/home_screen.dart';

import 'test_guard.dart';

/// س138 (تكليف المالك 2026-11-14): سطر «الجلسة» أسفل الهيكلية كان خلف
/// شريط التنقل السفلي بأندرويد — الرسم الحافي يمدُّ الجسم تحت حزام
/// النظام بلا حزام واجهة — فأصلحه SafeArea سفلية على جسم الرئيسية.
///
/// **س203 (م6 صقل M3 بأمر المالك «تابع إلى ب60»)**: صاحب الجلسة انتقل
/// إلى شريط العنوان أعلى الهيكلية (`AppBar.actions`) لا أسفلها — فالمعلومة
/// أول ما تُرى والأسفل هادئ، والحزام السفلي على الجسم باقٍ لآخر أسطر
/// القائمة المسحوبة.
///
/// الاختبار يحكم الموضعين الجديدين: صاحب الجلسة بلسانه «الاسم (الدور)»
/// داخل `AppBar` حصراً — وسطر «الجلسة: » القديم أسفل الهيكلية زال لا
/// يظهر مكانين.
///
/// ضخّات محدودة لا pumpAndSettle (درس س22..س26 الموثق).
void main() {
  installTestTimeoutGuard();

  testWidgets('صاحب الجلسة بشريط العنوان أعلى الهيكلية — '
      'انتقال س203 م6 عن س138', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    // مدير حي حتى يظهر صاحب الجلسة أصلاً — createManager لا يثبت
    // الحالي فتثبيت الجلسة بعده صراحة (نمط س101).
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 'test-hash');
    await db.setCurrentUserId(managerId);

    // نافذة أندرويد بحزام نظام سفلي 24 بكسل — الرسم الحافي: viewPadding
    // والpadding سويّاً (لا لوحة مفاتيح فviewInsets صفر).
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: 24),
          viewPadding: EdgeInsets.only(bottom: 24),
        ),
        child: HomeScreen(db: db, dbPath: ':memory:', onRestored: () {}),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // صاحب الجلسة «المالك (مدير)» داخل شريط العنوان حصراً — النقل
    // من أسفل الهيكلية إلى AppBar (س203 م6).
    final ownerInAppBar = find.descendant(
      of: find.byType(AppBar),
      matching: find.textContaining('المالك'),
    );
    expect(ownerInAppBar, findsOneWidget,
        reason: 'صاحب الجلسة أعلى الهيكلية بشريط العنوان');

    // وسطر «الجلسة: » القديم أسفل الهيكلية زال — لا موضعان لهوية واحدة.
    expect(find.textContaining('الجلسة: '), findsNothing,
        reason: 'الانتقال كامل لا تراكم');
  });
}
