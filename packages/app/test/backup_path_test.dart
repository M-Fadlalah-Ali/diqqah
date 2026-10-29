// فحص نقي لاختيار مسار النسخة الحرة — علّة CI #40/#41 (2026-10-29):
// نسختان في نفس الثانية كان اسمهما واحداً (الختم بدقة الثانية وD-061
// بلاحقة موحدة) فتدمّر الأولى بإعادة الكتابة فوقها بصمت. الدالة نقية
// والوجود يُحاكى بمجموعة أسماء — لا نظام ملفات ولا Flutter، والتوقعات
// مبنية بـ p.join نفسها فتسلم على أي منصة.
import 'package:diqqah_app/settings_screen.dart' show freeBackupPath;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const dir = '/tmp/diqqah_bpath_t';
  const stamp = '20261029-125044';

  test('اسم حر أول: الصيغة الاعتيادية بلا لاحقة ترقيم', () {
    final taken = <String>{};
    final path = freeBackupPath(dir, stamp, taken.contains);
    expect(path, p.join(dir, 'diqqah-backup-$stamp.diqqah'));
  });

  test('تصادم نفس الثانية: لاحقة -2 تفرد الاسم ولا تلمس السابقة', () {
    final taken = {p.join(dir, 'diqqah-backup-$stamp.diqqah')};
    final path = freeBackupPath(dir, stamp, taken.contains);
    expect(path, p.join(dir, 'diqqah-backup-$stamp-2.diqqah'));
  });

  test('سلسلة تصادمات: -3 تلي -2 بلا سقف', () {
    final taken = {
      p.join(dir, 'diqqah-backup-$stamp.diqqah'),
      p.join(dir, 'diqqah-backup-$stamp-2.diqqah'),
    };
    final path = freeBackupPath(dir, stamp, taken.contains);
    expect(path, p.join(dir, 'diqqah-backup-$stamp-3.diqqah'));
  });

  test('أختام مختلفة لا تتداخل: لكل ختم مساره الخاص', () {
    final taken = {p.join(dir, 'diqqah-backup-$stamp.diqqah')};
    final path = freeBackupPath(dir, '20261029-125045', taken.contains);
    expect(path, p.join(dir, 'diqqah-backup-20261029-125045.diqqah'));
  });
}
