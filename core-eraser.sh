#!/bin/bash
# core-eraser : entretien d'un Mac en ligne de commande. Sans argument : menu au clavier.
#
# Maintenance
#   maintenance       : cases à cocher (caches, journaux, DNS, Spotlight, Time Machine), exécution en une fois
# Applications
#   app-uninstall     : choix d'une app, puis mise à la Corbeille de l'app et de ses fichiers
#   orphans           : restes d'apps supprimées, puis choix de les mettre à la Corbeille ou de les protéger
#   updates           : versions des apps et mode de mise à jour, mise à jour Homebrew (internet pour Sparkle)
#   brew-manage       : paquets et apps Homebrew (taille, mises à jour), désinstallation, dépendances inutiles
#   plugins           : plug-ins et extensions installés (app d'origine présente ou non), puis retrait
#   services          : services lancés au démarrage (programme, état, app d'origine), arrêt et retrait
#   pkg-manage        : traces d'installations .pkg, fichiers restants, commande pour effacer une trace
#   lipo-app          : retire la partie Intel d'une app (sauvegarde, signature locale, avertissement)
# Nettoyage
#   user-clean        : caches des navigateurs, caches et journaux de ton dossier perso
#   dev-clean         : caches des outils de développement installés (npm, pip, Homebrew, Xcode)
#   system-clean      : caches et journaux système (tailles), commandes sudo pour les vider
# Stockage et sauvegarde
#   timemachine       : état, exclusions, analyse, sauvegarde, place de chaque sauvegarde, différences
#   spotlight         : état de l'index Spotlight, commande sudo pour le reconstruire
# Réseau
#   network           : diagnostic, test DNS, test de débit, commande sudo pour vider le cache DNS
# Claude Code (à lancer avec Claude Code fermé)
#   conv-list         : conversations, puis reprise ou mise à la Corbeille
#   conv --all        : toutes les conversations à la Corbeille
#   claude-cache      : vide cache/, debug/, backups/ et le dossier temporaire de Claude Code
#   all               : conv --all + zsh-history + claude-cache (une seule confirmation)
# Confidentialité
#   zsh-history       : historique du terminal à la Corbeille, remplacé par un historique vide
# Réglages de core-eraser
#   exclude [list|add <chemin>|remove <N>] : éléments protégés, jamais signalés ni déplacés
#   sentinel on|off   : surveille la Corbeille et signale les fichiers liés aux apps qu'on y jette
#   lang [en|fr]      : langue de core-eraser (anglais par défaut)
# Option
#   --dry-run <cmd>   : simulation, rien n'est modifié
#   --version         : version de core-eraser

set -u

VERSION="0.1.0"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TMP_DIR="${TMPDIR_CLAUDE:-/private/tmp/claude-$(id -u)}"
SESSION_SUBDIRS="file-history session-env sessions shell-snapshots todos paste-cache plans"
CACHE_SUBDIRS="cache debug backups"
ASSUME_YES=0
count=0
DRY_RUN=0
# 1 quand le script est piloté par l'app (mode « api ») : aucune question n'est posée
API=0
# Chemin réel du script (pour le service de surveillance et le bouton « Ouvrir dans Terminal »)
SELF="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"

# Aide : l'en-tête commenté du script, traduit ligne par ligne
usage() {
    local line
    while IFS= read -r line; do
        printf '%s\n' "$(t "$line")"
    done < <(awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0")
    exit 1
}

# 0 si la réponse vaut « oui » (ou « yes ») ; les deux langues sont acceptées
is_yes() {
    case "$1" in oui|yes|"$(t "oui")") return 0 ;; esac
    return 1
}

confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    ask "Confirmer ? (oui/non) "
    read -r answer
    is_yes "$answer" || { msg "Annulé."; exit 0; }
}

warn_running() {
    if pgrep -fl "claude" | grep -v "$0" | grep -qv grep; then
        msg "Attention : un processus Claude Code semble actif. Ferme-le avant de continuer."
    fi
}

# Vide le contenu d'un dossier sans supprimer le dossier lui-même
empty_dir() {
    [ -d "$1" ] || return 0
    find "$1" -mindepth 1 -maxdepth 1 -exec rm -rf {} + && count=$((count + 1))
}

# Quitte si un numéro de la saisie ($1) n'est pas entre 1 et le maximum ($2)
check_numbers() {
    local num
    for num in $1; do
        if ! [[ "$num" =~ ^[0-9]+$ ]] || [ $((10#$num)) -lt 1 ] || [ $((10#$num)) -gt "$2" ]; then
            msg "Numéro invalide : %s" "$num"
            exit 1
        fi
    done
}

# Protège un texte pour l'afficher dans une commande à copier-coller (rien n'y est exécuté par erreur)
shq() {
    printf '%q' "$1"
}

# Vérifie que la saisie ($1) est un seul numéro entre 1 et $2 ; le range dans NUM
one_number() {
    local words=()
    read -r -a words <<< "$1"
    [ ${#words[@]} -eq 1 ] || { msg "Un seul numéro."; exit 1; }
    check_numbers "$1" "$2"
    NUM=$((10#$1))
}

# Taille lisible à partir d'un nombre de Ko (Mo/Go, ou MB/GB en anglais avec un point décimal)
fmt_kb() {
    local loc="C"
    [ "$TOOLS_LANG" = "fr" ] && loc="fr_FR.UTF-8"
    LC_ALL="$loc" awk -v k="${1:-0}" -v g="$(t "Go")" -v m="$(t "Mo")" \
        'BEGIN { if (k >= 1048576) printf "%.1f %s", k / 1048576, g; else printf "%.0f %s", k / 1024, m }'
}

# Taille lisible d'un chemin
human_size() {
    fmt_kb "$(du -sk "$1" 2>/dev/null | cut -f1)"
}

# --- liste d'exclusions ------------------------------------------------------

TOOLS_DATA="$HOME/Library/Application Support/io.github.benjaminbusselet.core-eraser"
EXCLUDE_FILE="$TOOLS_DATA/exclusions.txt"

# --- langue -------------------------------------------------------------------
# Les textes sont écrits en français dans le script ; t() les traduit en anglais (langue par défaut)
# grâce au catalogue i18n_catalog, placé en fin de script. Choix mémorisé par « core-eraser lang fr|en ».

TOOLS_LANG="${TOOLS_LANG:-$(cat "$TOOLS_DATA/lang" 2>/dev/null)}"
case "$TOOLS_LANG" in fr|en) ;; *) TOOLS_LANG="en" ;; esac

# Traduit un texte écrit en français ; sans traduction connue, le texte est gardé tel quel
t() {
    local r
    [ "$TOOLS_LANG" = "fr" ] && { printf '%s' "$1"; return 0; }
    r=$(i18n_catalog | awk -F'\t' -v k="$1" '$1 == k { print $2; exit }')
    printf '%s' "${r:-$1}"
}

# Affiche un message traduit ; chaque %s est remplacé par l'argument suivant
msg() {
    local f
    f=$(t "$1")
    shift
    # shellcheck disable=SC2059  # le format vient du catalogue de traductions
    printf -- "$f\n" "$@"
}

# Pose une question traduite (sans retour à la ligne)
ask() {
    local f
    f=$(t "$1")
    shift
    # shellcheck disable=SC2059
    printf -- "$f" "$@"
}

# En-tête de tableau : format, puis titres de colonnes traduits
hdr() {
    local f="$1" a=() x
    shift
    for x in "$@"; do
        a+=("$(t "$x")")
    done
    # shellcheck disable=SC2059
    printf -- "$f" "${a[@]}"
}

lang_run() {
    case "${1:-}" in
        fr|en)
            mkdir -p "$TOOLS_DATA"
            printf '%s\n' "$1" > "$TOOLS_DATA/lang"
            TOOLS_LANG="$1"
            count=$((count + 1)) ;;
        "")
            MS_LABELS=("English" "Français")
            menu_select || return 0
            if [ "$MS_CHOICE" -eq 0 ]; then lang_run en; else lang_run fr; fi
            return 0 ;;
        *) usage ;;
    esac
    msg "Langue : français"
}

# Crée la liste vide si elle n'existe pas
exclude_init() {
    [ -f "$EXCLUDE_FILE" ] && return 0
    mkdir -p "$TOOLS_DATA"
    {
        msg "# Liste d'exclusions de core-eraser : un chemin par ligne."
        msg "# Un dossier exclu protège aussi tout ce qu'il contient. Les jokers * sont acceptés."
        msg "# Ces éléments ne sont jamais signalés ni déplacés par core-eraser."
    } > "$EXCLUDE_FILE"
}

# Lignes de la liste (sans commentaires), "~" remplacé par le dossier perso
exclude_entries() {
    [ -f "$EXCLUDE_FILE" ] || return 0
    grep -vE '^[[:space:]]*(#|$)' "$EXCLUDE_FILE" | sed "s|^~|$HOME|"
}

# 0 si le chemin est protégé : dossier de core-eraser lui-même, ou ligne de la liste (dossier ou joker)
is_excluded() {
    local path="$1" pat
    case "$path" in "$TOOLS_DATA"|"$TOOLS_DATA"/*) return 0 ;; esac
    [ -n "${EXCLUDES_LOADED:-}" ] || { EXCLUDES=$(exclude_entries); EXCLUDES_LOADED=1; }
    while IFS= read -r pat; do
        [ -n "$pat" ] || continue
        # $pat sans guillemets : les jokers * restent actifs
        # shellcheck disable=SC2254
        case "$path" in $pat|$pat/*) return 0 ;; esac
    done <<< "$EXCLUDES"
    return 1
}

# Ajoute un chemin à la liste (écrit avec ~ pour le dossier perso)
exclude_add() {
    local p="${1/#$HOME/~}"
    [ -n "$p" ] || { msg "Chemin manquant."; return 1; }
    exclude_init
    if grep -qxF "$p" "$EXCLUDE_FILE"; then
        msg "Déjà protégé : %s" "$p"
        return 0
    fi
    [ -e "${p/#\~/$HOME}" ] || case "$p" in *\**) ;; *) msg "Attention, ce chemin n'existe pas (ajouté quand même) : %s" "$p" ;; esac
    printf '%s\n' "$p" >> "$EXCLUDE_FILE"
    EXCLUDES_LOADED=""
    count=$((count + 1))
    msg "Protégé : %s" "$p"
}

# Réécrit la liste sans la ligne donnée (commentaires conservés)
exclude_remove_line() {
    awk -v l="$1" '$0 != l' "$EXCLUDE_FILE" > "$EXCLUDE_FILE.tmp" && mv "$EXCLUDE_FILE.tmp" "$EXCLUDE_FILE"
    EXCLUDES_LOADED=""
}

exclude_run() {
    local n=0 line
    exclude_init
    case "${1:-list}" in
        list)
            while IFS= read -r line; do
                n=$((n + 1))
                printf "%3d  %s\n" "$n" "$line"
            done < <(grep -vE '^[[:space:]]*(#|$)' "$EXCLUDE_FILE")
            [ "$n" -gt 0 ] || msg "Aucune exclusion."
            msg "Toujours protégé : %s" "$TOOLS_DATA" ;;
        add)
            line="${2:-}"
            if [ -z "$line" ]; then
                ask "Chemin à protéger (glisser-déposer accepté) : "
                read -r line
                line=$(printf '%s' "$line" | sed "s/^'//; s/'\$//; s/ *\$//; s/\\\\ / /g")
            fi
            exclude_add "$line" ;;
        remove)
            line="${2:-}"
            if [ -z "$line" ]; then
                exclude_run list
                ask "Numéro à retirer (vide = rien) : "
                read -r line
                [ -n "$line" ] || { msg "Rien retiré."; return 0; }
            fi
            n=$(grep -cvE '^[[:space:]]*(#|$)' "$EXCLUDE_FILE")
            one_number "$line" "$n"
            line=$(grep -vE '^[[:space:]]*(#|$)' "$EXCLUDE_FILE" | sed -n "${NUM}p")
            # Réécrit la liste sans cette ligne (commentaires conservés)
            exclude_remove_line "$line"
            count=$((count + 1))
            msg "Retiré : %s" "$line" ;;
        *) usage ;;
    esac
}

# Déplace un élément à la Corbeille (refuse hors de $HOME et /Applications, et les éléments protégés)
trash_item() {
    local src="$1" base dest n
    case "$src" in
        "$HOME"/?*|/Applications/?*) ;;
        *) msg "Refusé (hors de \$HOME et /Applications) : %s" "$src"; return 1 ;;
    esac
    is_excluded "$src" && { msg "Refusé (protégé par la liste d'exclusions) : %s" "$src"; return 1; }
    [ -e "$src" ] || { msg "Introuvable : %s" "$src"; return 1; }
    base=$(basename "$src")
    dest="$HOME/.Trash/$base"
    n=1
    while [ -e "$dest" ]; do
        dest="$HOME/.Trash/$base.$n"
        n=$((n + 1))
    done
    if [ "$DRY_RUN" -eq 1 ]; then
        msg "[simulation] %s -> Corbeille" "$src"
        return 0
    fi
    mv "$src" "$dest" && count=$((count + 1))
}

# --- conversations --------------------------------------------------------

conv_list() {
    local f id date project prompt n=0
    CONV_IDS=()
    CONV_FILES=()
    [ -d "$CLAUDE_DIR/projects" ] || { msg "Aucune conversation."; return 0; }
    command -v jq >/dev/null || { msg "jq requis pour la liste."; exit 1; }
    hdr "%3s  %-16s  %-24s  %-36s  %s\n" "N°" "Date" "Projet" "Id" "Résumé"
    printf '%.0s-' {1..145}; echo
    while IFS= read -r f; do
        n=$((n + 1))
        id=$(basename "$f" .jsonl)
        CONV_IDS+=("$id")
        CONV_FILES+=("$f")
        date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$f")
        project=$(basename "$(dirname "$f")")
        prompt=$(jq -r 'select(.type == "ai-title") | .aiTitle' "$f" 2>/dev/null | tail -1 | cut -c1-60)
        [ -n "$prompt" ] || prompt=$(jq -r 'select(.type == "user" and (.isSidechain | not) and (.isMeta | not))
            | .message.content
            | if type == "string" then . else (map(select(.type == "text") | .text) | join(" ")) end' \
            "$f" 2>/dev/null | grep -vE '^[[:space:]]*(<|$)' | head -1 | tr '\n' ' ' | cut -c1-60)
        printf "%3d  %-16s  %-24.24s  %-36s  %s\n" "$n" "$date" "$project" "$id" "$prompt"
    done < <(find "$CLAUDE_DIR/projects" -mindepth 2 -maxdepth 2 -name "*.jsonl" -print0 | xargs -0 ls -t 2>/dev/null)
    [ "$n" -gt 0 ] || msg "Aucune conversation."
}

# Liste numérotée, puis une saisie : "r N" (resume) ou "d N N N" (delete)
conv_menu() {
    local line action nums num cid dir selected=()
    conv_list
    [ ${#CONV_IDS[@]} -gt 0 ] || return 0
    ask "r N = resume, d N N = delete (vide = annuler) : "
    read -r action nums
    nums=${nums//,/ }
    for num in $nums; do
        if ! [[ "$num" =~ ^[0-9]+$ ]] || [ $((10#$num)) -lt 1 ] || [ $((10#$num)) -gt ${#CONV_IDS[@]} ]; then
            msg "Numéro invalide : %s" "$num"
            exit 1
        fi
    done
    case "$action" in
        r|resume)
            # shellcheck disable=SC2086  # découpage voulu des numéros saisis
            set -- $nums
            [ $# -eq 1 ] || { msg "resume : un seul numéro."; exit 1; }
            num=$((10#$1))
            cid="${CONV_IDS[$((num - 1))]}"
            dir=$(jq -r 'select(.cwd) | .cwd' "${CONV_FILES[$((num - 1))]}" 2>/dev/null | head -1)
            [ -d "$dir" ] || { msg "Dossier d'origine introuvable : %s" "$dir"; exit 1; }
            cd "$dir" && exec claude --resume "$cid"
            ;;
        d|delete)
            for num in $nums; do
                cid="${CONV_IDS[$((10#$num - 1))]}"
                case " ${selected[*]+${selected[*]}} " in
                    *" $cid "*) ;;
                    *) selected+=("$cid") ;;
                esac
            done
            [ ${#selected[@]} -gt 0 ] || { msg "Annulé."; exit 0; }
            msg "Conversations à supprimer : %s" "${#selected[@]}"
            confirm
            ASSUME_YES=1
            for cid in "${selected[@]}"; do
                conv_one "$cid"
            done
            ;;
        *) msg "Annulé."; exit 0 ;;
    esac
}

# Version de Claude Code avec laquelle l'organisation de ~/.claude a été vérifiée
CLAUDE_TESTED="2.1.323"

# Message d'information affiché avant les commandes Claude Code
claude_notice() {
    local v
    v=$(claude --version 2>/dev/null | awk '{ print $1 }')
    msg "Info : ces commandes lisent l'organisation interne de %s, vérifiée avec Claude Code %s." "$CLAUDE_DIR" "$CLAUDE_TESTED"
    if [ -n "$v" ] && [ "$v" != "$CLAUDE_TESTED" ]; then
        msg "Attention : ta version est %s. Si elle a changé cette organisation, des fichiers pourraient être mal visés." "$v"
    fi
    msg "Les conversations et historiques vont à la Corbeille ; les caches sont supprimés directement."
}

# Message d'information affiché au début de chaque commande : ce qu'elle fait et ce qu'elle touche
info_msg() {
    local m=""
    case "$1" in
        conv-list|conv|claude-cache|all) claude_notice ;;
        maintenance) m="coche les opérations d'entretien voulues, puis exécute-les en une fois. Celles qui demandent sudo sont regroupées à la fin, à lancer toi-même." ;;
        zsh-history) m="vide l'historique des commandes du terminal (confidentialité), sans lien avec Claude Code. L'ancien historique va à la Corbeille." ;;
        orphans) m="cherche dans ~/Library les fichiers laissés par des apps supprimées. Rien n'est déplacé sans ton choix ; les éléments choisis vont à la Corbeille." ;;
        app-uninstall) m="met une app et ses fichiers liés (réglages, caches, données) à la Corbeille. Si l'app est ouverte, core-eraser propose de la fermer." ;;
        dev-clean) m="vide les caches des outils de développement avec leurs propres commandes. Ils se recréent au besoin ; rien ne va à la Corbeille." ;;
        brew-manage) m="liste ce que tu as installé avec Homebrew. Les désinstallations passent par Homebrew : définitives, mais réinstallables." ;;
        plugins) m="liste les modules et extensions installés, et indique si leur app existe encore. Ceux de /Library demandent une commande sudo affichée." ;;
        services) m="liste les services lancés au démarrage (hors Apple). Les retirer les arrête ; ceux de /Library demandent une commande sudo affichée." ;;
        pkg-manage) m="liste les traces laissées par les installations .pkg. Effacer une trace demande sudo et ne supprime pas l'app." ;;
        updates) m="compare les versions installées aux dernières disponibles. Les apps Sparkle sont interrogées sur internet ; seules les apps Homebrew se mettent à jour d'ici." ;;
        lipo-app) m="retire la partie Intel d'une app pour gagner de la place. Un avertissement détaillé s'affiche avant le choix." ;;
        sentinel) m="surveille la Corbeille et signale les fichiers laissés par une app que tu y jettes. Ne supprime rien." ;;
        spotlight) m="montre l'état de l'index Spotlight de chaque disque ; le reconstruire demande une commande sudo affichée." ;;
        user-clean) m="vide des caches et journaux de ton dossier perso. Ils se recréent ; historique, mots de passe et marque-pages ne sont pas touchés." ;;
        system-clean) m="montre la taille des caches et journaux système, et affiche les commandes sudo pour les vider. Rien n'est supprimé d'ici." ;;
        network) m="diagnostic et tests du réseau. Seul le vidage du cache DNS demande sudo ; le test de débit utilise ta connexion." ;;
        exclude) m="gère la liste des éléments que core-eraser ne signale et ne touche jamais." ;;
        lang) m="choisit la langue de core-eraser : anglais (par défaut) ou français." ;;
        timemachine) m="état, exclusions et sauvegardes Time Machine. Rien n'est supprimé d'ici : les suppressions demandent une commande sudo affichée." ;;
    esac
    [ -n "$m" ] && msg "Info : %s" "$(t "$m")"
    [ "$DRY_RUN" -eq 1 ] && msg "Mode simulation : rien ne sera modifié."
    return 0
}

# Met à la Corbeille le contenu d'un dossier, sans le dossier lui-même
trash_contents() {
    local item
    [ -d "$1" ] || return 0
    while IFS= read -r -d '' item; do
        trash_item "$item"
    done < <(find "$1" -mindepth 1 -maxdepth 1 -print0)
}

conv_all() {
    local sub
    msg "Dossier : %s" "$CLAUDE_DIR"
    msg "Seront mis à la Corbeille :"
    msg "  - projects/* : dossiers de projet complets (memory/ compris)"
    echo "  - $SESSION_SUBDIRS"
    msg "  - history.jsonl"
    confirm

    # Dossiers de projet complets (transcripts, sessions, memory/)
    trash_contents "$CLAUDE_DIR/projects"

    # Données annexes des sessions
    for sub in $SESSION_SUBDIRS; do
        trash_contents "$CLAUDE_DIR/$sub"
    done

    # Historique des prompts
    [ -f "$CLAUDE_DIR/history.jsonl" ] && trash_item "$CLAUDE_DIR/history.jsonl"
}

conv_one() {
    local cid="$1" targets=() item agents=0 sub pid f

    # Format attendu d'un id de session (évite tout motif dangereux dans rm)
    if ! [[ "$cid" =~ ^[0-9a-fA-F-]{8,}$ ]]; then
        msg "Id invalide : %s" "$cid"
        exit 1
    fi

    # Transcript principal et dossier de la conversation (sous-agents compris)
    if [ -d "$CLAUDE_DIR/projects" ]; then
        while IFS= read -r -d '' item; do
            targets+=("$item")
        done < <(find "$CLAUDE_DIR/projects" -mindepth 2 -maxdepth 2 \( -name "$cid.jsonl" -o -name "$cid" \) -print0)
    fi

    # Données annexes de la session
    for sub in $SESSION_SUBDIRS; do
        if [ -d "$CLAUDE_DIR/$sub" ]; then
            while IFS= read -r -d '' item; do
                targets+=("$item")
            done < <(find "$CLAUDE_DIR/$sub" -mindepth 1 -maxdepth 1 -name "$cid*" -print0)
        fi
    done

    # Registre des processus : <pid>.json contient le sessionId, <pid>.*.key l'accompagne
    if [ -d "$CLAUDE_DIR/sessions" ]; then
        while IFS= read -r item; do
            pid=$(basename "$item" .json)
            for f in "$CLAUDE_DIR/sessions/$pid".*; do
                targets+=("$f")
            done
        done < <(grep -lE "\"sessionId\": ?\"$cid\"" "$CLAUDE_DIR/sessions"/*.json 2>/dev/null)
    fi

    # Dossier temporaire de la session
    if [ -d "$TMP_DIR" ]; then
        while IFS= read -r -d '' item; do
            targets+=("$item")
        done < <(find "$TMP_DIR" -mindepth 2 -maxdepth 2 -name "$cid" -print0)
    fi

    local hist=0
    if [ -f "$CLAUDE_DIR/history.jsonl" ]; then
        hist=$(grep -cE "\"sessionId\": ?\"$cid\"" "$CLAUDE_DIR/history.jsonl")
    fi

    if [ ${#targets[@]} -eq 0 ] && [ "$hist" -eq 0 ]; then
        msg "Aucune conversation trouvée pour : %s" "$cid"
        exit 1
    fi

    msg "Conversation : %s" "$cid"
    msg "Seront mis à la Corbeille (dossier temporaire : supprimé directement) :"
    for item in ${targets[@]+"${targets[@]}"}; do
        echo "  - ${item#"$CLAUDE_DIR"/}"
        if [ -d "$item" ]; then
            agents=$((agents + $(find "$item" -type f -name "agent-*.jsonl" | wc -l)))
        fi
    done
    msg "  - sous-agents : %s" "$agents"
    msg "  - history.jsonl : %s ligne(s)" "$hist"
    confirm

    for item in ${targets[@]+"${targets[@]}"}; do
        case "$item" in
            "$TMP_DIR"/*) rm -rf "$item" && count=$((count + 1)) ;;
            *) trash_item "$item" ;;
        esac
    done

    # Retire les lignes de cette session de l'historique ; l'ancien historique va à la Corbeille
    if [ "$hist" -gt 0 ]; then
        grep -vE "\"sessionId\": ?\"$cid\"" "$CLAUDE_DIR/history.jsonl" > "$CLAUDE_DIR/history.jsonl.tmp" || true
        trash_item "$CLAUDE_DIR/history.jsonl" && mv "$CLAUDE_DIR/history.jsonl.tmp" "$CLAUDE_DIR/history.jsonl"
        rm -f "$CLAUDE_DIR/history.jsonl.tmp"
    fi
}

# --- historique zsh -------------------------------------------------------

zsh_history() {
    msg "Seront mis à la Corbeille, puis remplacés par un historique vide :"
    msg "  - ~/.zsh_history"
    msg "  - ~/.zsh_sessions/*"
    msg "Ferme les autres terminaux avant : chaque shell ouvert réécrit son historique en quittant."
    confirm

    if [ -f "$HOME/.zsh_history" ] && trash_item "$HOME/.zsh_history"; then
        [ "$DRY_RUN" -eq 1 ] || { touch "$HOME/.zsh_history" && chmod 600 "$HOME/.zsh_history"; }
    fi
    trash_contents "$HOME/.zsh_sessions"
    msg "Quitte ce terminal avec : kill -9 \$\$ (sinon zsh réécrit l'ancien historique en se fermant)."
}

# --- caches Claude --------------------------------------------------------

claude_cache() {
    local sub
    msg "Seront vidés définitivement (caches, recréés par Claude Code) :"
    for sub in $CACHE_SUBDIRS; do
        echo "  - $CLAUDE_DIR/$sub"
    done
    echo "  - $TMP_DIR"
    confirm

    for sub in $CACHE_SUBDIRS; do
        empty_dir "$CLAUDE_DIR/$sub"
    done
    empty_dir "$TMP_DIR"
}

# --- tout -----------------------------------------------------------------

clean_all() {
    msg "Seront traités : toutes les conversations Claude et l'historique zsh (Corbeille), les caches Claude (supprimés)."
    confirm
    ASSUME_YES=1
    conv_all
    zsh_history
    claude_cache
}

# --- restes d'apps absentes -----------------------------------------------

APP_DIRS="/Applications /Applications/Utilities $HOME/Applications /System/Applications /System/Applications/Utilities"
LIB_DIRS=("Application Support" "Caches" "Containers" "Group Containers" "Preferences" "Saved Application State"
          "HTTPStorages" "WebKit" "Logs" "Application Scripts" "LaunchAgents")

# Clés (en minuscules) d'une app : identifiants (app, extensions, éléments de connexion),
# nom, et groupes partagés déclarés dans sa signature (ex : group.com.canalplus.tv.topShelf)
app_keys() {
    local app="$1" sub id
    for sub in "$app" "$app"/Contents/PlugIns/*.appex "$app"/Contents/Library/LoginItems/*.app; do
        [ -d "$sub" ] || continue
        id=$(plutil -extract CFBundleIdentifier raw -o - "$sub/Contents/Info.plist" 2>/dev/null) && echo "$id"
    done
    basename "$app" .app
    codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -p - 2>/dev/null \
        | awk '/application-groups/ { f = 1; next } f && /\]/ { f = 0 } f { gsub(/.*=> "|"$/, ""); print }' \
        | sed -E 's/^[A-Z0-9]{10}\.//; s/^groups?\.//'
}

# Clé (en minuscules) d'une entrée de ~/Library : sans extension, préfixe d'éditeur ni "group."
entry_key() {
    echo "$1" | sed -E 's/\.(plist|savedState|binarycookies)$//; s/^[A-Z0-9]{10}\.//; s/^(systemgroup|groups?)\.//' | tr '[:upper:]' '[:lower:]'
}

# 0 si la clé correspond à une ligne de la liste (identique, variante "ligne.suffixe", ou nom d'app)
key_matches() {
    local key="$1" line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$key" in "$line"|"$line".*) return 0 ;; esac
        case "$line" in "$key".*|"$key "*) return 0 ;; esac
    done <<< "$2"
    return 1
}

# Identifiants, noms et groupes partagés de toutes les apps installées
installed_apps() {
    local d app id
    {
    for d in $APP_DIRS; do
        for app in "$d"/*.app; do
            [ -d "$app" ] && app_keys "$app"
        done
    done
    # Apps auxiliaires installées dans Application Support (ex : GoogleUpdater de Chrome)
    find "$HOME/Library/Application Support" "/Library/Application Support" -maxdepth 6 -name '*.app' -type d -prune 2>/dev/null \
        | while IFS= read -r app; do
              id=$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist" 2>/dev/null) && echo "$id"
          done
    } | tr '[:upper:]' '[:lower:]' | sort -u
}

# Charge les apps installées et leurs noms d'éditeur (utilisés par app_is_installed)
load_apps() {
    APPS_LIST=$(installed_apps)
    VENDOR_LIST=$(printf '%s\n' "$APPS_LIST" | awk -F. 'NF >= 3 { print $2 }' | grep -vx apple | sort -u)
}

# 0 si la clé correspond à une app installée
app_is_installed() {
    local key="$1"
    key_matches "$key" "$APPS_LIST" && return 0
    # Simple nom de dossier égal au nom d'éditeur d'une app installée (ex : "mozilla" pour Firefox)
    printf '%s\n' "$VENDOR_LIST" | grep -qxF "$key"
}

# Noms (en minuscules) des composants de macOS : frameworks, programmes, services système
system_index() {
    { find /System/Library/PrivateFrameworks /System/Library/Frameworks /System/Library/CoreServices \
           /System/Applications -mindepth 1 -maxdepth 1
      ls /usr/libexec /usr/sbin /usr/bin /System/Library/LaunchAgents /System/Library/LaunchDaemons
    } 2>/dev/null | sed -E 's|.*/||; s/\.(framework|app|plist|bundle)$//; s/^com\.apple\.//' | tr '[:upper:]' '[:lower:]' | sort -u
}

# 0 si le dossier vient de macOS : son nom commence comme un composant système (5 lettres
# minimum), ou il n'a pas l'attribut com.apple.provenance posé sur les fichiers des apps tierces
is_macos_item() {
    local key="$1" path="$2"
    printf '%s\n' "$SYSTEM_INDEX" | awk -v k="$key" \
        'length($0) >= 5 && (index(k, $0) == 1 || index($0, k) == 1) { found = 1; exit } END { exit !found }' && return 0
    xattr "$path" 2>/dev/null | grep -qx com.apple.provenance || return 0
    return 1
}

# Affiche une ligne par reste : taille en Ko, dossier, nom, chemin (séparés par une tabulation)
orphans_scan() {
    local dir entry base key kb label
    load_apps
    SYSTEM_INDEX=$(system_index)
    for dir in "${LIB_DIRS[@]}"; do
        [ -d "$HOME/Library/$dir" ] || continue
        while IFS= read -r -d '' entry; do
            is_excluded "$entry" && continue
            base=$(basename "$entry")
            key=$(entry_key "$base")
            case "$key" in ""|.*|com.apple.*) continue ;; esac
            label="$base"
            # Identifiant (a.b.c) : vérifié partout. Simple nom de dossier : seulement dans Application Support.
            case "$key" in
                *.*.*) ;;
                *) [ "$dir" = "Application Support" ] && [ -d "$entry" ] || continue
                   is_macos_item "$key" "$entry" && continue
                   label="$base $(t "(à vérifier)")" ;;
            esac
            app_is_installed "$key" && continue
            kb=$(du -sk "$entry" 2>/dev/null | cut -f1)
            printf '%s\t%s\t%s\t%s\n' "${kb:-0}" "$dir" "$label" "$entry"
        done < <(find "$HOME/Library/$dir" -mindepth 1 -maxdepth 1 -print0)
    done
}

orphans_run() {
    local lines n=0 kb dir name path sel num
    ORPHAN_PATHS=()
    msg "Analyse en cours..."
    lines=$(orphans_scan | sort -rn)
    [ -n "$lines" ] || { msg "Aucun reste détecté."; return 0; }
    hdr "%3s  %9s  %-24s  %s\n" "N°" "Taille" "Dossier" "Nom"
    while IFS=$'\t' read -r kb dir name path; do
        n=$((n + 1))
        ORPHAN_PATHS+=("$path")
        printf "%3d  %9s  %-24.24s  %s\n" "$n" "$(fmt_kb "$kb")" "$dir" "$name"
    done <<< "$lines"
    ask "Numéros à mettre à la Corbeille, ou x suivi des numéros à protéger (ex : 1 3 ou x 2, vide = rien) : "
    read -r sel
    sel=${sel//,/ }
    [ -n "$sel" ] || { msg "Rien déplacé."; return 0; }
    case "$sel" in
        x\ *)
            sel=${sel#x }
            check_numbers "$sel" "$n"
            for num in $sel; do
                exclude_add "${ORPHAN_PATHS[$((10#$num - 1))]}"
            done
            return 0 ;;
    esac
    check_numbers "$sel" "$n"
    msg "Seront mis à la Corbeille :"
    for num in $sel; do
        echo "  - ${ORPHAN_PATHS[$((10#$num - 1))]}"
    done
    confirm
    for num in $sel; do
        trash_item "${ORPHAN_PATHS[$((10#$num - 1))]}"
    done
}

# --- désinstallation d'une app --------------------------------------------

# Nom du cask Homebrew qui a installé l'app, vide sinon
cask_token() {
    command -v brew >/dev/null || return 0
    : "${CASKROOM:=$(brew --caskroom)}"
    [ -d "$CASKROOM" ] || return 0
    grep -lF "\"$(basename "$1")\"" "$CASKROOM"/*/.metadata/INSTALL_RECEIPT.json 2>/dev/null \
        | head -1 | sed -E "s|^$CASKROOM/([^/]+)/.*|\1|"
}

# Fichiers de ~/Library liés à une app (un chemin par ligne)
app_related_files() {
    local keys dir entry
    keys=$(app_keys "$1" | tr '[:upper:]' '[:lower:]' | sort -u)
    for dir in "${LIB_DIRS[@]}"; do
        [ -d "$HOME/Library/$dir" ] || continue
        while IFS= read -r -d '' entry; do
            is_excluded "$entry" && continue
            key_matches "$(entry_key "$(basename "$entry")")" "$keys" && printf '%s\n' "$entry"
        done < <(find "$HOME/Library/$dir" -mindepth 1 -maxdepth 1 -print0)
    done
}

# 0 si l'app est ouverte (pgrep ne se compte pas lui-même ; caractères spéciaux du chemin neutralisés)
app_is_running() {
    pgrep -f "$(printf '%s' "$1/Contents/MacOS/" | sed 's/[][\.*^$+?(){}|]/\\&/g')" >/dev/null
}

# Propose de fermer les apps ouvertes parmi celles reçues (chemins .app), comme Cmd+Q.
# Renvoie 0 si plus aucune n'est ouverte.
offer_quit() {
    local app open=() still="" id answer
    for app in "$@"; do
        app_is_running "$app" && open+=("$app")
    done
    [ ${#open[@]} -gt 0 ] || return 0
    [ "$API" -eq 1 ] && return 1
    msg "Apps ouvertes :"
    for app in "${open[@]}"; do
        echo "  - $(basename "$app" .app)"
    done
    ask "Les fermer maintenant ? (oui/non) "
    read -r answer
    is_yes "$answer" || return 1
    for app in "${open[@]}"; do
        id=$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist" 2>/dev/null)
        # Identifiant inséré dans AppleScript : seulement lettres, chiffres, point et tiret
        [[ "$id" =~ ^[A-Za-z0-9.-]+$ ]] && osascript -e "tell application id \"$id\" to quit" >/dev/null 2>&1 &
    done
    wait
    # Jusqu'à 15 secondes pour laisser chaque app se fermer (ou demander d'enregistrer)
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        still=""
        for app in "${open[@]}"; do
            app_is_running "$app" && still="$still $(basename "$app" .app)"
        done
        [ -n "$still" ] || return 0
        sleep 1
    done
    msg "Toujours ouvertes (une fenêtre attend peut-être ta réponse) :%s" "$still"
    return 1
}

app_uninstall_run() {
    local apps=() files=() d app n=0 num keys dir entry kb total=0 token
    # Apps déplaçables : les liens (ex : Safari, protégé par macOS) sont exclus
    for d in /Applications "$HOME/Applications"; do
        for app in "$d"/*.app; do
            [ -d "$app" ] && [ ! -L "$app" ] && apps+=("$app")
        done
    done
    [ ${#apps[@]} -gt 0 ] || { msg "Aucune app trouvée."; return 0; }
    for app in "${apps[@]}"; do
        n=$((n + 1))
        printf "%3d  %s\n" "$n" "$(basename "$app" .app)"
    done
    ask "Numéro de l'app à désinstaller (vide = rien) : "
    read -r num
    [ -n "$num" ] || { msg "Rien déplacé."; return 0; }
    one_number "$num" "$n"
    app="${apps[$((NUM - 1))]}"
    offer_quit "$app" || { msg "%s est ouverte : rien fait." "$(basename "$app" .app)"; exit 1; }
    files=("$app")
    while IFS= read -r entry; do
        files+=("$entry")
    done < <(app_related_files "$app")
    msg "Seront mis à la Corbeille :"
    for entry in "${files[@]}"; do
        kb=$(du -sk "$entry" 2>/dev/null | cut -f1)
        total=$((total + ${kb:-0}))
        printf "  %9s  %s\n" "$(fmt_kb "$kb")" "$entry"
    done
    msg "  Total : %s" "$(fmt_kb "$total")"
    token=$(cask_token "$app")
    [ -n "$token" ] && msg "Installée par Homebrew : lance aussi « brew uninstall --cask %s » ensuite." "$token"
    confirm
    for entry in "${files[@]}"; do
        trash_item "$entry"
    done
}

# --- caches de développement ----------------------------------------------

# Une ligne par outil installé : nom, dossier de cache donné par l'outil lui-même
dev_caches() {
    # npm 11 refuse parfois "config get cache" : lecture dans la liste complète des réglages
    if command -v npm >/dev/null; then
        printf 'npm\t%s\n' "$(npm config ls -l 2>/dev/null | sed -n 's/^cache = "\(.*\)"$/\1/p')"
    fi
    if command -v pip3 >/dev/null; then printf 'pip\t%s\n' "$(pip3 cache dir 2>/dev/null)"; fi
    if command -v brew >/dev/null; then printf 'Homebrew\t%s\n' "$(brew --cache 2>/dev/null)"; fi
    if command -v xcodebuild >/dev/null; then
        printf 'Xcode\t%s\n' "$(defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation 2>/dev/null \
            || printf "%s\n" "$HOME/Library/Developer/Xcode/DerivedData")"
    fi
}

# Vide un cache avec la commande de l'outil ($1 = nom, $2 = dossier)
dev_clean_one() {
    case "$1" in
        npm) npm cache clean --force ;;
        pip) pip3 cache purge ;;
        Homebrew) brew cleanup -s --prune=all ;;
        Xcode) empty_dir "$2" ;;
    esac
}

# Vide un cache ($1 nom, $2 dossier) en tenant compte de la simulation, puis affiche ce qui reste
dev_clean_item() {
    if [ "$DRY_RUN" -eq 1 ]; then
        msg "[simulation] %s : cache vidé" "$1"
        return 0
    fi
    dev_clean_one "$1" "$2" >/dev/null 2>&1 && count=$((count + 1))
    msg "  %s : %s restant" "$1" "$(human_size "$2")"
}

# Vide tous les caches de développement trouvés, sans question (écran Maintenance)
dev_clean_all() {
    local name path
    while IFS=$'\t' read -r name path; do
        [ -n "$path" ] && [ -d "$path" ] && dev_clean_item "$name" "$path"
    done < <(dev_caches)
}

dev_clean_run() {
    local names=() paths=() name path n=0 sel num i
    while IFS=$'\t' read -r name path; do
        [ -n "$path" ] && [ -d "$path" ] || continue
        n=$((n + 1))
        names+=("$name")
        paths+=("$path")
        printf "%3d  %-9s  %9s  %s\n" "$n" "$name" "$(human_size "$path")" "$path"
    done < <(dev_caches)
    [ "$n" -gt 0 ] || { msg "Aucun cache trouvé."; return 0; }
    msg "(Homebrew retire aussi les anciennes versions des paquets installés)"
    ask "Numéros à vider (ex : 1 3, vide = rien) : "
    read -r sel
    sel=${sel//,/ }
    [ -n "$sel" ] || { msg "Rien vidé."; return 0; }
    check_numbers "$sel" "$n"
    msg "Seront vidés :"
    for num in $sel; do
        echo "  - ${names[$((10#$num - 1))]}"
    done
    confirm
    for num in $sel; do
        i=$((10#$num - 1))
        dev_clean_item "${names[$i]}" "${paths[$i]}"
    done
}

# --- Homebrew --------------------------------------------------------------

brew_manage_run() {
    local names=() kinds=() name app n=0 sel num i outdated deps cellar caskroom state path
    command -v brew >/dev/null || { msg "Homebrew n'est pas installé."; return 0; }
    export HOMEBREW_NO_AUTO_UPDATE=1
    outdated=$(brew outdated --quiet 2>/dev/null)
    cellar=$(brew --cellar)
    caskroom=$(brew --caskroom)
    hdr "%3s  %-6s  %9s  %-28s  %s\n" "N°" "Type" "Taille" "Nom" "État"
    # Paquets installés à ta demande (leurs dépendances ne sont pas listées), puis apps (casks)
    while IFS=$'\t' read -r name app; do
        [ -n "$name" ] || continue
        n=$((n + 1))
        names+=("$name")
        if [ "$app" = "-" ]; then
            kinds+=("paquet")
            path="$cellar/$name"
        else
            kinds+=("app")
            path="$caskroom/$name"
            [ -n "$app" ] && [ -d "/Applications/$app" ] && path="/Applications/$app"
        fi
        state=$(t "à jour")
        printf '%s\n' "$outdated" | grep -qxF "$name" && state=$(t "mise à jour disponible")
        printf "%3d  %-6s  %9s  %-28.28s  %s\n" "$n" "$(t "${kinds[$((n - 1))]}")" "$(human_size "$path")" "$name" "$state"
    done < <(brew leaves --installed-on-request 2>/dev/null | awk '{ print $0 "\t-" }'
             brew info --cask --json=v2 --installed 2>/dev/null \
                 | jq -r '.casks[] | [.token, ([.artifacts[] | objects | .app // empty | .[] | strings] | first // "")] | @tsv')
    [ "$n" -gt 0 ] || { msg "Rien d'installé avec Homebrew."; return 0; }
    deps=$(brew autoremove -n 2>/dev/null | grep -v '^==>')
    if [ -n "$deps" ]; then
        msg "Dépendances devenues inutiles : %s" "$(printf '%s' "$deps" | tr '\n' ' ')"
    else
        msg "Dépendances devenues inutiles : aucune"
    fi
    ask "Numéros à désinstaller, ou d pour retirer les dépendances inutiles (vide = rien) : "
    read -r sel
    sel=${sel//,/ }
    [ -n "$sel" ] || { msg "Rien désinstallé."; return 0; }
    if [ "$sel" = "d" ]; then
        [ -n "$deps" ] || { msg "Aucune dépendance à retirer."; return 0; }
        msg "Seront retirées : %s" "$(printf '%s' "$deps" | tr '\n' ' ')"
        confirm
        if [ "$DRY_RUN" -eq 1 ]; then msg "[simulation] brew autoremove"; return 0; fi
        brew autoremove && count=$((count + $(echo "$deps" | wc -l)))
        return 0
    fi
    check_numbers "$sel" "$n"
    msg "Seront désinstallés :"
    for num in $sel; do
        i=$((10#$num - 1))
        echo "  - ${names[$i]} ($(t "${kinds[$i]}"))"
    done
    confirm
    for num in $sel; do
        i=$((10#$num - 1))
        if [ "$DRY_RUN" -eq 1 ]; then
            msg "[simulation] désinstallation de %s" "${names[$i]}"
            continue
        fi
        if [ "${kinds[$i]}" = "app" ]; then
            brew uninstall --cask "${names[$i]}" && count=$((count + 1))
        else
            brew uninstall "${names[$i]}" && count=$((count + 1))
        fi
    done
}

# --- plug-ins et extensions ------------------------------------------------

# Éditeur (Team ID) inscrit dans la signature d'un paquet, vide si absent
team_of() {
    codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p' | grep -vx "not set"
}

# Éditeurs (Team ID) des apps installées
installed_teams() {
    local d app
    for d in $APP_DIRS; do
        for app in "$d"/*.app; do
            [ -d "$app" ] && team_of "$app"
        done
    done | sort -u
}

# Origine d'un élément ($1 = identifiant, $2 = paquet ou programme signé) ; TEAMS doit être chargé
owner_of() {
    local low
    low=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    [ -n "$low" ] || { echo "-"; return; }
    if app_is_installed "$low"; then
        msg "app présente"
    elif [ -e "$2" ] && printf '%s\n' "$TEAMS" | grep -qxF "$(team_of "$2")"; then
        msg "même éditeur qu'une app"
    else
        msg "app absente"
    fi
}

# Une ligne par module (hors Apple) : taille en Ko, type, nom, app d'origine, chemin
plugins_scan() {
    local root b id low type owner kb exclude sysext
    TEAMS=$(installed_teams)
    # Modules = paquets avec Contents/Info.plist, hors apps, frameworks et dossiers de données
    exclude=$(printf '/%s/|' "${LIB_DIRS[@]}" Developer Frameworks)
    exclude="${exclude}\.app/|\.framework/"
    sysext=$(systemextensionsctl list 2>/dev/null)
    for root in "$HOME/Library" /Library; do
        find "$root" -maxdepth 5 -path '*/Contents/Info.plist' -type f 2>/dev/null
    done | grep -vE "$exclude" | sed 's|/Contents/Info.plist$||' | while IFS= read -r b; do
        is_excluded "$b" && continue
        id=$(plutil -extract CFBundleIdentifier raw -o - "$b/Contents/Info.plist" 2>/dev/null)
        low=$(echo "$id" | tr '[:upper:]' '[:lower:]')
        case "$low" in com.apple.*) continue ;; esac
        type="${b##*.}"
        owner=$(owner_of "$id" "$b")
        # État des extensions système (ex : "activated enabled")
        [ "$type" = "systemextension" ] && owner="$owner, $(printf '%s\n' "$sysext" | grep -F "$id" | sed -n 's/.*\[\(.*\)\]$/\1/p')"
        kb=$(du -sk "$b" 2>/dev/null | cut -f1)
        printf '%s\t%s\t%s\t%s\t%s\n' "${kb:-0}" "$type" "$(basename "$b")" "$owner" "$b"
    done
}

plugins_run() {
    local lines n=0 kb type name owner path paths=() sel num p
    msg "Analyse en cours..."
    load_apps
    lines=$(plugins_scan | sort -rn)
    [ -n "$lines" ] || { msg "Aucun module trouvé."; return 0; }
    hdr "%3s  %9s  %-16s  %-32s  %s\n" "N°" "Taille" "Type" "App d'origine" "Nom"
    while IFS=$'\t' read -r kb type name owner path; do
        n=$((n + 1))
        paths+=("$path")
        printf "%3d  %9s  %-16.16s  %-32.32s  %s\n" "$n" "$(fmt_kb "$kb")" "$type" "$owner" "$name"
    done <<< "$lines"
    ask "Numéros à retirer (vide = rien) : "
    read -r sel
    sel=${sel//,/ }
    [ -n "$sel" ] || { msg "Rien retiré."; return 0; }
    check_numbers "$sel" "$n"
    msg "Seront retirés :"
    for num in $sel; do
        echo "  - ${paths[$((10#$num - 1))]}"
    done
    confirm
    for num in $sel; do
        p="${paths[$((10#$num - 1))]}"
        case "$p" in
            *.systemextension)
                msg "Extension système, à retirer dans Réglages Système > Général > Ouverture et extensions : %s" "$(basename "$p")" ;;
            "$HOME"/*)
                trash_item "$p" ;;
            *)
                msg "Droits administrateur requis, lance toi-même : sudo mv %s %s" "$(shq "$p")" "$(shq "$HOME/.Trash/")" ;;
        esac
    done
}

# --- services au démarrage -------------------------------------------------

# Dossiers lus par launchd au démarrage (domaine utilisateur, puis système)
LAUNCH_DIRS=("$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons")

# Domaine launchd d'un fichier de service
launch_domain() {
    case "$1" in
        "$HOME"/*|/Library/LaunchAgents/*) printf "gui/%s\n" "$(id -u)" ;;
        *) printf "system\n" ;;
    esac
}

# Une ligne par service (hors Apple) : label, programme, état du programme, état, origine, fichier
services_scan() {
    local d p label prog file state
    TEAMS=$(installed_teams)
    for d in "${LAUNCH_DIRS[@]}"; do
        for p in "$d"/*.plist; do
            [ -f "$p" ] || continue
            is_excluded "$p" && continue
            label=$(plutil -extract Label raw -o - "$p" 2>/dev/null)
            case "$label" in com.apple.*) continue ;; esac
            prog=$(plutil -extract Program raw -o - "$p" 2>/dev/null || plutil -extract ProgramArguments.0 raw -o - "$p" 2>/dev/null)
            if [ -z "$label" ]; then
                file=$(t "fichier invalide (ignoré)")
            elif [ -e "$prog" ]; then
                file=$(t "programme présent")
            else
                file=$(t "programme manquant")
            fi
            state=$(launchctl print "$(launch_domain "$p")/$label" 2>/dev/null | sed -n 's/^[[:space:]]*state = //p' | head -1 \
                | sed 's/^not running$/arrêté/; s/^running$/en marche/')
            printf '%s\t%s\t%s\t%s\t%s\n' "${label:-$(basename "$p" .plist)}" "$file" "$(t "${state:-non chargé}")" \
                "$(owner_of "$label" "$prog")" "$p"
        done
    done
}

services_run() {
    local lines n=0 label file state owner path paths=() labels=() sel num i dom
    msg "Analyse en cours..."
    load_apps
    lines=$(services_scan)
    [ -n "$lines" ] || { msg "Aucun service tiers."; return 0; }
    hdr "%3s  %-36s  %-20s  %-12s  %s\n" "N°" "Service" "Programme" "État" "App d'origine"
    while IFS=$'\t' read -r label file state owner path; do
        n=$((n + 1))
        labels+=("$label")
        paths+=("$path")
        printf "%3d  %-36.36s  %-20s  %-12s  %s\n" "$n" "$label" "$file" "$state" "$owner"
    done <<< "$lines"
    ask "Numéros à retirer (vide = rien) : "
    read -r sel
    sel=${sel//,/ }
    [ -n "$sel" ] || { msg "Rien retiré."; return 0; }
    check_numbers "$sel" "$n"
    msg "Seront arrêtés et retirés :"
    for num in $sel; do
        echo "  - ${paths[$((10#$num - 1))]}"
    done
    confirm
    for num in $sel; do
        i=$((10#$num - 1))
        dom=$(launch_domain "${paths[$i]}")
        case "${paths[$i]}" in
            "$HOME"/*)
                if [ "$DRY_RUN" -eq 1 ]; then
                    msg "[simulation] arrêt de %s" "${labels[$i]}"
                else
                    launchctl bootout "$dom/${labels[$i]}" 2>/dev/null
                fi
                trash_item "${paths[$i]}" ;;
            *)
                msg "Droits administrateur requis, lance toi-même :"
                msg "  sudo launchctl bootout %s" "$(shq "$dom/${labels[$i]}")"
                msg "  sudo mv %s %s" "$(shq "${paths[$i]}")" "$(shq "$HOME/.Trash/")" ;;
        esac
    done
}

# --- paquets d'installation (.pkg) -----------------------------------------

# Une ligne par paquet tiers : identifiant, version, date, fichiers présents/total, état, emplacement
pkg_scan() {
    local p info ver loc date f tot ok state
    while IFS= read -r p; do
        info=$(pkgutil --pkg-info "$p" 2>/dev/null)
        ver=$(printf '%s\n' "$info" | sed -n 's/^version: //p')
        loc=$(printf '%s\n' "$info" | sed -n 's/^location: //p')
        date=$(date -r "$(printf '%s\n' "$info" | sed -n 's/^install-time: //p')" '+%Y-%m-%d' 2>/dev/null)
        tot=0
        ok=0
        while IFS= read -r f; do
            tot=$((tot + 1))
            if [ -e "/$loc/$f" ] || [ -e "/$f" ]; then ok=$((ok + 1)); fi
        done < <(pkgutil --only-files --files "$p" 2>/dev/null)
        if [ "$ok" -eq 0 ]; then
            state="trace seule (fichiers supprimés)"
        elif [ "$ok" -lt "$tot" ]; then
            state="partiel (app mise à jour depuis)"
        else
            state="complet"
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "$ver" "$date" "$ok/$tot" "$state" "/$loc"
    done < <(pkgutil --pkgs | grep -v '^com\.apple\.')
}

pkg_manage_run() {
    local lines n=0 id ver date files state loc ids=() states=() sel num i
    lines=$(pkg_scan)
    [ -n "$lines" ] || { msg "Aucun paquet tiers."; return 0; }
    hdr "%3s  %-42s  %-10s  %-10s  %-12s  %s\n" "N°" "Paquet" "Version" "Installé" "Fichiers" "État"
    while IFS=$'\t' read -r id ver date files state loc; do
        n=$((n + 1))
        ids+=("$id")
        states+=("$state")
        printf "%3d  %-42.42s  %-10.10s  %-10s  %-12s  %s\n" "$n" "$id" "$ver" "$date" "$files" "$(t "$state")"
    done <<< "$lines"
    ask "Numéros dont effacer la trace (vide = rien) : "
    read -r sel
    sel=${sel//,/ }
    [ -n "$sel" ] || { msg "Rien effacé."; return 0; }
    check_numbers "$sel" "$n"
    msg "Droits administrateur requis, lance toi-même :"
    for num in $sel; do
        i=$((10#$num - 1))
        msg "  sudo pkgutil --forget %s" "$(shq "${ids[$i]}")"
        case "${states[$i]}" in
            trace*) ;;
            *) msg "    (n'efface que la trace : les fichiers restent, utilise app-uninstall pour l'app)" ;;
        esac
    done
}

# --- mises à jour des apps -------------------------------------------------

# Dernière version annoncée par le flux Sparkle d'une app (accès réseau au serveur de l'app)
sparkle_latest() {
    # Seulement en https ; seules les versions faites de chiffres, lettres, . + - sont gardées
    case "$1" in https://*) ;; *) return 0 ;; esac
    curl -fsSL --proto '=https' --max-time 15 "$1" 2>/dev/null \
        | grep -oE "sparkle:shortVersionString=\"[^\"]+\"|<sparkle:shortVersionString>[^<]+" \
        | sed -E 's/^<?sparkle:shortVersionString(>|=")//; s/"$//' \
        | grep -E '^[0-9A-Za-z.+-]{1,40}$' | sort -V | tail -1
}

# 0 si la version $2 est plus récente que $1
is_newer() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]
}

updates_run() {
    local app name ver latest how token outdated seen=" " tokens=() n=0 num sel line
    export HOMEBREW_NO_AUTO_UPDATE=1
    command -v brew >/dev/null && outdated=$(brew outdated --cask --greedy --verbose 2>/dev/null)
    msg "Analyse en cours (les apps Sparkle sont interrogées sur internet)..."
    hdr "%3s  %-28s  %-14s  %-14s  %s\n" "N°" "App" "Installée" "Disponible" "Mise à jour par"
    for app in /Applications/*.app "$HOME/Applications"/*.app; do
        [ -d "$app" ] && [ ! -L "$app" ] || continue
        name=$(basename "$app" .app)
        ver=$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist" 2>/dev/null)
        latest="-"
        num=""
        token=$(cask_token "$app")
        if [ -n "$token" ]; then
            how="Homebrew"
            seen="$seen$token "
            latest=$(printf '%s\n' "${outdated:-}" | awk -v t="$token" '$1 == t { print $NF }')
            if [ -n "$latest" ]; then
                n=$((n + 1)); num=$n; tokens+=("$token")
            else
                latest=$(t "à jour")
            fi
        elif [ -d "$app/Contents/_MASReceipt" ]; then
            how=$(t "App Store (app App Store > Mises à jour)")
        elif line=$(defaults read "$app/Contents/Info" SUFeedURL 2>/dev/null); then
            how=$(t "Sparkle (menu de l'app)")
            latest=$(sparkle_latest "$line")
            if [ -z "$latest" ]; then latest="?"; elif ! is_newer "$ver" "$latest"; then latest=$(t "à jour"); fi
        else
            how=$(t "l'app elle-même")
        fi
        printf "%3s  %-28.28s  %-14.14s  %-14.14s  %s\n" "$num" "$name" "${ver:--}" "$latest" "$how"
    done
    # Casks Homebrew en retard sans app dans /Applications (ex : outils en ligne de commande)
    while IFS= read -r line; do
        token=${line%% *}
        [ -n "$token" ] || continue
        case "$seen" in *" $token "*) continue ;; esac
        n=$((n + 1)); tokens+=("$token")
        printf "%3s  %-28.28s  %-14.14s  %-14.14s  %s\n" "$n" "$token" \
            "$(echo "$line" | sed -n 's/.*(\(.*\)).*/\1/p')" "${line##* }" "Homebrew"
    done <<< "${outdated:-}"
    [ "$n" -gt 0 ] || { msg "Aucune mise à jour Homebrew à faire ici."; return 0; }
    ask "Numéros à mettre à jour avec Homebrew (vide = rien) : "
    read -r sel
    sel=${sel//,/ }
    [ -n "$sel" ] || { msg "Rien mis à jour."; return 0; }
    check_numbers "$sel" "$n"
    msg "Seront mis à jour :"
    for num in $sel; do
        echo "  - ${tokens[$((10#$num - 1))]}"
    done
    confirm
    for num in $sel; do
        token="${tokens[$((10#$num - 1))]}"
        if [ "$DRY_RUN" -eq 1 ]; then
            msg "[simulation] brew upgrade --cask %s" "$token"
            continue
        fi
        if brew upgrade --cask "$token"; then
            count=$((count + 1))
        else
            msg "Échec pour %s : lance « brew update » (index Homebrew périmé ?) puis réessaie." "$token"
        fi
    done
}

# --- retrait de la partie Intel des apps -----------------------------------

# Fichiers d'une app qui contiennent du code Intel et Apple (un par ligne)
universal_files() {
    local f a
    while IFS= read -r -d '' f; do
        a=" $(lipo -archs "$f" 2>/dev/null) "
        case "$a" in *" x86_64 "*) ;; *) continue ;; esac
        case "$a" in *" arm64 "*) printf '%s\n' "$f" ;; esac
    done < <(find "$1" -type f -perm +111 -print0 2>/dev/null)
}

# Taille en Ko de la partie Intel des fichiers reçus sur l'entrée
intel_kb() {
    local f s kb=0
    while IFS= read -r f; do
        s=$(lipo -detailed_info "$f" 2>/dev/null | awk '/^architecture x86_64/ { f = 1 } f && $1 == "size" { print $2; exit }')
        kb=$((kb + ${s:-0} / 1024))
    done
    echo "$kb"
}

lipo_app_run() {
    local apps=() gains=() app kb n=0 num backup f before after mode
    [ "$(uname -m)" = "arm64" ] || { msg "Ce Mac n'a pas de puce Apple : rien à retirer."; return 0; }
    msg "Analyse en cours..."
    # Apps qui t'appartiennent (les apps de l'App Store appartiennent à root)
    for app in /Applications/*.app "$HOME/Applications"/*.app; do
        [ -d "$app" ] && [ ! -L "$app" ] && [ -O "$app" ] || continue
        kb=$(universal_files "$app" | intel_kb)
        [ "$kb" -ge 1024 ] || continue
        n=$((n + 1))
        apps+=("$app")
        gains+=("$kb")
        printf "%3d  %9s  %s\n" "$n" "$(fmt_kb "$kb")" "$(basename "$app" .app)"
    done
    [ "$n" -gt 0 ] || { msg "Aucune app modifiable avec une partie Intel."; return 0; }
    echo
    msg "ATTENTION : l'app choisie sera modifiée et sa signature d'origine remplacée par une signature locale."
    msg "  - sa mise à jour automatique peut échouer ;"
    msg "  - macOS peut redemander des autorisations (trousseau, caméra, micro...) ;"
    msg "  - chaque mise à jour remet la version complète : le gain disparaît ;"
    msg "  - une copie de sauvegarde complète est mise dans la Corbeille avant toute modification."
    ask "Numéro de l'app (vide = rien) : "
    read -r num
    [ -n "$num" ] || { msg "Rien modifié."; return 0; }
    one_number "$num" "$n"
    app="${apps[$((NUM - 1))]}"
    offer_quit "$app" || { msg "%s est ouverte : rien fait." "$(basename "$app" .app)"; exit 1; }
    msg "Seront faits sur %s : sauvegarde dans la Corbeille, retrait de %s, signature locale." "$(basename "$app" .app)" "$(fmt_kb "${gains[$((NUM - 1))]}")"
    confirm
    if [ "$DRY_RUN" -eq 1 ]; then
        msg "[simulation] %s : rien modifié" "$(basename "$app" .app)"
        return 0
    fi
    backup="$HOME/.Trash/$(basename "$app" .app) (sauvegarde $(date +%Y%m%d-%H%M%S)).app"
    ditto "$app" "$backup" || { msg "Sauvegarde impossible : rien modifié."; return 1; }
    before=$(du -sk "$app" | cut -f1)
    while IFS= read -r f; do
        mode=$(stat -f %Lp "$f")
        lipo "$f" -thin arm64 -output "$f.arm64" && mv "$f.arm64" "$f" && chmod "$mode" "$f"
    done < <(universal_files "$app")
    # Les exigences d'origine (liées à l'éditeur) ne sont pas conservées : une signature locale ne peut pas les remplir
    if codesign --force --deep --preserve-metadata=entitlements,flags,runtime --sign - "$app" 2>/dev/null \
        && codesign --verify --deep --strict "$app" 2>/dev/null; then
        after=$(du -sk "$app" | cut -f1)
        count=$((count + 1))
        msg "Fait : %s -> %s." "$(fmt_kb "$before")" "$(fmt_kb "$after")"
        msg "Sauvegarde : %s (à remettre dans Applications si l'app pose problème)." "$backup"
    else
        msg "Échec de la signature : remise de la sauvegarde."
        rm -rf "$app" && ditto "$backup" "$app"
    fi
}

# --- caches et journaux utilisateur ----------------------------------------

# Identifiants (en minuscules) des apps ouvertes
running_ids() {
    lsappinfo list 2>/dev/null | sed -n 's/.*bundleID="\([^"]*\)".*/\1/p' | tr '[:upper:]' '[:lower:]' | sort -u
}

# Navigateurs installés : apps qui déclarent ouvrir les liens web (http/https)
installed_browsers() {
    local d app
    for d in $APP_DIRS; do
        for app in "$d"/*.app; do
            [ -d "$app" ] || continue
            plutil -extract CFBundleURLTypes json -o - "$app/Contents/Info.plist" 2>/dev/null \
                | grep -q '"https\{0,1\}"' && printf '%s\n' "$app"
        done
    done
}

# Dossiers de cache d'une app : ~/Library/Caches/<app> et cache de son conteneur
app_caches() {
    local p
    app_related_files "$1" | while IFS= read -r p; do
        case "$p" in
            "$HOME/Library/Caches/"*) printf '%s\n' "$p" ;;
            "$HOME/Library/Containers/"*) [ -d "$p/Data/Library/Caches" ] && printf '%s\n' "$p/Data/Library/Caches" ;;
        esac
    done
}

# Somme en Ko des chemins reçus sur l'entrée
sum_kb() {
    local p
    while IFS= read -r p; do
        [ -n "$p" ] && du -sk "$p" 2>/dev/null | cut -f1
    done | awk '{ s += $1 } END { print s + 0 }'
}

# Vide un chemin : contenu seul pour un dossier "Caches" de conteneur, élément entier sinon
clear_path() {
    is_excluded "$1" && { msg "Refusé (protégé par la liste d'exclusions) : %s" "$1"; return 1; }
    case "$1" in
        */Data/Library/Caches) empty_dir "$1" ;;
        "$HOME/Library/Caches/"*|"$HOME/Library/Logs/"*) rm -rf "$1" && count=$((count + 1)) ;;
    esac
}

# Prépare les 3 listes de user-clean : UC_LISTS, UC_LABELS, UC_SKIPPED (navigateurs restés ouverts)
user_clean_build() {
    local running app key p browsers="" all="" logs="" blist=()
    UC_SKIPPED=""
    # 1. Caches des navigateurs : proposition de fermer ceux qui sont ouverts
    while IFS= read -r app; do
        blist+=("$app")
    done < <(installed_browsers)
    offer_quit ${blist[@]+"${blist[@]}"} || true
    running=$(running_ids)
    for app in ${blist[@]+"${blist[@]}"}; do
        if app_is_running "$app"; then
            UC_SKIPPED="$UC_SKIPPED $(basename "$app" .app)"
        else
            browsers="$browsers$(app_caches "$app")"$'\n'
        fi
    done
    browsers=$(printf '%s' "$browsers" | grep -v '^$' | sort -u)
    # 2. Tous les caches, sauf ceux des apps ouvertes
    for p in "$HOME/Library/Caches"/* "$HOME/Library/Containers"/*/Data/Library/Caches; do
        [ -e "$p" ] || continue
        is_excluded "$p" && continue
        case "$p" in
            */Data/Library/Caches) key=$(entry_key "$(basename "${p%/Data/Library/Caches}")") ;;
            *) key=$(entry_key "$(basename "$p")") ;;
        esac
        key_matches "$key" "$running" && continue
        all="$all$p"$'\n'
    done
    # 3. Journaux
    for p in "$HOME/Library/Logs"/*; do
        [ -e "$p" ] && ! is_excluded "$p" && logs="$logs$p"$'\n'
    done
    UC_LISTS=("$browsers" "$all" "$logs")
    UC_LABELS=("$(t "Caches des navigateurs fermés")" "$(t "Tous les caches utilisateur (apps ouvertes exclues)")" "$(t "Journaux utilisateur")")
}

# Vide la liste n° $1 (0 à 2) préparée par user_clean_build
user_clean_apply() {
    local p
    if [ "$DRY_RUN" -eq 1 ]; then
        msg "[simulation] %s : %s élément(s)" "${UC_LABELS[$1]}" "$(printf '%s\n' "${UC_LISTS[$1]}" | grep -c .)"
        return 0
    fi
    while IFS= read -r p; do
        [ -n "$p" ] && clear_path "$p"
    done <<< "${UC_LISTS[$1]}"
}

user_clean_run() {
    local sel num i
    user_clean_build
    hdr "%3s  %9s  %s\n" "N°" "Taille" "Contenu"
    for i in 0 1 2; do
        printf "%3d  %9s  %s\n" $((i + 1)) "$(fmt_kb "$(printf '%s\n' "${UC_LISTS[$i]}" | sum_kb)")" "${UC_LABELS[$i]}"
    done
    [ -n "$UC_SKIPPED" ] && msg "Navigateurs ouverts, ignorés :%s" "$UC_SKIPPED"
    msg "Seul le cache est vidé : historique, mots de passe, cookies et marque-pages restent."
    ask "Numéros à vider (vide = rien) : "
    read -r sel
    sel=${sel//,/ }
    [ -n "$sel" ] || { msg "Rien vidé."; return 0; }
    check_numbers "$sel" 3
    msg "Seront vidés :"
    for num in $sel; do
        echo "  - ${UC_LABELS[$((10#$num - 1))]}"
    done
    confirm
    for num in $sel; do
        user_clean_apply $((10#$num - 1))
    done
}

# --- caches et journaux système --------------------------------------------

# Noms des journaux archivés par macOS (newsyslog) : compressés ou numérotés
ROTATED_NAMES="*.gz *.bz2 *.[0-9]"

# Journaux système archivés (un chemin par ligne)
rotated_logs() {
    local args=() n
    for n in $ROTATED_NAMES; do
        [ ${#args[@]} -gt 0 ] && args+=(-o)
        args+=(-name "$n")
    done
    find /private/var/log -type f \( "${args[@]}" \) 2>/dev/null
}

# Prépare les 3 éléments de system-clean : SC_LABELS et SC_CMDS (commandes à lancer avec sudo)
system_clean_cmds() {
    local n expr=""
    for n in $ROTATED_NAMES; do
        expr="$expr${expr:+ -o }-name '$n'"
    done
    SC_LABELS=("$(t "Caches système (/Library/Caches)")" "$(t "Rapports de plantage et journaux d'apps (/Library/Logs)")"
               "$(t "Journaux système archivés (/private/var/log, journaux en cours exclus)")")
    SC_CMDS=("find /Library/Caches -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
             "find /Library/Logs -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
             "find /private/var/log -type f \\( $expr \\) -delete")
}

# Taille en Ko des 3 éléments de system-clean, une par ligne
system_clean_kb() {
    du -sk /Library/Caches 2>/dev/null | cut -f1
    du -sk /Library/Logs 2>/dev/null | cut -f1
    rotated_logs | sum_kb
}

system_clean_run() {
    local sizes=() n sel num
    system_clean_cmds
    while IFS= read -r n; do
        sizes+=("$(fmt_kb "$n")")
    done < <(system_clean_kb)
    hdr "%3s  %9s  %s\n" "N°" "Taille" "Contenu"
    for n in 0 1 2; do
        printf "%3d  %9s  %s\n" $((n + 1)) "${sizes[$n]}" "${SC_LABELS[$n]}"
    done
    msg "(tailles lues sans droits administrateur : elles peuvent être sous-estimées)"
    ask "Numéros à vider (vide = rien) : "
    read -r sel
    sel=${sel//,/ }
    [ -n "$sel" ] || { msg "Rien vidé."; return 0; }
    check_numbers "$sel" 3
    msg "Droits administrateur requis, lance toi-même :"
    for num in $sel; do
        msg "  sudo %s" "${SC_CMDS[$((10#$num - 1))]}"
    done
}

# --- réseau ----------------------------------------------------------------

network_diag() {
    local line
    msg "Serveurs DNS :"
    scutil --dns 2>/dev/null | awk '/^resolver #1/ { r = 1; next } /^resolver/ { r = 0 } r && /nameserver\[/ { print "  - " $3 }' | sort -u
    msg "Proxy actifs :"
    line=$(scutil --proxy 2>/dev/null | awk '/Enable : 1/ { sub(/Enable.*/, ""); gsub(/ /, ""); print "  - " $0 }')
    echo "${line:-  - aucun}"
    msg "Entrées ajoutées dans /etc/hosts (hors réglages d'origine localhost et broadcasthost) :"
    line=$(grep -vE '^[[:space:]]*(#|$)' /etc/hosts | grep -vwE 'localhost|broadcasthost' | sed 's/^/  - /')
    echo "${line:-  - aucune}"
    msg "Extensions réseau actives :"
    line=$(systemextensionsctl list 2>/dev/null | grep 'activated enabled' | awk -F'\t' '{ print "  - " $5 }')
    echo "${line:-  - aucune}"
}

network_resolve() {
    local site
    command -v dig >/dev/null || { msg "dig absent."; return 0; }
    ask "Site à tester (vide = apple.com) : "
    read -r site
    site=${site:-apple.com}
    dig +noall +stats "$site" 2>/dev/null | sed -n "s/^;; Query time: /$(t "Temps de réponse : ")/p; s/^;; SERVER: \([^#]*\)#.*/$(t "Serveur DNS : ")\1/p"
    printf 'Adresse : %s\n' "$(dig +short "$site" 2>/dev/null | tail -1)"
}

network_run() {
    local sel num labels=()
    labels=("$(t "Vider le cache DNS (commande sudo affichée)")" "$(t "Diagnostic : DNS, proxy, /etc/hosts, extensions réseau")"
            "$(t "Test de résolution DNS d'un site")" "$(t "Test de débit (networkQuality, environ 20 s, utilise ta connexion)")")
    for num in 1 2 3 4; do
        printf "%3d  %s\n" "$num" "${labels[$((num - 1))]}"
    done
    ask "Numéros (ex : 2 3, vide = rien) : "
    read -r sel
    sel=${sel//,/ }
    [ -n "$sel" ] || { msg "Rien fait."; return 0; }
    check_numbers "$sel" 4
    for num in $sel; do
        echo "--- ${labels[$((10#$num - 1))]}"
        case "$((10#$num))" in
            1) msg "Droits administrateur requis, lance toi-même :"
               msg "  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder" ;;
            2) network_diag ;;
            3) network_resolve ;;
            4) networkQuality 2>&1 | grep -vE '^=+' | sed "s/^Uplink capacity/$(t "Débit montant")/; s/^Downlink capacity/$(t "Débit descendant")/;
                   s/^Responsiveness/$(t "Réactivité")/; s/^Idle Latency/$(t "Latence au repos")/" ;;
        esac
    done
}

# --- Time Machine ----------------------------------------------------------

TM_PREFS="/Library/Preferences/com.apple.TimeMachine"
TM_XATTR="com.apple.metadata:com_apple_backup_excludeItem"

# Point de montage de la destination (vide si le disque est débranché)
tm_dest() {
    tmutil destinationinfo 2>/dev/null | sed -n 's/^Mount Point *: //p' | head -1
}

# Dates des sauvegardes (AAAA-MM-JJ-HHMMSS), de la plus ancienne à la plus récente
tm_backups() {
    diskutil apfs listSnapshots "$1" 2>/dev/null | sed -n 's/.*Name: *com\.apple\.TimeMachine\.\(.*\)\.backup$/\1/p' | sort
}

# Monte une sauvegarde en lecture seule ($1 destination, $2 date, $3 point de montage) ; affiche son chemin
tm_mount() {
    local dev cur
    # Déjà montée par macOS (après une sauvegarde ou depuis le Finder) : on réutilise ce montage
    cur=$(mount | sed -n "s|^com\.apple\.TimeMachine\.$2\.backup@[^ ]* on \(.*\) (.*|\1|p" | head -1)
    if [ -n "$cur" ] && [ -d "$cur/$2.backup" ]; then
        printf '%s\n' "$cur/$2.backup"
        return 0
    fi
    dev=$(diskutil info "$1" 2>/dev/null | sed -n 's/^ *Device Identifier: *//p')
    mkdir -p "$3"
    mount_apfs -o rdonly,nobrowse -s "com.apple.TimeMachine.$2.backup" "/dev/$dev" "$3" 2>/dev/null && printf "%s/%s.backup\n" "$3" "$2"
}

# Éléments exclus : "réglages" (chemins fixés dans les réglages) ou "attribut" (exclusion posée sur l'élément)
tm_excluded() {
    local r
    defaults read "$TM_PREFS" SkipPaths 2>/dev/null | sed -n 's/^ *"\(.*\)",\{0,1\}$/\1/p' | sed 's/^/réglages\t/'
    for r in "$HOME" /opt /usr/local /Library; do
        find "$r" -maxdepth 6 -xattrname "$TM_XATTR" -prune -print 2>/dev/null
    done | sed 's/^/attribut\t/'
}

tm_status() {
    local dest list
    dest=$(tm_dest)
    msg "Destination : %s" "${dest:-aucune (disque débranché ?)}"
    # shellcheck disable=SC2046  # les trois tailles de df sont passées comme arguments distincts
    [ -n "$dest" ] && msg "Espace : %s utilisés sur %s, %s libres" $(df -h "$dest" | awk 'NR == 2 { print $3, $2, $4 }')
    if [ "$(defaults read "$TM_PREFS" AutoBackup 2>/dev/null)" = "1" ]; then
        msg "Sauvegarde automatique : active, toutes les %s min" "$(( $(defaults read "$TM_PREFS" AutoBackupInterval 2>/dev/null || echo 3600) / 60 ))"
    else
        msg "Sauvegarde automatique : désactivée"
    fi
    if [ -n "$dest" ]; then
        list=$(tm_backups "$dest")
        msg "Sauvegardes : %s (de %s à %s)" "$(printf '%s\n' "$list" | grep -c .)" "$(printf '%s\n' "$list" | head -1)" "$(printf '%s\n' "$list" | tail -1)"
    fi
    msg "Instantanés locaux : %s" "$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple.TimeMachine')"
    if tmutil status 2>/dev/null | grep -q 'Running = 1'; then msg "Sauvegarde en cours"; else msg "Aucune sauvegarde en cours"; fi
}

# 2 et 4 : liste des exclusions (les plus grosses), puis retrait éventuel
tm_exclusions_run() {
    local lines n=0 kb kind p paths=() kinds=() sel num i
    msg "Analyse en cours..."
    lines=$(tm_excluded | while IFS=$'\t' read -r kind p; do
                printf '%s\t%s\t%s\n' "$(du -sk "$p" 2>/dev/null | cut -f1)" "$kind" "$p"
            done | sort -rn)
    msg "%s exclusions ; les 30 plus grosses :" "$(printf '%s\n' "$lines" | grep -c .)"
    while IFS=$'\t' read -r kb kind p; do
        [ -n "$p" ] || continue
        n=$((n + 1))
        paths+=("$p")
        kinds+=("$kind")
        printf "%3d  %9s  %-9s  %s\n" "$n" "$(fmt_kb "${kb:-0}")" "$(t "$kind")" "${p/#$HOME/~}"
    done < <(printf '%s\n' "$lines" | head -30)
    [ "${1:-}" = "remove" ] || return 0
    ask "Numéros dont retirer l'exclusion (vide = rien) : "
    read -r sel
    sel=${sel//,/ }
    [ -n "$sel" ] || { msg "Rien changé."; return 0; }
    check_numbers "$sel" "$n"
    for num in $sel; do
        i=$((10#$num - 1))
        if [ "${kinds[$i]}" = "attribut" ] && tmutil removeexclusion "${paths[$i]}" 2>/dev/null; then
            count=$((count + 1))
            msg "Sera de nouveau sauvegardé : %s" "${paths[$i]}"
        else
            msg "Droits administrateur requis, lance toi-même : sudo tmutil removeexclusion -p %s" "$(shq "${paths[$i]}")"
        fi
    done
}

# Dossiers (niveau $2 sous $1) avec leur taille en Ko, une ligne "Ko<TAB>chemin"
tm_candidates() {
    du -k -d "$2" "$1" 2>/dev/null | awk -F'\t' -v b="$1/" -v d="$2" \
        'index($2, b) == 1 && split(substr($2, length(b) + 1), a, "/") == d'
}

# 3 : plus gros dossiers encore sauvegardés (exclusions déduites), puis exclusion au choix
tm_analyse_run() {
    local excl lines n=0 kb p paths=() sel num
    msg "Analyse en cours (une à quelques minutes)..."
    excl=$(tm_excluded | cut -f2 | while IFS= read -r p; do
               printf '%s\t%s\n' "$(du -sk "$p" 2>/dev/null | cut -f1)" "$p"
           done)
    # Un seul flux : lignes "E" (exclusions) puis lignes "C" (dossiers candidats)
    lines=$({ printf '%s\n' "$excl" | sed 's/^/E\t/'
              { tm_candidates "$HOME" 2; tm_candidates /Library 1; tm_candidates /opt 1
                tm_candidates /usr/local 1; tm_candidates /private/var 1; } | sed 's/^/C\t/'; } \
        | awk -F'\t' '
            $1 == "E" { if ($3 != "") ek[$3] = $2 + 0; next }
            { p = $3; kb = $2; skip = 0
              for (e in ek) {
                  if (p == e || index(p, e "/") == 1) { skip = 1; break }
                  if (index(e, p "/") == 1) kb -= ek[e]
              }
              if (!skip && kb > 0) print kb "\t" p }' | sort -rn | head -15)
    hdr "%3s  %9s  %s\n" "N°" "Taille" "Dossier encore sauvegardé"
    while IFS=$'\t' read -r kb p; do
        [ -n "$p" ] || continue
        n=$((n + 1))
        paths+=("$p")
        printf "%3d  %9s  %s\n" "$n" "$(fmt_kb "$kb")" "${p/#$HOME/~}"
    done <<< "$lines"
    ask "Numéros à exclure de Time Machine (vide = rien) : "
    read -r sel
    sel=${sel//,/ }
    [ -n "$sel" ] || { msg "Rien changé."; return 0; }
    check_numbers "$sel" "$n"
    for num in $sel; do
        p="${paths[$((10#$num - 1))]}"
        if tmutil addexclusion "$p" 2>/dev/null; then
            count=$((count + 1))
            msg "Exclu : %s" "${p/#$HOME/~}"
        else
            msg "Droits administrateur requis, lance toi-même : sudo tmutil addexclusion -p %s" "$(shq "$p")"
        fi
    done
}

# 6 et 7 : place propre de chaque sauvegarde (libérée si on la supprime), puis commandes de suppression
tm_unique_run() {
    local dest mnt b path kb n=0 dates=() sel num
    dest=$(tm_dest)
    [ -n "$dest" ] || { msg "Disque Time Machine débranché."; return 0; }
    mnt=$(mktemp -d)
    msg "Mesure de chaque sauvegarde..."
    hdr "%3s  %-19s  %s\n" "N°" "Sauvegarde" "Place propre"
    while IFS= read -r b; do
        path=$(tm_mount "$dest" "$b" "$mnt/s") || continue
        kb=$(tmutil uniquesize "$path" 2>/dev/null | awk '{ print $1 }')
        umount "$mnt/s" 2>/dev/null
        n=$((n + 1))
        dates+=("$b")
        printf "%3d  %-19s  %s\n" "$n" "$b" "${kb:-?}"
    done < <(tm_backups "$dest")
    rmdir "$mnt/s" "$mnt" 2>/dev/null
    [ "${1:-}" = "delete" ] || return 0
    msg "Instantanés locaux : %s (copies sur ton disque, retirées seules par macOS)" "$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple.TimeMachine')"
    ask "Numéros des sauvegardes à supprimer, ou l pour les instantanés locaux (vide = rien) : "
    read -r sel
    sel=${sel//,/ }
    [ -n "$sel" ] || { msg "Rien supprimé."; return 0; }
    msg "Droits administrateur requis, lance toi-même :"
    if [ "$sel" = "l" ]; then
        msg "  sudo tmutil deletelocalsnapshots /"
        return 0
    fi
    check_numbers "$sel" "$n"
    for num in $sel; do
        msg "  sudo tmutil delete -d %s -t %s" "$(shq "$dest")" "$(shq "${dates[$((10#$num - 1))]}")"
    done
}

# 8 : différences d'une sauvegarde avec la précédente
tm_compare_run() {
    local dest mnt dates=() n=0 b num old new out
    dest=$(tm_dest)
    [ -n "$dest" ] || { msg "Disque Time Machine débranché."; return 0; }
    while IFS= read -r b; do
        n=$((n + 1))
        dates+=("$b")
        printf "%3d  %s\n" "$n" "$b"
    done < <(tm_backups "$dest")
    [ "$n" -ge 2 ] || { msg "Il faut au moins deux sauvegardes."; return 0; }
    ask "Numéro de la sauvegarde à comparer avec la précédente (2 à %s, vide = rien) : " "$n"
    read -r num
    [ -n "$num" ] || { msg "Rien fait."; return 0; }
    one_number "$num" "$n"
    [ "$NUM" -ge 2 ] || { msg "La n° 1 n'a pas de précédente."; return 0; }
    mnt=$(mktemp -d)
    old=$(tm_mount "$dest" "${dates[$((NUM - 2))]}" "$mnt/a")
    new=$(tm_mount "$dest" "${dates[$((NUM - 1))]}" "$mnt/b")
    msg "Comparaison en cours (environ une minute)..."
    out=$(tmutil compare -s "$old" "$new" 2>/dev/null)
    umount "$mnt/a" "$mnt/b" 2>/dev/null
    rmdir "$mnt/a" "$mnt/b" "$mnt" 2>/dev/null
    printf '%s\n' "$out" | sed -n "s/^Added: */$(t "Ajouté : ")/p; s/^Removed: */$(t "Supprimé : ")/p; s/^Changed: */$(t "Modifié : ")/p"
    # Lignes "+ taille chemin" / "- taille chemin" : les 10 plus gros éléments ajoutés et supprimés
    for sign in "+" "-"; do
        if [ "$sign" = "+" ]; then msg "Plus gros ajouts :"; else msg "Plus grosses suppressions :"; fi
        printf '%s\n' "$out" | awk -v s="$sign" '
            $1 == s { u = substr($2, length($2)); v = $2 + 0
                      m = (u == "K") ? 1e3 : (u == "M") ? 1e6 : (u == "G") ? 1e9 : (u == "T") ? 1e12 : 1
                      p = substr($0, index($0, "/")); sub(/.*\.backup\/[^\/]*/, "", p)
                      printf "%015d\t%s\t%s\n", v * m, $2, p }' | sort -r | head -10 | cut -f2- | sed 's/^/  /; s/\t/  /'
    done
}

timemachine_run() {
    local sel num labels=()
    labels=("$(t "État : destination, espace, fréquence, sauvegardes, instantanés locaux")"
            "$(t "Liste des exclusions")"
            "$(t "Analyse : plus gros dossiers encore sauvegardés, puis exclusion au choix")"
            "$(t "Retirer une exclusion")"
            "$(t "Lancer une sauvegarde maintenant")"
            "$(t "Supprimer d'anciennes sauvegardes ou les instantanés locaux (commande sudo affichée)")"
            "$(t "Place propre de chaque sauvegarde (libérée si on la supprime)")"
            "$(t "Différences d'une sauvegarde avec la précédente")")
    for num in 1 2 3 4 5 6 7 8; do
        printf "%3d  %s\n" "$num" "${labels[$((num - 1))]}"
    done
    ask "Numéro (vide = rien) : "
    read -r sel
    [ -n "$sel" ] || { msg "Rien fait."; return 0; }
    one_number "$sel" 8
    case "$NUM" in
        1) tm_status ;;
        2) tm_exclusions_run ;;
        3) tm_analyse_run ;;
        4) tm_exclusions_run remove ;;
        5) tmutil startbackup && sleep 3 && tm_status | tail -1 ;;
        6) tm_unique_run delete ;;
        7) tm_unique_run ;;
        8) tm_compare_run ;;
    esac
}

# --- index Spotlight -------------------------------------------------------

spotlight_run() {
    local vols=() vol line state n=0 num
    hdr "%3s  %-28s  %s\n" "N°" "Disque" "État de l'index"
    # mdutil -s -a : une ligne "disque:" suivie d'une ligne d'état
    while IFS= read -r line; do
        case "$line" in
            /*:) vol="${line%:}" ;;
            *)
                [ -n "${vol:-}" ] || continue
                state=$(echo "$line" | sed 's/^[[:space:]]*//; s/Indexing enabled\./indexation active/; s/Indexing disabled\./indexation désactivée/; s/[[:space:]]*$//')
                n=$((n + 1))
                vols+=("$vol")
                printf "%3d  %-28s  %s\n" "$n" "$vol" "$(t "$state")"
                vol="" ;;
        esac
    done < <(mdutil -s -a 2>/dev/null)
    [ "$n" -gt 0 ] || { msg "Aucun disque trouvé."; return 0; }
    ask "Numéro du disque dont reconstruire l'index (vide = rien) : "
    read -r num
    [ -n "$num" ] || { msg "Rien fait."; return 0; }
    one_number "$num" "$n"
    msg "Droits administrateur requis, lance toi-même :"
    msg "  sudo mdutil -E %s" "$(shq "${vols[$((NUM - 1))]}")"
    msg "La reconstruction se fait en arrière-plan (de quelques minutes à une heure) ; la recherche est incomplète pendant ce temps."
}

# --- surveillance de la Corbeille ------------------------------------------

SENTINEL_LABEL="io.github.benjaminbusselet.core-eraser.sentinel"
SENTINEL_PLIST="$HOME/Library/LaunchAgents/$SENTINEL_LABEL.plist"

sentinel_on() {
    [ -f "$SENTINEL_PLIST" ] && { msg "Surveillance déjà active."; return 0; }
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$SENTINEL_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$SENTINEL_LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$SELF</string><string>sentinel-check</string></array>
  <key>WatchPaths</key>
  <array><string>$HOME/.Trash</string></array>
</dict>
</plist>
EOF
    launchctl bootstrap "gui/$(id -u)" "$SENTINEL_PLIST" && count=$((count + 1))
    msg "Surveillance de la Corbeille active."
}

sentinel_off() {
    [ -f "$SENTINEL_PLIST" ] || { msg "Surveillance déjà inactive."; return 0; }
    launchctl bootout "gui/$(id -u)/$SENTINEL_LABEL" 2>/dev/null
    trash_item "$SENTINEL_PLIST"
    msg "Surveillance de la Corbeille arrêtée."
}

# Lancé par launchd quand la Corbeille change : notifie, ne déplace et n'efface rien
sentinel_check() {
    local app files n kb msg b1 b2
    load_apps
    # Apps arrivées dans la Corbeille depuis moins de 2 minutes
    while IFS= read -r -d '' app; do
        # App encore installée ailleurs (ex : sauvegarde de lipo-app) : rien à signaler
        app_is_installed "$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist" 2>/dev/null | tr '[:upper:]' '[:lower:]')" && continue
        files=$(app_related_files "$app")
        [ -n "$files" ] || continue
        n=$(printf '%s\n' "$files" | wc -l | tr -d ' ')
        kb=$(printf '%s\n' "$files" | while IFS= read -r f; do du -sk "$f" 2>/dev/null | cut -f1; done | awk '{ s += $1 } END { print s + 0 }')
        msg=$(msg "%s est dans la Corbeille : %s fichier(s) lié(s) (%s) restent sur le disque." \
                  "$(basename "$app" .app)" "$n" "$(fmt_kb "$kb")")
        # shellcheck disable=SC1003  # retire les guillemets et barres obliques inverses du message
        msg=$(printf '%s' "$msg" | tr -d '"\\')
        echo "$msg"
        # Fenêtre qui reste jusqu'au clic ; le bouton ouvre « core-eraser orphans » dans Terminal
        b1=$(t "Plus tard")
        b2=$(t "Ouvrir dans Terminal")
        if osascript -e "display dialog \"$msg\" with title \"core-eraser\" buttons {\"$b1\", \"$b2\"} default button 2 with icon caution" 2>/dev/null \
            | grep -qF "$b2"; then
            osascript -e "tell application \"Terminal\" to do script \"$SELF orphans\"" \
                      -e 'tell application "Terminal" to activate' >/dev/null 2>&1
        fi
    done < <(find "$HOME/.Trash" -maxdepth 1 -name '*.app' -cmin -2 -print0 2>/dev/null)
}

# --- interface : menus et cases à cocher ------------------------------------
# Au clavier dans un vrai terminal ; par numéros sinon (tests, saisie redirigée).

# Dessine le menu à choix unique (MS_LABELS, ligne courante $cur)
ms_draw() {
    local i mark
    for i in "${!MS_LABELS[@]}"; do
        if [ "$i" -eq "$cur" ]; then mark=">"; else mark=" "; fi
        printf "\033[2K %s %s\n" "$mark" "${MS_LABELS[$i]}"
    done
    printf "\033[2K %s\n" "$(t "Flèches : se déplacer   Entrée : choisir   q : retour")"
}

# Menu à choix unique. Entrée : MS_LABELS. Sortie : MS_CHOICE (indice). Renvoie 1 pour revenir.
menu_select() {
    local key rest n=${#MS_LABELS[@]} cur=0 i
    if [ ! -t 0 ]; then
        for i in "${!MS_LABELS[@]}"; do
            printf "%3d  %s\n" $((i + 1)) "${MS_LABELS[$i]}"
        done
        ask "Numéro (vide = retour) : "
        read -r key || return 1
        [ -n "$key" ] || return 1
        one_number "$key" "$n"
        MS_CHOICE=$((NUM - 1))
        return 0
    fi
    printf "\033[?25l"
    ms_draw
    while IFS= read -rsn1 key; do
        # Touche fléchée : Échap [ A ou Échap [ B ; Échap seule = retour
        if [ "$key" = $'\033' ]; then
            read -rsn2 -t 1 rest || rest=""
            key="$key$rest"
        fi
        case "$key" in
            $'\033[A') cur=$(( (cur - 1 + n) % n )) ;;
            $'\033[B') cur=$(( (cur + 1) % n )) ;;
            "") MS_CHOICE=$cur; printf "\033[?25h"; return 0 ;;
            q|$'\033') printf "\033[?25h"; return 1 ;;
        esac
        printf "\033[%dA" $((n + 1))
        ms_draw
    done
    printf "\033[?25h"
    return 1
}

# Dessine les cases à cocher (CL_LABELS, CL_STATES, ligne courante $cur)
cl_draw() {
    local i box mark
    for i in "${!CL_LABELS[@]}"; do
        if [ "${CL_STATES[$i]}" -eq 1 ]; then box="[x]"; else box="[ ]"; fi
        if [ "$i" -eq "$cur" ]; then mark=">"; else mark=" "; fi
        printf "\033[2K %s %s  %s\n" "$mark" "$box" "${CL_LABELS[$i]}"
    done
    printf "\033[2K %s\n" "$(t "Flèches : se déplacer   Espace : cocher   d : par défaut   Entrée : exécuter   q : quitter")"
}

# Cases à cocher. Entrées : CL_LABELS, CL_DEFAULTS (0 ou 1). Sortie : CL_STATES. Renvoie 1 pour quitter.
checklist() {
    local key rest n=${#CL_LABELS[@]} cur=0 i
    CL_STATES=("${CL_DEFAULTS[@]}")
    if [ ! -t 0 ]; then
        while true; do
            for i in "${!CL_LABELS[@]}"; do
                if [ "${CL_STATES[$i]}" -eq 1 ]; then rest="[x]"; else rest="[ ]"; fi
                printf "%3d  %s  %s\n" $((i + 1)) "$rest" "${CL_LABELS[$i]}"
            done
            ask "Numéros à cocher/décocher, d = par défaut, e = exécuter, q = quitter : "
            read -r key || return 1
            case "$key" in
                e) return 0 ;;
                q) return 1 ;;
                d) CL_STATES=("${CL_DEFAULTS[@]}") ;;
                *) check_numbers "$key" "$n"
                   for i in $key; do
                       i=$((10#$i - 1))
                       CL_STATES[i]=$((1 - CL_STATES[i]))
                   done ;;
            esac
        done
    fi
    printf "\033[?25l"
    cl_draw
    while IFS= read -rsn1 key; do
        if [ "$key" = $'\033' ]; then
            read -rsn2 -t 1 rest || rest=""
            key="$key$rest"
        fi
        case "$key" in
            $'\033[A') cur=$(( (cur - 1 + n) % n )) ;;
            $'\033[B') cur=$(( (cur + 1) % n )) ;;
            " ") CL_STATES[cur]=$((1 - CL_STATES[cur])) ;;
            d) CL_STATES=("${CL_DEFAULTS[@]}") ;;
            "") printf "\033[?25h"; return 0 ;;
            q|$'\033') printf "\033[?25h"; return 1 ;;
        esac
        printf "\033[%dA" $((n + 1))
        cl_draw
    done
    printf "\033[?25h"
    return 1
}

# --- écran Maintenance -----------------------------------------------------

maintenance_run() {
    local i sudo_cmds=() vol
    CL_LABELS=("$(t "Caches des navigateurs fermés")" "$(t "Caches utilisateur (apps ouvertes exclues)")" "$(t "Journaux utilisateur")"
               "$(t "Caches de développement (npm, pip, Homebrew)")" "$(t "Cache DNS (sudo)")"
               "$(t "Index Spotlight du disque de données (sudo)")" "$(t "Caches et journaux système (sudo)")"
               "$(t "État de Time Machine")" "$(t "Sauvegarde Time Machine maintenant")")
    CL_DEFAULTS=(1 1 1 0 1 0 0 1 0)
    checklist || { msg "Annulé."; return 0; }
    msg "Seront exécutés :"
    for i in "${!CL_LABELS[@]}"; do
        [ "${CL_STATES[$i]}" -eq 1 ] && echo "  - ${CL_LABELS[$i]}"
    done
    confirm
    if [ "${CL_STATES[0]}${CL_STATES[1]}${CL_STATES[2]}" != "000" ]; then
        user_clean_build
        [ -n "$UC_SKIPPED" ] && msg "Navigateurs ouverts, ignorés :%s" "$UC_SKIPPED"
        for i in 0 1 2; do
            [ "${CL_STATES[$i]}" -eq 1 ] && user_clean_apply "$i"
        done
    fi
    [ "${CL_STATES[3]}" -eq 1 ] && dev_clean_all
    [ "${CL_STATES[4]}" -eq 1 ] && sudo_cmds+=("dscacheutil -flushcache" "killall -HUP mDNSResponder")
    if [ "${CL_STATES[5]}" -eq 1 ]; then
        vol=$(df "$HOME" | awk 'NR == 2 { print $NF }')
        sudo_cmds+=("mdutil -E $(shq "$vol")")
    fi
    if [ "${CL_STATES[6]}" -eq 1 ]; then
        system_clean_cmds
        sudo_cmds+=("${SC_CMDS[@]}")
    fi
    [ "${CL_STATES[7]}" -eq 1 ] && tm_status
    if [ "${CL_STATES[8]}" -eq 1 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then msg "[simulation] sauvegarde Time Machine"
        else tmutil startbackup && msg "Sauvegarde Time Machine lancée."; fi
    fi
    if [ ${#sudo_cmds[@]} -gt 0 ]; then
        msg "Droits administrateur requis : copie ces lignes dans le Terminal (mot de passe demandé une fois) :"
        for i in "${sudo_cmds[@]}"; do
            msg "  sudo %s" "$i"
        done
    fi
}

# --- mode api : piloté par l'app, sans aucune question ----------------------
# Sorties en colonnes séparées par des tabulations. Code de retour 2 : demande inconnue.
#   api list orphans|plugins|services|pkgs|apps|dev-caches|user-clean|system-clean|excludes|tm-backups
#   api list app-files <app>
#   api text tm-status|network-diag
#   api trash <chemin>...            api exclude-add <chemin>     api exclude-remove <chemin>
#   api user-clean <0|1|2>...        api dev-clean <nom>...       api version

api_list() {
    local d app p kb i name path
    case "${1:-}" in
        orphans) orphans_scan | sort -rn ;;
        plugins) load_apps; plugins_scan | sort -rn ;;
        services) load_apps; services_scan ;;
        pkgs) pkg_scan ;;
        apps)
            for d in /Applications "$HOME/Applications"; do
                for app in "$d"/*.app; do
                    [ -d "$app" ] && [ ! -L "$app" ] || continue
                    if app_is_running "$app"; then i=1; else i=0; fi
                    printf '%s\t%s\n' "$i" "$app"
                done
            done ;;
        app-files)
            [ -d "${2:-}" ] || return 2
            app_related_files "$2" | while IFS= read -r p; do
                printf '%s\t%s\n' "$(du -sk "$p" 2>/dev/null | cut -f1)" "$p"
            done ;;
        dev-caches)
            dev_caches | while IFS=$'\t' read -r name path; do
                [ -n "$path" ] && [ -d "$path" ] || continue
                printf '%s\t%s\t%s\n' "$(du -sk "$path" 2>/dev/null | cut -f1)" "$name" "$path"
            done ;;
        user-clean)
            user_clean_build
            for i in 0 1 2; do
                printf '%s\t%s\t%s\n' "$i" "$(printf '%s\n' "${UC_LISTS[$i]}" | sum_kb)" "${UC_LABELS[$i]}"
            done ;;
        system-clean)
            system_clean_cmds
            i=0
            while IFS= read -r kb; do
                printf '%s\t%s\t%s\tsudo %s\n' "$i" "${kb:-0}" "${SC_LABELS[$i]}" "${SC_CMDS[$i]}"
                i=$((i + 1))
            done < <(system_clean_kb) ;;
        excludes) exclude_entries ;;
        tm-backups) tm_backups "$(tm_dest)" ;;
        *) return 2 ;;
    esac
}

api_run() {
    local what="${1:-}" p rc=0 name path
    [ $# -gt 0 ] && shift
    case "$what" in
        list) api_list "$@" ;;
        text)
            case "${1:-}" in
                tm-status) tm_status ;;
                network-diag) network_diag ;;
                *) return 2 ;;
            esac ;;
        trash)
            for p in "$@"; do
                trash_item "$p" || rc=1
            done
            return "$rc" ;;
        exclude-add) exclude_add "${1:-}" ;;
        exclude-remove)
            [ -n "${1:-}" ] && [ -f "$EXCLUDE_FILE" ] || return 1
            exclude_remove_line "${1/#$HOME/~}" ;;
        user-clean)
            user_clean_build
            for p in "$@"; do
                case "$p" in 0|1|2) user_clean_apply "$p" ;; *) rc=2 ;; esac
            done
            return "$rc" ;;
        dev-clean)
            for p in "$@"; do
                path=$(dev_caches | awk -F'\t' -v n="$p" '$1 == n { print $2 }')
                if [ -n "$path" ] && [ -d "$path" ]; then dev_clean_item "$p" "$path"; else rc=2; fi
            done
            return "$rc" ;;
        version) printf '%s\n' "$VERSION" ;;
        *) return 2 ;;
    esac
}

# --- menu -----------------------------------------------------------------

# Catégories du menu principal ; chaque sous-menu liste "commande|libellé"
MENU_CATS=("Maintenance (cases à cocher)" "Applications" "Nettoyage" "Stockage et sauvegarde" "Réseau"
           "Claude Code" "Confidentialité" "Réglages de core-eraser")
MENU_1=("app-uninstall|Désinstaller une app et ses fichiers" "orphans|Restes d'apps supprimées"
        "updates|Mises à jour des apps" "brew-manage|Paquets et apps Homebrew" "plugins|Plug-ins et extensions"
        "services|Services au démarrage" "pkg-manage|Traces d'installations .pkg" "lipo-app|Retirer la partie Intel d'une app")
MENU_2=("user-clean|Caches et journaux de ton dossier perso" "dev-clean|Caches des outils de développement"
        "system-clean|Caches et journaux système")
MENU_3=("timemachine|Time Machine" "spotlight|Index Spotlight")
MENU_4=("network|Diagnostic et tests réseau")
MENU_5=("conv-list|Conversations : reprendre ou supprimer" "conv --all|Toutes les conversations à la Corbeille"
        "claude-cache|Vider les caches de Claude Code" "all|Tout : conversations, historique zsh, caches")
MENU_6=("zsh-history|Vider l'historique du terminal")
MENU_7=("exclude list|Éléments protégés : voir" "exclude add|Éléments protégés : ajouter"
        "exclude remove|Éléments protégés : retirer" "sentinel on|Surveillance de la Corbeille : activer"
        "sentinel off|Surveillance de la Corbeille : désactiver" "lang|Langue : English / Français")

menu() {
    local items=() entry words=()
    while true; do
        MS_LABELS=()
        for entry in "${MENU_CATS[@]}"; do
            MS_LABELS+=("$(t "$entry")")
        done
        msg "core-eraser : choisis une catégorie"
        menu_select || { msg "Au revoir."; exit 0; }
        case "$MS_CHOICE" in
            0) run maintenance; return ;;
            1) items=("${MENU_1[@]}") ;;
            2) items=("${MENU_2[@]}") ;;
            3) items=("${MENU_3[@]}") ;;
            4) items=("${MENU_4[@]}") ;;
            5) items=("${MENU_5[@]}") ;;
            6) items=("${MENU_6[@]}") ;;
            7) items=("${MENU_7[@]}") ;;
        esac
        MS_LABELS=()
        for entry in "${items[@]}"; do
            MS_LABELS+=("$(t "${entry#*|}")")
        done
        msg "%s :" "$(t "${MENU_CATS[$MS_CHOICE]}")"
        menu_select || continue
        entry="${items[$MS_CHOICE]}"
        read -r -a words <<< "${entry%%|*}"
        run "${words[@]}"
        return
    done
}


run() {
    # Pas de message pour la vérification lancée en arrière-plan par le service sentinel
    [ "$1" = "sentinel-check" ] || info_msg "$1"
    # Les commandes Claude Code exigent son dossier ; les autres fonctionnent sans
    case "$1" in
        conv-list|conv|claude-cache|all)
            [ -d "$CLAUDE_DIR" ] || { msg "Dossier introuvable : %s" "$CLAUDE_DIR"; exit 1; } ;;
    esac
    case "$1" in
        conv-list) warn_running; conv_menu ;;
        conv)
            [ $# -eq 2 ] && [ "$2" = "--all" ] || usage
            warn_running
            conv_all
            ;;
        zsh-history) zsh_history ;;
        claude-cache) warn_running; claude_cache ;;
        all) warn_running; clean_all ;;
        orphans) orphans_run ;;
        app-uninstall) app_uninstall_run ;;
        dev-clean) dev_clean_run ;;
        brew-manage) brew_manage_run ;;
        plugins) plugins_run ;;
        services) services_run ;;
        pkg-manage) pkg_manage_run ;;
        updates) updates_run ;;
        lipo-app) lipo_app_run ;;
        sentinel)
            case "${2:-}" in
                on) sentinel_on ;;
                off) sentinel_off ;;
                *) usage ;;
            esac ;;
        sentinel-check) sentinel_check ;;
        spotlight) spotlight_run ;;
        user-clean) user_clean_run ;;
        system-clean) system_clean_run ;;
        network) network_run ;;
        exclude) exclude_run "${2:-}" "${3:-}" ;;
        timemachine) timemachine_run ;;
        maintenance) maintenance_run ;;
        lang) lang_run "${2:-}" ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
    case "$count" in
        0) msg "Terminé." ;;
        1) msg "Terminé (1 élément traité)." ;;
        *) msg "Terminé (%s éléments traités)." "$count" ;;
    esac
}

if [ "${1:-}" = "--version" ]; then
    printf 'core-eraser %s\n' "$VERSION"
    exit 0
fi

# --- catalogue des traductions (français -> anglais), séparées par une tabulation ---

i18n_catalog() {
    cat <<'EOF'
core-eraser : entretien d'un Mac en ligne de commande. Sans argument : menu au clavier.	core-eraser: command-line maintenance for a Mac. Without arguments: keyboard menu.
Maintenance	Maintenance
  maintenance       : cases à cocher (caches, journaux, DNS, Spotlight, Time Machine), exécution en une fois	  maintenance       : checkboxes (caches, logs, DNS, Spotlight, Time Machine), run all at once
Applications	Applications
  app-uninstall     : choix d'une app, puis mise à la Corbeille de l'app et de ses fichiers	  app-uninstall     : pick an app, then move the app and its files to the Trash
  orphans           : restes d'apps supprimées, puis choix de les mettre à la Corbeille ou de les protéger	  orphans           : leftovers of deleted apps, then trash or protect them
  updates           : versions des apps et mode de mise à jour, mise à jour Homebrew (internet pour Sparkle)	  updates           : app versions and how they update, Homebrew updates (internet for Sparkle)
  brew-manage       : paquets et apps Homebrew (taille, mises à jour), désinstallation, dépendances inutiles	  brew-manage       : Homebrew packages and apps (size, updates), uninstall, unused dependencies
  plugins           : plug-ins et extensions installés (app d'origine présente ou non), puis retrait	  plugins           : installed plug-ins and extensions (parent app present or not), then removal
  services          : services lancés au démarrage (programme, état, app d'origine), arrêt et retrait	  services          : startup services (program, state, parent app), stop and removal
  pkg-manage        : traces d'installations .pkg, fichiers restants, commande pour effacer une trace	  pkg-manage        : .pkg install receipts, remaining files, command to forget a receipt
  lipo-app          : retire la partie Intel d'une app (sauvegarde, signature locale, avertissement)	  lipo-app          : strip the Intel part of an app (backup, local signature, warning)
Nettoyage	Cleanup
  user-clean        : caches des navigateurs, caches et journaux de ton dossier perso	  user-clean        : browser caches, caches and logs in your home folder
  dev-clean         : caches des outils de développement installés (npm, pip, Homebrew, Xcode)	  dev-clean         : caches of installed developer tools (npm, pip, Homebrew, Xcode)
  system-clean      : caches et journaux système (tailles), commandes sudo pour les vider	  system-clean      : system caches and logs (sizes), sudo commands to empty them
Stockage et sauvegarde	Storage and backup
  timemachine       : état, exclusions, analyse, sauvegarde, place de chaque sauvegarde, différences	  timemachine       : status, exclusions, analysis, backup, size of each backup, differences
  spotlight         : état de l'index Spotlight, commande sudo pour le reconstruire	  spotlight         : Spotlight index status, sudo command to rebuild it
Réseau	Network
  network           : diagnostic, test DNS, test de débit, commande sudo pour vider le cache DNS	  network           : diagnostics, DNS test, speed test, sudo command to flush the DNS cache
Claude Code (à lancer avec Claude Code fermé)	Claude Code (run with Claude Code closed)
  conv-list         : conversations, puis reprise ou mise à la Corbeille	  conv-list         : conversations, then resume or move to the Trash
  conv --all        : toutes les conversations à la Corbeille	  conv --all        : all conversations to the Trash
  claude-cache      : vide cache/, debug/, backups/ et le dossier temporaire de Claude Code	  claude-cache      : empty cache/, debug/, backups/ and the Claude Code temporary folder
  all               : conv --all + zsh-history + claude-cache (une seule confirmation)	  all               : conv --all + zsh-history + claude-cache (single confirmation)
Confidentialité	Privacy
  zsh-history       : historique du terminal à la Corbeille, remplacé par un historique vide	  zsh-history       : terminal history to the Trash, replaced by an empty history
Réglages de core-eraser	core-eraser settings
  exclude [list|add <chemin>|remove <N>] : éléments protégés, jamais signalés ni déplacés	  exclude [list|add <path>|remove <N>] : protected items, never reported or moved
  sentinel on|off   : surveille la Corbeille et signale les fichiers liés aux apps qu'on y jette	  sentinel on|off   : watch the Trash and report files left by apps thrown into it
  lang [en|fr]      : langue de core-eraser (anglais par défaut)	  lang [en|fr]      : core-eraser language (English by default)
Option	Option
  --dry-run <cmd>   : simulation, rien n'est modifié	  --dry-run <cmd>   : simulation, nothing is changed
  --version         : version de core-eraser	  --version         : core-eraser version
oui	yes
Confirmer ? (oui/non) 	Confirm? (yes/no) 
Annulé.	Cancelled.
Attention : un processus Claude Code semble actif. Ferme-le avant de continuer.	Warning: a Claude Code process seems to be running. Close it before continuing.
Numéro invalide : %s	Invalid number: %s
Un seul numéro.	One number only.
Go	GB
Mo	MB
Langue : français	Language: English
# Liste d'exclusions de core-eraser : un chemin par ligne.	# core-eraser exclusion list: one path per line.
# Un dossier exclu protège aussi tout ce qu'il contient. Les jokers * sont acceptés.	# An excluded folder also protects everything inside it. Wildcards * are accepted.
# Ces éléments ne sont jamais signalés ni déplacés par core-eraser.	# These items are never reported or moved by core-eraser.
Chemin manquant.	Missing path.
Déjà protégé : %s	Already protected: %s
Attention, ce chemin n'existe pas (ajouté quand même) : %s	Warning, this path does not exist (added anyway): %s
Protégé : %s	Protected: %s
Aucune exclusion.	No exclusions.
Toujours protégé : %s	Always protected: %s
Chemin à protéger (glisser-déposer accepté) : 	Path to protect (drag and drop accepted): 
Numéro à retirer (vide = rien) : 	Number to remove (empty = nothing): 
Rien retiré.	Nothing removed.
Retiré : %s	Removed: %s
Refusé (protégé par la liste d'exclusions) : %s	Refused (protected by the exclusion list): %s
Introuvable : %s	Not found: %s
[simulation] %s -> Corbeille	[simulation] %s -> Trash
Aucune conversation.	No conversations.
jq requis pour la liste.	jq is required for the list.
N°	No.
Projet	Project
Résumé	Summary
r N = resume, d N N = delete (vide = annuler) : 	r N = resume, d N N = delete (empty = cancel): 
resume : un seul numéro.	resume: one number only.
Dossier d'origine introuvable : %s	Original folder not found: %s
Conversations à supprimer : %s	Conversations to delete: %s
Info : ces commandes lisent l'organisation interne de %s, vérifiée avec Claude Code %s.	Info: these commands read the internal layout of %s, checked with Claude Code %s.
Attention : ta version est %s. Si elle a changé cette organisation, des fichiers pourraient être mal visés.	Warning: your version is %s. If it changed this layout, the wrong files could be targeted.
Les conversations et historiques vont à la Corbeille ; les caches sont supprimés directement.	Conversations and histories go to the Trash; caches are deleted directly.
Info : %s	Info: %s
Mode simulation : rien ne sera modifié.	Simulation mode: nothing will be changed.
Dossier : %s	Folder: %s
Seront mis à la Corbeille :	Will be moved to the Trash:
  - projects/* : dossiers de projet complets (memory/ compris)	  - projects/*: full project folders (memory/ included)
Id invalide : %s	Invalid id: %s
Aucune conversation trouvée pour : %s	No conversation found for: %s
Conversation : %s	Conversation: %s
Seront mis à la Corbeille (dossier temporaire : supprimé directement) :	Will be moved to the Trash (temporary folder: deleted directly):
  - sous-agents : %s	  - subagents: %s
  - history.jsonl : %s ligne(s)	  - history.jsonl: %s line(s)
Seront mis à la Corbeille, puis remplacés par un historique vide :	Will be moved to the Trash, then replaced by an empty history:
Ferme les autres terminaux avant : chaque shell ouvert réécrit son historique en quittant.	Close other terminals first: each open shell rewrites its history when it exits.
Seront vidés définitivement (caches, recréés par Claude Code) :	Will be emptied permanently (caches, recreated by Claude Code):
Seront traités : toutes les conversations Claude et l'historique zsh (Corbeille), les caches Claude (supprimés).	Will be processed: all Claude conversations and the zsh history (Trash), the Claude caches (deleted).
(à vérifier)	(to check)
Analyse en cours...	Analyzing...
Aucun reste détecté.	No leftovers found.
Taille	Size
Dossier	Folder
Nom	Name
Numéros à mettre à la Corbeille, ou x suivi des numéros à protéger (ex : 1 3 ou x 2, vide = rien) : 	Numbers to move to the Trash, or x followed by numbers to protect (e.g. 1 3 or x 2, empty = nothing): 
Rien déplacé.	Nothing moved.
Apps ouvertes :	Open apps:
Les fermer maintenant ? (oui/non) 	Quit them now? (yes/no) 
Toujours ouvertes (une fenêtre attend peut-être ta réponse) :%s	Still open (a window may be waiting for your answer):%s
Aucune app trouvée.	No apps found.
Numéro de l'app à désinstaller (vide = rien) : 	Number of the app to uninstall (empty = nothing): 
%s est ouverte : rien fait.	%s is open: nothing done.
  Total : %s	  Total: %s
Installée par Homebrew : lance aussi « brew uninstall --cask %s » ensuite.	Installed by Homebrew: also run "brew uninstall --cask %s" afterwards.
[simulation] %s : cache vidé	[simulation] %s: cache emptied
  %s : %s restant	  %s: %s left
Aucun cache trouvé.	No caches found.
(Homebrew retire aussi les anciennes versions des paquets installés)	(Homebrew also removes old versions of installed packages)
Numéros à vider (ex : 1 3, vide = rien) : 	Numbers to empty (e.g. 1 3, empty = nothing): 
Rien vidé.	Nothing emptied.
Seront vidés :	Will be emptied:
Homebrew n'est pas installé.	Homebrew is not installed.
État	State
à jour	up to date
mise à jour disponible	update available
Rien d'installé avec Homebrew.	Nothing installed with Homebrew.
Dépendances devenues inutiles : %s	Dependencies no longer needed: %s
Dépendances devenues inutiles : aucune	Dependencies no longer needed: none
Numéros à désinstaller, ou d pour retirer les dépendances inutiles (vide = rien) : 	Numbers to uninstall, or d to remove unused dependencies (empty = nothing): 
Rien désinstallé.	Nothing uninstalled.
Aucune dépendance à retirer.	No dependencies to remove.
Seront retirées : %s	Will be removed: %s
Seront désinstallés :	Will be uninstalled:
[simulation] désinstallation de %s	[simulation] uninstalling %s
app présente	app present
même éditeur qu'une app	same developer as an app
app absente	app missing
Aucun module trouvé.	No modules found.
App d'origine	Parent app
Numéros à retirer (vide = rien) : 	Numbers to remove (empty = nothing): 
Seront retirés :	Will be removed:
Extension système, à retirer dans Réglages Système > Général > Ouverture et extensions : %s	System extension, remove it in System Settings > General > Login Items & Extensions: %s
Droits administrateur requis, lance toi-même : sudo mv %s %s	Administrator rights required, run it yourself: sudo mv %s %s
fichier invalide (ignoré)	invalid file (ignored)
programme présent	program present
programme manquant	program missing
Aucun service tiers.	No third-party services.
Programme	Program
Seront arrêtés et retirés :	Will be stopped and removed:
[simulation] arrêt de %s	[simulation] stopping %s
Droits administrateur requis, lance toi-même :	Administrator rights required, run it yourself:
Aucun paquet tiers.	No third-party packages.
Paquet	Package
Installé	Installed
Fichiers	Files
Numéros dont effacer la trace (vide = rien) : 	Numbers whose receipt to forget (empty = nothing): 
Rien effacé.	Nothing forgotten.
    (n'efface que la trace : les fichiers restent, utilise app-uninstall pour l'app)	    (only forgets the receipt: files stay, use app-uninstall for the app)
Analyse en cours (les apps Sparkle sont interrogées sur internet)...	Analyzing (Sparkle apps are checked over the internet)...
Installée	Installed
Disponible	Available
Mise à jour par	Updated by
App Store (app App Store > Mises à jour)	App Store (App Store app > Updates)
Sparkle (menu de l'app)	Sparkle (app menu)
l'app elle-même	the app itself
Aucune mise à jour Homebrew à faire ici.	No Homebrew updates to do here.
Numéros à mettre à jour avec Homebrew (vide = rien) : 	Numbers to update with Homebrew (empty = nothing): 
Rien mis à jour.	Nothing updated.
Seront mis à jour :	Will be updated:
Échec pour %s : lance « brew update » (index Homebrew périmé ?) puis réessaie.	Failed for %s: run "brew update" (outdated Homebrew index?) then try again.
Ce Mac n'a pas de puce Apple : rien à retirer.	This Mac has no Apple chip: nothing to strip.
Aucune app modifiable avec une partie Intel.	No modifiable app with an Intel part.
ATTENTION : l'app choisie sera modifiée et sa signature d'origine remplacée par une signature locale.	WARNING: the chosen app will be modified and its original signature replaced by a local signature.
  - sa mise à jour automatique peut échouer ;	  - its automatic updates may fail;
  - macOS peut redemander des autorisations (trousseau, caméra, micro...) ;	  - macOS may ask for permissions again (keychain, camera, microphone...);
  - chaque mise à jour remet la version complète : le gain disparaît ;	  - each update restores the full version: the gain disappears;
  - une copie de sauvegarde complète est mise dans la Corbeille avant toute modification.	  - a full backup copy is put in the Trash before any change.
Numéro de l'app (vide = rien) : 	App number (empty = nothing): 
Rien modifié.	Nothing changed.
Seront faits sur %s : sauvegarde dans la Corbeille, retrait de %s, signature locale.	Will be done on %s: backup to the Trash, removal of %s, local signature.
[simulation] %s : rien modifié	[simulation] %s: nothing changed
Sauvegarde impossible : rien modifié.	Backup failed: nothing changed.
Fait : %s -> %s.	Done: %s -> %s.
Sauvegarde : %s (à remettre dans Applications si l'app pose problème).	Backup: %s (put it back in Applications if the app misbehaves).
Échec de la signature : remise de la sauvegarde.	Signing failed: restoring the backup.
Caches des navigateurs fermés	Caches of closed browsers
Tous les caches utilisateur (apps ouvertes exclues)	All user caches (open apps excluded)
Journaux utilisateur	User logs
[simulation] %s : %s élément(s)	[simulation] %s: %s item(s)
Contenu	Content
Navigateurs ouverts, ignorés :%s	Open browsers, skipped:%s
Seul le cache est vidé : historique, mots de passe, cookies et marque-pages restent.	Only the cache is emptied: history, passwords, cookies and bookmarks stay.
Numéros à vider (vide = rien) : 	Numbers to empty (empty = nothing): 
Caches système (/Library/Caches)	System caches (/Library/Caches)
Rapports de plantage et journaux d'apps (/Library/Logs)	Crash reports and app logs (/Library/Logs)
Journaux système archivés (/private/var/log, journaux en cours exclus)	Archived system logs (/private/var/log, current logs excluded)
(tailles lues sans droits administrateur : elles peuvent être sous-estimées)	(sizes read without administrator rights: they may be underestimated)
Serveurs DNS :	DNS servers:
Proxy actifs :	Active proxies:
Entrées ajoutées dans /etc/hosts (hors réglages d'origine localhost et broadcasthost) :	Entries added to /etc/hosts (besides the default localhost and broadcasthost):
Extensions réseau actives :	Active network extensions:
dig absent.	dig is missing.
Site à tester (vide = apple.com) : 	Site to test (empty = apple.com): 
Temps de réponse : 	Response time: 
Serveur DNS : 	DNS server: 
Vider le cache DNS (commande sudo affichée)	Flush the DNS cache (sudo command shown)
Diagnostic : DNS, proxy, /etc/hosts, extensions réseau	Diagnostics: DNS, proxy, /etc/hosts, network extensions
Test de résolution DNS d'un site	DNS resolution test for a site
Test de débit (networkQuality, environ 20 s, utilise ta connexion)	Speed test (networkQuality, about 20 s, uses your connection)
Numéros (ex : 2 3, vide = rien) : 	Numbers (e.g. 2 3, empty = nothing): 
Rien fait.	Nothing done.
Débit montant	Upload capacity
Débit descendant	Download capacity
Réactivité	Responsiveness
Latence au repos	Idle latency
Destination : %s	Destination: %s
Espace : %s utilisés sur %s, %s libres	Space: %s used of %s, %s free
Sauvegarde automatique : active, toutes les %s min	Automatic backup: on, every %s min
Sauvegarde automatique : désactivée	Automatic backup: off
Sauvegardes : %s (de %s à %s)	Backups: %s (from %s to %s)
Instantanés locaux : %s	Local snapshots: %s
Sauvegarde en cours	Backup in progress
Aucune sauvegarde en cours	No backup in progress
%s exclusions ; les 30 plus grosses :	%s exclusions; the 30 largest:
Numéros dont retirer l'exclusion (vide = rien) : 	Numbers whose exclusion to remove (empty = nothing): 
Rien changé.	Nothing changed.
Sera de nouveau sauvegardé : %s	Will be backed up again: %s
Droits administrateur requis, lance toi-même : sudo tmutil removeexclusion -p %s	Administrator rights required, run it yourself: sudo tmutil removeexclusion -p %s
Analyse en cours (une à quelques minutes)...	Analyzing (one to a few minutes)...
Dossier encore sauvegardé	Folder still backed up
Numéros à exclure de Time Machine (vide = rien) : 	Numbers to exclude from Time Machine (empty = nothing): 
Exclu : %s	Excluded: %s
Droits administrateur requis, lance toi-même : sudo tmutil addexclusion -p %s	Administrator rights required, run it yourself: sudo tmutil addexclusion -p %s
Disque Time Machine débranché.	Time Machine disk disconnected.
Mesure de chaque sauvegarde...	Measuring each backup...
Sauvegarde	Backup
Place propre	Own size
Instantanés locaux : %s (copies sur ton disque, retirées seules par macOS)	Local snapshots: %s (copies on your disk, removed automatically by macOS)
Numéros des sauvegardes à supprimer, ou l pour les instantanés locaux (vide = rien) : 	Numbers of the backups to delete, or l for local snapshots (empty = nothing): 
Rien supprimé.	Nothing deleted.
Numéro de la sauvegarde à comparer avec la précédente (2 à %s, vide = rien) : 	Number of the backup to compare with the previous one (2 to %s, empty = nothing): 
Il faut au moins deux sauvegardes.	At least two backups are needed.
La n° 1 n'a pas de précédente.	No. 1 has no previous backup.
Comparaison en cours (environ une minute)...	Comparing (about one minute)...
Ajouté : 	Added: 
Supprimé : 	Removed: 
Modifié : 	Changed: 
Plus gros ajouts :	Largest additions:
Plus grosses suppressions :	Largest removals:
État : destination, espace, fréquence, sauvegardes, instantanés locaux	Status: destination, space, frequency, backups, local snapshots
Liste des exclusions	Exclusion list
Analyse : plus gros dossiers encore sauvegardés, puis exclusion au choix	Analysis: largest folders still backed up, then optional exclusion
Retirer une exclusion	Remove an exclusion
Lancer une sauvegarde maintenant	Start a backup now
Supprimer d'anciennes sauvegardes ou les instantanés locaux (commande sudo affichée)	Delete old backups or local snapshots (sudo command shown)
Place propre de chaque sauvegarde (libérée si on la supprime)	Own size of each backup (freed if deleted)
Différences d'une sauvegarde avec la précédente	Differences between a backup and the previous one
Numéro (vide = rien) : 	Number (empty = nothing): 
Disque	Disk
État de l'index	Index state
Aucun disque trouvé.	No disks found.
Numéro du disque dont reconstruire l'index (vide = rien) : 	Number of the disk whose index to rebuild (empty = nothing): 
La reconstruction se fait en arrière-plan (de quelques minutes à une heure) ; la recherche est incomplète pendant ce temps.	The rebuild runs in the background (from a few minutes to an hour); search is incomplete meanwhile.
Surveillance déjà active.	Monitoring already on.
Surveillance de la Corbeille active.	Trash monitoring on.
Surveillance déjà inactive.	Monitoring already off.
Surveillance de la Corbeille arrêtée.	Trash monitoring stopped.
%s est dans la Corbeille : %s fichier(s) lié(s) (%s) restent sur le disque.	%s is in the Trash: %s related file(s) (%s) remain on disk.
Plus tard	Later
Ouvrir dans Terminal	Open in Terminal
Flèches : se déplacer   Entrée : choisir   q : retour	Arrows: move   Enter: choose   q: back
Numéro (vide = retour) : 	Number (empty = back): 
Flèches : se déplacer   Espace : cocher   d : par défaut   Entrée : exécuter   q : quitter	Arrows: move   Space: check   d: defaults   Enter: run   q: quit
Numéros à cocher/décocher, d = par défaut, e = exécuter, q = quitter : 	Numbers to check/uncheck, d = defaults, e = run, q = quit: 
Caches utilisateur (apps ouvertes exclues)	User caches (open apps excluded)
Caches de développement (npm, pip, Homebrew)	Developer caches (npm, pip, Homebrew)
Cache DNS (sudo)	DNS cache (sudo)
Index Spotlight du disque de données (sudo)	Spotlight index of the data disk (sudo)
Caches et journaux système (sudo)	System caches and logs (sudo)
État de Time Machine	Time Machine status
Sauvegarde Time Machine maintenant	Time Machine backup now
Seront exécutés :	Will be run:
[simulation] sauvegarde Time Machine	[simulation] Time Machine backup
Sauvegarde Time Machine lancée.	Time Machine backup started.
Droits administrateur requis : copie ces lignes dans le Terminal (mot de passe demandé une fois) :	Administrator rights required: paste these lines into Terminal (password asked once):
core-eraser : choisis une catégorie	core-eraser: choose a category
Au revoir.	Goodbye.
%s :	%s:
Terminé.	Done.
Terminé (1 élément traité).	Done (1 item processed).
Terminé (%s éléments traités).	Done (%s items processed).
Dossier introuvable : %s	Folder not found: %s
Maintenance (cases à cocher)	Maintenance (checkboxes)
Désinstaller une app et ses fichiers	Uninstall an app and its files
Restes d'apps supprimées	Leftovers of deleted apps
Mises à jour des apps	App updates
Paquets et apps Homebrew	Homebrew packages and apps
Plug-ins et extensions	Plug-ins and extensions
Services au démarrage	Startup services
Traces d'installations .pkg	.pkg install receipts
Retirer la partie Intel d'une app	Strip the Intel part of an app
Caches et journaux de ton dossier perso	Caches and logs in your home folder
Caches des outils de développement	Developer tool caches
Caches et journaux système	System caches and logs
Index Spotlight	Spotlight index
Diagnostic et tests réseau	Network diagnostics and tests
Conversations : reprendre ou supprimer	Conversations: resume or delete
Toutes les conversations à la Corbeille	All conversations to the Trash
Vider les caches de Claude Code	Empty the Claude Code caches
Tout : conversations, historique zsh, caches	Everything: conversations, zsh history, caches
Vider l'historique du terminal	Clear the terminal history
Éléments protégés : voir	Protected items: view
Éléments protégés : ajouter	Protected items: add
Éléments protégés : retirer	Protected items: remove
Surveillance de la Corbeille : activer	Trash monitoring: turn on
Surveillance de la Corbeille : désactiver	Trash monitoring: turn off
Langue : English / Français	Language: English / Français
coche les opérations d'entretien voulues, puis exécute-les en une fois. Celles qui demandent sudo sont regroupées à la fin, à lancer toi-même.	check the maintenance tasks you want, then run them all at once. Those needing sudo are grouped at the end, for you to run.
vide l'historique des commandes du terminal (confidentialité), sans lien avec Claude Code. L'ancien historique va à la Corbeille.	clears the terminal command history (privacy), unrelated to Claude Code. The old history goes to the Trash.
cherche dans ~/Library les fichiers laissés par des apps supprimées. Rien n'est déplacé sans ton choix ; les éléments choisis vont à la Corbeille.	looks in ~/Library for files left by deleted apps. Nothing is moved without your choice; chosen items go to the Trash.
met une app et ses fichiers liés (réglages, caches, données) à la Corbeille. Si l'app est ouverte, core-eraser propose de la fermer.	moves an app and its related files (settings, caches, data) to the Trash. If the app is open, core-eraser offers to quit it.
vide les caches des outils de développement avec leurs propres commandes. Ils se recréent au besoin ; rien ne va à la Corbeille.	empties developer tool caches with their own commands. They are recreated when needed; nothing goes to the Trash.
liste ce que tu as installé avec Homebrew. Les désinstallations passent par Homebrew : définitives, mais réinstallables.	lists what you installed with Homebrew. Uninstalls go through Homebrew: permanent, but reinstallable.
liste les modules et extensions installés, et indique si leur app existe encore. Ceux de /Library demandent une commande sudo affichée.	lists installed modules and extensions, and whether their app still exists. Those in /Library need a sudo command, which is shown.
liste les services lancés au démarrage (hors Apple). Les retirer les arrête ; ceux de /Library demandent une commande sudo affichée.	lists startup services (non-Apple). Removing them stops them; those in /Library need a sudo command, which is shown.
liste les traces laissées par les installations .pkg. Effacer une trace demande sudo et ne supprime pas l'app.	lists the receipts left by .pkg installs. Forgetting a receipt needs sudo and does not delete the app.
compare les versions installées aux dernières disponibles. Les apps Sparkle sont interrogées sur internet ; seules les apps Homebrew se mettent à jour d'ici.	compares installed versions with the latest available. Sparkle apps are checked over the internet; only Homebrew apps update from here.
retire la partie Intel d'une app pour gagner de la place. Un avertissement détaillé s'affiche avant le choix.	strips the Intel part of an app to save space. A detailed warning is shown before you choose.
surveille la Corbeille et signale les fichiers laissés par une app que tu y jettes. Ne supprime rien.	watches the Trash and reports files left by an app you throw into it. Deletes nothing.
montre l'état de l'index Spotlight de chaque disque ; le reconstruire demande une commande sudo affichée.	shows the Spotlight index state of each disk; rebuilding it needs a sudo command, which is shown.
vide des caches et journaux de ton dossier perso. Ils se recréent ; historique, mots de passe et marque-pages ne sont pas touchés.	empties caches and logs in your home folder. They are recreated; history, passwords and bookmarks are not touched.
montre la taille des caches et journaux système, et affiche les commandes sudo pour les vider. Rien n'est supprimé d'ici.	shows the size of system caches and logs, and the sudo commands to empty them. Nothing is deleted from here.
diagnostic et tests du réseau. Seul le vidage du cache DNS demande sudo ; le test de débit utilise ta connexion.	network diagnostics and tests. Only flushing the DNS cache needs sudo; the speed test uses your connection.
gère la liste des éléments que core-eraser ne signale et ne touche jamais.	manages the list of items core-eraser never reports or touches.
choisit la langue de core-eraser : anglais (par défaut) ou français.	chooses the core-eraser language: English (default) or French.
état, exclusions et sauvegardes Time Machine. Rien n'est supprimé d'ici : les suppressions demandent une commande sudo affichée.	Time Machine status, exclusions and backups. Nothing is deleted from here: deletions need a sudo command, which is shown.
paquet	package
réglages	settings
attribut	attribute
trace seule (fichiers supprimés)	receipt only (files deleted)
partiel (app mise à jour depuis)	partial (app updated since)
complet	complete
indexation active	indexing enabled
indexation désactivée	indexing disabled
arrêté	stopped
en marche	running
non chargé	not loaded
EOF
}

# Chargé comme bibliothèque (tests) : les fonctions sont définies, rien n'est lancé
if [ "${CORE_ERASER_LIB:-0}" = "1" ]; then
    # shellcheck disable=SC2317  # « exit » ne sert que si le fichier est lancé au lieu d'être chargé
    return 0 2>/dev/null || exit 0
fi

# Le curseur, masqué par les menus au clavier, est toujours réaffiché en sortant
[ -t 1 ] && trap 'printf "\033[?25h"' EXIT

if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
    shift
fi

if [ "${1:-}" = "api" ]; then
    API=1
    ASSUME_YES=1
    shift
    api_run "$@"
    exit $?
fi

if [ $# -eq 0 ]; then
    menu
else
    run "$@"
fi
