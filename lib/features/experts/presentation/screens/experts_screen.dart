import 'package:skeen/core/localization/locale_controller.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../application/insights_controller.dart';
import '../../domain/article.dart';

/// Insights feed — curated dermatology recommendations from PubMed served
/// through `/api/v1/experts/articles`.
class ExpertsScreen extends ConsumerStatefulWidget {
  const ExpertsScreen({super.key});

  @override
  ConsumerState<ExpertsScreen> createState() => _ExpertsScreenState();
}

class _ExpertsScreenState extends ConsumerState<ExpertsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initialQuery = ref.read(insightsControllerProvider).query;
    _searchCtrl.text = initialQuery;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _onTap(Article article) async {
    final uri = Uri.parse(article.url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the article.'.tr)),
      );
    }
  }

  void _onTabSelected(SkeenNavTab tab) {
    switch (tab) {
      case SkeenNavTab.home:
        context.goNamed('home');
      case SkeenNavTab.history:
        context.goNamed('history');
      case SkeenNavTab.scan:
        context.pushNamed('scan-a-mole');
      case SkeenNavTab.experts:
        return;
      case SkeenNavTab.profile:
        context.goNamed('profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(insightsControllerProvider);
    final controller = ref.read(insightsControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            SkeenTopAppBar(
              title: 'Insights'.tr,
              subtitle: 'expert tips on skin cancer'.tr,
            ),
            _SearchField(
              controller: _searchCtrl,
              onChanged: controller.setQuery,
            ),
            _CategoryRow(
              active: state.category,
              onSelected: controller.selectCategory,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.violetaClaro,
                backgroundColor: AppColors.indigo,
                onRefresh: controller.refresh,
                child: _Body(state: state, onTap: _onTap),
              ),
            ),
            SkeenBottomNav(
              activeTab: SkeenNavTab.experts,
              onTabSelected: _onTabSelected,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search field ───────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1A44),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A1F66)),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: AppColors.violetaClaro,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: AppColors.hintText,
              size: 20,
            ),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.hintText,
                    size: 18,
                  ),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                );
              },
            ),
            hintText: 'Search melanoma, sunscreen, biopsy…'.tr,
            hintStyle: const TextStyle(
              fontFamily: 'Poppins',
              color: AppColors.hintText,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Filter chips ──────────────────────────────────────────────────────

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.active, required this.onSelected});

  final ArticleCategory active;
  final ValueChanged<ArticleCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: ArticleCategory.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final category = ArticleCategory.values[i];
          final isActive = category == active;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () => onSelected(category),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.violeta.withValues(alpha: 0.18)
                      : const Color(0xFF1C1A44),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: isActive
                        ? AppColors.violeta
                        : const Color(0xFF2A1F66),
                  ),
                ),
                child: Text(
                  category.displayLabel,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 0.2,
                    color: isActive
                        ? AppColors.violetaClaro
                        : const Color(0xFFB5A9E9),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Body switcher (loading / error / empty / list) ───────────────────

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.onTap});

  final InsightsState state;
  final ValueChanged<Article> onTap;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.articles.isEmpty) {
      return const _SkeletonList();
    }
    if (state.errorMessage != null && state.articles.isEmpty) {
      return _ErrorState(message: state.errorMessage!);
    }
    if (state.articles.isEmpty) {
      return const _EmptyState();
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: state.articles.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, i) {
        return _ArticleCard(article: state.articles[i], onTap: onTap);
      },
    );
  }
}

// ── Article card (social-network style) ───────────────────────────────

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article, required this.onTap});

  final Article article;
  final ValueChanged<Article> onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onTap(article),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1A44),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2A1F66)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(article: article),
              const SizedBox(height: 12),
              Text(
                article.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  height: 1.35,
                  color: Color(0xFFE2DFFF),
                ),
              ),
              if (article.summary != null) ...[
                const SizedBox(height: 8),
                Text(
                  article.summary!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: 12.5,
                    height: 1.5,
                    color: Color(0xFFCCC3D8),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _CardFooter(article: article),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.article});
  final Article article;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.violeta.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.medical_information_outlined,
            color: AppColors.violeta,
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _authorsLine(article.authors),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Color(0xFFE2DFFF),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                _journalLine(article),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                  color: Color(0xFF8B82B5),
                ),
              ),
            ],
          ),
        ),
        if (article.articleType != null)
          _TypeBadge(label: article.articleType!),
      ],
    );
  }

  String _authorsLine(List<ArticleAuthor> authors) {
    if (authors.isEmpty) return 'Unknown author';
    if (authors.length == 1) return authors.first.name;
    if (authors.length == 2) {
      return '${authors[0].name} · ${authors[1].name}';
    }
    return '${authors[0].name} · ${authors[1].name} +${authors.length - 2}';
  }

  String _journalLine(Article article) {
    final country = article.authors
        .map((a) => a.country)
        .firstWhere((c) => c != null && c.isNotEmpty, orElse: () => null);
    final pieces = <String>[
      if (article.journal != null && article.journal!.isNotEmpty)
        article.journal!,
      if (country != null) country,
    ];
    if (pieces.isEmpty) return 'PubMed';
    return pieces.join(' · ');
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.turquesa.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.turquesa.withValues(alpha: 0.32)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 9,
          letterSpacing: 0.4,
          color: AppColors.turquesa,
        ),
      ),
    );
  }
}

class _CardFooter extends StatelessWidget {
  const _CardFooter({required this.article});
  final Article article;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.calendar_today_outlined,
          size: 12,
          color: Color(0xFF8B82B5),
        ),
        const SizedBox(width: 4),
        Text(
          _formatDate(article.publishedAt),
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: 11,
            color: Color(0xFF8B82B5),
          ),
        ),
        const Spacer(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Read on PubMed'.tr,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: AppColors.violetaClaro,
              ),
            ),
            SizedBox(width: 4),
            Icon(
              Icons.open_in_new_rounded,
              size: 12,
              color: AppColors.violetaClaro,
            ),
          ],
        ),
      ],
    );
  }

  static String _formatDate(DateTime? at) {
    if (at == null) return 'Recent';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[at.month - 1]} ${at.year}';
  }
}

// ── Skeleton, error & empty states ────────────────────────────────────

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, _) => Container(
        height: 152,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1A44),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF2A1F66)),
        ),
        child: const _ShimmerStrip(),
      ),
    );
  }
}

class _ShimmerStrip extends StatefulWidget {
  const _ShimmerStrip();

  @override
  State<_ShimmerStrip> createState() => _ShimmerStripState();
}

class _ShimmerStripState extends State<_ShimmerStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Opacity(
        opacity: 0.4 + (_ctrl.value - 0.5).abs() * 0.4,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 24),
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.violeta.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.menu_book_outlined,
            size: 28,
            color: AppColors.violeta,
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            'No articles match'.tr,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: AppColors.violetaClaro,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Try a different keyword or pick another category.'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            height: 1.5,
            color: AppColors.hintText,
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 24),
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.fucsia.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.cloud_off_rounded,
            size: 28,
            color: AppColors.fucsia,
          ),
        ),
        const SizedBox(height: 14),
        const Center(
          child: Text(
            'Couldn\'t load articles',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: AppColors.violetaClaro,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            height: 1.5,
            color: AppColors.hintText,
          ),
        ),
      ],
    );
  }
}
