import 'custom_tunnel.dart';

/// Générateur local de secours quand le backend IA est injoignable.
/// Retourne toujours 9 questions valides (3 par difficulté) :
/// - 3 faciles calculées depuis le thème (réponses exactes garanties) ;
/// - 6 issues de la culture générale (banque locale).
/// Le joueur relit puis sauvegarde comme avec l'IA.
class TunnelLocalGenerator {
  static List<CustomQuestion> generate({
    required String theme,
    String lang = 'fr',
  }) {
    final t = theme.trim().isEmpty ? 'Quiz' : theme.trim();
    final compact = t.replaceAll(RegExp(r'\s+'), '');
    final firstLetter =
        compact.isEmpty ? 'A' : compact[0].toUpperCase();
    final letterCount = compact.runes.length.toString();
    final wordCount =
        t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length.toString();

    switch (lang) {
      case 'en':
        return [
          CustomQuestion(
              prompt: 'What is the first letter of "$t"?',
              answer: firstLetter,
              difficulty: TunnelDifficulty.easy),
          CustomQuestion(
              prompt: 'How many letters in "$t" (no spaces)?',
              answer: letterCount,
              difficulty: TunnelDifficulty.easy),
          CustomQuestion(
              prompt: 'How many words in "$t"?',
              answer: wordCount,
              difficulty: TunnelDifficulty.easy),
          const CustomQuestion(
              prompt: 'Capital of France?',
              answer: 'Paris',
              difficulty: TunnelDifficulty.medium),
          const CustomQuestion(
              prompt: 'How much is 2 + 6?',
              answer: '8',
              difficulty: TunnelDifficulty.medium),
          const CustomQuestion(
              prompt: 'Color of a clear sky?',
              answer: 'Blue',
              difficulty: TunnelDifficulty.medium),
          const CustomQuestion(
              prompt: 'How many legs does a spider have?',
              answer: '8',
              difficulty: TunnelDifficulty.hard),
          const CustomQuestion(
              prompt: 'Closest planet to the Sun?',
              answer: 'Mercury',
              difficulty: TunnelDifficulty.hard),
          const CustomQuestion(
              prompt: 'How much is 5 x 3?',
              answer: '15',
              difficulty: TunnelDifficulty.hard),
        ];
      case 'ar':
        return [
          CustomQuestion(
              prompt: 'ما الحرف الأول من "$t"؟',
              answer: firstLetter,
              difficulty: TunnelDifficulty.easy),
          CustomQuestion(
              prompt: 'كم عدد الحروف في "$t" (بدون مسافات)؟',
              answer: letterCount,
              difficulty: TunnelDifficulty.easy),
          CustomQuestion(
              prompt: 'كم عدد الكلمات في "$t"؟',
              answer: wordCount,
              difficulty: TunnelDifficulty.easy),
          const CustomQuestion(
              prompt: 'ما عاصمة فرنسا؟',
              answer: 'باريس',
              difficulty: TunnelDifficulty.medium),
          const CustomQuestion(
              prompt: 'كم يساوي 2 + 6؟',
              answer: '8',
              difficulty: TunnelDifficulty.medium),
          const CustomQuestion(
              prompt: 'ما لون السماء الصافية؟',
              answer: 'أزرق',
              difficulty: TunnelDifficulty.medium),
          const CustomQuestion(
              prompt: 'كم عدد أرجل العنكبوت؟',
              answer: '8',
              difficulty: TunnelDifficulty.hard),
          const CustomQuestion(
              prompt: 'ما أقرب كوكب إلى الشمس؟',
              answer: 'عطارد',
              difficulty: TunnelDifficulty.hard),
          const CustomQuestion(
              prompt: 'كم يساوي 5 × 3؟',
              answer: '15',
              difficulty: TunnelDifficulty.hard),
        ];
      default:
        return [
          CustomQuestion(
              prompt: 'Par quelle lettre commence « $t » ?',
              answer: firstLetter,
              difficulty: TunnelDifficulty.easy),
          CustomQuestion(
              prompt: 'Combien de lettres dans « $t » (sans espaces) ?',
              answer: letterCount,
              difficulty: TunnelDifficulty.easy),
          CustomQuestion(
              prompt: 'Combien de mots dans « $t » ?',
              answer: wordCount,
              difficulty: TunnelDifficulty.easy),
          const CustomQuestion(
              prompt: 'Capitale de la France ?',
              answer: 'Paris',
              difficulty: TunnelDifficulty.medium),
          const CustomQuestion(
              prompt: 'Combien font 2 + 6 ?',
              answer: '8',
              difficulty: TunnelDifficulty.medium),
          const CustomQuestion(
              prompt: 'Couleur du ciel par beau temps ?',
              answer: 'Bleu',
              difficulty: TunnelDifficulty.medium),
          const CustomQuestion(
              prompt: 'Combien de pattes a une araignée ?',
              answer: '8',
              difficulty: TunnelDifficulty.hard),
          const CustomQuestion(
              prompt: 'Planète la plus proche du Soleil ?',
              answer: 'Mercure',
              difficulty: TunnelDifficulty.hard),
          const CustomQuestion(
              prompt: 'Combien font 5 × 3 ?',
              answer: '15',
              difficulty: TunnelDifficulty.hard),
        ];
    }
  }
}
