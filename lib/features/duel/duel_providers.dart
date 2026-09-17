import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/game_duel.dart';
import 'duel_service.dart';

/// Service duel injectable (Supabase en prod, fake en tests).
final duelServiceProvider = Provider<DuelService>((ref) {
  return SupabaseDuelService();
});

/// Doc duel en temps réel (positions + scores adverses en direct).
final duelStreamProvider =
    StreamProvider.autoDispose.family<GameDuel, String>((ref, duelId) {
  return ref.watch(duelServiceProvider).watchDuel(duelId);
});

enum DuelSearchPhase { idle, searching, matched, timeout, error }

class DuelSearchState {
  const DuelSearchState({
    this.phase = DuelSearchPhase.idle,
    this.duelId,
    this.opponentUid,
    this.error,
  });

  final DuelSearchPhase phase;
  final String? duelId;
  final String? opponentUid;
  final String? error;
}

/// Matchmaking : rejoint la file puis interroge findDuel toutes les 3 s
/// (appariement atomique côté serveur). Timeout 60 s.
class DuelSearchController extends Notifier<DuelSearchState> {
  Timer? _timer;
  int _tries = 0;
  bool _cancelled = false;
  static const int maxTries = 20;
  static const Duration pollEvery = Duration(seconds: 3);

  @override
  DuelSearchState build() {
    ref.onDispose(() {
      _cancelled = true;
      _timer?.cancel();
    });
    return const DuelSearchState();
  }

  DuelService get _service => ref.read(duelServiceProvider);

  Future<void> search({required String lang}) async {
    _cancelled = false;
    _tries = 0;
    _timer?.cancel();
    state = const DuelSearchState(phase: DuelSearchPhase.searching);
    await _attempt(lang);
    if (_cancelled || state.phase != DuelSearchPhase.searching) return;
    _timer = Timer.periodic(pollEvery, (_) => _attempt(lang));
  }

  Future<void> _attempt(String lang) async {
    if (_cancelled) return;
    _tries++;
    try {
      final res = await _service.findDuel(lang: lang);
      if (_cancelled) return;
      if (res.matched && res.duelId != null) {
        _timer?.cancel();
        state = DuelSearchState(
          phase: DuelSearchPhase.matched,
          duelId: res.duelId,
          opponentUid: res.opponentUid,
        );
        return;
      }
      if (_tries >= maxTries) {
        _timer?.cancel();
        await _service.leaveQueue();
        if (!_cancelled && ref.mounted) {
          state = const DuelSearchState(phase: DuelSearchPhase.timeout);
        }
      }
    } catch (e) {
      if (_cancelled) return;
      _timer?.cancel();
      if (ref.mounted) {
        state = DuelSearchState(
          phase: DuelSearchPhase.error,
          error: e is StateError ? e.message : 'Erreur réseau.',
        );
      }
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    _timer?.cancel();
    await _service.leaveQueue();
    if (ref.mounted) state = const DuelSearchState();
  }
}

final duelSearchProvider =
    NotifierProvider.autoDispose<DuelSearchController, DuelSearchState>(
        DuelSearchController.new);
