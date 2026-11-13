// Restes d'apps supprimées : liste à sélection multiple, puis Corbeille ou protection.
import SwiftUI

struct Leftover: Identifiable {
    let kb: Int
    let folder: String
    let name: String
    let path: String
    let toCheck: Bool    // repéré par son seul nom, sans identifiant d'app : à vérifier avant d'effacer
    var id: String { path }
}

struct LeftoversView: View {
    @EnvironmentObject private var state: AppState
    @State private var items: [Leftover] = []
    @State private var selection = Set<String>()
    @State private var loading = false
    @State private var scanned = false
    @State private var output = ""
    @State private var confirmTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(state.t("Analyser")) { Task { await scan() } }
                    .disabled(loading)
                if loading {
                    ProgressView().controlSize(.small)
                    Text(state.t("Analyse en cours...")).foregroundStyle(.secondary)
                }
                Spacer()
                Button(state.t("Protéger")) { Task { await protect() } }
                    .disabled(selection.isEmpty || loading)
                Button(state.t("Mettre à la Corbeille")) { confirmTrash = true }
                    .disabled(selection.isEmpty || loading)
            }
            if !scanned && !loading {
                Text(state.t("Clique sur Analyser pour chercher les restes.")).foregroundStyle(.secondary)
            }
            Table(items, selection: $selection) {
                TableColumn(state.t("Taille")) { Text(formatKB($0.kb)).monospacedDigit() }.width(90)
                TableColumn(state.t("Dossier"), value: \.folder).width(min: 120, ideal: 170)
                TableColumn(state.t("Nom")) { item in
                    Text(item.toCheck ? "\(item.name) \(state.t("(à vérifier)"))" : item.name)
                }
            }
            if !output.isEmpty {
                Text(output).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .navigationTitle(state.t("Restes d'apps supprimées"))
        .confirmationDialog(state.t("Mettre la sélection à la Corbeille ?"), isPresented: $confirmTrash) {
            Button(state.t("Mettre à la Corbeille"), role: .destructive) { Task { await trash() } }
            Button(state.t("Annuler"), role: .cancel) {}
        }
    }

    private func scan() async {
        loading = true
        output = ""
        let result = await Script.run(["list", "orphans"], lang: state.lang)
        items = result.rows.compactMap { row in
            guard row.count == 5, let kb = Int(row[0]) else { return nil }
            return Leftover(kb: kb, folder: row[1], name: row[2], path: row[3], toCheck: row[4] == "1")
        }
        selection = []
        scanned = true
        loading = false
    }

    private func trash() async {
        loading = true
        let paths = Array(selection)
        let result = await Script.run(["trash"] + paths, dryRun: state.dryRun, lang: state.lang)
        output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        // Retire de la liste ce qui a réellement quitté son emplacement
        items.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        selection = []
        loading = false
    }

    private func protect() async {
        loading = true
        var lines: [String] = []
        for path in selection {
            let result = await Script.run(["exclude-add", path], lang: state.lang)
            lines.append(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
            if result.ok { items.removeAll { $0.path == path } }
        }
        output = lines.joined(separator: "\n")
        selection = []
        loading = false
    }
}
