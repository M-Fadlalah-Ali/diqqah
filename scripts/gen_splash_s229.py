#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""مولد انطلاقة دِقَّة الموحّدة (س229 — د11/توحيد الانطلاقة بكلمة المالك
«وحّد الانطلاقة»): الانطلاقة بالعمل الفني الديواني الجديد عينه الذي
صار أيقونة س228 — فالأمر توحيد لا ابتكار: العمل الفني المودع
icon-master.png (1920×1920 بخلفيته الفحمية 30,30,30 وحبره الخوخي
والبُني) يُعرض مركزياً فوق الخلفية الفحمية ذاتها، فالانطلاقة والأيقونة
وجهان لعمل واحد بعد أن كانت الانطلاقة بالهوية البنية القديمة والكلمة
الوسطة القديمة (س227) بينما الأيقونة تجددت (س228).

المخرجات:
  - drawable-nodpi/diqqah_splash_art.png (512×512 — العمل كاملاً
    بهوامشه الزخرفية، LANCZOS بنمط س228: تكوين مكتمل فلا قصّ ولا
    هامش داخلي ولا إعادة تلوين)
  - وإزالة الكلمة الوسطة القديمة diqqah_splash_wordmark.png (س227 —
    حل محلها العمل الفني، والمراجع حدّثتها launch_background.xml
    وdrawable-v21/launch_background.xml حصراً)
  - التحقق التوثيقي: عيّنة زوايا الأصل فحمية (30,30,30) — فتوحيد
    الخلفية بالقالب اللوني ذاته لا تقريب عين.

التفعيل اليدوي عند الحاجة: python3 scripts/gen_splash_s229.py
"""
from PIL import Image

BASE = 'packages/app'
SRC = f'{BASE}/assets/brand/icon-master.png'
OUT = (f'{BASE}/android/app/src/main/res/drawable-nodpi/'
       'diqqah_splash_art.png')
LEGACY = (f'{BASE}/android/app/src/main/res/drawable-nodpi/'
          'diqqah_splash_wordmark.png')

# حجم العرض الوسيط: drawable-nodpi = بلا تحجيم كثافة، فيُعرض 512px
# مركزياً على الشاشات كلها — وحدة معقولة فوق الخلفية الفحمية الواسعة
# (لا 1920 فيفيض عن الشاشات الصغيرة ولا 256 فيضيع التكوين الزخرفي).
SPLASH_SIZE = 512

# خلفية العمل الفني الموثقة (س228): فحمي (30,30,30) — والمقاس
# بالقالب اللوني بالأنظمة (values/colors.xml: diqqah_launch_bg).
BG = (30, 30, 30)


def corner_samples(img: Image.Image) -> list[tuple[int, ...]]:
    """عيّنات الزوايا الأربع + منتصف الحواف — إثبات توحيد الخلفية."""
    w, h = img.size
    pts = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    return [img.getpixel(pt) for pt in pts]


def main() -> None:
    src = Image.open(SRC).convert('RGBA')
    assert src.size == (1920, 1920), f'أصل غير متوقع: {src.size}'

    # الصدق التوثيقي: زوايا الأصل فحمية فالخلفية بالقالب توحيد لا اجتهاد.
    corners = corner_samples(src)
    for c in corners:
        rgb = c[:3]
        assert all(abs(rgb[i] - BG[i]) <= 3 for i in range(3)), (
            f'زاوية غير فحمية: {rgb} — العمل الفني تغيّر فافحص الأصل')
    print('عيّنات الزوايا فحمية (30,30,30) — التوحيد بالأصل نفسه')

    # العمل كاملاً بلا قصّ ولا هامش — بنمط س228 حرفاً.
    splash = src.resize((SPLASH_SIZE, SPLASH_SIZE), Image.LANCZOS)
    splash.save(OUT)
    print(f'drawable-nodpi/diqqah_splash_art.png {SPLASH_SIZE}x{SPLASH_SIZE}')

    # الكلمة الوسطة القديمة (س227) تحل محلها الأرضية الجديدة.
    try:
        Image.open(LEGACY).close()
        import os
        os.remove(LEGACY)
        print('أُزيلت diqqah_splash_wordmark.png القديمة (س227 — حل محلها '
              'العمل الفني)')
    except FileNotFoundError:
        print('الكلمة القديمة غير موجودة أصلاً — تخطٍّ')

    # تحقق نهائي: الناتج موجود بمقاسه وخلفيته فحمية هي الأصل.
    out = Image.open(OUT).convert('RGBA')
    assert out.size == (SPLASH_SIZE, SPLASH_SIZE)
    for c in corner_samples(out):
        assert all(abs(c[i] - BG[i]) <= 3 for i in range(3)), (
            f'زاوية الناتج انحرفت: {c[:3]}')
    print('CLEAN — الانطلاقة بالعمل الفني الجديد (توحيد س229)')


if __name__ == '__main__':
    main()
