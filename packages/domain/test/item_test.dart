import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

void main() {
  group('مفتاح الكود (D-073) — تقليم الفراغات حصراً بلا نزع أصفار', () {
    test('الفراغات الطرفية تقلم ولا يُمس جسم الكود', () {
      expect(itemSkuKey('  A-12 '), 'A-12');
      expect(itemSkuKey('0100'), '0100', reason: 'نزع الأصفار قرار أطراف '
          'خاص (D-063) لا يُسقط على كود صنف متنوع');
      expect(itemSkuKey(''), '');
    });
  });

  group('نزاهة الإدخال D-170/D-171 (س56 بكلمة المالك)', () {
    ExistingItem oil(int id) =>
        ExistingItem(id: id, sku: 'A/1', name: 'زيت', isActive: true);

    ItemDraft draft({String sku = 'Z-12', String name = 'سكر'}) =>
        ItemDraft(sku: sku, name: name, kind: ItemKind.good, baseUnitId: 1);

    test('sanitizeFreeName (D-170): تجريد العلامات غير المرئية وتقليم الأطراف',
        () {
      expect(sanitizeFreeName('\u200Bزيت\u200F سمسم\uFEFF '), 'زيت سمسم');
    });

    test('محارف التحكم في الاسم مرفوضة لا تُجرد (D-170)', () {
      final errors = validateItemDraft(draft(name: 'زيت\x01'),
          existing: ItemUniquenessIndex.build(const []));
      expect(errors, contains(isA<ItemNameControlChars>()));
    });

    test('قائمة بيضاء الكود (D-171): حروف بأي لغة وأرقام و - _ . حصراً', () {
      expect(isValidItemSku('Z-12'), isTrue);
      expect(isValidItemSku('زيت_100.أ'), isTrue);
      expect(isValidItemSku('Z/12'), isFalse,
          reason: 'فاصل المسار علّته حية (س-154/D-152)');
      expect(isValidItemSku('Z 12'), isFalse);
      expect(isValidItemSku('Z*12'), isFalse);
    });

    test('كود خارج القائمة يُرفض عند الإنشاء (D-171)', () {
      final errors = validateItemDraft(draft(sku: 'Z/12'),
          existing: ItemUniquenessIndex.build([oil(7)]));
      expect(errors, contains(isA<ItemSkuInvalidFormat>()));
    });

    test('الكود القائم غير المتغير يمر عند التعديل — الاستثناء الذاتي (D-171)',
        () {
      final index = ItemUniquenessIndex.build([oil(7)]);
      // نفس الكود القائم «A/1» على نفس الصنف: بلا خطأ صيغة فلا يُحبس
      // تعديلُ اسم صنف قديم على كودِ ما قبل D-171
      final same = validateItemDraft(draft(sku: 'A/1'),
          existing: index, excludeItemId: 7);
      expect(same.whereType<ItemSkuInvalidFormat>(), isEmpty);
      // وتغييره لكود سليم يمر، وتغييره لكود خارج القائمة يُرفض
      final changed = validateItemDraft(draft(sku: 'B-2'),
          existing: index, excludeItemId: 7);
      expect(changed.whereType<ItemSkuInvalidFormat>(), isEmpty);
      final bad = validateItemDraft(draft(sku: 'B/2'),
          existing: index, excludeItemId: 7);
      expect(bad, contains(isA<ItemSkuInvalidFormat>()));
    });
  });

  group('نوع الصنف (05 §3.2) — التخزين والقراءة والملصق', () {
    test('القيم الثلاث مخزنة والواجهة في م1 تعرض الأولى والثانية حصراً', () {
      expect(ItemKind.good.storageValue, 'good');
      expect(ItemKind.service.label, 'خدمة');
      expect(ItemKind.bundle.storageValue, 'bundle');
      expect(ItemKind.fromStorage('service'), ItemKind.service);
      expect(() => ItemKind.fromStorage('unknown'), throwsArgumentError);
    });
  });

  group('البحث الجامع (س-38/D-064) — الاسم والكود والتصنيف بكلمات تلتقي', () {
    const oil = ItemSearchFields(
      name: 'زيت محلي',
      sku: '100',
      category: 'مواد غذائية',
    );

    test('«زيت 100» تجيء بالصنف — بالترتيبين وأي حقلين', () {
      expect(oil.matchesQuery('زيت 100'), isTrue);
      expect(oil.matchesQuery('100 زيت'), isTrue);
      expect(oil.matchesQuery('100 غذائية'), isTrue);
    });

    test('كلمة غائبة تُفشل المطابقة كلها', () {
      expect(oil.matchesQuery('زيت 100 غائب'), isFalse);
    });

    test('البحث مطبَّع: «مواد غذائيه» بتاء مفتوحة تجيء بالتصنيف', () {
      expect(oil.matchesQuery('غذائيه'), isTrue);
    });

    test('الخانة الفارغة تجيء بالجميع', () {
      expect(oil.matchesQuery(''), isTrue);
      expect(oil.matchesQuery('   '), isTrue);
    });

    test('N-003/س-38: البحث صحيح عند 5,000 صنف — الحد المتساهل حارس '
        'انحدار حصراً (القياس الفعلي على الجهاز المرجعي عند التسليم)', () {
      final fields = List.generate(5000, (i) {
        return ItemSearchFields(
          name: 'صنف رقم $i',
          sku: (i + 1).toString().padLeft(4, '0'),
        );
      });
      final watch = Stopwatch()..start();
      // «5000» لا «4999»: نمط علة CI 2026-10-29 (الأطراف) — استعلام غير
      // تصادمي يعطي صنفاً واحداً.
      final hits = fields.where((f) => f.matchesQuery('صنف 5000')).toList();
      watch.stop();
      expect(hits, hasLength(1));
      expect(hits.single.sku, '5000');
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)),
          reason: 'الفلترة في الذاكرة أضعاف أسرع من الحد — الارتفاع علة '
              'انحدار لا بطء طبيعي');
    });
  });

  group('منع تكرار الاسم حرفياً (D-074) — المقارنة بلا تطبيع', () {
    test('«احمد» غير «أحمد» صنفاً مختلفاً — التطبيع للبحث حصراً', () {
      final index = ItemUniquenessIndex.build([
        const ExistingItem(id: 1, sku: '100', name: 'أحمد', isActive: true),
      ]);
      final errors = validateItemDraft(
        const ItemDraft(sku: '101', name: 'احمد', kind: ItemKind.service, baseUnitId: 1),
        existing: index,
      );
      expect(errors, isEmpty);
    });

    test('المطابق الحرفي مرفوض والرسالة تحمل الصنف القائم بالاسم والكود', () {
      final index = ItemUniquenessIndex.build([
        const ExistingItem(id: 1, sku: '100', name: 'زيت محلي', isActive: true),
      ]);
      final errors = validateItemDraft(
        const ItemDraft(
            sku: '101', name: 'زيت محلي ', kind: ItemKind.good, baseUnitId: 1),
        existing: index,
      );
      expect(errors, hasLength(1));
      final taken = errors.single as ItemNameTaken;
      expect(taken.existingLabel, 'زيت محلي (100)');
    });

    test('المعطل يبقى محجوز الاسم والكود — التعطيل لا يحذف (س-40)', () {
      final index = ItemUniquenessIndex.build([
        const ExistingItem(id: 2, sku: '200', name: 'صنف معطل', isActive: false),
      ]);
      final errors = validateItemDraft(
        const ItemDraft(sku: '200', name: 'صنف معطل', kind: ItemKind.good, baseUnitId: 1),
        existing: index,
      );
      expect(errors.whereType<ItemNameTaken>(), isNotEmpty);
      expect(errors.whereType<ItemSkuTaken>(), isNotEmpty);
    });
  });

  group('التحقق قبل الحفظ (س-36/س-39)', () {
    final index = ItemUniquenessIndex.build([
      const ExistingItem(id: 1, sku: '100', name: 'زيت محلي', isActive: true),
      const ExistingItem(id: 2, sku: '200', name: 'صنف معطل', isActive: false),
    ]);

    test('بلا اسم مرفوض — الاسم إلزامي وحده (س-36)', () {
      final errors = validateItemDraft(
        const ItemDraft(sku: '101', name: '   ', kind: ItemKind.good, baseUnitId: 1),
        existing: index,
      );
      expect(errors.whereType<ItemNameRequired>(), isNotEmpty);
    });

    test('بلا كود مرفوض — الكود إلزامي (F-030/D-073)', () {
      final errors = validateItemDraft(
        const ItemDraft(sku: '   ', name: 'صنف بلا كود', kind: ItemKind.good, baseUnitId: 1),
        existing: index,
      );
      expect(errors.whereType<ItemSkuRequired>(), isNotEmpty);
    });

    test('بلا وحدة مرفوض — الوحدة إلزامية بالاختيار (F-031)', () {
      for (final bad in const [0, -1]) {
        final errors = validateItemDraft(
          ItemDraft(sku: '101', name: 'صنف', kind: ItemKind.good, baseUnitId: bad),
          existing: index,
        );
        expect(errors.whereType<ItemUnitMissing>(), isNotEmpty);
      }
    });

    test('عملة صفراً أو سالباً مرفوضة — لا فراغ للعملة (D-066)', () {
      for (final bad in const [0, -1]) {
        final errors = validateItemDraft(
          ItemDraft(sku: '101', name: 'صنف', kind: ItemKind.good, baseUnitId: 1, currencyId: bad),
          existing: index,
        );
        expect(errors.whereType<ItemCurrencyMissing>(), isNotEmpty);
      }
    });

    test('السعر السالب مرفوض شراءً وبيعاً — والصفر مشروع «بلا سعر بعد» (س6)', () {
      final buy = validateItemDraft(
        const ItemDraft(sku: '101', name: 'صنف', kind: ItemKind.good, baseUnitId: 1, purchasePriceMinor: -250),
        existing: index,
      );
      expect(buy.whereType<ItemPriceInvalid>(), isNotEmpty);

      final sell = validateItemDraft(
        const ItemDraft(sku: '101', name: 'صنف', kind: ItemKind.good, baseUnitId: 1, salePriceMinor: -1),
        existing: index,
      );
      expect(sell.whereType<ItemPriceInvalid>(), isNotEmpty);

      final zeros = validateItemDraft(
        const ItemDraft(sku: '101', name: 'صنف', kind: ItemKind.good, baseUnitId: 1),
        existing: index,
      );
      expect(zeros.whereType<ItemPriceInvalid>(), isEmpty);
    });

    test('«100» مكرر مرفوض لأن الصنف الأول كوده 100 — والرسالة تري صاحبها', () {
      final errors = validateItemDraft(
        const ItemDraft(sku: '100', name: 'صنف آخر', kind: ItemKind.good, baseUnitId: 1),
        existing: index,
      );
      expect(errors, hasLength(1));
      final taken = errors.single as ItemSkuTaken;
      expect(taken.duplicateSku, '100');
      expect(taken.existingLabel, 'زيت محلي (100)');
    });

    test('التعديل يستثني صاحبه من فحص التكرار ويصطدم بغيره (س-39)', () {
      final self = validateItemDraft(
        const ItemDraft(sku: '100', name: 'زيت محلي', kind: ItemKind.good, baseUnitId: 1),
        existing: index,
        excludeItemId: 1,
      );
      expect(self, isEmpty);

      final clash = validateItemDraft(
        const ItemDraft(sku: '100', name: 'زيت محلي', kind: ItemKind.good, baseUnitId: 1),
        existing: index,
        excludeItemId: 2,
      );
      expect(clash.whereType<ItemSkuTaken>(), isNotEmpty);
      expect(clash.whereType<ItemNameTaken>(), isNotEmpty);
    });
  });

  group('الوحدات (س-41/F-031/D-074) — الاسم الحرفي فريد ولا وحدة بلا اسم', () {
    final index = UnitUniquenessIndex.build([
      const ExistingUnit(id: 1, name: 'قطعة', isActive: true),
      const ExistingUnit(id: 2, name: 'كيلوغرام', isActive: true),
    ]);

    test('اسم فارغ مرفوض', () {
      final errors = validateUnitName('   ', existing: index);
      expect(errors.whereType<UnitNameRequired>(), isNotEmpty);
    });

    test('الاسم المطابق حرفياً مرفوض بعد التقليم — «قطعة » تصطدم بـ«قطعة»', () {
      final errors = validateUnitName(' قطعة ', existing: index);
      expect(errors, hasLength(1));
      expect((errors.single as UnitNameTaken).existingName, 'قطعة');
    });

    test('اسم جديد يمر — «غرام» مشروع', () {
      expect(validateUnitName('غرام', existing: index), isEmpty);
    });
  });

  test('صيغة العرض المعتمدة «الاسم (الكود)» (D-074/س-36)', () {
    expect(itemDisplayLabel('زيت محلي', '100'), 'زيت محلي (100)');
  });
}
