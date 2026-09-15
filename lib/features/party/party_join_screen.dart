import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/backend.dart';
import '../../core/i18n/app_lang.dart';
import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/game_button.dart';
import 'party_host_screen.dart';
import 'party_play_screen.dart';
import 'party_providers.dart';

/// Rejoindre une Party avec le code à 6 caractères, puis salon d'attente.
/// Bascule auto vers le jeu (ou l'écran host en cas de promotion).
class PartyJoinScreen extends ConsumerStatefulWidget {
  const PartyJoinScreen({
    super.key,
    this.lang = AppLang.fr,
    this.prefs,
    this.uid,
  });

  final AppLang lang;
  final AppPrefs? prefs;
  final String? uid;

  @override
  ConsumerState<PartyJoinScreen> createState() => _PartyJoinScreenState();
}

class _PartyJoinScreenState extends ConsumerState<PartyJoinScreen> {
  final _code = TextEditingController();
  late final String _uid = widget.uid ?? Backend.instance.uid ?? '';

  String? _roomId;
  bool _joining = false;
  String? _error;
  bool _navigated = false;

  String _t({required String fr, required String en, required String ar}) =>
      switch (widget.lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar
      };

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final ref = await this
          .ref
          .read(partyServiceProvider)
          .joinParty(code: _code.text);
      if (mounted) setState(() => _roomId = ref.roomId);
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _quit() async {
    final id = _roomId;
    if (id != null) {
      try {
        await ref.read(partyServiceProvider).leaveParty(roomId: id);
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _goPlay() {
    if (_navigated || _roomId == null) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PartyPlayScreen(
            roomId: _roomId!,
            lang: widget.lang,
            prefs: widget.prefs,
            uid: _uid,
          ),
        ),
      );
    });
  }

  void _goHost() {
    if (_navigated || _roomId == null) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PartyHostScreen(
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
    return Directionality(
      textDirection:
          widget.lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('partyJoinScreen'),
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration:
              const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: _roomId == null
                ? _buildJoin(context)
                : _buildLobby(context, _roomId!),
          ),
        ),
      ),
    );
  }

  Widget _buildJoin(BuildContext context) {
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
                    fr: 'Rejoindre une Party',
                    en: 'Join a party',
                    ar: 'الانضمام إلى حفلة'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          _t(
              fr: 'Code à 6 caractères donné par le host :',
              en: '6-character code from the host:',
              ar: 'الرمز المكوّن من 6 أحرف من المضيف:'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('partyCodeField'),
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.sun,
            fontWeight: FontWeight.w900,
            fontSize: 28,
            letterSpacing: 6,
          ),
          decoration: InputDecoration(
            counterText: '',
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
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                key: const Key('partyJoinError'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.pinkPop,
                    fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 16),
        GameButton(
          key: const Key('partyJoinButton'),
          label: _joining
              ? _t(
                  fr: 'Connexion…', en: 'Joining…', ar: 'جارٍ الانضمام…')
              : _t(
                  fr: 'Rejoindre', en: 'Join', ar: 'انضمام'),
          icon: Icons.login_rounded,
          onPressed: _joining ? null : _join,
        ),
      ],
    );
  }

  Widget _buildLobby(BuildContext context, String roomId) {
    final asyncRoom = ref.watch(partyRoomProvider(roomId));
    final asyncPlayers = ref.watch(partyPlayersProvider(roomId));

    ref.listen(partyRoomProvider(roomId), (_, next) {
      next.whenData((room) {
        if (room.isPlaying) {
          if (room.isHost(_uid)) {
            _goHost();
          } else {
            _goPlay();
          }
        }
      });
    });

    return asyncRoom.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.sun),
      ),
      error: (e, _) => Center(
        child: Text(e is StateError ? e.message : 'Room indisponible.'),
      ),
      data: (room) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
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
              ],
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 56,
              height: 56,
              child:
                  CircularProgressIndicator(color: AppColors.sun, strokeWidth: 5),
            ),
            const SizedBox(height: 12),
            Text(
              _t(
                fr: 'En attente du host…',
                en: 'Waiting for the host…',
                ar: 'بانتظار المضيف…',
              ),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: asyncPlayers.when(
                loading: () => const SizedBox(),
                error: (_, st) => const SizedBox(),
                data: (players) => ListView(
                  key: const Key('partyLobbyList'),
                  children: [
                    for (final p in players)
                      ListTile(
                        leading: Text(
                            p.uid == room.hostId ? '👑' : '🚂'),
                        title: Text(
                          p.displayName.isEmpty ? '…' : p.displayName,
                          style: const TextStyle(
                              color: AppColors.cream,
                              fontWeight: FontWeight.w800),
                        ),
                        trailing: p.connected
                            ? null
                            : const Text('💤'),
                      ),
                  ],
                ),
              ),
            ),
            GameButton(
              key: const Key('partyQuitButton'),
              variant: GameButtonVariant.secondary,
              label: _t(
                  fr: 'Quitter', en: 'Leave', ar: 'مغادرة'),
              icon: Icons.logout_rounded,
              onPressed: _quit,
            ),
          ],
        ),
      ),
    );
  }
}
