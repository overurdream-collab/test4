import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../models.dart';

class BrandGalleryScreen extends StatelessWidget {
  const BrandGalleryScreen({super.key});

  static const concepts = [
    BrandConcept(
      id: 'a',
      title: 'A • الورقة والرابط',
      description:
          'ورقة نظيفة داخل إطار حرف Q، مع طرفين متصلين يرمزان للدفتر المشترك. '
          'الأكثر توازناً بين الهوية المحلية والتقنية.',
    ),
    BrandConcept(
      id: 'b',
      title: 'B • Q المتصلة',
      description:
          'حرف Q مبني من حلقتي رابط متداخلتين. يعبّر عن الاعتماد المتبادل '
          'ويبقى واضحاً في الأحجام الصغيرة.',
    ),
    BrandConcept(
      id: 'c',
      title: 'C • الشكل الهندسي',
      description:
          'شكل Q هندسي مبني على شبكة 8×8، مناسب للأيقونة والتطبيقات '
          'واللوحات الكبيرة.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مفاهيم الشعار')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: QSpace.xxl),
        children: [
          QResponsiveBody(
            maxWidth: 900,
            padding: const EdgeInsets.fromLTRB(
              QSpace.lg,
              QSpace.sm,
              QSpace.lg,
              QSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ثلاثة اتجاهات بصرية',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  'كل مفهوم يعمل كأيقونة تطبيق وشعار أفقي. الموصى به هو A.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: QSpace.lg),
                for (var index = 0; index < concepts.length; index++) ...[
                  _ConceptCard(
                    concept: concepts[index],
                    recommended: index == 0,
                    variant: index,
                  ),
                  const SizedBox(height: QSpace.md),
                ],
                const SizedBox(height: QSpace.lg),
                const QSectionHeader(title: 'قواعد الهوية'),
                const QCard(
                  child: Column(
                    children: [
                      _Rule(
                        icon: Icons.check_circle_outline_rounded,
                        color: QColors.brightGreen,
                        text:
                            'استخدم الأخضر المشرق على خلفية بيضاء أو فاتحة. الشعار نفسه مشرق وواضح.',
                      ),
                      SizedBox(height: QSpace.md),
                      _Rule(
                        icon: Icons.check_circle_outline_rounded,
                        color: QColors.brightGreen,
                        text:
                            'مساحة حماية حول الشعار لا تقل عن نصف عرض الحرف Q.',
                      ),
                      SizedBox(height: QSpace.md),
                      _Rule(
                        icon: Icons.cancel_outlined,
                        color: QColors.rejectedFg,
                        text:
                            'لا تستخدم أخضر داكناً كخلفية أساسية، ولا تضف ظلالاً أو تدرجات خارج الهوية.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                const QSectionHeader(title: 'استخدامات الشعار'),
                Row(
                  children: [
                    Expanded(
                      child: QCard(
                        child: Column(
                          children: [
                            const QLogoMark(size: 64, showGlow: true),
                            const SizedBox(height: QSpace.sm),
                            Text(
                              'أيقونة التطبيق',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: QSpace.md),
                    Expanded(
                      child: QCard(
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const QLogoMark(size: 40),
                                const SizedBox(width: QSpace.sm),
                                Text(
                                  'QAT LINK',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            const SizedBox(height: QSpace.md),
                            Text(
                              'الشعار الأفقي',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConceptCard extends StatelessWidget {
  const _ConceptCard({
    required this.concept,
    required this.recommended,
    required this.variant,
  });

  final BrandConcept concept;
  final bool recommended;
  final int variant;

  @override
  Widget build(BuildContext context) {
    return QCard(
      borderColor: recommended
          ? QColors.brightGreen.withValues(alpha: 0.65)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [QColors.softMint, QColors.pureWhite],
              ),
              borderRadius: BorderRadius.circular(QRadius.md),
            ),
            child: Center(child: _ConceptMark(variant: variant)),
          ),
          const SizedBox(height: QSpace.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  concept.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (recommended)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: QSpace.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: QColors.approvedBg,
                    borderRadius: BorderRadius.circular(QRadius.pill),
                  ),
                  child: Text(
                    'موصى به',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: QColors.approvedFg),
                  ),
                ),
            ],
          ),
          const SizedBox(height: QSpace.xs),
          Text(
            concept.description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: QSpace.md),
          Row(
            children: [
              const Icon(
                Icons.download_outlined,
                size: 16,
                color: QColors.neutralGray,
              ),
              const SizedBox(width: 4),
              Text(
                'SVG • PNG • 1024px',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => QToast.show(
                  context,
                  'تم تجهيز ملفات ${concept.title.substring(0, 1)} للتنزيل',
                ),
                child: const Text('تنزيل الحزمة'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConceptMark extends StatelessWidget {
  const _ConceptMark({required this.variant});

  final int variant;

  @override
  Widget build(BuildContext context) {
    if (variant == 0) {
      return const QLogoMark(size: 92, showGlow: true);
    }
    if (variant == 1) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: QColors.brightGreen, width: 10),
                  ),
                ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: QColors.gradient,
                  ),
                  child: const Icon(
                    Icons.link_rounded,
                    color: QColors.charcoal,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'QAT LINK',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            gradient: QColors.gradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                'Q',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: QColors.charcoal,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Positioned(
                bottom: 20,
                right: 20,
                child: Container(
                  width: 24,
                  height: 8,
                  decoration: BoxDecoration(
                    color: QColors.pureWhite,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: QSpace.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'QAT',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              'LINK',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: QColors.brightGreen,
                letterSpacing: 4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: QSpace.sm),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}
