import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizrail/core/storage/app_prefs.dart';
import 'package:quizrail/features/results/results_screen.dart';
import 'package:quizrail/features/shop/ads_service.dart';
import 'package:quizrail/features/shop/billing_service.dart';
import 'package:quizrail/features/shop/monetization_config.dart';
import 'package:quizrail/features/shop/shop_providers.dart';
import 'package:quizrail/features/shop/shop_screen.dart';

void main() {
  test('Interstitielle : jamais en pleine question ni boutique', () {
    expect(isInterstitialPlacement(AdPlacement.question), isFalse);
    expect(isInterstitialPlacement(AdPlacement.shop), isFalse);
    expect(isInterstitialPlacement(AdPlacement.resultsSolo), isTrue);
    expect(isInterstitialPlacement(AdPlacement.resultsDuel), isTrue);
    expect(isInterstitialPlacement(AdPlacement.resultsParty), isTrue);
  });

  test('Capping interstitielle : remove_ads, délai, quota session', () {
    const now = 1000000;
    // Cas nominal : autorisée.
    expect(
      shouldShowInterstitial(
        removeAdsActive: false,
        lastShownMs: null,
        shownThisSession: 0,
        nowMs: now,
      ),
      isTrue,
    );
    // Achat remove_ads : coupée pour toujours.
    expect(
      shouldShowInterstitial(
        removeAdsActive: true,
        lastShownMs: null,
        shownThisSession: 0,
        nowMs: now,
      ),
      isFalse,
    );
    // Délai minimal 5 min entre deux affichages.
    expect(
      shouldShowInterstitial(
        removeAdsActive: false,
        lastShownMs: now - const Duration(minutes: 4).inMilliseconds,
        shownThisSession: 1,
        nowMs: now,
      ),
      isFalse,
    );
    expect(
      shouldShowInterstitial(
        removeAdsActive: false,
        lastShownMs: now - const Duration(minutes: 6).inMilliseconds,
        shownThisSession: 1,
        nowMs: now,
      ),
      isTrue,
    );
    // Quota par session.
    expect(
      shouldShowInterstitial(
        removeAdsActive: false,
        lastShownMs: null,
        shownThisSession: MonetizationConfig.interstitialMaxPerSession,
        nowMs: now,
      ),
      isFalse,
    );
  });

  test('Récompensée : +30 jetons, x2 avec le pass', () {
    expect(
      MonetizationConfig.rewardedGrant(battlePassActive: false),
      30,
    );
    expect(
      MonetizationConfig.rewardedGrant(battlePassActive: true),
      60,
    );
    expect(
      MonetizationConfig.applyPassMultiplier(10, battlePassActive: true),
      20,
    );
    expect(
      MonetizationConfig.applyPassMultiplier(10, battlePassActive: false),
      10,
    );
  });

  test('Catalogue : IDs uniques, packs mappés', () {
    expect(MonetizationConfig.allProductIds.length, 7);
    expect(MonetizationConfig.packTokens[MonetizationConfig.tokensPackS], 120);
    expect(MonetizationConfig.packTokens[MonetizationConfig.tokensPackM], 550);
    expect(MonetizationConfig.packTokens[MonetizationConfig.tokensPackL], 1300);
    expect(MonetizationConfig.productSkins[MonetizationConfig.skinGold], 'gold');
  });

  test('Regroupement boutique : ordre stable, sections non vides filtrées', () {
    const products = [
      ShopProduct(
          id: MonetizationConfig.skinGold,
          title: 'Or',
          price: '2,99 €',
          kind: ShopProductKind.nonConsumable,
          skinId: 'gold'),
      ShopProduct(
          id: MonetizationConfig.tokensPackM,
          title: 'Pack M',
          price: '5,99 €',
          kind: ShopProductKind.consumable,
          tokens: 550),
      ShopProduct(
          id: MonetizationConfig.removeAds,
          title: 'Sans pubs',
          price: '4,99 €',
          kind: ShopProductKind.nonConsumable),
    ];
    final groups = groupShopProducts(products);
    expect(groups['tokens']!.map((p) => p.id),
        [MonetizationConfig.tokensPackM]);
    expect(groups['extras']!.map((p) => p.id),
        [MonetizationConfig.removeAds]);
    expect(groups['skins']!.map((p) => p.id), [MonetizationConfig.skinGold]);
  });

  test('Entitlements : défauts sûrs (rien d\u2019accordé par défaut)', () {
    const e = Entitlements();
    expect(e.removeAds, isFalse);
    expect(e.battlePassActive, isFalse);
    expect(e.skins, isEmpty);
    final d = Entitlements.fromMap({});
    expect(d.removeAds, isFalse);
    expect(d.battlePassActive, isFalse);
  });

  test('FakeAds : la question est refusée même au fake', () async {
    final fake = FakeAdsService();
    expect(
      await fake.maybeShowInterstitial(AdPlacement.question),
      isFalse,
    );
    expect(fake.placements, isEmpty);
    expect(
      await fake.maybeShowInterstitial(AdPlacement.resultsSolo),
      isTrue,
    );
    expect(fake.placements, [AdPlacement.resultsSolo]);
  });

  testWidgets('Boutique : prix du store affichés, achat, récompensée',
      (tester) async {
    final prefs = AppPrefs.inMemory();
    final billing = FakeBillingService(products: const [
      ShopProduct(
          id: MonetizationConfig.tokensPackS,
          title: 'Pack S',
          price: '1,99 €',
          kind: ShopProductKind.consumable,
          tokens: 120),
      ShopProduct(
          id: MonetizationConfig.removeAds,
          title: 'Sans pubs',
          price: '4,99 €',
          kind: ShopProductKind.nonConsumable),
    ]);
    final ads = FakeAdsService();
    await tester.pumpWidget(
      MaterialApp(
        home: ShopScreen(prefs: prefs, billing: billing, ads: ads),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Les prix viennent du "store" (fakes), pas du code : affichés tels quels.
    expect(find.byKey(const Key('shopPrice_quizrail_tokens_s')),
        findsOneWidget);
    expect(find.text('1,99 €'), findsWidgets);
    expect(find.text('4,99 €'), findsWidgets);
    // Achat : le flux store est lancé, la validation serveur suivra.
    await tester.tap(find.byKey(const Key('shopBuy_quizrail_tokens_s')));
    await tester.pump();
    expect(billing.bought, ['quizrail_tokens_s']);
    // Récompensée : +30 jetons au portefeuille.
    await tester.tap(find.byKey(const Key('shopRewardedButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(ads.rewardedCalls, 1);
    expect(prefs.tokens, 150);
    expect(find.byKey(const Key('shopMessage')), findsOneWidget);
    // Issue serveur simulée : message de validation.
    billing.emit(const BillingEvent(
        productId: MonetizationConfig.tokensPackS,
        outcome: BillingOutcome.granted));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('shopMessage')), findsOneWidget);
  });

  testWidgets('Boutique : remove_ads actif + skin à équiper', (tester) async {
    final prefs = AppPrefs.inMemory();
    await prefs.setRemoveAds(true);
    await prefs.setOwnedSkins(['gold']);
    final billing = FakeBillingService(products: const [
      ShopProduct(
          id: MonetizationConfig.removeAds,
          title: 'Sans pubs',
          price: '4,99 €',
          kind: ShopProductKind.nonConsumable),
      ShopProduct(
          id: MonetizationConfig.skinGold,
          title: 'Or',
          price: '2,99 €',
          kind: ShopProductKind.nonConsumable,
          skinId: 'gold'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ShopScreen(
            prefs: prefs, billing: billing, ads: FakeAdsService()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Déjà possédé : pas de bouton d'achat, mention actif.
    expect(
        find.byKey(const Key('shopBuy_quizrail_remove_ads')), findsNothing);
    // Skin possédé : équipable, puis équipé.
    await tester.tap(find.byKey(const Key('shopEquip_gold')));
    await tester.pump();
    expect(prefs.selectedSkin, 'gold');
  });

  testWidgets('Boutique : store indisponible → état propre', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ShopScreen(
          prefs: AppPrefs.inMemory(),
          billing: FakeBillingService(available: false),
          ads: FakeAdsService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('shopUnavailable')), findsOneWidget);
  });

  testWidgets('Résultats : interstitielle post-partie (jamais en question)',
      (tester) async {
    final ads = FakeAdsService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [adsServiceProvider.overrideWithValue(ads)],
        child: const MaterialApp(
          home: ResultsScreen(score: 300, tokensEarned: 40),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(ads.placements, [AdPlacement.resultsSolo]);
    expect(find.byKey(const Key('resultsScreen')), findsOneWidget);
  });
}
