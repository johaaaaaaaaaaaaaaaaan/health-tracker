# SPEC — « Forme du jour » : score de disponibilité matinal (iOS, usage personnel)

> Version 1.0 — 19/10/2026 — statut : **à relire**
> Nom de code : `Readiness` (identifiants en anglais). Nom affiché : « Forme du jour ». Interface en français.

## 0. Résumé

Une app iPhone SwiftUI, pour un seul utilisateur et hors App Store. Chaque matin, elle calcule à partir d'Apple Santé :

- un **score de disponibilité** sur 100, à la manière du Training Readiness de Garmin ;
- un **statut VFC** ;
- un **temps de récupération** ;
- un **ratio de charge aiguë/chronique** ;
- une **phrase de recommandation**, avec la contribution de chaque composante en points.

Un check-in de 30 s, fait « à l'aveugle » avant l'affichage du score, ajoute le ressenti. Une question quotidienne (« le score d'hier était-il juste ? ») sert à proposer des pondérations calibrées. Toutes les méthodes sont publiées et assumées. Aucune donnée ne quitte le téléphone.

Le développement se fait **sans Mac** :

- le code est écrit sous Windows, et le moteur de calcul est testé sous Windows ;
- l'app est compilée, testée et capturée en simulateur par GitHub Actions (macOS) ;
- elle est installée sur l'iPhone par sideload avec un Apple ID gratuit.

---

## 1. Objectif et critères de succès

**Objectif.** Ouvrir l'app au réveil et savoir en moins d'une minute si la journée se prête à de l'intensité, à du modéré ou à de la récupération, avec la raison.

| # | Critère de succès | Mesure |
|---|---|---|
| C1 | Moins de 60 s entre l'ouverture et la lecture du score, check-in compris (check-in ≤ 30 s) | chronométrage pendant le protocole de 14 jours (§17) |
| C2 | Score explicable : contribution en points par composante, raison de tout plafond, entrées visibles (valeur, ligne de base, n) | écran Contributions et détail des composantes |
| C3 | Robustesse aux trous (nuit sans montre, séance sans FC, check-in oublié, maladie, reprise) : jamais de score absurde, toujours un indicateur de confiance | scénarios de démo et tests de scénarios |
| C4 | Reproductible : mêmes entrées → même score (moteur déterministe, versions d'algorithme et de poids stockées avec chaque score figé) | tests de déterminisme |
| C5 | Calibrable : les réponses « score d'hier juste ? » sont collectées. Après 30 réponses, une proposition de poids est calculée avec son impact simulé | test de calibration sur données synthétiques et écran de proposition |
| C6 | Confidentialité : aucune donnée ne quitte le téléphone | rapport de confidentialité des apps iOS : 0 domaine contacté. Base exclue de la sauvegarde iCloud |

---

## 2. Contexte et contraintes

- **Matériel :**
  - iPhone 13 sous iOS 27.0.1 (iOS 27 supporte l'iPhone 11 et suivants) ;
  - Apple Watch Ultra 2 sous watchOS 27.0.1, portée **toutes les nuits**.
- **Enregistrement des séances :**
  - WorkOutDoors écrit les séances (`HKWorkout`, FC, tracé) dans Santé ;
  - HealthFit les réimporte parfois, ce qui crée des **doublons** ;
  - l'app **Exercice d'Apple** est aussi utilisée de temps en temps.
- **Sports :**
  - course et trail ;
  - vélo de route ;
  - **VTT enduro** (montées comptées) et **VTT de descente** (montées exclues) ;
  - musculation, renforcement et HIIT ;
  - randonnée et montagne ;
  - ski de piste (remontées exclues) et ski de randonnée (montées comptées).
- **Horaires de sommeil variables** : cours, soirées, week-ends décalés.
- **Poste de développement : Windows 11, sans Mac.** macOS en machine virtuelle sur PC est exclu, car la licence d'Apple l'interdit.
- **Signature : Apple ID gratuit (Personal Team).**
  - Les profils expirent au bout de **7 jours**.
  - Limites : 3 apps par appareil, 10 App ID par 7 jours.
  - Disponible : HealthKit, App Groups, Background Modes, Data Protection.
  - Non disponible : iCloud, Push.
  - **Pas d'option payante**, même si le sideload échoue (voir le plan B au §15).
- **Dépôt GitHub public.** Il contient le code et des données fictives uniquement, jamais de données de santé.
- **Confidentialité :**
  - aucun code réseau, aucune dépendance tierce, aucune télémétrie ;
  - base exclue de la sauvegarde iCloud, avec un export manuel local.

---

## 3. Faits HealthKit vérifiés (base de la spec)

La vérification a été faite dans la documentation Apple le 19/10/2026. **V** = vu sur une page Apple. **NV** = non vérifié, à confirmer sur l'appareil à l'étape 0 ou à l'étape 1.

| Donnée | API | Dispo | Remarques qui changent la conception |
|---|---|---|---|
| VFC SDNN | `HKQuantityTypeIdentifier.heartRateVariabilitySDNN` (ms) | iOS 11 — V | Mesure en arrière-plan **≈ toutes les 4 h** et seulement quand l'utilisateur est immobile : **0 à 3 mesures par nuit** (livre blanc Apple, nov. 2024). Les notifications de rythme irrégulier font passer la cadence à 2 h. Chaque séance **Respirer** (app Pleine conscience) écrit une mesure. |
| Série battement-à-battement | `HKSeriesType.heartbeat()`, `HKHeartbeatSeriesSample`, `HKHeartbeatSeriesQuery` | iOS 13 — V | Stockée **avec chaque mesure SDNN**, ce qui permet de **calculer le RMSSD**. Chaque battement donne `timeSinceSeriesStart` et `precededByGap`. Aucun lien objet avec l'échantillon SDNN : on les apparie par plage horaire. Précision des horodatages : NV. |
| VFC RMSSD Apple | `.heartRateVariabilityRMSSD` | iOS 27 — V (existe) | On ne sait pas qui l'écrit (NV). Le « Readiness » d'Apple et le Recovery HRV sont réservés aux Series 12 / Ultra 4 et ne sont pas exposés. Lu en debug uniquement. |
| FC | `.heartRate` | iOS 8 — V | Environ un échantillon toutes les 5 min au repos, toutes les 5 s en séance. `HKMetadataKeyHeartRateMotionContext` est disponible. |
| FC repos Apple | `.restingHeartRate` | iOS 11 — V | **Exclut le sommeil**, publiée **en fin de journée** : inutilisable pour le score du matin. Elle sert seulement de secours pour la FC repos du TRIMP. |
| Sommeil | `.sleepAnalysis` : `asleepCore/Deep/REM/Unspecified`, `awake`, `inBed` | phases iOS 16 — V | La montre écrit `awake` seulement entre deux échantillons de sommeil. `HKMetadataKeyTimeZone` est présent. **Le score de sommeil d'Apple n'est pas dans HealthKit.** |
| Effort de séance | `.workoutEffortScore`, `.estimatedWorkoutEffortScore` (`HKUnit.appleEffortScore()`, 0–10) | iOS 18 — V | Doit être **relié** à une séance via `relateWorkoutEffortSample(_:with:activity:)`, et se lit avec `HKWorkoutEffortRelationshipQuery`. Apple n'estimerait pas l'effort pour les séances d'apps tierces (NV). **On ne sait pas si l'app peut écrire un RPE sur une séance de WorkOutDoors** (NV : à tester à l'étape 0). |
| Effort physique | `.physicalEffort` (MET) | iOS 17 — V | Lu en debug uniquement. |
| Charge d'entraînement Apple | — | — | Aucune API HealthKit. |
| Température du poignet | `.appleSleepingWristTemperature` | iOS 16 — V | Une valeur par nuit, exige la concentration Sommeil, lecture seule. Stockée pour la v2. |
| Fréquence respiratoire, SpO2, VO2max | `.respiratoryRate`, `.oxygenSaturation`, `.vo2Max` | iOS 8 / 8 / 11 — V | Fréquence respiratoire nocturne depuis watchOS 8. Stockées pour la v2. |
| Séances | `HKWorkout`, `workoutActivities`, `statistics(for:)` | iOS 16 — V | `totalEnergyBurned` et `totalDistance` sont **dépréciés** (iOS 18) : utiliser `statistics(for:)`. Sources : `sourceRevision`, `device`. Métadonnées : `HKMetadataKeySyncIdentifier/SyncVersion`, `ExternalUUID`, `WasUserEntered`. HealthFit écrit-il ses propres échantillons de FC ? NV. |
| Tracé | `HKWorkoutRoute`, `HKWorkoutRouteQuery` | iOS 11 — V | Altitude et précision verticale par point. |
| Requêtes | `HKAnchoredObjectQueryDescriptor`, `HKSampleQueryDescriptor`, `HKObserverQuery` | iOS 15.4 — V | `results(for:)` sert de flux continu. La livraison en arrière-plan n'est **pas** supportée par le simulateur. |
| Verrouillage | `HKError.errorDatabaseInaccessible` | V | Données illisibles quand l'iPhone est verrouillé. Conséquence pour la v1.1 : le widget lira un cache. |
| Autorisations | — | V | Un refus de lecture est **indétectable** : l'app voit simplement « aucune donnée ». L'écran de debug doit afficher des compteurs. |
| Swift sous Windows | toolchain Swift 6.4.1 (`winget install Swift.Toolchain`) | V | Swift Testing et XCTest fonctionnent : un package qui ne dépend que de Foundation se teste sous Windows. |

---

## 4. Journal des décisions

| Sujet | Décision | Écarté |
|---|---|---|
| Chaîne de build | PC Windows + GitHub Actions macOS + sideload (Sideloadly ou SideStore) avec Apple ID gratuit | Developer Program et TestFlight (payant, refusé). Mac distant. Raccourcis seul. |
| Si HealthKit échoue en sideload | Plan B gratuit : pont Raccourcis (§15) | Passage au payant |
| Dépôt | Public (minutes macOS de CI illimitées) | Privé (quota de ~200 min/mois) |
| Moteur | Package Swift pur, Foundation seule, testé sous Windows et macOS | Moteur dans la cible de l'app |
| Sauvegarde | Base exclue de la sauvegarde iCloud, export et import manuels d'un fichier JSON | Sauvegarde iCloud. Rien du tout. |
| Mesure VFC | **Hybride** : mesure du matin (Respirer, 1 min) prioritaire, mesures nocturnes en secours, deux lignes de base séparées | Matin seul. Nuit seule. |
| Métrique VFC | **lnRMSSD calculé** depuis les séries battement-à-battement, lnSDNN en secours (ligne de base distincte) | lnSDNN seul |
| FC de repos du matin | Plus basse moyenne glissante sur 30 min pendant le sommeil principal | Moyenne de la nuit. FC repos Apple de la veille. |
| Autres apps de sommeil | Aucune. Filtre « source Apple Watch » appliqué quand même. | — |
| Score de sommeil | Durée 55 %, continuité 20 %, régularité 10 % (horaires variables), phases 15 % | Façon Garmin. Minimal. |
| FC max | 99,5e centile observé en séance sur 12 mois, modifiable. FC repos = moyenne 7 j de la FC nocturne. | Saisie seule. Tanaka (secours seulement). |
| TRIMP et Foster | Facteur personnel k = médiane(TRIMP / sRPE), 0,35 par défaut | Foster partout. Deux charges séparées (v2). |
| Ratio de charge | EWMA 7 j / 28 j, **courbe asymétrique** : ne pénalise pas le sous-entraînement | Courbe symétrique |
| Descente et ski de piste | Sport attribué à la séance (règle et correction manuelle) + exclusion automatique des montées via le tracé altimétrique | Saisie de la durée seule. Filtre par FC. |
| Agrégation | Moyenne pondérée renormalisée + plafonds | Moyenne géométrique. Moyenne pure. |
| Poids de départ | VFC 22, sommeil 15, historique du sommeil 8, FC nocturne 10, récupération 15, charge 15, ressenti 15 | Façon Garmin sans ressenti. Ressenti fort. |
| Temps de récupération | Modèle de fatigue résiduelle (impulsion-réponse), modulé par la nuit | Table intensité × durée. Aucun. |
| Statut VFC | Moyenne 7 j comparée à la base 60 j ± 0,5 écart-type | ± 1 écart-type. Centiles. |
| Ordre du check-in | **À l'aveugle**, avant le score. Bouton « Passer ». | Score d'abord |
| Échelle du check-in | 1–5 avec libellés (McLean) | 1–7 (Hooper). Curseur. |
| Calibration | Après 30 réponses : proposition de poids (± 5 points max par composante), **appliquée seulement si validée** | Collecte seule. Ajustement automatique. |
| Maladie | Case « malade » : score ≤ 30, recommandation de repos, jours exclus des lignes de base, puis 2 jours de « retour progressif » | Simple facteur du journal |
| Reprise après une pause | Plancher sur la charge chronique (50 % de la référence d'avant la pause) + mode reprise | Composante charge retirée |
| Séance sans FC ni RPE | Estimation (RPE par défaut du sport) + rappel « à noter » | Exclue |
| Saisie du RPE | Dans le check-in (séances de la veille) et depuis la liste des séances. Écrit dans Santé si l'étape 0 le permet. | Liste seule. Local seul. |
| Doublons | **Confirmation manuelle** de chaque doublon suspect. Hypothèse « doublon » tant que c'est en attente. Proposition de règle automatique après 10 confirmations identiques. | Automatique. Stricte. |
| Cases du check-in | Alcool, repas tardif, voyage, malade, événement stressant, écran ou travail tard, sieste | Caféine |
| Gel du score | À la première consultation où la nuit est complète. Les séances de la journée comptent pour le lendemain. | Recalcul continu. Heure fixe. |
| Synchronisation tardive | Score provisoire + mise à jour en direct, gel automatique quand la nuit est complète | Écran d'attente |
| Check-in tardif | Va au journal seulement. Score figé inchangé, exclu de la calibration. | Mise à jour du score |
| Historique des graphiques | Recalculé avec les réglages actuels. Le score réellement affiché reste stocké. | Tel qu'affiché |
| Navigation | 4 onglets : Aujourd'hui, Tendances, Séances, Réglages (Debug dedans) | Écran unique |
| Contributions | Écart en points ± par rapport à 50 | Sous-scores et poids |
| Phrase | 4 phrases + ligne « facteur limitant ». Niveaux Optimale, Élevée, Modérée, Basse, Faible. | 3 phrases |
| Mode démo | Source fictive en mémoire, scénarios déterministes choisis par argument de lancement | Injection de données dans le HealthKit du simulateur |
| « Prêt pour l'intensité » | Récupération restante **≤ 6 h** (et non 0 h) | 0 h : condition presque jamais remplie avec un entraînement quotidien |
| Cible de déploiement | iOS 26.0, compilée avec le dernier SDK disponible. API d'iOS 27 derrière `#available`. | iOS 27 seul |

---

## 5. Architecture

### 5.1 Vue d'ensemble

```
┌──────────────────────────── App (SwiftUI, iOS) ─────────────────────────────┐
│  Features/  Today · CheckIn · Trends · Sessions · Settings · Debug          │
│        ▲ @Observable view models                                            │
│  Pipeline/DailyPipeline ──► SyncMonitor (observateurs, app au premier plan)  │
│        │   1. lecture        2. extraction (cache)     3. évaluation        │
│        ▼                                                                    │
│  Data/HealthDataSource (protocole)                                          │
│     ├─ HealthKitDataSource   (requêtes HK → types Raw, rien d'autre)        │
│     ├─ DemoDataSource        (SyntheticDataGenerator, en mémoire)           │
│     └─ ShortcutsImportDataSource (plan B uniquement)                        │
│  Persistence/ SwiftData (App Group, exclu de la sauvegarde) · Backup JSON   │
└────────┬────────────────────────────────────────────────────────────────────┘
         │ types Raw*, entrées utilisateur          ▲ DayEvaluation, ReadinessAssessment
         ▼                                          │
┌──────────── Packages/ReadinessEngine (Swift pur, Foundation seule) ─────────┐
│  Couche A — FeatureExtractor : Raw → NightFeatures, HRVReading,              │
│             SessionFeatures (histogrammes FC, segments de descente)          │
│  Couche B — ReadinessEngine.evaluate : Features + entrées utilisateur        │
│             → doublons, sports, charge, lignes de base, sous-scores,         │
│               agrégation, plafonds, recommandation, confiance, trace         │
│  Calibration/WeightCalibrator · Synthetic/SyntheticDataGenerator            │
│  readiness-cli (exécutable de vérification)                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

Principes :

- **Le moteur ne connaît ni HealthKit ni SwiftUI.**
  - Il reçoit des structures qui recopient les champs HealthKit.
  - Il contient toute l'interprétation : filtres par source, nuit principale, artefacts, contextes de VFC, doublons, formules.
  - Il compile et se teste sous Windows comme sous macOS.
- **Deux couches dans le moteur :**
  - La **couche A** (extraction) produit des caractéristiques par nuit et par séance. Ces résultats sont **mis en cache** par l'app, avec un numéro `extractorVersion`.
  - La **couche B** (évaluation) est rapide, sans entrées/sorties et déterministe. Elle tourne sur 90 jours à chaque rafraîchissement, ce qui permet de recalculer l'historique.
- **`HealthKitDataSource` est une couche mince.** Elle fait des requêtes et une conversion, sans aucune règle métier. La même couche A sert les trois sources de données.
- **Persistance minimale.** On ne stocke que ce que Santé n'a pas, plus des caches dérivés :
  - check-ins, RPE, décisions de doublons, corrections de sport ;
  - scores figés, jeux de poids, réglages ;
  - caches de caractéristiques.
  - Les tracés GPS ne sont **jamais** stockés : seuls les segments retenus le sont.

### 5.2 Arborescence du dépôt

```
App_Sport/
├── SPEC.md                         ← ce document
├── README.md                       guide d'installation (Swift Windows, CI, sideload)
├── project.yml                     XcodeGen : cibles Readiness, ReadinessTests
├── .github/workflows/
│   ├── engine.yml                  swift test sur windows-latest et macos-latest
│   └── ios.yml                     xcodegen → build → tests → captures démo → IPA
├── scripts/
│   ├── build-ipa.sh                archive Release, signature ad hoc + entitlements, IPA
│   ├── demo-screenshots.sh         simulateur : un lancement par scénario et onglet, captures
│   └── check-no-network.sh         refuse URLSession/Network/NWConnection/WebKit dans le code
├── Packages/ReadinessEngine/
│   ├── Package.swift               swift-tools-version 6.0 ; produits ReadinessEngine, readiness-cli
│   ├── Sources/ReadinessEngine/
│   │   ├── Core/        DayKey.swift · TimeMath.swift · Statistics.swift · Piecewise.swift · SeededRandom.swift
│   │   ├── Raw/         RawTypes.swift
│   │   ├── Inputs/      UserInputs.swift
│   │   ├── Settings/    EngineSettings.swift · WeightSet.swift · SportProfile.swift · EngineConstants.swift
│   │   ├── Extraction/  Features.swift · FeatureExtractor.swift · SleepEpisodeBuilder.swift ·
│   │   │                RRIntervals.swift · HRVReadingBuilder.swift · NocturnalHeartRate.swift ·
│   │   │                SessionFeatureBuilder.swift · DescentSegmenter.swift
│   │   ├── Evaluation/  ReadinessEngine.swift · Results.swift · SportClassifier.swift · Deduplicator.swift ·
│   │   │                LoadCalculator.swift · LoadSeries.swift · RecoveryModel.swift · Baselines.swift ·
│   │   │                HRVEvaluator.swift · SleepScorer.swift · ComponentScorers.swift · Aggregator.swift ·
│   │   │                Recommendation.swift · Completeness.swift
│   │   ├── Calibration/ WeightCalibrator.swift
│   │   └── Synthetic/   SyntheticDataGenerator.swift · Scenario.swift
│   ├── Sources/readiness-cli/main.swift
│   └── Tests/ReadinessEngineTests/   (liste aux étapes 1 et 2 du §14) + Fixtures/
├── App/
│   ├── ReadinessApp.swift          @main, choix de la source (HealthKit ou démo) selon LaunchOptions
│   ├── Info.plist                  NSHealthShareUsageDescription, NSHealthUpdateUsageDescription,
│   │                               UIFileSharingEnabled, LSSupportsOpeningDocumentsInPlace
│   ├── Readiness.entitlements      com.apple.developer.healthkit (+ access vide), App Group
│   ├── Sources/
│   │   ├── Support/      LaunchOptions.swift · Formatters.swift
│   │   ├── Data/         HealthDataSource.swift · FeatureCache.swift
│   │   │   ├── HealthKit/ HealthKitDataSource.swift · HealthKitTypes.swift · HealthKitMapper.swift ·
│   │   │   │              HeartbeatSeriesReader.swift · RouteReader.swift · EffortWriter.swift
│   │   │   ├── Demo/      DemoDataSource.swift
│   │   │   └── Shortcuts/ ShortcutsImportDataSource.swift · ImportHealthExportIntent.swift  (plan B seulement)
│   │   ├── Persistence/  Schema.swift · Entities.swift · AppStore.swift · BackupService.swift
│   │   ├── Pipeline/     DailyPipeline.swift · SyncMonitor.swift · TodayModel.swift
│   │   └── Features/
│   │       ├── Today/     TodayView · ScoreGaugeView · ContributionsView · ComponentDetailView
│   │       ├── CheckIn/   MorningFlowView · AccuracyStepView · WellnessStepView · TagsStepView · SessionsStepView
│   │       ├── Trends/    TrendsView · ScoreChart · HRVChart · NightHRChart · LoadChart · SleepChart
│   │       ├── Sessions/  SessionsView · SessionDetailView · DuplicateResolutionView
│   │       ├── Settings/  SettingsView · WeightsView · CalibrationSuggestionView · SportProfilesView · BackupView
│   │       ├── Debug/     DebugView · SourcesDebugView · NightsDebugView · WorkoutsDebugView · EngineTraceView
│   │       └── Probe/     HealthKitProbeView (étape 0, ensuite rangée dans Debug)
│   └── Resources/        Localizable.xcstrings · Assets.xcassets
└── AppTests/             HealthKitMapperTests · PipelineFreezeTests · BackupRoundTripTests · MorningFlowLogicTests
```

### 5.3 Choix techniques

- **Langage et outils :**
  - Swift 6, mode de langage 6, concurrence stricte.
  - SwiftUI et Observation (`@Observable`).
  - Swift Charts.
  - SwiftData avec `VersionedSchema` dès la V1 et un `SchemaMigrationPlan`. Toute évolution doit être additive.
- **Tests :** Swift Testing (`import Testing`) dans le package et dans `AppTests`.
- **Projet Xcode :** **XcodeGen** (`project.yml`). Le `.xcodeproj` n'est jamais versionné, et la CI le génère.
- **Dépendances :** **aucune dépendance tierce à l'exécution.** Les outils de CI (XcodeGen) restent hors de l'app.
- **Contraintes du moteur :**
  - Foundation seule : pas de Combine, d'OSLog ou de SwiftUI.
  - Dates calculées avec `Calendar(identifier: .gregorian)` et le fuseau horaire explicite.
- **Identifiants :**
  - Bundle ID configurable dans `project.yml` (`BUNDLE_ID`, `fr.perso.formedujour` par défaut).
  - App Group : `group.<BUNDLE_ID>`.

---

## 6. Modèle de données

### 6.1 Types bruts (moteur, `Raw/RawTypes.swift`)

Tous les types sont `Codable`, `Sendable` et `Hashable`. Les unités sont **canoniques** : bpm, ms, °C, fraction 0–1, ml/kg/min, MET, secondes.

```swift
public struct RawSource { bundleID: String; name: String; productType: String?; deviceModel: String?; deviceName: String? }
public enum QuantityKind: String { case heartRate, hrvSDNN, hrvRMSSDApple, restingHeartRate, respiratoryRate,
                                   wristTemperature, oxygenSaturation, vo2Max, physicalEffort }
public struct RawQuantitySample { uuid: UUID; kind: QuantityKind; start: Date; end: Date; value: Double;
                                  source: RawSource; motionContext: Int?; metadata: [String: String] }  // metadata vide pour heartRate
public enum SleepStage: String { case inBed, awake, core, deep, rem, unspecified }
public struct RawSleepSample { uuid: UUID; start: Date; end: Date; stage: SleepStage; source: RawSource; timeZoneID: String? }
public struct RawBeat { t: Double /* s depuis le début de la série */; precededByGap: Bool }
public struct RawHeartbeatSeries { uuid: UUID; start: Date; end: Date; source: RawSource; beats: [RawBeat] }
public struct RawInterval { uuid: UUID; start: Date; end: Date; source: RawSource }            // séances de pleine conscience
public struct RawEffort { sampleUUID: UUID; value: Double /* 0–10 */; estimated: Bool }
public struct RawWorkout { uuid: UUID; activityTypeRaw: UInt; start: Date; end: Date; duration: TimeInterval;
                           pauses: [DateInterval]; distanceMeters: Double?; energyKcal: Double?;
                           source: RawSource; metadata: [String: String]; hasRoute: Bool; effort: RawEffort? }
public struct RawLocation { t: Date; altitude: Double; verticalAccuracy: Double; latitude: Double; longitude: Double }
public struct RawRoute { workoutID: UUID; points: [RawLocation] }                              // jamais persisté
public enum BiologicalSex: String { case female, male, other, notSet }
public struct RawProfile { dateOfBirth: DateComponents?; biologicalSex: BiologicalSex }
public struct RawHealthSnapshot { range: DateInterval; fetchedAt: Date; quantities: [RawQuantitySample];
                                  sleep: [RawSleepSample]; heartbeatSeries: [RawHeartbeatSeries];
                                  mindfulSessions: [RawInterval]; workouts: [RawWorkout]; routes: [RawRoute];
                                  profile: RawProfile; sourcesSeen: [RawSource] }
```

`DayKey` (`Core/DayKey.swift`) : `struct DayKey: Hashable, Comparable, Codable, Sendable { year, month, day }`. Il se représente en `"YYYY-MM-DD"` et dispose de `advanced(by:)` et `range(to:)`.

### 6.2 Entrées utilisateur (`Inputs/UserInputs.swift`)

```swift
public struct CheckIn { day: DayKey; createdAt: Date; wasBlind: Bool; skipped: Bool;
                        sleepQuality: Int?; soreness: Int?; stress: Int?; motivation: Int?   // 1 (pire) … 5 (meilleur)
                        tags: Set<CheckInTag> }
public struct CheckInTag: RawRepresentable, Hashable { rawValue: String }   // ensemble ouvert, extensible en v2
//   .alcohol, .lateMeal, .travel, .illness, .stressfulEvent, .lateScreenOrWork, .nap
public enum AccuracyAnswer: Int { case tooOptimistic = 1, right = 0, tooPessimistic = -1 }
public struct AccuracyFeedback { targetDay: DayKey; answer: AccuracyAnswer; answeredAt: Date }
public struct EffortEntry { workoutID: UUID; rpe: Int /* 0–10 */; enteredAt: Date }
public enum DedupDecision { case duplicate(pairKey: String, keep: UUID, ruleID: UUID?), distinct(pairKey: String) }
public struct DedupRule { id: UUID; sourceA: String; sourceB: String; minOverlap: Double; keepSource: String }
public struct SessionOverride { workoutID: UUID; sport: SportID?; manualEffectiveMinutes: Double? }
public struct SportRule { id: UUID; sourceBundlePattern: String; activityTypeRaw: UInt; namePattern: String?; sport: SportID }
public struct MorningActions { continueWithoutMorningHRV: Set<DayKey> }
```

### 6.3 Caractéristiques (couche A, `Extraction/Features.swift`)

```swift
public struct SleepEpisode { start: Date; end: Date; asleep: TimeInterval; deep: TimeInterval; rem: TimeInterval;
                             core: TimeInterval; unspecified: TimeInterval; waso: TimeInterval; awakenings: Int;
                             stagesAvailable: Bool; timeZoneID: String }
public enum HRVContext: String { case morning, nocturnal, other }
public struct HRVReading { id: UUID /* série ou SDNN */; start: Date; end: Date; context: HRVContext;
                           sdnnMs: Double?; rmssdMs: Double?; validDiffs: Int; artifactRate: Double; isValidRMSSD: Bool }
public struct NightFeatures { day: DayKey; mainSleep: SleepEpisode?; naps: [SleepEpisode]; hrvReadings: [HRVReading];
                              nocturnalHR: Double?; nocturnalHRSamples: Int; respiratoryRate: Double?;
                              wristTemperature: Double?; oxygenSaturation: Double?; anyWatchSleepSample: Bool;
                              firstWatchHRAfterWake: Date? }
public struct LoadFeatures { windows: [DateInterval]; effectiveDuration: TimeInterval;
                             hrHistogram: [Int: Double] /* bpm → secondes */; hrCoverage: Double }
public struct SessionFeatures { workoutID: UUID; activityTypeRaw: UInt; source: RawSource; displayName: String?;
                                start: Date; end: Date; full: LoadFeatures; descentOnly: LoadFeatures?;
                                routeCoverage: Double; peakHR: Double?; healthEffort: RawEffort? }
```

### 6.4 Résultats (couche B, `Evaluation/Results.swift`)

```swift
public enum ComponentID: String, CaseIterable { case hrv, sleep, sleepHistory, nocturnalHR, recovery, load, subjective }
public struct ComponentScore { id: ComponentID; available: Bool; missingReason: MissingReason?;
                               subscore: Double?; weight: Double; contribution: Double; inputs: [String: Double] }
public enum CapReason: String { case veryLowComponent, lowHRV, illness, noNightData }
public struct AppliedCap { reason: CapReason; component: ComponentID?; value: Double; delta: Double }
public enum ReadinessLevel: String { case optimal, high, moderate, low, poor }        // Optimale … Faible
public enum RecommendationKind: String { case intensity, moderate, easy, recovery }
public enum Confidence: String { case high, medium, low }
public enum HRVStatus: String { case balanced, elevated, low, veryLow, buildingBaseline, insufficient }
public enum LoadStatus: String { case low, optimal, high, overload }
public enum Completeness { case complete, provisional(missing: [MissingItem]) }
public enum MissingItem: String { case sleepPending, heartRatePending, morningHRVPending }
public struct ReadinessAssessment { day: DayKey; computedAt: Date; score: Int?; uncappedScore: Double?;
                                    level: ReadinessLevel?; components: [ComponentScore]; caps: [AppliedCap];
                                    recommendation: RecommendationKind?; limitingFactor: LimitingFactor;
                                    confidence: Confidence; hrvStatus: HRVStatus; loadStatus: LoadStatus?;
                                    loadRatio: Double?; returnMode: Bool; recoveryHours: Double;
                                    completeness: Completeness; pendingDuplicates: Int; pendingEfforts: Int;
                                    algorithmVersion: Int; weightSetVersion: Int }
public struct TrainingSession { workoutID: UUID; memberIDs: [UUID]; sport: SportID; start: Date; end: Date;
                                effectiveDuration: TimeInterval; ascentsExcluded: Bool; hrReliable: Bool;
                                trimp: Double?; rpe: Int?; rpeSource: RPESource; fosterLoad: Double?;
                                load: Double; method: LoadMethod; isEstimated: Bool }
public struct DayEvaluation { day: DayKey; night: NightFeatures?; dailyLoad: Double; acute: Double; chronic: Double;
                              assessment: ReadinessAssessment }
public struct EngineTrace { lines: [TraceLine] }   // détail chiffré de chaque étape, pour Debug et la CLI
```

### 6.5 Entités persistées (SwiftData, `Persistence/Entities.swift`)

Le stockage est en `VersionedSchema` V1, dans le conteneur App Group, avec `isExcludedFromBackup = true` sur le dossier. Les clés de jour sont des chaînes `"YYYY-MM-DD"`. Les `payload` sont du JSON `Codable` versionné (`schemaVersion` inclus).

| Entité | Clé unique | Champs principaux |
|---|---|---|
| `CheckInRecord` | `dayKey` | `createdAt`, `wasBlind`, `skipped`, `sleepQuality`, `soreness`, `stress`, `motivation`, `tags: [String]` |
| `AccuracyFeedbackRecord` | `targetDayKey` | `answer` (+1 trop optimiste, 0, −1 trop pessimiste), `answeredAt` |
| `EffortRecord` | `workoutID` | `rpe`, `enteredAt`, `healthKitSampleID?` |
| `SessionOverrideRecord` | `workoutID` | `sportID?`, `manualEffectiveMinutes?` |
| `SportRuleRecord` | `id` | `sourceBundlePattern`, `activityTypeRaw`, `namePattern?`, `sportID` |
| `DedupDecisionRecord` | `pairKey` (UUID triés, joints par `|`) | `isDuplicate`, `keepWorkoutID?`, `decidedAt`, `ruleID?` |
| `DedupRuleRecord` | `id` | `sourceA`, `sourceB`, `minOverlap`, `keepSource`, `acceptedAt` |
| `ReadinessSnapshotRecord` | `dayKey` | `frozenAt`, `shownAt`, `score`, `level`, `algorithmVersion`, `weightSetVersion`, `incompleteAtFreeze`, `payload` (le `ReadinessAssessment` tel qu'affiché) — **immuable** |
| `WeightSetRecord` | `version` | `weights` (JSON `[ComponentID: Double]`), `origin` (default, calibration), `createdAt`, `isActive` |
| `CalibrationProposalRecord` | `id` | `createdAt`, `proposedWeights`, `feedbackCount`, `status` (pending, accepted, refused), `impact` (JSON) |
| `SettingsRecord` | singleton | `payload` = `EngineSettings` sans les poids (FC max forcée, sexe forcé, besoin de sommeil, mesure du matin activée, profils de sport, priorités de source) |
| `MorningActionRecord` | `dayKey` | `continueWithoutMorningHRV` |
| `NightFeaturesCache` | `dayKey` | `extractorVersion`, `payload`, `updatedAt` |
| `SessionFeaturesCache` | `workoutID` | `extractorVersion`, `payload`, `updatedAt` |
| `HRVReadingCache` | `seriesID` | `extractorVersion`, `payload` |
| `SyncAnchorRecord` | `typeIdentifier` | `anchor: Data` |

### 6.6 Extensibilité sans restructuration

| Extension | Ce qui existe déjà en v1 |
|---|---|
| v1.1 widget, notification, complication | Snapshot figé dans le conteneur **App Group**. Le widget lit `ReadinessSnapshotRecord` et ne lit jamais Santé, qui est illisible quand l'iPhone est verrouillé. |
| v2 recommandation de séance et charge maximale conseillée | `acute`, `chronic`, `C_eff`, fatigue résiduelle et profils de sport sont exposés par `DayEvaluation`. |
| v2 signes inhabituels | `NightFeatures` stocke déjà la FC nocturne, la VFC, la fréquence respiratoire, la température et la SpO2. `Baselines` est générique pour toute série journalière. |
| v2 besoin de sommeil adaptatif | Historique de `SleepEpisode`, check-ins (`sleepQuality`) et retours de calibration. Le besoin est un réglage lu par `SleepScorer`. |
| v2 corrélations du journal | `CheckInTag` est un ensemble **ouvert**. Les métriques journalières sont dans `DayEvaluation`. |
| v2 focus de charge | `LoadFeatures.hrHistogram` par séance permet de recalculer n'importe quel découpage par zones. |
| v3 batterie d'énergie | Les échantillons bruts de FC et de VFC sont déjà lus. Il faudra un nouveau module moteur, sans modifier les types existants. |
| v3 import FIT | `RawWorkout.source` + nouvelle implémentation `HealthDataSource`. Le `Deduplicator` gère déjà N sources. |
| v3 objectifs et affûtage | Nouvelle entité `GoalEventRecord`, purement additive. |
| v3 Siri et Raccourcis | `DailyPipeline` et `AppStore` sont appelables depuis des App Intents. |
| v3 résumé hebdo et export CSV | Tout est dans les snapshots, les séances et les check-ins. `BackupService` sérialise déjà tout. |

---

## 7. Interfaces principales

### 7.1 Moteur

```swift
// Extraction/FeatureExtractor.swift
public struct FeatureExtractor: Sendable {
    public static let version = 1                                   // extractorVersion
    public init(constants: EngineConstants = .v1)
    public func nights(from raw: RawHealthSnapshot, days: [DayKey]) -> [NightFeatures]
    public func sessions(from raw: RawHealthSnapshot, workoutIDs: [UUID]?) -> [SessionFeatures]  // nil = toutes
    public func workoutsNeedingRoutes(_ raw: RawHealthSnapshot) -> [UUID]   // vélo, ski de piste, snowboard
}

// Evaluation/ReadinessEngine.swift
public struct EngineInput: Sendable {
    public var nights: [DayKey: NightFeatures]
    public var sessions: [SessionFeatures]
    public var profile: RawProfile
    public var checkIns: [DayKey: CheckIn]
    public var efforts: [UUID: EffortEntry]
    public var dedupDecisions: [DedupDecision]
    public var dedupRules: [DedupRule]
    public var overrides: [UUID: SessionOverride]
    public var sportRules: [SportRule]
    public var settings: EngineSettings            // inclut le WeightSet actif
    public var morningActions: MorningActions
    public var days: ClosedRange<DayKey>           // jours à évaluer (90 j)
    public var now: Date
    public var timeZone: TimeZone
}
public struct EngineOutput: Sendable {
    public var days: [DayKey: DayEvaluation]
    public var sessions: [TrainingSession]
    public var dedupCandidates: [DedupCandidate]          // en attente de confirmation
    public var dedupRuleProposals: [DedupRuleProposal]
    public var hrMax: HRMaxEstimate                       // valeur, origine, séance source
    public var loadUnification: LoadUnification           // k, n, origine
    public var trace: EngineTrace
}
public struct ReadinessEngine: Sendable {
    public static let algorithmVersion = 1
    public init(constants: EngineConstants = .v1)
    public func evaluate(_ input: EngineInput) -> EngineOutput
}

// Calibration/WeightCalibrator.swift
public struct CalibrationSample: Sendable { day: DayKey; subscores: [ComponentID: Double]; shownScore: Double; capped: Bool; answer: AccuracyAnswer }
public struct WeightCalibrator: Sendable {
    public func suggest(samples: [CalibrationSample], current: WeightSet, defaults: WeightSet) -> CalibrationSuggestion?
}

// Synthetic/SyntheticDataGenerator.swift
public struct SyntheticDataGenerator: Sendable {
    public init(seed: UInt64, scenario: Scenario, now: Date, days: Int = 90, timeZone: TimeZone)
    public func snapshot() -> RawHealthSnapshot
    public func userInputs() -> (checkIns: [CheckIn], efforts: [EffortEntry], feedback: [AccuracyFeedback])
}
```

### 7.2 App

```swift
// Data/HealthDataSource.swift
enum DataSourceKind: Sendable { case healthKit, demo(Scenario), shortcutsImport }
enum WriteResult: Sendable { case written(UUID), unsupported(String), failed(String) }
protocol HealthDataSource: Sendable {
    var kind: DataSourceKind { get }
    func requestAuthorization() async throws
    func fetch(range: DateInterval) async throws -> RawHealthSnapshot             // tout sauf les tracés
    func fetchWorkoutChanges() async throws -> (added: [RawWorkout], deleted: [UUID]) // requête ancrée
    func fetchRoutes(workoutIDs: [UUID]) async throws -> [RawRoute]
    func changes() -> AsyncStream<Void>                                           // observateurs, app au premier plan
    func writeEffort(rpe: Int, workoutID: UUID) async -> WriteResult
}

// Pipeline/DailyPipeline.swift
@MainActor @Observable final class DailyPipeline {
    enum State { case idle, importing(progress: Double), needsAuthorization, ready(TodayModel), failed(String) }
    private(set) var state: State
    func refresh(reason: RefreshReason) async     // .launch, .foreground, .healthChange, .userInput, .manual
    func markDisplayed(_ day: DayKey)             // déclenche le gel si l'évaluation du jour est complète
    func rebuildAll() async                       // Debug : réextraction complète
}

// Persistence/AppStore.swift — dépôt unique devant SwiftData (MainActor)
// Persistence/BackupService.swift
struct BackupService { func export() throws -> URL; func importBackup(from: URL) throws -> ImportReport }
```

---

## 8. Algorithmes et formules

Toutes les constantes chiffrées sont regroupées dans `EngineConstants.v1` (§8.14). Les fonctions « par paliers » interpolent **linéairement** entre les points donnés et sont constantes au-delà des extrémités (`Core/Piecewise.swift`).

### 8.1 Conventions

- **Source Apple Watch :** `source.productType` commence par `"Watch"` ou `deviceModel == "Watch"`.
  - Ce filtre s'applique au sommeil, à la FC, à la VFC et aux séries battement-à-battement.
  - La FC enregistrée pendant une séance WorkOutDoors a pour source WorkOutDoors et pour appareil la montre : elle passe le filtre.
- **Fuseau horaire :**
  - celui de `HKMetadataKeyTimeZone` de l'échantillon s'il est présent, sinon le fuseau courant ;
  - le `DayKey` d'une nuit est la date locale de **fin** du sommeil principal ;
  - le `DayKey` d'une séance est la date locale de son **début**.
- **Jour affiché :** avant 03:00 heure locale, l'app affiche le jour J−1, avec un bandeau « Nuit en cours ».
- **Jours exclus des lignes de base :** les jours cochés « malade » (§8.11).

### 8.2 Sommeil

**Épisodes** (`SleepEpisodeBuilder`) :

1. On prend les échantillons `asleep*` de la montre et on les trie par début.
2. On les fusionne en épisodes tant que le trou entre deux échantillons est ≤ 90 min.
3. Pour chaque épisode :
   - `start` = premier début et `end` = dernière fin ;
   - `asleep` = union des durées `asleep*` ;
   - `waso` = (end − start) − asleep ;
   - `awakenings` = nombre d'intervalles non dormis ≥ 3 min ;
   - `stagesAvailable` = vrai si au moins un échantillon core, deep ou REM existe.
4. Les échantillons `inBed` sont ignorés.

**Nuit principale du jour J :** l'épisode au `asleep` maximal (≥ 30 min) qui se termine dans l'intervalle [J 03:00, J 15:00[. Les autres épisodes ≥ 20 min sont des **siestes** : elles sont stockées mais pas notées en v1.

**Score de sommeil** (`SleepScorer`, 0–100). Les poids sont 55 % durée, 20 % continuité, 10 % régularité et 15 % phases. Une sous-composante indisponible est retirée et les poids sont renormalisés.

- **Durée :** r = asleep / besoin (besoin = 8 h par défaut, réglable). Paliers r → score : ≤ 0,5 → 0 ; 0,625 → 30 ; 0,75 → 60 ; 0,875 → 85 ; ≥ 1,0 → 100.
- **Continuité :** `clamp(100 − 1,0 × max(0, waso_min − 15) − 4 × max(0, awakenings − 3), 0, 100)`.
- **Régularité :** écart Δ (en min) entre le milieu de la nuit et la moyenne **circulaire** des milieux des 7 nuits principales précédentes (au moins 3 nuits requises). Paliers : Δ ≤ 30 → 100 ; Δ ≥ 180 → 0.
- **Phases :** d = deep/asleep et p = REM/asleep. `f_d` vaut 0 si d ≤ 4 % et 100 si d ≥ 12 %. `f_p` vaut 0 si p ≤ 8 % et 100 si p ≥ 18 %. Phases = (f_d + f_p)/2. Composante indisponible si `!stagesAvailable`.

**Historique du sommeil (3 nuits) :**

- dette = Σ max(0, besoin − asleep) sur les nuits principales de J, J−1 et J−2 ;
- au moins 2 nuits sont requises, et s'il en manque une, dette × 3/n ;
- paliers dette → score : ≤ 0,5 h → 100 ; ≥ 6 h → 0.

### 8.3 VFC

**Intervalles RR** (`RRIntervals`) : pour chaque battement i ≥ 1 avec `!precededByGap`, RR_i = t_i − t_{i−1}. L'intervalle qui mène à un battement précédé d'un trou est abandonné, mais l'horodatage de ce battement est conservé.

**Artefacts :** un RR est valide si 0,3 s ≤ RR ≤ 2,0 s et |RR − med5| ≤ 0,2 × med5. Ici, med5 est la médiane des RR disponibles dans une fenêtre centrée de 5.

**RMSSD :**

- différences successives d = RR_{i+1} − RR_i, pour deux RR valides et adjacents ;
- RMSSD = √(moyenne(d²)) × 1000 ms ;
- la lecture est **valide** si elle compte ≥ 20 différences et si taux d'artefacts = RR invalides / RR totaux ≤ 0,20.

**Appariement :** une série et un échantillon SDNN forment une même lecture si leurs débuts diffèrent de ≤ 5 s ou s'ils se recouvrent à ≥ 50 %.

**Contexte** (`HRVReadingBuilder`) :

- `morning` :
  - le début est dans [fin du sommeil principal − 15 min, fin + 90 min] ;
  - la lecture chevauche une séance de pleine conscience ;
  - on retient la première lecture qui remplit ces conditions.
- `nocturnal` : la lecture est entièrement dans [start, end] du sommeil principal et ne chevauche aucune séance de pleine conscience.
- `other` : tout le reste, ignoré par le score et visible en Debug.

**Valeurs journalières (en ln) :**

- x_m(J) = ln(RMSSD) de la lecture du matin ;
- x_n(J) = moyenne des ln(RMSSD) des lectures nocturnes valides (au moins une) ;
- **secours SDNN :** même calcul avec SDNN quand le contexte n'a aucune lecture RMSSD valide. La métrique est étiquetée, et **les lignes de base sont séparées par (contexte, métrique)**.

**Ligne de base** (`Baselines`), pour le jour J :

- valeurs des jours J−60 à J−1, hors jours exclus ;
- μ = moyenne et σ = écart-type d'échantillon, avec un plancher σ ≥ 0,05 ;
- la base est **mature** si n ≥ 14.

**Choix du jour**, dans cet ordre. Chaque option exige une valeur du jour **et** une ligne de base mature pour ce couple (contexte, métrique) :

1. (matin, RMSSD), seulement si la mesure du matin est activée ;
2. (nuit, RMSSD) ;
3. (matin, SDNN), seulement si la mesure du matin est activée ;
4. (nuit, SDNN) ;
5. sinon, la composante manque.

**Calculs :**

- m7 = moyenne des valeurs du même couple (contexte, métrique) sur J−6 à J, avec au moins 3 valeurs ;
- z7 = (m7 − μ)/σ et z_j = (x(J) − μ)/σ ;
- **z = 0,6 × z7 + 0,4 × z_j**. Si m7 n'est pas disponible, z = z_j.

**Statut (sur m7) :**

| Statut | Condition |
|---|---|
| Très basse | m7 < μ − 1,5σ |
| Basse | m7 < μ − 0,5σ |
| Équilibrée | μ − 0,5σ ≤ m7 ≤ μ + 0,5σ |
| Élevée | m7 > μ + 0,5σ (neutre pour le score en v1) |
| En construction | n < 14 |
| Insuffisante | m7 indisponible |

**Indicateur d'instabilité :** CV7 = 100 × écart-type / moyenne des ln sur 7 jours. Il est seulement affiché.

**Sous-score VFC :** paliers z → score : ≤ −2,5 → 0 ; −1,5 → 30 ; −1,0 → 55 ; −0,5 → 80 ; ≥ 0 → 100.

**Affichage :** la valeur du jour exp(x) et la moyenne exp(m7), en ms.

### 8.4 FC nocturne

- Échantillons de FC de la montre pendant le sommeil principal.
- Pour chaque échantillon i, on calcule la moyenne de la fenêtre [t_i, t_i + 30 min] si elle contient ≥ 4 échantillons. **FC_nuit = la plus basse de ces moyennes.**
- Si aucune fenêtre n'est valide, la composante manque.
- Ligne de base : jours J−60 à J−1 hors jours exclus, avec μ, σ (plancher 1,5 bpm) et maturité à n ≥ 14.
- z = (FC_nuit − μ)/σ. Paliers z → score : ≤ 0,5 → 100 ; 1,0 → 75 ; 1,5 → 50 ; 2,0 → 25 ; ≥ 3,0 → 0.
- **FC repos utilisée par le TRIMP**, par ordre de priorité :
  1. moyenne de FC_nuit sur 7 jours (au moins 3 nuits) ;
  2. sinon μ sur 60 jours ;
  3. sinon moyenne sur 7 jours de `restingHeartRate` ;
  4. sinon 60 bpm.

### 8.5 Séances et charge par séance

**Sports et profils** (`SportProfile`, modifiables dans Réglages) :

| `SportID` | Famille | FC représentative | Montées exclues | RPE par défaut |
|---|---|---|---|---|
| `run` course | pied | oui | non | 5 |
| `trailRun` trail | pied | oui | non | 6 |
| `roadBike` vélo de route | vélo | oui | non | 5 |
| `mtbEnduro` VTT enduro | vélo | oui | non | 6 |
| `mtbDownhill` VTT de descente | vélo | **non** (Foster prioritaire) | **oui** | 6 |
| `strength` muscu, renfo | salle | non | non | 6 |
| `hiit` HIIT | salle | non | non | 7 |
| `hike` randonnée, montagne | montagne | oui | non | 3 |
| `alpineSki` ski de piste, snowboard | montagne | non | **oui** | 4 |
| `skiTouring` ski de randonnée | montagne | oui | non | 5 |
| `other` autre | autre | oui | non | 4 |

**Classification** (`SportClassifier`), par ordre de priorité :

1. correction manuelle de la séance (`SessionOverride.sport`) ;
2. `SportRule` créée par l'utilisateur (« toujours pour ce profil » : source + type d'activité + motif sur le nom ou les métadonnées) ;
3. table par défaut selon le type d'activité HealthKit :

| Type HealthKit | Sport par défaut |
|---|---|
| running | run |
| cycling | roadBike |
| traditionalStrengthTraining, functionalStrengthTraining, coreTraining | strength |
| highIntensityIntervalTraining, crossTraining, mixedCardio | hiit |
| hiking | hike |
| downhillSkiing, snowboarding | alpineSki |
| crossCountrySkiing | skiTouring |
| autres | other |

Les motifs propres à WorkOutDoors (nom de profil dans les métadonnées) sont relevés à l'étape 1. On les ajoute alors à la table par défaut.

**Fenêtres utiles :**

- `full` = [start, end] moins les pauses.
- `descentOnly` (`DescentSegmenter`) est calculé pour les séances candidates qui ont un tracé :
  1. on écarte les points dont la précision verticale est < 0 ou > 20 m ;
  2. on rééchantillonne à 5 s et on applique une médiane glissante de 15 s sur l'altitude ;
  3. vitesse verticale v(t) = (alt(t+15 s) − alt(t−15 s)) / 30 s ;
  4. un segment est une **montée** si v > +0,15 m/s pendant ≥ 60 s ;
  5. `descentOnly` = `full` moins les montées.
- Si le tracé couvre moins de 50 % de la séance, `descentOnly` vaut nil. La séance est alors marquée « montées non exclues » et l'app propose de saisir à la main les minutes de descente (`manualEffectiveMinutes`, qui a priorité).
- La fenêtre retenue est `descentOnly` si le profil exclut les montées, sinon `full`.

**FC de séance :**

- échantillons de la montre dans les fenêtres retenues, **dédoublonnés par horodatage (± 1 s)**, quelle que soit l'app source ;
- couverture = Σ min(Δt entre échantillons, 60 s) / durée utile ;
- **FC fiable** si couverture ≥ 0,80 ;
- `hrHistogram` donne les secondes par bpm entier, chaque échantillon valant min(Δt, 60 s).

**FC max :**

- pic d'une séance = 99,5e centile de l'histogramme pondéré par la durée ;
- FC max observée = maximum des pics sur 12 mois, parmi les séances de couverture ≥ 0,5 et de pic ≤ 220 ;
- priorité : valeur forcée dans les Réglages, puis valeur observée, puis Tanaka (208 − 0,7 × âge), puis 190 ;
- les séances de J−365 à J−91 ne servent qu'au pic : leur FC est lue en différé, après le premier affichage.

**TRIMP de Banister (1991)**, calculé depuis l'histogramme :

- HRr = clamp((bpm − FC_repos)/(FC_max − FC_repos), 0, 1) ;
- TRIMP = Σ_bpm (secondes/60) × HRr × a × e^(b × HRr) ;
- homme : a = 0,64 et b = 1,92 ; femme : a = 0,86 et b = 1,67. Le sexe vient de Santé, sinon des Réglages, sinon les coefficients homme sont utilisés.

**RPE**, par ordre de priorité :

1. saisi dans l'app ;
2. `workoutEffortScore` relié à la séance ;
3. `estimatedWorkoutEffortScore` relié ;
4. RPE par défaut du sport, marqué **estimé**.

**Foster (2001) :** sRPE = RPE × minutes utiles.

**Facteur k** (`LoadCalculator`) :

- séances des 90 derniers jours qui remplissent toutes ces conditions : FC représentative, FC fiable, RPE réel (saisi ou `workoutEffortScore`, jamais estimé ni par défaut), TRIMP > 0 ;
- k = médiane(TRIMP / sRPE), bornée à [0,15 ; 0,80], si n ≥ 8 ;
- sinon **k = 0,35**.

**Charge unifiée** (en unités TRIMP) :

| Situation | Charge | Méthode |
|---|---|---|
| FC représentative et FC fiable | TRIMP | `.trimp` |
| Sinon, RPE réel disponible | k × sRPE | `.foster` |
| Sinon | k × RPE par défaut × minutes | `.estimated` (badge « séance à noter ») |

### 8.6 Doublons (`Deduplicator`)

- **Paire candidate :** chevauchement ≥ 0,6 × durée de la plus courte **et** (même famille de sport **ou** une des deux a HealthFit pour source). Les groupes de plus de deux séances se forment par composantes connexes.
- **Séance à garder (proposition) :** priorité de source WorkOutDoors > Exercice d'Apple > HealthFit > autres. Les motifs de bundle sont réglables et confirmés à l'étape 1. En cas d'égalité, on garde la meilleure couverture FC.
- **États d'une paire :**
  - `pending` : en attente ;
  - `duplicate(keep:)` : confirmé comme doublon, avec la séance à garder ;
  - `distinct` : confirmé comme deux séances différentes ;
  - `duplicate(ruleID:)` : traité par une règle automatique acceptée.
- **Tant que c'est en attente :** la paire est traitée comme un doublon, avec la séance proposée. L'évaluation expose `pendingDuplicates`, ce qui n'empêche pas le gel du score. Une décision prise plus tard modifie l'historique recalculé, mais jamais un score figé.
- **Proposition de règle :** après **10 confirmations identiques consécutives** pour le même couple de sources, avec un chevauchement ≥ 0,9 et la même source gardée, l'app propose « Toujours fusionner A + B (chevauchement ≥ 90 %), garder A ». Les décisions prises ensuite par la règle sont marquées `auto` et restent réversibles.
- **FC :** elle est lue par plage horaire depuis la montre (§8.5). Une copie HealthFit ne double donc jamais la FC.

### 8.7 Charge aiguë et chronique (`LoadSeries`)

- **Charge du jour :** L_d = Σ des charges unifiées des séances retenues du jour d.
- **EWMA** (Williams et al., 2017), avec λ = 2/(N+1) :
  - λ_a = 0,25 (7 j) et λ_c = 2/29 ≈ 0,0690 (28 j) ;
  - A_d = λ_a × L_d + (1 − λ_a) × A_{d−1}, et de même pour C_d avec λ_c ;
  - initialisation : A et C valent la moyenne de L sur les 28 premiers jours de la fenêtre.
- **Évaluation le matin du jour J :** A = A_{J−1} et C = C_{J−1}. Les séances du jour comptent pour le lendemain.
- **Pause :** ≥ 14 jours consécutifs avec L = 0.
  - C_ref = médiane de C sur les 60 jours qui précèdent la pause (s'il y a moins de 28 jours d'historique, maximum de C).
  - **Mode reprise :** de la première séance après la pause jusqu'à ce que C ≥ 0,7 × C_ref, ou au plus 28 jours.
  - Pendant la pause et le mode reprise : C_eff = max(C, 0,5 × C_ref). Le reste du temps, C_eff = C.
- **Ratio :** R = A / C_eff. La composante manque si C_eff < 1,0, ou si moins de 28 jours séparent la première séance connue de J.
- **Sous-score asymétrique :** paliers R → score : ≤ 1,0 → 100 ; 1,3 → 70 ; 1,5 → 40 ; ≥ 2,0 → 0.
- **Statut affiché :** R < 0,8 « Charge basse » ; 0,8–1,3 « Optimale » ; 1,3–1,5 « Élevée » ; > 1,5 « Surcharge ». Un badge « Reprise » s'ajoute si le mode reprise est actif.
- **Garde-fou du mode reprise :** si W7 > 1,15 × W7_précédent, la recommandation est plafonnée à « Séance modérée possible ». Ici W7 est la somme de L sur les 7 jours se terminant à J−1, et W7_précédent celle des 7 jours d'avant.

### 8.8 Temps de récupération (`RecoveryModel`)

- **Fatigue résiduelle :** F(t) = Σ L_i × e^(−(t − fin_i)/τ), avec **τ = 26 h**. On prend les séances retenues terminées avant t, sur les 10 derniers jours.
- **Seuil :** Θ = 0,9 × C_eff. Si C_eff manque, Θ = 30.
- **Temps brut :** h_brut(t) = τ × ln(F(t)/Θ) si F > Θ, sinon 0.
- **Modulation par la nuit :**
  - p = moyenne des sous-scores disponibles parmi {VFC, sommeil}, divisée par 100 ;
  - **m = 1,3 − 0,5 × p**, ce qui donne 0,8 quand p = 1 et 1,3 quand p = 0 ;
  - si aucun des deux n'est disponible, m = 1.
- **Temps final :** h = clamp(m × h_brut(t_éval), 0, 96) h. Il est figé avec le score.
- **Après le gel :** Aujourd'hui affiche « séance enregistrée depuis : récup ≈ X h (comptera demain) », sans modifier le score.
- **Sous-score :** paliers h → score : 0 → 100 ; 12 → 80 ; 24 → 55 ; 48 → 25 ; ≥ 72 → 0.
- **Ordres de grandeur attendus :**
  - entraînement quotidien au niveau chronique, séance le soir : environ 4 h restantes au matin ;
  - deux jours à environ 2 × la charge chronique : environ 16 h restantes.

### 8.9 Ressenti (check-in)

Les 4 items sont orientés de 1 (pire) à 5 (meilleur) :

- sommeil ressenti : de « très mauvais » à « excellent » ;
- courbatures : de « très fortes » à « aucune » ;
- stress : de « très élevé » à « très bas » ;
- motivation : de « aucune » à « très forte ».

**Sous-score :** moyenne des items répondus de (x − 1)/4 × 100. Il n'est pris en compte **que si le check-in du jour a été fait à l'aveugle** (`wasBlind`). Les cases n'ont aucun effet sur le score, sauf « malade ».

### 8.10 Agrégation, plafonds, niveaux, recommandation, confiance (`Aggregator`, `Recommendation`)

**Score :**

- Poids actifs w_k (somme = 100). Valeurs par défaut : VFC 22, sommeil 15, historique du sommeil 8, FC nocturne 10, récupération 15, charge 15, ressenti 15.
- Soit D l'ensemble des composantes disponibles. Si Σ_D w < 40, l'app affiche « Données insuffisantes » sans score.
- score_brut = Σ_D w_k × s_k / Σ_D w_k.
- **Contribution affichée :** c_k = (w_k / Σ_D w) × (s_k − 50), d'où score_brut = 50 + Σ c_k. Les composantes manquantes apparaissent grisées avec leur raison.

**Plafonds** (le plus restrictif s'applique, et la ligne « Plafond : raison (−X) » s'affiche) :

| Code | Condition | Plafond |
|---|---|---|
| P1 | une composante disponible a s_k < 25 | 50 |
| P2 | statut VFC Basse ou Très basse | 60 |
| P3 | case « malade » cochée aujourd'hui | 30 |
| P4 | nuit sans données (sommeil, VFC et FC nocturne tous absents, jour complet) | 74 |

**Score final :** round(min(score_brut, plafond)), borné à [1, 100].

**Niveaux** (seuils de Garmin) : Optimale 95–100 · Élevée 75–94 · Modérée 50–74 · Basse 25–49 · Faible 1–24.

**Recommandation** (les lignes sont évaluées de haut en bas, et la première qui s'applique l'emporte) :

| Phrase | Condition |
|---|---|
| « Privilégie la récup » | score < 35 ou malade aujourd'hui |
| « Endurance facile ou technique » | 35–54, ou l'un des 2 jours de retour progressif après une maladie |
| « Séance modérée possible » | 55–74, ou score ≥ 75 avec un plafond appliqué, une récupération > 6 h ou le garde-fou du mode reprise |
| « Prêt pour de l'intensité » | score ≥ 75, aucun plafond, récupération ≤ 6 h, garde-fou de reprise inactif |

**Ligne « facteur limitant »**, première règle qui s'applique :

1. malade ;
2. retour progressif ;
3. raison du plafond ;
4. « Encore N h de récupération » si h > 6 ;
5. contribution la plus négative si elle est ≤ −3, avec un gabarit par composante :
   - « Ton sommeil limite le score » ;
   - « Dette de sommeil sur 3 nuits » ;
   - « VFC sous ta normale » ;
   - « FC nocturne élevée » ;
   - « Charge en forte hausse (ratio 1,42) » ;
   - « Ressenti en baisse » ;
6. sinon « Aucun facteur limitant ».

**Confiance :**

| Niveau | Conditions |
|---|---|
| Haute | Σ_D w ≥ 85, bases VFC et FC matures, jour complet |
| Moyenne | Σ_D w ≥ 60 |
| Faible | sinon, ou si P4 s'applique |

### 8.11 Maladie

- **Jour coché « malade » :** plafond P3, recommandation de récupération, jour exclu des lignes de base VFC et FC. La charge éventuelle est comptée normalement.
- **Retour progressif :** les 2 jours qui suivent le dernier jour coché, la recommandation est au plus « Endurance facile ou technique », avec un bandeau « retour progressif ». Le score n'est pas plafonné.

### 8.12 Complétude, provisoire, gel (`Completeness`)

Pour le jour J à l'instant « maintenant » :

| Élément manquant | Condition |
|---|---|
| `sleepPending` | pas de nuit principale pour J, ou elle s'est terminée il y a moins de 20 min (et il est avant 14:00) |
| `heartRatePending` | nuit principale trouvée, mais FC nocturne absente et aucun échantillon de FC de la montre après le réveil |
| `morningHRVPending` | mesure du matin activée, aucune lecture du matin, moins de 2 h depuis le réveil, et l'utilisateur n'a pas touché « continuer sans » |

- **Nuit sans montre :** aucun échantillon de sommeil de la montre depuis J−1 18:00, alors que la montre a écrit de la FC après J 05:00. Le jour est alors **complet**, sans les composantes nocturnes, et le plafond P4 s'applique.
- **Score provisoire :** tant que le jour n'est pas complet, l'évaluation est provisoire et affiche la liste de ce qui manque (par exemple « dernière donnée 02:14 »). Elle est recalculée à chaque changement détecté par `SyncMonitor`, avec 5 s d'attente avant recalcul.
- **Gel :** dès qu'une évaluation **complète** est affichée à l'écran (`markDisplayed`), un `ReadinessSnapshotRecord` immuable est écrit.
  - Si la première consultation a lieu après 14:00 et que le jour est toujours incomplet, le score est figé tel quel avec `incompleteAtFreeze = true`.
- **Recalcul de l'historique :** les graphiques et les jours passés sont recalculés avec les réglages actuels. Le détail d'un jour montre les deux valeurs : celle affichée ce jour-là et la valeur recalculée.

### 8.13 Calibration (`WeightCalibrator`)

- **Échantillons utilisables :**
  - jours qui ont un score figé, une réponse « score d'hier juste ? » et **aucun plafond appliqué** ;
  - la question est posée dans le check-in du lendemain, avant l'affichage du score du jour, et reste proposée jusqu'à 48 h ;
  - un check-in tardif (fait après avoir vu le score) n'entre jamais dans la calibration.
- **Cible fictive :** t_d = score_affiché_d − δ × réponse_d, avec δ = 15. La réponse vaut +1 pour « trop optimiste », 0 pour « juste », −1 pour « trop pessimiste ».
- **Problème à résoudre :**
  - P_d(w) = Σ_{D_d} w_k × s_kd / Σ_{D_d} w_k ;
  - minimiser J(w) = (1/N) × Σ (P_d(w) − t_d)² + λ × Σ (w_k − w_def_k)², avec λ = 1,0 ;
  - w_def = les **poids de départ** (§8.10). La régularisation tire toujours vers eux, ce qui empêche une dérive cumulée au fil des calibrations ;
  - sous les contraintes Σ w = 100, w_k ≥ 3 et |w_k − w_actif_k| ≤ 5. Ici, w_actif = le jeu de poids actif au moment du calcul (paramètre `current`).
- **Méthode :** descente de gradient projetée, déterministe : 2000 itérations, pas de 0,05, projection sur l'intersection de la boîte et du simplexe par bisection.
- **Déclenchement :** au moins 30 échantillons utilisables depuis le jeu de poids actif.
- **Proposition affichée si :** max |Δw| ≥ 1 point et J s'améliore d'au moins 5 %.
- **Écran de proposition :**
  - poids actuels et poids proposés ;
  - impact simulé sur 90 jours : écart moyen de score, nombre de jours dont la recommandation change, part des réponses « juste » ou « trop optimiste/pessimiste » qui seraient mieux expliquées.
- **Décision :**
  - acceptée : nouveau `WeightSetRecord` (version + 1, origine calibration). L'historique est recalculé et les snapshots gardent leur version ;
  - refusée : proposée à nouveau après 30 nouveaux échantillons.

### 8.14 Constantes (`EngineConstants.v1`)

| Groupe | Valeurs |
|---|---|
| Sommeil | fusion 90 min ; fenêtre de fin [03:00, 15:00[ ; minimum 30 min ; sieste ≥ 20 min ; poids 55/20/10/15 ; besoin 8 h ; réveil ≥ 3 min |
| VFC | RR [0,3 ; 2,0] s ; tolérance 20 % sur med5 ; ≥ 20 différences ; artefacts ≤ 20 % ; fenêtre du matin [−15 ; +90] min ; base 60 j, n ≥ 14, σ ≥ 0,05 ; m7 ≥ 3 valeurs ; z = 0,6 z7 + 0,4 z_j ; zone ± 0,5σ, très basse −1,5σ |
| FC nocturne | fenêtre 30 min, ≥ 4 échantillons ; σ ≥ 1,5 bpm |
| Séances | couverture FC ≥ 0,80 ; trou max 60 s ; montée > +0,15 m/s pendant ≥ 60 s ; couverture du tracé ≥ 50 % ; FC max au 99,5e centile sur 12 mois, pic ≤ 220 |
| TRIMP | homme 0,64 / 1,92 ; femme 0,86 / 1,67 |
| k | défaut 0,35 ; n ≥ 8 ; bornes [0,15 ; 0,80] ; 90 j |
| Doublons | chevauchement ≥ 0,6 ; règle proposée après 10 confirmations avec chevauchement ≥ 0,9 |
| Charge | λ_a = 0,25 ; λ_c = 2/29 ; pause ≥ 14 j ; plancher 0,5 × C_ref ; sortie du mode reprise à 0,7 × C_ref ou 28 j ; garde-fou + 15 % |
| Récupération | τ = 26 h ; Θ = 0,9 × C_eff ; modulation 1,3 − 0,5p ; maximum 96 h ; seuil « intensité » 6 h |
| Agrégation | poids 22/15/8/10/15/15/15 ; minimum Σw 40 ; plafonds P1 50, P2 60, P3 30, P4 74 ; confiance 85/60 |
| Calibration | δ 15 ; λ 1,0 ; N ≥ 30 ; ± 5 ; poids minimal 3 ; amélioration ≥ 5 % |
| Gel | fin du sommeil + 20 min ; attente de la VFC du matin 2 h ; gel forcé à 14:00 ; jour affiché qui bascule à 03:00 |

Toute modification d'une constante qui change un résultat incrémente `ReadinessEngine.algorithmVersion` (couche B) ou `FeatureExtractor.version` (couche A).

### 8.15 Vecteurs de test de référence (calculés à la main)

| Fonction | Entrée | Attendu |
|---|---|---|
| TRIMP | 30 min à HRr = 0,5 (FC repos 50, FC max 190, FC 120), homme | 30 × 0,5 × 0,64 × e^0,96 = **25,07** |
| RMSSD (fonction brute) | RR = 1,000 ; 1,050 ; 0,980 ; 1,020 ; 0,990 s | √(0,0099/4) = **49,75 ms** |
| EWMA aiguë | L = 100, 0, 0 avec A0 = 0 | **25 ; 18,75 ; 14,0625** |
| Récupération | une séance de 100 à t = 0, C_eff = 50, t = 12 h, m = 1 | 26 × ln(63,04/45) ≈ **8,77 h** |
| Durée du sommeil | 6 h 30 pour un besoin de 8 h | r = 0,8125 → **72,5** |
| Agrégation | s = VFC 82, sommeil 77, historique 75, FC 80, récup 97, charge 90, ressenti 43, poids par défaut | contributions +7,04 ; +4,05 ; +2,0 ; +3,0 ; +7,05 ; +6,0 ; −1,05 → **78** |

---

## 9. UX / UI

### 9.1 Parcours du matin

À l'ouverture, s'il n'y a ni score figé ni check-in pour le jour, une feuille plein écran (`MorningFlowView`) s'affiche **avant** le score. Chaque étape a un bouton « Passer ». Objectif : ≤ 30 s.

0. **Bandeau (non bloquant)** si aucune mesure VFC du matin n'est détectée : « Fais 1 min de Respirer sur ta montre, allongé, avant de te lever ». S'y ajoute un bouton « Continuer sans ».
1. **Calibration** (si le score d'hier est figé et sans réponse) : « Hier : 78 · Prêt pour de l'intensité. C'était… » avec les choix [Trop optimiste] [Juste] [Trop pessimiste].
2. **Bien-être :** 4 lignes de 5 gros boutons libellés (sommeil, courbatures, stress, motivation).
3. **Cases :** des puces pour Alcool, Repas tardif, Voyage, Malade, Événement stressant, Écran ou travail tard, Sieste.
4. **Séances de la veille :** une ligne RPE 0–10 par séance sans RPE réel, et une ligne « Même séance ? » [Oui, garder X] [Non, deux séances] par doublon en attente.
5. **« Voir mon score »** mène à Aujourd'hui.

Les 30 s du check-in laissent aussi le temps à la montre de synchroniser la nuit. Si l'utilisateur passe tout le check-in, il est enregistré comme `skipped` et le score est calculé sans ressenti. Un check-in rempli plus tard dans la journée est marqué `wasBlind = false` et va au journal seulement.

### 9.2 Onglets

- **Aujourd'hui :**
  - En-tête : date, puis « figé à 7:42 », ou un badge « Provisoire » avec ce qui manque.
  - Jauge du score et niveau.
  - Phrase de recommandation, puis ligne « facteur limitant ».
  - Badge de confiance.
  - Tuiles : VFC (statut, ms, tendance), Récupération (h), Charge (ratio et statut, badge Reprise), Sommeil (score et durée), FC nuit (bpm et Δ par rapport à la base).
  - **Contributions** en barres de part et d'autre de 0, avec la ligne de plafond. Un tap ouvre `ComponentDetailView` : entrées, μ ± σ, n, formule en une phrase, paliers.
  - Mini-courbe du score sur 7 jours.
  - Badges « N séances à noter » et « N doublons à confirmer ».
  - Note d'après-gel « séance enregistrée depuis : récup ≈ X h ».
- **Tendances :** sélecteur 7, 30 ou 90 jours. Graphiques Swift Charts :
  1. score (barres colorées par niveau, repères des réponses de calibration) ;
  2. VFC : points du jour en ms, ligne de la moyenne sur 7 jours, bande normale μ ± 0,5σ, avec indication du contexte et de la métrique ;
  3. FC nocturne et bande de la base ;
  4. charge : barres journalières, lignes aiguë et chronique, et sous-graphique du ratio avec la bande 0,8–1,3 ;
  5. sommeil : durée en barres, ligne du besoin, courbe du score.
  - Un tap sur un jour ouvre son détail (valeur figée et valeur recalculée).
- **Séances :**
  - Liste par jour : icône du sport, durée utile, charge avec un badge de méthode (TRIMP, Foster, estimé), RPE.
  - Section « Doublons à confirmer ».
  - Détail d'une séance :
    - RPE ;
    - sport, avec l'interrupteur « toujours pour ce profil » ;
    - résolution des doublons ;
    - minutes de descente si le tracé manque ;
    - couverture FC, fenêtres retenues.
- **Réglages :**
  - Profil : FC max (observée et forcée), sexe pour le TRIMP, besoin de sommeil.
  - Mesure VFC du matin (oui/non).
  - Poids : jeu actif, historique, proposition de calibration.
  - Profils de sport.
  - Sauvegarde : export et import.
  - Mode démo et choix du scénario.
  - **Debug**.
  - À propos : versions d'algorithme et références (annexe A).

### 9.3 Debug (`DebugView`)

- **Sources et autorisations :**
  - par type : nombre d'échantillons sur 90 jours, première et dernière date, sources (bundle, nom, productType), date de dernière synchronisation ;
  - un type à 0 affiche « 0 échantillon : autorisation refusée ? iOS ne permet pas de le savoir », avec un lien vers Réglages > Santé.
- **Nuits :**
  - chronologie des phases ;
  - épisodes et siestes ;
  - lectures VFC (heure, SDNN, RMSSD calculé, nombre de différences, taux d'artefacts, contexte, appariement) ;
  - nombre d'échantillons de FC et FC_nuit ;
  - fréquence respiratoire, température, SpO2.
- **Séances :**
  - source, type brut, toutes les métadonnées ;
  - durée et pauses ;
  - présence d'un tracé ;
  - effort Santé, réel ou estimé ;
  - couverture FC, pic, fenêtres de descente ;
  - doublons candidats et décision ;
  - détail de la charge (TRIMP, sRPE, k, méthode).
- **Trace moteur** d'un jour choisi : chaque sous-score avec ses entrées, ses lignes de base, les plafonds et la recommandation (`EngineTrace`).
- **Actions :**
  - « Tout réimporter » (`rebuildAll`) ;
  - « Exporter le JSON de debug », en local via la feuille de partage ;
  - sonde HealthKit de l'étape 0.

### 9.4 Accessibilité et rendu

- Dynamic Type.
- Libellés VoiceOver sur la jauge et les graphiques (valeurs résumées).
- Couleurs de niveau toujours doublées d'un libellé.
- Mode sombre.
- Taille de référence des captures : iPhone 13 (390 × 844 pt).

---

## 10. Mode démo

- **Principe :** `DemoDataSource` enveloppe `SyntheticDataGenerator` (graine fixe). Le stockage est **en mémoire** : il n'y a aucune persistance et HealthKit n'est jamais touché. Le mode est activable par argument de lancement ou dans Réglages, y compris sur l'iPhone.
- **Arguments** (`LaunchOptions`) :
  - `-demoScenario <nom>` ;
  - `-demoNow 2026-10-19T07:45:00+02:00` ;
  - `-demoTab today|trends|sessions|settings|debug` ;
  - `-demoSheet checkin|none` ;
  - `-demoTrendsRange 7|30|90`.

| Scénario | Contenu | Attendu, vérifié par les tests et les captures |
|---|---|---|
| `normal` | 90 j, 4–5 séances par semaine, mesure du matin quotidienne | score de 60 à 90 la plupart du temps, VFC équilibrée, confiance haute |
| `overreaching` | charge + 60 % sur les 10 derniers jours, VFC en baisse, FC nocturne + 4 bpm | ratio ≈ 1,5, VFC basse (P2), score < 50, phrase « Endurance facile… » ou « Privilégie la récup » |
| `illness` | J−3 à J cochés « malade », FC nocturne + 8, VFC très basse | P3, score ≤ 30, bases inchangées par rapport au scénario `normal` |
| `missingNight` | aucune donnée de sommeil la nuit dernière | P4, score ≤ 74, confiance faible |
| `returnFromBreak` | pause de 21 j puis 3 séances | plancher appliqué, badge Reprise, pas d'explosion du ratio |
| `duplicates` | copies WorkOutDoors et HealthFit, dont une en attente | badge « 1 doublon à confirmer », charge comptée une seule fois |
| `descent` | sortie de descente VTT avec télésiège (tracé) | durée utile ≈ 1/3 du total, TRIMP calculé sur les descentes seulement |
| `provisionalMorning` | sommeil terminé à 07:20, il est 07:25, FC pas encore synchronisée | badge Provisoire, liste de ce qui manque |
| `calibration` | 40 réponses de calibration, biais simulé | proposition de calibration disponible |

`scripts/demo-screenshots.sh` démarre le simulateur, installe l'app et la lance pour chaque couple (scénario, onglet ou feuille) avec `-demoNow` figé. Il prend ensuite une capture avec `xcrun simctl io booted screenshot`. Les captures sont publiées comme artefact de CI `screenshots/`.

---

## 11. Confidentialité et sauvegarde

- **Aucun code réseau.** `scripts/check-no-network.sh` (exécuté en CI) échoue si `URLSession`, `Network`, `NWConnection`, `WKWebView` ou `URLRequest` apparaît dans `App/` ou dans `Packages/`. Il n'y a aucune dépendance tierce.
- **Exclusion de la sauvegarde :** le dossier du stockage SwiftData (conteneur App Group) porte `isExcludedFromBackup = true`. C'est vérifié et réappliqué à chaque lancement.
- **Export :** `readiness-backup-AAAAMMJJ.json` contient toutes les entités sauf les caches, avec un `schemaVersion`. On le partage via la feuille de partage (Fichiers > Sur mon iPhone). Le dossier `Documents` est aussi visible depuis Windows par l'app « Appareils Apple » en USB (`UIFileSharingEnabled`), sans aucun cloud.
- **Import :** sélecteur de fichier, contrôle du `schemaVersion`, fusion par clé unique, puis rapport de ce qui a été ajouté, ignoré ou en conflit.
- **Données sensibles :** les tracés GPS ne sont jamais persistés. Le JSON de debug contient des données de santé : il n'est créé qu'à la demande et l'utilisateur choisit sa destination.
- **Contrôle final :** Réglages iOS > Confidentialité et sécurité > Rapport de confidentialité des apps doit montrer **0 domaine** contacté par « Forme du jour ».

---

## 12. Build, CI, installation

- **Windows (local) :**
  - Swift 6.4.1 (`winget install Swift.Toolchain`) et Visual Studio Build Tools.
  - Dans `Packages/ReadinessEngine` : `swift build`, `swift test`, `swift run readiness-cli --scenario <nom> --days 30`. La CLI affiche, jour par jour, les sous-scores, le score, les plafonds et la recommandation.
  - J'installe `gh` sur ce PC (winget) avec ton accord. L'authentification (`gh auth login`) et la création du compte GitHub restent à faire par toi.
- **GitHub Actions** (dépôt public, créé par l'utilisateur ou avec son accord) :
  - `engine.yml` : à chaque push, `swift test` sur `windows-latest` et `macos-latest`.
  - `ios.yml` : sur push vers `main` et `workflow_dispatch`, sur `macos-latest` :
    1. sélection du Xcode le plus récent ;
    2. `brew install xcodegen` puis `xcodegen generate` ;
    3. `scripts/check-no-network.sh` ;
    4. `xcodebuild test`, schéma `Readiness`, simulateur iPhone 13 (ou l'iPhone le plus proche disponible) ;
    5. `scripts/demo-screenshots.sh` ;
    6. `scripts/build-ipa.sh`.
  - Artefacts publiés : `screenshots/`, `Readiness.ipa`, `xcresult`.
- **`build-ipa.sh` :**
  - archive Release sans signature ;
  - **signature ad hoc avec les entitlements** (`codesign --force --sign - --entitlements App/Readiness.entitlements`), pour que l'outil de sideload sache qu'il faut demander HealthKit ;
  - contrôle avec `codesign -d --entitlements :-` : la clé `com.apple.developer.healthkit` doit être présente ;
  - création de `Payload/` puis zip en `.ipa`.
- **Comment je vérifie :** `gh run watch`, puis `gh run download <id> -n screenshots -D build/screenshots`, puis lecture des PNG.
- **Installation sur l'iPhone (par l'utilisateur) :**
  1. activer le mode développeur sur l'iPhone ;
  2. dans Sideloadly sous Windows, choisir l'IPA et saisir son Apple ID gratuit ;
  3. faire confiance au profil dans Réglages > Général > VPN et gestion de l'appareil ;
  4. activer le rafraîchissement automatique de Sideloadly en Wi-Fi : le PC doit être allumé et sur le même réseau au moins une fois tous les 7 jours.
  - **Alternative :** SideStore, qui se rafraîchit depuis l'iPhone.

---

## 13. Hors périmètre v1

- Widget, notification du matin, complication, app watchOS, rafraîchissement en arrière-plan et livraison en arrière-plan HealthKit (v1.1).
- Recommandation de séance détaillée et charge maximale conseillée, alerte « signes inhabituels », besoin de sommeil adaptatif, corrélations du journal, focus de charge et deux charges séparées (v2).
- Batterie d'énergie, import FIT, objectifs et affûtage, Siri et Raccourcis (hors plan B), résumé hebdomadaire, export CSV (v3).
- Notation des siestes, cycle menstruel, acclimatation à l'altitude ou à la chaleur, FC max par sport.
- Tout réseau, synchronisation cloud, iCloud, compte utilisateur, multi-utilisateur, iPad, autre langue que le français.
- App Store, TestFlight, Apple Developer Program payant (exclus par choix).
- Injection de données dans le HealthKit du simulateur.
- Écriture dans Santé d'autre chose que le RPE (et le RPE seulement si l'étape 0 le permet).

---

## 14. Plan de livraison v1

Chaque étape se termine par :

- un **critère que je peux lancer moi-même** (tests, build, captures) ;
- un **protocole que tu suis sur l'iPhone** avec tes vraies données.

Une étape n'est terminée que quand les deux sont validés.

### Étape 0 — Socle, CI et preuve HealthKit en sideload

**Contenu :**

- `project.yml`, cible `Readiness` (entitlement HealthKit, App Group), `Info.plist` avec les textes d'autorisation ;
- package `ReadinessEngine` minimal (`DayKey` + un test) ;
- `.github/workflows/engine.yml` et `ios.yml`, `scripts/build-ipa.sh`, `scripts/check-no-network.sh` ;
- `README.md`, avec les guides d'installation de Swift sous Windows et de sideload.

**`HealthKitProbeView` (sonde) :**

- demande la lecture de la VFC SDNN, de la série battement-à-battement, du sommeil, des séances, de l'effort et du tracé, et l'écriture de `workoutEffortScore` ;
- affiche, sur 7 jours, le nombre de mesures de VFC, de séries battement-à-battement, de nuits avec phases, et de séances WorkOutDoors et HealthFit ;
- bouton « Écrire un RPE test sur la dernière séance WorkOutDoors » : `relateWorkoutEffortSample`, puis relecture via `HKWorkoutEffortRelationshipQuery`, puis suppression de l'échantillon de test écrit par l'app ;
- affiche le résultat : écrit, refusé, ou erreur avec son code.

**Ce que je vérifie :**

- `swift test` passe sous Windows ;
- la CI est verte (moteur sous Windows et macOS, build iOS) ;
- l'artefact `Readiness.ipa` existe, et `codesign -d --entitlements` montre `com.apple.developer.healthkit` ;
- `check-no-network.sh` passe.

**Ce que tu vérifies sur l'iPhone :**

1. installation par Sideloadly ;
2. la feuille d'autorisation Santé apparaît ;
3. les compteurs ne sont pas à zéro et correspondent à peu près à l'app Santé ;
4. résultat du test d'écriture du RPE ;
5. à J+8, l'app s'ouvre toujours, ce qui prouve que le rafraîchissement automatique fonctionne.

**Décision consignée ici, en fin d'étape :**

| Résultat | Suite |
|---|---|
| HealthKit OK | on continue normalement |
| HealthKit KO avec Sideloadly | on essaie SideStore |
| KO avec les deux | plan B (§15), puis l'étape 1 adaptée |
| Écriture du RPE impossible | RPE stocké en local seulement, sans autre changement |

### Étape 1 — Lecture HealthKit, cache, doublons et écran de debug

**Contenu :**

- `HealthKitDataSource`, `HealthKitTypes`, `HealthKitMapper`, `HeartbeatSeriesReader`, `RouteReader` ;
- import de 90 jours avec indicateur de progression, puis lecture différée des pics de FC sur 12 mois ;
- **à chaque rafraîchissement :**
  - réextraction de J, J−1 et J−2 ;
  - séances nouvelles ou supprimées via une requête ancrée ;
  - nouvelles séries battement-à-battement via une requête ancrée ;
  - reconstruction complète à la demande, ou si `extractorVersion` change ;
- couche A complète (`FeatureExtractor`, épisodes de sommeil, RMSSD, contextes VFC, FC nocturne, caractéristiques des séances, segmentation des descentes) et `Deduplicator` ;
- `SyntheticDataGenerator`, scénarios `normal` et `duplicates` (base des tests et des captures de debug) ;
- `DemoDataSource` et `LaunchOptions` minimaux (`-demoScenario`, `-demoNow`, `-demoTab debug`), et une première version de `scripts/demo-screenshots.sh` ;
- schéma SwiftData V1 complet, `AppStore`, exclusion de la sauvegarde ;
- `DebugView` complète (§9.3) et résolution des doublons dans Debug.

**Ce que je vérifie :**

- `swift test` sous Windows : `SleepEpisodeTests`, `RRIntervalsTests` (vecteur RMSSD, rejet d'artefacts, gestion de `precededByGap`), `HRVContextTests`, `NocturnalHRTests`, `DescentSegmenterTests`, `DedupTests` ;
- `AppTests/HealthKitMapperTests` en CI : des `HKQuantitySample` et `HKCategorySample` construits en test convertis vers les types Raw, avec les unités ;
- captures de Debug en mode démo (`-demoTab debug`, scénario `duplicates`).

**Ce que tu vérifies sur l'iPhone, et que tu reportes dans le tableau « Constats de l'étape 1 » ci-dessous :**

- les nuits et les phases correspondent à l'app Santé sur 5 nuits ;
- nombre de lectures VFC par nuit et part de celles qui ont une série RMSSD valide ;
- la mesure Respirer du matin est bien détectée comme `morning` ;
- chaque doublon WorkOutDoors + HealthFit est détecté et apparié ;
- bundle ID affiché pour l'app Exercice d'Apple et pour WorkOutDoors ;
- métadonnées de WorkOutDoors : nom de profil qui permettrait de reconnaître descente, enduro et ski ;
- présence du tracé sur une sortie de descente et segments de montée cohérents ;
- un RPE saisi dans l'app Forme d'Apple est bien lu.

**Constats de l'étape 1** (à remplir). Ces constats règlent les choix avec une règle par défaut fixée d'avance :

| Constat | Règle de décision |
|---|---|
| Métrique VFC | si ≥ 60 % des mesures SDNN des 30 dernières nuits ont une série donnant un RMSSD valide, on garde **RMSSD**. Sinon SDNN devient la métrique principale. |
| Motifs de bundle (WorkOutDoors, Exercice, HealthFit) | on reporte les valeurs observées dans `SourcePriority` |
| Règles de sport WorkOutDoors | on ajoute les motifs observés à la table par défaut du §8.5 |
| HealthFit écrit-il sa propre FC ? | sans conséquence sur le calcul (lecture de la FC de la montre par plage horaire), à noter seulement |

### Étape 2 — Moteur de calcul testé, avec les entrées du check-in et du RPE

**Contenu :**

- couche B complète : `SportClassifier`, `LoadCalculator` (TRIMP, Foster, k), `LoadSeries` (EWMA, pause, mode reprise), `RecoveryModel`, `Baselines`, `HRVEvaluator`, `SleepScorer`, `ComponentScorers`, `Aggregator`, `Recommendation`, `Completeness`, `EngineTrace` ;
- `WeightCalibrator` ;
- les entrées `CheckIn`, `EffortEntry`, `AccuracyFeedback` et `SessionOverride` sont **déjà consommées**, alimentées en test par le générateur ;
- tous les scénarios du §10 dans le générateur ;
- exécutable `readiness-cli` ;
- branchement de `EngineTrace` dans Debug (trace d'un jour sur les vraies données).

**Ce que je vérifie :**

- `swift test` sous Windows et en CI macOS, avec :
  - `TRIMPTests`, `RecoveryModelTests`, `EWMALoadTests`, `SleepScoreTests`, `AggregatorTests` : vecteurs du §8.15, somme des contributions = score brut − 50, renormalisation, plafonds, niveaux, recommandation, facteur limitant ;
  - `ReturnFromBreakTests`, `LoadUnifierTests` (k par défaut puis appris) ;
  - `CompletenessTests` ;
  - `CalibrationTests` : sur des données générées avec des poids « vrais » w*, la proposition se rapproche de w* (corrélation(Δw, w* − w0) > 0,5) et respecte les bornes ;
  - `ScenarioTests` : attendus du tableau du §10 ;
  - `PropertyTests` : améliorer un seul sous-score ne baisse jamais le score ; même entrée → même sortie ; 90 jours évalués en moins de 300 ms en CI ;
- `swift run readiness-cli --scenario overreaching --days 30` affiche une trajectoire cohérente : ratio qui monte, VFC basse, score qui baisse.

**Ce que tu vérifies sur l'iPhone :**

- Debug > Trace moteur sur tes 90 jours ;
- une semaine chargée connue donne bien un ratio élevé ;
- une période de maladie ou de grosse fatigue connue donne bien une VFC basse et une FC nocturne haute ;
- la FC max observée et le k appris sont plausibles ;
- aucune séance n'est classée dans un sport aberrant.

### Étape 3 — Mode démo, écran principal, graphiques, gel du score

**Contenu :**

- `DailyPipeline`, `SyncMonitor`, `TodayModel`, gel et snapshots ;
- onglets Aujourd'hui (jauge, phrase, facteur limitant, confiance, tuiles, contributions et détails), Tendances (5 graphiques, 7/30/90 jours, détail d'un jour) et Réglages (profil, poids en lecture, profils de sport, mode démo) ;
- mode démo complet : tous les arguments du §10, le réglage dans Réglages, et `scripts/demo-screenshots.sh` étendu à tous les scénarios et onglets.

**Ce que je vérifie :**

- `AppTests/PipelineFreezeTests` en CI :
  - provisoire → complet → gel ;
  - un snapshot figé ne change plus quand de nouvelles données arrivent ;
  - gel forcé à 14:00 ;
  - basculement du jour affiché à 03:00 ;
- **captures** relues une à une : chaque scénario × (Aujourd'hui, Contributions, Tendances 7/30/90, Réglages), en clair et en sombre ;
- contrôle visuel : pas de texte tronqué, phrase et plafond conformes aux attendus du §10.

**Ce que tu vérifies sur l'iPhone, pendant 7 matins :**

- le score apparaît et passe de « Provisoire » à « figé » ;
- l'heure du gel est cohérente ;
- les graphiques sur 90 jours sont plausibles ;
- le ressenti global du score est juste, noté librement en attendant le check-in.

### Étape 4 — Check-in et effort ressenti

**Contenu :**

- `MorningFlowView` et ses 5 étapes (§9.1), avec le bandeau de mesure du matin et « Passer » ;
- check-in tardif envoyé au journal ;
- onglet Séances complet (RPE, sport et « toujours pour ce profil », doublons, minutes de descente) ;
- `EffortWriter`, si l'étape 0 l'a autorisé ;
- proposition de règle de doublons ;
- `CalibrationSuggestionView`, avec acceptation et refus ;
- `BackupService` (export et import), `BackupView`.

**Ce que je vérifie :**

- `AppTests/MorningFlowLogicTests` :
  - un check-in à l'aveugle compte dans le score, un check-in tardif non ;
  - la question de calibration n'est posée que pour un score d'hier figé ;
  - le RPE saisi remplace l'estimation et retire le badge ;
- `BackupRoundTripTests` : export puis import dans un stockage vide → égalité ;
- captures : chaque étape du check-in, Séances (scénarios `duplicates` et `descent`), proposition de calibration (scénario `calibration`).

**Ce que tu vérifies sur l'iPhone :**

- check-in chronométré, objectif ≤ 30 s ;
- RPE écrit et visible dans l'app Forme d'Apple (si autorisé) ;
- résolution des doublons en un tap ;
- export vers Fichiers et import sur une réinstallation propre ;
- une semaine d'usage complète.

---

## 15. Plan B — pont Raccourcis (seulement si l'étape 0 échoue pour HealthKit)

- **Principe :** l'app n'a plus l'entitlement HealthKit. Un raccourci « Export Santé → Forme du jour », créé par l'utilisateur avec un modèle fourni, fait trois choses :
  1. il lit les échantillons Santé avec l'action « Rechercher des échantillons de santé » : VFC SDNN, FC, FC repos, sommeil, séances si disponibles, fréquence respiratoire, température ;
  2. il construit un JSON au format `RawHealthSnapshot` (sans les séries battement-à-battement ni les tracés) ;
  3. il appelle l'App Intent `ImportHealthExportIntent(file:)`.
- **Déclenchement :** l'app lance le raccourci via `shortcuts://run-shortcut?name=…` à l'ouverture, ou une automatisation personnelle le lance chaque matin.
- **Confidentialité :** rien ne quitte le téléphone.
- **Conséquences :**

| Fonctionnalité | Ce qui change |
|---|---|
| VFC | lnSDNN seulement (§8.3, secours) |
| Exclusion des montées | sans tracé, saisie manuelle des minutes de descente |
| Effort Santé | probablement indisponible : RPE saisi dans l'app |
| Gel du score | « complet » une fois l'import du jour fait |

- **Le reste de la spec ne change pas** : couche A, couche B, UI. L'étape 1 est remplacée par « import Raccourcis + Debug », avec les mêmes critères de vérification, hormis le RMSSD.

---

## 16. Étapes ultérieures (non détaillées)

**v1.1 — En dehors de l'app :**

- widget du score (lit le snapshot dans l'App Group) ;
- notification du matin quand le score est figé (exige la livraison en arrière-plan HealthKit : à revérifier avec le compte gratuit) ;
- complication Apple Watch (app watchOS minimale ou widget watchOS).

**v2 — Conseils et vigilance :**

- recommandation de séance détaillée et charge maximale conseillée (à partir de A, C_eff, de la fatigue résiduelle et des profils) ;
- alerte « signes inhabituels » : FC nocturne, VFC, fréquence respiratoire et température comparées à leurs bases, déjà stockées ;
- besoin de sommeil adaptatif ;
- corrélations du journal de facteurs (tags × métriques) ;
- focus de charge et deux charges séparées (cardio et musculaire) ;
- notation des siestes.

**v3 — Écosystème :**

- batterie d'énergie façon Body Battery ;
- import FIT depuis iCloud Drive (HealthFit), comme nouvelle source de données ;
- calendrier d'objectifs et affûtage ;
- Siri et Raccourcis (App Intents) ;
- résumé hebdomadaire ;
- export CSV.

---

## 17. Vérification de bout en bout de la v1

**Ce que je lance :**

1. `swift test` sous Windows : tout est vert.
2. Un `workflow_dispatch` sur `ios.yml`, qui doit être entièrement vert : tests du moteur sous Windows et macOS, `check-no-network`, `xcodebuild test`, captures, IPA avec l'entitlement HealthKit.
3. Relecture de la matrice complète des captures : les 9 scénarios × écrans, en clair et en sombre. Chaque capture doit respecter l'attendu du §10.
4. `readiness-cli` sur les 9 scénarios. On compare au tableau des attendus.
5. Contrôle de la trace : un jour du scénario `normal` recalculé à la main à partir de la trace (contributions, plafonds) correspond au score affiché.

**Ce que tu fais pendant 14 jours consécutifs, sur l'iPhone :**

1. Chaque matin : 1 min de Respirer sur la montre au lit, ouverture de l'app, check-in, lecture du score. Tu chronomètres et tu notes le temps total (critère C1 : < 60 s).
2. Au moins une fois : un matin où tu ouvres l'app juste au réveil, pour vérifier le passage de « Provisoire » à « figé » sans intervention.
3. Au moins une séance sans FC fiable (muscu), une descente ou une sortie de ski si la saison le permet, et un doublon HealthFit résolu.
4. Au moins un check-in passé, puis rempli plus tard : il va au journal et le score figé ne change pas.
5. Si l'occasion se présente, un jour « malade » ou une nuit sans montre, en vérifiant le plafond et la confiance affichés.
6. À J14 :
   - la part des réponses « juste » est relevée dans Debug ;
   - Rapport de confidentialité des apps : **0 domaine** ;
   - Réglages > iCloud > Sauvegardes : les données de l'app ne sont pas sauvegardées ;
   - un export, puis une réinstallation, puis un import restaurent l'historique ;
   - l'app s'est ouverte tous les jours, sans expiration de signature.

La v1 est **acceptée** quand les 6 critères du §1 sont remplis.

---

## Annexe A — Références

- Banister E.W. (1991). *Modeling elite athletic performance*. In MacDougall, Wenger, Green (éd.), *Physiological Testing of the High-Performance Athlete*. Human Kinetics. Pour le TRIMP pondéré exponentiellement.
- Foster C. et al. (2001). *A new approach to monitoring exercise training*. J Strength Cond Res 15(1):109–115. Pour le sRPE.
- Christen J., Foster C., Porcari J.P., Mikat R.P. (2016). *Temporal robustness of the session rating of perceived exertion*. IJSPP 11(8):1088–1093. Le RPE reste valide jusqu'à 24 h après la séance.
- Williams S., West S., Cross M.J., Stokes K.A. (2017). *Better way to determine the acute:chronic workload ratio?* Br J Sports Med 51(3):209–210. Pour l'EWMA.
- Impellizzeri F.M. et al. (2020). *Acute:chronic workload ratio: conceptual issues and fundamental pitfalls*. IJSPP 15(6):907–913. Justifie le plancher et la prudence sur le ratio.
- Plews D.J., Laursen P.B., Kilding A.E., Buchheit M. (2012). *Heart rate variability in elite triathletes, is variation in variability the key to effective training?* Eur J Appl Physiol 112:3729–3741.
- Plews D.J. et al. (2013). *Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring*. Sports Med 43:773–781. Pour la moyenne lnRMSSD sur 7 j et le plus petit changement significatif à 0,5 écart-type.
- Buchheit M. (2014). *Monitoring training status with HR measures: do all roads lead to Rome?* Front Physiol 5:73.
- Task Force of the ESC/NASPE (1996). *Heart rate variability: standards of measurement…* Circulation 93:1043–1065. Définitions du RMSSD et du SDNN.
- McLean B.D. et al. (2010). *Neuromuscular, endocrine, and perceptual fatigue responses during different length between-match microcycles in professional rugby league players*. IJSPP 5(3):367–383. Questionnaire de bien-être en 1–5.
- Hooper S.L., Mackinnon L.T. (1995). *Monitoring overtraining in athletes*. Sports Med 20(5):321–327.
- Saw A.E., Main L.C., Gastin P.B. (2016). *Monitoring the athlete training response: subjective self-reported measures trump commonly used objective measures: a systematic review*. Br J Sports Med 50(5):281–291.
- Tanaka H., Monahan K.D., Seals D.R. (2001). *Age-predicted maximal heart rate revisited*. J Am Coll Cardiol 37(1):153–156.
- Apple (nov. 2024). *Heart Rate, Calorimetry, and Activity on Apple Watch* (livre blanc). Cadence des mesures VFC et stockage des séries battement-à-battement.
- Documentation Apple HealthKit (developer.apple.com/documentation/healthkit), consultée le 19/10/2026 : pages des identifiants cités au §3.
