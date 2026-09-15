import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Consentement pubs (RGPD/EEA) via la plateforme UMP officielle de Google.
/// Séquence au démarrage : mise à jour du statut → formulaire si requis →
/// init du SDK ads. Les chargements de pubs attendent cette séquence et
/// vérifient [canRequestAds] : sans consentement valide, aucune pub
/// (ni personnalisée, ni requête) n'est chargée.
///
/// Côté console : AdMob > Confidentialité et messages > créer un message
/// RGPD + sélectionner les partenaires. Sans message configuré, l'UMP
/// n'affiche rien et `canRequestAds` reste vrai hors EEA.
abstract final class AdsConsent {
  static Future<void>? _ready;

  /// Lance la séquence une fois (idempotent). Échec silencieux : les pubs
  /// restent simplement indisponibles jusqu'au prochain démarrage.
  static Future<void> ensureInitialized() =>
      _ready ??= _runConsentFlow().timeout(
        const Duration(seconds: 20),
        onTimeout: () {},
      );

  static Future<void> _runConsentFlow() async {
    try {
      final updated = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          if (!updated.isCompleted) updated.complete();
        },
        (_) {
          if (!updated.isCompleted) updated.complete();
        },
      );
      await updated.future.timeout(const Duration(seconds: 12));
      if (await ConsentInformation.instance.isConsentFormAvailable()) {
        final dismissed = Completer<void>();
        ConsentForm.loadAndShowConsentFormIfRequired((_) {
          if (!dismissed.isCompleted) dismissed.complete();
        });
        await dismissed.future.timeout(const Duration(minutes: 5));
      }
    } catch (_) {
      // UMP indisponible (hors ligne, pas de message configuré) :
      // canRequestAds() tranchera au moment du chargement.
    }
  }

  /// Vrai si une pub peut être demandée (consentement obtenu ou non requis).
  static Future<bool> canRequestAds() async {
    try {
      return await ConsentInformation.instance
          .canRequestAds()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  /// Vrai si l'utilisateur doit voir un point d'entrée "Choix pubs"
  /// (exigé dans l'EEE). Appelé par la boutique.
  static Future<bool> privacyOptionsRequired() async {
    try {
      final status = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus()
          .timeout(const Duration(seconds: 5),
              onTimeout: () => PrivacyOptionsRequirementStatus.unknown);
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  /// Rouvre le formulaire de choix (bouton boutique). Silencieux si
  /// indisponible.
  static Future<void> showPrivacyOptions() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((_) {}).timeout(
        const Duration(minutes: 5),
      );
    } catch (_) {}
  }

  /// Réservé aux tests internes.
  static void debugResetForTests() {
    _ready = null;
  }
}
