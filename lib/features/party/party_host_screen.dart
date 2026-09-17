import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/data/backend.dart';
import '../../core/i18n/app_lang.dart';
import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/game_button.dart';
import '../../features/tunnel/custom_tunnel.dart';
import '../../features/tunnel/custom_tunnel_store.dart';
import 'party_local_screen.dart';
import 'party_providers.dart';
import 'party_results_screen.dart';
import 'party_service.dart';

/// Écran Host Party : création (thème + tunnel), salon (code + QR),
/// animation live (question suivante / terminer), puis résultats.
/// Le host ne répond pas : il anime depuis cet écran.
class PartyHostScreen extends ConsumerStatefulWidget {
  const PartyHostScreen({
    super.key,
    this.lang = AppLang.fr,
    this.prefs,
    this.uid,
    this.roomId,
    this.store,
  });

  final AppLang lang;
  final AppPrefs? prefs;
  final String? uid;
  final String? roomId;
  final CustomTunnelStore? store;

  @override
  ConsumerState<PartyHostScreen> createState() => _PartyHostScreenState();
}

class _PartyHostScreenState extends ConsumerState<PartyHostScreen> {
  final _theme = TextEditingController();
  late final String _uid = widget.uid ?? Backend.instance.uid ?? '';
  late final PartyService _service;

  String? _roomId;
  bool _creating = false;
  bool _retrying = false;
  String? _error;
  CustomTunnel? _pickedCustom;
  List<CustomTunnel> _customs = [];
  Timer? _heartbeat;
  bool _navigated = false;

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
    _roomId = widget.roomId;
    final store = widget.store;
    if (store != null) {
      _customs = store.tunnels.where((t) => t.isValid).toList();
    } else {
      CustomTunnelStore.load().then((s) {
        if (mounted) {
          setState(
              () => _customs = s.tunnels.where((t) => t.isValid).toList());
        }
      });
    }
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      final id = _roomId;
      if (id != null) {
        _service.setPresence(roomId: id, connected: true);
      }
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _theme.dispose();
    final id = _roomId;
    if (id != null) {
      _service.setPresence(roomId: id, connected: false);
    }
    super.dispose();
  }

  bool get _isOfflineError =>
      _error != null && _error!.toLowerCase().contains('hors ligne');

  Future<void> _retryConnection() async {
    if (_retrying) return;
    setState(() {
      _retrying = true;
      _error = null;
    });
    try {
      await Backend.instance.retry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
    if (mounted) await _create();
  }

  void _goLocal() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PartyLocalScreen(lang: widget.lang),
      ),
    );
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final ref = await this
          .ref
          .read(partyServiceProvider)
          .createParty(
            theme: _theme.text.trim().isEmpty ? null : _theme.text.trim(),
            customTunnel: _pickedCustom,
            lang: widget.lang.code,
          );
      if (mounted) setState(() => _roomId = ref.roomId);
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _start() async {
    final id = _roomId;
    if (id == null) return;
    try {
      await _service.startParty(roomId: id);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _next() async {
    final id = _roomId;
    if (id == null) return;
    try {
      await _service.advanceParty(roomId: id);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _end() async {
    final id = _roomId;
    if (id == null) return;
    try {
      await _service.endParty(roomId: id);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _quit() async {
    final id = _roomId;
    if (id != null) {
      try {
        await _service.leaveParty(roomId: id);
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _goResults() {
    if (_navigated || _roomId == null) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PartyResultsScreen(
            roomId: _roomId!,
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
    final roomId = _roomId;
    return Directionality(
      textDirection:
          widget.lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('partyHostScreen'),
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration:
              const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: roomId == null
                ? _buildSetup(context)
                : _buildLive(context, roomId),
          ),
        ),
      ),
    );
  }

  Widget _buildSetup(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                    fr: 'Créer une Party',
                    en: 'Create a party',
                    ar: 'إنشاء حفلة'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _t(fr: 'Thème', en: 'Theme', ar: 'الموضوع'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        TextField(
          key: const Key('partyThemeField'),
          controller: _theme,
          style: const TextStyle(
              color: AppColors.cream, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: _t(
                fr: 'Ex : Animaux (optionnel)',
                en: 'E.g. Animals (optional)',
                ar: 'مثال: حيوانات (اختياري)'),
            hintStyle: const TextStyle(color: AppColors.creamDim),
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
        const SizedBox(height: 12),
        Text(
          _t(
              fr: 'Tunnel joué',
              en: 'Tunnel to play',
              ar: 'النفق المعروض'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.deepSpace,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.midnightLight, width: 1.5),
          ),
          child: DropdownButton<CustomTunnel?>(
            key: const Key('partyTunnelPicker'),
            value: _pickedCustom,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: AppColors.midnight,
            style: const TextStyle(
                color: AppColors.cream, fontWeight: FontWeight.w700),
            items: [
              DropdownMenuItem<CustomTunnel?>(
                value: null,
                child: Text(_t(
                    fr: '★ Banque standard (8 questions)',
                    en: '★ Standard bank (8 questions)',
                    ar: '★ البنك القياسي (8 أسئلة)')),
              ),
              for (final t in _customs)
                DropdownMenuItem<CustomTunnel?>(
                  value: t,
                  child: Text(t.theme,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _pickedCustom = v),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                _isOfflineError
                    ? _t(
                        fr: 'Serveur Party injoignable. Vérifie ta connexion ou joue en Party locale en attendant.',
                        en: 'Party server unreachable. Check your connection or play a local party meanwhile.',
                        ar: 'تعذر الوصول لخادم الحفلة. تحقق من الاتصال أو العب حفلة محلية مؤقتًا.',
                      )
                    : _error!,
                style: const TextStyle(
                    color: AppColors.pinkPop,
                    fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 16),
        GameButton(
          key: const Key('partyCreateButton'),
          label: _creating
              ? _t(fr: 'Création…', en: 'Creating…', ar: 'جارٍ الإنشاء…')
              : _retrying
                  ? _t(
                      fr: 'Connexion…',
                      en: 'Connecting…',
                      ar: 'جارٍ الاتصال…')
                  : _t(
                      fr: 'Créer la room',
                      en: 'Create room',
                      ar: 'إنشاء الغرفة'),
          icon: Icons.group_add_rounded,
          onPressed: (_creating || _retrying) ? null : _create,
        ),
        if (_isOfflineError) ...[
          const SizedBox(height: 10),
          GameButton(
            key: const Key('partyRetryButton'),
            label: _t(
                fr: 'Réessayer la connexion',
                en: 'Retry connection',
                ar: 'إعادة الاتصال'),
            icon: Icons.refresh_rounded,
            onPressed: _retrying ? null : _retryConnection,
          ),
          const SizedBox(height: 10),
          GameButton(
            key: const Key('partyLocalButton'),
            variant: GameButtonVariant.gold,
            label: _t(
                fr: 'Party locale (même écran)',
                en: 'Local party (same screen)',
                ar: 'حفلة محلية (نفس الشاشة)'),
            icon: Icons.smartphone_rounded,
            onPressed: _goLocal,
          ),
        ],
      ],
    );
  }

  Widget _buildLive(BuildContext context, String roomId) {
    final asyncRoom = ref.watch(partyRoomProvider(roomId));
    final asyncPlayers = ref.watch(partyPlayersProvider(roomId));

    ref.listen(partyRoomProvider(roomId), (_, next) {
      next.whenData((room) {
        if (room.isFinished) _goResults();
      });
    });

    return asyncRoom.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.sun),
      ),
      error: (e, _) => Center(
        child: Text(
          e is StateError
              ? e.message
              : _t(
                  fr: 'Room indisponible.',
                  en: 'Room unavailable.',
                  ar: 'الغرفة غير متاحة.',
                ),
        ),
      ),
      data: (room) => ListView(
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
                  room.theme.isEmpty ? 'Party' : room.theme,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.midnight.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.midnightLight, width: 1.5),
                ),
                child: Text(
                  '${room.playerIds.length}/12',
                  style: const TextStyle(
                      color: AppColors.sun,
                      fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (room.isLobby) ...[
            // Code + QR à montrer aux joueurs.
            Center(
              child: Column(
                children: [
                  Text(
                    room.code,
                    key: const Key('partyCodeText'),
                    style: const TextStyle(
                      color: AppColors.sun,
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    key: const Key('partyQr'),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: AppColors.ink, width: 2),
                    ),
                    child: QrImageView(
                      data: room.code,
                      version: QrVersions.auto,
                      size: 150,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      fr: 'Les joueurs rejoignent avec ce code.',
                      en: 'Players join with this code.',
                      ar: 'ينضم اللاعبون بهذا الرمز.',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            // Animation : question courante + standings.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.midnight.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: AppColors.midnightLight, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      fr: 'Question ${room.questionIndex + 1}/${room.questions.length}',
                      en: 'Question ${room.questionIndex + 1}/${room.questions.length}',
                      ar: 'سؤال ${room.questionIndex + 1}/${room.questions.length}',
                    ),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: AppColors.sun),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    room.questions.isNotEmpty
                        ? room.questions[room.questionIndex
                                .clamp(0, room.questions.length - 1)]
                            .text(widget.lang)
                        : '',
                    style:
                        Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            _t(fr: 'Joueurs', en: 'Players', ar: 'اللاعبون'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          asyncPlayers.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                    color: AppColors.sun),
              ),
            ),
            error: (_, st) => Text(
              _t(
                  fr: 'Liste indisponible.',
                  en: 'List unavailable.',
                  ar: 'القائمة غير متاحة.'),
              style: const TextStyle(color: AppColors.creamDim),
            ),
            data: (players) => Column(
              key: const Key('partyLobbyList'),
              children: [
                for (final p in players)
                  _PlayerRow(
                    name: p.displayName.isEmpty ? '…' : p.displayName,
                    score: '${p.score}',
                    active: p.connected,
                    isHost: p.uid == room.hostId,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (room.isLobby)
            GameButton(
              key: const Key('partyStartButton'),
              label: _t(
                  fr: 'Démarrer (2+ joueurs)',
                  en: 'Start (2+ players)',
                  ar: 'بدء (لاعبان+)'),
              icon: Icons.play_arrow_rounded,
              onPressed: _start,
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: GameButton(
                    key: const Key('partyNextButton'),
                    variant: GameButtonVariant.secondary,
                    label: _t(
                        fr: 'Question suivante',
                        en: 'Next question',
                        ar: 'السؤال التالي'),
                    icon: Icons.skip_next_rounded,
                    height: 54,
                    fontSize: 16,
                    onPressed: _next,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GameButton(
                    key: const Key('partyEndButton'),
                    variant: GameButtonVariant.gold,
                    label: _t(
                        fr: 'Terminer', en: 'Finish', ar: 'إنهاء'),
                    icon: Icons.flag_rounded,
                    height: 54,
                    fontSize: 16,
                    onPressed: _end,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.name,
    required this.score,
    required this.active,
    required this.isHost,
  });

  final String name;
  final String score;
  final bool active;
  final bool isHost;

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
          if (isHost)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Text('👑', style: TextStyle(fontSize: 16)),
            ),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.cream, fontWeight: FontWeight.w800),
            ),
          ),
          if (!active)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Text('💤', style: TextStyle(fontSize: 14)),
            ),
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
