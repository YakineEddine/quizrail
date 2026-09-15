import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/storage/app_prefs.dart';
import 'monetization_config.dart';
import 'shop_providers.dart';

/// Façade pubs : récompensée (à l'initiative du joueur) + interstitielle
/// (résultats uniquement, cappée, coupée par remove_ads).
/// Toute erreur réseau/SDK est best-effort : le jeu continue sans pub.
abstract class AdsService {
  /// Affiche une récompensée. Retourne true si le joueur a gagné la
  /// récompense (à créditer par l'appelant).
  Future<bool> showRewarded();

  /// Affiche une interstitielle si l'emplacement est autorisé (résultats
  /// uniquement, jamais en pleine question) et si le capping le permet.
  /// Retourne true si affichée.
  Future<bool> maybeShowInterstitial(AdPlacement placement);

  int get interstitialsThisSession;
}

class AdMobAdsService implements AdsService {
  AdMobAdsService({required this.prefs});

  final AppPrefs prefs;
  int _sessionCount = 0;

  /// À appeler une fois au démarrage (échec silencieux hors ligne).
  static Future<void> init() async {
    try {
      await MobileAds.instance.initialize().timeout(
            const Duration(seconds: 10),
          );
    } catch (_) {
      // Pubs indisponibles : le jeu reste 100 % jouable.
    }
  }

  @override
  int get interstitialsThisSession => _sessionCount;

  Future<RewardedAd?> _loadRewarded() async {
    final done = Completer<RewardedAd?>();
    try {
      await RewardedAd.load(
        adUnitId: MonetizationConfig.rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (!done.isCompleted) done.complete(ad);
          },
          onAdFailedToLoad: (_) {
            if (!done.isCompleted) done.complete(null);
          },
        ),
      );
      return await done.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> showRewarded() async {
    final ad = await _loadRewarded();
    if (ad == null) return false;
    final earned = Completer<bool>();
    try {
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (a) {
          a.dispose();
          if (!earned.isCompleted) earned.complete(false);
        },
        onAdFailedToShowFullScreenContent: (a, _) {
          a.dispose();
          if (!earned.isCompleted) earned.complete(false);
        },
      );
      await ad.show(
        onUserEarnedReward: (a, _) {
          if (!earned.isCompleted) earned.complete(true);
        },
      );
      return await earned.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => false,
      );
    } catch (_) {
      try {
        ad.dispose();
      } catch (_) {}
      return false;
    }
  }

  Future<InterstitialAd?> _loadInterstitial() async {
    final done = Completer<InterstitialAd?>();
    try {
      await InterstitialAd.load(
        adUnitId: MonetizationConfig.interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (!done.isCompleted) done.complete(ad);
          },
          onAdFailedToLoad: (_) {
            if (!done.isCompleted) done.complete(null);
          },
        ),
      );
      return await done.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> maybeShowInterstitial(AdPlacement placement) async {
    // Règle Google Play : jamais en pleine question (ni boutique).
    if (!isInterstitialPlacement(placement)) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!shouldShowInterstitial(
      removeAdsActive: prefs.removeAds,
      lastShownMs: prefs.lastInterstitialMs,
      shownThisSession: _sessionCount,
      nowMs: now,
    )) {
      return false;
    }
    final ad = await _loadInterstitial();
    if (ad == null) return false;
    final shown = Completer<bool>();
    try {
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (a) {
          if (!shown.isCompleted) shown.complete(true);
        },
        onAdDismissedFullScreenContent: (a) {
          a.dispose();
          if (!shown.isCompleted) shown.complete(true);
        },
        onAdFailedToShowFullScreenContent: (a, _) {
          a.dispose();
          if (!shown.isCompleted) shown.complete(false);
        },
      );
      await ad.show();
      final ok = await shown.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => false,
      );
      if (ok) {
        _sessionCount++;
        await prefs.setLastInterstitialMs(now);
      }
      return ok;
    } catch (_) {
      try {
        ad.dispose();
      } catch (_) {}
      return false;
    }
  }
}

/// Fake scriptable pour les tests (aucun SDK, aucun réseau).
class FakeAdsService implements AdsService {
  FakeAdsService({this.rewardedResult = true});

  bool rewardedResult;
  final List<AdPlacement> placements = [];
  int rewardedCalls = 0;
  int _sessionCount = 0;

  @override
  int get interstitialsThisSession => _sessionCount;

  @override
  Future<bool> showRewarded() async {
    rewardedCalls++;
    return rewardedResult;
  }

  @override
  Future<bool> maybeShowInterstitial(AdPlacement placement) async {
    // Même garde que la prod : jamais en pleine question.
    if (!isInterstitialPlacement(placement)) return false;
    placements.add(placement);
    _sessionCount++;
    return true;
  }
}

/// Secours pour les écrans sans Riverpod : lit le provider via le scope
/// racine, no-op silencieux hors scope (tests) ou en cas d'erreur.
Future<bool> maybeShowResultsAd(
  BuildContext context,
  AdPlacement placement,
) async {
  try {
    final container = ProviderScope.containerOf(context);
    return await container
        .read(adsServiceProvider)
        .maybeShowInterstitial(placement);
  } catch (_) {
    return false;
  }
}

/// Récompensée depuis un écran sans Riverpod (boutique, question).
Future<bool> showRewardedAd(BuildContext context) async {
  try {
    final container = ProviderScope.containerOf(context);
    return await container.read(adsServiceProvider).showRewarded();
  } catch (_) {
    return false;
  }
}
