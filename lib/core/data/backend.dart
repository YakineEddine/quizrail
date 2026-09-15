import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';

/// Point d'accès unique au backend Firebase.
/// - Si `DefaultFirebaseOptions.configured == false` : 100 % local,
///   aucun appel réseau (comportement actuel inchangé, tests verts).
/// - Sinon : init Firebase + Auth anonyme (avec email optionnel plus tard),
///   puis bascule en ligne. Tout échec → repli offline silencieux.
/// Firestore garde son cache persistant : lecture/écriture possibles
/// hors ligne, synchro automatique au retour réseau.
class Backend {
  Backend._();
  static final Backend instance = Backend._();

  bool _booted = false;
  bool _online = false;
  String? _uid;

  bool get isOnline => _online;
  bool get isOffline => !_online;
  String? get uid => _uid;

  FirebaseFirestore? get firestore =>
      _online ? FirebaseFirestore.instance : null;
  FirebaseAuth? get auth => _online ? FirebaseAuth.instance : null;

  Future<void> boot() async {
    if (_booted) return;
    _booted = true;
    try {
      if (!DefaultFirebaseOptions.configured) return;
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(const Duration(seconds: 10));
      }
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth
            .signInAnonymously()
            .timeout(const Duration(seconds: 10));
      }
      _uid = auth.currentUser?.uid;
      _online = _uid != null;
    } catch (_) {
      _online = false;
      _uid = null;
    }
  }
}
