import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n/app_lang.dart';
import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/game_button.dart';
import '../board/questions.dart';

/// Duel hors ligne contre le "Train fantôme" (bot local).
/// Utilisé quand le serveur n'est pas joignable : 8 questions de la banque
/// locale, le bot répond au hasard (~60 % de réussite), scores en direct.
/// Les jetons gagnés sont persistés dans [AppPrefs] comme en solo.
class DuelOfflineScreen extends StatefulWidget {
  const DuelOfflineScreen({super.key, this.prefs, this.lang = AppLang.fr});

  final AppPrefs? prefs;
  final AppLang lang;

  @override
  State<DuelOfflineScreen> createState() => _DuelOfflineScreenState();
}

class _DuelOfflineScreenState extends State<DuelOfflineScreen> {
  static const int maxQuestions = 8;

  final _answer = TextEditingController();
  final _rng = math.Random();

  int _qIndex = 0;
  int _myScore = 0;
  int _botScore = 0;
  int _myCorrect = 0;
  int _botCorrect = 0;
  int _earned = 0;
  String? _feedback;
  bool _finished = false;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  String _t({required String fr, required String en, required String ar}) =>
      switch (widget.lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar
      };

  QuizQuestion get _question => kQuestions[_qIndex % kQuestions.length];

  Future<void> _persistTokens(int tokens) async {
    final p = widget.prefs;
    if (p == null) return;
    await p.setTokens(tokens);
  }

  void _submit() {
    if (_finished) return;
    final q = _question;
    final ok = q.check(_answer.text, widget.lang);
    // Le bot répond au hasard à la même question.
    final botOk = _rng.nextDouble() < 0.6;
    setState(() {
      if (ok) {
        _myScore += 100;
        _myCorrect += 1;
        _earned += 10;
        final p = widget.prefs;
        if (p != null) {
          final next = p.tokens + 10;
          _persistTokens(next);
        }
      }
      if (botOk) {
        _botScore += 100;
        _botCorrect += 1;
      }
      if (ok && botOk) {
        _feedback = _t(
            fr: 'Tous les deux au but !',
            en: 'Both on target!',
            ar: 'كلاكما أصاب!');
      } else if (ok) {
        _feedback = _t(
            fr: 'Bonne réponse, tu prends la tête !',
            en: 'Correct, you take the lead!',
            ar: 'إجابة صحيحة، تتقدم!');
      } else if (botOk) {
        _feedback = _t(
            fr: 'Raté — le fantôme marque.',
            en: 'Missed — the ghost scores.',
            ar: 'خطأ — الشبح يسجل.');
      } else {
        _feedback = _t(
            fr: 'Personne ne marque.',
            en: 'Nobody scores.',
            ar: 'لا أحد يسجل.');
      }
      _answer.clear();
      _qIndex += 1;
      if (_qIndex >= maxQuestions) _finished = true;
    });
  }

  void _skip() {
    if (_finished) return;
    final botOk = _rng.nextDouble() < 0.6;
    setState(() {
      if (botOk) {
        _botScore += 100;
        _botCorrect += 1;
      }
      _feedback = _t(
          fr: 'Question passée.', en: 'Question skipped.', ar: 'تم تخطي السؤال.');
      _answer.clear();
      _qIndex += 1;
      if (_qIndex >= maxQuestions) _finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection:
          widget.lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('duelOfflineScreen'),
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration:
              const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
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
                              fr: 'Duel fantôme (hors ligne)',
                              en: 'Ghost duel (offline)',
                              ar: 'مبارزة الشبح (دون اتصال)'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ScoreRow(
                    myScore: _myScore,
                    botScore: _botScore,
                    qIndex: _qIndex.clamp(0, maxQuestions),
                    max: maxQuestions,
                    lang: widget.lang,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _finished
                        ? _ResultCard(
                            myScore: _myScore,
                            botScore: _botScore,
                            myCorrect: _myCorrect,
                            botCorrect: _botCorrect,
                            earned: _earned,
                            lang: widget.lang,
                            onReplay: () => setState(() {
                              _qIndex = 0;
                              _myScore = 0;
                              _botScore = 0;
                              _myCorrect = 0;
                              _botCorrect = 0;
                              _earned = 0;
                              _feedback = null;
                              _finished = false;
                            }),
                            onQuit: () =>
                                Navigator.of(context).pop(),
                          )
                        : _QuestionCard(
                            question: _question.prompt(widget.lang),
                            answerController: _answer,
                            feedback: _feedback,
                            lang: widget.lang,
                            onSubmit: _submit,
                            onSkip: _skip,
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

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.myScore,
    required this.botScore,
    required this.qIndex,
    required this.max,
    required this.lang,
  });

  final int myScore;
  final int botScore;
  final int qIndex;
  final int max;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    String t({required String fr, required String en, required String ar}) =>
        switch (lang) { AppLang.fr => fr, AppLang.en => en, AppLang.ar => ar };
    return Container(
      key: const Key('duelOfflineScore'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.midnight.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: AppColors.midnightLight, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Text(t(fr: 'Toi', en: 'You', ar: 'أنت'),
                    style: const TextStyle(
                        color: AppColors.creamDim,
                        fontWeight: FontWeight.w800)),
                Text('$myScore',
                    style: const TextStyle(
                        color: AppColors.sun,
                        fontWeight: FontWeight.w900,
                        fontSize: 24)),
              ],
            ),
          ),
          Text(
            t(fr: 'Question ${qIndex + 1}/$max', en: 'Question ${qIndex + 1}/$max', ar: 'سؤال ${qIndex + 1}/$max'),
            style: const TextStyle(
                color: AppColors.cream, fontWeight: FontWeight.w800),
          ),
          Expanded(
            child: Column(
              children: [
                Text(t(fr: 'Fantôme', en: 'Ghost', ar: 'الشبح'),
                    style: const TextStyle(
                        color: AppColors.creamDim,
                        fontWeight: FontWeight.w800)),
                Text('$botScore',
                    style: const TextStyle(
                        color: AppColors.skyPop,
                        fontWeight: FontWeight.w900,
                        fontSize: 24)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.answerController,
    required this.feedback,
    required this.lang,
    required this.onSubmit,
    required this.onSkip,
  });

  final String question;
  final TextEditingController answerController;
  final String? feedback;
  final AppLang lang;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    String t({required String fr, required String en, required String ar}) =>
        switch (lang) { AppLang.fr => fr, AppLang.en => en, AppLang.ar => ar };
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.midnight.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: AppColors.midnightLight, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(question,
                  style:
                      Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              TextField(
                key: const Key('duelOfflineAnswerField'),
                controller: answerController,
                onSubmitted: (_) => onSubmit(),
                textInputAction: TextInputAction.done,
                style: const TextStyle(
                    color: AppColors.cream,
                    fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: t(
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
                    borderSide: const BorderSide(
                        color: AppColors.sun, width: 2),
                  ),
                ),
              ),
              if (feedback != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(feedback!,
                      style: const TextStyle(
                          color: AppColors.sun,
                          fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 12),
              GameButton(
                key: const Key('duelOfflineSubmitButton'),
                label: t(fr: 'Valider', en: 'Submit', ar: 'تأكيد'),
                icon: Icons.check_rounded,
                onPressed: onSubmit,
              ),
              TextButton(
                key: const Key('duelOfflineSkipButton'),
                onPressed: onSkip,
                child: Text(
                  t(
                      fr: 'Passer',
                      en: 'Skip',
                      ar: 'تخطي'),
                  style: const TextStyle(
                      color: AppColors.creamDim,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.myScore,
    required this.botScore,
    required this.myCorrect,
    required this.botCorrect,
    required this.earned,
    required this.lang,
    required this.onReplay,
    required this.onQuit,
  });

  final int myScore;
  final int botScore;
  final int myCorrect;
  final int botCorrect;
  final int earned;
  final AppLang lang;
  final VoidCallback onReplay;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    String t({required String fr, required String en, required String ar}) =>
        switch (lang) { AppLang.fr => fr, AppLang.en => en, AppLang.ar => ar };
    final title = myScore > botScore
        ? t(fr: 'Victoire !', en: 'Victory!', ar: 'فوز!')
        : myScore < botScore
            ? t(fr: 'Le fantôme gagne', en: 'Ghost wins', ar: 'الشبح يفوز')
            : t(fr: 'Match nul', en: 'Draw', ar: 'تعادل');
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.midnight.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: AppColors.midnightLight, width: 1.5),
          ),
          child: Column(
            children: [
              Text(title,
                  style:
                      Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('$myScore — $botScore',
                  style: const TextStyle(
                      color: AppColors.sun,
                      fontWeight: FontWeight.w900,
                      fontSize: 28)),
              const SizedBox(height: 4),
              Text(
                t(
                    fr: 'Bonnes réponses : toi $myCorrect, fantôme $botCorrect • +$earned jetons',
                    en: 'Correct: you $myCorrect, ghost $botCorrect • +$earned tokens',
                    ar: 'إجابات صحيحة: أنت $myCorrect، الشبح $botCorrect • +$earned رموز'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.creamDim),
              ),
              const SizedBox(height: 14),
              GameButton(
                key: const Key('duelOfflineReplayButton'),
                label: t(fr: 'Rejouer', en: 'Rematch', ar: 'إعادة'),
                icon: Icons.refresh_rounded,
                onPressed: onReplay,
              ),
              const SizedBox(height: 10),
              GameButton(
                key: const Key('duelOfflineQuitButton'),
                variant: GameButtonVariant.secondary,
                label: t(fr: 'Accueil', en: 'Home', ar: 'الرئيسية'),
                icon: Icons.home_rounded,
                onPressed: onQuit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
