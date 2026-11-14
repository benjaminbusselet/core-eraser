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

/// Time Machine : état et sauvegardes, exclusions, analyse des plus gros dossiers encore sauvegardés.
struct TimeMachineView: View {
    @EnvironmentObject private var state: AppState
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(state.t("État")).tag(0)
                Text(state.t("Exclusions")).tag(1)
                Text(state.t("Analyse")).tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])
            switch tab {
            case 1:
                ListScreen(title: "Time Machine", list: ["list", "tm-exclusions"], columnCount: 3, idColumn: 2,
                           columns: [ScreenColumn(title: "Taille", index: 0, isSize: true, width: 80),
                                     ScreenColumn(title: "Type", index: 1, width: 100),
                                     ScreenColumn(title: "Dossier", index: 2)],
                           actions: [ScreenAction(title: "Retirer l'exclusion", command: "tm-exclude-remove")],
                           pick: ScreenAction(title: "Exclure…", command: "tm-exclude-add"))
            case 2:
                ListScreen(title: "Time Machine", list: ["list", "tm-analysis"], columnCount: 2, idColumn: 1,
                           columns: [ScreenColumn(title: "Taille", index: 0, isSize: true, width: 80),
                                     ScreenColumn(title: "Dossier encore sauvegardé", index: 1)],
                           actions: [ScreenAction(title: "Exclure de Time Machine", command: "tm-exclude-add")])
            default:
                CommandScreen(title: "Time Machine",
                              commands: [CommandButton(title: "Afficher l'état", args: ["text", "tm-status"]),
                                         CommandButton(title: "Lancer une sauvegarde maintenant", args: ["tm-backup"]),
                                         CommandButton(title: "Différences avec la sauvegarde précédente",
                                                       args: ["text", "tm-compare"])])
            }
        }
    }
}

struct LipoView: View {
    var body: some View {
        ListScreen(title: "Retirer la partie Intel d'une app", list: ["list", "lipo-apps"], columnCount: 3, idColumn: 2,
                   columns: [ScreenColumn(title: "Gain", index: 0, isSize: true, width: 90),
                             ScreenColumn(title: "App", index: 1)],
                   actions: [ScreenAction(title: "Retirer la partie Intel", command: "lipo-app",
                                          confirm: "Modifier la sélection ? Une sauvegarde va dans la Corbeille.")],
                   note: ["text", "lipo-warning"])
    }
}

struct SpotlightView: View {
    var body: some View {
        ListScreen(title: "Index Spotlight", list: ["list", "spotlight"], columnCount: 2, idColumn: 0,
                   columns: [ScreenColumn(title: "Disque", index: 0),
                             ScreenColumn(title: "État de l'index", index: 1, width: 220)],
                   actions: [ScreenAction(title: "Reconstruire l'index", command: "spotlight-rebuild")])
    }
}

/// Conversations Claude Code (à traiter avec Claude Code fermé) et caches.
struct ClaudeView: View {
    var body: some View {
        ListScreen(title: "Claude Code", list: ["list", "convs"], columnCount: 5, idColumn: 2,
                   columns: [ScreenColumn(title: "Date", index: 0, width: 140),
                             ScreenColumn(title: "Projet", index: 1, width: 200),
                             ScreenColumn(title: "Résumé", index: 3)],
                   actions: [ScreenAction(title: "Mettre à la Corbeille", command: "conv-trash",
                                          confirm: "Mettre la sélection à la Corbeille ?"),
                             ScreenAction(title: "Vider les caches Claude Code", command: "claude-cache",
                                          confirm: "Vider les caches Claude Code ?", needsSelection: false)],
                   note: ["text", "claude-notice"])
    }
}

struct ZshHistoryView: View {
    var body: some View {
        CommandScreen(title: "Vider l'historique du terminal",
                      commands: [CommandButton(title: "Afficher l'état", args: ["text", "zsh-info"]),
                                 CommandButton(title: "Vider l'historique du terminal", args: ["zsh-history"],
                                               confirm: "Vider l'historique du terminal ?")])
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
                       actions: [ScreenAction(title: "Retirer", command: "exclude-remove")],
                       pick: ScreenAction(title: "Ajouter…", command: "exclude-add"))
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
    let args: [String]           // commande api complète
    var confirm: String? = nil   // question posée avant de lancer
}

/// Écran de commandes : chaque bouton lance une commande de l'API ; la première est lancée à l'ouverture.
struct CommandScreen: View {
    @EnvironmentObject private var state: AppState
    let title: String
    let commands: [CommandButton]
    @State private var output = ""
    @State private var loading = false
    @State private var pending: CommandButton?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ForEach(commands, id: \.title) { command in
                    Button(state.t(command.title)) {
                        if command.confirm == nil { Task { await run(command) } } else { pending = command }
                    }
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
        .confirmationDialog(state.t(pending?.confirm ?? ""),
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            if let command = pending {
                Button(state.t(command.title), role: .destructive) { Task { await run(command) } }
            }
            Button(state.t("Annuler"), role: .cancel) {}
        }
    }

    private func run(_ command: CommandButton) async {
        loading = true
        let result = await Script.run(command.args, dryRun: state.dryRun, lang: state.lang)
        output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        loading = false
    }
}
