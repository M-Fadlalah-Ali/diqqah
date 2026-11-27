#!/usr/bin/env python3
# س228 — مولّد أيقونة التطبيق من العمل الفني الجديد بأمر المالك
# («واستخدم الصورة المرفقة أيقونة للتطبيق» — جلسة المرحلة الأولى).
#
# المصدر: packages/app/assets/brand/icon-master.png (1920×1920 RGBA)
# عمل خطّي ديواني لكلمة «دِقَّة» بخلفية فحمية داكنة وحبر خوخي وبُني —
# الأصل الفني مودع بحزمة الهوية والاشتقاق منه آلي لا ابتكار يدوي (عقد الهوية س182).
#
# النمط: أداة س227 gen_app_icons_s227.py بعينها — لكن بلا هامش داخلي ولا
# إعادة تلوين: العمل الفني تكوين مكتمل بهوامشه الزخرفية وخلفيته الخاصة،
# فالملء الكامل بمقياس LANCZOS يحفظ التكوين كما رآه المالك.
#
# المخارج: خمس كثافات mipmap (48/72/96/144/192) + ICO ويندوز
# (256/128/64/48/32/16) — بنفس مسارات س227 حرفاً فلا مرجع يُكسر
# (Runner.rc سطر 55 وlaunch_background.xml لا يمسان).
#
# الاستخدام: python3 scripts/gen_app_icons_s228.py  (من جذر المستودع)
import os
from PIL import Image

SRC = 'packages/app/assets/brand/icon-master.png'
RES = 'packages/app/android/app/src/main/res'
ICO = 'packages/app/windows/runner/resources/app_icon.ico'

DENSITIES = [
    ('mipmap-mdpi', 48),
    ('mipmap-hdpi', 72),
    ('mipmap-xhdpi', 96),
    ('mipmap-xxhdpi', 144),
    ('mipmap-xxxhdpi', 192),
]
ICO_SIZES = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]

def main():
    master = Image.open(SRC).convert('RGBA')
    w, h = master.size
    if w != h:
        raise SystemExit(f'ERR: المصدر غير مربع ({w}x{h}) — الأيقونة مربع إلزاماً')
    print(f'MASTER: {SRC} — {w}x{h} RGBA')

    # توثيق الألوان (لملف العمل وسجل الجلسة)
    px = master.load()
    corner = px[8, 8]
    center = px[w // 2, h // 2]
    print(f'COLORS: corner={tuple(corner)} center_sample={tuple(center)}')

    for folder, size in DENSITIES:
        out = os.path.join(RES, folder, 'ic_launcher.png')
        img = master.resize((size, size), Image.LANCZOS)
        img.save(out, 'PNG', optimize=True)
        print(f'ICON: {out} — {size}x{size} — {os.path.getsize(out)} B')

    master.resize((256, 256), Image.LANCZOS).save(
        ICO, format='ICO', sizes=ICO_SIZES)
    print(f'ICO: {ICO} — {os.path.getsize(ICO)} B — sizes={ICO_SIZES}')
    print('OK س228')

if __name__ == '__main__':
    main()
