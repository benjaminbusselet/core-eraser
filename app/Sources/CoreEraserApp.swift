// Fenêtre principale : catégories à gauche, écran à droite.
import SwiftUI

@main
struct CoreEraserApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("core-eraser") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 860, minHeight: 520)
                .task { await state.load() }
        }
    }
}

enum Screen: String, CaseIterable, Identifiable {
    case maintenance = "Maintenance"
    case uninstall = "Désinstaller une app et ses fichiers"
    case leftovers = "Restes d'apps supprimées"
    case plugins = "Plug-ins et extensions"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .maintenance: return "wrench.and.screwdriver"
        case .uninstall: return "xmark.app"
        case .leftovers: return "trash.slash"
        case .plugins: return "puzzlepiece.extension"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var screen: Screen? = .maintenance

    var body: some View {
        NavigationSplitView {
            List(Screen.allCases, selection: $screen) { item in
                Label(state.t(item.rawValue), systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            VStack(spacing: 0) {
                if !state.hasFullDiskAccess { FullDiskAccessBanner() }
                switch screen ?? .maintenance {
                case .maintenance: MaintenanceView()
                case .uninstall: UninstallView()
                case .leftovers: LeftoversView()
                case .plugins: PluginsView()
                }
            }
        }
        // Revérifie au retour des Réglages Système
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.checkFullDiskAccess()
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $state.dryRun) { Text(state.t("Simulation (rien n'est modifié)")) }
                    .toggleStyle(.switch)
                    .labelsHidden()
                Text(state.t("Simulation (rien n'est modifié)"))
                    .foregroundStyle(state.dryRun ? .primary : .secondary)
                Picker(state.t("Langue"), selection: Binding(
                    get: { state.lang },
                    set: { value in Task { await state.setLang(value) } })) {
                    Text("English").tag("en")
                    Text("Français").tag("fr")
                }
                .pickerStyle(.menu)
            }
        }
    }
}

/// Bandeau affiché tant que l'accès complet au disque manque.
struct FullDiskAccessBanner: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(state.t("L'accès complet au disque manque : la Corbeille et les conteneurs d'apps ne peuvent pas être analysés."))
            Spacer()
            Button(state.t("Ouvrir les réglages")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(10)
        .background(.yellow.opacity(0.15))
    }
}
