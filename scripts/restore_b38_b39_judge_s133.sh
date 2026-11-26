#!/bin/bash
# restore_b38_b39_judge_s133.sh — س134 (2026-11-14)
# استعادة أثرات b38 وb39 الضائعة محلياً بتدوير صندوق بيئة العمل + حكم الجولة المؤجلة على دفع س133.
#
# لماذا هذه الأداة؟ تدوير الصندوق بعد س133 أذهب من download/ ملفَي b39 وملفَي b38
# (أحدث ملف باقٍ فيه بتاريخ 2026-11-13 00:25) وأذهب معها أداة
# /home/z/my-project/scripts/verify_b39_markers.py (خارج المستودع — قابلة للضياع) —
# فبُنيت هذه الأداة داخل المستودع نفسه لتصمد بتدويرات الصندوق القادمة.
#
# الفيصل في صحة الاستعادة: مطابقة sha256 وال حجم البايتي حرفياً للبصمات الموثقة
# بسجل س130 (b38) وس132 (b39) — وتطابق البصمة يعني تطابق البايتات كلها، وهو أقوى
# من إعادة فحص العلامات (67/67 بس132) إذ يثبت أنها ذات الملفات التي فُحصت يومها.
# أرقام الأثرات (artifact ids) من سجل التشغيل نفسه: b39 = التشغيل 43474511386،
# وb38 = التشغيل 43408256064 — صلاحية أثرات GitHub 90 يوماً من بنائها.
#
# الاستخدام: GH_TOKEN=<الرمز المدوَّر> bash scripts/restore_b38_b39_judge_s133.sh
# الرمز من متغير البيئة حصراً (بروتوكول D-173): لا يُطبع ولا يُكتب في أي ملف.
set -euo pipefail

REPO="M-Fadlalah-Ali/diqqah"
DL_DIR="/home/z/my-project/download"
S133_SHA="4c57d4e5cac82622d1cda9de86c263cab9a360e3"   # دفع س133 (دفعة توثيق D-208)
API="https://api.github.com/repos/$REPO"

# ─── القيم المرجعية الموثقة (س130 لـb38 وس132 لـb39) ───
# الصيغة: artifact_id|الملف_الداخلي|الاسم_القياسي|الحجم_بالبايت|بصمة_sha256
SPECS=(
  "14062363490|app-arm64-v8a-release.apk|diqqah-android-v0.2.03-b39.apk|31566797|7bb095183680f3c4913971b9290cdef972e4430a20a6fc6b863fd146f59efb97"
  "14063316004|diqqah-windows-x64.zip|diqqah-windows-v0.2.03-b39.zip|18373653|8bc33c144626ee6d842169a8e719f983c35078480738fa4d68ee00d820d26682"
  "14028228588|app-arm64-v8a-release.apk|diqqah-android-v0.2.03-b38.apk|31501261|669791bb26c66bf3f413aeb257eb2c2c889bcc7000e97e5be24b240b946778e6"
  "14029085676|diqqah-windows-x64.zip|diqqah-windows-v0.2.03-b38.zip|18367202|36c4ad1469ef7c510a352a41ffbf3e6ea5aa97e46c263079151a8872223238e3"
)

FAIL=0

# ─── 0) بوابات البدء ───
if [ -z "${GH_TOKEN:-}" ]; then
  echo "خطأ: متغير البيئة GH_TOKEN فارغ — الصق الرمز المدوَّر لحظة الاستخدام (بروتوكول D-173)" >&2
  exit 2
fi
AUTH="Authorization: Bearer $GH_TOKEN"

mkdir -p "$DL_DIR"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "$AUTH" "$API")
if [ "$CODE" != "200" ]; then
  echo "خطأ: الرمز لا يفتح المستودع (HTTP $CODE) — تأكد أنه المدوَّر الصحيح" >&2
  exit 2
fi
echo "الرمز صالح ويفتح المستودع — يبدأ العمل"

# ─── 1) حكم الجولة المؤجلة على دفع س133 (4c57d4e) ───
echo
echo "═══ 1) حكم الجولة المؤجلة على دفع س133 (4c57d4e — آخر جولة حُكمت: 265 على 332df8f) ═══"
RUNS=$(curl -s -H "$AUTH" "$API/actions/runs?branch=main&per_page=50")
MATCH=$(echo "$RUNS" | jq -r --arg sha "$S133_SHA" \
  '.workflow_runs[] | select(.head_sha == $sha) | "\(.run_number)|\(.id)|\(.status)|\(.conclusion // "pending")|\(.name)"')

if [ -z "$MATCH" ]; then
  echo "⚠ لم يُعثر على جولة على رأس 4c57d4e ضمن آخر 50 تشغيلة — تحقق يدوي: scripts/ci_status.sh"
  echo "  (احتمال: تجاوزت الجولات الأحدث حد الصفحة، أو لم تنطلق جولة على الدفع)"
  FAIL=1
else
  GREEN=1
  while IFS='|' read -r NUM RID STATUS CONCL NAME; do
    echo "الجولة #$NUM [$NAME] — run id $RID — status=$STATUS conclusion=$CONCL"
    if [ "$STATUS" != "completed" ] || [ "$CONCL" != "success" ]; then GREEN=0; fi
  done <<< "$MATCH"
  # تفصيل مهام أول جولة مطابقة (بنمط ci_watch.sh)
  RID=$(echo "$MATCH" | head -1 | cut -d'|' -f2)
  echo "── مهام الجولة رقم $RID:"
  curl -s -H "$AUTH" "$API/actions/runs/$RID/jobs?per_page=10" | \
    jq -r '.jobs[] | "    \(.name) | \(.status) | \(.conclusion // "-") | خطوات=\([.steps[]? | select(.status == "completed")] | length)/\(.steps | length)"'
  if [ "$GREEN" = "1" ]; then
    echo "═══ الحكم: خضراء كاملة على 4c57d4e — التزام س133 ينقضي عرف الدورة ═══"
  else
    echo "═══ الحكم: ليست خضراء بعد — تُجلب سجلات الإخفاق: bash scripts/ci_failure.sh $RID ═══"
    FAIL=1
  fi
fi

# ─── 2) استعادة أثرات b39 ثم b38 بالبصمات الموثقة ───
echo
echo "═══ 2) استعادة الأثرات الأربعة من تشغيلات CI إلى download/ ═══"
for SPEC in "${SPECS[@]}"; do
  ID="${SPEC%%|*}"; REST="${SPEC#*|}"
  INNER="${REST%%|*}"; REST="${REST#*|}"
  TARGET="${REST%%|*}"; REST="${REST#*|}"
  ESIZE="${REST%%|*}"
  ESHA="${REST#*|}"

  echo "── $TARGET (أثر رقم $ID)"
  DONE=""
  if [ -f "$DL_DIR/$TARGET" ]; then
    ASIZE=$(stat -c '%s' "$DL_DIR/$TARGET")
    ASHA=$(sha256sum "$DL_DIR/$TARGET" | awk '{print $1}')
    if [ "$ASIZE" = "$ESIZE" ] && [ "$ASHA" = "$ESHA" ]; then
      echo "    حاضر سليماً بالبصمة الموثقة — لا يُنزَّل من جديد"
      DONE=1
    else
      echo "    الموجود لا يطابق البصمة (حجم $ASIZE/بصمة ${ASHA:0:12}…) — يُستبدل"
    fi
  fi

  if [ -z "$DONE" ]; then
    TMP=$(mktemp -d)
    # الأثر يُنزَّل عبر تحويلة موقعة: نجلب عنوان التحويل أولاً ثم ننزل بلا ترويسة
    # التوثيق (الترويسة على الرابط الموقَّع تُفسده) — درس توثيقي لهذه الأداة.
    URL=$(curl -s -o /dev/null -w '%{redirect_url}' -H "$AUTH" "$API/actions/artifacts/$ID/zip")
    if [ -z "$URL" ]; then
      echo "    خطأ: تعذر جلب رابط الأثر $ID (HTTP) — انتهت صلاحيته (90 يوماً) أو الرمز بلا صلاحية actions:read" >&2
      FAIL=1; rm -rf "$TMP"; continue
    fi
    curl -sL "$URL" -o "$TMP/artifact.zip"
    unzip -o -q "$TMP/artifact.zip" -d "$TMP/x"
    INNER_PATH=$(find "$TMP/x" -type f -name "$INNER" | head -1)
    if [ -z "$INNER_PATH" ]; then
      echo "    خطأ: الملف الداخلي المتوقع «$INNER» غير موجود بالأثر" >&2
      FAIL=1; rm -rf "$TMP"; continue
    fi
    mv -f "$INNER_PATH" "$DL_DIR/$TARGET"
    rm -rf "$TMP"

    ASIZE=$(stat -c '%s' "$DL_DIR/$TARGET")
    ASHA=$(sha256sum "$DL_DIR/$TARGET" | awk '{print $1}')
    if [ "$ASIZE" = "$ESIZE" ] && [ "$ASHA" = "$ESHA" ]; then
      echo "    CLEAN — $ASIZE بايتاً والبصمة ${ASHA:0:12}… مطابقة للموثق بسجل الإغلاق"
    else
      echo "    خطأ: عدم تطابق! الحجم $ASIZE (المنتظر $ESIZE) والبصمة $ASHA" >&2
      FAIL=1
    fi
  fi
done

# ─── 3) الخلاصة ───
echo
if [ "$FAIL" = "0" ]; then
  echo "═══ الخلاصة: الحكم منفَّذ والأثرات الأربعة سليمة بالبصمات في download/ ═══"
  echo "المعلق بعدها على المالك: تثبيت b39 فوق b38 بلا حذف — وكلمة بدء دفعة GFS (b40)"
  exit 0
else
  echo "═══ الخلاصة: شيء لم يكتمل — راجع الأسطر المعلَّمة بخطأ أعلاه ═══"
  exit 1
fi
