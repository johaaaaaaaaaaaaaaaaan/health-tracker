# Étape 0 — Socle, CI et sonde HealthKit : plan d'implémentation

> **Pour les agents :** sous-skill REQUIS : superpowers:subagent-driven-development (recommandé) ou superpowers:executing-plans pour exécuter ce plan tâche par tâche. Les étapes utilisent des cases à cocher (`- [ ]`).

**Objectif :** prouver qu'une app SwiftUI, compilée sans Mac par GitHub Actions et installée par sideload avec un Apple ID gratuit, peut lire HealthKit sur l'iPhone. Mettre en place au passage tout le socle (package moteur testé sous Windows, projet XcodeGen, CI, IPA).

**Architecture :**
- Un package Swift pur `ReadinessEngine` (Foundation seule) qui ne contient pour l'instant que `DayKey`. Il est testé sous Windows et en CI.
- Une app iOS générée par XcodeGen, dont l'écran racine est la sonde HealthKit. Elle compte les données disponibles et teste l'écriture d'un RPE.
- La CI compile, teste et produit une IPA signée ad hoc **avec ses entitlements**, pour que l'outil de sideload demande HealthKit.

**Technologies :** Swift 6.4.1 (Windows), Xcode le plus récent (CI), Swift Testing, SwiftUI, HealthKit, XcodeGen, GitHub Actions, Sideloadly ou SideStore.

**Spec :** `SPEC.md` (§3, §5, §12, §14 étape 0, §15).

## Contraintes globales

- Swift 6, mode de langage 6, concurrence stricte. Tests en Swift Testing (`import Testing`).
- Moteur : Foundation seule (pas de Combine, d'OSLog ni de SwiftUI). Dates calculées avec `Calendar(identifier: .gregorian)` et un fuseau explicite.
- Aucune dépendance tierce à l'exécution.
- Aucun code réseau : `URLSession`, `import Network`, `NWConnection`, `WKWebView` et `URLRequest` sont interdits dans `App/` et `Packages/`.
- Cible de déploiement iOS 26.0, compilée avec le dernier SDK disponible. Les API d'iOS 27 restent derrière `#available`.
- Projet décrit par XcodeGen (`project.yml`). Le `.xcodeproj` n'est jamais versionné.
- Bundle ID configurable `BUNDLE_ID`, par défaut `fr.perso.formedujour`. App Group : `group.<BUNDLE_ID>`.
- Nom affiché « Forme du jour ». Interface en français, identifiants en anglais.
- Dépôt GitHub **public** : code et données fictives uniquement.
- Signature par Apple ID gratuit, **aucune option payante**.
- Branche de travail `etape-0`. Chaque message de commit se termine par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Actions réservées à l'utilisateur ou soumises à son accord explicite :
  - **par l'utilisateur seul** : création du compte GitHub, `gh auth login`, saisie de l'Apple ID dans Sideloadly, validation de l'UAC Windows ;
  - **avec son accord, au moment voulu** : création du dépôt et premier push.

## Points de vigilance

Ce sont les cas que la spec implique sans qu'aucun test ne les couvre directement. Chacun est épinglé dans la tâche indiquée.

1. **Fins de ligne CRLF sur les scripts** commités depuis Windows : bash échoue sur macOS (`$'\r': command not found`). → Tâche 1 (`.gitattributes`) et contrôle `git ls-files --eol` à la tâche 3.
2. **Chemin du dépôt avec des espaces** (`C:\Mes Fichiers\INSA Strasbourg\Cours - …`) : `swift build` ou l'éditeur de liens sous Windows peuvent casser. → Tâche 1, étape de repli `subst`.
3. **IPA sans entitlements embarqués, ou avec des variables `$(…)` non résolues** : l'outil de sideload ne demande pas HealthKit, ou l'App Group, et la sonde affiche « 0 partout », ce qui ressemble à un refus d'autorisation. → Tâche 5 (le script résout les variables et échoue si la clé manque ou si un `$(` subsiste). La tâche 4 affiche aussi l'erreur exacte de `requestAuthorization`.
4. **Identifiant d'App Group réécrit par l'outil de sideload** : l'App Group paraît KO alors que HealthKit fonctionne. → Tâche 4 (diagnostic séparé) et tâche 5 (variante d'IPA `healthkit-only`).
5. **Jour local autour du changement d'heure et des fuseaux** : `DayKey(date:timeZone:)` doit utiliser le fuseau passé en paramètre, pas celui de l'appareil. → Tâche 1 (tests DST et fuseau).

## Fichiers

| Fichier | Rôle |
|---|---|
| `.gitattributes`, `.gitignore` | fins de ligne LF, exclusion de `build/`, `.build/`, `*.xcodeproj`, des fichiers plist et entitlements générés |
| `Packages/ReadinessEngine/Package.swift` | package `ReadinessEngine` (bibliothèque + tests) |
| `Packages/ReadinessEngine/Sources/ReadinessEngine/Core/DayKey.swift` | jour local `YYYY-MM-DD` |
| `Packages/ReadinessEngine/Tests/ReadinessEngineTests/DayKeyTests.swift` | tests de `DayKey` |
| `.github/workflows/engine.yml` | `swift test` sur Windows et macOS |
| `project.yml` | cibles `Readiness` et `ReadinessTests`, Info.plist et entitlements générés |
| `App/ReadinessApp.swift` | `@main` ; racine = sonde |
| `App/Sources/Data/HealthKit/HealthKitTypes.swift` | types lus et écrits par la sonde |
| `App/Sources/Features/Probe/ProbeCounting.swift` | fonctions pures de comptage, testables |
| `App/Sources/Features/Probe/HealthKitProbe.swift` | logique de la sonde (requêtes, test d'écriture) |
| `App/Sources/Features/Probe/HealthKitProbeView.swift` | écran de la sonde |
| `AppTests/InfoPlistTests.swift`, `AppTests/ProbeCountingTests.swift` | tests de l'app (CI) |
| `scripts/check-no-network.sh` | garde-fou anti-réseau |
| `scripts/sim-destination.sh` | choix du simulateur pour `xcodebuild` |
| `scripts/build-ipa.sh`, `scripts/entitlements-healthkit-only.plist` | archive, signature ad hoc avec entitlements, IPA (deux variantes) |
| `.github/workflows/ios.yml` | génération du projet, garde-fou, tests, IPA, artefacts |
| `README.md` | installation de Swift sous Windows, CI, sideload, protocole de l'étape 0 |
| `SPEC.md` (§14 étape 0) | consignation de la décision finale |

---

### Tâche 1 : package moteur et `DayKey`, testés sous Windows

**Fichiers :**
- Créer : `.gitattributes`, `.gitignore`, `Packages/ReadinessEngine/Package.swift`, `Packages/ReadinessEngine/Sources/ReadinessEngine/Core/DayKey.swift`
- Test : `Packages/ReadinessEngine/Tests/ReadinessEngineTests/DayKeyTests.swift`

**Interfaces :**
- Consomme : rien.
- Produit :

```swift
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int, month: Int, day: Int
    public init?(year: Int, month: Int, day: Int)          // nil si la date n'existe pas
    public init?(_ string: String)                         // exactement "YYYY-MM-DD"
    public init(date: Date, timeZone: TimeZone)            // date locale dans ce fuseau
    public var description: String                         // "2026-10-19"
    public func advanced(by days: Int) -> DayKey
    public func range(to end: DayKey) -> [DayKey]          // inclusif ; [] si end < self
    public func startDate(in timeZone: TimeZone) -> Date   // 00:00 locale
}
// Codable = une chaîne "YYYY-MM-DD" (conteneur à valeur unique) ; un décodage invalide lève une erreur.
```

- [ ] **Étape 1 : créer la branche et les fichiers d'hygiène du dépôt**

```bash
git switch -c etape-0
```

- `.gitattributes` : `* text=auto eol=lf` et `*.png binary`.
- `.gitignore` : `.build/`, `build/`, `*.xcodeproj/`, `DerivedData/`, `App/Info.plist`, `App/Readiness.entitlements`, `.DS_Store`, `*.ipa`.

- [ ] **Étape 2 : installer le toolchain Swift sous Windows (l'utilisateur valide l'UAC)**

Suivre swift.org/install/windows :
1. installer Visual Studio 2022 par winget, avec les composants Windows SDK et VC Tools x64 ;
2. `winget install --id Swift.Toolchain -e` ;
3. rouvrir un terminal.

Commande : `swift --version`
Attendu : `Swift version 6.4.1`

- [ ] **Étape 3 : écrire `Package.swift`**

- `// swift-tools-version: 6.0`, nom `ReadinessEngine` ;
- `platforms: [.iOS("26.0"), .macOS("14.0")]` ;
- produit bibliothèque `ReadinessEngine` ;
- cibles `ReadinessEngine` (`Sources/ReadinessEngine`) et `ReadinessEngineTests`.

- [ ] **Étape 4 : écrire les tests qui échouent**

```swift
import Testing
import Foundation
@testable import ReadinessEngine

private let paris = TimeZone(identifier: "Europe/Paris")!
private let utc = TimeZone(identifier: "UTC")!
private func d(_ s: String) -> DayKey { DayKey(s)! }
private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

@Test func formatsAndParsesISODay() {
    #expect(d("2026-10-19").description == "2026-10-19")
    #expect(DayKey(year: 2026, month: 3, day: 5)?.description == "2026-03-05")
}

@Test(arguments: ["2026-02-30", "2026-13-01", "2026-1-05", "26-10-19", "2026/10/19", "", "abcd-ef-gh"])
func rejectsInvalidStrings(_ s: String) { #expect(DayKey(s) == nil) }

@Test func advancesAcrossMonthYearAndLeapDay() {
    #expect(d("2026-12-31").advanced(by: 1) == d("2027-01-01"))
    #expect(d("2028-02-28").advanced(by: 1) == d("2028-02-29"))
    #expect(d("2027-02-28").advanced(by: 1) == d("2027-03-01"))
    #expect(d("2026-10-19").advanced(by: -19) == d("2026-09-30"))
}

@Test func dayFromDateUsesGivenTimeZone() {
    let instant = iso("2026-10-18T22:30:00Z")
    #expect(DayKey(date: instant, timeZone: paris) == d("2026-10-19"))
    #expect(DayKey(date: instant, timeZone: utc) == d("2026-10-18"))
}

@Test func startDateHandlesDSTDay() {
    // 29/03/2026 : passage à l'heure d'été en Europe, la journée dure 23 h.
    let start = d("2026-03-29").startDate(in: paris)
    #expect(start == iso("2026-03-28T23:00:00Z"))
    #expect(d("2026-03-30").startDate(in: paris).timeIntervalSince(start) == 23 * 3600)
}

@Test func rangeIsInclusiveAndEmptyWhenReversed() {
    #expect(d("2026-10-17").range(to: d("2026-10-19")) == [d("2026-10-17"), d("2026-10-18"), d("2026-10-19")])
    #expect(d("2026-10-19").range(to: d("2026-10-17")).isEmpty)
}

@Test func codableRoundTripsAsString() throws {
    let data = try JSONEncoder().encode(d("2026-10-19"))
    #expect(String(decoding: data, as: UTF8.self) == "\"2026-10-19\"")
    #expect(try JSONDecoder().decode(DayKey.self, from: data) == d("2026-10-19"))
    #expect(throws: (any Error).self) { try JSONDecoder().decode(DayKey.self, from: Data("\"2026-02-30\"".utf8)) }
}

@Test func ordersChronologically() {
    #expect(d("2026-09-30") < d("2026-10-01"))
    #expect(d("2026-12-31") < d("2027-01-01"))
}
```

- [ ] **Étape 5 : lancer les tests et vérifier qu'ils échouent**

Commande : `swift test` (dans `Packages/ReadinessEngine`)
Attendu : échec de compilation, « cannot find 'DayKey' in scope ».

Si l'échec vient du chemin avec des espaces (erreur de l'éditeur de liens ou chemin tronqué) plutôt que de l'absence de `DayKey` :
1. `subst S: "C:\Mes Fichiers\INSA Strasbourg\Cours - Marcuzzi Johan - Documents\Perso\Code\App_Sport"` ;
2. relancer depuis `S:\Packages\ReadinessEngine` ;
3. consigner ce repli dans `README.md` à la tâche 6.

- [ ] **Étape 6 : implémenter `DayKey` dans `Core/DayKey.swift`**

- Toutes les conversions passent par un `Calendar(identifier: .gregorian)` dont on fixe `timeZone`.
- `advanced(by:)` calcule à partir de midi UTC du jour, pour ne pas être affecté par le changement d'heure.
- La validation par `init?` refait un aller-retour par `Calendar`, ce qui rejette le 30 février.
- `init?(_:)` exige le motif à 4-2-2 chiffres.

- [ ] **Étape 7 : lancer les tests et vérifier qu'ils passent**

Commande : `swift test`
Attendu : `Test run with 14 tests passed` (8 fonctions, dont 7 cas paramétrés pour `rejectsInvalidStrings`).

- [ ] **Étape 8 : commiter**

```bash
git add .gitattributes .gitignore Packages/ReadinessEngine
git commit -m "Add ReadinessEngine package with DayKey"
```

---

### Tâche 2 : CI du moteur et dépôt GitHub

**Fichiers :**
- Créer : `.github/workflows/engine.yml`

**Interfaces :**
- Consomme : le package de la tâche 1.
- Produit : un workflow `Engine` lancé à chaque push et via `workflow_dispatch`.

- [ ] **Étape 1 : prérequis de l'utilisateur**

1. `winget install --id GitHub.cli -e`, avec son accord ;
2. l'utilisateur crée son compte GitHub s'il n'en a pas, puis lance `gh auth login` ;
3. accord explicite pour `gh repo create forme-du-jour --public --source . --remote origin` (le nom est modifiable).

- [ ] **Étape 2 : écrire `engine.yml`**

- Déclencheurs : `push` sur toutes les branches, et `workflow_dispatch`.
- Matrice `os: [windows-latest, macos-latest]`, `fail-fast: false`, `working-directory: Packages/ReadinessEngine`.
- Étapes :
  1. `actions/checkout@v4` ;
  2. **Windows :** `compnerd/gha-setup-swift`, épinglé sur sa dernière release, avec les entrées de son README pour `6.4.1-RELEASE` ;
  3. **macOS :** `maxim-lobanov/setup-xcode@v1` avec `xcode-version: latest-stable` ;
  4. `swift --version` ;
  5. `swift test`.

- [ ] **Étape 3 : pousser et vérifier**

Commandes : `git add .github/workflows/engine.yml`, `git commit -m "Add engine CI on Windows and macOS"`, `git push -u origin etape-0`, puis `gh run watch`
Attendu : les deux jobs sont verts. Le log Windows affiche `Swift version 6.4.1` et les deux logs affichent les 14 tests réussis.

---

### Tâche 3 : projet XcodeGen, squelette de l'app, garde-fou anti-réseau et tests iOS en CI

**Fichiers :**
- Créer : `project.yml`, `App/ReadinessApp.swift`, `scripts/check-no-network.sh`, `scripts/sim-destination.sh`, `.github/workflows/ios.yml`
- Test : `AppTests/InfoPlistTests.swift`

**Interfaces :**
- Consomme : `ReadinessEngine` (dépendance de package locale).
- Produit :
  - schéma `Readiness`, projet `Readiness.xcodeproj` généré ;
  - `scripts/check-no-network.sh [dossier…]`, avec `App Packages` par défaut. Code de sortie 1 si un motif interdit est trouvé dans un fichier `*.swift` ;
  - `scripts/sim-destination.sh`, qui affiche `platform=iOS Simulator,id=<udid>`. Il prend de préférence un « iPhone 13 » sur le runtime iOS le plus récent, sinon le premier iPhone de ce runtime. Il échoue avec un message s'il n'en trouve aucun.

- [ ] **Étape 1 : écrire `project.yml`**

- `name: Readiness`.
- Réglages globaux : `options.deploymentTarget.iOS: "26.0"`, `SWIFT_VERSION: "6.0"`, `BUNDLE_ID: fr.perso.formedujour`, `APP_GROUP_ID: group.$(BUNDLE_ID)`.
- `packages.ReadinessEngine.path: Packages/ReadinessEngine`.
- **Cible `Readiness`** (`application`, iOS, `sources: [App]`, dépendance au package `ReadinessEngine`) :
  - réglages : `PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID)` et `TARGETED_DEVICE_FAMILY: "1"` ;
  - `info.path: App/Info.plist`, propriétés :

    | Clé | Valeur |
    |---|---|
    | `CFBundleDisplayName` | `Forme du jour` |
    | `CFBundleShortVersionString` | `0.0.1` |
    | `CFBundleVersion` | `1` |
    | `UILaunchScreen` | `{}` |
    | `UISupportedInterfaceOrientations` | `[UIInterfaceOrientationPortrait]` |
    | `AppGroupIdentifier` | `$(APP_GROUP_ID)` |
    | `NSHealthShareUsageDescription` | « Forme du jour lit tes données Santé (VFC, fréquence cardiaque, sommeil, séances) pour calculer ton score du matin. Rien ne quitte ton iPhone. » |
    | `NSHealthUpdateUsageDescription` | « Forme du jour peut enregistrer l'effort ressenti que tu saisis pour une séance. Rien ne quitte ton iPhone. » |

  - `entitlements.path: App/Readiness.entitlements`, propriétés : `com.apple.developer.healthkit: true`, `com.apple.developer.healthkit.access: []`, `com.apple.security.application-groups: [$(APP_GROUP_ID)]`.
- **Cible `ReadinessTests`** : `bundle.unit-test`, iOS, `sources: [AppTests]`, dépendance à `Readiness` (hôte de test).
- **Schéma `Readiness`** : build de `Readiness`, tests de `ReadinessTests`.

- [ ] **Étape 2 : écrire `App/ReadinessApp.swift`**

`@main struct ReadinessApp: App`, dont la scène affiche `NavigationStack { Text("Forme du jour") }`. Cette racine sera remplacée à la tâche 4.

- [ ] **Étape 3 : écrire le test de l'app**

```swift
import Testing
import Foundation

@Test func infoPlistDeclaresHealthUsageAndAppGroup() {
    let info = Bundle.main.infoDictionary ?? [:]
    #expect((info["CFBundleDisplayName"] as? String) == "Forme du jour")
    #expect(((info["NSHealthShareUsageDescription"] as? String) ?? "").isEmpty == false)
    #expect(((info["NSHealthUpdateUsageDescription"] as? String) ?? "").isEmpty == false)
    #expect(((info["AppGroupIdentifier"] as? String) ?? "").hasPrefix("group."))
}
```

- [ ] **Étape 4 : écrire `check-no-network.sh` et le vérifier localement (Git Bash)**

Il fait `grep -REn --include='*.swift' 'URLSession|import Network|NWConnection|WKWebView|URLRequest'` sur les dossiers passés en argument (`App Packages` par défaut). Il affiche `OK : aucun code réseau` et sort avec le code 0 si rien n'est trouvé. Sinon il affiche les lignes fautives et sort avec le code 1.

Commandes :
1. créer, dans le dossier scratchpad, un fichier `bad/X.swift` contenant `let s = URLSession.shared` ;
2. `bash scripts/check-no-network.sh <scratchpad>/bad; echo $?` ;
3. `bash scripts/check-no-network.sh; echo $?`.

Attendu : `1`, puis `OK : aucun code réseau` et `0`.

- [ ] **Étape 5 : écrire `sim-destination.sh` et `ios.yml`**

- `ios.yml` : nom `iOS`, déclencheurs `push` (toutes branches) et `workflow_dispatch`, `runs-on: macos-latest`.
- Étapes :
  1. `actions/checkout@v4` ;
  2. `maxim-lobanov/setup-xcode@v1` (`latest-stable`) ;
  3. `xcodebuild -version` ;
  4. `brew install xcodegen` ;
  5. `xcodegen generate` ;
  6. `bash scripts/check-no-network.sh` ;
  7. `xcodebuild test -project Readiness.xcodeproj -scheme Readiness -destination "$(bash scripts/sim-destination.sh)" CODE_SIGNING_ALLOWED=NO` ;
  8. `actions/upload-artifact@v4` pour `xcresult` (`if: always()`).
- Tous les scripts sont lancés par `bash script`, pour ne pas dépendre du bit exécutable posé sous Windows.

- [ ] **Étape 6 : vérifier les fins de ligne, commiter, pousser, vérifier la CI**

Commande : `git ls-files --eol scripts project.yml`
Attendu : `i/lf` sur chaque ligne.

Commandes : `git add project.yml App AppTests scripts .github/workflows/ios.yml`, `git commit -m "Add XcodeGen app skeleton, no-network guard and iOS CI"`, `git push`, puis `gh run watch`
Attendu :
- le workflow `iOS` est vert ;
- `xcodebuild -version` affiche Xcode 26 ou plus ;
- le log contient `infoPlistDeclaresHealthUsageAndAppGroup` réussi et `OK : aucun code réseau`.

Si Xcode est antérieur à 26 sur `macos-latest`, passer `runs-on` au libellé macOS le plus récent proposé par GitHub, puis relancer.

---

### Tâche 4 : sonde HealthKit

**Fichiers :**
- Créer :
  - `App/Sources/Data/HealthKit/HealthKitTypes.swift`
  - `App/Sources/Features/Probe/ProbeCounting.swift`
  - `App/Sources/Features/Probe/HealthKitProbe.swift`
  - `App/Sources/Features/Probe/HealthKitProbeView.swift`
- Modifier : `App/ReadinessApp.swift`, pour afficher `HealthKitProbeView` à la racine.
- Test : `AppTests/ProbeCountingTests.swift`

**Interfaces :**
- Consomme : `DayKey(date:timeZone:)` (tâche 1).
- Produit :

```swift
enum HealthKitTypes {
    static var probeRead: Set<HKObjectType>   // heartRateVariabilitySDNN, HKSeriesType.heartbeat(), sleepAnalysis,
                                              // workoutType(), HKSeriesType.workoutRoute(), workoutEffortScore,
                                              // estimatedWorkoutEffortScore
    static var probeShare: Set<HKSampleType>  // workoutEffortScore
}
struct ProbeSleepRecord { let end: Date; let hasStage: Bool }          // hasStage = core, deep ou REM
struct ProbeSourceCount: Equatable { let name: String; let bundleID: String; let count: Int }
enum ProbeCounting {
    static func nightsWithStages(_ records: [ProbeSleepRecord], timeZone: TimeZone) -> Int  // DayKey distincts de `end`
    static func workoutsBySource(_ sources: [(bundleID: String, name: String)]) -> [ProbeSourceCount] // nombre ↓ puis nom ↑
    static func isWorkOutDoors(bundleID: String, name: String) -> Bool   // "workoutdoors", insensible à la casse
}
struct ProbeReport {
    var healthDataAvailable: Bool; var appGroupContainerOK: Bool; var authorizationError: String?
    var hrvSDNN: Int; var heartbeatSeries: Int; var nightsWithStages: Int; var routes: Int; var effortSamples: Int
    var workoutsBySource: [ProbeSourceCount]; var effortWrite: EffortWriteOutcome?
}
enum EffortWriteOutcome: Equatable {
    case noWorkOutDoorsWorkout
    case success(path: String, readBack: Bool, deleted: Bool)     // path : "A" (relier directement) ou "B" (enregistrer puis relier)
    case failed(step: String, code: Int, message: String)
}
@MainActor @Observable final class HealthKitProbe {
    private(set) var report: ProbeReport
    private(set) var isRunning: Bool
    func requestAuthorization() async     // remplit authorizationError avec le domaine, le code et le message exacts
    func refreshCounts(days: Int = 7) async
    func runEffortWriteTest() async
}
```

- [ ] **Étape 1 : écrire les tests des fonctions pures, qui doivent échouer**

```swift
import Testing
import Foundation
@testable import Readiness

private let paris = TimeZone(identifier: "Europe/Paris")!
private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

@Test func countsDistinctNightsWithStagesInLocalTime() {
    let records = [
        ProbeSleepRecord(end: iso("2026-10-19T05:10:00Z"), hasStage: true),
        ProbeSleepRecord(end: iso("2026-10-19T05:40:00Z"), hasStage: true),   // même nuit
        ProbeSleepRecord(end: iso("2026-10-18T23:30:00Z"), hasStage: true),   // 01:30 à Paris → 19/10, même nuit
        ProbeSleepRecord(end: iso("2026-10-18T05:00:00Z"), hasStage: false),  // sans phase : ignorée
        ProbeSleepRecord(end: iso("2026-10-17T05:00:00Z"), hasStage: true),
    ]
    #expect(ProbeCounting.nightsWithStages(records, timeZone: paris) == 2)
}

@Test func groupsWorkoutsBySourceSortedByCount() {
    let result = ProbeCounting.workoutsBySource([
        ("com.example.healthfit", "HealthFit"), ("com.example.wod", "WorkOutDoors"),
        ("com.example.wod", "WorkOutDoors"), ("com.apple.health.x", "Exercice"),
    ])
    #expect(result == [
        ProbeSourceCount(name: "WorkOutDoors", bundleID: "com.example.wod", count: 2),
        ProbeSourceCount(name: "Exercice", bundleID: "com.apple.health.x", count: 1),
        ProbeSourceCount(name: "HealthFit", bundleID: "com.example.healthfit", count: 1),
    ])
}

@Test func recognisesWorkOutDoorsByNameOrBundle() {
    #expect(ProbeCounting.isWorkOutDoors(bundleID: "com.x.app", name: "WorkOutDoors"))
    #expect(ProbeCounting.isWorkOutDoors(bundleID: "net.y.WORKOUTDOORS", name: "Autre"))
    #expect(!ProbeCounting.isWorkOutDoors(bundleID: "com.z.healthfit", name: "HealthFit"))
}
```

- [ ] **Étape 2 : implémenter `ProbeCounting.swift` et `HealthKitTypes.swift`**

- [ ] **Étape 3 : implémenter `HealthKitProbe.swift`**

Comptages (sur `days` jours, avec `HKSampleQueryDescriptor` et un prédicat de dates) :

| Compteur | Requête |
|---|---|
| `hrvSDNN` | échantillons `heartRateVariabilitySDNN` |
| `heartbeatSeries` | échantillons `HKSeriesType.heartbeat()` |
| `nightsWithStages` | `sleepAnalysis` → `ProbeSleepRecord`, fuseau du sample (`HKMetadataKeyTimeZone`) ou fuseau courant |
| `routes` | échantillons `workoutRoute` |
| `effortSamples` | échantillons `workoutEffortScore` |
| `workoutsBySource` | séances → `(sourceRevision.source.bundleIdentifier, .name)` |

`appGroupContainerOK` = `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)` non nil, avec l'identifiant lu dans `Info.plist` (`AppGroupIdentifier`).

`runEffortWriteTest()`, dans cet ordre :
1. Dernière séance des 30 derniers jours qui vérifie `isWorkOutDoors`. S'il n'y en a pas, `.noWorkOutDoorsWorkout`.
2. Créer un `HKQuantitySample` `workoutEffortScore` de valeur `5` en `.appleEffortScore()`, avec le début et la fin de la séance, et la métadonnée `"FormeDuJourProbe": "1"`.
3. **Chemin A :** `relateWorkoutEffortSample(sample, with: workout, activity: nil)` sans enregistrement préalable. En cas d'erreur, **chemin B :** `save(sample)` puis `relate`. En cas de nouvel échec, `.failed(step:code:message:)` avec l'erreur de B.
4. Relecture : `HKSampleQueryDescriptor` sur `workoutEffortScore` avec `HKQuery.predicateForWorkoutEffortSamplesRelated(workout:activity: nil)`. `readBack` = l'UUID créé est présent.
5. Suppression : `delete(sample)` sur **l'instance créée à l'étape 2 uniquement**. Jamais de requête de suppression par prédicat, pour ne pas toucher aux RPE réels de l'utilisateur.

Les noms d'API sont ceux de la doc iOS 18 (§3 de la spec). Si le SDK diffère, on ajuste pour que ça compile, sans changer la séquence.

- [ ] **Étape 4 : implémenter `HealthKitProbeView.swift` et brancher la racine**

Une `List` avec ces sections, textes en français :
- **Appareil :** version d'iOS, `isHealthDataAvailable`, App Group OK ou KO (« KO : identifiant réécrit par l'outil de sideload ? »).
- **Autorisation :** bouton « Autoriser Santé », erreur exacte si présente.
- **7 derniers jours :** les 5 compteurs.
- **Séances par source.**
- **Test d'écriture du RPE :** bouton, puis résultat lisible (chemin, relecture, suppression, ou étape et code d'erreur).

En pied de liste : « 0 partout ? Autorisation refusée possible : iOS ne permet pas de le savoir. Vérifie Réglages > Santé > Accès aux données. »

- [ ] **Étape 5 : vérifier en CI**

Commandes : `git add App AppTests`, `git commit -m "Add HealthKit probe screen"`, `git push`, puis `gh run watch`
Attendu : workflow `iOS` vert, avec les 4 tests de `ReadinessTests` réussis (le test de la tâche 3 + les 3 nouveaux) et `OK : aucun code réseau`.

---

### Tâche 5 : IPA signée ad hoc avec ses entitlements

**Fichiers :**
- Créer : `scripts/build-ipa.sh`, `scripts/entitlements-healthkit-only.plist`
- Modifier : `.github/workflows/ios.yml`, pour ajouter la construction et l'envoi des IPA.

**Interfaces :**
- Consomme : le projet généré (tâche 3) et `App/Readiness.entitlements`, généré par XcodeGen.
- Produit : `bash scripts/build-ipa.sh <entitlements.plist> <sortie.ipa>`. Le script sort avec un code non nul si l'app signée ne contient pas `com.apple.developer.healthkit`. Artefacts de CI : `Readiness.ipa` (HealthKit + App Group) et `Readiness-healthkit-only.ipa`.

- [ ] **Étape 1 : écrire `entitlements-healthkit-only.plist`**

Il contient seulement `com.apple.developer.healthkit = true` et `com.apple.developer.healthkit.access = []`.

- [ ] **Étape 2 : écrire `build-ipa.sh`**

1. `xcodebuild archive -project Readiness.xcodeproj -scheme Readiness -configuration Release -destination 'generic/platform=iOS' -archivePath build/Readiness.xcarchive CODE_SIGNING_ALLOWED=NO`, seulement si l'archive n'existe pas encore ;
2. copier `Readiness.app` dans `build/stage-<nom>/Payload/` ;
3. préparer une copie résolue des entitlements :
   - remplacer chaque `$(NOM)` de `$1` par la valeur que donne `xcodebuild -showBuildSettings -scheme Readiness -configuration Release` (un `sed` vers un fichier temporaire). XcodeGen y laisse en effet `$(APP_GROUP_ID)` littéral, et `codesign` appelé à la main ne le résout pas ;
   - échouer avec un message si un `$(` subsiste ;
4. `codesign --force --sign - --timestamp=none --entitlements <copie résolue>` sur cette copie de l'app (et sur `Frameworks/*` d'abord, s'il y en a) ;
5. `codesign -d --entitlements :- <app>`, puis `grep -q com.apple.developer.healthkit`, sinon échec avec le message « entitlement HealthKit absent ». Vérifier aussi qu'aucun `$(` n'apparaît dans cette sortie ;
6. zip de `Payload` vers `$2`.

- [ ] **Étape 3 : compléter `ios.yml`**

Après les tests :
1. `bash scripts/build-ipa.sh App/Readiness.entitlements build/Readiness.ipa` ;
2. `bash scripts/build-ipa.sh scripts/entitlements-healthkit-only.plist build/Readiness-healthkit-only.ipa` ;
3. `actions/upload-artifact@v4`, artefact `ipa` contenant les deux fichiers.

- [ ] **Étape 4 : vérifier**

Commandes : `git add scripts .github/workflows/ios.yml`, `git commit -m "Build ad-hoc signed IPAs with HealthKit entitlements"`, `git push`, `gh run watch`, puis `gh run download <id> -n ipa -D build/ipa`
Attendu :
- workflow vert ;
- le log de chaque appel à `build-ipa.sh` montre les entitlements avec `com.apple.developer.healthkit` ;
- `build/ipa/` contient les deux `.ipa`, de taille non nulle.

---

### Tâche 6 : guide d'installation, essai sur l'iPhone et décision

**Fichiers :**
- Créer : `README.md`
- Modifier : `SPEC.md`, §14, étape 0. Ajouter une ligne « Résultat (date) » sous le tableau de décision.

**Interfaces :**
- Consomme : les artefacts `ipa` (tâche 5) et la sonde (tâche 4).
- Produit : la décision qui conditionne l'étape 1, selon le tableau de la spec : HealthKit OK, ou essai SideStore, ou plan B, et RPE écrit dans Santé ou gardé en local.

- [ ] **Étape 1 : écrire `README.md`**

Sections :
1. Ce que contient le dépôt (renvoi vers `SPEC.md`) ;
2. Tests du moteur sous Windows : installation de la tâche 1, étape 2, `swift test`, repli `subst` si l'étape 5 de la tâche 1 l'a rendu nécessaire ;
3. CI : workflows, où trouver les artefacts, `gh run download` ;
4. Installation sur l'iPhone :
   - activer le mode développeur ;
   - Sideloadly : choisir `Readiness.ipa`, saisir son Apple ID (fait par l'utilisateur) ;
   - faire confiance au profil (Réglages > Général > VPN et gestion de l'appareil) ;
   - activer le rafraîchissement automatique en Wi-Fi (le PC doit être allumé et sur le même réseau au moins une fois tous les 7 jours) ;
5. Dépannage :
   - si l'installation échoue, réessayer avec `Readiness-healthkit-only.ipa` ;
   - si HealthKit est KO avec Sideloadly, essayer SideStore ;
   - limites du compte gratuit (3 apps, 10 App ID par 7 jours) ;
6. Protocole de vérification de l'étape 0 (§14 de la spec).

- [ ] **Étape 2 : commiter le README**

```bash
git add README.md
git commit -m "Add install and step 0 verification guide"
git push
```

- [ ] **Étape 3 : essai sur l'iPhone (par l'utilisateur, en suivant le README)**

À relever :
- l'installation a-t-elle réussi, et avec quelle IPA ;
- la feuille d'autorisation Santé est-elle apparue ;
- les 5 compteurs et les séances par source, comparés à l'app Santé ;
- App Group OK ou KO ;
- le résultat exact du test d'écriture du RPE.

- [ ] **Étape 4 : consigner la décision dans `SPEC.md` et commiter**

Ajouter sous le tableau de décision de l'étape 0 :
- `Résultat (JJ/MM/AAAA) : …`, avec les relevés de l'étape 3 ;
- la ligne retenue dans le tableau de décision.

```bash
git add SPEC.md
git commit -m "Record step 0 sideload and HealthKit outcome"
git push
```

- [ ] **Étape 5 : contrôle à J+8 (par l'utilisateur)**

L'app s'ouvre toujours, ce qui prouve que le rafraîchissement automatique fonctionne. Si ce n'est pas le cas, on l'ajoute au résultat dans `SPEC.md` et on passe à SideStore.
