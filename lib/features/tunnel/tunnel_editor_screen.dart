import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/data/tunnel_repository.dart';
import '../../core/i18n/app_lang.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/game_button.dart';
import 'custom_tunnel.dart';
import 'custom_tunnel_store.dart';
import 'tunnel_ai_service.dart';

/// Création de tunnel custom :
/// thème + 9 questions (3 par difficulté) + réponse exacte + image optionnelle.
/// Saisie manuelle (locale, zéro coût) ou génération IA via la Cloud Function
/// `generateTunnel` quand le backend est configuré (quota 5/jour).
class TunnelEditorScreen extends StatefulWidget {
  const TunnelEditorScreen({
    super.key,
    this.lang = AppLang.fr,
    this.store,
  });

  final AppLang lang;
  final CustomTunnelStore? store;

  @override
  State<TunnelEditorScreen> createState() => _TunnelEditorScreenState();
}

class _TunnelEditorScreenState extends State<TunnelEditorScreen> {
  late final AppLang _lang = widget.lang;
  CustomTunnelStore? _store;

  final _theme = TextEditingController();
  late final List<TextEditingController> _prompts =
      List.generate(9, (_) => TextEditingController());
  late final List<TextEditingController> _answers =
      List.generate(9, (_) => TextEditingController());

  XFile? _image;
  Uint8List? _preview;
  bool _showErrors = false;
  bool _saving = false;
  bool _aiLoading = false;
  bool _public = false;
  int _savedCount = 0;

  static const _difficulties = [
    TunnelDifficulty.easy,
    TunnelDifficulty.easy,
    TunnelDifficulty.easy,
    TunnelDifficulty.medium,
    TunnelDifficulty.medium,
    TunnelDifficulty.medium,
    TunnelDifficulty.hard,
    TunnelDifficulty.hard,
    TunnelDifficulty.hard,
  ];

  @override
  void initState() {
    super.initState();
    _store = widget.store;
    if (_store != null) {
      _savedCount = _store!.tunnels.length;
    } else {
      CustomTunnelStore.load().then((s) {
        if (!mounted) return;
        setState(() {
          _store = s;
          _savedCount = s.tunnels.length;
        });
      });
    }
  }

  @override
  void dispose() {
    _theme.dispose();
    for (final c in [..._prompts, ..._answers]) {
      c.dispose();
    }
    super.dispose();
  }

  String _t({required String fr, required String en, required String ar}) =>
      switch (_lang) { AppLang.fr => fr, AppLang.en => en, AppLang.ar => ar };

  CustomTunnel _buildTunnel() {
    final questions = List.generate(
      9,
      (i) => CustomQuestion(
        prompt: _prompts[i].text,
        answer: _answers[i].text,
        difficulty: _difficulties[i],
      ),
    );
    return CustomTunnel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      theme: _theme.text,
      imagePath: _image?.path,
      questions: questions,
    );
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;
      Uint8List? bytes;
      try {
        bytes = await picked.readAsBytes();
      } catch (_) {
        bytes = null;
      }
      if (!mounted) return;
      setState(() {
        _image = picked;
        _preview = bytes;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_t(
          fr: 'Image indisponible sur cet appareil.',
          en: 'Image unavailable on this device.',
          ar: 'الصورة غير متاحة على هذا الجهاز.',
        )),
      ));
    }
  }

  Future<void> _save() async {
    final tunnel = _buildTunnel();
    setState(() => _showErrors = true);
    if (!tunnel.isValid) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(_t(
            fr: 'Thème + 9 questions (3 par difficulté) + réponses requises.',
            en: 'Theme + 9 questions (3 per level) + answers required.',
            ar: 'الموضوع + 9 أسئلة (3 لكل مستوى) + إجابات مطلوبة.',
          )),
        ));
      return;
    }
    setState(() => _saving = true);
    try {
      final store = _store ?? await CustomTunnelStore.load();
      _store ??= store;
      await store.add(tunnel);
      if (!mounted) return;
      // Publication communautaire optionnelle (marché public).
      if (_public) {
        await _publish(tunnel);
        if (!mounted) return;
      } else {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(_t(
              fr: 'Tunnel « ${tunnel.theme.trim()} » sauvegardé sur l\u2019appareil.',
              en: 'Tunnel "${tunnel.theme.trim()}" saved on this device.',
              ar: 'تم حفظ النفق "${tunnel.theme.trim()}" على هذا الجهاز.',
            )),
          ));
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Publie le tunnel sur le marché communautaire (isPublic = true).
  /// Le brouillon local est toujours conservé.
  Future<void> _publish(CustomTunnel tunnel) async {
    try {
      await TunnelRepository(local: _store ?? await CustomTunnelStore.load())
          .publishTunnel(
        tunnel,
        imageBytes: _preview,
        isPublic: true,
        langCode: _lang.code,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(_t(
            fr: 'Publié sur le marché ! Les joueurs peuvent le noter.',
            en: 'Published to the marketplace! Players can rate it.',
            ar: 'تم النشر في السوق! يمكن للاعبين تقييمه.',
          )),
        ));
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(_t(
            fr: 'Sauvegardé local. Publication échouée : ${e.message}',
            en: 'Saved locally. Publish failed: ${e.message}',
            ar: 'حُفظ محليًا. فشل النشر: ${e.message}',
          )),
        ));
    }
  }

  /// Remplit les 9 champs via la Cloud Function `generateTunnel`.
  /// Le thème doit être saisi ; les champs existants sont écrasés.
  Future<void> _generateWithAi() async {
    if (_aiLoading) return;
    if (_theme.text.trim().length < 2) {
      setState(() => _showErrors = true);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(_t(
            fr: 'Saisis d\u2019abord un thème pour l\u2019IA.',
            en: 'Enter a theme first for the AI.',
            ar: 'أدخل موضوعًا أولًا للذكاء الاصطناعي.',
          )),
        ));
      return;
    }
    setState(() => _aiLoading = true);
    try {
      final questions = await TunnelAiService().generate(
        theme: _theme.text,
        lang: _lang.code,
      );
      if (!mounted) return;
      setState(() {
        for (final s in [0, 1, 2]) {
          final diff = TunnelDifficulty.values[s];
          final group =
              questions.where((q) => q.difficulty == diff).toList();
          for (var k = 0; k < 3; k++) {
            _prompts[s * 3 + k].text = group[k].prompt;
            _answers[s * 3 + k].text = group[k].answer;
          }
        }
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(_t(
            fr: '9 questions générées — relis avant de sauvegarder.',
            en: '9 questions generated — review before saving.',
            ar: 'تم توليد 9 أسئلة — راجعها قبل الحفظ.',
          )),
        ));
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  InputDecoration _deco(String hint, {bool error = false}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.creamDim),
      filled: true,
      fillColor: AppColors.deepSpace,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
            color: error ? AppColors.pinkPop : AppColors.midnightLight,
            width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.sun, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('tunnelEditorScreen'),
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration:
              const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            // SingleChildScrollView + Column (pas ListView lazy) :
            // tous les champs restent trouvables en tests, même hors écran.
            child: SingleChildScrollView(
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
                            fr: 'Tunnel custom',
                            en: 'Custom tunnel',
                            ar: 'نفق مخصص'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.midnight.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.midnightLight, width: 1.5),
                      ),
                      child: Text(
                        _t(
                            fr: '$_savedCount sauvegardé(s)',
                            en: '$_savedCount saved',
                            ar: 'المحفوظ: $_savedCount'),
                        style: const TextStyle(
                            color: AppColors.sun,
                            fontWeight: FontWeight.w900,
                            fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    fr: 'Thème + 9 questions (3 Facile / 3 Moyen / 3 Difficile). Stocké sur l\u2019appareil, zéro réseau.',
                    en: 'Theme + 9 questions (3 Easy / 3 Medium / 3 Hard). Stored on-device, zero network.',
                    ar: 'الموضوع + 9 أسئلة (3 سهل / 3 متوسط / 3 صعب). يُخزن على الجهاز بدون شبكة.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                Text(
                  _t(fr: 'Thème', en: 'Theme', ar: 'الموضوع'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('tunnelThemeField'),
                  controller: _theme,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(
                      color: AppColors.cream, fontWeight: FontWeight.w700),
                  decoration: _deco(
                    _t(
                        fr: 'Ex : Animaux, Espace, Foot…',
                        en: 'E.g. Animals, Space, Soccer…',
                        ar: 'مثال: حيوانات، فضاء، كرة…'),
                    error: _showErrors && _theme.text.trim().isEmpty,
                  ),
                ),
                const SizedBox(height: 14),
                // Image optionnelle.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.midnight.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: AppColors.midnightLight, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.deepSpace,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.midnightLight, width: 1.5),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _preview != null
                            ? Image.memory(_preview!, fit: BoxFit.cover)
                            : const Icon(Icons.image_rounded,
                                color: AppColors.creamDim, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t(
                                  fr: 'Image (optionnel)',
                                  en: 'Image (optional)',
                                  ar: 'صورة (اختياري)'),
                              style: const TextStyle(
                                  color: AppColors.cream,
                                  fontWeight: FontWeight.w900),
                            ),
                            Text(
                              _image == null
                                  ? _t(
                                      fr: 'Aucune image — le tunnel marche sans.',
                                      en: 'No image — tunnel works without.',
                                      ar: 'لا صورة — يعمل النفق بدونها.')
                                  : _image!.name.isNotEmpty
                                      ? _image!.name
                                      : _t(
                                          fr: 'Image choisie',
                                          en: 'Image picked',
                                          ar: 'تم اختيار صورة'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.creamDim, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        key: const Key('tunnelImageButton'),
                        onTap: _pickImage,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: AppColors.secondaryGradient,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.ink, width: 2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add_a_photo_rounded,
                                  color: AppColors.cream, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                _t(
                                    fr: 'Choisir',
                                    en: 'Pick',
                                    ar: 'اختيار'),
                                style: const TextStyle(
                                    color: AppColors.cream,
                                    fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (!kIsWeb)
                  Text(
                    _t(
                      fr: 'Formats galerie classiques, reste sur l\u2019appareil.',
                      en: 'Standard gallery formats, stays on-device.',
                      ar: 'صيغ المعرض المعتادة، تبقى على الجهاز.'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 12),
                // Génération IA (Cloud Function, quota 5/jour).
                GestureDetector(
                  key: const Key('tunnelAiButton'),
                  onTap: _aiLoading ? null : _generateWithAi,
                  behavior: HitTestBehavior.opaque,
                  child: Opacity(
                    opacity: _aiLoading ? 0.6 : 1.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: AppColors.goldGradient,
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: AppColors.ink, width: 2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_aiLoading)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.ink,
                              ),
                            )
                          else
                            const Icon(Icons.auto_awesome_rounded,
                                color: AppColors.ink, size: 20),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _aiLoading
                                  ? _t(
                                      fr: 'Génération en cours…',
                                      en: 'Generating…',
                                      ar: 'جارٍ التوليد…')
                                  : _t(
                                      fr: 'Générer les 9 questions avec l\u2019IA',
                                      en: 'Generate 9 questions with AI',
                                      ar: 'توليد الأسئلة التسعة بالذكاء الاصطناعي'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Publication communautaire (marché public + notation).
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.midnight.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppColors.midnightLight, width: 1.5),
                  ),
                  child: SwitchListTile(
                    key: const Key('tunnelPublicSwitch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _t(
                          fr: 'Publier sur le marché',
                          en: 'Publish to marketplace',
                          ar: 'النشر في السوق'),
                      style: const TextStyle(
                          color: AppColors.cream,
                          fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      _t(
                          fr: 'Visible par tous, noté par étoiles.',
                          en: 'Visible to all, star-rated.',
                          ar: 'مرئي للجميع، بتقييم النجوم.'),
                      style: const TextStyle(
                          color: AppColors.creamDim, fontSize: 12),
                    ),
                    activeThumbColor: AppColors.sun,
                    value: _public,
                    onChanged: (v) =>
                        setState(() => _public = v),
                  ),
                ),
                for (var s = 0; s < 3; s++) ...[
                  const SizedBox(height: 16),
                  _SectionTitle(
                    difficulty: TunnelDifficulty.values[s],
                    lang: _lang.code,
                  ),
                  const SizedBox(height: 8),
                  for (var k = 0; k < 3; k++)
                    _QuestionCard(
                      index: s * 3 + k,
                      difficulty: TunnelDifficulty.values[s],
                      promptController: _prompts[s * 3 + k],
                      answerController: _answers[s * 3 + k],
                      showErrors: _showErrors,
                      lang: _lang,
                      deco: _deco,
                    ),
                ],
                const SizedBox(height: 18),
                GameButton(
                  key: const Key('tunnelSaveButton'),
                  label: _saving
                      ? _t(
                          fr: 'Sauvegarde…',
                          en: 'Saving…',
                          ar: 'جارٍ الحفظ…')
                      : _t(
                          fr: 'Sauvegarder le tunnel',
                          en: 'Save tunnel',
                          ar: 'حفظ النفق'),
                  icon: Icons.save_rounded,
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    fr: 'Sauvegarde locale JSON (SharedPreferences), pas de cloud.',
                    en: 'Local JSON save (SharedPreferences), no cloud.',
                    ar: 'حفظ محلي JSON (SharedPreferences)، بدون سحابة.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.difficulty, required this.lang});

  final TunnelDifficulty difficulty;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final color = switch (difficulty) {
      TunnelDifficulty.easy => AppColors.mintPop,
      TunnelDifficulty.medium => AppColors.sun,
      TunnelDifficulty.hard => AppColors.pinkPop,
    };
    return Row(
      children: [
        Container(
            width: 10, height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 8),
        Text(
          '${difficulty.label(lang: lang)} (3)',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: color, letterSpacing: 1.0),
        ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.difficulty,
    required this.promptController,
    required this.answerController,
    required this.showErrors,
    required this.lang,
    required this.deco,
  });

  final int index;
  final TunnelDifficulty difficulty;
  final TextEditingController promptController;
  final TextEditingController answerController;
  final bool showErrors;
  final AppLang lang;
  final InputDecoration Function(String hint, {bool error}) deco;

  String _t({required String fr, required String en, required String ar}) =>
      switch (lang) { AppLang.fr => fr, AppLang.en => en, AppLang.ar => ar };

  @override
  Widget build(BuildContext context) {
    final promptError = showErrors && promptController.text.trim().isEmpty;
    final answerError = showErrors && answerController.text.trim().isEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.midnight.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: AppColors.midnightLight, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
                fr: 'Question ${index + 1}',
                en: 'Question ${index + 1}',
                ar: 'سؤال ${index + 1}'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            key: Key('tunnelQuestionField_$index'),
            controller: promptController,
            minLines: 1,
            maxLines: 3,
            style: const TextStyle(
                color: AppColors.cream, fontWeight: FontWeight.w700),
            decoration: deco(
              _t(
                  fr: 'Énoncé…',
                  en: 'Prompt…',
                  ar: 'نص السؤال…'),
              error: promptError,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: Key('tunnelAnswerField_$index'),
            controller: answerController,
            textInputAction: TextInputAction.next,
            style: const TextStyle(
                color: AppColors.cream, fontWeight: FontWeight.w700),
            decoration: deco(
              _t(
                  fr: 'Réponse exacte…',
                  en: 'Exact answer…',
                  ar: 'الإجابة الدقيقة…'),
              error: answerError,
            ),
          ),
        ],
      ),
    );
  }
}
