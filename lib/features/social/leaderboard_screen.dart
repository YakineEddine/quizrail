import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_lang.dart';
import '../../core/models/leaderboard_entry.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/game_button.dart';
import 'social_providers.dart';

enum _BoardTab { global, country, friends }

/// Classements : mondial, par pays, entre amis (+ ajout d'ami).
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key, this.lang = AppLang.fr});

  final AppLang lang;

  @override
  ConsumerState<LeaderboardScreen> createState() =>
      _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  _BoardTab _tab = _BoardTab.global;
  final _friend = TextEditingController();
  final _country = TextEditingController();
  String? _friendMsg;

  String _t({required String fr, required String en, required String ar}) =>
      switch (widget.lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar
      };

  @override
  void dispose() {
    _friend.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _addFriend() async {
    final id = _friend.text.trim();
    if (id.isEmpty) return;
    try {
      final name = await ref
          .read(socialServiceProvider)
          .addFriend(friendUid: id);
      if (!mounted) return;
      setState(() {
        _friendMsg = _t(
          fr: '$name ajouté !',
          en: '$name added!',
          ar: 'تمت إضافة $name!',
        );
        _friend.clear();
      });
    } on StateError catch (e) {
      if (mounted) setState(() => _friendMsg = e.message);
    }
  }

  Future<void> _saveCountry() async {
    final c = _country.text.trim().toUpperCase();
    if (c.length != 2) {
      setState(() => _friendMsg = _t(
        fr: 'Code pays à 2 lettres (ex : FR).',
        en: '2-letter country code (e.g. FR).',
        ar: 'رمز البلد من حرفين (مثال: FR).',
      ));
      return;
    }
    await ref.read(socialServiceProvider).setCountry(c);
    if (mounted) {
      setState(() => _friendMsg = null);
      ref.invalidate(myProfileProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final country =
        (ref.watch(myProfileProvider).value?['country'] as String?) ??
            '--';

    final board = switch (_tab) {
      _BoardTab.global => ref.watch(leaderboardGlobalProvider),
      _BoardTab.country =>
        ref.watch(leaderboardCountryProvider(country)),
      _BoardTab.friends => ref.watch(leaderboardFriendsProvider),
    };

    return Directionality(
      textDirection:
          widget.lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('leaderboardScreen'),
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
                              fr: 'Classements',
                              en: 'Leaderboards',
                              ar: 'الترتيب'),
                          style:
                              Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
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
                        for (final t in _BoardTab.values)
                          Expanded(
                            child: GestureDetector(
                              key: Key('lbTab${t.name}'),
                              onTap: () =>
                                  setState(() => _tab = t),
                              behavior: HitTestBehavior.opaque,
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10),
                                decoration: BoxDecoration(
                                  gradient: _tab == t
                                      ? AppColors.goldGradient
                                      : null,
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                                child: Text(
                                  switch (t) {
                                    _BoardTab.global => _t(
                                        fr: 'Mondial',
                                        en: 'Global',
                                        ar: 'عالمي'),
                                    _BoardTab.country =>
                                      country == '--'
                                          ? _t(
                                              fr: 'Pays',
                                              en: 'Country',
                                              ar: 'بلد')
                                          : country,
                                    _BoardTab.friends => _t(
                                        fr: 'Amis',
                                        en: 'Friends',
                                        ar: 'أصدقاء'),
                                  },
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _tab == t
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
                    child: board.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.sun),
                      ),
                      error: (e, _) => Center(
                        child: Text(
                          e is StateError
                              ? e.message
                              : _t(
                                  fr: 'Classements indisponibles.',
                                  en: 'Leaderboards unavailable.',
                                  ar: 'الترتيب غير متاح.',
                                ),
                        ),
                      ),
                      data: (entries) => entries.isEmpty
                          ? Center(
                              child: Text(
                                _t(
                                  fr: 'Personne classée pour l\u2019instant — joue un duel ou une party !',
                                  en: 'Nobody ranked yet — play a duel or party!',
                                  ar: 'لا أحد مصنّف بعد — العب مبارزة أو حفلة!',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: AppColors.creamDim),
                              ),
                            )
                          : ListView(
                              key: const Key('lbList'),
                              children: [
                                for (var i = 0; i < entries.length; i++)
                                  _RankRow(
                                      rank: i + 1,
                                      entry: entries[i]),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Ajout d'ami par UID.
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('lbFriendField'),
                          controller: _friend,
                          style: const TextStyle(
                              color: AppColors.cream,
                              fontWeight: FontWeight.w700),
                          decoration: InputDecoration(
                            hintText: _t(
                                fr: 'UID d\u2019un ami…',
                                en: 'A friend\u2019s UID…',
                                ar: 'معرّف صديق…'),
                            hintStyle: const TextStyle(
                                color: AppColors.creamDim),
                            filled: true,
                            fillColor: AppColors.deepSpace,
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: AppColors.midnightLight,
                                  width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: AppColors.sun, width: 2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        key: const Key('lbAddFriendButton'),
                        onTap: _addFriend,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            gradient: AppColors.secondaryGradient,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: AppColors.ink, width: 2),
                          ),
                          child: const Icon(Icons.person_add_rounded,
                              color: AppColors.cream),
                        ),
                      ),
                    ],
                  ),
                  // Pays perso (2 lettres).
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('lbCountryField'),
                          controller: _country,
                          textCapitalization:
                              TextCapitalization.characters,
                          maxLength: 2,
                          style: const TextStyle(
                              color: AppColors.cream,
                              fontWeight: FontWeight.w700),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: _t(
                                fr: 'Mon pays (FR)… — actuel : $country',
                                en: 'My country (FR)… — now: $country',
                                ar: 'بلدي (FR)… — الحالي: $country'),
                            hintStyle: const TextStyle(
                                color: AppColors.creamDim),
                            filled: true,
                            fillColor: AppColors.deepSpace,
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: AppColors.midnightLight,
                                  width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: AppColors.sun, width: 2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GameButton(
                        key: const Key('lbCountrySave'),
                        label: 'OK',
                        expanded: false,
                        height: 50,
                        fontSize: 16,
                        onPressed: _saveCountry,
                      ),
                    ],
                  ),
                  if (_friendMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _friendMsg!,
                        key: const Key('lbFriendMsg'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.sun,
                            fontWeight: FontWeight.w700),
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

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.entry});

  final int rank;
  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.midnight.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.midnightLight, width: 1.5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              rank == 1
                  ? '🥇'
                  : rank == 2
                      ? '🥈'
                      : rank == 3
                          ? '🥉'
                          : '$rank.',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.cream,
                      fontWeight: FontWeight.w800),
                ),
                Text(
                  '${entry.country} • ${entry.wins} victoires',
                  style: const TextStyle(
                      color: AppColors.creamDim, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '${entry.bestScore}',
            style: const TextStyle(
                color: AppColors.sun,
                fontWeight: FontWeight.w900,
                fontSize: 20),
          ),
        ],
      ),
    );
  }
}
