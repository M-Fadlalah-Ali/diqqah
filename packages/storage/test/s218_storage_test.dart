import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// جذر المستودع: الاختبارات تعمل من packages/storage في CI ومحلياً
/// بعرف الدورة — فالصعود درجتين يصل المستودع (نمط core_shell_boundary).
Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    if (File('${dir.path}/worklog.md').existsSync()) return dir;
    dir = dir.parent;
  }
  fail('جذر المستودع غير موجود من ${Directory.current.path}');
}

/// س218 — علة b72 الحيّة بكلمة المالك «عند تشغيل النسخة 0.272 ظهر هذا
/// الخطأ: … Invalid argument in isolate message: object is unsendable —
/// dart:async _AsyncCompleter … (DQ-0999)». الجذر: توثيق drift حرفاً
/// (native.dart لسطري 141–145) أن دوال setup تُرسَل إلى عزل الخلفية
/// وتُنفَّذ هناك فلا يجوز أن تلتقط حالة غير مقصودة — وإغلاقُ الإعداد
/// المشفر المبني بنطاق المُصنعية كان يحمل سلسلة سياقه كاملة فسياقُ
/// الأب يلتقط كائن قاعدة البيانات ذاته (فيه LazyDatabase تسبيغه
/// _AsyncCompleter لا يُرسَل) فرفض Dart رسالة Isolate.spawn كلها لحظة
/// أول افتتاح — قبل فتح الملف إطلاقاً: البيانات سليمة والعللة حتمية.
///
/// الاختبارات تحرس العقد الجديد من ثلاثة وجوه: الفتح الفعلي عبر
/// المصنعية الإنتاجية بعزل الخلفية، وإرسال إغلاق الإعداد المشفر عبر
/// حدود عزل حقيقية (العلة ذاتها كانت ترمي هنا)، والحرس البنيوي الذي
/// يمنع عودة الإغلاق المضمّن بنطاق المُصنعية — والحد الصادق بنمط
/// م11/م18: الفتح الكامل للفرع المشفر ببيئة الاختبار بلا دمج MC
/// يرمي بحارس debug فلا يحكمه هذا الملف (توثيق drift يفصله).
void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('s218');
  });
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('س218: الفتح الفعلي عبر المصنعية الإنتاجية (الفرع النصي) بعزل '
      'الخلفية — إرسال رسالة الإقلاع يجري ولا يرمي unsendable والقاعدة '
      'تعمل وتغلق', () async {
    final dbPath = p.join(tmp.path, 's218-plain.db');
    final db = DiqqahDatabase(filePath: dbPath);
    addTearDown(db.close);
    // أول استعلام يجري الافتتاح فعلاً: LazyDatabase ثم
    // NativeDatabase.createInBackground ثم Isolate.spawn برسالة
    // _NativeIsolateStartup (بإغلاق الإعداد) — وهنا كان موضع رمي
    // علّة الإرسال لو عاد الإغلاق يحمل سياق المُصنعية.
    final rows = await db.customSelect('SELECT 1 AS one').get();
    expect(rows.single.data['one'], 1);
    // وإعادة الفتح على المسار ذاته آمنة التكرار (الفتح الحي الثاني).
    final db2 = DiqqahDatabase(filePath: dbPath);
    addTearDown(db2.close);
    expect((await db2.customSelect('SELECT 2 AS two').get())
        .single
        .data['two'], 2);
  });

  test('س218: إغلاق إعداد الفرع المشفر يعبُر حدود العزل بسلام — الجذر '
      'الجوهري لعلّة b72: الإغلاق المبني بنطاق المُصنعية كان يحمل بقاعدة '
      'البيانات فرفض الإرسال (object is unsendable - _AsyncCompleter)',
      () async {
    // الإغلاق ذاته الذي يمرره drift إلى عزل الخلفية بالفرع المشفر —
    // بنّاءة النطاق العلوي تلتقط المفتاح النصي حصراً (قيمة بسيطة
    // قابلة للإرسال) فلا سلسلة سياق نحو المُصنعية ولا كائن قاعدة.
    final setup = cipherSetupFor('aa' * kDbKeyBytes);
    // الإرسال الفعلي عبر عزل حقيقي — كان يرمي unsendable قبل الإصلاح —
    // والناتج هاش الإغلاق بالعزل الآخر دليل وصوله حياً (س218: تصويب
    // الجولة #438 — مسند عدم المساواة مع null يحذّر المحلل بلا معنى
    // فالإغلاق غير قابل للفراغ أصلاً).
    final crossedHash = await Isolate.run(() => setup.hashCode);
    expect(crossedHash, isA<int>(),
        reason: 'الإغلاق عبر العزل كاملاً بلا رفض إرسال (عقد س218)');
  });

  test('س218: توأم الاختبار fileSyncClose بالإغلاقات العلوية المشتركة — '
      'الفتح يعمل والبراغمات بنص الإنتاج ببنية الشيفرة', () async {
    final dbPath = p.join(tmp.path, 's218-twin.db');
    final db = DiqqahDatabase.fileSyncClose(filePath: dbPath);
    addTearDown(db.close);
    final rows = await db.customSelect('SELECT 7 AS seven').get();
    expect(rows.single.data['seven'], 7);
    expect(await File(dbPath).exists(), isTrue,
        reason: 'التوأم ملف حقيقي بمحرك متزامن (عقد س217 باقياً)');
  });

  test('س218: الحرس البنيوي — لا إغلاق setup مضمّن بنطاق المُصنعية '
      'والمصنعية تفوض البنّاءتين العلويتين (عقد قابلية الإرسال)', () {
    final src = File(
            '${_repoRoot().path}/packages/storage/lib/src/database.dart')
        .readAsStringSync();
    // المصنعية الإنتاجية تفوض البناء للبنّاءتين العلويتين حصراً.
    expect(src.contains('return _openPlainInBackground(filePath);'), isTrue,
        reason: 'الفرع النصي بالبنّاءة العلوية حصراً');
    expect(src.contains('return _openCipherInBackground(filePath, keyHex);'),
        isTrue,
        reason: 'الفرع المشفر بالبنّاءة العلوية حصراً');
    // ولا إغلاق setup مضمّن إطلاقاً — الإغلاق المبني بنطاق المُصنعية
    // يحمل سلسلة سياقه كاملة فترفضه حواجز العزل (علّة b72 الحيّة).
    final inline = RegExp(r'setup\s*:\s*\(').allMatches(src).toList();
    expect(inline, isEmpty,
        reason: 'عقد س218: كل إغلاق setup يُبنى نطاقاً علوياً — '
            'المواضع المخالفة: $inline');
    // والفرعان يستعملان الإغلاقَين العلويين المشتركين لا نسخاً يدوية
    // (التوأم والإنتاج بنص البراغمات ذاته ببنية الشيفرة).
    expect(src.contains('setup: _applyPlainPragmas'), isTrue);
    expect(src.contains('setup: cipherSetupFor(keyHex)'), isTrue);
  });
}
