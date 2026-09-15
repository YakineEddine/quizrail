# Fiche Play Store — QuizRail (`com.quizrail.quizrail`)

## Nom (30 car. max)
`QuizRail – Quiz & Duels`

## Description courte (80 car. max)
`Quiz en rails : solo, duels en direct et Party entre amis.`

## Description longue (FR)
```
Monte à bord de QuizRail, le quiz qui roule !

🚂 SOLO : fais avancer ton train case par case, enchaîne les bonnes
réponses et empoche des jetons. Indices, bonus, pièges et raccourcis :
chaque partie est différente.

⚔️ DUELS EN DIRECT : défie un joueur en temps réel. Même questions,
pouvoirs (gel, gains x2, vol de jetons), forfait et revanche.

🎉 PARTY ENTRE AMIS : crée une room avec un code à 6 lettres ou un QR,
tes amis rejoignent depuis leur téléphone, tu animes depuis ton écran.

🏆 CLASSEMENTS : mondial, par pays et entre amis.
🛠️ TUNNELS CUSTOM : crée tes quiz, publie-les sur le marché
communautaire, note ceux des autres.

Gratuit, parties courtes, français / English / عربي.
Achats intégrés optionnels (jetons, suppression des pubs, skins, pass).
```

## Description longue (EN, à coller en traduction)
```
All aboard QuizRail, the quiz that rolls!

🚂 SOLO: move your train tile by tile, chain correct answers and stack
tokens. Hints, bonuses, traps and shortcuts: every run is different.

⚔️ LIVE DUELS: challenge a player in real time. Same questions, powers
(freeze, double gains, token steal), forfeit and rematch.

🎉 PARTY WITH FRIENDS: create a room with a 6-letter code or QR, friends
join from their phones, you host from your screen.

🏆 LEADERBOARDS: global, by country and among friends.
🛠️ CUSTOM TUNNELS: build your quizzes, publish them to the community
market, rate other players' tunnels.

Free, short sessions, français / English / عربي.
Optional in-app purchases (tokens, ad removal, skins, pass).
```

## Catégorie / tags
- Catégorie : **Jeux > Quiz / Culture générale** (Trivia).
- Tags : quiz, culture générale, duel, multijoueur, party, famille.

## Captures d'écran (à faire sur un téléphone réel, 1080×2400 min)
1. Accueil (train animé + compteur de jetons).
2. Question en cours + indices (montre l'indice gratuit via pub).
3. Résultats solo (trophée + stats).
4. Duel en direct (les deux trains + pouvoirs).
5. Salon Party (code + QR + liste joueurs).
6. Classements (onglets Mondial/Pays/Amis).
7. Marché communautaire (tunnels + étoiles).
8. Boutique (packs + suppression pubs).
- Min. requis : 2 captures téléphone. Recommandé : 4–8.
- Icône 512×512 : exporter `assets/icon/app_icon.png` (1024) en 512.
- Visuel de présentation 1024×500 : fond nuit `#14102E` + pièce or +
  titre — à composer (Canva/Figma) à partir de `assets/icon/`.

## Icône / splash (déjà générés dans le repo)
- Sources : `assets/icon/app_icon.png`, `app_icon_fg.png`, `app_splash.png`
  (générés par `tool/generate_icon.dart`, reproductibles offline).
- Appliqués via `flutter_launcher_icons` + `flutter_native_splash`.
- Bascule prod pubs : remplacer les IDs TEST dans
  `lib/features/shop/monetization_config.dart` + `AndroidManifest.xml`.
