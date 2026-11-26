#!/bin/bash
# متابعة حالة CI وحزم البناء لمستودع دِقَّة — الرمز من متغير البيئة
# GH_TOKEN حصراً ولا يُطبع أبداً (بروتوكول D-173 — س142: عنوان remote
# نظيف بلا رمز منذ س135، والترميز Bearer لخدمة الرموز دقيقة الترخيص
# github_pat_ — ترميز token القديم يخدم الكلاسيكية حصراً).
# الاستخدام: GH_TOKEN=... bash scripts/ci_status.sh [عدد التشغيلات]
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="M-Fadlalah-Ali/diqqah"
N="${1:-5}"
curl -sL -H "Authorization: Bearer $GH_TOKEN" \
  "https://api.github.com/repos/$REPO/actions/runs?per_page=$N" | \
python3 -c "
import json, sys
data = json.load(sys.stdin)
for run in data.get('workflow_runs', []):
    print(f\"#{run['run_number']} [{run['name']}] {run['head_sha'][:7]} {run['status']}/{run.get('conclusion')} id={run['id']}\")
"
