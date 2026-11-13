// Maintenance : interrupteurs, bouton Exécuter, et commandes sudo à copier.
import SwiftUI
import AppKit

struct MaintenanceTask: Identifiable {
    enum Kind { case user, dev }
    let kind: Kind
    let key: String      // indice (user-clean) ou nom de l'outil (dev-clean)
    let label: String
    let kb: Int
    var isOn: Bool
    var id: String { "\(kind)-\(key)" }
}

struct SudoCommand: Identifiable {
    let label: String
    let kb: Int
    let command: String
    var id: String { command }
}

struct MaintenanceView: View {
    @EnvironmentObject private var state: AppState
    @State private var tasks: [MaintenanceTask] = []
    @State private var sudoCommands: [SudoCommand] = []
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
                                Text(task.label)
                                Spacer()
                                Text(formatKB(task.kb)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                }
                Section(state.t("Commandes à lancer toi-même dans Terminal (droits administrateur) :")) {
                    ForEach(sudoCommands) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(item.label)  ·  \(formatKB(item.kb))")
                                Text(item.command).font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Spacer()
                            Button(state.t("Copier")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.command, forType: .string)
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

    private func reload() async {
        loading = true
        let lang = state.lang
        async let user = Script.run(["list", "user-clean"], lang: lang)
        async let dev = Script.run(["list", "dev-caches"], lang: lang)
        // Chaque partie s'affiche dès qu'elle est prête, la plus rapide d'abord
        sudoCommands = (await Script.run(["list", "system-clean"], lang: lang)).rows.compactMap { row in
            row.count == 4 ? SudoCommand(label: row[2], kb: Int(row[1]) ?? 0, command: row[3]) : nil
        }
        let devTasks = (await dev).rows.filter { $0.count == 3 }.map { row in
            MaintenanceTask(kind: .dev, key: row[1], label: row[1], kb: Int(row[0]) ?? 0, isOn: false)
        }
        tasks = devTasks
        // Par défaut : caches des navigateurs et journaux, pas « tous les caches »
        let userTasks = (await user).rows.filter { $0.count == 3 }.map { row in
            MaintenanceTask(kind: .user, key: row[0], label: row[2], kb: Int(row[1]) ?? 0, isOn: row[0] != "1")
        }
        tasks = userTasks + devTasks
        loading = false
    }

    private func run() async {
        loading = true
        var lines: [String] = []
        let user = tasks.filter { $0.isOn && $0.kind == .user }.map(\.key)
        let dev = tasks.filter { $0.isOn && $0.kind == .dev }.map(\.key)
        if !user.isEmpty {
            lines.append((await Script.run(["user-clean"] + user, dryRun: state.dryRun, lang: state.lang)).output)
        }
        if !dev.isEmpty {
            lines.append((await Script.run(["dev-clean"] + dev, dryRun: state.dryRun, lang: state.lang)).output)
        }
        await reload()
        let text = lines.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        output = text.isEmpty ? "OK" : text
        loading = false
    }
}
