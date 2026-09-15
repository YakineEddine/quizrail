import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/backend.dart';
import '../../core/data/user_repository.dart';
import '../../core/i18n/app_lang.dart';
import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/game_button.dart';
import 'ads_service.dart';
import 'billing_service.dart';
import 'consent_service.dart';
import 'monetization_config.dart';
import 'shop_providers.dart';

/// Boutique : jetons (packs S/M/L au VRAI prix Play Console), suppression
/// des pubs, skins de train, battle pass (abonnement) et pub récompensée.
/// Aucun crédit sans validation serveur : les achats sont vérifiés par
/// verifyAndGrantPurchase avant tout (le store seul ne crédite jamais).
class ShopScreen extends StatelessWidget {
  const ShopScreen(
      {super.key, this.prefs, this.lang = AppLang.fr, this.billing, this.ads});

  final AppPrefs? prefs;
  final AppLang lang;

  /// Hooks de test : services injectés au scope interne (prod = défauts).
  final BillingService? billing;
  final AdsService? ads;

  @override
  Widget build(BuildContext context) {
    // Scope interne : la boutique apporte ses prefs et services aux
    // providers (aucun override exigé des appelants).
    final p = prefs ?? AppPrefs.inMemory();
    return ProviderScope(
      overrides: [
        monetPrefsProvider.overrideWithValue(p),
        if (billing != null)
          billingServiceProvider.overrideWithValue(billing!),
        if (ads != null) adsServiceProvider.overrideWithValue(ads!),
      ],
      child: _ShopView(prefs: p, lang: lang),
    );
  }
}

class _ShopView extends ConsumerStatefulWidget {
  const _ShopView({required this.prefs, required this.lang});

  final AppPrefs prefs;
  final AppLang lang;

  @override
  ConsumerState<_ShopView> createState() => _ShopViewState();
}

class _ShopViewState extends ConsumerState<_ShopView> {
  late final AppPrefs _prefs = widget.prefs;
  StreamSubscription<BillingEvent>? _events;
  String? _buyingId;
  String? _message;
  bool _rewardBusy = false;

  String _t({required String fr, required String en, required String ar}) =>
      switch (widget.lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar
      };

  @override
  void initState() {
    super.initState();
    _events =
        ref.read(billingServiceProvider).events.listen((event) async {
      if (!mounted) return;
      if (event.outcome == BillingOutcome.granted) {
        await EntitlementsRepository().pullToLocal(_prefs);
        // Les packs sont crédités côté serveur : on resynchronise le
        // portefeuille local (merge max, sans perte).
        await UserRepository(prefs: _prefs).pullToLocal();
        ref.invalidate(entitlementsProvider);
        ref.invalidate(shopProductsProvider);
        if (mounted) {
          setState(() {
            _buyingId = null;
            _message = _t(
              fr: 'Achat validé, merci !',
              en: 'Purchase verified, thanks!',
              ar: 'تم التحقق من الشراء، شكرًا!',
            );
          });
        }
      } else if (event.outcome == BillingOutcome.failed) {
        if (mounted) {
          setState(() {
            _buyingId = null;
            _message = event.message ??
                _t(
                  fr: 'Achat non validé.',
                  en: 'Purchase not verified.',
                  ar: 'تعذّر التحقق من الشراء.',
                );
          });
        }
      }
      // Annulation : retour silencieux à la boutique.
      else if (mounted) {
        setState(() => _buyingId = null);
      }
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _buy(ShopProduct product) async {
    if (_buyingId != null) return;
    setState(() {
      _buyingId = product.id;
      _message = null;
    });
    try {
      final launched =
          await ref.read(billingServiceProvider).buy(product);
      if (!launched && mounted) {
        setState(() {
          _buyingId = null;
          _message = _t(
            fr: 'Achat impossible pour l\u2019instant.',
            en: 'Purchase unavailable right now.',
            ar: 'الشراء غير متاح حاليًا.',
          );
        });
      }
      // Sinon : l'issue arrive via le stream (vérification serveur).
    } catch (_) {
      if (mounted) {
        setState(() {
          _buyingId = null;
          _message = _t(
            fr: 'Achat impossible pour l\u2019instant.',
            en: 'Purchase unavailable right now.',
            ar: 'الشراء غير متاح حاليًا.',
          );
        });
      }
    }
  }

  Future<void> _watchRewarded() async {
    if (_rewardBusy) return;
    setState(() {
      _rewardBusy = true;
      _message = null;
    });
    try {
      final earned = await showRewardedAd(context);
      if (!mounted) return;
      if (earned) {
        final grant = MonetizationConfig.rewardedGrant(
          battlePassActive: _prefs.battlePassActive,
        );
        await _prefs.setTokens(_prefs.tokens + grant);
        await UserRepository(prefs: _prefs).pushTokens(_prefs.tokens);
        setState(() {
          _message = _t(
            fr: '+$grant jetons ! Merci d\u2019avoir regardé.',
            en: '+$grant tokens! Thanks for watching.',
            ar: '+$grant رموز! شكرًا للمشاهدة.',
          );
        });
      } else {
        setState(() {
          _message = _t(
            fr: 'Pub non terminée, aucun gain.',
            en: 'Ad not finished, no reward.',
            ar: 'لم يكتمل الإعلان، لا مكافأة.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _rewardBusy = false);
    }
  }

  Future<void> _equipSkin(String skinId) async {
    await _prefs.setSelectedSkin(skinId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Rafraîchit les droits serveurs à chaque ouverture.
    ref.watch(entitlementsProvider);
    final products = ref.watch(shopProductsProvider);
    final online =
        Backend.instance.isOnline || Backend.instance.firestore == null;
    return Directionality(
      textDirection:
          widget.lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('shopScreen'),
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration:
              const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                              fr: 'Boutique',
                              en: 'Shop',
                              ar: 'المتجر'),
                          style:
                              Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              color: AppColors.sun, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            '${_prefs.tokens}',
                            key: const Key('shopWallet'),
                            style: const TextStyle(
                                color: AppColors.sun,
                                fontWeight: FontWeight.w900,
                                fontSize: 18),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _message!,
                        key: const Key('shopMessage'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.sun,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: products.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.sun),
                      ),
                      error: (_, _) => _StoreUnavailable(
                        text: !online
                            ? _t(
                                fr: 'Boutique indisponible hors ligne.',
                                en: 'Shop unavailable offline.',
                                ar: 'المتجر غير متاح دون اتصال.',
                              )
                            : _t(
                                fr: 'Boutique indisponible (produits non configurés dans Play Console).',
                                en: 'Shop unavailable (products not configured in Play Console).',
                                ar: 'المتجر غير متاح (المنتجات غير مُعدّة في Play Console).',
                              ),
                      ),
                      data: (list) => _ShopBody(
                        products: list,
                        prefs: _prefs,
                        buyingId: _buyingId,
                        rewardBusy: _rewardBusy,
                        onBuy: _buy,
                        onRewarded: _watchRewarded,
                        onEquip: _equipSkin,
                        t: _t,
                      ),
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

class _StoreUnavailable extends StatelessWidget {
  const _StoreUnavailable({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('shopUnavailable'),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.creamDim),
      ),
    );
  }
}

class _ShopBody extends StatefulWidget {
  const _ShopBody({
    required this.products,
    required this.prefs,
    required this.buyingId,
    required this.rewardBusy,
    required this.onBuy,
    required this.onRewarded,
    required this.onEquip,
    required this.t,
  });

  final List<ShopProduct> products;
  final AppPrefs prefs;
  final String? buyingId;
  final bool rewardBusy;
  final ValueChanged<ShopProduct> onBuy;
  final VoidCallback onRewarded;
  final ValueChanged<String> onEquip;
  final String Function(
      {required String fr,
      required String en,
      required String ar}) t;

  @override
  State<_ShopBody> createState() => _ShopBodyState();
}

class _ShopBodyState extends State<_ShopBody> {
  // Future créé UNE fois : recréé à chaque build, il laisserait un timer
  // en suspens à chaque rebuild (et en tests fake-async).
  late final Future<bool> _privacyFuture =
      AdsConsent.privacyOptionsRequired();

  @override
  Widget build(BuildContext context) {
    final products = widget.products;
    final prefs = widget.prefs;
    final buyingId = widget.buyingId;
    final rewardBusy = widget.rewardBusy;
    final onBuy = widget.onBuy;
    final onRewarded = widget.onRewarded;
    final onEquip = widget.onEquip;
    final t = widget.t;
    final groups = groupShopProducts(products);
    return ListView(
      key: const Key('shopList'),
      children: [
        // Pub récompensée : à l'initiative du joueur, gains visibles.
        _RewardCard(
          busy: rewardBusy,
          battlePass: prefs.battlePassActive,
          onTap: onRewarded,
          t: t,
        ),
        const SizedBox(height: 12),
        for (final entry in groups.entries) ...[
          Text(
            switch (entry.key) {
              'tokens' => t(
                  fr: 'Jetons',
                  en: 'Tokens',
                  ar: 'رموز',
                ),
              'extras' => t(
                  fr: 'Extras',
                  en: 'Extras',
                  ar: 'إضافات',
                ),
              _ => t(
                  fr: 'Skins de train',
                  en: 'Train skins',
                  ar: 'أشكال القطار',
                ),
            },
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          for (final p in entry.value)
            _ProductCard(
              product: p,
              prefs: prefs,
              buying: buyingId == p.id,
              onBuy: () => onBuy(p),
              onEquip: onEquip,
              t: t,
            ),
          const SizedBox(height: 12),
        ],
        // RGPD/EEE : point d'entrée "Choix pubs" quand l'UMP l'exige.
        FutureBuilder<bool>(
          future: _privacyFuture,
          builder: (_, snap) {
            if (snap.data != true) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: TextButton(
                  key: const Key('shopPrivacyButton'),
                  onPressed: AdsConsent.showPrivacyOptions,
                  child: Text(
                    t(
                      fr: 'Choix pubs et confidentialité',
                      en: 'Ad choices & privacy',
                      ar: 'خيارات الإعلانات والخصوصية',
                    ),
                    style: const TextStyle(
                        color: AppColors.creamDim,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.busy,
    required this.battlePass,
    required this.onTap,
    required this.t,
  });

  final bool busy;
  final bool battlePass;
  final VoidCallback onTap;
  final String Function(
      {required String fr,
      required String en,
      required String ar}) t;

  @override
  Widget build(BuildContext context) {
    final grant =
        MonetizationConfig.rewardedGrant(battlePassActive: battlePass);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ink, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_rounded,
              color: AppColors.ink, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t(
                fr: 'Pub vidéo : +$grant jetons',
                en: 'Video ad: +$grant tokens',
                ar: 'إعلان فيديو: +$grant رموز',
              ),
              style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 16),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            key: const Key('shopRewardedButton'),
            onTap: busy ? null : onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                busy
                    ? '…'
                    : t(fr: 'Voir', en: 'Watch', ar: 'شاهد'),
                style: const TextStyle(
                    color: AppColors.sun,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.prefs,
    required this.buying,
    required this.onBuy,
    required this.onEquip,
    required this.t,
  });

  final ShopProduct product;
  final AppPrefs prefs;
  final bool buying;
  final VoidCallback onBuy;
  final ValueChanged<String> onEquip;
  final String Function(
      {required String fr,
      required String en,
      required String ar}) t;

  @override
  Widget build(BuildContext context) {
    final subtitle = product.isTokensPack
        ? t(
            fr: '${product.tokens} jetons',
            en: '${product.tokens} tokens',
            ar: '${product.tokens} رموز',
          )
        : product.isRemoveAds
            ? t(
                fr: 'Plus aucune interstitielle, pour toujours.',
                en: 'No more interstitials, forever.',
                ar: 'لا مزيد من الإعلانات البينية، للأبد.',
              )
            : product.isBattlePass
                ? t(
                    fr: 'Abonnement mensuel : gains de jetons x2.',
                    en: 'Monthly subscription: double token gains.',
                    ar: 'اشتراك شهري: ضِعف مكاسب الرموز.',
                  )
                : t(
                    fr: 'Teinte exclusive pour ton train.',
                    en: 'Exclusive tint for your train.',
                    ar: 'لون حصري لقطارك.',
                  );
    final ownedSkin = product.skinId != null &&
        prefs.ownedSkins.contains(product.skinId);
    final equipped =
        product.skinId != null && prefs.selectedSkin == product.skinId;
    final ownedRemoveAds =
        product.isRemoveAds && prefs.removeAds;

    return Container(
      key: Key('shopCard_${product.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.midnight.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.midnightLight, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  product.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.cream,
                      fontWeight: FontWeight.w900,
                      fontSize: 16),
                ),
              ),
              // Prix 100 % store (jamais en dur dans le code).
              Text(
                product.price,
                key: Key('shopPrice_${product.id}'),
                style: const TextStyle(
                    color: AppColors.sun,
                    fontWeight: FontWeight.w900,
                    fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
                color: AppColors.creamDim, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (ownedRemoveAds)
            Text(
              t(fr: 'Actif ✓', en: 'Active ✓', ar: 'مفعّل ✓'),
              style: const TextStyle(
                  color: AppColors.mintPop,
                  fontWeight: FontWeight.w800),
            )
          else if (equipped)
            Text(
              t(fr: 'Équipé ✓', en: 'Equipped ✓', ar: 'مُجهّز ✓'),
              style: const TextStyle(
                  color: AppColors.mintPop,
                  fontWeight: FontWeight.w800),
            )
          else if (ownedSkin)
            GameButton(
              key: Key('shopEquip_${product.skinId}'),
              variant: GameButtonVariant.secondary,
              label: t(
                  fr: 'Équiper', en: 'Equip', ar: 'تجهيز'),
              height: 46,
              fontSize: 15,
              onPressed: () => onEquip(product.skinId!),
            )
          else
            GameButton(
              key: Key('shopBuy_${product.id}'),
              label: buying
                  ? t(
                      fr: 'Achat…',
                      en: 'Buying…',
                      ar: 'جارٍ الشراء…')
                  : product.price,
              icon: Icons.shopping_cart_rounded,
              height: 46,
              fontSize: 15,
              onPressed: buying ? null : onBuy,
            ),
        ],
      ),
    );
  }
}
