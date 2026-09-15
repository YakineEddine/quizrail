import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/backend.dart';
import '../../core/i18n/app_lang.dart';
import '../../core/models/party.dart';
import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/game_button.dart';
import '../shop/ads_service.dart';
import '../shop/monetization_config.dart';
import 'party_providers.dart';

/// Résultats Party : gagnant + tableau, puis sortie.
class PartyResultsScreen extends ConsumerStatefulWidget {
  const PartyResultsScreen({
    super.key,
    required this.roomId,
    this.lang = AppLang.fr,
    this.prefs,
    this.uid,
  });

  final String roomId;
  final AppLang lang;
  final AppPrefs? prefs;
  final String? uid;

  @override
  ConsumerState<PartyResultsScreen> createState() =>
      _PartyResultsScreenState();
}

class _PartyResultsScreenState extends ConsumerState<PartyResultsScreen> {
  late final String _uid = widget.uid ?? Backend.instance.uid ?? '';

  @override
  void initState() {
    super.initState();
    // Interstitielle APRÈS les résultats (jamais en pleine question),
    // cappée et coupée par remove_ads — best-effort silencieux.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowResultsAd(context, AdPlacement.resultsParty);
    });
  }

  String _t({required String fr, required String en, required String ar}) =>
      switch (widget.lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar
      };

  Future<void> _quit() async {
    try {
      await ref
          .read(partyServiceProvider)
          .leaveParty(roomId: widget.roomId);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final asyncPlayers = ref.watch(partyPlayersProvider(widget.roomId));
    return Directionality(
      textDirection:
          widget.lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('partyResultsScreen'),
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration:
              const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: asyncPlayers.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.sun),
              ),
              error: (_, st) => Center(
                child: Text(_t(
                  fr: 'Résultats indisponibles.',
                  en: 'Results unavailable.',
                  ar: 'النتائج غير متاحة.',
                )),
              ),
              data: (players) => _buildBody(context, players),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<PartyPlayer> players) {
    final res = partyWinner(players);
    final iWon = res.winnerUid == _uid;
    final winnerName = players
        .firstWhere((p) => p.uid == res.winnerUid,
            orElse: () => players.first)
        .displayName;
    final title = res.isDraw
        ? _t(fr: 'Match nul !', en: 'Draw!', ar: 'تعادل!')
        : iWon
            ? _t(
                fr: 'Tu gagnes la Party !',
                en: 'You win the party!',
                ar: 'فزت بالحفلة!',
              )
            : _t(
                fr: 'Victoire de $winnerName !',
                en: '$winnerName wins!',
                ar: 'فاز $winnerName!',
              );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          decoration: BoxDecoration(
            gradient: iWon
                ? AppColors.goldGradient
                : AppColors.secondaryGradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.ink, width: 2.5),
          ),
          child: Column(
            children: [
              Icon(
                iWon
                    ? Icons.emoji_events_rounded
                    : Icons.celebration_rounded,
                size: 56,
                color: iWon ? AppColors.ink : AppColors.cream,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                key: const Key('partyWinnerBanner'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: iWon ? AppColors.ink : AppColors.cream,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < players.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.midnight.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.midnightLight, width: 1.5),
            ),
            child: Row(
              children: [
                Text(
                  i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '${i + 1}.',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    players[i].displayName.isEmpty
                        ? '…'
                        : players[i].displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.cream,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${players[i].score}',
                  style: const TextStyle(
                      color: AppColors.sun,
                      fontWeight: FontWeight.w900,
                      fontSize: 20),
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        GameButton(
          key: const Key('partyLeaveButton'),
          label: _t(
              fr: 'Quitter la Party',
              en: 'Leave party',
              ar: 'مغادرة الحفلة'),
          icon: Icons.logout_rounded,
          onPressed: _quit,
        ),
      ],
    );
  }
}
