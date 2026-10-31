#!/bin/bash
# متابعة حالة CI وحزم البناء لمستودع دِقَّة — الرمز يُقرأ من remote ولا يُطبع أبداً.
# الاستخدام: bash scripts/ci_status.sh [عدد التشغيلات]
set -euo pipefail
cd "$(dirname "$0")/.."
TOKEN=$(git remote get-url origin | sed -n 's|https://x-access-token:\([^@]*\)@.*|\1|p')
REPO="mfadlalah/diqqah"
N="${1:-5}"
curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/$REPO/actions/runs?per_page=$N" | \
python3 -c "
import json, sys
data = json.load(sys.stdin)
for run in data.get('workflow_runs', []):
    print(f\"#{run['run_number']} [{run['name']}] {run['head_sha'][:7]} {run['status']}/{run.get('conclusion')} id={run['id']}\")
"
