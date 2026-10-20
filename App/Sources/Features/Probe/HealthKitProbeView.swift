import SwiftUI
import UIKit

struct HealthKitProbeView: View {
    @State private var probe = HealthKitProbe()

    var body: some View {
        List {
            Section("Appareil") {
                row("iOS", UIDevice.current.systemVersion)
                row("Santé disponible", probe.report.healthDataAvailable ? "oui" : "non")
                row("App Group", probe.report.appGroupContainerOK
                    ? "OK" : "KO : identifiant réécrit par l'outil de sideload ?")
            }
            Section("Autorisation") {
                Button("Autoriser Santé") { Task { await probe.requestAuthorization(); await probe.refreshCounts() } }
                if let error = probe.report.authorizationError {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            Section("7 derniers jours") {
                row("Mesures VFC (SDNN)", "\(probe.report.hrvSDNN)")
                row("Séries battement-à-battement", "\(probe.report.heartbeatSeries)")
                row("Nuits avec phases", "\(probe.report.nightsWithStages)")
                row("Tracés de séance", "\(probe.report.routes)")
                row("Efforts de séance", "\(probe.report.effortSamples)")
                Button("Rafraîchir") { Task { await probe.refreshCounts() } }
            }
            Section("Séances par source") {
                if probe.report.workoutsBySource.isEmpty {
                    Text("Aucune séance").foregroundStyle(.secondary)
                }
                ForEach(probe.report.workoutsBySource, id: \.bundleID) { source in
                    row(source.name, "\(source.count)", detail: source.bundleID)
                }
            }
            Section("Test d'écriture du RPE") {
                Button("Écrire un RPE test sur la dernière séance WorkOutDoors") {
                    Task { await probe.runEffortWriteTest() }
                }
                if let outcome = probe.report.effortWrite {
                    Text(Self.text(for: outcome)).font(.footnote)
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text("0 partout ? Autorisation refusée possible : iOS ne permet pas de le savoir. Vérifie Réglages > Santé > Accès aux données.")
            }
        }
        .navigationTitle("Sonde HealthKit")
        .disabled(probe.isRunning)
        .overlay { if probe.isRunning { ProgressView() } }
    }

    private func row(_ label: String, _ value: String, detail: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(label)
                if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private static func text(for outcome: EffortWriteOutcome) -> String {
        switch outcome {
        case .noWorkOutDoorsWorkout:
            "Aucune séance WorkOutDoors sur les 30 derniers jours."
        case let .success(path, readBack, deleted):
            "Écrit (chemin \(path)) · relu : \(readBack ? "oui" : "non") · supprimé : \(deleted ? "oui" : "non")"
        case let .failed(step, code, message):
            "Échec à l'étape « \(step) » (code \(code)) : \(message)"
        }
    }
}
