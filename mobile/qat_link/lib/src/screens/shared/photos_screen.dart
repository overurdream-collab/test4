import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';

class PhotosScreen extends StatelessWidget {
  const PhotosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final isMerchant = state.persona == AppPersona.merchant;
    final photos = [...state.photos]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final remaining = (state.dailyPhotoLimit - state.todayPhotos).clamp(
      0,
      state.dailyPhotoLimit,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('صور اليوم'),
        actions: [
          if (isMerchant)
            IconButton(
              tooltip: 'إضافة صورة',
              onPressed: remaining == 0
                  ? null
                  : () => _showAddPhoto(context, state),
              icon: const Icon(Icons.add_a_photo_outlined),
            ),
          const SizedBox(width: QSpace.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: QSpace.xxl),
        children: [
          QResponsiveBody(
            padding: const EdgeInsets.fromLTRB(
              QSpace.lg,
              QSpace.sm,
              QSpace.lg,
              QSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                QCard(
                  gradient: const LinearGradient(
                    colors: [QColors.softMint, QColors.pureWhite],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: QColors.gradient,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.photo_camera_back_outlined,
                          color: QColors.charcoal,
                        ),
                      ),
                      const SizedBox(width: QSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMerchant
                                  ? 'اعرض منتجات اليوم'
                                  : 'آخر صور التجار',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              isMerchant
                                  ? 'متبقي $remaining من ${state.dailyPhotoLimit} صور اليوم'
                                  : 'صور حديثة من التجار الذين تتعامل معهم.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (isMerchant)
                        QStatusBadge(
                          status: remaining == 0
                              ? TxStatus.rejected
                              : TxStatus.approved,
                          compact: true,
                        ),
                    ],
                  ),
                ),
                if (isMerchant) ...[
                  const SizedBox(height: QSpace.md),
                  QCreditLimitBar(
                    usedMinor: state.todayPhotos,
                    limitMinor: state.dailyPhotoLimit,
                    hidden: false,
                  ),
                ],
                const SizedBox(height: QSpace.lg),
                QSectionHeader(
                  title: 'المعرض',
                  subtitle: '${photos.length} صورة',
                  actionLabel: isMerchant ? 'إضافة' : null,
                  onAction: isMerchant && remaining > 0
                      ? () => _showAddPhoto(context, state)
                      : null,
                ),
                if (photos.isEmpty)
                  const QStateView(
                    state: QDataState.empty,
                    title: 'لا توجد صور بعد',
                    message: 'أضف أول صورة لتظهر للعملاء المستهدفين.',
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: photos.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          mainAxisSpacing: QSpace.md,
                          crossAxisSpacing: QSpace.md,
                          childAspectRatio: 0.92,
                        ),
                    itemBuilder: (context, index) {
                      final photo = photos[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          QPhotoTile(photo: photo, height: 126),
                          const SizedBox(height: QSpace.sm),
                          Text(
                            photo.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            '${photo.audience} • ${formatDateTime(photo.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: QSpace.lg),
                if (isMerchant)
                  Text(
                    'الصور تُحذف تلقائياً بعد 30 يوماً حسب سياسة الاحتفاظ.',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddPhoto(BuildContext context, AppState state) async {
    final pageContext = context;
    final titleController = TextEditingController();
    String audience = 'جميع العملاء';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(QRadius.xl)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: QSpace.xl,
            right: QSpace.xl,
            top: QSpace.lg,
            bottom: MediaQuery.of(context).viewInsets.bottom + QSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              QSheetHeader(
                title: 'إضافة صورة اليوم',
                subtitle: 'تظهر للعملاء المستهدفين فقط',
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: QSpace.lg),
              QCard(
                onTap: () => QToast.show(context, 'تم اختيار صورة تجريبية'),
                borderColor: QColors.brightGreen.withValues(alpha: 0.45),
                child: const Row(
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: QColors.brightGreen,
                    ),
                    SizedBox(width: QSpace.md),
                    Expanded(child: Text('اختيار صورة من الكاميرا أو المعرض')),
                  ],
                ),
              ),
              const SizedBox(height: QSpace.md),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان الصورة',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: QSpace.md),
              DropdownButtonFormField<String>(
                initialValue: audience,
                decoration: const InputDecoration(
                  labelText: 'الجمهور',
                  prefixIcon: Icon(Icons.groups_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'جميع العملاء',
                    child: Text('جميع العملاء'),
                  ),
                  DropdownMenuItem(
                    value: 'العملاء المفضلون',
                    child: Text('العملاء المفضلون'),
                  ),
                  DropdownMenuItem(
                    value: 'عميل محدد',
                    child: Text('عميل محدد'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setSheetState(() => audience = value);
                },
              ),
              const SizedBox(height: QSpace.lg),
              QGradientButton(
                label: 'نشر الصورة',
                icon: Icons.publish_rounded,
                onPressed: () {
                  final title = titleController.text.trim();
                  if (title.isEmpty) {
                    QToast.show(context, 'أدخل عنوان الصورة', error: true);
                    return;
                  }
                  state.addPhoto(title, audience);
                  Navigator.of(context).pop();
                  QToast.show(pageContext, 'تم نشر صورة اليوم');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
