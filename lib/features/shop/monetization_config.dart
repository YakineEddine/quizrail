import 'package:flutter/material.dart';

/// Configuration monétisation — IDs TEST Google tant que l'app n'est pas
/// publiée. Bascule prod : remplacer les 3 constantes marquées TEST par les
/// IDs AdMob réels + créer les produits ci-dessous dans Play Console
/// (mêmes IDs), puis republier. Aucun prix n'est en dur : l'écran boutique
/// affiche toujours `price` renvoyé par le Play Store.
///
/// Checklist Play Console avant prod :
/// 1. Monétiser > Produits intégrés : créer tokens_s/m/l (consommables),
///    remove_ads + skins (non consommables), battle_pass (abonnement).
/// 2. Monétiser > Comptes de test de licence : ajouter les testeurs.
/// 3. API Play Developer + compte de service avec accès financier,
///    pour que verifyAndGrantPurchase puisse valider les tokens d'achat.
/// 4. AdMob : créer les blocs réels et remplacer les IDs TEST.
abstract final class MonetizationConfig {
  // -- AdMob (IDs TEST officiels Google, pub de test uniquement) ------------
  // TEST : à remplacer par l'ID d'application AdMob prod.
  static const androidAppId = 'ca-app-pub-3940256099942544~3347511713';
  // TEST : bloc récompensé de test.
  static const rewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';
  // TEST : bloc interstitiel de test.
  static const interstitialAdUnitId = 'ca-app-pub-3940256099942544/1033173712';

  // -- Google Play Billing : IDs produits (à créer dans Play Console) -------
  static const tokensPackS = 'quizrail_tokens_s';
  static const tokensPackM = 'quizrail_tokens_m';
  static const tokensPackL = 'quizrail_tokens_l';
  static const removeAds = 'quizrail_remove_ads';
  static const skinGold = 'quizrail_skin_gold';
  static const skinNeon = 'quizrail_skin_neon';
  static const battlePass = 'quizrail_battle_pass';

  static const consumables = {tokensPackS, tokensPackM, tokensPackL};
  static const nonConsumables = {removeAds, skinGold, skinNeon};
  static const subscriptions = {battlePass};

  static const allProductIds = {
    ...consumables,
    ...nonConsumables,
    ...subscriptions,
  };

  // -- Catalogue : ce que DONNE chaque produit (game design, pas des prix) --
  // Les prix affichés viennent du Play Store. Les attributions sont
  // recalculées côté serveur (verifyAndGrantPurchase) : le client ne crédite
  // jamais de jetons/droits sur simple retour du store.
  static const packTokens = {
    tokensPackS: 120,
    tokensPackM: 550,
    tokensPackL: 1300,
  };
  static const productSkins = {
    skinGold: 'gold',
    skinNeon: 'neon',
  };

  // -- Pub récompensée -------------------------------------------------------
  static const rewardedTokens = 30;

  /// Jetons offerts par pub récompensée (x2 avec le battle pass actif).
  static int rewardedGrant({required bool battlePassActive}) =>
      battlePassActive ? rewardedTokens * 2 : rewardedTokens;

  // -- Interstitielle : règles Google Play -----------------------------------
  // Jamais en pleine question (voir AdPlacement : seuls les écrans de
  // résultats sont autorisés), cappée en fréquence, coupée si remove_ads.
  static const interstitialMinInterval = Duration(minutes: 5);
  static const interstitialMaxPerSession = 3;

  // -- Battle pass -----------------------------------------------------------
  /// Multiplicateur de gains de jetons (solo + récompensées + serveur
  /// duel/party qui lit le droit côté fonction).
  static int applyPassMultiplier(int base, {required bool battlePassActive}) =>
      battlePassActive ? base * 2 : base;
}

/// Emplacements où une pub peut être DEMANDÉE. Seuls les écrans de résultats
/// peuvent afficher une interstitielle : toute demande depuis une question
/// (ou un autre écran) est refusée par [AdsService].
enum AdPlacement {
  question,
  resultsSolo,
  resultsDuel,
  resultsParty,
  shop,
}

/// Interstitielle autorisée uniquement après un écran de résultats.
bool isInterstitialPlacement(AdPlacement placement) => switch (placement) {
      AdPlacement.resultsSolo ||
      AdPlacement.resultsDuel ||
      AdPlacement.resultsParty =>
        true,
      _ => false,
    };

/// Gating pur (testable) d'une interstitielle : achat remove_ads, délai
/// minimal depuis la dernière, quota par session.
bool shouldShowInterstitial({
  required bool removeAdsActive,
  required int? lastShownMs,
  required int shownThisSession,
  required int nowMs,
}) {
  if (removeAdsActive) return false;
  if (shownThisSession >= MonetizationConfig.interstitialMaxPerSession) {
    return false;
  }
  if (lastShownMs != null &&
      nowMs - lastShownMs <
          MonetizationConfig.interstitialMinInterval.inMilliseconds) {
    return false;
  }
  return true;
}

/// Skins de train achetables (teintes de la loco). `classic` = défaut gratuit.
class TrainSkinPalette {
  const TrainSkinPalette({
    required this.id,
    required this.cab,
    required this.roof,
    required this.chimney,
  });

  final String id;
  final Color cab;
  final Color roof;
  final Color chimney;
}

/// Palettes par id de skin (voir [MonetizationConfig.productSkins]).
/// Les couleurs sont des teintes, pas des prix : aucun lien avec le store.
Map<String, TrainSkinPalette> trainSkinPalettes({
  required Color classicCab,
  required Color classicRoof,
  required Color classicChimney,
  required Color gold,
  required Color pink,
  required Color mint,
  required Color sky,
}) =>
    {
      'classic': TrainSkinPalette(
        id: 'classic',
        cab: classicCab,
        roof: classicRoof,
        chimney: classicChimney,
      ),
      'gold': TrainSkinPalette(
        id: 'gold',
        cab: gold,
        roof: gold,
        chimney: classicChimney,
      ),
      'neon': TrainSkinPalette(
        id: 'neon',
        cab: pink,
        roof: mint,
        chimney: sky,
      ),
    };
