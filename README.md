# Forme du jour (`health-tracker`)

App iPhone personnelle qui calcule chaque matin un score de disponibilité à l'entraînement à partir d'Apple Santé. La conception complète est dans [SPEC.md](SPEC.md). Le dépôt ne contient que du code et des données fictives, jamais de données de santé.

## Contenu

| Dossier | Rôle |
|---|---|
| `Packages/ReadinessEngine` | moteur de calcul en Swift pur (Foundation seule), testable hors Mac |
| `App/`, `AppTests/` | app SwiftUI et ses tests. Le projet Xcode est généré par XcodeGen depuis `project.yml` |
| `scripts/` | garde-fou anti-réseau, choix du simulateur, construction des IPA |
| `.github/workflows/` | CI : `Engine` (tests du moteur sous Windows et macOS), `iOS` (tests de l'app et IPA) |

## Tester le moteur en local

**Ce PC a Smart App Control activé.** Windows bloque donc les exécutables de test que `swift test` compile localement (code `C0E90002`). Les tests locaux passent par WSL :

1. Dans un terminal administrateur, lancer `wsl --install`, puis redémarrer.
2. Dans Ubuntu, installer Swift 6.4.1 pour Linux en suivant swift.org/install/linux (par exemple avec `swiftly`).
3. Depuis Ubuntu :

```bash
cd "/mnt/c/Mes Fichiers/INSA Strasbourg/Cours - Marcuzzi Johan - Documents/Perso/Code/App_Sport/Packages/ReadinessEngine"
swift test
```

La CI `Engine` teste quand même le moteur sous Windows (Swift 6.4.1) et sous macOS à chaque push.

## CI et artefacts

Chaque push lance les deux workflows. Pour suivre le dernier run et récupérer les IPA :

```bash
gh run watch
```

```bash
gh run download --name ipa --dir build/ipa
```

L'artefact `ipa` contient :
- `Readiness.ipa` : HealthKit + App Group ;
- `Readiness-healthkit-only.ipa` : HealthKit seul, en secours.

Les deux sont signées ad hoc **avec leurs entitlements**, pour que l'outil de sideload demande HealthKit. Le script `scripts/build-ipa.sh` échoue si l'entitlement HealthKit manque.

## Installer sur l'iPhone (Apple ID gratuit)

1. **Mode développeur :** sur l'iPhone, Réglages > Confidentialité et sécurité > Mode développeur. L'activer, puis redémarrer.
2. **Sideloadly** (sideloadly.io) sous Windows : brancher l'iPhone en USB, choisir `Readiness.ipa`, saisir ton Apple ID, puis Start.
3. **Faire confiance au profil :** sur l'iPhone, Réglages > Général > VPN et gestion de l'appareil > ton Apple ID > Faire confiance.
4. **Rafraîchissement automatique :** dans Sideloadly, activer l'actualisation automatique en Wi-Fi. Le PC doit être allumé et sur le même réseau au moins une fois tous les 7 jours, sinon l'app ne s'ouvre plus.

Limites du compte gratuit : 3 apps par appareil, 10 App ID par période de 7 jours.

### Dépannage

- **L'installation échoue :** réessayer avec `Readiness-healthkit-only.ipa`. L'outil réécrit peut-être l'App Group.
- **La sonde affiche « 0 partout » ou une erreur d'autorisation :** vérifier Réglages > Santé > Accès aux données > Forme du jour. Si l'erreur parle d'un entitlement manquant, essayer SideStore (sidestore.io) au lieu de Sideloadly.
- **Les deux outils échouent pour HealthKit :** c'est le plan B, le pont Raccourcis (SPEC.md §15).

## Vérification de l'étape 0 (sur l'iPhone)

Ouvrir l'app (écran « Sonde HealthKit »), puis :

1. Toucher **Autoriser Santé** : la feuille d'autorisation Santé doit apparaître. Tout autoriser.
2. Relever les compteurs sur 7 jours (mesures VFC, séries battement-à-battement, nuits avec phases, tracés, efforts) et les séances par source. Les comparer à l'app Santé.
3. Relever la ligne **App Group** (OK ou KO).
4. Toucher **Écrire un RPE test sur la dernière séance WorkOutDoors** et relever le texte du résultat. Le test supprime ensuite l'échantillon qu'il a lui-même créé, et seulement celui-là.
5. **À J+8**, vérifier que l'app s'ouvre toujours, ce qui prouve que le rafraîchissement automatique fonctionne.

Envoie ces relevés : la décision (suite normale, SideStore, plan B, RPE en local) sera consignée dans SPEC.md §14.
