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

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .maintenance: return "wrench.and.screwdriver"
        case .uninstall: return "xmark.app"
        case .leftovers: return "trash.slash"
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
            switch screen ?? .maintenance {
            case .maintenance: MaintenanceView()
            case .uninstall: UninstallView()
            case .leftovers: LeftoversView()
            }
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
