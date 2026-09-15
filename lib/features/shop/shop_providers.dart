import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_prefs.dart';
import 'ads_service.dart';
import 'billing_service.dart';

/// Prefs partagées : le scope racine n'en fournit pas, chaque écran reçoit
/// les siennes (même motif que Party). Les services les lisent en synchrone.
final monetPrefsProvider = Provider<AppPrefs>((ref) {
  throw UnimplementedError('monetPrefsProvider non surchargé.');
});

/// Pubs injectables (AdMob en prod, fake en tests).
final adsServiceProvider = Provider<AdsService>((ref) {
  return AdMobAdsService(prefs: ref.watch(monetPrefsProvider));
});

/// Billing injectable (Play en prod, fake en tests).
final billingServiceProvider = Provider<BillingService>((ref) {
  return PlayBillingService();
});

/// Produits au vrai prix du store (rechargés à chaque ouverture boutique).
final shopProductsProvider =
    FutureProvider.autoDispose<List<ShopProduct>>((ref) async {
  final billing = ref.watch(billingServiceProvider);
  if (!await billing.isStoreAvailable) {
    throw StateError('unavailable');
  }
  return billing.queryProducts();
});

/// Droits serveurs rapatriés en local à l'ouverture de la boutique.
final entitlementsProvider =
    FutureProvider.autoDispose<Entitlements?>((ref) async {
  return EntitlementsRepository()
      .pullToLocal(ref.watch(monetPrefsProvider));
});
