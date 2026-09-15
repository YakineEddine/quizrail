import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/leaderboard_entry.dart';
import 'social_service.dart';

/// Service social injectable (cloud en prod, fake en tests).
final socialServiceProvider = Provider<SocialService>((ref) {
  return CloudSocialService();
});

/// Profil perso (pays, pseudo, friendIds).
final myProfileProvider =
    StreamProvider.autoDispose<Map<String, Object?>>((ref) {
  return ref.watch(socialServiceProvider).watchMyProfile();
});

/// Classement mondial.
final leaderboardGlobalProvider =
    StreamProvider.autoDispose<List<LeaderboardEntry>>((ref) {
  return ref.watch(socialServiceProvider).watchGlobal();
});

/// Classement par pays.
final leaderboardCountryProvider = StreamProvider.autoDispose
    .family<List<LeaderboardEntry>, String>((ref, country) {
  return ref.watch(socialServiceProvider).watchCountry(country);
});

/// Classement entre amis (moi + friendIds).
final leaderboardFriendsProvider =
    StreamProvider.autoDispose<List<LeaderboardEntry>>((ref) async* {
  final profile = await ref.watch(myProfileProvider.future);
  final raw = profile['friendIds'] as List? ?? const [];
  final all = [...raw.map((e) => e.toString())];
  final uid = profile['_uid'] as String?;
  if (uid != null) all.add(uid);
  yield* ref.watch(socialServiceProvider).watchFriends(all);
});
