// Écrans bâtis sur ListScreen (listes) et CommandScreen (commandes à résultat texte).
import SwiftUI

struct ServicesView: View {
    var body: some View {
        ListScreen(title: "Services au démarrage", list: ["list", "services"], columnCount: 5, idColumn: 4,
                   columns: [ScreenColumn(title: "Service", index: 0),
                             ScreenColumn(title: "Programme", index: 1, width: 150),
                             ScreenColumn(title: "État", index: 2, width: 110),
                             ScreenColumn(title: "App d'origine", index: 3, width: 220)],
                   actions: [ScreenAction(title: "Retirer", command: "service-remove", confirm: "Retirer la sélection ?")])
    }
}

struct PackagesView: View {
    var body: some View {
        ListScreen(title: "Traces d'installations .pkg", list: ["list", "pkgs"], columnCount: 6, idColumn: 0,
                   columns: [ScreenColumn(title: "Paquet", index: 0),
                             ScreenColumn(title: "Version", index: 1, width: 90),
                             ScreenColumn(title: "Installé", index: 2, width: 100),
                             ScreenColumn(title: "Fichiers", index: 3, width: 80),
                             ScreenColumn(title: "État", index: 4, width: 220)],
                   actions: [ScreenAction(title: "Effacer la trace", command: "pkg-forget")])
    }
}

struct UpdatesView: View {
    var body: some View {
        ListScreen(title: "Mises à jour des apps", list: ["list", "updates"], columnCount: 5, idColumn: 0,
                   columns: [ScreenColumn(title: "App", index: 0),
                             ScreenColumn(title: "Installée", index: 1, width: 110),
                             ScreenColumn(title: "Disponible", index: 2, width: 110),
                             ScreenColumn(title: "Mise à jour par", index: 3, width: 280)],
                   actions: [ScreenAction(title: "Mettre à jour avec Homebrew", command: "brew-upgrade",
                                          confirm: "Mettre à jour la sélection ?")])
    }
}

struct BrewView: View {
    var body: some View {
        ListScreen(title: "Paquets et apps Homebrew", list: ["list", "brew"], columnCount: 4, idColumn: 2,
                   columns: [ScreenColumn(title: "Taille", index: 0, isSize: true, width: 80),
                             ScreenColumn(title: "Type", index: 1, width: 90),
                             ScreenColumn(title: "Nom", index: 2),
                             ScreenColumn(title: "État", index: 3, width: 200)],
                   actions: [ScreenAction(title: "Désinstaller", command: "brew-uninstall",
                                          confirm: "Désinstaller la sélection ?"),
                             ScreenAction(title: "Retirer les dépendances inutiles", command: "brew-autoremove",
                                          confirm: "Retirer les dépendances devenues inutiles ?", needsSelection: false)])
    }
}

struct TimeMachineView: View {
    var body: some View {
        CommandScreen(title: "Time Machine",
                      commands: [CommandButton(title: "Afficher l'état", args: ["text", "tm-status"]),
                                 CommandButton(title: "Lancer une sauvegarde maintenant", args: ["tm-backup"])])
    }
}

struct NetworkView: View {
    var body: some View {
        CommandScreen(title: "Diagnostic et tests réseau",
                      commands: [CommandButton(title: "Diagnostic", args: ["text", "network-diag"]),
                                 CommandButton(title: "Test DNS (apple.com)", args: ["text", "dns-test"]),
                                 CommandButton(title: "Test de débit (environ 20 s)", args: ["text", "speed-test"]),
                                 CommandButton(title: "Vider le cache DNS", args: ["text", "dns-flush"])])
    }
}

/// Réglages : surveillance de la Corbeille, puis éléments protégés (retirables).
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var sentinel = false
    @State private var tmClean = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(state.t("Surveiller la Corbeille (fichiers laissés par les apps qu'on y jette)"), isOn: Binding(
                get: { sentinel },
                set: { value in Task { await setAgent("sentinel", value) } }))
                .toggleStyle(.switch)
                .padding([.horizontal, .top])
            Toggle(state.t("Vider caches des navigateurs fermés et journaux au branchement du disque Time Machine"),
                   isOn: Binding(get: { tmClean }, set: { value in Task { await setAgent("tm-clean", value) } }))
                .toggleStyle(.switch)
                .padding([.horizontal, .top])
            ListScreen(title: "Réglages de core-eraser", list: ["list", "excludes"], columnCount: 1, idColumn: 0,
                       columns: [ScreenColumn(title: "Éléments protégés", index: 0)],
                       actions: [ScreenAction(title: "Retirer", command: "exclude-remove")])
        }
        .task { await loadAgents() }
    }

    private func isOn(_ agent: String) async -> Bool {
        let result = await Script.run([agent, "status"], lang: state.lang)
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    private func loadAgents() async {
        sentinel = await isOn("sentinel")
        tmClean = await isOn("tm-clean")
    }

    private func setAgent(_ agent: String, _ on: Bool) async {
        _ = await Script.run([agent, on ? "on" : "off"], lang: state.lang)
        await loadAgents()
    }
}

struct CommandButton {
    let title: String
    let args: [String]     // commande api complète
}

/// Écran de commandes : chaque bouton lance une commande de l'API ; la première est lancée à l'ouverture.
struct CommandScreen: View {
    @EnvironmentObject private var state: AppState
    let title: String
    let commands: [CommandButton]
    @State private var output = ""
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ForEach(commands, id: \.title) { command in
                    Button(state.t(command.title)) { Task { await run(command) } }
                        .disabled(loading)
                }
                if loading { ProgressView().controlSize(.small) }
                Spacer()
            }
            ScrollView {
                if !output.isEmpty { ResultBox(text: output) }
            }
        }
        .padding()
        .navigationTitle(state.t(title))
        .task(id: state.lang) { if let first = commands.first { await run(first) } }
    }

    private func run(_ command: CommandButton) async {
        loading = true
        let result = await Script.run(command.args, dryRun: state.dryRun, lang: state.lang)
        output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        loading = false
    }
}
