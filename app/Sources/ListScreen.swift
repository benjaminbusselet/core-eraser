// Écran générique : liste fournie par l'API, sélection multiple, actions sur la sélection, résultat à copier.
import SwiftUI
import AppKit

struct ScreenColumn {
    let title: String          // texte français, traduit à l'affichage
    let index: Int             // colonne de la ligne renvoyée par l'API
    var isSize = false         // Ko, affichés en taille lisible
    var width: CGFloat? = nil  // nil : prend la place restante
}

struct ScreenAction {
    let title: String
    let command: String        // commande api, suivie des identifiants des lignes sélectionnées
    var confirm: String? = nil // question posée avant d'agir
    var needsSelection = true  // false : agit sans sélection (ex. brew autoremove)
}

struct ScreenRow: Identifiable {
    let cells: [String]
    let id: String
}

struct ListScreen: View {
    @EnvironmentObject private var state: AppState
    let title: String
    let list: [String]         // ex. ["list", "plugins"]
    let columnCount: Int       // lignes d'un autre format ignorées
    let idColumn: Int          // colonne transmise aux actions (en général le chemin)
    let columns: [ScreenColumn]
    let actions: [ScreenAction]
    @State private var rows: [ScreenRow] = []
    @State private var selection = Set<String>()
    @State private var loading = false
    @State private var output = ""
    @State private var pending: ScreenAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(state.t("Analyser")) { Task { await load() } }
                    .disabled(loading)
                if loading {
                    ProgressView().controlSize(.small)
                    Text(state.t("Analyse en cours...")).foregroundStyle(.secondary)
                }
                Spacer()
                ForEach(actions, id: \.command) { action in
                    Button(state.t(action.title)) {
                        if action.confirm == nil { Task { await run(action) } } else { pending = action }
                    }
                    .disabled((action.needsSelection && selection.isEmpty) || loading)
                }
            }
            // Même retrait que les lignes de la liste
            line(columns.map { state.t($0.title) }).font(.headline).foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            List(rows, selection: $selection) { row in
                line(columns.map { column in
                    let cell = column.index < row.cells.count ? row.cells[column.index] : ""
                    return column.isSize ? formatKB(Int(cell) ?? 0) : cell
                })
            }
            if !output.isEmpty { ResultBox(text: output) }
        }
        .padding()
        .navigationTitle(state.t(title))
        .task(id: state.lang) { await load() }
        .confirmationDialog(state.t(pending?.confirm ?? ""),
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            if let action = pending {
                Button(state.t(action.title), role: .destructive) { Task { await run(action) } }
            }
            Button(state.t("Annuler"), role: .cancel) {}
        }
    }

    /// Une ligne de cellules aux largeurs des colonnes (en-tête et contenu).
    private func line(_ cells: [String]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(zip(columns.indices, cells)), id: \.0) { index, cell in
                let width = columns[index].width
                Text(cell).lineLimit(1).truncationMode(.middle)
                    .monospacedDigit()
                    .frame(width: width, alignment: .leading)
                    .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            }
        }
    }

    private func load() async {
        loading = true
        let result = await Script.run(list, lang: state.lang)
        rows = result.rows.filter { $0.count == columnCount }.map { ScreenRow(cells: $0, id: $0[idColumn]) }
        selection = []
        loading = false
    }

    private func run(_ action: ScreenAction) async {
        loading = true
        let ids = action.needsSelection ? Array(selection) : []
        let result = await Script.run(action.command.split(separator: " ").map(String.init) + ids,
                                      dryRun: state.dryRun, lang: state.lang)
        output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        loading = false
        await load()
    }
}

/// Résultat d'une action, sélectionnable, avec un bouton pour le copier (commandes sudo comprises).
struct ResultBox: View {
    @EnvironmentObject private var state: AppState
    let text: String

    var body: some View {
        HStack(alignment: .top) {
            Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(state.t("Copier")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}

/// Plug-ins et extensions installés, avec leur app d'origine.
struct PluginsView: View {
    var body: some View {
        ListScreen(title: "Plug-ins et extensions", list: ["list", "plugins"], columnCount: 5, idColumn: 4,
                   columns: [ScreenColumn(title: "Taille", index: 0, isSize: true, width: 80),
                             ScreenColumn(title: "Type", index: 1, width: 130),
                             ScreenColumn(title: "Nom", index: 2),
                             ScreenColumn(title: "App d'origine", index: 3, width: 220)],
                   actions: [ScreenAction(title: "Retirer", command: "plugin-remove", confirm: "Retirer la sélection ?")])
    }
}
