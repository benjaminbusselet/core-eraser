// Maintenance : interrupteurs par catégorie, détail à cocher par élément ; le système demande les droits administrateur.
import SwiftUI
import AppKit

struct MaintenanceTask: Identifiable {
    enum Kind { case user, dev, npx, system }
    let kind: Kind
    let key: String      // indice (user-clean, system-clean), nom de l'outil (dev-clean) ou dossier (outil npx)
    let label: String
    let kb: Int
    var isOn: Bool
    var expanded = false
    var items: [AppItem]?    // détail chargé à la demande ; nil tant qu'il n'a pas été ouvert
    var busy = false         // outil npx en cours d'utilisation : impossible à cocher
    var id: String { "\(kind)-\(key)" }
}

struct MaintenanceView: View {
    @EnvironmentObject private var state: AppState
    @State private var tasks: [MaintenanceTask] = []
    @State private var loading = false
    @State private var output = ""
    @State private var confirmRun = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Form {
                Section {
                    ForEach($tasks) { $task in
                        Toggle(isOn: $task.isOn) {
                            HStack {
                                Text(task.busy ? "\(task.label)  (\(state.t("en cours d'utilisation")))" : task.label)
                                Spacer()
                                Text(formatKB(selectedKB(task))).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(task.busy)
                        // Le détail par élément n'existe que pour les caches et journaux du dossier perso
                        if task.kind == .user {
                            DisclosureGroup(state.t("Détail"), isExpanded: $task.expanded) {
                                if let items = task.items {
                                    ItemChecklist(items: Binding(get: { items }, set: { task.items = $0 }))
                                } else {
                                    ProgressView().controlSize(.small)
                                }
                            }
                            .onChange(of: task.expanded) { open in
                                if open && task.items == nil { Task { await loadItems(task.id) } }
                            }
                        }
                    }
                }
                if !output.isEmpty {
                    Section(state.t("Résultat")) {
                        Text(output).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if loading { ProgressView().controlSize(.small) }
                Spacer()
                Button(state.t("Exécuter")) { confirmRun = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(loading || !tasks.contains { $0.isOn })
            }
            .padding([.horizontal, .bottom])
        }
        .navigationTitle(state.t("Maintenance"))
        .task(id: state.lang) { await reload() }
        .confirmationDialog(state.t("Exécuter les opérations cochées ?"), isPresented: $confirmRun) {
            Button(state.t("Exécuter")) { Task { await run() } }
            Button(state.t("Annuler"), role: .cancel) {}
        }
    }

    /// Taille retenue : celle des éléments cochés si le détail est ouvert, sinon celle de la catégorie.
    private func selectedKB(_ task: MaintenanceTask) -> Int {
        guard let items = task.items else { return task.kb }
        return items.filter(\.checked).reduce(0) { $0 + $1.kb }
    }

    private func loadItems(_ id: String) async {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let result = await Script.run(["list", "user-clean-items", task.key], lang: state.lang)
        let items = result.rows.compactMap { row in
            row.count == 2 ? AppItem(path: row[1], kb: Int(row[0]) ?? 0, checked: true) : nil
        }
        if let index = tasks.firstIndex(where: { $0.id == id }) { tasks[index].items = items }
    }

    private func reload() async {
        loading = true
        let lang = state.lang
        async let user = Script.run(["list", "user-clean"], lang: lang)
        async let dev = Script.run(["list", "dev-caches"], lang: lang)
        async let npx = Script.run(["list", "npx-tools"], lang: lang)
        // Chaque partie s'affiche dès qu'elle est prête, la plus rapide d'abord
        // Le système demande les droits administrateur (mot de passe ou empreinte) au moment d'exécuter
        let systemTasks = (await Script.run(["list", "system-clean"], lang: lang)).rows.filter { $0.count == 3 }.map { row in
            MaintenanceTask(kind: .system, key: row[0], label: row[2], kb: Int(row[1]) ?? 0, isOn: false)
        }
        let devTasks = (await dev).rows.filter { $0.count == 3 }.map { row in
            MaintenanceTask(kind: .dev, key: row[1], label: row[1], kb: Int(row[0]) ?? 0, isOn: false)
        }
        tasks = devTasks
        // Par défaut : caches des navigateurs et journaux, pas « tous les caches »
        let userTasks = (await user).rows.filter { $0.count == 3 }.map { row in
            MaintenanceTask(kind: .user, key: row[0], label: row[2], kb: Int(row[1]) ?? 0, isOn: row[0] != "1")
        }
        let npxTasks = (await npx).rows.filter { $0.count == 5 }.map { row in
            MaintenanceTask(kind: .npx, key: row[4], label: "npx · \(row[1]) · \(row[2])",
                            kb: Int(row[0]) ?? 0, isOn: false, busy: row[3] == "1")
        }
        tasks = userTasks + devTasks + npxTasks + systemTasks
        loading = false
    }

    private func run() async {
        loading = true
        var lines: [String] = []
        let lang = state.lang
        let dryRun = state.dryRun
        // Catégories dont le détail n'a pas été ouvert : vidées en entier
        let whole = tasks.filter { $0.isOn && $0.kind == .user && $0.items == nil }.map(\.key)
        if !whole.isEmpty {
            lines.append((await Script.run(["user-clean"] + whole, dryRun: dryRun, lang: lang)).output)
        }
        // Catégories détaillées : seulement les éléments cochés
        let picked = tasks.filter { $0.isOn && $0.kind == .user }
            .flatMap { ($0.items ?? []).filter(\.checked).map(\.path) }
        if !picked.isEmpty {
            lines.append((await Script.run(["clear"] + picked, dryRun: dryRun, lang: lang)).output)
        }
        let dev = tasks.filter { $0.isOn && $0.kind == .dev }.map(\.key)
        if !dev.isEmpty {
            lines.append((await Script.run(["dev-clean"] + dev, dryRun: dryRun, lang: lang)).output)
        }
        let npx = tasks.filter { $0.isOn && $0.kind == .npx && !$0.busy }.map(\.key)
        if !npx.isEmpty {
            lines.append((await Script.run(["npx-remove"] + npx, dryRun: dryRun, lang: lang)).output)
        }
        let system = tasks.filter { $0.isOn && $0.kind == .system }.map(\.key)
        if !system.isEmpty {
            lines.append((await Script.run(["system-clean-run"] + system, dryRun: dryRun, lang: lang)).output)
        }
        await reload()
        let text = lines.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        output = text.isEmpty ? "OK" : text
        loading = false
    }
}

/// Liste d'éléments à cocher, avec « tout cocher / tout décocher » ; défile au-delà d'une certaine hauteur.
struct ItemChecklist: View {
    @EnvironmentObject private var state: AppState
    @Binding var items: [AppItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(state.t("Tout cocher")) { setAll(true) }
                Button(state.t("Tout décocher")) { setAll(false) }
            }
            .controlSize(.small)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach($items) { $item in
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
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func setAll(_ value: Bool) {
        for index in items.indices { items[index].checked = value }
    }
}
