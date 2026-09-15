import '../../core/i18n/app_lang.dart';

/// Banque de questions Phase 1 (8 questions, FR/EN/AR).
/// Réponse libre validée en insensible à la casse.
class QuizQuestion {
  const QuizQuestion({
    required this.fr,
    required this.en,
    required this.ar,
    required this.answersFr,
    required this.answersEn,
    required this.answersAr,
  });

  final String fr;
  final String en;
  final String ar;
  final List<String> answersFr;
  final List<String> answersEn;
  final List<String> answersAr;

  String prompt(AppLang lang) => switch (lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar,
      };

  List<String> answers(AppLang lang) => switch (lang) {
        AppLang.fr => answersFr,
        AppLang.en => answersEn,
        AppLang.ar => answersAr,
      };

  List<String> get allAnswers => [...answersFr, ...answersEn, ...answersAr];

  bool check(String input, AppLang lang) {
    final v = input.trim().toLowerCase();
    if (v.isEmpty) return false;
    return answers(lang).map((e) => e.toLowerCase()).contains(v);
  }

  String firstLetter(AppLang lang) {
    final a = answers(lang).first;
    return a.isEmpty ? '' : a[0].toUpperCase();
  }
}

const kQuestions = [
  QuizQuestion(
    fr: 'Capitale de la France ?',
    en: 'Capital of France?',
    ar: 'ما عاصمة فرنسا؟',
    answersFr: ['paris'],
    answersEn: ['paris'],
    answersAr: ['باريس', 'paris'],
  ),
  QuizQuestion(
    fr: 'Combien font 2 + 6 ?',
    en: 'How much is 2 + 6?',
    ar: 'كم يساوي 2 + 6؟',
    answersFr: ['8', 'huit'],
    answersEn: ['8', 'eight'],
    answersAr: ['8', '٨', 'ثمانية'],
  ),
  QuizQuestion(
    fr: 'Couleur du ciel par beau temps ?',
    en: 'Color of a clear sky?',
    ar: 'ما لون السماء الصافية؟',
    answersFr: ['bleu'],
    answersEn: ['blue'],
    answersAr: ['أزرق', 'ازرق'],
  ),
  QuizQuestion(
    fr: 'Combien de pattes a une araignée ?',
    en: 'How many legs does a spider have?',
    ar: 'كم عدد أرجل العنكبوت؟',
    answersFr: ['8', 'huit'],
    answersEn: ['8', 'eight'],
    answersAr: ['8', '٨', 'ثمانية'],
  ),
  QuizQuestion(
    fr: 'Le petit du chat s’appelle…',
    en: 'A baby cat is called a…',
    ar: 'ما اسم صغير القط؟',
    answersFr: ['chaton'],
    answersEn: ['kitten'],
    answersAr: ['هريرة', 'قط صغير', 'kitten'],
  ),
  QuizQuestion(
    fr: 'Planète la plus proche du Soleil ?',
    en: 'Closest planet to the Sun?',
    ar: 'ما أقرب كوكب إلى الشمس؟',
    answersFr: ['mercure'],
    answersEn: ['mercury'],
    answersAr: ['عطارد'],
  ),
  QuizQuestion(
    fr: 'Combien font 5 × 3 ?',
    en: 'How much is 5 × 3?',
    ar: 'كم يساوي 5 × 3؟',
    answersFr: ['15', 'quinze'],
    answersEn: ['15', 'fifteen'],
    answersAr: ['15', '١٥', 'خمسة عشر'],
  ),
  QuizQuestion(
    fr: 'Quel animal miaule ?',
    en: 'Which animal meows?',
    ar: 'ما الحيوان الذي يموء؟',
    answersFr: ['chat'],
    answersEn: ['cat'],
    answersAr: ['قط', 'قطة'],
  ),
];
