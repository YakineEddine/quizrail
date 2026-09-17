/// Configuration Supabase — REMPLACE Firebase (aucune carte requise).
///
/// Remplissage (5 min, gratuit) :
///   1. supabase.com → New project (nom : quizrail).
///   2. Authentication → Providers → activer "Anonymous".
///   3. SQL Editor → exécuter supabase/schema.sql.
///   4. Project Settings → API → copier URL + anon key ci-dessous,
///      puis passer [configured] à true et reconstruire l'APK.
///
/// Tant que [configured] vaut false, l'app reste 100 % locale :
/// aucun appel réseau (modes bot / party locale / générateur local).
class SupabaseConfig {
  /// Passer à true une fois URL + anonKey renseignées.
  static const bool configured = true;

  static const String url = 'https://owocymdiohnfokppyujl.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im93b2N5bWRpb2huZm9rcHB5dWpsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk2MzA4ODEsImV4cCI6MjEwNTIwNjg4MX0.Q4ORb4A-32Zv1ZXnMSTMQH0a_cEQL5lp432FvFELREs';
}
