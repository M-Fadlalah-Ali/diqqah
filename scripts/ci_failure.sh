#!/bin/bash
# تفاصيل مهام تشغيل CI وسجل المهمة الفاشلة — الرمز لا يُطبع أبداً.
# الاستخدام: bash scripts/ci_failure.sh <run_id>
set -euo pipefail
cd "$(dirname "$0")/.."
TOKEN=$(git remote get-url origin | sed -n 's|https://x-access-token:\([^@]*\)@.*|\1|p')
REPO="mfadlalah/diqqah"
RUN_ID="${1:?run id}"
JOBS=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID/jobs")
echo "$JOBS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for job in data.get('jobs', []):
    print(f\"job {job['id']} [{job['name']}] {job['status']}/{job.get('conclusion')}\")
"
FAILED=$(echo "$JOBS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bad = [j['id'] for j in data.get('jobs', []) if j.get('conclusion') not in ('success', 'skipped', None)]
print(bad[0] if bad else '')
")
if [ -n "$FAILED" ]; then
  echo "=== سجل المهمة الفاشلة $FAILED (آخر الأسطر المتعلقة) ==="
  curl -sL -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO/actions/jobs/$FAILED/logs" > /tmp/ci_log.txt || true
  rg -n "error|Error|ERROR|FAILED|Exception|failed|failed_|Some tests" /tmp/ci_log.txt | tail -40 || tail -30 /tmp/ci_log.txt
fi
