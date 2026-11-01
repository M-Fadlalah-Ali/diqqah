/// إطار قص مربع للصورة الملتقطة — دفعة (10) (س-123، D-120/D-121).
///
/// «إطار قص مربع افتراضه الصورة كاملة داخله والتقريب والإزاحة بيد
/// المستخدم» — الشاشة تعرض الصورة داخل مربع بالاحتواء (اللوحة المربعة
/// بحشوها الهادئ كما ستحفظ)، والتقريب بالإصبعين أو الشريط (للماوس على
/// ويندوز) والإزاحة بالسحب عبر InteractiveViewer، والتأكيد يعيد مستطيل
/// القص بإحداثيات الصورة الطبيعية (computeItemCropRect النقي في المجال)
/// فيمرر للمحرك الإلزامي.
library;

import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart'
    show ItemImageCrop, computeItemCropRect;

class ItemCropScreen extends StatefulWidget {
  final List<int> rawBytes;

  /// أبعاد الصورة بعد تدوير EXIF — تُحسب مسبقاً في بطاقة الصنف كي
  /// لا يُفك الملف مرتين في جلسة إدخال واحدة.
  final int imageWidth;
  final int imageHeight;

  const ItemCropScreen({
    super.key,
    required this.rawBytes,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  State<ItemCropScreen> createState() => _ItemCropScreenState();
}

class _ItemCropScreenState extends State<ItemCropScreen> {
  final TransformationController _transform =
      TransformationController(Matrix4.identity());

  double _zoom = 1.0;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// التقريب من الشريط يبقى ضمن قدرة المشاهد (سقف 4×) محافظاً على
  /// المركز الحالي — والإزاحة الدقيقة بيد المشاهد من السحب مباشرة.
  void _onSlider(double v) {
    final clamped = v.clamp(1.0, 4.0);
    final current = _transform.value.getMaxScaleOnAxis();
    final k = current <= 0 ? clamped : clamped / current;
    _transform.value =
        _transform.value.scaled(Matrix4.diagonal3Values(k, k, 1.0));
    setState(() => _zoom = clamped);
  }

  void _reset() {
    _transform.value = Matrix4.identity();
    setState(() => _zoom = 1.0);
  }

  /// تأكيد الإطار: المستطيل المرئي بإحداثيات المربع المعروض (S) يُحوَّل
  /// إلى إحداثيات الصورة الطبيعية بضربه في max(W,H)/S — الشاشة تعرض
  /// بالاحتواء فالمقياس واحد لكلا المحورين.
  void _confirm(double viewportSide) {
    final visible = computeItemCropRect(
      canvasSide: viewportSide.round(),
      viewportSide: viewportSide,
      scale: _transform.value.getMaxScaleOnAxis(),
      tx: _transform.value.getTranslation().x,
      ty: _transform.value.getTranslation().y,
    );
    final naturalMax = widget.imageWidth > widget.imageHeight
        ? widget.imageWidth
        : widget.imageHeight;
    final k = naturalMax / viewportSide;
    Navigator.of(context).pop(
      ItemImageCrop(
        x: visible.x * k,
        y: visible.y * k,
        side: visible.side * k,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return Scaffold(
          appBar: AppBar(title: const Text('إطار صورة الصنف')),
          body: Center(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'الصورة كاملة داخل الإطار افتراضياً — قرّب بالشريط أو '
                    'بإصبعين واسحب لتأطير ما تشاء ثم أكّد',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: ClipRect(
                      child: InteractiveViewer(
                        transformationController: _transform,
                        minScale: 1.0,
                        maxScale: 4.0,
                        child: Container(
                          color: Colors.white,
                          alignment: Alignment.center,
                          child: Image.memory(
                            Uint8List.fromList(widget.rawBytes),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'الصورة كاملة',
                      onPressed: _reset,
                      icon: const Icon(Icons.filter_center_focus),
                    ),
                    Expanded(
                      child: Slider(
                        value: _zoom,
                        min: 1.0,
                        max: 4.0,
                        onChanged: _onSlider,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _confirm(side),
                          child: const Text('تأكيد الإطار'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
