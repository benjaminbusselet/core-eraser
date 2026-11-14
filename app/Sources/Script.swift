// Pont entre l'app et le script : l'app n'agit jamais elle-même, elle appelle « core-eraser.sh api … ».
import Foundation
import SwiftUI

enum Script {
    /// Le script est rangé dans l'app (Contents/Resources).
    static let url: URL = Bundle.main.url(forResource: "core-eraser", withExtension: "sh")
        ?? URL(fileURLWithPath: "core-eraser.sh")

    struct Result {
        let status: Int32
        let output: String
        var ok: Bool { status == 0 }
        /// Lignes découpées en colonnes (séparateur : tabulation).
        var rows: [[String]] {
            output.split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.components(separatedBy: "\t") }
        }
    }

    /// Lance « core-eraser.sh [--dry-run] api <args> » sans bloquer l'interface.
    static func run(_ args: [String], dryRun: Bool = false, lang: String = "en") async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [url.path] + (dryRun ? ["--dry-run"] : []) + ["api"] + args
                var env = ProcessInfo.processInfo.environment
                env["TOOLS_LANG"] = lang
                // Une app ne reçoit pas le PATH du terminal : sans cela, Homebrew et npm seraient introuvables
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
                process.environment = env
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Result(status: -1, output: "\(error.localizedDescription)"))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: Result(status: process.terminationStatus,
                                                      output: String(data: data, encoding: .utf8) ?? ""))
            }
        }
    }
}

/// État partagé : langue, simulation, traductions (fournies par le catalogue du script).
@MainActor
final class AppState: ObservableObject {
    @Published var lang = "en"
    @Published var dryRun = false
    @Published private var table: [String: String] = [:]

    /// Textes de l'app, écrits en français comme dans le script.
    static let keys = [
        "Maintenance", "Restes d'apps supprimées", "Analyser", "Mettre à la Corbeille", "Protéger",
        "Simulation (rien n'est modifié)", "Exécuter", "Copier", "Résultat", "Langue", "Taille", "Dossier", "Nom",
        "Analyse en cours...", "(à vérifier)",
        "Désinstaller une app et ses fichiers", "Choisis une app dans la liste.", "Tout cocher", "Tout décocher",
        "Sélection :", "Mettre les éléments cochés à la Corbeille ?", "L'app est ouverte : elle sera fermée avant.",
        "Élément", "Installée par Homebrew : lance aussi « brew uninstall --cask %s » ensuite.", "Clique sur Analyser pour chercher les restes.",
        "Mettre la sélection à la Corbeille ?", "Exécuter les opérations cochées ?", "Annuler",
        "Commandes à lancer toi-même dans Terminal (droits administrateur) :",
    ]

    /// Traduit un texte français ; sans traduction connue, le texte est gardé tel quel.
    func t(_ french: String) -> String { table[french] ?? french }

    func load() async {
        let current = await Script.run(["lang"])
        let value = current.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "fr" || value == "en" { lang = value }
        await loadTranslations()
    }

    func setLang(_ value: String) async {
        // « lang » est une commande ordinaire du script : elle mémorise le choix pour le script et l'app
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Script.url.path, "lang", value]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        lang = value
        await loadTranslations()
    }

    private func loadTranslations() async {
        let result = await Script.run(["tr"] + Self.keys, lang: lang)
        let lines = result.output.components(separatedBy: "\n")
        var next: [String: String] = [:]
        for (index, key) in Self.keys.enumerated() where index < lines.count {
            next[key] = lines[index]
        }
        table = next
    }
}

/// Taille lisible à partir d'un nombre de Ko.
func formatKB(_ kb: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(kb) * 1024, countStyle: .file)
}
