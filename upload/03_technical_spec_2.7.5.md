03_technical_spec_2.7.5.md — المواصفة التقنية

الإصدار: 2.7.5
التاريخ: 23 أكتوبر 2026
الحالة: النسخة المعتمدة.

يُحكَم هذا الملف بقواعد المقدمة (00_readme_2.7.5.md): لا يُعيد شرح قواعد العمل، ولا يتضمَّن رسائل واجهة. غايته تفصيل التخزين والتنفيذ فقط، بالإحالة إلى 01_product_spec_2.7.4.md عند الحاجة.

ملاحظة على المنصة: هذه المواصفة محايدة المنصة — تصف التخزين والقيود بصرف النظر عن بيئة التنفيذ. في الإصدار الحالي، التطبيق يُنفَّذ على PWA (React + TypeScript + IndexedDB). عند العودة إلى بيئة أخرى (كالـKotlin + Room + SQLite)، تُطبَّق هذه المواصفة على البيئة الجديدة، مع الفروق التالية:

· في PWA (IndexedDB/Dexie): يُستخدَم `camelCase` لأسماء الحقول (`isArchived`, `currencyId`, `sortOrder`)، لأنها الاصطلاح السائد في JavaScript، وأسماء الجداول تُبقى بصيغة الجمع.
· في Kotlin (Room + SQLite): يُستخدَم `snake_case` كما هو موصوف في هذه المواصفة.
· الفرق شكلي، لا دلالي. القيود والعلاقات نفسها.

---

1. قاموس الأسماء الموحد (Naming Convention)

· الجداول: بصيغة الجمع.
· المفاتيح الأجنبية: `[table]_id` (في SQLite) أو `[table]Id` (في PWA).
· أنواع الحركات: بصيغة `TYPE_NAME` (أحرف كبيرة).
· حقول الحالة: `status` للكيانات ذات الحالة التشغيلية، و`is_archived` (أو `isArchived` في PWA) للأرشفة.
· حقول التسلسل الزمني: `created_at` / `updated_at` (SQLite) أو `createdAt` / `updatedAt` (PWA)، كأعداد صحيحة (Unix timestamp، ميلي ثانية).
· التواريخ: TEXT بصيغة `YYYY-MM-DD`.
· المبالغ: أعداد صحيحة (INTEGER)، بدقة تخزين موحَّدة قدرها 4 خانات عشرية (المبلغ × 10^4)، بغض النظر عن خانات العملة المعروضة.
· حقول الترتيب: `sort_order` / `sortOrder` كأعداد صحيحة (INTEGER)، الافتراضي 0.

### 1.1 قاعدة PWA (الفروق عن SQLite)

**أسماء الحقول (`camelCase`):** في مسار PWA، تُستخدَم `camelCase` لأسماء الحقول في TypeScript وIndexedDB. مثال: `isArchived`، `currencyId`، `sortOrder`، `createdAt`، `updatedAt`. أسماء الجداول تبقى بصيغة الجمع (`wallets`, `currencies`).

**الأعلام المنطقية (`boolean`):** في PWA، تُخزَّن الأعلام المنطقية (`isArchived`, `isPrimary`, `allowNegative`, `isDeferred`) كـ`boolean` في TypeScript وIndexedDB، لا كأعداد `0/1`. هذا هو الأسلوب الطبيعي في JavaScript، والاستعلامات (`where('isArchived').equals(false)`) تعمل به.

**`undefined` بدل `NULL` في الفهارس الفريدة الجزئية:** IndexedDB لا يدعم Partial Indexes. الحقول التي تُستخدم للفهرسة الفريدة الجزئية (`primaryMarker`, `initialBalanceMarker`) تُخزَّن:
· القيمة الفعلية (1 أو `sourceWalletId`) للعناصر المعنية.
· `undefined` لغير المعنية. Dexie يستثنيها تلقائياً من الفهرس الفريد.

**`runInTransaction`:** Dexie's `transaction` signature معقّد، ويُنتج خطأ `TS2589` عند تمرير الجداول الديناميكية. الحل الموحَّد: دالة `runInTransaction<T>(fn)` تُغلّف كل معاملات الكتابة، بداخلها cast واحد لتمرير الجداول. كل خدمة تستدعي `runInTransaction`، لا `db.transaction` مباشرة.

### 1.2 رسائل الخدمات

جميع رسائل الخطأ والتأكيد الصادرة من طبقة الخدمات بالعربية الفصحى.

**النطاق:** يشمل `planService.ts`، `balanceService.ts`، `walletService.ts`، `debtService.ts`، `transferService.ts`، وبقية خدمات المجال.

**السبب:**
· توحيد اللغة على مستوى التطبيق.
· تسهيل عرض الرسائل مباشرة بلا حاجة إلى طبقة ترجمة.
· إزالة الازدواجية بين رسائل عربية في الواجهة وإنجليزية في الخدمة.

**مثال:**
· `balanceService.ts` يُطلق `HistoricalNegativeBalanceError` برسالة عربية: «المبلغ المطلوب (X) يتجاوز رصيد المحفظة المتاح (Y). لا يمكن التنفيذ.»

**قاعدة:** الرسائل التقنية الداخلية (Stack Traces) تبقى بالإنجليزية للتصحيح، لكن الرسائل التي تصل إلى المستخدم بالعربية.

---

2. مخطط العلاقات (ERD)

currencies (1) ──────── (N) wallets
│
▼
financial_events (N) ─────── (1) categories
│
▼
debts (1) ──────── (N) debt_payments
│
▼
people (1)
│
▼
financial_plans (1) ──────── (N) plan_payments

settings (جدول مستقل، لا علاقات)

ملاحظات:

· financial_events هو الجدول المركزي.
· wallets يتبع currencies.
· debts يتبع people وfinancial_events (عبر creation_event_id).
· debt_payments يربط debts بـ financial_events.
· financial_plans يتبع people (اختياري)، ومحفظتين (اختياريان).
· plan_payments يربط financial_plans بـ financial_events.
· settings جدول مستقل (key-value) للإعدادات العامة، بلا مفاتيح أجنبية.

---

3. الجداول (Tables)

3.1 العملات (currencies)

الحقل (عربي) | الحقل التقني | النوع | القيد
المعرِّف | id | INTEGER | PRIMARY KEY AUTOINCREMENT
الاسم | name | TEXT | NOT NULL
الكود | code | TEXT | NOT NULL, UNIQUE
الرمز | symbol | TEXT | —
اسم الجزء الكسري | fraction_name | TEXT | —
الخانات العشرية | decimal_places | INTEGER | NOT NULL, DEFAULT 2, CHECK (0–3) — **للعرض فقط**
مؤشر الأرشفة | is_archived | INTEGER/boolean | NOT NULL, DEFAULT 0/false
مؤشر الرئيسية | is_primary | INTEGER/boolean | NOT NULL, DEFAULT 0/false
**مؤشر الرئيسية الفريد** | **primary_marker** | **INTEGER** | **NULL/undefined، فريد جزئي**: يأخذ القيمة 1 للعملة الرئيسية النشطة، وNULL/undefined لغيرها. (**حقل تقني للفهرس** — يُملأ فقط عند التعيين، ولا يُعرَض في الواجهة.)
الترتيب | sort_order | INTEGER | DEFAULT 0
وقت الإنشاء | created_at | INTEGER | —
وقت التعديل | updated_at | INTEGER | —

ملاحظات:

· **لا تُدرَج أي عملة عند تهيئة قاعدة البيانات.** تُنشأ عملة واحدة فقط عند اكتمال شاشة الدخول الأولى (02 §4.0)، وهي العملة الرئيسية.
· `decimal_places` يُستخدَم **للعرض فقط**: يُقرَّب المبلغ المخزَّن (بـ4 خانات) إلى `decimal_places` عند العرض. التخزين والحسابات تعتمد على القيمة المخزَّنة كاملة.
· `sort_order` يحكم ترتيب العملات في الواجهة. **الأولى (أصغر `sort_order`) هي العملة الرئيسية** (`is_primary = 1`).
· لا حقل is_custom. العملة المخصصة والوحدة المخصصة تُخزَّنان بنفس البنية.
· **`primary_marker`** حقل تقني يستخدمه الفهرس الفريد لمنع وجود أكثر من عملة رئيسية نشطة واحدة. قيمته 1 للرئيسية النشطة، وNULL/undefined لغيرها. عند تغيير الرئيسية: يُفرَّغ أولاً (`undefined`) من القديمة، ثم يُملأ (`1`) في الجديدة، في المعاملة الذرية نفسها.

### قاعدة `is_primary` و`sort_order` و`primary_marker`

- عند إدخال عملة جديدة: `sort_order` = (MAX الحالي) + 1، `is_primary = false`، `primary_marker = undefined`.
- عند السحب والإفلات في تبويب «النشط»: يُعاد ترتيب العملات النشطة (`sort_order` من 0 تصاعدياً)، ثم تُرقَّم المؤرشفة بعدها (`newActiveCount + i`). ثم تُفرَّغ `primary_marker` من الرئيسية القديمة، ويُعيَّن `is_primary = true` و`primary_marker = 1` للعملة الأولى (في موضع 0).
- عند السحب والإفلات في تبويب «مؤرشف»: تُرقَّم المؤرشفة بدءاً من (أعلى `sort_order` للنشطة + 1). لا تُلمَس `is_primary` ولا `primary_marker` في هذا التبويب. ← يمنع وجود رئيسية مؤرشفة.
- عند السحب والإفلات في تبويب «الكل»: تُرقَّم كل العملات (`sort_order` من 0 تصاعدياً)، وتُعيَّن الرئيسية لأول عملة **نشطة** في القائمة، بغض النظر عن موضع السحب.
- الفهرس الفريد الجزئي (`primary_marker` = 1) يضمن عدم وجود أكثر من عملة واحدة بهذه الصفة، على مستوى قاعدة البيانات.

**`reorderCurrencies` بمعامل `mode`:**

تقبل الدالة معاملاً صريحاً `mode: 'active' | 'archived' | 'all'`:

· **`mode = 'active'`:** تُرتَّب العملات النشطة بدءاً من 0، ثم المؤرشفة بعدها (`newActiveCount + i`). تُفرَّغ `primaryMarker` من الرئيسية القديمة، ويُعيَّن `isPrimary = true` و`primaryMarker = 1` للعملة الأولى.
· **`mode = 'archived'`:** تُرتَّب المؤرشفة بدءاً من (أعلى `sort_order` للنشطة + 1). **لا تُلمَس `isPrimary` ولا `primaryMarker`.**
· **`mode = 'all'`:** تُرتَّب كل العملات بدءاً من 0، وتُعيَّن الرئيسية لأول عملة **نشطة** في القائمة.

هذا الفصل يمنع تداخل السلوك بين التبويبات الثلاثة.

### حقل `symbol` — الرموز المعتمدة

حقل `symbol` يحمل الرمز المعروض للعملة. للعملات التسع الافتراضية، القيم مثبَّتة:

| العملة | code | symbol |
|---|---|---|
| ليرة سورية | SYP | `ل.س` |
| دولار أمريكي | USD | `$` |
| يورو | EUR | `€` |
| ليرة تركية | TRY | `₺` |
| دينار أردني | JOD | `د.أ` |
| جنيه مصري | EGP | `ج.م` |
| درهم إماراتي | AED | `د.إ` |
| ريال سعودي | SAR | `ر.س` |
| دينار كويتي | KWD | `د.ك` |

· للعملات المخصصة والوحدات: يُدخِل المستخدم الرمز يدوياً عند الإنشاء.
· `symbol` للعرض فقط، لا يُستخدَم في الحسابات.

3.2 المحافظ (wallets)

الحقل (عربي) | الحقل التقني | النوع | القيد
المعرِّف | id | INTEGER | PRIMARY KEY AUTOINCREMENT
الاسم | name | TEXT | NOT NULL
العملة | currency_id | INTEGER | → currencies(id), NOT NULL
السماح بالسالب | allow_negative | INTEGER/boolean | NOT NULL, DEFAULT 0/false
مؤشر الأرشفة | is_archived | INTEGER/boolean | NOT NULL, DEFAULT 0/false
الترتيب | sort_order | INTEGER | DEFAULT 0
الملاحظات | notes | TEXT | —
وقت الإنشاء | created_at | INTEGER | —
وقت التعديل | updated_at | INTEGER | —

ملاحظات:

· لا يوجد حقل opening_balance. الرصيد الافتتاحي يُسجَّل كحركة INITIAL_BALANCE.
· **`sort_order` يحكم الترتيب.** المحفظة الأولى (أصغر `sort_order`) هي **المحفظة الافتراضية**، وتُقترَح مسبقاً عند تسجيل حركة جديدة.
· عرض الرصيد في قوائم الاختيار (وفق 02 §4.2.5) يُحسَب عند العرض، لا يُخزَّن في هذا الجدول.
· **قاعدة منع «محفظة مؤرشفة افتراضية»:** لا يجوز أن تكون المحفظة ذات `sort_order = 0` (الافتراضية) محفظة مؤرشفة. عند السحب والإفلات في تبويب «مؤرشف»، تُرقَّم المحافظ المؤرشفة بدءاً من (أعلى `sort_order` للنشطة + 1).

**`reorderWallets` بمعامل `mode`:**

· **`mode = 'active'`:** النشط من 0، المؤرشف بعده.
· **`mode = 'archived'`:** المؤرشف من (أعلى نشط + 1)، النشط لا يُمَس.
· **`mode = 'all'`:** السلوك الأصلي.

3.3 التصنيفات (categories)

الحقل (عربي) | الحقل التقني | النوع | القيد
المعرِّف | id | INTEGER | PRIMARY KEY AUTOINCREMENT
الاسم | name | TEXT | NOT NULL
الأيقونة | icon | TEXT | — (اسم الأيقونة في Material Icons، مثل `restaurant`، لا نص حر)
اللون | color | TEXT | —
النوع | type | TEXT | NOT NULL, CHECK (INCOME, EXPENSE, BOTH)
مؤشر الأرشفة | is_archived | INTEGER/boolean | NOT NULL, DEFAULT 0/false
الترتيب | sort_order | INTEGER | DEFAULT 0
وقت الإنشاء | created_at | INTEGER | —
وقت التعديل | updated_at | INTEGER | —

ملاحظات:

· القيم التقنية (INCOME, EXPENSE, BOTH) تبقى كما هي في قاعدة البيانات.
· **العربية في العرض: إيراد، مصروف، مشترك.**
· `sort_order` يحكم الترتيب **داخل كل نوع** (ثلاثة ترتيبات مستقلة: إيراد، مصروف، مشترك). الفهرس المركَّب `[type+sort_order]` يُسرِّع الاستعلام.
· التصنيف الأول في كل نوع (أصغر `sort_order` ضمن نوعه) هو **الافتراضي في قائمته**، ويُملأ مسبقاً عند تسجيل حركة من نوعه.
· الأيقونات الافتراضية مثبَّتة في 02 §4.6.4.

**دالة إعادة الترتيب مع أنواع مختلطة:**

عند استقبال قائمة من معرِّفات التصنيفات لإعادة الترتيب، يُتوقَّع أن تكون كلها من نوع واحد. لكن الحماية الدفاعية: العناصر غير المطابقة للنوع المطلوب **تُتجاهَل** (لا يُحدَّث `sortOrder` لها)، لكنها **تستهلك موضعاً في المصفوفة** (تزيد `i`). بهذا يبقى الترتيب صحيحاً للعناصر المطابقة، دون أن تُعطى عناصر أخرى ترتيباً خاطئاً.

**`reorderCategoriesByType` بمعامل `mode`:**

· **`mode = 'active'`:** التصنيفات النشطة من 0، المؤرشفة بعدها.
· **`mode = 'archived'`:** المؤرشفة من (أعلى نشط + 1)، النشط لا يُمَس.
· **`mode = 'all'`:** السلوك الأصلي.

تُرتَّب داخل كل نوع (إيراد، مصروف، مشترك) على حدة.

3.4 الأشخاص (people)

الحقل (عربي) | الحقل التقني | النوع | القيد
المعرِّف | id | INTEGER | PRIMARY KEY AUTOINCREMENT
الاسم | name | TEXT | NOT NULL
مؤشر الأرشفة | is_archived | INTEGER/boolean | NOT NULL, DEFAULT 0/false
وقت الإنشاء | created_at | INTEGER | —
وقت التعديل | updated_at | INTEGER | —

ملاحظات:

· لا يوجد `sort_order`. الترتيب **أبجدي (أ–ي)**، محسوب من `name` عند العرض (عبر `localeCompare` في PWA).
· لا سحب وإفلات للأشخاص.
· يُؤرشف إن ارتبط بديون، لا يُحذف.

3.4.1 الإعدادات العامة (settings)

جدول مستقل (key-value) لحفظ الإعدادات العامة. لا مفاتيح أجنبية.

الحقل (عربي) | الحقل التقني | النوع | القيد
المفتاح | key | TEXT | PRIMARY KEY
القيمة | value | TEXT | NOT NULL
وقت التعديل | updated_at | INTEGER | —

المفاتيح المعرَّفة:

المفتاح | القيمة | الافتراضي
default_event_type | 'EXPENSE' / 'INCOME' / 'TRANSFER' / 'RETURN' / 'LAST_USED' | 'EXPENSE'
last_event_type | 'EXPENSE' / 'INCOME' / 'TRANSFER' / 'RETURN' | 'EXPENSE'
category_required | '0' / '1' | '0'
default_transfer_fee_category_id | INTEGER بصيغة نصية | (فارغ حتى التعيين)
primary_currency_id | INTEGER بصيغة نصية | (يُضبط في شاشة الدخول الأولى)
first_day_of_week | '0' – '6' | (يُضبط في شاشة الدخول الأولى)
theme_mode | 'light' / 'dark' / 'system' | 'light'

ملاحظات على `default_event_type` و`last_event_type`:

· `default_event_type` يقبل الأنواع الأربعة (EXPENSE, INCOME, TRANSFER, RETURN) أو LAST_USED.
· LAST_USED ليس نوع حركة مالية، ولا يُدرَج ضمن الأنواع في financial_events. هو قيمة إعداد فقط.
· عند LAST_USED: يُحفَظ `last_event_type` مع الحركة المالية داخل المعاملة نفسها.
· LAST_USED الافتراضي عند عدم وجود حركة سابقة: EXPENSE.
· `last_event_type` يحمل دائماً أحد الأنواع الأربعة، ولا يحمل LAST_USED مطلقاً.

**قاعدة `getDefaultEventTypeSetting`:** عند قراءة قيمة غير معروفة من قاعدة البيانات (فساد بيانات، migration قديم)، تُعاد `'EXPENSE'` بدل رفع خطأ. هذا قرار دفاعي، ويمنع كسر التطبيق.

ملاحظة على `first_day_of_week`:

· الترميز داخلي (0 = الأحد … 6 = السبت)، مطابق لمعيار JavaScript (`getDay()`).
· **الترتيب المعروض للمستخدم يبدأ بالسبت** (02 §4.0 و§4.6.6): السبت، الأحد، الاثنين، الثلاثاء، الأربعاء، الخميس، الجمعة.
· **مرة قراءته:** الإعداد العام يُقرأ عند إنشاء خطة جديدة (يُخزَّن في `schedule_week_start` في الخطة)، ولا يُعاد قراءته لاحقاً. تغيير الإعداد لا يُعيد جدولة الخطط القائمة.

القيود المباشرة:

· key مفتاح رئيسي.
· value NOT NULL.
· القيم النصية مُتحقَّق منها في طبقة الخدمات، لا بقيد CHECK (لتسهيل التوسعة).

---

3.5 الحركات المالية (financial_events)

الجدول المركزي. يُسجِّل كل حركة مالية.

الحقل (عربي) | الحقل التقني | الهدف | ملاحظات
المعرِّف | id | — | تلقائي
النوع | type | — | أحد الأنواع التقنية (أدناه)
المحفظة المتأثرة | source_wallet_id | → wallets(id) | إلزامي
المحفظة الهدف | destination_wallet_id | → wallets(id) | في التحويل فقط
المبلغ | amount | — | موجب، بوحدة 10^4
المبلغ المستلم | destination_amount | — | يُملأ بشروط (أدناه)، بوحدة 10^4
رقم سعر الصرف | exchange_rate_value | — | عند اختلاف العملة
مقياس سعر الصرف | exchange_rate_scale | — | عند اختلاف العملة
التاريخ | date | — | فارغ في الرصيد البدئي فقط
التصنيف | category_id | → categories(id) | اختياري
الملاحظات | notes | — | اختياري
الحركة المرتبطة | related_event_id | → financial_events(id) | محجوز لميزة مؤجَّلة، لا يُملأ حالياً
الدين | debt_id | → debts(id) | في حركات الديون
معرِّف المجموعة | event_group_id | — | يربط الحركة برسومها، يقبل NULL
نوع الدين | debt_type | — | PAYABLE أو RECEIVABLE
اتجاه التسوية | adjustment_direction | — | INCREASE أو DECREASE
ملاحظة التسوية | adjustment_note | — | سبب التسوية
**مؤشر الرصيد البدئي الفريد** | **initial_balance_marker** | — | **INTEGER، NULL/undefined، فريد جزئي**: يأخذ قيمة `source_wallet_id` لحركة INITIAL_BALANCE فقط، وNULL/undefined لغيرها. (**حقل تقني للفهرس** — يمنع وجود أكثر من رصيد بدئي واحد لكل محفظة.)
وقت الإنشاء | created_at | — | تلقائي
وقت التعديل | updated_at | — | تلقائي

ملاحظات على الجدول:

· لا يوجد حقل حذف منطقي. الحذف نهائي.
· المبالغ بوحدة 10^4 (وفق §6.1).
· `related_event_id` يبقى فارغاً، تفادياً لـ migration لاحقة.
· **`initial_balance_marker`** حقل تقني يستخدمه الفهرس الفريد لمنع وجود أكثر من حركة INITIAL_BALANCE لكل محفظة. قيمته `source_wallet_id` للرصيد البدئي، وNULL/undefined لغيره. عند إنشاء محفظة جديدة برصيد افتتاحي: يُملأ في المعاملة الذرية نفسها.
· **`currency_id` غير مخزَّن.** عملة الحركة تُستنبط من عملة محفظتها عند العرض. هذا يعني أن أي عملية تحتاج عملة الحركة، تقرأ محفظتها أولاً. (تكلفة أداء مقبولة؛ تفادٍ لتكرار قد يفسد.)

**`event_group_id = id`:** يُولَّد بعد إنشاء الحركة الرئيسية. التسلسل: تُنشأ الحركة بلا `event_group_id`، ثم يُحدَّث الحقل بنفس قيمة `id`. هذا يربط حركة الرسوم (TRANSFER_FEE) بالتحويل أو بدفعة الدين، لأن كلتيهما تُنشأ في المعاملة الذرية نفسها بعد معرفة `id`.

### الأنواع — التقني مقابل المنطقي

في قاعدة البيانات **أحد عشر نوعاً تقنياً**. تُطابق الأنواع الاثني عشر المنطقية الموصوفة في 01 §4.1، مع فارق واحد: النوعان المنطقيان «اقتراض (دين عليّ)» و«إقراض (دين لي)» يُخزَّنان بنوع تقني واحد هو `DEBT_CREATION`، ويُفصَلان بحقل `debt_type` (`PAYABLE` للاقتراض، `RECEIVABLE` للإقراض). وباقي الأنواع تطابق واحداً بواحد.

الأنواع التقنية الأحد عشر:

· INCOME
· EXPENSE
· TRANSFER
· TRANSFER_FEE
· DEBT_CREATION (يُغطي الاقتراض والإقراض عبر `debt_type`)
· DEBT_PAYMENT
· DEBT_RECEIPT
· RETURN_EXPENSE
· RETURN_INCOME
· ADJUSTMENT
· INITIAL_BALANCE

تعريف «المحفظة المتأثرة»: المحفظة التي يقع عليها الأثر الأساسي للحركة، بغض النظر عن الاتجاه.

تعريف «المحفظة الهدف»: تُملأ في التحويل فقط. في بقية الأنواع، الربط عبر debt_id أو plan_payments.

تعريف «المبلغ المستلم» — الشرط مركّب:

يُملأ في ثلاث حالات:

1. تحويل: دائماً.
2. سداد / قبض دين: دائماً.
3. حركة مرتبطة بدفعة خطة: فقط إذا اختلفت عملة الخطة عن عملة المحفظة.

في بقية الأنواع، يبقى فارغاً.

القاعدة: يُثبَّت بعد الحساب والتقريب، ولا يُشتقّ عند العرض.

تعريف «سعر الصرف»:

· يُملأ عند اختلاف العملة فقط.
· يُخزَّن كعدد صحيح + مقياس.
· القيمة الفعلية = الرقم ÷ 10^المقياس.
· التفاصيل في §6.2.

القيود المباشرة في قاعدة البيانات:

· amount > 0.
· التاريخ مطلوب لكل الحركات ما عدا الرصيد البدئي.
· الأنواع محدَّدة بالقائمة.
· adjustment_direction وadjustment_note إلزاميان إذا كان type = 'ADJUSTMENT'.
· debt_type إلزامي إذا كان النوع من أنواع الديون.
· category_id إلزامي في TRANSFER_FEE.

القيود في طبقة الخدمات:

التاريخ:
· المستقبلي ممنوع للحركات الفعلية.
· الرصيد البدئي بلا تاريخ.

تطابق العملات:
· عملة المبلغ المستلم تطابق عملة الطرف المقابل.

العلاقة مع رسوم التحويل:
· إذا وُجدت رسوم، تُنشأ حركة مستقلة بـ`event_group_id` نفسه.
· لا تُعدَّل الرسوم مستقلةً.
· لا تُخصَم مرتين.

العلاقة مع الدين أو الخطة:
· سداد دين يحمل `debt_id` إلزاماً.
· دفعة خطة تُربط بحركة بالنوع الصحيح.
· لا يمكن وجود دفعتَي دين لنفس الحركة.

الرصيد السالب:
· التحقق من الرصيد قبل الحفظ.
· عند إعادة الحساب: مقارنة الحالة قبل التعديل بالحالة بعده، لا بحالة مثالية مطلقة.
· **القراءة الحاسمة يجب أن تحدث داخل نفس المعاملة التي ستكتب النتيجة** (وفق §6.16).

تعديل الحركات المرتبطة:
· المحفظة تُقفل في الحركات المرتبطة بخطة منفَّذة، عند التعديل من سجل الحركات.

تحديث `last_event_type`:
· إذا كان `default_event_type = 'LAST_USED'`، يُحدَّث `last_event_type` = نوع الحركة المحفوظة، في المعاملة الذرية نفسها مع حفظ الحركة.

**النقل بين العملات (تصحيح خطأ إدخال):**

عند تعديل حركة عامة (إيراد، مصروف، مرتجع) لتغيير محفظتها من عملة إلى أخرى:
· `amount` يبقى كما هو (بلا تغيير رقمي).
· لا يُملأ `exchange_rate_value` ولا `exchange_rate_scale`.
· العرض يستخدم عملة المحفظة الجديدة عند القراءة.
· لا معالجة خاصة. هذه ليست تحويلاً، بل تصحيح خطأ.

**دوال الرصيد البدئي:**

ثلاث دوال صريحة في طبقة الخدمات:

· `createInitialBalance(walletId, amount, notes?)` — تُنشئ حركة `INITIAL_BALANCE` في المعاملة الذرية نفسها مع المحفظة.
· `updateInitialBalance(walletId, newAmount, notes?)` — تُعدِّل الرصيد البدئي فقط.
· `deleteInitialBalance(walletId)` — تحذف حركة `INITIAL_BALANCE`.

تُستخدَم من شاشة إدارة المحفظة حصراً. **يُمنع** استخدام `updateStandardEvent` أو `deleteEvent` على الرصيد البدئي.

---

3.6 الديون (debts)

الحقل (عربي) | الحقل التقني | الهدف | ملاحظات
المعرِّف | id | — | تلقائي
الشخص | person_id | → people(id) | إلزامي
النوع | type | — | PAYABLE أو RECEIVABLE
المبلغ الأصلي | original_amount | — | موجب، بوحدة 10^4
العملة | currency_id | → currencies(id) | موروثة من المحفظة
المتبقي | remaining_amount | — | مخزَّن، يُعاد احتسابه، بوحدة 10^4
الحالة | status | — | active أو settled
مؤشر الأرشفة | is_archived | — | مستقل عن الحالة
تاريخ الاستحقاق | due_date | — | اختياري، بلا قيد زمني
الملاحظات | notes | — | اختياري
وقت الإنشاء | created_at | — | تلقائي
وقت التعديل | updated_at | — | تلقائي
حركة الإنشاء | creation_event_id | → financial_events(id) | فريد

القيود المباشرة:

· original_amount > 0.
· type من PAYABLE, RECEIVABLE.
· status من active, settled.
· remaining_amount ≥ 0.
· creation_event_id فريد.

القيود في طبقة الخدمات:

الإجراء الذري لإنشاء الدين:

1. إنشاء سجل الدين مؤقتاً (بلا creation_event_id).
2. إنشاء حركة الإنشاء.
3. تحديث سجل الدين بـcreation_event_id.
4. الالتزام.

علاقة الدين بالحركة:

· عملة الدين = عملة المحفظة المرتبطة بحركة الإنشاء.
· لا تُعدَّل عملة الدين مستقلةً.
· عند تغيير المحفظة (بلا دفعات)، تتغير العملة تبعاً.

حساب المتبقي:

عمود مخزَّن، يُعاد احتسابه وكتابته بالكامل من المصدر ضمن كل معاملة تمسّ دفعات الدين، ولا يُعدَّل تراكمياً.

المتبقي = المبلغ الأصلي − مجموع `destination_amount`

لكل حركات الدفع/القبض المرتبطة بهذا الدين (لا `amount`). السبب: في السداد بعملة مختلفة، `amount` بعملة المحفظة، و`destination_amount` بعملة الدين.

الدفعة التي تُنقص المتبقي:

نوع الدين | الدفعة
PAYABLE | DEBT_PAYMENT
RECEIVABLE | DEBT_RECEIPT

يُرفض أي دفع يجعل المتبقي سالباً.

عكس الحالة:

· عند وصول المتبقي إلى صفر: settled.
· عند أي تعديل يجعل المتبقي > 0: تعود active.

الأرشفة:

· لا تُغيِّر الحالة ولا المتبقي.
· إخفاء من العرض الافتراضي فقط.
· في الدين المؤرشف: الحقول التحريرية قابلة للتعديل (due_date، notes)، والحقول التشغيلية/المالية (original_amount، currency_id، type، status) ممنوعة.

التعديل:

· بلا دفعات: حرية كاملة.
· مع دفعات: المبلغ ≥ مجموع الدفعات. المحفظة والعملة والنوع: ممنوعة.

الحذف بلا دفعات:

1. حذف سجل الدين من debts.
2. حذف حركة الإنشاء من financial_events.
3. الالتزام.

السبب: `creation_event_id` تحت RESTRICT. حذف الحركة أولاً سيُرفض من قاعدة البيانات.

---

3.7 دفعات الديون (debt_payments)

الحقل (عربي) | الحقل التقني | الهدف | ملاحظات
المعرِّف | id | — | تلقائي
الدين | debt_id | → debts(id) | إلزامي
الحركة المالية | financial_event_id | → financial_events(id) | فريد، إلزامي
الملاحظات | notes | — | اختياري
وقت الإنشاء | created_at | — | تلقائي
وقت التعديل | updated_at | — | يتغير عند تعديل الحركة

القيود المباشرة: debt_id إلزامي؛ financial_event_id إلزامي وفريد.

القيود في طبقة الخدمات:
· نوع الحركة المرتبطة: DEBT_PAYMENT أو DEBT_RECEIPT.
· نوع الحركة يتوافق مع نوع الدين.
· debt_id في الحركة يطابق debt_id في الدفعة.
· الحركة المرتبطة بدفعة لا ترتبط بسجل دين آخر.

دلالة `destination_amount`: القيمة التي تغيّر رصيد الدين، بعملة الدين.

قاعدة المجموع: مجموع `destination_amount` لكل الدفعات ≤ المبلغ الأصلي.

الإجراء الذري لإضافة دفعة:

0. التحقق: الدين موجود وحالته active، النوع متوافق، المبلغ موجب، remaining_amount − المبلغ الجديد ≥ 0، العملة صحيحة، فحص الرصيد السالب التاريخي.
1. إنشاء حركة السداد.
2. إنشاء حركة رسوم التحويل إن وُجدت.
3. إنشاء سجل الدفعة.
4. إعادة احتساب remaining_amount.
5. تحديث حالة الدين.
6. الالتزام.

الإجراء الذري لتعديل دفعة:

0. التحقق: الدين موجود، المبلغ الجديد لا يجعل remaining_amount سالباً، فحص الرصيد السالب التاريخي.
1. تعديل الحركة المرتبطة (وفق 6.4 و6.5 من 01).
2. إن تغيّر مبلغ رسوم التحويل: يُعاد احتسابها، أو تُحذف/تُنشأ.
3. إعادة احتساب remaining_amount.
4. تحديث حالة الدين.
5. تحديث updated_at.
6. الالتزام.

الإجراء الذري لحذف دفعة:

0. التحقق: الدين موجود، فحص الرصيد السالب التاريخي.
1. حذف سجل الدفعة من debt_payments (أولاً، لتفادي قيد RESTRICT).
2. حذف حركة رسوم التحويل (بالـ`event_group_id` المرتبط بالحركة الرئيسية).
3. حذف حركة السداد.
4. إعادة احتساب remaining_amount.
5. تحديث حالة الدين (active إن كان المتبقي > 0، settled إن = 0).
6. الالتزام.

التزامن: جميع الإجراءات أعلاه تُنفَّذ في معاملة واحدة بمنع التداخل.

---

3.8 الخطط المالية (financial_plans)

الحقل (عربي) | الحقل التقني | الهدف | ملاحظات
المعرِّف | id | — | تلقائي
الاسم | name | — | إلزامي
النوع | type | — | installment, association, project, rent, saving
المبلغ الإجمالي | total_amount | — | موجب، بوحدة 10^4
العملة | currency_id | → currencies(id) | إلزامي
الاتجاه | direction | — | pay أو receive. اختياري
الطبيعة المحاسبية | accounting_nature | — | expense, income, transfer. اختياري
محفظة المصدر | wallet_source_id | → wallets(id) | اختياري
محفظة الهدف | wallet_target_id | → wallets(id) | اختياري
الشخص/الجهة | person_id | → people(id) | اختياري
الحالة | status | — | active, frozen, completed
مؤشر الأرشفة | is_archived | — | مستقل عن الحالة
**حقول التسوية** | **settlement_amount** | **INTEGER، NULL** | **موجب = حسم، سالب = زيادة. NULL = بلا تسوية.**
**حقول التسوية** | **settlement_note** | **TEXT، NULL** | **مبرر التسوية، اختياري.**
ملاحظة الحالة | status_note | — | اختياري
تاريخ البداية | start_date | — | اختياري
تاريخ النهاية | end_date | — | اختياري
الملاحظات | notes | — | اختياري
طريقة الجدولة | schedule_method | — | auto أو manual. NOT NULL
الفاصل | schedule_frequency | — | daily / weekly / semi_monthly / monthly / quarterly
الموضع | schedule_position | — | first أو last
عدد الدفعات | schedule_count | — | إجمالي دفعات الخطة. موجب
تاريخ بداية الجدولة | schedule_start_date | — | YYYY-MM-DD
أول يوم من الأسبوع | schedule_week_start | — | 0–6
وقت الإنشاء | created_at | — | تلقائي
وقت التعديل | updated_at | — | تلقائي

القيود المباشرة:

· total_amount > 0.
· type محدَّد بالقيم الخمس.
· status من active, frozen, completed. **لا حالة `settled` منفصلة.**
· direction من pay, receive إن وُجد.
· **accounting_nature من القيم الثلاث** (expense, income, transfer) إن وُجدت.
· end_date ≥ start_date إن وُجدا.
· schedule_method NOT NULL، من auto, manual.
· **settlement_amount:** إن كان NULL، فلا توجد تسوية. إن كان قيمة، فالخطة مُسوَّاة.
· **الانسجام:** إن كان `status = 'completed'` و`settlement_amount` NULL، فالخطة اكتملت طبيعياً أو أُغلقت إدارياً. لا تمييز بينهما في الحقل — الإغلاق الإداري لا يُسجَّل تلقائياً.

القيود الشرطية على حقول الجدولة:

الشرط | القيود
schedule_method = 'auto' | schedule_frequency, schedule_position, schedule_count, schedule_start_date إلزامية
schedule_method = 'auto' مع schedule_frequency = 'weekly' | schedule_week_start إلزامي
schedule_method = 'auto' مع فاصل آخر | schedule_week_start = NULL
schedule_method = 'manual' | جميع حقول الجدولة = NULL

قيد إضافي: schedule_count ≥ عدد الدفعات المنفَّذة — ينطبق على الخطط التلقائية فقط.

ترميز أيام الأسبوع (schedule_week_start):

القيمة | اليوم
0 | الأحد
1 | الاثنين
2 | الثلاثاء
3 | الأربعاء
4 | الخميس
5 | الجمعة
6 | السبت

ملاحظة: الترميز داخلي فقط. العرض للمستخدم يبدأ بالسبت (وفق §3.4.1).

القيود في طبقة الخدمات:

المحافظ والعملة:
· المحفظتان مختلفتان إن حُدِّدتا معاً.
· عند التنفيذ بمحفظتين: عملة الخطة تطابق إحداهما، وإلا يُرفض.

**حفظ المحفظة عند أول تنفيذ:** إذا كانت الخطة بلا محفظة محدَّدة (`wallet_source_id` و`wallet_target_id` كلاهما فارغ)، فإن `executePlanPayment` تحفظ المحفظة المختارة في `wallet_source_id` في المعاملة الذرية نفسها، قبل إنشاء الحركة. لا يُشترَط تحديد المحفظة عند إنشاء الخطة.

قيد المجموع:
· الأنواع الأربعة: مجموع expected_amount = المبلغ الإجمالي.
· الادخار: نسبة تقدُّم فقط.

**التنفيذ (`executePlanPayment`):**
· محفظتان: تحويل كامل.
· محفظة واحدة: الطبيعة المحاسبية محدَّدة بثلاث قيم (`expense`, `income`, `transfer`). التخطيط إلى EventType:
  · `expense` → `EXPENSE`
  · `income` → `INCOME`
  · `transfer` → `TRANSFER`
· **لا `debt` ولا `debt_receipt` ولا `none`.** الديون لها مسارها المستقل (شاشة الديون).

تعديل المبلغ الإجمالي:

0. التحقق: المبلغ الجديد ≥ مجموع الدفعات المنفَّذة، وتوجد دفعة غير منفَّذة.
1. حساب الفرق.
2. التوزيع بالتساوي على الدفعات غير المنفَّذة (تشمل المتوقَّعة والمؤجَّلة).
3. تحميل فارق التقريب على آخر دفعة غير منفَّذة (ترتيب: expected_date تصاعدي، ثم created_at، ثم id).
4. الفحص النهائي: كل دفعة بقيمة > 0. وإلا يُرفض التعديل.
5. الالتزام.

الاتجاه والطبيعة المحاسبية:
· اختياريان في الخطة.
· يُطلبان عند التنفيذ إن كانا فارغين.
· بعد وجود دفعة منفَّذة: يُمنع تغييرهما.

الأرشفة:

· يمكن أرشفة خطة في أي حالة.
· إن كانت active: تُغيَّر حالتها التشغيلية إلى frozen في العملية الذرية نفسها، مع تحذير مسبق.
· إن كانت frozen أو completed: لا تتغير حالتها التشغيلية.
· إلغاء الأرشفة لا يُلغي التجميد.
· الخطة المؤرشفة لا يمكن تنفيذ دفعاتها، ولا تعديل دفعاتها، ولا حذفها.
· في الخطة المؤرشفة: الحقول التحريرية قابلة للتعديل (name، notes)، والحقول التشغيلية/المالية (total_amount، حقول الجدولة، status، wallet_source_id، wallet_target_id) ممنوعة.

الحالات التشغيلية والانتقالات:

من | إلى | الشرط
active | frozen | تجميد يدوي
active | frozen | أرشفة تلقائية
active | completed | تلقائياً عند اكتمال الدفعات (مجموع = إجمالي)
active | completed | بتسوية (`settlement_amount` يُسجَّل)
active | completed | بإغلاق إداري (بلا `settlement_amount`)
frozen | active | إلغاء التجميد
completed | active | حذف دفعة منفَّذة تُخِلّ بالمساواة
completed | active | إلغاء التسوية أو الإغلاق

**قاعدة اكتمال تلقائي بدون تسوية:** تُغلَق الخطة تلقائياً إلى `completed` فقط إذا اكتملت كل الدفعات ومجموعها = الإجمالي، أو إذا كان نوعها «ادخار» وتحقق `paid ≥ total`. غير ذلك، تبقى `active` حتى يقرر المستخدم (تسوية أو إغلاق).

**قاعدة اكتمال الادخار:**
`مجموع المبالغ المنفَّذة ≥ المبلغ الإجمالي` → `completed`.

**لا إغلاق تلقائي عند التجاوز أو النقصان:** عند انحراف، تبقى الخطة `active` حتى يقرر المستخدم. يُعرَض تنبيه وشارة.

**الدوال المخصَّصة:**

**`settlePlan(planId, amount, note?)`:**
· `amount`: عدد صحيح. موجب = حسم، سالب = زيادة.
· يُسجِّل `settlementAmount` و`settlementNote`.
· يُحوِّل `status` إلى `'completed'`.
· كل ذلك في معاملة ذرية واحدة.

**`closePlan(planId)`:**
· `settlementAmount` يبقى `null`.
· يُحوِّل `status` إلى `'completed'`.
· الإغلاق الإداري لا يُوثَّق بمبلغ.

**`cancelSettlement(planId)`:**
· يُمسح `settlementAmount` و`settlementNote`.
· يُعيد `status` إلى `'active'`.
· الدفعات غير المنفَّذة تعود «متوقَّعة».

**`cancelClosure(planId)`:**
· يُعيد `status` إلى `'active'`.
· لا يمسّ `settlementAmount` (لأنه `null` أصلاً).

**`maybeCompletePlan(plan)`:**
· **الادخار:** `status = 'completed'` إذا `paid >= total`.
· **الأنواع الأربعة:** `status = 'completed'` إذا تحقق شرطان معاً:
  · كل الدفعات لها `financialEventId` غير فارغ.
  · `sum(expectedAmount) === totalAmount`.
· **خلاف ذلك:** لا تغيير.
· **مراجَع ومنفَّذ:** الكود يفحص الشرطين معاً، ويشترط `every` على كل دفعة. موثَّق ومطابق.

**`deferOneInterval(lastDate, frequency)`:**
· **`daily`:** `lastDate` + 1 يوم.
· **`weekly`:** `lastDate` + 7 أيام.
· **`semi_monthly`:** التبديل بين 1 و16:
  · إن كان اليوم 1 → 16 من الشهر نفسه.
  · إن كان اليوم 16 → 1 من الشهر التالي.
  · إن كان يوماً آخر (حالة `last` في آخر المدة) → يُعاد الحساب وفق القاعدة.
· **`monthly`:** `lastDate` + 1 شهر، مع قاعدة الأشهر القصيرة.
· **`quarterly`:** `lastDate` + 3 أشهر، مع قاعدة الأشهر القصيرة.
· **بلا فاصل (يدوي):** `lastDate` + 1 يوم.

**`deferPayment(planId, paymentId, ...)`:**
· تُحدِّد `referenceDate` (آخر دفعة غير منفَّذة).
· تستدعي `deferOneInterval(referenceDate, plan.scheduleFrequency)`.
· تُحدِّث `expectedDate` و`isDeferred`.
· **مراجَع ومنفَّذ:** الدالة تستدعي `deferOneInterval` فعلاً. لا ازدواجية، لا كود ميت. موثَّق ومطابق.

**التسوية والإغلاق:**

**التسوية:** إجراء مالي إداري على الخطة النشطة عند وجود انحراف. يُسجِّل:
· `settlement_amount` (موجب = حسم، سالب = زيادة).
· `settlement_note` (اختياري).

النتيجة: `status = 'completed'`. الدفعات غير المنفَّذة تبقى في الجدول.

**الإغلاق:** إجراء إداري. `settlement_amount` يبقى NULL. النتيجة: `status = 'completed'`. الدفعات غير المنفَّذة تبقى.

**إلغاء التسوية أو الإغلاق:** تعود الخطة `active`. `settlement_amount` يُمسح (إن وُجد). الدفعات غير المنفَّذة تعود «متوقَّعة».

**وسم الدفعات غير المنفَّذة عند الإغلاق أو التسوية:** تبقى الدفعات في الجدول، وتُستنتَج حالتها من `status = 'completed'` للخطة، مع عدم وجود `financial_event_id`. لا حقل صريح جديد — الحالة مشتقّة.

---

3.9 دفعات الخطط (plan_payments)

الحقل (عربي) | الحقل التقني | الهدف | ملاحظات
المعرِّف | id | — | تلقائي
الخطة | plan_id | → financial_plans(id) | إلزامي
الحركة المالية | financial_event_id | → financial_events(id) | فريد، ON DELETE SET NULL
التاريخ المتوقَّع | expected_date | — | إلزامي
المبلغ المتوقَّع | expected_amount | — | موجب، بعملة الخطة، بوحدة 10^4
مؤشر التأجيل | is_deferred | — | افتراضي: false
الملاحظات | notes | — | اختياري
وقت الإنشاء | created_at | — | تلقائي
وقت التعديل | updated_at | — | تلقائي

ملاحظات على الحقول المحذوفة:
· actual_date: يُشتقّ من تاريخ الحركة المرتبطة.
· actual_amount: يُشتقّ من الحركة المرتبطة.

القيود المباشرة:

· plan_id إلزامي.
· financial_event_id يقبل NULL، وفريد إن وُجد.
· expected_amount > 0.
· is_deferred من (true, false).
· لا يمكن أن يكون financial_event_id غير فارغ مع is_deferred = true.

القيود في طبقة الخدمات:

حالات الدفعة:

الحالة | الشرط
منفَّذة | financial_event_id غير فارغ
متوقَّعة | financial_event_id فارغ، is_deferred = false
مؤجَّلة | financial_event_id فارغ، is_deferred = true
متأخرة | expected_date < اليوم + غير منفَّذة، غير مؤجَّلة (مؤشر بصري)
**مُغلَقة ضمن خطة مُغلَقة** | الخطة `completed`، الدفعة بلا `financial_event_id`

**حالة الدفعة «مُغلَقة ضمن خطة مُغلَقة»** مشتقّة: تُحسَب عند العرض من `plan.status === 'completed'` و`financial_event_id === null`. لا حقل صريح.

المبلغ المنفَّذ:

يُشتقّ من الحركة المرتبطة، حسب الطرف الذي يطابق عملة الخطة:

الحالة | المصدر
عملة الخطة = عملة المحفظة المصدر | amount
عملة الخطة = عملة المحفظة الهدف | destination_amount

إن لم تطابق أي منهما: يُرفض التنفيذ.

فحص الأرشفة:

· فحص is_archived = 0 في إجراءات تعديل/حذف الدفعة، من أي مسار.
· الخطة المؤرشفة: دفعاتها للعرض فقط. لا تعديل، ولا حذف، ولا تنفيذ.

الإجراء الذري لتنفيذ دفعة:

0. التحقق: الدفعة غير منفَّذة، الخطة active وغير مؤرشفة، عملة الخطة تطابق إحدى المحفظتين (إن كانتا محددتين)، فحص الرصيد السالب التاريخي.
1. **إن كانت الخطة بلا محفظة: حفظ المحفظة المختارة في `wallet_source_id` في المعاملة نفسها.**
2. إنشاء الحركة الرئيسية.
3. إن وُجدت رسوم: إنشاء حركة الرسوم المستقلة بـevent_group_id نفسه.
4. ربط الدفعة بالحركة.
5. إعادة فحص حالة الخطة (→ completed إن تحقق شرط الاكتمال).
6. الالتزام.

الإجراء الذري لتعديل دفعة منفَّذة:

0. التحقق: الدفعة منفَّذة، الخطة غير مؤرشفة، المبلغ الجديد لا يُخِلّ بالقيود، فحص الرصيد السالب التاريخي.
1. تعديل الحركة المرتبطة (وفق 6.4 و6.5 من 01).
2. إن تغيّر مبلغ رسوم التحويل: يُعاد احتسابها، أو تُحذف/تُنشأ.
3. إعادة فحص حالة الخطة.
4. تحديث updated_at.
5. الالتزام.

قاعدة: تعديل الدفعة من هذا المسار يُتيح تعديل المحفظة (بخلاف التعديل من سجل الحركات).

الإجراء الذري لحذف دفعة منفَّذة (من شاشة الخطة):

0. التحقق: الخطة غير مؤرشفة، فحص الرصيد السالب التاريخي.
1. تصفير financial_event_id في الدفعة.
2. حذف حركة الرسوم (بالـevent_group_id المرتبط بالحركة الرئيسية).
3. حذف الحركة الرئيسية.
4. إعادة فحص حالة الخطة (→ active إن كانت completed ونقص المجموع).
5. الالتزام.

الإجراء الذري لحذف حركة مرتبطة بخطة (من سجل الحركات):

0. التحقق: الخطة غير مؤرشفة، فحص الرصيد السالب التاريخي.
1. تصفير financial_event_id في الدفعة.
2. حذف الحركة (وفق قواعد 12.2 من 01).
3. إعادة فحص حالة الخطة.
4. الالتزام.

الإجراء الذري لتأجيل دفعة:

1. التحقق: الدفعة متوقَّعة، الخطة غير مؤرشفة.
2. حساب `referenceDate` (آخر expected_date بين الدفعات غير المنفَّذة، بـMAX، مع كسر التعادل: created_at ثم id).
3. استدعاء `deferOneInterval(referenceDate, plan.scheduleFrequency)` لحساب `newDate`.
4. تحديث expected_date وis_deferred.
5. الالتزام.

الإجراء الذري لإلغاء التأجيل:

1. التحقق: الدفعة مؤجَّلة، الخطة غير مؤرشفة.
2. رفع is_deferred = false.
3. طلب expected_date جديد.
4. الالتزام.

الإجراء الذري لإعادة التوليد التلقائي:

0. التحقق:
   · طريقة الجدولة في الخطة = auto.
   · عدد الدفعات الجديدة (schedule_count − عدد المنفَّذة) > 0، إن كان المتبقي موجباً.
   · لا يوجد فحص للرصيد السالب التاريخي في إعادة التوليد، لأن الدفعات المحذوفة غير منفَّذة (بلا أحداث مالية).
1. حذف جميع الدفعات غير المنفَّذة المرتبطة بالخطة.
2. حساب تاريخ بداية الدفعات الجديدة:
   · إن وُجدت دفعة منفَّذة: الأبعد بين (schedule_start_date، أول تاريخ مطابق للموضع بعد آخر دفعة منفَّذة).
   · إن لم توجد دفعة منفَّذة: schedule_start_date وحده.
3. توليد الدفعات الجديدة وفق:
   · schedule_frequency، schedule_position، schedule_count، schedule_start_date، schedule_week_start (للأسبوعي).
4. توزيع المبلغ المتبقي (الإجمالي − مجموع المنفَّذ) بالتساوي، وفق آلية 3.8 (التوزيع، تحميل فارق التقريب، فحص القيم الموجبة).
5. تحديث حالة الخطة (→ completed إن تحقق الشرط).
6. الالتزام.

الدفعات المنفَّذة لا تُمسّ في كل الخطوات.

إعادة الجدولة:

· من داخل شاشة تعديل الخطة.
· تعديل تواريخ ومبالغ وأعداد الدفعات غير المنفَّذة.
· الدفعات المنفَّذة لا تُمس.
· عند تعديل المبالغ، يُحدَّث total_amount وفق آلية 3.8.
· لا تغيِّر حالة الخطة.

قيد المجموع: انظر 3.8.

---

4. ملخّص القيود (Constraints Summary)

ملاحظة: هذا الفصل فهرس مرجعي سريع. المصدر التفصيلي لكل قيد هو قسمه الخاص في §3.

الجدول | القيود
currencies | decimal_places بين 0 و3 (للعرض)، code فريد، is_archived وis_primary boolean في PWA، فهرس فريد جزئي على `primary_marker`: عملة رئيسية نشطة واحدة، sort_order يحكم الترتيب
wallets | allow_negative وis_archived boolean في PWA، sort_order يحكم الترتيب (الأولى = الافتراضية)، منع محفظة مؤرشفة افتراضية
categories | type من (INCOME, EXPENSE, BOTH)، is_archived boolean، فهرس مركَّب [type+sort_order]
people | is_archived boolean، الترتيب أبجدي من name
settings | key مفتاح رئيسي، value NOT NULL، القيم النصية مُتحقَّق منها في طبقة الخدمات
financial_events | amount > 0، type محدَّد، التاريخ ≤ اليوم للحركات الفعلية، adjustment_direction وadjustment_note إلزاميان إذا كان type = ADJUSTMENT، debt_type إلزامي إذا كان النوع من أنواع الديون، category_id إلزامي في TRANSFER_FEE، فهرس فريد جزئي على `initial_balance_marker`، currencyId غير مخزَّن
debts | type من (PAYABLE, RECEIVABLE)، original_amount > 0، remaining_amount ≥ 0، status من (active, settled)، creation_event_id فريد
debt_payments | financial_event_id فريد، إلزامي
financial_plans | type محدَّد، total_amount > 0، status من (active, frozen, completed)، direction من (pay, receive) إن وُجد، accounting_nature من (expense, income, transfer) إن وُجدت، end_date ≥ start_date إن وُجدا، schedule_method NOT NULL من (auto, manual)، القيود الشرطية على حقول الجدولة، schedule_count ≥ عدد الدفعات المنفَّذة (للخطط التلقائية فقط)، settlement_amount يقبل NULL، settlement_note يقبل NULL
plan_payments | expected_amount > 0، is_deferred boolean، financial_event_id فريد إن وُجد، لا يمكن أن يكون financial_event_id غير فارغ مع is_deferred = true

---

5. الفهارس الموصى بها (Recommended Indexes)

الحركات المالية:
· financial_events(source_wallet_id, date)
· financial_events(destination_wallet_id)
· financial_events(type)
· financial_events(category_id)
· financial_events(debt_id)
· financial_events(event_group_id)

الديون:
· debts(person_id)
· debts(status)
· debt_payments(debt_id)

الخطط:
· financial_plans(status)
· financial_plans(schedule_method)
· plan_payments(plan_id)
· plan_payments(financial_event_id)

الترتيب:
· wallets(sort_order)
· categories(type, sort_order)
· currencies(sort_order)

فهارس فريدة جزئية:
· currencies(primary_marker) بشرط `primary_marker = 1`.
· financial_events(initial_balance_marker) بشرط `initial_balance_marker IS NOT NULL`.
· financial_events(source_wallet_id, type) بشرط `type = 'INITIAL_BALANCE'`.

ملاحظة على IndexedDB:
· IndexedDB لا يدعم الفهارس الجزئية (Partial Indexes). الحل المُتبَع: استخدام حقل `primary_marker` / `initial_balance_marker` بقيمة `undefined` للعناصر غير المعنية (تُستثنى تلقائياً من الفهرس الفريد)، وفهرس فريد عادي `&primary_marker` / `&initial_balance_marker`.

---

6. ملاحظات التنفيذ (Implementation Notes)

6.0 مصدر الحقيقة للمبالغ

الحقل | موضعه | معناه
amount | financial_events | المبلغ بعملة المحفظة المصدر (المبلغ الصادر)
destination_amount | financial_events | المبلغ بعملة الطرف المقابل (المحفظة الهدف، أو الدين، أو الخطة)
expected_amount | plan_payments | المبلغ المخطَّط، بعملة الخطة
actual_plan_amount | مشتقّ (لا يُخزَّن) | المبلغ المنفَّذ، بعملة الخطة. يُقرأ من amount أو destination_amount وفق الطرف الذي يطابق عملة الخطة
income_expense_detailed_income_rows | مشتقّ (لا يُخزَّن) | صفوف الإيرادات في التقرير المفصَّل
income_expense_detailed_expense_rows | مشتقّ (لا يُخزَّن) | صفوف المصروفات في التقرير المفصَّل

6.1 المبالغ (Amounts)

· INTEGER، بوحدة **10^4** (4 خانات عشرية موحَّدة).
· مثال: 100.50 (أياً كانت عملته) → يُخزَّن `1005000`.
· مثال: 12581.44 ليرة سورية → يُخزَّن `125814400`.
· دقة التخزين موحَّدة عبر كل العملات، بغض النظر عن خانات العملة المعروضة.
· **لا سقف لعدد الخانات التي يُدخلها المستخدم في الواجهة.** عند الحفظ، يُقرَّب صامتاً إلى 4 خانات عشرية. مثال: إدخال `12581.44444` يُحفَظ `12581.4444`.

### سقف التخزين الآمن

`MAX_SAFE_STORED_AMOUNT = 900,719,925,474` (تسعمائة مليار، وسبع مئة وتسعة عشر مليوناً، وتسع مئة وخمسة وعشرون ألفاً، وأربع مئة وأربعة وسبعون).

**السبب:** JavaScript `number` له حد أقصى آمن (`Number.MAX_SAFE_INTEGER = 9,007,199,254,740,991`). عند تقسيمه على وحدة التخزين (10^4)، يكون السقف النظري ~900 مليار. أي قيمة تتجاوز هذا السقف تُخزَّن بدقة غير موثوقة.

**القاعدة:** أي إدخال يتجاوز `MAX_SAFE_STORED_AMOUNT` يُرفض. يُعرَض للمستخدم تحذير بحد التخزين.

### العرض مقابل التخزين

· **التخزين**: القيمة مضروبة في `10^4`.
· **العرض**: القيمة مضروبة في `10^decimal_places` للعملة، مع التقريب نحو +∞ عند النصف.
· **الحسابات**: على القيمة المخزَّنة كاملة.
· **نافذة التعديل**: تُعرَض القيمة كما حُفِظت (بأعلى دقة)، ليعرف المستخدم ما سيُحفَظ فعلاً.
· **القوائم والتقارير**: تُعرَض القيمة بعد التقريب إلى `decimal_places` للعملة.

### دوال التحويل المعتمدة

في `mathService.ts`:
· `toStoredAmount(input: number | string): number` — يحوّل المدخل إلى وحدة 10^4 مع التقريب نحو +∞ عند النصف.
· `toDisplayAmount(value: number): number` — يحوّل من وحدة 10^4 إلى القيمة العشرية.
· `roundMinorUnits(value: number): number` — تقريب نحو +∞ عند النصف.
· `roundStoredToDisplay(storedAmount, decimalPlaces): number` — تقريب للعرض.

**قاعدة إلزامية:** يُمنع استخدام `Math.round` مباشرةً لتحويل المبالغ. يُستخدَم `toStoredAmount` دائماً، لضمان الاتساق.

6.2 سعر الصرف (Exchange Rate)

· عدد وحدات عملة الطرف المقابل لكل وحدة من عملة المصدر.
· المعادلة (بالقيم الفعلية، لا المخزَّنة):

destination_amount = (amount − رسوم التحويل بعملة المصدر) × exchange_rate

· يُخزَّن كعدد صحيح مُقيَّس (value + scale).
· ينطبق على: التحويلات، سداد الديون، دفعات الخطط بعملة مختلفة.

6.3 مقياس سعر الصرف عند غياب السعر المُدخَل

مع التخزين الموحَّد (4 خانات لكل المبالغ)، تُبسَّط الصيغة:

rate_scale = ⌈log10(amount_stored)⌉ + 1

· `amount_stored` = المبلغ المخزَّن (بعملة المصدر، بوحدة 10^4).
· الحد الأدنى للنتيجة: 10.
· السبب: المبالغ المُدخَلة من المستخدم نادراً ما تتجاوز 3 خانات فعلية، لكن التخزين بـ4 خانات يمنح هامشاً كافياً. المقياس الناتج من هذه الصيغة يضمن عدم فقدان قيمة التحويل بسبب التقريب.

مثال: amount_stored = 1300000000 (130000 ليرة × 10^4).
· `log10(1300000000) ≈ 9.11`
· `⌈9.11⌉ = 10`
· `rate_scale = 11`
· الحد الأدنى (10) لا يُطبَّق.
· السعر يُخزَّن بعدد صحيح + مقياس 11.

6.4 تأكيد أثر TRANSFER_FEE

· أثرها على الرصيد: صفر.
· السبب: أثرها النقدي محتسب أصلاً ضمن المبلغ الصادر.
· لا تُستخدم مرة ثانية في حساب الرصيد، حتى عند إعادة بناء الرصيد التاريخي.

6.5 التواريخ (Dates)

· TEXT بصيغة YYYY-MM-DD.
· التخزين: صيغة ثابتة.
· الحركات الفعلية: date ≤ اليوم.
· الخطط: تواريخ متوقَّعة قد تكون مستقبلية.
· الرصيد البدئي: date = NULL.
· `today` يُحدَّد بتوقيت الجهاز المحلي (Device Local Time).

**العرض:**

صيغة العرض: `اسم اليوم: DD-MM-YYYY` (بدون أقواس). مثال: `الثلاثاء: 06-10-2026`.

التخزين يبقى `YYYY-MM-DD`. يُستخدَم `formatDateDisplay` لعرض التاريخ في كل مكان.

6.6 الرصيد الافتتاحي (Initial Balance)

· يُعامَل كأول حركة، بغض النظر عن أي تاريخ.
· يُستثنى من ترتيب التواريخ (يُقدَّم على كل الحركات).
· لا يظهر حقل التاريخ عند إدخاله أو تعديله.
· لا يُعدَّل من سجل الحركات، بل من شاشة إدارة المحفظة فقط.
· تُستخدَم الدوال الثلاث الصريحة (`createInitialBalance`, `updateInitialBalance`, `deleteInitialBalance`).

6.7 الأرشفة (Archiving)

· is_archived للكيانات فقط، لا للحركات.
· الحركات تُحذف نهائياً.
· أرشفة خطة نشطة: تُحدَّث is_archived = 1 وstatus = 'frozen' في المعاملة الذرية نفسها.
· أرشفة خطة frozen أو completed: is_archived فقط.
· إلغاء الأرشفة: is_archived = 0 فقط. لا يُلغي التجميد.
· الخطة المؤرشفة: دفعاتها للعرض فقط، لا تعديل ولا حذف ولا تنفيذ.
· في الكيانات ذات الترتيب (العملات، المحافظ، التصنيفات): لا يُغيَّر `sort_order` عند الأرشفة. العنصر المؤرشف يحتفظ بموضعه.

6.8 قيود الحذف (Delete Constraints)

· ON DELETE RESTRICT بشكل عام.
· استثناء موثَّق: plan_payments.financial_event_id يقبل ON DELETE SET NULL.
· قاعدة عامة: لا يعتمد النظام على ON DELETE CASCADE في العمليات المحاسبية. الحذف المركّب يتم من طبقة الخدمات داخل معاملة ذرية.

6.9 التصنيف الافتراضي لأجرة التحويل

قاعدة: حقل category_id إلزامي في حركات TRANSFER_FEE.

عند التغيير:

SELECT COUNT(*) FROM financial_events
WHERE type = 'TRANSFER_FEE'
AND category_id != :new_default_category_id

إذا كانت النتيجة > 0، تُعرَض رسالة التنبيه الديناميكي.

6.10 التأجيل (Postponement)

· expected_date الجديد يُحسَب بـ`deferOneInterval` (انظر §3.8)، بمقدار الفاصل المُعتمَد في الخطة.
· is_deferred = 1.
· expected_amount لا يتغير.
· total_amount لا يتغير.
· `deferPayment` تستدعي `deferOneInterval` فعلاً. لا ازدواجية.

6.11 التقريب (Rounding)

· يُقرَّب الناتج إلى أقرب وحدة من عملة الحقل الذي سيُخزَّن فيه.
· عند النصف، يكون الاتجاه نحو +∞ (Half Up Toward +∞). مثال: -10.5 → -10، لا -11.
· التقريب **مرحلتان**:

المرحلة الأولى — عند الحفظ:
· يُقرَّب المبلغ المُدخَل إلى 4 خانات عشرية (وحدة التخزين).
· لا إشعار للمستخدم بهذا التقريب (صامت).

المرحلة الثانية — عند العرض:
· يُقرَّب المبلغ المخزَّن إلى `decimal_places` للعملة.
· مثال: 12581.4444 ليرة سورية (0 خانة عرض) → يُعرَض `12581`.

6.12 الذرية (Transactions)

جميع العمليات المركبة تُنفَّذ في معاملة ذرية واحدة:

التهيئة:
· إنشاء العملة الرئيسية + المحفظة الأولى + 18 تصنيفاً افتراضياً.

التحويلات:
· إنشاء تحويل + رسومه.
· تعديل تحويل + إعادة حساب رسومه.

الديون:
· إنشاء دين + حركته + تحديث creation_event_id.
· إضافة دفعة دين + حركتها + حركة TRANSFER_FEE + تحديث remaining_amount.
· تعديل دفعة دين + تحديث الحركة والديون + تحديث TRANSFER_FEE.
· حذف دفعة دين + حذف debt_payments + حذف TRANSFER_FEE + حذف الحركة الرئيسية + إعادة حساب المتبقي.
· حذف دين بلا دفعات + حذف حركة الإنشاء.

**الخطط:**
· تنفيذ دفعة خطة (مع حفظ المحفظة عند أول تنفيذ، إن كانت الخطة بلا محفظة).
· تعديل دفعة خطة منفَّذة.
· حذف دفعة خطة منفَّذة.
· حذف حركة مرتبطة بخطة.
· تأجيل دفعة (بمقدار الفاصل، عبر `deferOneInterval`).
· إلغاء التأجيل.
· إعادة الجدولة اليدوية.
· إعادة التوليد التلقائي.
· تعديل total_amount + إعادة توزيع الفرق.
· أرشفة خطة نشطة + تحديث status إلى frozen.
· **`settlePlan`:** تحديث `settlementAmount` و`settlementNote` و`status = 'completed'`.
· **`closePlan`:** تحديث `status = 'completed'` بلا `settlementAmount`.
· **`cancelSettlement`:** إعادة `status = 'active'`، مسح `settlementAmount` و`settlementNote`.
· **`cancelClosure`:** إعادة `status = 'active'`.

الحركات العامة:
· تعديل حركة + إعادة احتساب الأرصدة التراكمية اللاحقة.
· حذف حركة + إعادة احتساب الأرصدة التراكمية اللاحقة.
· إنشاء حركة + تحديث last_event_type في settings (إن كان default_event_type = 'LAST_USED').

**التسويات:**
· إنشاء حركة ADJUSTMENT + التحقق من الرصيد السالب (عند DECREASE) — القراءة والفحص داخل المعاملة نفسها.

**النسخ الاحتياطي:**
· **الاستيراد:** استبدال كل الجداول في معاملة واحدة شاملة (لكل جدول: `clear()` ثم `bulkAdd` من ملف النسخة). لا استبدال جزئي.
· **نسخة الأمان التلقائية:** قبل مسح البيانات الحالية، تُستدعى `exportBackup(isPreRestore: true)`، ويُنتَج ملف باسم `financial-backup-pre-restore-YYYY-MM-DD-HH-mm.json`. يُنزَّل تلقائياً، ثم تبدأ عملية المسح. كل ذلك ضمن تدفق الاستيراد.

الترتيب:
· إعادة ترتيب الكيانات (عملات، محافظ، تصنيفات) + تحديث sort_order + تحديث is_primary وprimary_marker (للعملات فقط).

6.13 معادلة الرصيد الحالي

الرصيد_الحالي = مجموع(أثر_الحركة) لجميع حركات المحفظة

نوع الحركة | أثر المحفظة
INCOME | +amount
EXPENSE | -amount
TRANSFER (في المصدر) | -amount
TRANSFER (في الهدف) | +destination_amount
TRANSFER_FEE | 0
DEBT_CREATION (PAYABLE) | +amount
DEBT_CREATION (RECEIVABLE) | -amount
DEBT_PAYMENT (PAYABLE) | -amount
DEBT_RECEIPT (RECEIVABLE) | +amount
RETURN_EXPENSE | +amount
RETURN_INCOME | -amount
INITIAL_BALANCE | +amount
ADJUSTMENT | +amount إن INCREASE، -amount إن DECREASE

6.14 الترتيب التاريخي الحتمي

عند إعادة حساب الأرصدة التراكمية:

1. date تصاعدي.
2. ثم created_at تصاعدي.
3. ثم id تصاعدي.

الرصيد البدئي يُعامَل كأول حركة دائماً.

6.15 فحص الرصيد السالب التاريخي

· تُعاد حوسبة الأرصدة اللاحقة بعد أي تعديل أو حذف.
· يُفحَص كل رصيد لحظي.
· إن ظهر رصيد سالب في محفظة لا تسمح به: يُرفض التعديل.

قاعدة المقارنة: يقارن الفحص الحالة قبل التعديل بالحالة بعده.

ملاحظة: هذا الفحص طبقة دفاعية للحالات الموروثة. في التشغيل الطبيعي، وفق 3.3 من 01، لا يُفترض وجود محفظة بـallow_negative = 0 ورصيد سالب تاريخي.

**`HistoricalNegativeBalanceError`:**

اسم الصنف الصريح في `balanceService.ts`. الرسالة الموحَّدة بالعربية:

> «المبلغ المطلوب (X) يتجاوز رصيد المحفظة المتاح (Y). لا يمكن التنفيذ.»

حيث `X` هو المبلغ المطلوب، و`Y` هو الرصيد المتاح. تُملأ القيمتان في وقت رفع الخطأ.

**الوصول إلى الرسالة:** الواجهة تقرأ `error.message` مباشرة، بلا حاجة إلى رمز أو ترجمة.

6.16 التزامن (Concurrency) والقراءة الحاسمة

في PWA (IndexedDB/Dexie):
· IndexedDB يوفر معاملات ذرية (transactions) بمستوى عزل Serializable.
· يُستخدَم معاملة واحدة بكتابة شاملة لكل عملية مركّبة.
· **قاعدة القراءة الحاسمة:** أي قراءة تؤثر في قرار السماح بالعملية **يجب أن تحدث داخل نفس المعاملة التي ستكتب النتيجة**.
· الدالة `validateHistoricalBalance` في `balanceService.ts` **نقيّة** (تستقبل `wallet` و`currentEvents` كمعاملات)، والمستدعي مسؤول عن جلب البيانات داخل `executeTransaction`.

**نمط `runInTransaction`:**

لتجاوز خطأ TypeScript `TS2589` الذي ينشأ من تمرير الجداول الديناميكية إلى `db.transaction`، تُستخدَم دالة موحَّدة:

    async function runInTransaction<T>(fn: () => Promise<T>): Promise<T> {
      return db.transaction('rw', db.tables, async () => {
        return fn();
      });
    }

كل خدمة تستدعي `runInTransaction`، لا `db.transaction` مباشرة. الـ`cast` واحد في مكان واحد، بلا تكرار.

في Kotlin (Room + SQLite) عند العودة:
· يُستخدَم BEGIN IMMEDIATE (أو ما يعادله) للحصول على قفل كتابة مبكر.
· يُضاف busy_timeout مع سياسة إعادة محاولة عند حدوث database is locked.
· قاعدة القراءة الحاسمة نفسها.

6.17 ترقية قاعدة البيانات

**ترقية قاعدة البيانات إلى 2.7.0:**

عند ترقية قاعدة البيانات من 2.6.1 إلى 2.7.0:

1. إضافة الحقلين التقنيين إن لم يكونا موجودين:
   · `currencies.primary_marker` (INTEGER، يقبل NULL).
   · `financial_events.initial_balance_marker` (INTEGER، يقبل NULL).

2. فهارس فريدة:
   · فهرس فريد على `currencies.primary_marker`.
   · فهرس فريد على `financial_events.initial_balance_marker`.
   · فهرس مركَّب على `categories(type, sort_order)`.
   · فهرس على `wallets.sort_order`.

3. تهيئة الحقلين:
   · `primary_marker = 1` للعملة الرئيسية النشطة حالياً (is_primary = 1)، وNULL لغيرها.
   · `initial_balance_marker = source_wallet_id` لكل حركة INITIAL_BALANCE، وNULL لغيرها.

4. في PWA (Data version 4): استُخدم `undefined` بدل NULL في IndexedDB.

5. التحقق من سلامة السجلات.

6. الالتزام.

**ترقية قاعدة البيانات إلى 2.7.1:**

لا ترقية مطلوبة. تصحيح توثيقي.

**ترقية قاعدة البيانات إلى 2.7.2:**

تغييرات جوهرية:
1. **`financial_plans`:** إضافة حقلي `settlement_amount` (INTEGER، NULL) و`settlement_note` (TEXT، NULL).
2. **`financial_plans.accounting_nature`:** حذف القيم `debt`, `debt_receipt`, `none` من القيد. ترقية السجلات القائمة:
   · أي سجل بـ`accounting_nature = 'debt'` أو `'debt_receipt'` أو `'none'` → يُحوَّل إلى `NULL`.
   · لا تُغيَّر حالات الخطط القائمة، ولا حركاتها.
3. **`boolean` في PWA:** تحويل الأعلام المنطقية من `0/1` إلى `true/false`.
   · الحقول المتأثرة: `currencies.is_archived`, `currencies.is_primary`, `wallets.allow_negative`, `wallets.is_archived`, `categories.is_archived`, `people.is_archived`, `plan_payments.is_deferred`.
   · في PWA (IndexedDB): استخدام `boolean` مباشرة.
4. **`undefined` بدل `NULL`:** لـ`primary_marker` و`initial_balance_marker`. السجلات التي كانت تحمل `NULL` تصبح `undefined`.

في PWA (Data version 5): تُنفَّذ الترقية عبر معاملة واحدة شاملة. الاستعلامات للتحقق:
· `SELECT COUNT(*) FROM financial_plans WHERE accounting_nature IN ('debt', 'debt_receipt', 'none')` — تُتوقَّع 0 بعد الترقية.
· التحقق من فهارس `primary_marker` و`initial_balance_marker`.

**ترقية قاعدة البيانات إلى 2.7.3:**

لا ترقية مطلوبة في البنية. الإصدار توثيقي.

**ترقية قاعدة البيانات إلى 2.7.4:**

لا ترقية مطلوبة. الإصدار توثيقي وبنيوي في الواجهة فقط. Data version تبقى 5.

**ترقية قاعدة البيانات إلى 2.7.5:**

لا ترقية مطلوبة. الإصدار توثيقي وبنيوي في الواجهة (هوية بصرية) والنسخ الاحتياطي فقط. Data version تبقى 5.

**نموذج Dexie/IndexedDB (للمرجع):**

    this.version(1).stores({
      currencies: '++id, &code, is_archived, is_primary, &primary_marker, sort_order',
      wallets: '++id, currency_id, is_archived, sort_order',
      categories: '++id, type, is_archived, [type+sort_order]',
      people: '++id, name, is_archived',
      settings: '&key',
      financial_events: '++id, type, source_wallet_id, destination_wallet_id, date, category_id, debt_id, event_group_id, &initial_balance_marker, [source_wallet_id+date], created_at',
      debts: '++id, person_id, type, status, is_archived, &creation_event_id, currency_id',
      debt_payments: '++id, debt_id, &financial_event_id',
      financial_plans: '++id, type, status, is_archived, schedule_method, currency_id, person_id',
      plan_payments: '++id, plan_id, &financial_event_id, expected_date, is_deferred',
    });

في SQLite، تُنفَّذ الترقيات السابقة عبر إنشاء جدول جديد بالبنية المحدَّثة، ثم نسخ البيانات مع القيمة الافتراضية، ثم إعادة التسمية. كل ذلك في معاملة ذرية واحدة.
في PWA (IndexedDB)، تُنفَّذ الترقيات عبر معاملة واحدة شاملة، بحيث تكون كل التعديلات ذرية.

---

7. الأدوات المساعدة (Utilities)

7.1 `formatWalletOption(name, balance, currency)`

في `utils/format.ts`.

**الوظيفة:** تُنتج نصاً موحَّداً لعرض المحفظة في القوائم المنسدلة، مع عزل اتجاه النص (Bidi Isolation).

**التنفيذ:**

    function formatWalletOption(name, balance, currency) {
      const formatted = `${name} — ${balance} ${currency.symbol}`;
      return `\u2068${formatted}\u2069`;
    }

**السبب:** في القوائم المنسدلة ذات الاتجاه RTL، قد تختلط الأرقام والعملة والاسم. عزل Bidi يضمن عرضاً صحيحاً في المتصفحات كلها.

**النطاق:** يُستخدَم في كل قائمة منسدلة تعرض محفظة مع رصيدها.

7.2 `formatDateDisplay(date)`

في `utils/format.ts`.

**الوظيفة:** تُنتج نص التاريخ بصيغة `اسم اليوم: DD-MM-YYYY` من تاريخ مخزَّن `YYYY-MM-DD`.

**التنفيذ:**

    function formatDateDisplay(date: string): string {
      const d = parseISO(date);
      const dayName = format(d, 'EEEE', { locale: ar });
      const formatted = format(d, 'dd-MM-yyyy');
      return `${dayName}: ${formatted}`;
    }

**النطاق:** كل مكان يعرض تاريخاً.

7.3 `formatAmountWithSymbol(amount, currency)`

**الوظيفة:** عرض المبلغ يليه رمز العملة بحجم أصغر في السطر نفسه.

**النطاق:** الرئيسية (بطاقة المحافظ)، بطاقات المعلومات في الشاشات التفصيلية.

7.4 `amountInput.ts`

في `utils/amountInput.ts`:

· `formatAmountInput(value)` — يُضيف فاصلة الألوف للعرض.
· `parseAmountInput(str)` — يُزيل الفواصل ويُعيد رقماً.

7.5 `dateRange.ts`

في `src/app/utils/dateRange.ts`.

**الوظيفة:** المصدر الوحيد لتصفية التاريخ في كل التطبيق.

**الواجهات:**

· `quickRangeFullLabel(range)` — التسمية الكاملة: «الكل»، «هذا اليوم»، «هذا الأسبوع»، «هذا الشهر»، «هذا العام»، «مخصص».
· `quickRangeShortLabel(range)` — التسمية المختصرة للزر: «الكل»، «اليوم»، «الأسبوع»، «الشهر»، «السنة»، «مخصص».
· `resolveQuickRange(range)` — يُعيد `{ from, to }` بناءً على القيمة.
· `WEEK_START_DAY = 6` — السبت (وفق JavaScript `getDay()`: 6 = السبت).

**قاعدة:** لا تُعرِّف أي شاشة تصفية تاريخ بنفسها. تُستدعى التسميات والسلوك من هذا الملف.

7.6 `backupService.ts` (مُحدَّث في 2.7.5)

في `services/backupService.ts`.

**الواجهات:**

· `exportBackup(isPreRestore?: boolean)` — يُجمِّع كل الجداول، ويُنتج ملف JSON. اسم الملف: `financial-backup-YYYY-MM-DD.json` (أو `financial-backup-pre-restore-YYYY-MM-DD-HH-mm.json` إن كان `isPreRestore = true`).
· `importBackup(file)` — يقرأ ملف JSON، يتحقق من صحته (`schemaVersion`)، ثم يستبدل كل البيانات في معاملة ذرية واحدة.

**حقوق الملف:** `schemaVersion`، `appVersion`، `exportedAt`، ثم كل جدول بمفاتيحه.

**التحقق من الإصدار:**
· إن كان `file.schemaVersion > currentSchemaVersion`: يُرفض الملف.
· إن كان `file.schemaVersion < currentSchemaVersion`: يُحاوَل الترقية في الذاكرة (سلسلة migrations على البيانات المستوردة).

**حد أقصى لحجم الملف:** 100 ميجابايت. أكبر من ذلك → رفض.

**النسخة التلقائية:** قبل الاستبدال، تستدعي `importBackup` الدالة `exportBackup(true)` تلقائياً، وتُنزِّل الملف الناتج، ثم تمسح البيانات وتستورد. هذا لا يمكن تجاوزه من الواجهة (يُنفَّذ في الخدمة).

**دين تقني:** `BACKUP_APP_VERSION` في الملف لا يزال `'2.7.1'`؛ يُحدَّث إلى `'2.7.5'`.

---

نهاية 03_technical_spec_2.7.5.md — الإصدار 2.7.5.