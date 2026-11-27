#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""بوابة فحص الأسرار (س227 — المرحلة صفر د2 من خارطة طريق التقرير
الاستشاري بأمر المالك «ابدأ التنفيذ»): تمسح شجرة المستودع المسلوكة
فقط (git ls-files) بحثاً عن أسرار البناء والتوزيع — ملفات الخواتم
وكلماتها ومفاتيح الخاصة ورموز الوصول وملفات البيئة — والفشل برسالة
معللة ورمز خروج 1 (بوابةٌ لا تفشل ليست بوابات — س225).

النمط: أداة CI خالصة بلا تبعيات خارج النظام (قاعدة السفراء الثالثة
للحزم) — تعمل على ubuntu-latest كما في windows بلا فرق، وتُستدعى من
ci.yml وbuild.yml قبل أي بناء أو حكم.
"""
import re
import subprocess
import sys


def tracked_files() -> list[str]:
    out = subprocess.run(
        ['git', 'ls-files'], capture_output=True, text=True, check=True)
    return [f for f in out.stdout.splitlines() if f.strip()]


# امتدادات وأسماء ملفات الأسرار المعروفة — وجود الملف نفسه علّة.
SECRET_FILE_PATTERNS = [
    re.compile(r'\.(keystore|jks|p12|pfx|pem|key)$', re.I),
    re.compile(r'(^|/)(id_rsa|id_dsa|id_ecdsa|id_ed25519)(\.|$)'),
    re.compile(r'\.pass\.txt$', re.I),
    re.compile(r'(^|/)\.env(\..+)?$'),
]

# بصمات المحتوى المعروفة — ترويسات المفاتيح الخاصة وبادئات رموز الوصول.
SECRET_CONTENT_PATTERNS = [
    (re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'), 'ترويسة مفتاح خاص'),
    (re.compile(r'github_pat_[A-Za-z0-9_]{20,}'), 'رمز وصول GitHub دقيق'),
    (re.compile(r'\bgh[pousr]_[A-Za-z0-9]{30,}'), 'رمز وصول GitHub'),
    (re.compile(r'\bAKIA[0-9A-Z]{16}\b'), 'مفتاح وصول AWS'),
    (re.compile(r'\bxox[baprs]-[A-Za-z0-9-]{10,}'), 'رمز Slack'),
]

# أماكن يجوز ذكر البادئات فيها تعليقاً وتوثيقاً لا سراً (الواجهة الأدبية).
CONTENT_ALLOWLIST = ['scripts/secret_scan.py']


def main() -> int:
    findings: list[str] = []
    files = tracked_files()

    for f in files:
        for pat in SECRET_FILE_PATTERNS:
            if pat.search(f):
                findings.append(f'ملف سرّي في الشجرة: {f}')
                break

    for f in files:
        if f in CONTENT_ALLOWLIST or not f.endswith(('.dart', '.py', '.yml',
                                                      '.yaml', '.kts', '.md',
                                                      '.xml', '.json', '.sh',
                                                      '.txt', '.rc', '.cpp',
                                                      '.h', '.js')):
            continue
        try:
            blob = open(f, encoding='utf-8', errors='ignore').read()
        except OSError:
            continue
        for pat, label in SECRET_CONTENT_PATTERNS:
            m = pat.search(blob)
            if m:
                findings.append(f'{label} في {f}: …{m.group(0)[:24]}…')
                break

    if findings:
        print('FAIL — أسرار مكتشفة في الشجرة (بوابة س227):')
        for f in findings:
            print('  ✗', f)
        print('لا تُدفع الأسرار أبداً — درّجها في أسرار GitHub أو بيئة العمل.')
        return 1
    print(f'CLEAN — بلا أسرار في الشجرة ({len(files)} ملفاً مفحوصاً)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
