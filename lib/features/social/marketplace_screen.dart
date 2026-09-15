import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_lang.dart';
import '../../core/models/game_tunnel.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/game_button.dart';
import 'social_providers.dart';
import 'social_service.dart';

const reportReasons = ['spam', 'inappropriate', 'offensive', 'other'];

/// Marché communautaire : tunnels publics, tri popularité/récence,
/// recherche par thème, notation étoiles, signalement.
class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key, this.lang = AppLang.fr});

  final AppLang lang;

  @override
  ConsumerState<MarketplaceScreen> createState() =>
      _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  MarketSort _sort = MarketSort.popular;
  final _search = TextEditingController();
  String _query = '';

  String _t({required String fr, required String en, required String ar}) =>
      switch (widget.lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar
      };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _rate(GameTunnel tunnel) async {
    final stars = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        key: const Key('mkRateDialog'),
        backgroundColor: AppColors.midnight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(
              color: AppColors.midnightLight, width: 1.5),
        ),
        title: Text(
          tunnel.theme,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.cream),
        ),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var s = 1; s <= 5; s++)
              IconButton(
                key: Key('mkStar_$s'),
                onPressed: () => Navigator.of(context).pop(s),
                icon: const Icon(Icons.star_rounded,
                    color: AppColors.sun, size: 32),
              ),
          ],
        ),
      ),
    );
    if (stars == null || !mounted) return;
    try {
      await ref
          .read(socialServiceProvider)
          .rateTunnel(tunnelId: tunnel.id, stars: stars);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(_t(
            fr: 'Merci pour ta note !',
            en: 'Thanks for rating!',
            ar: 'شكرًا لتقييمك!',
          )),
        ));
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _report(GameTunnel tunnel) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        key: const Key('mkReportDialog'),
        backgroundColor: AppColors.midnight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(
              color: AppColors.midnightLight, width: 1.5),
        ),
        title: Text(
          _t(
              fr: 'Signaler ce tunnel ?',
              en: 'Report this tunnel?',
              ar: 'الإبلاغ عن هذا النفق؟'),
          style: const TextStyle(color: AppColors.cream),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in reportReasons)
              ListTile(
                key: Key('mkReason_$r'),
                title: Text(r,
                    style: const TextStyle(color: AppColors.cream)),
                onTap: () => Navigator.of(context).pop(r),
              ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await ref
          .read(socialServiceProvider)
          .reportTunnel(tunnelId: tunnel.id, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(_t(
            fr: 'Signalement envoyé, merci.',
            en: 'Report sent, thanks.',
            ar: 'تم إرسال البلاغ، شكرًا.',
          )),
        ));
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tunnels = ref.watch(
      marketProvider((_sort, _query)),
    );
    return Directionality(
      textDirection:
          widget.lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('marketplaceScreen'),
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration:
              const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.cream),
                      ),
                      Expanded(
                        child: Text(
                          _t(
                              fr: 'Marché',
                              en: 'Marketplace',
                              ar: 'السوق'),
                          style:
                              Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('mkSearchField'),
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(
                        color: AppColors.cream,
                        fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: _t(
                          fr: 'Chercher un thème…',
                          en: 'Search a theme…',
                          ar: 'ابحث عن موضوع…'),
                      hintStyle: const TextStyle(
                          color: AppColors.creamDim),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.creamDim),
                      filled: true,
                      fillColor: AppColors.deepSpace,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: AppColors.midnightLight,
                            width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: AppColors.sun, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color:
                          AppColors.midnight.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.midnightLight, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        for (final s in MarketSort.values)
                          Expanded(
                            child: GestureDetector(
                              key: Key('mkSort${s.name}'),
                              onTap: () =>
                                  setState(() => _sort = s),
                              behavior: HitTestBehavior.opaque,
                              child: AnimatedContainer(
                                duration: const Duration(
                                    milliseconds: 160),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10),
                                decoration: BoxDecoration(
                                  gradient: _sort == s
                                      ? AppColors.goldGradient
                                      : null,
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                                child: Text(
                                  s == MarketSort.popular
                                      ? _t(
                                          fr: '★ Populaires',
                                          en: '★ Popular',
                                          ar: '★ الرائج')
                                      : _t(
                                          fr: '🕘 Récents',
                                          en: '🕘 Recent',
                                          ar: '🕘 الأحدث'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _sort == s
                                        ? AppColors.ink
                                        : AppColors.creamDim,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: tunnels.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.sun),
                      ),
                      error: (e, _) => Center(
                        child: Text(
                          e is StateError
                              ? e.message
                              : _t(
                                  fr: 'Marché indisponible.',
                                  en: 'Marketplace unavailable.',
                                  ar: 'السوق غير متاح.',
                                ),
                        ),
                      ),
                      data: (list) => list.isEmpty
                          ? Center(
                              child: Text(
                                _t(
                                  fr: 'Aucun tunnel public pour l\u2019instant — publie le tien depuis l\u2019éditeur !',
                                  en: 'No public tunnels yet — publish yours from the editor!',
                                  ar: 'لا أنفاق عامة بعد — انشر نفقك من المحرر!',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: AppColors.creamDim),
                              ),
                            )
                          : ListView(
                              key: const Key('mkList'),
                              children: [
                                for (final t in list)
                                  _TunnelCard(
                                    tunnel: t,
                                    onRate: () => _rate(t),
                                    onReport: () => _report(t),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tri + recherche du marché.
final marketProvider = StreamProvider.autoDispose
    .family<List<GameTunnel>, (MarketSort, String)>((ref, args) {
  return ref
      .watch(socialServiceProvider)
      .watchMarket(sort: args.$1, query: args.$2);
});

class _TunnelCard extends StatelessWidget {
  const _TunnelCard({
    required this.tunnel,
    required this.onRate,
    required this.onReport,
  });

  final GameTunnel tunnel;
  final VoidCallback onRate;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final stars = tunnel.ratingCount > 0
        ? '★ ${tunnel.ratingAvg.toStringAsFixed(1)} (${tunnel.ratingCount})'
        : '☆ —';
    return Container(
      key: Key('mkTunnelCard_${tunnel.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.midnight.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: AppColors.midnightLight, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tunnel.theme,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.cream,
                      fontWeight: FontWeight.w900,
                      fontSize: 16),
                ),
              ),
              Text(
                stars,
                style: const TextStyle(
                    color: AppColors.sun,
                    fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${tunnel.questions.length} questions',
            style: const TextStyle(
                color: AppColors.creamDim, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GameButton(
                  key: Key('mkRateButton_${tunnel.id}'),
                  label: 'Noter',
                  icon: Icons.star_rounded,
                  height: 46,
                  fontSize: 15,
                  onPressed: onRate,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                key: Key('mkReportButton_${tunnel.id}'),
                onTap: onReport,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.deepSpace,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.pinkPop, width: 1.5),
                  ),
                  child: const Icon(Icons.flag_outlined,
                      color: AppColors.pinkPop, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
