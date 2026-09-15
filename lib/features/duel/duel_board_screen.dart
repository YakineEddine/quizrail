import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/backend.dart';
import '../../core/i18n/app_lang.dart';
import '../../core/models/game_duel.dart';
import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/cute_train.dart';
import '../../core/widgets/game_button.dart';
import '../board/board_screen.dart' show BoardPainter, kTiles;
import 'duel_providers.dart';
import 'duel_results_screen.dart';
import 'duel_service.dart';

/// Plateau Duel : les deux trains sur la même voie, scores live (stream),
/// question perso, pouvoirs (gel / x2 / vol), forfait et abandon.
/// Le score n'est jamais calculé ici : tout passe par les Cloud Functions.
class DuelBoardScreen extends ConsumerStatefulWidget {
  const DuelBoardScreen({
    super.key,
    required this.duelId,
    this.lang = AppLang.fr,
    this.prefs,
    this.uid,
  });

  final String duelId;
  final AppLang lang;
  final AppPrefs? prefs;

  /// Testabilité : en prod, Backend.instance.uid.
  final String? uid;

  @override
  ConsumerState<DuelBoardScreen> createState() => _DuelBoardScreenState();
}

class _DuelBoardScreenState extends ConsumerState<DuelBoardScreen> {
  final _answer = TextEditingController();
  late final String _uid = widget.uid ?? Backend.instance.uid ?? '';

  int _questionStartMs = DateTime.now().millisecondsSinceEpoch;
  int _lastAnsweredSeen = -1;
  bool _submitting = false;
  bool _powerBusy = false;
  String? _formError;
  bool _navigated = false;
  Timer? _uiTick;
  Timer? _heartbeat;
  late final DuelService _service;

  String _t({required String fr, required String en, required String ar}) =>
      switch (widget.lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar
      };

  @override
  void initState() {
    super.initState();
    // Service figé ici : ref est interdit dans dispose().
    _service = ref.read(duelServiceProvider);
    _presence(true);
    // Horloge UI (compte à rebours gel, bouton forfait) + heartbeat 10 s
    // (grâce forfait 30 s : jamais de faux forfait en jeu normal).
    _uiTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      _presence(true);
    });
  }

  @override
  void dispose() {
    _uiTick?.cancel();
    _heartbeat?.cancel();
    _presence(false);
    _answer.dispose();
    super.dispose();
  }

  Future<void> _presence(bool connected) async {
    try {
      await _service.setPresence(
          duelId: widget.duelId, connected: connected);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _submit(GameDuel duel) async {
    final me = duel.me(_uid);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_submitting || duel.isFinished) return;
    if (me.isFrozen(now)) {
      setState(() => _formError = _t(
        fr: 'Gelé par l\u2019adversaire, attends la fin du gel !',
        en: 'Frozen by your opponent, wait it out!',
        ar: 'جمّدك الخصم، انتظر نهاية التجميد!',
      ));
      return;
    }
    if (_answer.text.trim().isEmpty) {
      setState(() => _formError = _t(
        fr: 'Écris une réponse d\u2019abord.',
        en: 'Write an answer first.',
        ar: 'اكتب إجابة أولًا.',
      ));
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      final res =
          await ref.read(duelServiceProvider).submitAnswer(
                duelId: widget.duelId,
                questionIndex: me.answered,
                answer: _answer.text,
                elapsedMs: now - _questionStartMs,
                lang: widget.lang.code,
              );
      if (res.correct) {
        final p = widget.prefs;
        if (p != null) await p.setTokens(p.tokens + 10);
      }
      if (mounted) {
        setState(() {
          _formError = res.correct
              ? null
              : _t(
                  fr: 'Raté ! L\u2019adversaire avance peut-être…',
                  en: 'Missed! Your opponent may be pulling ahead…',
                  ar: 'خطأ! قد يتقدم الخصم…',
                );
        });
      }
    } on StateError catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
        _answer.clear();
      }
    }
  }

  Future<void> _power(GameDuel duel, DuelPower power) async {
    if (_powerBusy || duel.isFinished) return;
    setState(() => _powerBusy = true);
    try {
      final res = await ref
          .read(duelServiceProvider)
          .usePower(duelId: widget.duelId, power: power);
      final p = widget.prefs;
      if (p != null) await p.setTokens(res.wallet);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(switch (power) {
            DuelPower.freeze => _t(
                fr: 'Adversaire gelé 5 s !',
                en: 'Opponent frozen for 5s!',
                ar: 'تم تجميد الخصم 5 ثوانٍ!',
              ),
            DuelPower.doubleGains => _t(
                fr: 'Gains doublés pendant 20 s !',
                en: 'Double gains for 20s!',
                ar: 'تضاعفت الأرباح لمدة 20 ثانية!',
              ),
            DuelPower.steal => _t(
                fr: '10 jetons volés !',
                en: 'Stole 10 tokens!',
                ar: 'سُرقت 10 رموز!',
              ),
          }),
        ));
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _powerBusy = false);
    }
  }

  Future<void> _forfeit() async {
    try {
      await ref
          .read(duelServiceProvider)
          .claimForfeit(duelId: widget.duelId);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _quit() async {
    await _presence(false);
    if (mounted) Navigator.of(context).pop();
  }

  void _goResults() {
    if (_navigated) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DuelResultsScreen(
            duelId: widget.duelId,
            lang: widget.lang,
            prefs: widget.prefs,
            uid: _uid,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncDuel = ref.watch(duelStreamProvider(widget.duelId));

    // Reset du chrono à chaque nouvelle question + navigation fin de duel.
    ref.listen(duelStreamProvider(widget.duelId), (_, next) {
      next.whenData((duel) {
        final me = duel.me(_uid);
        if (me.answered != _lastAnsweredSeen) {
          _lastAnsweredSeen = me.answered;
          _questionStartMs = DateTime.now().millisecondsSinceEpoch;
          _answer.clear();
          if (mounted) setState(() => _formError = null);
        }
        if (duel.isFinished) _goResults();
      });
    });

    final screenH = MediaQuery.sizeOf(context).height;
    final boardH = (screenH - 430).clamp(320.0, 560.0);

    return Directionality(
      textDirection:
          widget.lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('duelBoardScreen'),
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration:
              const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: asyncDuel.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.sun),
              ),
              error: (e, _) => _ErrorCard(
                message: e is StateError
                    ? e.message
                    : _t(
                        fr: 'Duel indisponible hors ligne.',
                        en: 'Duel unavailable offline.',
                        ar: 'المبارزة غير متاحة دون اتصال.',
                      ),
                backLabel: _t(
                    fr: 'Retour', en: 'Back', ar: 'رجوع'),
                onBack: () => Navigator.of(context).pop(),
              ),
              data: (duel) => _buildLive(context, duel, boardH),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLive(BuildContext context, GameDuel duel, double boardH) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final me = duel.me(_uid);
    final opp = duel.opponent(_uid);
    final frozenLeft =
        ((me.frozenUntilMs - now) / 1000).ceil().clamp(0, 99);
    final oppFrozen = opp.isFrozen(now);
    final iDouble = me.hasDouble(now);
    final wallet = widget.prefs?.tokens ?? 0;
    final finishedAll = me.answered >= duel.questions.length;
    final canForfeit = !duel.isFinished &&
        canClaimForfeit(nowMs: now, oppLastSeenMs: opp.lastSeenMs);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('duelQuitButton'),
              onPressed: _quit,
              icon: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.cream),
            ),
            Expanded(
              child: Text(
                _t(fr: 'Duel', en: 'Duel', ar: 'مبارزة'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.midnight.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.midnightLight, width: 1.5),
              ),
              child: Text(
                '🪙 $wallet',
                style: const TextStyle(
                    color: AppColors.sun, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Tableau live.
        Row(
          children: [
            Expanded(
              child: _ScoreCard(
                key: const Key('duelMyScore'),
                title: _t(fr: 'Toi', en: 'You', ar: 'أنت'),
                score: '${me.score}',
                sub:
                    '${me.correct}/${DuelRules.questionCount} ✓',
                highlight: me.score >= opp.score,
                badge: me.isFrozen(now)
                    ? '❄'
                    : (iDouble ? '×2' : null),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ScoreCard(
                key: const Key('duelOppScore'),
                title: _t(
                    fr: 'Adversaire',
                    en: 'Opponent',
                    ar: 'الخصم'),
                score: '${opp.score}',
                sub:
                    '${opp.correct}/${DuelRules.questionCount} ✓${opp.connected ? '' : ' 💤'}',
                highlight: opp.score > me.score,
                badge: oppFrozen ? '❄' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Voie partagée : les deux trains en direct.
        Container(
          height: boardH,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.midnight.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: AppColors.midnightLight, width: 1.5),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              Offset px(Offset n) =>
                  Offset(n.dx * c.maxWidth, n.dy * c.maxHeight);
              Widget train(
                  int correct, Color? tint, String? badge, Key key) {
                final idx = correct.clamp(0, kTiles.length - 1);
                final p = px(kTiles[idx].pos);
                return Positioned(
                  key: key,
                  left:
                      (p.dx - 34).clamp(0.0, c.maxWidth - 68),
                  top: (p.dy - 50).clamp(0.0, c.maxHeight - 60),
                  child: _DuelTrain(tint: tint, badge: badge),
                );
              }

              return Stack(
                children: [
                  const Positioned.fill(
                    child: CustomPaint(painter: BoardPainter()),
                  ),
                  train(me.correct, null,
                      me.isFrozen(now) ? '❄' : (iDouble ? '×2' : null),
                      const Key('duelMyTrain')),
                  train(
                      opp.correct,
                      AppColors.pinkPop,
                      oppFrozen ? '❄' : null,
                      const Key('duelOppTrain')),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Pouvoirs.
        Row(
          children: [
            for (final power in DuelPower.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _PowerButton(
                    key: Key('duelPower${power.apiName}'),
                    power: power,
                    lang: widget.lang,
                    enabled: !_powerBusy &&
                        !duel.isFinished &&
                        wallet >= power.cost &&
                        !(power == DuelPower.freeze && oppFrozen) &&
                        !(power == DuelPower.doubleGains && iDouble),
                    onTap: () => _power(duel, power),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Question perso.
        if (me.isFrozen(now))
          Container(
            key: const Key('duelFrozenBanner'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.skyPop.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: AppColors.skyPop, width: 1.5),
            ),
            child: Text(
              _t(
                fr: '❄ Gelé ! Réponse bloquée $frozenLeft s.',
                en: '❄ Frozen! Answers blocked for $frozenLeft s.',
                ar: '❄ مجمّد! الإجابات محظورة لـ $frozenLeft ث.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.cream, fontWeight: FontWeight.w800),
            ),
          )
        else if (finishedAll)
          Container(
            key: const Key('duelWaitingOpp'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.midnight.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.midnightLight, width: 1.5),
            ),
            child: Text(
              _t(
                fr: 'Tes 8 réponses sont jouées — l\u2019adversaire termine…',
                en: 'Your 8 answers are in — waiting on your opponent…',
                ar: 'أُرسلت إجاباتك الثماني — بانتظار الخصم…',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.creamDim),
            ),
          )
        else ...[
          Text(
            duel.questions.length > me.answered
                ? duel.questions[me.answered].text(widget.lang)
                : '',
            softWrap: true,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('duelAnswerField'),
            controller: _answer,
            onSubmitted: (_) => _submit(duel),
            textInputAction: TextInputAction.done,
            style: const TextStyle(
                color: AppColors.cream, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: _t(
                  fr: 'Ta réponse…',
                  en: 'Your answer…',
                  ar: 'إجابتك…'),
              hintStyle:
                  const TextStyle(color: AppColors.creamDim),
              filled: true,
              fillColor: AppColors.deepSpace,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: AppColors.midnightLight, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppColors.sun, width: 2),
              ),
            ),
          ),
          if (_formError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _formError!,
                key: const Key('duelAnswerError'),
                style: const TextStyle(
                    color: AppColors.pinkPop,
                    fontWeight: FontWeight.w700),
              ),
            ),
          const SizedBox(height: 10),
          GameButton(
            key: const Key('duelSubmitButton'),
            label: _submitting
                ? _t(
                    fr: 'Envoi…', en: 'Sending…', ar: 'جارٍ الإرسال…')
                : _t(
                    fr: 'Valider', en: 'Submit', ar: 'تأكيد'),
            icon: Icons.check_rounded,
            height: 54,
            fontSize: 18,
            onPressed: _submitting ? null : () => _submit(duel),
          ),
        ],
        if (canForfeit) ...[
          const SizedBox(height: 10),
          GameButton(
            key: const Key('duelForfeitButton'),
            variant: GameButtonVariant.gold,
            label: _t(
              fr: 'Réclamer la victoire',
              en: 'Claim the win',
              ar: 'المطالبة بالفوز',
            ),
            icon: Icons.flag_rounded,
            height: 54,
            fontSize: 16,
            onPressed: _forfeit,
          ),
        ],
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    super.key,
    required this.title,
    required this.score,
    required this.sub,
    required this.highlight,
    this.badge,
  });

  final String title;
  final String score;
  final String sub;
  final bool highlight;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.midnight.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? AppColors.sun : AppColors.midnightLight,
          width: highlight ? 2 : 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 4),
                Text(badge!,
                    style: const TextStyle(fontSize: 14)),
              ],
            ],
          ),
          Text(
            score,
            style: const TextStyle(
              color: AppColors.cream,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(sub,
              style:
                  const TextStyle(color: AppColors.creamDim, fontSize: 12)),
        ],
      ),
    );
  }
}

class _DuelTrain extends StatelessWidget {
  const _DuelTrain({this.tint, this.badge});

  final Color? tint;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 68,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: (tint ?? AppColors.sun).withValues(alpha: 0.5),
                  blurRadius: 12,
                ),
              ],
            ),
            child: const FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                  width: 212, height: 90, child: CuteTrain()),
            ),
          ),
          if (badge != null)
            Positioned(
              top: -12,
              right: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.sun, width: 1.5),
                ),
                child: Text(badge!,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w900)),
              ),
            ),
        ],
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    super.key,
    required this.power,
    required this.lang,
    required this.enabled,
    required this.onTap,
  });

  final DuelPower power;
  final AppLang lang;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = switch (power) {
      DuelPower.freeze => ('❄', switch (lang) {
        AppLang.fr => 'Gel',
        AppLang.en => 'Freeze',
        AppLang.ar => 'تجميد'
      }),
      DuelPower.doubleGains => ('×2', switch (lang) {
        AppLang.fr => 'Double',
        AppLang.en => 'Double',
        AppLang.ar => 'مضاعفة'
      }),
      DuelPower.steal => ('🪙', switch (lang) {
        AppLang.fr => 'Vol',
        AppLang.en => 'Steal',
        AppLang.ar => 'سرقة'
      }),
    };
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.midnightLight.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.sun, width: 1.5),
          ),
          child: Column(
            children: [
              Text(data.$1, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 2),
              Text(
                data.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.cream,
                    fontWeight: FontWeight.w800,
                    fontSize: 13),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '−${power.cost} 🪙',
                  style: const TextStyle(
                      color: AppColors.sun,
                      fontWeight: FontWeight.w900,
                      fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.backLabel,
    required this.onBack,
  });

  final String message;
  final String backLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 64, color: AppColors.pinkPop),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            GameButton(
              label: backLabel,
              icon: Icons.arrow_back_rounded,
              onPressed: onBack,
            ),
          ],
        ),
      ),
    );
  }
}
