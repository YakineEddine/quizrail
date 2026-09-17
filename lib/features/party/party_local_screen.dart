import 'package:flutter/material.dart';

import '../../core/i18n/app_lang.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/game_button.dart';
import '../board/questions.dart';

/// Party locale "même écran" (hotseat) : aucun réseau requis.
/// Les joueurs se passent le téléphone, chacun répond à tour de rôle
/// aux 8 questions de la banque locale. Idéal en attendant le backend.
class PartyLocalScreen extends StatefulWidget {
  const PartyLocalScreen({super.key, this.lang = AppLang.fr});

  final AppLang lang;

  @override
  State<PartyLocalScreen> createState() => _PartyLocalScreenState();
}

class _PartyLocalScreenState extends State<PartyLocalScreen> {
  static const int maxQuestions = 8;
  static const int maxPlayers = 4;

  final List<TextEditingController> _names = [
    TextEditingController(),
    TextEditingController(),
  ];
  final _answer = TextEditingController();

  bool _started = false;
  int _qIndex = 0;
  int _playerTurn = 0;
  late List<int> _scores = [0, 0];
  String? _error;
  String? _feedback;

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    _answer.dispose();
    super.dispose();
  }

  String _t({required String fr, required String en, required String ar}) =>
      switch (widget.lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar
      };

  List<String> get _playerNames =>
      _names.map((c) => c.text.trim()).toList();

  void _addPlayer() {
    if (_names.length >= maxPlayers) return;
    setState(() => _names.add(TextEditingController()));
  }

  void _start() {
    final names = _playerNames;
    if (names.any((n) => n.isEmpty)) {
      setState(() => _error = _t(
          fr: 'Donne un pseudo à chaque joueur.',
          en: 'Give every player a nickname.',
          ar: 'أعطِ كل لاعب اسمًا.'));
      return;
    }
    if (names.toSet().length != names.length) {
      setState(() => _error = _t(
          fr: 'Pseudos identiques : change-en un.',
          en: 'Duplicate nicknames: change one.',
          ar: 'أسماء مكررة: غيّر واحدًا.'));
      return;
    }
    setState(() {
      _started = true;
      _scores = List.filled(names.length, 0);
      _qIndex = 0;
      _playerTurn = 0;
      _error = null;
      _feedback = null;
    });
  }

  bool get _finished => _qIndex >= maxQuestions;

  void _submit() {
    if (!_started || _finished) return;
    final q = kQuestions[_qIndex % kQuestions.length];
    final ok = q.check(_answer.text, widget.lang);
    setState(() {
      if (ok) _scores[_playerTurn] += 100;
      final name = _playerNames[_playerTurn];
      _feedback = ok
          ? _t(
              fr: 'Bonne réponse pour $name ! (+100)',
              en: 'Correct for $name! (+100)',
              ar: 'إجابة صحيحة لـ $name! (+100)')
          : _t(
              fr: 'Raté pour $name.',
              en: 'Missed for $name.',
              ar: 'خطأ لـ $name.');
      _answer.clear();
      _playerTurn += 1;
      if (_playerTurn >= _playerNames.length) {
        _playerTurn = 0;
        _qIndex += 1;
      }
    });
  }

  void _skip() {
    if (!_started || _finished) return;
    setState(() {
      _answer.clear();
      _feedback = null;
      _playerTurn += 1;
      if (_playerTurn >= _playerNames.length) {
        _playerTurn = 0;
        _qIndex += 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection:
          widget.lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('partyLocalScreen'),
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
                        onPressed: () =>
                            Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.cream),
                      ),
                      Expanded(
                        child: Text(
                          _t(
                              fr: 'Party locale',
                              en: 'Local party',
                              ar: 'حفلة محلية'),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: !_started
                        ? _SetupView(
                            names: _names,
                            error: _error,
                            canAdd:
                                _names.length < maxPlayers,
                            lang: widget.lang,
                            onAdd: _addPlayer,
                            onStart: _start,
                          )
                        : _finished
                            ? _LocalResults(
                                names: _playerNames,
                                scores: _scores,
                                lang: widget.lang,
                                onReplay: () => setState(() {
                                  _started = false;
                                  _qIndex = 0;
                                  _playerTurn = 0;
                                  _feedback = null;
                                }),
                                onQuit: () =>
                                    Navigator.of(context).pop(),
                              )
                            : _TurnView(
                                question: kQuestions[
                                        _qIndex %
                                            kQuestions.length]
                                    .prompt(widget.lang),
                                qIndex: _qIndex,
                                max: maxQuestions,
                                playerName: _playerNames[
                                    _playerTurn %
                                        _playerNames.length],
                                scores: _scores,
                                names: _playerNames,
                                answer: _answer,
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

class _SetupView extends StatelessWidget {
  const _SetupView({
    required this.names,
    required this.error,
    required this.canAdd,
    required this.lang,
    required this.onAdd,
    required this.onStart,
  });

  final List<TextEditingController> names;
  final String? error;
  final bool canAdd;
  final AppLang lang;
  final VoidCallback onAdd;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    String t({required String fr, required String en, required String ar}) =>
        switch (lang) { AppLang.fr => fr, AppLang.en => en, AppLang.ar => ar };
    return ListView(
      children: [
        Text(
          t(
              fr: '2 à 4 joueurs sur ce téléphone : passez-vous l\u2019écran à tour de rôle. 8 questions, +100 par bonne réponse.',
              en: '2 to 4 players on this phone: pass the screen around. 8 questions, +100 per correct answer.',
              ar: 'من 2 إلى 4 لاعبين على هذا الهاتف: تناوبوا على الشاشة. 8 أسئلة، +100 لكل إجابة صحيحة.'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < names.length; i++) ...[
          Text(
            t(fr: 'Joueur ${i + 1}', en: 'Player ${i + 1}', ar: 'لاعب ${i + 1}'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          TextField(
            key: Key('partyLocalNameField_$i'),
            controller: names[i],
            textInputAction: TextInputAction.next,
            style: const TextStyle(
                color: AppColors.cream, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: t(
                  fr: 'Pseudo…', en: 'Nickname…', ar: 'الاسم…'),
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
          const SizedBox(height: 10),
        ],
        if (canAdd)
          TextButton.icon(
            key: const Key('partyLocalAddButton'),
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_rounded,
                color: AppColors.sun),
            label: Text(
              t(
                  fr: 'Ajouter un joueur',
                  en: 'Add a player',
                  ar: 'إضافة لاعب'),
              style: const TextStyle(
                  color: AppColors.sun,
                  fontWeight: FontWeight.w800),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error!,
                style: const TextStyle(
                    color: AppColors.pinkPop,
                    fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 14),
        GameButton(
          key: const Key('partyLocalStartButton'),
          label: t(
              fr: 'Démarrer la party',
              en: 'Start party',
              ar: 'بدء الحفلة'),
          icon: Icons.play_arrow_rounded,
          onPressed: onStart,
        ),
      ],
    );
  }
}

class _TurnView extends StatelessWidget {
  const _TurnView({
    required this.question,
    required this.qIndex,
    required this.max,
    required this.playerName,
    required this.scores,
    required this.names,
    required this.answer,
    required this.feedback,
    required this.lang,
    required this.onSubmit,
    required this.onSkip,
  });

  final String question;
  final int qIndex;
  final int max;
  final String playerName;
  final List<int> scores;
  final List<String> names;
  final TextEditingController answer;
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.midnight.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppColors.midnightLight, width: 1.5),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (var i = 0; i < names.length; i++)
                Chip(
                  label: Text('${names[i]} • ${scores[i]}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          t(
              fr: 'Question ${qIndex + 1}/$max — au tour de $playerName',
              en: 'Question ${qIndex + 1}/$max — $playerName to play',
              ar: 'سؤال ${qIndex + 1}/$max — دور $playerName'),
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: AppColors.sun),
        ),
        const SizedBox(height: 6),
        Text(question,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        TextField(
          key: const Key('partyLocalAnswerField'),
          controller: answer,
          onSubmitted: (_) => onSubmit(),
          textInputAction: TextInputAction.done,
          style: const TextStyle(
              color: AppColors.cream, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText:
                t(fr: 'Réponse…', en: 'Answer…', ar: 'الإجابة…'),
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
          key: const Key('partyLocalSubmitButton'),
          label:
              t(fr: 'Valider', en: 'Submit', ar: 'تأكيد'),
          icon: Icons.check_rounded,
          onPressed: onSubmit,
        ),
        TextButton(
          onPressed: onSkip,
          child: Text(
            t(fr: 'Passer', en: 'Skip', ar: 'تخطي'),
            style: const TextStyle(
                color: AppColors.creamDim,
                fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _LocalResults extends StatelessWidget {
  const _LocalResults({
    required this.names,
    required this.scores,
    required this.lang,
    required this.onReplay,
    required this.onQuit,
  });

  final List<String> names;
  final List<int> scores;
  final AppLang lang;
  final VoidCallback onReplay;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    String t({required String fr, required String en, required String ar}) =>
        switch (lang) { AppLang.fr => fr, AppLang.en => en, AppLang.ar => ar };
    final order = List.generate(names.length, (i) => i)
      ..sort((a, b) => scores[b].compareTo(scores[a]));
    final winner = names[order.first];
    return ListView(
      children: [
        Container(
          key: const Key('partyLocalWinnerBanner'),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.midnight.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: AppColors.midnightLight, width: 1.5),
          ),
          child: Column(
            children: [
              Text(
                t(
                    fr: '$winner gagne la Party !',
                    en: '$winner wins the party!',
                    ar: '$winner يفوز بالحفلة!'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              for (final i in order)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(names[i],
                            style: const TextStyle(
                                color: AppColors.cream,
                                fontWeight: FontWeight.w800)),
                      ),
                      Text('${scores[i]}',
                          style: const TextStyle(
                              color: AppColors.sun,
                              fontWeight: FontWeight.w900,
                              fontSize: 18)),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              GameButton(
                key: const Key('partyLocalReplayButton'),
                label: t(
                    fr: 'Rejouer', en: 'Rematch', ar: 'إعادة'),
                icon: Icons.refresh_rounded,
                onPressed: onReplay,
              ),
              const SizedBox(height: 10),
              GameButton(
                key: const Key('partyLocalQuitButton'),
                variant: GameButtonVariant.secondary,
                label: t(
                    fr: 'Quitter', en: 'Leave', ar: 'مغادرة'),
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
