#!/bin/bash
# متابعة تشغيل GitHub Actions للتشغيلة المحددة — الرمز من متغير البيئة
# GH_TOKEN الآني حصراً (بروتوكول D-173: يُلصق لحظة الاستخدام ولا يُخزن).
# الاستخدام: GH_TOKEN=... bash scripts/poll_gh_run.sh <run_id> [أقصى_ثوان]
set -uo pipefail
# درس س154 الموثق: الاسم القديم mfadlalah كان يسقط على تحويل 301 المتزامن
# (بلا -L فتعاد JSON التوجيه لا بيانات التشغيل — «?/?» طوال الدورة) —
# الاسم الكامل + -L حصراً (س151: التحويل المتزامن مُتبَع ب-L).
REPO="M-Fadlalah-Ali/diqqah"
RUN_ID="${1:?run_id required}"
MAXS="${2:-540}"
ELAPSED=0
while [ $ELAPSED -lt "$MAXS" ]; do
  JSON=$(curl -sL -H "Authorization: Bearer $GH_TOKEN" \
    "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID")
  STATUS=$(echo "$JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','?'))")
  CONCL=$(echo "$JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('conclusion','?'))")
  echo "[$ELAPSED s] $STATUS/$CONCL"
  if [ "$STATUS" = "completed" ]; then
    echo "RUN_DONE conclusion=$CONCL"
    exit 0
  fi
  sleep 30
  ELAPSED=$((ELAPSED+30))
done
echo "RUN_STILL_RUNNING"
exit 1
