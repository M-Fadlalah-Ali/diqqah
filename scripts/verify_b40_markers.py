#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتي b40 — دِقّة (منهجية السجل الموثقة — نمط b37/b39).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً (كل علامة موقّفة على ملفها بالمصدر
     وتُتحقق حرفياً فيه قبل البحث بالثنائي — لا كتابة يدوية من الذاكرة).
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. استخراج الثنائيات بأسماء فريدة بوسم الهدف حتى لا يطغى آخر استخراج
     على أقدمه (درس b36).
  4. المميِّز بالعكس: علامات س136 الجديدة يجب أن تكون غائبة عن ثنائيتَي
     المرجعين المتاحين كليهما (b39 السلف المباشر وb38) فتثبت أن ما بُني هو
     الجديد لا الأسلاف — وهذه المرة المرجعان الأحدثان كلاهما حاضر بعد أن
     استُعيدا بأداة س134، فالتحقق العكسي مزدوج أقوى من نمط س132.

  الأداة داخل المستودع بدرس س134 (تدوير الصندوق أذهب أدوات b38/b39
  الخارجية — فما كان داخل المستودع صمد).

أكتُبت لتشغيل إغلاق b40 (س137): 86 علامة = استمرارية 67 (أساس 7 ووسطى 2
وس119 6 وس123 8 وس125 15 وس128 17 وس131 12 — عين قائمة أداة b39) +
مميِّزات س136 الجديدة 19 (10 لاتينية و9 عربية).

درسا الأداة (من فحص المرشحين الاستباقي — probe_b40_markers.py):
  - مرمّز AOT أسقط اسم rollbackWindowClosedByWrite كلياً من الثنائيتين
    رغم حضوره بالمصدر (نمط درس BackupReminderId بس132) — فالمميِّز محتوى
    لا أسماء دوال نقية.
  - أسماء planCapTrim وdeleteBackupManually وRestoreGateState قديمة من
    س128 دخلت بثنائيتي b39 (س136 وسّعتها بالأرضية لكن الاسم سابق) فليست من
    مميِّزات س136 — العبرة بالاسم الجديد الخالص: RollbackWindowState
    وprotectedFloorFileNames وplanSmartCleanup وغيرها.

الاستخدام:
  python3 scripts/verify_b40_markers.py <b40_libapp.so> <b40_app.so> \
      [--ref-android <b39_libapp.so> --ref-windows <b39_app.so>] \
      [--ref2-android <b38_libapp.so> --ref2-windows <b38_app.so>] \
      [--repo <مسار المستودع>]
"""

import argparse
import sys

REPO_DEFAULT = "/home/z/my-project/diqqah"
APP = "packages/app/lib"
DOM = "packages/domain/lib/src"
STO = "packages/storage/lib/src"

# ── مجموعة العلامات: (الملف بالمصدر، العلامة الحرفية) ──────────────────────
BASE = [
    (f"{APP}/gate_error_screen.dart", "GateErrorScreen"),          # لاتيني أساس
    (f"{STO}/database.dart", "snapshotBeforeUpgrade"),             # لاتيني أساس
    ("packages/app/pubspec.yaml", "0.2.3"),                        # لاتيني أساس (الطبعة)
    (f"{STO}/database.dart", "DiqqahDatabase"),                   # لاتيني أساس
    (f"{APP}/gate_error_screen.dart", "إعادة المحاولة"),           # عربان الأساس
    (f"{APP}/home_screen.dart", "معطلة"),                          # عربان الأساس
    (f"{APP}/home_screen.dart", "طلبات الشراء والبيع"),             # تسمية البلاطة (س98)
]
MIDDLE = [
    (f"{APP}/vouchers_screen.dart", "تحصيلات في الطريق — عهدة المندوبين"),  # س103/س104
    (f"{APP}/settings_screen.dart", "التشخيص ومرجع الأخطاء"),               # س107
]
S119 = [
    (f"{APP}/print_copies.dart", "طباعة الفاتورة"),
    (f"{APP}/print_copies.dart", "نسخة الزبون"),
    (f"{APP}/print_copies.dart", "نسخة أمين المستودع (بلا أسعار)"),
    (f"{APP}/print_copies.dart", "الصنف والكمية ومجموع الكميات — للتجهيز والتسليم"),
    (f"{APP}/invoices_screen.dart", "إذن تسليم"),
    (f"{APP}/print_copies.dart", "قوالب طباعة الفواتير (س119)"),
]
S123 = [
    (f"{APP}/home_screen.dart", "متاحة الآن — أوامر البيع والشراء والتحويل لفاتورة (07 §3.2)"),
    (f"{APP}/orders_screen.dart", "أمر جديد — اختر الاتجاه بالضغط"),
    (f"{APP}/orders_screen.dart", "التزام بيع لزبون — يُحوَّل لفاتورة بيع"),
    (f"{APP}/orders_screen.dart", "لا أوامر بعد — ابدأ بـ«أمر جديد»"),
    (f"{APP}/orders_screen.dart", "تأكيد الأمر؟"),
    (f"{APP}/orders_screen.dart", "إلغاء الأمر؟"),
    (f"{APP}/orders_screen.dart", "إغلاق الأمر؟"),
    (f"{APP}/orders_screen.dart", "طباعة الأمر"),
]
S125 = [
    (f"{APP}/receivables_screen.dart", "لا أرصدة بهذا الفلتر"),
    (f"{APP}/receivables_screen.dart", "الصافي: هم يدينون لنا"),
    (f"{APP}/receivables_screen.dart", "الصافي: نحن مدينون لهم"),
    (f"{APP}/receivables_screen.dart", "الصافي: مصفاة — لا ذمة"),
    (f"{APP}/receivables_screen.dart", "لا قيود مرحّلة على الطرف"),
    (f"{APP}/receivables_screen.dart", "الصافي التراكمي"),
    (f"{APP}/receivables_screen.dart", "لا أعمار — لا فواتير آجلة مستحقة"),
    (f"{APP}/receivables_screen.dart", "كشف حساب —"),
    (f"{APP}/ledger_screen.dart", "لا حسابات — الدليل فارغ"),
    (f"{APP}/ledger_screen.dart", "دليل الحسابات"),
    (f"{APP}/ledger_screen.dart", "ورقة تفتح كشف حسابها"),
    (f"{APP}/ledger_screen.dart", "كشف الحساب"),
    (f"{APP}/ledger_screen.dart", "الرصيد الختامي"),
    (f"{APP}/ledger_screen.dart", "الرصيد التراكمي"),
    (f"{APP}/ledger_screen.dart", "لا قيود مرحّلة على الحساب"),
]
S128 = [  # 17 بعد تصحيح س132 (سحبت «نسخة احتياطية دِقَّة»)
    (f"{APP}/backup_center.dart", "BackupCenter"),
    (f"{APP}/restore_gate_screen.dart", "RestoreGateScreen"),
    (f"{APP}/backups_catalog_screen.dart", "BackupsCatalogScreen"),
    (f"{STO}/backup_gfs.dart", "GfsBackupStore"),
    (f"{DOM}/backup_schedule.dart", "BackupScheduleKind"),
    (f"{STO}/backup_gfs.dart", ".dqk"),                            # الفيصل حصراً (درس b38: البادئة غير فريدة)
    (f"{APP}/device_status.dart", "diqqah/device_status"),
    (f"{APP}/backups_catalog_screen.dart", "كتالوج النسخ الاحتياطي"),
    (f"{APP}/restore_gate_screen.dart", "بوابة الاستعادة"),
    (f"{APP}/restore_gate_screen.dart", "استُنفدت المحاولات الخمس"),
    (f"{APP}/restore_gate_screen.dart", "استعادة نسخة أخرى"),
    (f"{APP}/restore_gate_screen.dart", "سلامة القاعدة: سليمة"),
    (f"{APP}/settings_screen.dart", "النسخ الاحتياطي المجدول"),
    (f"{APP}/settings_screen.dart", "حصة مجلد النسخ"),
    (f"{APP}/home_screen.dart", "لم تُنشأ نسخة احتياطية منذ 30"),
    (f"{APP}/backups_catalog_screen.dart", "نسخة سنوية دائمة"),
    (f"{APP}/backup_center.dart", "فشل نسخة"),
]
S131 = [  # 12
    (f"{APP}/backup_reminders.dart", "BackupRemindersPanel"),
    (f"{APP}/backup_reminders.dart", "BackupReminderSeverity"),
    (f"{APP}/backup_reminders.dart", "buildBackupReminders"),
    (f"{APP}/backup_reminders.dart", "بلا نسخة احتياطية حديثة"),
    (f"{APP}/backup_reminders.dart", "المرفقات خارج آخر نسخة"),
    (f"{APP}/backup_reminders.dart", "السارية بانتظار الشحن"),
    (f"{APP}/backup_reminders.dart", "أنشئ نسخة الآن (مع المرفقات)"),
    (f"{APP}/backup_reminders.dart", "الحصة تقترب من السقف"),
    (f"{APP}/backup_reminders.dart", "الساعية متوقفة بحصة ممتلئة"),
    (f"{APP}/backup_reminders.dart", "بحماية سليمة"),
    (f"{APP}/backup_reminders.dart", "افتح الكتالوج"),
    (f"{APP}/backup_reminders.dart", "تخطّت النسخة السارية"),
]
S136_NEW = [  # 19: 10 لاتينية و9 عربية
    # المجال — نافذة التراجع والأرضية والتنظيف الذكي
    (f"{DOM}/rollback_window.dart", "RollbackWindowState"),
    (f"{DOM}/backup_schedule.dart", "protectedFloorFileNames"),
    (f"{DOM}/backup_schedule.dart", "planSmartCleanup"),
    # التخزين — زرع اللقطة والتسليح والحارس والفيصل
    (f"{STO}/backup_gfs.dart", "rotateBeforeRestoreSnapshots"),
    (f"{STO}/database.dart", "armRollbackWindow"),
    (f"{STO}/database.dart", "maxEventId"),
    (f"{STO}/database.dart", "restore.rollback_window"),
    (f"{STO}/database.dart", "rollback_window_closed"),
    # الواجهة — الشاشة المستقلة والإصدار بمصدر واحد
    (f"{APP}/storage_manager_screen.dart", "StorageManagerScreen"),
    (f"{APP}/backup_center.dart", "0.2.3+34"),                    # kAppVersion — مصدر واحد
    # العربية التسع — بوابة الاستعادة والكتالوج وإدارة التخزين
    (f"{APP}/restore_gate_screen.dart", "نافذة التراجع عن الاستعادة مفتوحة"),
    (f"{APP}/restore_gate_screen.dart", "تراجع عن الاستعادة"),
    (f"{APP}/backups_catalog_screen.dart", "نافذة التراجع مفتوحة"),
    (f"{APP}/backups_catalog_screen.dart", "لا تراجع بعد الآن — تصحيح أو استعادة واعية"),
    (f"{APP}/storage_manager_screen.dart", "إدارة التخزين"),
    (f"{APP}/storage_manager_screen.dart", "التنظيف الذكي"),
    (f"{APP}/storage_manager_screen.dart", "الأرضية النظامية (د-4): آخر نسخة من كل نوع لا تُحذف"),
    (f"{APP}/storage_manager_screen.dart", "نسخة بالتنظيف الذكي"),
    (f"{APP}/storage_manager_screen.dart", "نهائياً؟ الأرضية باقية مهما حدث."),
]

GROUPS = [
    ("الأساس (لاتينية أربع + عربان الثلاثة)", BASE),
    ("الوسطى (س103/س107)", MIDDLE),
    ("مميِّزات س119 (قوالب الطباعة والنسختين)", S119),
    ("مميِّزات س123 (الطلبات — الواجهة)", S123),
    ("مميِّزات س125 (الذمم والدفتر)", S125),
    ("مميِّزات س128 (النسخ GFS دفعة 1 — 17 بعد تصحيح س132)", S128),
    ("مميِّزات س131 (التذكيرات الذكية)", S131),
    ("مميِّزات س136 (نافذة التراجع والأرضية وإدارة التخزين — الجديدة)", S136_NEW),
]


def read_bin(path):
    with open(path, "rb") as fh:
        return fh.read()


def find_encodings(data, needle):
    """يرجع قائمة الترميزات التي وُجد فيها النص (UTF-8 و/أو UTF-16LE)."""
    found = []
    if needle.encode("utf-8") in data:
        found.append("UTF-8")
    if needle.encode("utf-16-le") in data:
        found.append("UTF-16LE")
    return found


def main():
    ap = argparse.ArgumentParser(description="التحقق البايتي لحزمتي b40")
    ap.add_argument("libapp", help="مسار b40_libapp.so (ثنائي أندرويد)")
    ap.add_argument("appso", help="مسار b40_app.so (ثنائي ويندوز data/app.so)")
    ap.add_argument("--ref-android", help="مرجع b39 libapp.so للتحقق العكسي الأول")
    ap.add_argument("--ref-windows", help="مرجع b39 app.so للتحقق العكسي الأول")
    ap.add_argument("--ref2-android", help="مرجع b38 libapp.so للتحقق العكسي الثاني")
    ap.add_argument("--ref2-windows", help="مرجع b38 app.so للتحقق العكسي الثاني")
    ap.add_argument("--repo", default=REPO_DEFAULT, help="مسار جذر المستودع")
    args = ap.parse_args()

    bin_a = read_bin(args.libapp)
    bin_w = read_bin(args.appso)
    refs = []
    if args.ref_android and args.ref_windows:
        refs.append(("b39", read_bin(args.ref_android), read_bin(args.ref_windows)))
    if args.ref2_android and args.ref2_windows:
        refs.append(("b38", read_bin(args.ref2_android), read_bin(args.ref2_windows)))

    total = 0
    ok = 0
    failures = []
    for group_name, markers in GROUPS:
        print(f"\n== {group_name} — {len(markers)} علامة ==")
        for src_rel, needle in markers:
            total += 1
            src_path = f"{args.repo}/{src_rel}"
            # القاعدة 1: العلامة يجب أن تكون حرفياً في سطر المصدر أولاً
            try:
                src_text = open(src_path, encoding="utf-8").read()
            except FileNotFoundError:
                failures.append(f"مصدر غائب: {src_path}")
                print(f"  ✗ {needle} — المصدر غائب: {src_path}")
                continue
            if needle not in src_text:
                failures.append(f"العلامة ليست بالمصدر: {needle} @ {src_rel}")
                print(f"  ✗ {needle} — ليست بالمصدر {src_rel} (خُلِفت القاعدة 1)")
                continue
            fa = find_encodings(bin_a, needle)
            fw = find_encodings(bin_w, needle)
            enc_txt = f"{','.join(fa) or 'غائب'} | {','.join(fw) or 'غائب'}"
            if fa and fw:
                ok += 1
                print(f"  ✓ {needle}  [{enc_txt}]")
            else:
                missing = ("أندرويد" if not fa else "") + ("+ويندوز" if not fw else "")
                failures.append(f"غائب بالثنائي ({missing}): {needle}")
                print(f"  ✗ {needle} — غائب بالثنائي ({missing}) [{enc_txt}]")

    print(f"\n== الخلاصة: {ok}/{total} علامة حاضرة بالثنائيتين ==")

    # القاعدة 4: المميِّز بالعكس — علامات س136 غائبة عن كل مرجع متاح
    for ref_name, ref_a, ref_w in refs:
        print(f"\n== التحقق العكسي: مميِّزات س136 يجب أن تكون غائبة عن ثنائيتَي {ref_name} ==")
        leaked = []
        for src_rel, needle in S136_NEW:
            ra = find_encodings(ref_a, needle)
            rw = find_encodings(ref_w, needle)
            if ra or rw:
                leaked.append(needle)
                print(f"  ✗ LEAK: {needle} موجود بمرجع {ref_name} ({','.join(ra + rw)})")
        if leaked:
            print(f"  تسريب {len(leaked)} علامة إلى مرجع {ref_name} — المميِّز غير صادق!")
            failures.append(f"تسريب {len(leaked)} علامة س136 إلى {ref_name}")
        else:
            print(f"  ✓ نظيف: {len(S136_NEW)} علامة س136 غائبة كلها عن ثنائيتَي {ref_name}")

    if failures:
        print(f"\nالنتيجة: FAIL — {len(failures)} إخفاق")
        for f in failures:
            print(f"  - {f}")
        sys.exit(1)
    print("\nالنتيجة: CLEAN — كل العلامات حاضرة والمميِّز صادق بالعكس على المرجعين")
    sys.exit(0)


if __name__ == "__main__":
    main()
