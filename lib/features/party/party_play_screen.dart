import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/backend.dart';
import '../../core/i18n/app_lang.dart';
import '../../core/models/party.dart';
import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/game_button.dart';
import 'party_providers.dart';
import 'party_results_screen.dart';
import 'party_service.dart';

/// Jeu Party côté joueur : question courante animée par le host,
/// réponse validée serveur, classement live.
class PartyPlayScreen extends ConsumerStatefulWidget {
  const PartyPlayScreen({
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
  ConsumerState<PartyPlayScreen> createState() => _PartyPlayScreenState();
}

class _PartyPlayScreenState extends ConsumerState<PartyPlayScreen> {
  final _answer = TextEditingController();
  late final String _uid = widget.uid ?? Backend.instance.uid ?? '';

  int _questionStartMs = DateTime.now().millisecondsSinceEpoch;
  int _lastIndexSeen = -1;
  bool _submitting = false;
  bool _answeredCurrent = false;
  String? _formError;
  bool _navigated = false;
  Timer? _heartbeat;
  late final PartyService _service;

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
    _service = ref.read(partyServiceProvider);
    _presence(true);
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      _presence(true);
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _presence(false);
    _answer.dispose();
    super.dispose();
  }

  Future<void> _presence(bool connected) async {
    try {
      await _service.setPresence(
          roomId: widget.roomId, connected: connected);
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (_submitting || _answeredCurrent) return;
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
      final res = await _service.submitAnswer(
                roomId: widget.roomId,
                answer: _answer.text,
                elapsedMs: DateTime.now().millisecondsSinceEpoch -
                    _questionStartMs,
                lang: widget.lang.code,
              );
      if (res.correct) {
        final p = widget.prefs;
        if (p != null) await p.setTokens(p.tokens + 10);
      }
      if (mounted) {
        setState(() {
          _answeredCurrent = true;
          _formError = res.correct
              ? null
              : _t(
                  fr: 'Raté ! Attends la prochaine question.',
                  en: 'Missed! Wait for the next question.',
                  ar: 'خطأ! انتظر السؤال التالي.',
                );
        });
      }
    } on StateError catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _quit() async {
    try {
      await ref
          .read(partyServiceProvider)
          .leaveParty(roomId: widget.roomId);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  void _goResults() {
    if (_navigated) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PartyResultsScreen(
            roomId: widget.roomId,
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
    final asyncRoom = ref.watch(partyRoomProvider(widget.roomId));
    final asyncPlayers = ref.watch(partyPlayersProvider(widget.roomId));

    ref.listen(partyRoomProvider(widget.roomId), (_, next) {
      next.whenData((room) {
        if (room.questionIndex != _lastIndexSeen) {
          _lastIndexSeen = room.questionIndex;
          _questionStartMs = DateTime.now().millisecondsSinceEpoch;
          _answer.clear();
          if (mounted) {
            setState(() {
              _answeredCurrent = false;
              _formError = null;
            });
          }
        }
        if (room.isFinished) _goResults();
      });
    });

    return Directionality(
      textDirection:
          widget.lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('partyPlayScreen'),
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration:
              const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: asyncRoom.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.sun),
              ),
              error: (e, _) => Center(
                child: Text(e is StateError ? e.message : 'Room indisponible.'),
              ),
              data: (room) => _buildLive(context, room, asyncPlayers),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLive(
    BuildContext context,
    PartyRoom room,
    AsyncValue<List<PartyPlayer>> asyncPlayers,
  ) {
    final idx = room.questionIndex.clamp(0, room.questions.length - 1);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _quit,
              icon: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.cream),
            ),
            Expanded(
              child: Text(
                _t(
                  fr: 'Question ${room.questionIndex + 1}/${room.questions.length}',
                  en: 'Question ${room.questionIndex + 1}/${room.questions.length}',
                  ar: 'سؤال ${room.questionIndex + 1}/${room.questions.length}',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.midnight.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: AppColors.midnightLight, width: 1.5),
          ),
          child: Text(
            room.questions.isNotEmpty
                ? room.questions[idx].text(widget.lang)
                : '',
            softWrap: true,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 12),
        if (_answeredCurrent)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.mintPop.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: AppColors.mintPop, width: 1.5),
            ),
            child: Text(
              _formError ??
                  _t(
                    fr: 'Réponse envoyée ✓ — attends le host.',
                    en: 'Answer sent ✓ — wait for the host.',
                    ar: 'أُرسلت الإجابة ✓ — انتظر المضيف.',
                  ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.cream, fontWeight: FontWeight.w800),
            ),
          )
        else ...[
          TextField(
            key: const Key('partyAnswerField'),
            controller: _answer,
            onSubmitted: (_) => _submit(),
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
                key: const Key('partyAnswerError'),
                style: const TextStyle(
                    color: AppColors.pinkPop,
                    fontWeight: FontWeight.w700),
              ),
            ),
          const SizedBox(height: 10),
          GameButton(
            key: const Key('partySubmitButton'),
            label: _submitting
                ? _t(
                    fr: 'Envoi…', en: 'Sending…', ar: 'جارٍ الإرسال…')
                : _t(
                    fr: 'Valider', en: 'Submit', ar: 'تأكيد'),
            icon: Icons.check_rounded,
            height: 54,
            fontSize: 18,
            onPressed: _submitting ? null : _submit,
          ),
        ],
        const SizedBox(height: 16),
        Text(
          _t(
              fr: 'Classement live',
              en: 'Live standings',
              ar: 'الترتيب المباشر'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        asyncPlayers.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child:
                  CircularProgressIndicator(color: AppColors.sun),
            ),
          ),
          error: (_, st) => const SizedBox(),
          data: (players) => Column(
            key: const Key('partyStandings'),
            children: [
              for (var i = 0; i < players.length; i++)
                _StandingRow(
                  rank: i + 1,
                  name: players[i].displayName.isEmpty
                      ? '…'
                      : players[i].displayName,
                  score: '${players[i].score}',
                  isMe: players[i].uid == _uid,
                  active: players[i].connected,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.name,
    required this.score,
    required this.isMe,
    required this.active,
  });

  final int rank;
  final String name;
  final String score;
  final bool isMe;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (isMe ? AppColors.sun : AppColors.midnight)
            .withValues(alpha: isMe ? 0.2 : 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe ? AppColors.sun : AppColors.midnightLight,
          width: isMe ? 2 : 1.5,
        ),
      ),
      child: Row(
        children: [
          Text(
            rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '$rank.',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.cream, fontWeight: FontWeight.w800),
            ),
          ),
          if (!active) const Text('💤'),
          const SizedBox(width: 6),
          Text(
            score,
            style: const TextStyle(
                color: AppColors.sun,
                fontWeight: FontWeight.w900,
                fontSize: 18),
          ),
        ],
      ),
    );
  }
}
