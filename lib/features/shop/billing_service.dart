import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/data/backend.dart';
import '../../core/storage/app_prefs.dart';
import 'monetization_config.dart';

/// Produit boutique : prix TOUJOURS fourni par le Play Store
/// (`ProductDetails.price`), jamais en dur. Le catalogue local ne décrit
/// que le contenu (jetons offerts, droits) et les IDs à créer en console.
enum ShopProductKind { consumable, nonConsumable, subscription }

class ShopProduct {
  const ShopProduct({
    required this.id,
    required this.title,
    required this.price,
    required this.kind,
    this.tokens,
    this.skinId,
  });

  final String id;
  final String title;
  final String price;
  final ShopProductKind kind;

  /// Jetons offerts par les packs (game design, pas un prix).
  final int? tokens;

  /// Skin débloqué (id de palette, voir [MonetizationConfig.productSkins]).
  final String? skinId;

  bool get isTokensPack => tokens != null;
  bool get isRemoveAds => id == MonetizationConfig.removeAds;
  bool get isBattlePass => id == MonetizationConfig.battlePass;
}

/// Droits serveurs (miroir de users/{uid}/entitlements/profile,
/// écrit UNIQUEMENT par verifyAndGrantPurchase, jamais par les clients).
class Entitlements {
  const Entitlements({
    this.removeAds = false,
    this.battlePassActive = false,
    this.battlePassExpiryMs,
    this.skins = const [],
  });

  final bool removeAds;
  final bool battlePassActive;
  final int? battlePassExpiryMs;
  final List<String> skins;

  factory Entitlements.fromMap(Map<String, Object?> map) {
    return Entitlements(
      removeAds: (map['removeAds'] as bool?) ?? false,
      battlePassActive: (map['battlePassActive'] as bool?) ?? false,
      battlePassExpiryMs:
          (map['battlePassExpiryMs'] as num?)?.toInt(),
      skins: ((map['skins'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, Object?> toMap() => {
        'removeAds': removeAds,
        'battlePassActive': battlePassActive,
        if (battlePassExpiryMs != null)
          'battlePassExpiryMs': battlePassExpiryMs,
        'skins': skins,
      };
}

/// Résultat du flux d'achat après vérification serveur.
enum BillingOutcome { granted, failed, canceled }

class BillingEvent {
  const BillingEvent({required this.productId, required this.outcome, this.message});

  final String productId;
  final BillingOutcome outcome;
  final String? message;
}

/// Façade Billing : produits au vrai prix du store, achat, puis
/// VÉRIFICATION SERVEUR obligatoire avant tout crédit (le retour client
/// seul ne crédite jamais rien : jetons et droits sont écrits par
/// verifyAndGrantPurchase via Admin SDK).
abstract class BillingService {
  Future<bool> get isStoreAvailable;
  Future<List<ShopProduct>> queryProducts();
  Future<bool> buy(ShopProduct product);
  Stream<BillingEvent> get events;
  Future<void> dispose();
}

/// Regroupe les produits par section de boutique (ordre stable).
Map<String, List<ShopProduct>> groupShopProducts(List<ShopProduct> products) {
  final byId = {for (final p in products) p.id: p};
  ShopProduct? get(String id) => byId[id];
  final groups = <String, List<ShopProduct>>{
    'tokens': [
      for (final id in [
        MonetizationConfig.tokensPackS,
        MonetizationConfig.tokensPackM,
        MonetizationConfig.tokensPackL,
      ])
        if (get(id) != null) get(id)!,
    ],
    'extras': [
      if (get(MonetizationConfig.removeAds) != null)
        get(MonetizationConfig.removeAds)!,
      if (get(MonetizationConfig.battlePass) != null)
        get(MonetizationConfig.battlePass)!,
    ],
    'skins': [
      if (get(MonetizationConfig.skinGold) != null)
        get(MonetizationConfig.skinGold)!,
      if (get(MonetizationConfig.skinNeon) != null)
        get(MonetizationConfig.skinNeon)!,
    ],
  };
  groups.removeWhere((_, v) => v.isEmpty);
  return groups;
}

ShopProduct _fromDetails(ProductDetails d) {
  final kind = MonetizationConfig.consumables.contains(d.id)
      ? ShopProductKind.consumable
      : MonetizationConfig.subscriptions.contains(d.id)
          ? ShopProductKind.subscription
          : ShopProductKind.nonConsumable;
  return ShopProduct(
    id: d.id,
    title: d.title,
    price: d.price,
    kind: kind,
    tokens: MonetizationConfig.packTokens[d.id],
    skinId: MonetizationConfig.productSkins[d.id],
  );
}

class PlayBillingService implements BillingService {
  PlayBillingService();

  FirebaseFunctions? _functions;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _events = StreamController<BillingEvent>.broadcast();
  final _handled = <String>{};
  bool _disposed = false;

  /// Accès paresseux aux Functions (Firebase peut ne pas être initialisé
  /// en tests : l'échec est converti en événement `failed`, jamais en crash).
  FirebaseFunctions _fn() =>
      _functions ??= FirebaseFunctions.instance;

  /// Abonnement paresseux au store (jamais dans le constructeur : le canal
  /// natif n'existe pas en tests desktop, et l'échec doit rester silencieux).
  void _ensureListening() {
    if (_sub != null) return;
    try {
      _sub = InAppPurchase.instance.purchaseStream.listen(
        _onPurchases,
        onError: (_) {},
      );
    } catch (_) {
      // Store indisponible : queryProducts/buy renverront un échec propre.
    }
  }

  @override
  Stream<BillingEvent> get events => _events.stream;

  @override
  Future<bool> get isStoreAvailable async {
    try {
      return await InAppPurchase.instance
          .isAvailable()
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<ShopProduct>> queryProducts() async {
    _ensureListening();
    try {
      final res = await InAppPurchase.instance
          .queryProductDetails(MonetizationConfig.allProductIds)
          .timeout(const Duration(seconds: 15));
      if (res.error != null || res.productDetails.isEmpty) return const [];
      final products = res.productDetails.map(_fromDetails).toList();
      products.sort((a, b) => a.id.compareTo(b.id));
      return products;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool> buy(ShopProduct product) async {
    _ensureListening();
    try {
      final res = await InAppPurchase.instance
          .queryProductDetails({product.id})
          .timeout(const Duration(seconds: 15));
      if (res.productDetails.isEmpty) return false;
      final param = PurchaseParam(
        productDetails: res.productDetails.first,
      );
      if (product.kind == ShopProductKind.consumable) {
        return await InAppPurchase.instance.buyConsumable(
          purchaseParam: param,
        );
      }
      return await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: param,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      final token = p.verificationData.serverVerificationData;
      final key = p.purchaseID ?? token;
      if (key.isEmpty || _handled.contains(key)) continue;
      if (p.status == PurchaseStatus.canceled) {
        _handled.add(key);
        _emit(p.productID, BillingOutcome.canceled, null);
        try {
          await InAppPurchase.instance.completePurchase(p);
        } catch (_) {}
        continue;
      }
      if (p.status == PurchaseStatus.error) {
        _handled.add(key);
        _emit(p.productID, BillingOutcome.failed,
            p.error?.message ?? 'Achat refusé.');
        try {
          await InAppPurchase.instance.completePurchase(p);
        } catch (_) {}
        continue;
      }
      if ((p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored) &&
          p.pendingCompletePurchase) {
        _handled.add(key);
        await _verifyThenComplete(p);
      }
    }
  }

  /// Cœur anti-fraude : le crédit (jetons + droits) est écrit par la
  /// fonction AVANT qu'on finalise l'achat côté store. Sans validation
  /// serveur, l'achat reste en suspens et rien n'est crédité.
  Future<void> _verifyThenComplete(PurchaseDetails p) async {
    try {
      final callable = _fn().httpsCallable('verifyAndGrantPurchase');
      final res = await callable.call({
        'productId': p.productID,
        'purchaseToken': p.verificationData.serverVerificationData,
      }).timeout(const Duration(seconds: 40));
      final data = (res.data as Map)
          .map((k, v) => MapEntry(k.toString(), v as Object?));
      if (data['granted'] == true) {
        await InAppPurchase.instance.completePurchase(p);
        _emit(p.productID, BillingOutcome.granted, null);
      } else {
        _emit(p.productID, BillingOutcome.failed, 'Achat non validé.');
      }
    } catch (e) {
      // Réseau / fonction : on NE finalise PAS (le Play Store re-émettra
      // l'achat au prochain démarrage pour une nouvelle tentative).
      final retryKey =
          p.purchaseID ?? p.verificationData.serverVerificationData;
      _handled.remove(retryKey);
      _emit(
        p.productID,
        BillingOutcome.failed,
        e is FirebaseFunctionsException
            ? (e.message ?? 'Vérification impossible.')
            : 'Vérification impossible, réessaie.',
      );
    }
  }

  void _emit(String productId, BillingOutcome outcome, String? message) {
    if (_disposed) return;
    _events.add(BillingEvent(
        productId: productId, outcome: outcome, message: message));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    await _events.close();
  }
}

/// Droits serveurs → prefs locales (bouton pubs, x2 pass, skins).
/// Lecture seule côté client (rules : écriture fonctions uniquement).
class EntitlementsRepository {
  Future<Entitlements?> pullToLocal(AppPrefs prefs) async {
    final fs = Backend.instance.firestore;
    final uid = Backend.instance.uid;
    if (fs == null || uid == null) return null;
    try {
      final snap = await fs
          .doc('users/$uid/entitlements/profile')
          .get()
          .timeout(const Duration(seconds: 10));
      if (!snap.exists) return const Entitlements();
      final data = snap
          .data()!
          .map((k, v) => MapEntry(k.toString(), v as Object?));
      final ent = Entitlements.fromMap(data);
      await prefs.setRemoveAds(ent.removeAds);
      await prefs.setBattlePass(ent.battlePassActive);
      await prefs.setOwnedSkins(ent.skins);
      // Resélection invalide (remboursement) → retour au classique.
      if (prefs.selectedSkin != 'classic' &&
          !ent.skins.contains(prefs.selectedSkin)) {
        await prefs.setSelectedSkin('classic');
      }
      return ent;
    } catch (_) {
      return null;
    }
  }
}

/// Fake scriptable pour les tests (aucun store, prix fictifs affichés
/// tels quels pour prouver qu'ils viennent du "store", pas du code).
class FakeBillingService implements BillingService {
  FakeBillingService({
    this.available = true,
    List<ShopProduct>? products,
    this.buyResult = true,
  }) : products = products ??
            const [
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
            ];

  bool available;
  final List<ShopProduct> products;
  bool buyResult;
  final List<String> bought = [];
  final _events = StreamController<BillingEvent>.broadcast();

  @override
  Future<bool> get isStoreAvailable async => available;

  @override
  Future<List<ShopProduct>> queryProducts() async => products;

  @override
  Future<bool> buy(ShopProduct product) async {
    bought.add(product.id);
    return buyResult;
  }

  /// Simule l'issue serveur (vérification fonction) d'un achat.
  void emit(BillingEvent event) => _events.add(event);

  @override
  Stream<BillingEvent> get events => _events.stream;

  @override
  Future<void> dispose() async => _events.close();
}
