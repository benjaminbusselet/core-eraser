// Désinstaller une app : l'app et ses résidus ensemble, une case à cocher par élément.
import SwiftUI

struct InstalledApp: Identifiable, Hashable {
    let path: String
    let kb: Int
    let running: Bool
    var id: String { path }
    var name: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
}

struct AppItem: Identifiable {
    let path: String
    let kb: Int
    var checked: Bool
    var id: String { path }
}

struct UninstallView: View {
    @EnvironmentObject private var state: AppState
    @State private var apps: [InstalledApp] = []
    @State private var selected: InstalledApp?
    @State private var items: [AppItem] = []
    @State private var cask = ""
    @State private var loading = false
    @State private var output = ""
    @State private var confirmTrash = false

    private var checkedKB: Int { items.filter(\.checked).reduce(0) { $0 + $1.kb } }

    var body: some View {
        HSplitView {
            List(apps, selection: $selected) { app in
                HStack {
                    Circle().fill(app.running ? Color.green : Color.clear).frame(width: 7, height: 7)
                    Text(app.name)
                    Spacer()
                    Text(formatKB(app.kb)).monospacedDigit().foregroundStyle(.secondary)
                }
                .tag(app)
            }
            .frame(minWidth: 240, idealWidth: 280)

            VStack(alignment: .leading, spacing: 10) {
                if selected == nil {
                    Text(state.t("Choisis une app dans la liste.")).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    HStack {
                        Button(state.t("Tout cocher")) { setAll(true) }
                        Button(state.t("Tout décocher")) { setAll(false) }
                        if loading { ProgressView().controlSize(.small) }
                        Spacer()
                        Text("\(state.t("Sélection :")) \(formatKB(checkedKB))").monospacedDigit()
                        Button(state.t("Mettre à la Corbeille")) { confirmTrash = true }
                            .disabled(loading || !items.contains { $0.checked })
                    }
                    List($items) { $item in
                        Toggle(isOn: $item.checked) {
                            HStack {
                                Text(item.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(formatKB(item.kb)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    if selected?.running == true {
                        Label(state.t("L'app est ouverte : elle sera fermée avant."), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if !cask.isEmpty {
                        Text(state.t("Installée par Homebrew : lance aussi « brew uninstall --cask %s » ensuite.")
                            .replacingOccurrences(of: "%s", with: cask))
                            .foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if !output.isEmpty {
                        Text(output).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            .padding()
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(state.t("Désinstaller une app et ses fichiers"))
        .task { await loadApps() }
        .onChange(of: selected) { app in Task { await loadItems(app) } }
        .confirmationDialog(state.t("Mettre les éléments cochés à la Corbeille ?"), isPresented: $confirmTrash) {
            Button(state.t("Mettre à la Corbeille"), role: .destructive) { Task { await trash() } }
            Button(state.t("Annuler"), role: .cancel) {}
        }
    }

    private func setAll(_ value: Bool) {
        for index in items.indices { items[index].checked = value }
    }

    private func loadApps() async {
        loading = true
        let result = await Script.run(["list", "apps"], lang: state.lang)
        apps = result.rows.compactMap { row in
            guard row.count == 3 else { return nil }
            return InstalledApp(path: row[2], kb: Int(row[1]) ?? 0, running: row[0] == "1")
        }
        loading = false
    }

    private func loadItems(_ app: InstalledApp?) async {
        items = []
        cask = ""
        output = ""
        guard let app else { return }
        loading = true
        async let files = Script.run(["list", "app-files", app.path], lang: state.lang)
        async let token = Script.run(["cask", app.path], lang: state.lang)
        // L'app elle-même en premier, puis ses fichiers ; tout est coché au départ
        var next = [AppItem(path: app.path, kb: app.kb, checked: true)]
        for row in await files.rows where row.count == 2 {
            next.append(AppItem(path: row[1], kb: Int(row[0]) ?? 0, checked: true))
        }
        // Le choix a pu changer pendant le chargement
        guard selected == app else { return }
        items = next
        cask = (await token).output.trimmingCharacters(in: .whitespacesAndNewlines)
        loading = false
    }

    private func trash() async {
        guard let app = selected else { return }
        loading = true
        var lines: [String] = []
        let paths = items.filter(\.checked).map(\.path)
        // L'app n'est fermée (et la simulation ne ferme rien) que si elle fait partie des éléments cochés
        if app.running && paths.contains(app.path) && !state.dryRun {
            let quit = await Script.run(["quit", app.path], lang: state.lang)
            if !quit.ok {
                output = quit.output.trimmingCharacters(in: .whitespacesAndNewlines)
                loading = false
                return
            }
        }
        let result = await Script.run(["trash"] + paths, dryRun: state.dryRun, lang: state.lang)
        lines.append(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        items.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        output = lines.joined(separator: "\n")
        if !FileManager.default.fileExists(atPath: app.path) {
            let message = output
            await loadApps()
            selected = nil
            output = message
        }
        loading = false
    }
}
