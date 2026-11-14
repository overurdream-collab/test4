import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../models.dart';

class AdminAdsCarousel extends StatefulWidget {
  const AdminAdsCarousel({super.key, required this.ads});

  final List<AdminAd> ads;

  @override
  State<AdminAdsCarousel> createState() => _AdminAdsCarouselState();
}

class _AdminAdsCarouselState extends State<AdminAdsCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 154,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.ads.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, index) {
              final ad = widget.ads[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(QRadius.lg),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        ad.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: QColors.softMint,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.campaign_outlined,
                            color: QColors.brightGreen,
                            size: 36,
                          ),
                        ),
                      ),
                      if (ad.title?.trim().isNotEmpty == true)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(QSpace.md),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black54],
                              ),
                            ),
                            child: Text(
                              ad.title!,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.ads.length > 1) ...[
          const SizedBox(height: QSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < widget.ads.length; index++)
                AnimatedContainer(
                  duration: QDuration.fast,
                  width: _page == index ? 18 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: _page == index
                        ? QColors.brightGreen
                        : QColors.neutralGray.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(QRadius.pill),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
