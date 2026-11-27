#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""مولد أيقونة دِقَّة وانطلاقتها (س227 — المرحلة صفر د6 من خارطة طريق
التقرير الاستشاري بأمر المالك «ابدأ التنفيذ»): الأيقونة والانطلاقة
بالهدوية من الشعار الموجود أصلاً (wordmark-footer.png) — الحبر الداكن
يُستبدل بلون الهوية الفاتح (#D4A57E) فوق بني الهوية العميق
(#8B5A3C) فلا أصل جديد يُبتكر بل اشتقاق من الأصل (عقد الهوية س182
والتقرير الاستشاري: «هوية الطباعة مدروسة والأيقونة الافتراضية تقتل
أول انطباع»).

المخرجات:
  - mipmap-{mdpi..xxxhdpi}/ic_launcher.png  (48..192)
  - drawable-nodpi/diqqah_splash_wordmark.png (كلمة الانطلاقة)
  - windows/runner/resources/app_icon.ico   (ويندوز متعدد المقاسات)

التفعيل اليدوي عند الحاجة: python3 scripts/gen_app_icons_s227.py
"""
from PIL import Image

BASE = 'packages/app'
SRC = f'{BASE}/assets/brand/wordmark-footer.png'

# هوية المشروع (app_theme.dart): البني العميق للنهار والفاتح لليل —
# الأيقونة من جسد النهار (العميق خلفية) بحبر ليل الهوية (الفاتح).
BG = (0x8B, 0x5A, 0x3C, 0xFF)  # kLightIdentityBrown
INK = (0xD4, 0xA5, 0x7E, 0xFF)  # kDarkIdentityBrown

DENSITIES = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}


def recolored_wordmark() -> Image.Image:
    """العلامة بحبرها الشكلي (ألفا) مصبوغة بلون الهوية الفاتح."""
    src = Image.open(SRC).convert('RGBA')
    bbox = src.getbbox()
    src = src.crop(bbox)
    inked = Image.new('RGBA', src.size, (0, 0, 0, 0))
    inked.paste(INK, mask=src.split()[3])
    return inked


def icon_of(wordmark: Image.Image, size: int) -> Image.Image:
    """مربع مملوء ببني الهوية والكلمة موسطة بهامش 10% من كل جهة."""
    canvas = Image.new('RGBA', (size, size), BG)
    margin = int(size * 0.10)
    inner = size - 2 * margin
    ratio = min(inner / wordmark.width, inner / wordmark.height)
    scaled = wordmark.resize(
        (max(1, int(wordmark.width * ratio)),
         max(1, int(wordmark.height * ratio))),
        Image.LANCZOS)
    canvas.alpha_composite(scaled, (
        int((size - scaled.width) / 2), int((size - scaled.height) / 2)))
    return canvas


def main() -> None:
    wordmark = recolored_wordmark()
    for bucket, size in DENSITIES.items():
        out = f'{BASE}/android/app/src/main/res/mipmap-{bucket}/ic_launcher.png'
        icon_of(wordmark, size).save(out)
        print(f'mipmap-{bucket}/ic_launcher.png {size}x{size}')

    # كلمة الانطلاقة: العلامة بحبر الهوية عرضها 720 (تُعرض مركزية
    # بlaunch_background فوق بني الهوية — أي كثافة بجذر drawable-nodpi).
    splash = wordmark.resize(
        (720, max(1, int(720 * wordmark.height / wordmark.width))),
        Image.LANCZOS)
    splash.save(f'{BASE}/android/app/src/main/res/drawable-nodpi/'
                'diqqah_splash_wordmark.png')
    print('drawable-nodpi/diqqah_splash_wordmark.png')

    # أيقونة ويندوز: متعددة المقاسات بأصل واحد.
    icons = [icon_of(wordmark, s) for s in (256, 128, 64, 48, 32, 16)]
    icons[0].save(f'{BASE}/windows/runner/resources/app_icon.ico',
                  format='ICO', sizes=[(s, s) for s in (256, 128, 64, 48, 32, 16)],
                  append_images=icons[1:])
    print('windows/runner/resources/app_icon.ico')


if __name__ == '__main__':
    main()
