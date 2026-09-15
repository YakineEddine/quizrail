import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Options Firebase — FICHIER TEMPORAIRE à écraser avec :
///   flutterfire configure
/// (sélectionne le projet créé sur console.firebase.google.com).
/// Tant que [configured] vaut false, l'app reste 100 % locale :
/// aucun appel réseau, comportement inchangé, tests verts.
class DefaultFirebaseOptions {
  /// Passé à true automatiquement par `flutterfire configure`
  /// (vérifie-le après génération).
  static const bool configured = false;

  static FirebaseOptions get currentPlatform => android;

  // Valeurs factices : jamais utilisées car configured == false
  // court-circuite l'init. Ne pas mettre de vraie clé ici à la main.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'REPLACE_ME',
    storageBucket: 'REPLACE_ME',
  );
}
