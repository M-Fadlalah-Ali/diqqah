#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س231 — قارئ versionCode وversionName من AndroidManifest الثنائي داخل أثر
APK (بلا aapt ولا أدوات أندرويد — قراءة بايتية صريحة).

لماذا هذه الأداة؟ درس س231 للترقيم: رقم البناء الحقيقي يُقرأ من داخل الأثر
لا من لاحقة pubspec ولا من نص السكربت بسجل المسار (المتغير GITHUB_RUN_NUMBER
يُطبع بلا توسيع) — فالتوثيق الصادق يحتاج قراءة بايتية من الأثر ذاتها:
  b81 (v.0.278) → versionCode 2081 وversionName 0.278.00.81
  b82 (v.0.279) → versionCode 2082 وversionName 0.279.00.82
  b83 (v.0.280) → versionCode 2083 وversionName 0.280.00.83
فقاعدة الرقم: versionCode = رقم تشغيل مسار «بناء الحزم» + 2000 (إزاحة
1000×ABI_VERSION=2 لأثر arm64 المقسومة يضيفها قالب فلاتر آلياً — تعليق
build.gradle.kts المودع يوثقها) وversionName بصيغة D-058 «0.N.00.X».

بنية AXML المقروءة: مجموعة السلاسل (UTF-8 أو UTF-16LE) ثم مقاطع عناصر
(0x0102) — كل سمة: ns(4) name(4) rawValue(4) حجم القيمة الموسومة(2) res0(1)
نوعها(1) بياناتها(4) — وversionCode قيمة موسومة بنوع INT فتُقرأ من
بياناتها مباشرة.

الاستخدام:
  python3 scripts/parse_apk_version_s231.py <apk>
"""
import struct
import sys
import zipfile


def parse_string_pool(data: bytes, off: int) -> list:
    """قراءة مجموعة سلاسل AXML بترميزيها."""
    (_typ, _hs, _size, count, _styles, flags, strings_start, _ss) = (
        struct.unpack_from('<HHIIIIII', data, off))
    utf8 = (flags & (1 << 8)) != 0
    out = []
    for i in range(count):
        (so,) = struct.unpack_from('<I', data, off + 28 + i * 4)
        p = off + strings_start + so
        if utf8:
            l1 = data[p]
            p += 1
            if l1 & 0x80:
                l2 = data[p]
                p += 1
                ln = ((l1 & 0x7F) << 8) | l2
            else:
                ln = l1
            out.append(data[p:p + ln].decode('utf-8', errors='replace'))
        else:
            (l,) = struct.unpack_from('<H', data, p)
            p += 2
            if l & 0x8000:
                (h,) = struct.unpack_from('<H', data, p)
                p += 2
                ln = ((l & 0x7FFF) << 16) | h
            else:
                ln = l
            out.append(data[p:p + ln * 2].decode('utf-16-le', errors='replace'))
    return out


def main(path: str) -> int:
    with zipfile.ZipFile(path) as z:
        data = z.read('AndroidManifest.xml')
    strings: list = []
    res: dict = {}
    i = 8
    while i < len(data) - 8:
        typ, _hs, sz = struct.unpack_from('<HHI', data, i)
        if typ == 0x0001:  # مجموعة السلاسل
            strings = parse_string_pool(data, i)
        elif typ == 0x0102:  # بداية عنصر
            node = i + 16  # بعد ترويسة السطر والتعليق
            _ns, name = struct.unpack_from('<II', data, node)
            (a_start, a_size, a_count) = struct.unpack_from('<HHH', data, node + 8)
            el = strings[name] if name != 0xFFFFFFFF else '?'
            if el != 'manifest':
                i += sz
                continue
            for a in range(a_count):
                ao = node + a_start + a * a_size
                _ans, aname, raw = struct.unpack_from('<III', data, ao)
                (_tv_size, _res0, tv_type) = struct.unpack_from('<HBB', data, ao + 12)
                (tv_data,) = struct.unpack_from('<I', data, ao + 16)
                an = strings[aname] if aname != 0xFFFFFFFF else ''
                if an == 'versionCode':
                    res['versionCode'] = tv_data
                elif an == 'versionName':
                    res['versionName'] = (strings[raw]
                                          if raw != 0xFFFFFFFF else str(tv_data))
                elif an == 'package':
                    res['package'] = (strings[raw]
                                      if raw != 0xFFFFFFFF else '')
        i += sz
    print('package:', res.get('package'))
    print('versionCode:', res.get('versionCode'))
    print('versionName:', res.get('versionName'))
    if 'versionCode' not in res:
        print('فشل: versionCode غائب عن الأثر — القراءة البايتية لم تجدها')
        return 1
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
