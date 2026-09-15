import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/party.dart';
import 'party_service.dart';

/// Service Party injectable (cloud en prod, fake en tests).
final partyServiceProvider = Provider<PartyService>((ref) {
  return CloudPartyService();
});

/// Room en temps réel (état global animé par le host).
final partyRoomProvider =
    StreamProvider.autoDispose.family<PartyRoom, String>((ref, roomId) {
  return ref.watch(partyServiceProvider).watchRoom(roomId);
});

/// Joueurs triés par score (classement live).
final partyPlayersProvider =
    StreamProvider.autoDispose.family<List<PartyPlayer>, String>(
        (ref, roomId) {
  return ref.watch(partyServiceProvider).watchPlayers(roomId);
});
