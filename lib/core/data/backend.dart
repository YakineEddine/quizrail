import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Point d'accès unique au backend Supabase (gratuit, sans carte).
/// - Si `SupabaseConfig.configured == false` : 100 % local,
///   aucun appel réseau (modes bot / party locale / générateur local).
/// - Sinon : init Supabase + Auth anonyme, puis bascule en ligne.
///   Tout échec → repli offline silencieux.
/// Les scores et réponses sont arbitrés côté serveur (RPC SECURITY DEFINER) :
/// le client ne calcule jamais rien.
class Backend {
  Backend._();
  static final Backend instance = Backend._();

  bool _booted = false;
  bool _online = false;
  String? _uid;

  bool get isOnline => _online;
  bool get isOffline => !_online;
  String? get uid => _uid;

  /// Client Supabase (null hors ligne — les services lèvent alors
  /// une erreur "hors ligne" et l'UI propose les modes locaux).
  SupabaseClient? get client =>
      _online ? Supabase.instance.client : null;

  Future<void> boot() async {
    // Déjà en ligne : rien à refaire.
    if (_booted && _online) return;
    // Si un boot a déjà échoué (offline), on autorise une nouvelle tentative.
    _booted = true;
    try {
      if (!SupabaseConfig.configured) return;
      try {
        await Supabase.initialize(
          url: SupabaseConfig.url,
          publishableKey: SupabaseConfig.anonKey,
        ).timeout(const Duration(seconds: 10));
      } catch (_) {
        // Déjà initialisé (hot restart / retry) : on continue.
      }
      final auth = Supabase.instance.client.auth;
      if (auth.currentUser == null) {
        await auth
            .signInAnonymously()
            .timeout(const Duration(seconds: 10));
      }
      _uid = auth.currentUser?.id;
      _online = _uid != null;
      if (_online) {
        // Profil miroir (jetons/langue) — best-effort.
        try {
          await Supabase.instance.client
              .rpc('ensure_profile')
              .timeout(const Duration(seconds: 8));
        } catch (_) {}
      }
    } catch (_) {
      _online = false;
      _uid = null;
    }
  }

  /// Nouvelle tentative de connexion (boutons "Réessayer").
  Future<void> retry() async {
    _booted = false;
    try {
      await boot().timeout(const Duration(seconds: 15));
    } catch (_) {
      // Reste offline : l'UI propose les modes locaux.
    }
  }

  /// Traduit une erreur Supabase en [StateError] affichable (FR).
  /// Les erreurs métier RPC remontent déjà en français (code P0001).
  static StateError friendly(Object e, {String fallback = 'Erreur réseau, réessaie.'}) {
    if (e is StateError) return e;
    if (e is PostgrestException) {
      final msg = e.message.trim();
      if (e.code == 'P0001' && msg.isNotEmpty) return StateError(msg);
      if (msg.isNotEmpty && !_looksTechnical(msg)) return StateError(msg);
      return StateError(fallback);
    }
    if (e is FunctionException) {
      final details = e.details;
      final msg = details is Map
          ? (details['error']?.toString() ?? '')
          : details?.toString() ?? '';
      if (msg.isNotEmpty && !_looksTechnical(msg)) return StateError(msg);
      if (e.status == 429) {
        return StateError('Quota IA du jour atteint (5 générations).');
      }
      if (e.status == 401) return StateError('Connexion requise.');
      return StateError(fallback);
    }
    if (e is AuthException) {
      return StateError('Connexion requise.');
    }
    return StateError(fallback);
  }

  static bool _looksTechnical(String msg) =>
      msg.contains('Failed host lookup') ||
      msg.contains('SocketException') ||
      msg.contains('Connection refused') ||
      msg.contains('JWT') ||
      msg.length > 160;
}
