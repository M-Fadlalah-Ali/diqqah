#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س228 — رقعة الإغلاق التوثيقي: توثيق أرقام الجولات الحاكمة بعد الخضرة.
PROBE_RUN / MAIN_RUN تمرر بيئةً أو تُعدل هنا حصراً — بلا مرساة غامضة."""
import io, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROBE_NUM = os.environ.get('PROBE_NUM', '474')
PROBE_ID = os.environ.get('PROBE_ID', '46062254454')
MAIN_NUM = os.environ.get('MAIN_NUM', '')
MAIN_ID = os.environ.get('MAIN_ID', '')
HEAD_SHA = os.environ.get('HEAD_SHA', 'a5ae291')
if not MAIN_NUM or not MAIN_ID:
    sys.exit('ERR: مرر MAIN_NUM وMAIN_ID')

def rw(path):
    with io.open(path, 'r', encoding='utf-8') as f: return f.read()

def wf(path, s):
    with io.open(path, 'w', encoding='utf-8') as f: f.write(s)

ROUNDS = (f'#{PROBE_NUM} خضراء كاملة بالمهام الأربع على {HEAD_SHA} (run {PROBE_ID}) '
          f'ثم دفع main و#{MAIN_NUM} خضراء كاملة بالمهام الأربع (run {MAIN_ID}) '
          '— وفرع الاستطلاع مدمج ومحذوف فرعياً وبعيداً')

# 1) worklog — بند (7)
p = os.path.join(ROOT, 'worklog.md')
s = rw(p)
OLD = '**(7) الجولة الحاكمة**: الاستطلاع بفرع `probe-s228` بworkflow_dispatch (عرف س227 — لا تعرف main حمراء أبداً) ثم دفع main — وأرقام التشغيلات تُوثق برقعة الإغلاق فور الخضرة.'
NEW = f'**(7) الجولة الحاكمة**: الاستطلاع بفرع `probe-s228` بworkflow_dispatch (عرف س227 — لا تعرف main حمراء أبداً) ثم دفع main — **{ROUNDS}**.'
if OLD not in s: sys.exit('ERR: مرساة worklog (7) غابت')
s = s.replace(OLD, NEW)
# سطر الفهرس
OLD2 = 'والخضرة بجولة CI حصراً (استطلاع probe-s228 ثم main — الأرقام برقعة الإغلاق)'
NEW2 = f'والخضرة موثقة: #{PROBE_NUM} على {HEAD_SHA} ثم #{MAIN_NUM} على الرأس (عرف س227)'
if OLD2 not in s: sys.exit('ERR: مرساة worklog/index غابت')
s = s.replace(OLD2, NEW2)
wf(p, s); print('OK worklog')

# 2) 09 §69 — بند (6)
p = os.path.join(ROOT, 'docs', 'diqqah-v2.03', '09-release-plan-v2.03.md')
s = rw(p)
OLD3 = '**(6) الجولة والتوثيق**: استطلاع probe-s228 ثم main بأرقامهما برقعة الإغلاق'
NEW3 = f'**(6) الجولة والتوثيق**: **{ROUNDS}**'
if OLD3 not in s: sys.exit('ERR: مرساة 09 (6) غابت')
s = s.replace(OLD3, NEW3)
wf(p, s); print('OK 09')

# 3) خريطة الحالة — صف الفرع
p = os.path.join(ROOT, 'docs', 'manuals', '01-خريطة-الحالة.md')
s = rw(p)
OLD4 = '— **لا حكم معلَّق والجولة الحاكمة بفرع probe-s228 ثم main** —'
NEW4 = f'— **لا حكم معلَّق: #{MAIN_NUM} خضراء كاملة على الرأس (run {MAIN_ID}) بعد استطلاع #{PROBE_NUM} الأخضر** —'
if OLD4 not in s: sys.exit('ERR: مرساة state-map غابت')
s = s.replace(OLD4, NEW4)
wf(p, s); print('OK state-map')
print('CLOSURE OK — الجولات موثقة')
