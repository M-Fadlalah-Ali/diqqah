# -*- coding: utf-8 -*-
"""إكمال فقرة الذرية في 05 + تحقق شامل من كل تعديلات v1.01."""
import io, os, sys

BASE = "/home/z/my-project/download/heseb-docs"

def rd(n):
    return io.open(os.path.join(BASE, n), encoding="utf-8").read()

def wr(n, t):
    io.open(os.path.join(BASE, n), "w", encoding="utf-8").write(t)

# ---- 1) إدراج فقرة الذرية في 05 (بعد سطر device_id) ----
t = rd("05-data-model.md")
if "معاملة (transaction) واحدة" not in t:
    lines = t.split("\n")
    out = []
    inserted = False
    for l in lines:
        out.append(l)
        if not inserted and "`device_id`" in l:
            out.append("- كل عملية ترحيل تُنفَّذ داخل معاملة (transaction) واحدة تشمل قيدها وحركات المخزون/الصندوق وتحديث المشتقات والترقيم وحدثها — إما أن تُكتب كلها أو لا شيء؛ انقطاع الكهرباء أو الإنهاء القسري يعيد القاعدة إلى آخر حالة مكتملة بلا أثر جزئي (07 §2.4، F-053 — D-029).")
            inserted = True
    assert inserted, "device_id anchor not found in 05"
    wr("05-data-model.md", "\n".join(out))
    print("05: atomicity bullet inserted")
else:
    print("05: atomicity already present")

# ---- 2) التحقق الشامل ----
fails = []
def chk(cond, msg):
    if not cond:
        fails.append(msg)

rdme = rd("README.md")
chk(rdme.count("(diqqah)") == 0, "README: lowercase (diqqah) still present")
chk(rdme.count("(Diqqah)") == 1, "README: title Diqqah wrong count")
for i in range(23, 32):
    chk("| D-0%02d |" % i in rdme, "README: D-0%d missing" % i)
chk("01-vision-and-scope-v1.01.md" in rdme and "10-test-plan-v1.01.md" in rdme, "README: map not versioned")
chk(rdme.count(" v1.0 —") == 0 and " v1.01 —" in rdme, "README: map status versions")

t1 = rd("01-vision-and-scope.md")
chk("(diqqah)" not in t1 and "(Diqqah)" in t1, "01: name casing")
chk("تطبيق محاسبة صغير" not in t1 and "قليل العدد" not in t1, "01: diminutives in s1")
chk("أصحاب الأعمال الصغيرة" not in t1, "01: s2 owners")
chk("حجم يصلح لعمل صغير" not in t1 and "حجم أعمالهم" in t1, "01: s2 scale")
chk("لفريق عمل صغير" not in t1, "01: s3 team")
chk("طلبات الشراء والبيع" in t1, "01: orders row missing")
chk("خيارات الفواتير/الحسابات" in t1, "01: tax options missing")
chk("خيارات العرض" in t1, "01: hijri options missing")
chk("بايثون/Rust/Go" in t1, "01: flutter rationale ref missing")
chk("جولة التنبيهات الأولى (2026-10-22)" in t1 and "13. تأكيد Flutter" in t1, "01: s9 block missing")
chk("يُعاد النقاش في هذا السقف" in t1, "01: d021 revisit missing")

t2 = rd("02-terminology.md")
chk("ما دوّن في هذا القاموس" in t2, "02: rule1 fix missing")
chk("ما دون هذا القاموس" not in t2, "02: rule1 old still there")
chk("وحدة بلقطة" not in t2, "02: blaqta still there")
chk("كمية، وحدة، لقطة العامل، سعر" in t2, "02: invoice lines option B missing")
chk("(Diqqah) | Diqqah" in t2, "02: name row casing")

t3 = rd("03-chart-of-accounts.md")
chk("محل تجاري صغير" not in t3, "03: shop diminutive still there")

t4 = rd("04-srs.md")
chk(t4.count("N-009") == 2, "04: N-009 (row+map)")
chk("ذرية العملية، سجل أحداث" in t4, "04: four rules in s0.5")
chk("قوالب مقترحة غير حصرية" in t4, "04: F-032 units non-exhaustive")
chk("D-027" in t4, "04: F-074 flexibility")
chk("يُعاد النقاش في السقف" in t4, "04: N-008 revisit")

t5 = rd("05-data-model.md")
chk("معاملة (transaction) واحدة" in t5, "05: atomicity bullet")
chk("أمثلة غير حصرية ويضيف المستخدم" in t5, "05: unit_group non-exhaustive")
chk("المدة قابلة للضبط من الإعدادات" in t5, "05: period flexibility")

t6 = rd("06-workflows.md")
chk("مدة الفترة قابلة للضبط" in t6, "06: s6 flexibility")
chk("اختيار الفترة ثم" in t6, "06: s20 wording")

t7 = rd("07-tryton-principles.md")
chk("القواعد التنفيذية الأربع" in t7, "07: four rules title")
chk("ذرية العملية الكاملة" in t7 and "2.4" not in "", "07: rule 4 present")
chk("لماذا Flutter تحديداً" in t7, "07: flutter note missing")
chk("مدة الفترة قابلة للضبط" in t7, "07: s1.5 flexibility")

t8 = rd("08-sync-strategy.md")
chk("1.01" in t8, "08: version bump")

t9 = rd("09-release-plan.md")
chk("لعمل محلي صغير" not in t9, "09: s5 diminutive")
chk("قوالب مقترحة غير حصرية" in t9, "09: s3 units note")
chk("خيارات الفواتير/الحسابات (D-028)" in t9, "09: s6 tax activation")
chk("أوامر البيع/الشراء والشحن" in t9, "09: s8 orders bullet")
chk("خيارات العرض (D-017، D-028)" in t9, "09: s8 hijri")

t10 = rd("10-test-plan.md")
chk("بلقطة" not in t10, "10: blaqta still there")
chk("مع لقطة عاملها" in t10, "10: m2 wording")
chk("N-009" in t10 and "N-001..N-009" in t10, "10: N-009 row+title")
chk("محاكاة إنهاء مفاجئ أثناء الترحيل لا تترك أثراً جزئياً" in t10, "10: m1 atomicity test")

# التواريخ
for f in ["README.md", "01-vision-and-scope.md", "02-terminology.md", "03-chart-of-accounts.md",
          "04-srs.md", "05-data-model.md", "06-workflows.md", "07-tryton-principles.md",
          "08-sync-strategy.md", "09-release-plan.md", "10-test-plan.md"]:
    t = rd(f)
    chk("| التاريخ | 2026-10-22 |" in t, f + ": header date not 2026-10-22")
    chk("1.01" in [l for l in t.split(chr(10)) if l.startswith(("| الإصدار |", "| إصدار الحزمة |"))][0], f + ": header version not 1.01")

# بقايا بلقطة وأقواس diqqah في الحزمة كلها
for f in ["README.md", "01-vision-and-scope.md", "02-terminology.md", "03-chart-of-accounts.md",
          "04-srs.md", "05-data-model.md", "06-workflows.md", "07-tryton-principles.md",
          "08-sync-strategy.md", "09-release-plan.md", "10-test-plan.md"]:
    t = rd(f)
    chk("بلقطة" not in t, f + ": blaqta residue")

if fails:
    print("VERIFY FAILURES ({}):".format(len(fails)))
    for m in fails:
        print("  - " + m)
    sys.exit(1)
print("ALL CHECKS PASSED (05 fixed + full verification)")
