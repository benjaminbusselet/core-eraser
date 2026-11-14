# core-eraser

**Un effaceur de restes et de caches pour macOS, en un seul script shell.**
Une alternative légère et lisible aux fonctions de nettoyage d'apps comme Pearcleaner et OnyX.

[English version](README.md)

> État : **0.3.0**, script et app (bêta). Testé sur macOS 27.2.1 (puce Apple). Commence par `--dry-run`.

## Ce qu'il fait

| Catégorie | Commandes |
|---|---|
| Maintenance | `maintenance` : cases à cocher (caches, journaux, DNS, Spotlight, Time Machine), exécution en une fois |
| Applications | `app-uninstall`, `orphans` (restes d'apps supprimées), `updates`, `brew-manage`, `plugins`, `services`, `pkg-manage`, `lipo-app` |
| Nettoyage | `user-clean`, `dev-clean`, `system-clean` |
| Stockage et sauvegarde | `timemachine` (état, exclusions, place de chaque sauvegarde, différences), `spotlight` |
| Réseau | `network` (diagnostic, test DNS, test de débit) |
| Claude Code | `conv-list`, `conv --all`, `claude-cache`, `all` |
| Confidentialité | `zsh-history` |
| Réglages | `exclude`, `sentinel on/off`, `tm-clean on/off`, `lang en/fr` |

`./core-eraser.sh -h` affiche la liste complète.

## La sécurité d'abord

- **Corbeille plutôt que suppression** : les fichiers vont à la Corbeille, d'où tu peux les remettre. Seuls les caches et journaux, que les apps recréent, sont supprimés directement.
- **Rien sans ton choix** : chaque action liste ce qu'elle va toucher et demande confirmation.
- **Ne lance jamais `sudo` lui-même** : les actions qui exigent les droits administrateur affichent la commande exacte à lancer toi-même, avec des chemins protégés.
- **Éléments protégés** : `./core-eraser.sh exclude add <chemin>` met un fichier ou un dossier à l'abri de toutes les commandes.
- **Simulation** : `./core-eraser.sh --dry-run <commande>` montre ce qui se passerait, sans rien modifier.
- **Apps ouvertes** : quand une app concernée est ouverte, core-eraser propose de la fermer (comme Cmd+Q).
- **La détection des restes** s'appuie sur ce qui est vraiment installé (identifiants, extensions, groupes partagés déclarés dans la signature des apps), pas sur des listes fixes.

## Prérequis

- macOS, avec le `bash` 3.2 fourni. Rien à installer.
- Facultatif : [Homebrew](https://brew.sh) (`brew-manage`, `updates`, `dev-clean`), `jq` (`conv-list`).
- Certains dossiers (`~/Library/Containers`, la Corbeille) peuvent exiger l'**accès complet au disque** pour Terminal : Réglages Système > Confidentialité et sécurité > Accès complet au disque.

## Installation

```sh
git clone https://github.com/benjaminbusselet/core-eraser.git
cd core-eraser
./core-eraser.sh lang fr    # interface en français
./core-eraser.sh            # menu au clavier
```

Raccourci facultatif dans `~/.zshrc` : `alias eraser='/chemin/vers/core-eraser/core-eraser.sh'`

### App (bêta, Mac Apple silicon)

- Télécharge `core-eraser-app.zip` sur la page [Releases](https://github.com/benjaminbusselet/core-eraser/releases) et décompresse-le.
- L'app n'est pas notarisée par Apple : au premier lancement, macOS la bloque. Autorise-la dans Réglages Système > Confidentialité et sécurité > « Ouvrir quand même ».
- Donne-lui l'**accès complet au disque** (l'app affiche un bandeau avec un bouton s'il manque).
- Ou construis-la toi-même (Xcode requis) : `./sign-setup.sh` une fois, puis `./build-app.sh`. Avec le certificat local, l'accès complet au disque survit aux recompilations.

## Utilisation

```sh
./core-eraser.sh                      # menu : flèches, Entrée, q pour revenir
./core-eraser.sh orphans              # restes d'apps supprimées
./core-eraser.sh --dry-run user-clean # simulation
```

## Limites connues

- Les commandes qui exigent `sudo` sont affichées, pas lancées : elles ne sont donc pas testées automatiquement.
- `sentinel` (surveillance de la Corbeille) et `tm-clean` ont besoin de l'accès complet au disque : active-les depuis l'app (Réglages), qui le possède. Activés depuis Terminal, ils tournent avec bash, qui ne l'a en général pas.
- `tm-clean` se lance au montage du disque, en même temps que la sauvegarde Time Machine : cette première sauvegarde peut encore contenir les caches.
- `updates` ne compare les versions que des apps Homebrew, Sparkle et App Store ; une version bêta peut être signalée à tort comme en retard.
- `lipo-app` remplace la signature de l'app par une signature locale : mises à jour automatiques et autorisations peuvent en souffrir (un avertissement s'affiche).
- Les commandes Claude Code lisent l'organisation interne de `~/.claude`, vérifiée avec Claude Code 2.1.323. Une autre version peut l'avoir changée (un avertissement s'affiche).
- Les colonnes des tableaux peuvent se décaler légèrement avec les caractères accentués.

## Tests

```sh
tests/run-tests.sh
```

Chaque test tourne dans un dossier perso temporaire, avec de fausses apps et de faux fichiers : ton Mac n'est jamais touché. Les mêmes tests tournent sur GitHub (machine macOS) à chaque envoi.

## Sécurité

Voir [SECURITY.md](SECURITY.md) pour signaler une faille.

## Licence

[MIT](LICENSE). Mac et macOS sont des marques d'Apple Inc., déposées aux États-Unis et dans d'autres pays et régions. Ce projet n'est affilié ni à Apple, ni à Pearcleaner, ni à OnyX.
