#!/bin/bash
# Tests de core-eraser. Chaque test tourne dans un dossier perso temporaire, avec de faux fichiers :
# rien n'est touché sur le vrai Mac. Usage : tests/run-tests.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT="$ROOT/core-eraser.sh"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
ko()  { fail=$((fail + 1)); printf '  ÉCHEC %s\n' "$1"; }
check() {   # check "description" commande...
    local d="$1"
    shift
    if "$@" >/dev/null 2>&1; then ok "$d"; else ko "$d"; fi
}

# Dossier perso temporaire, détruit en fin de test
new_home() {
    T=$(mktemp -d)
    mkdir -p "$T/.claude" "$T/.Trash" "$T/Library/Preferences" "$T/Applications"
}
end_home() { rm -rf "$T"; }

# Lance le script dans le dossier perso temporaire, en anglais
run() { HOME="$T" CLAUDE_CONFIG_DIR="$T/.claude" TMPDIR_CLAUDE="$T/tmpc" TOOLS_LANG="${LANG_TEST:-en}" "$SCRIPT" "$@" 2>&1; }

# Charge les fonctions du script sans le lancer
lib() { HOME="$T" TOOLS_LANG=en CORE_ERASER_LIB=1 bash -c "source \"$SCRIPT\"; $1"; }

# Fausse app : $1 nom, $2 identifiant
fake_app() {
    mkdir -p "$T/Applications/$1.app/Contents"
    plutil -create xml1 "$T/Applications/$1.app/Contents/Info.plist"
    plutil -insert CFBundleIdentifier -string "$2" "$T/Applications/$1.app/Contents/Info.plist"
}

echo "1. Syntaxe et qualité"
check "syntaxe du script" bash -n "$SCRIPT"
check "syntaxe des tests" bash -n "$0"
if command -v shellcheck >/dev/null; then
    check "shellcheck sans remarque" shellcheck -s bash "$SCRIPT" "$0"
else
    echo "  (shellcheck absent : vérification sautée)"
fi

echo "2. Traductions"
cat_ok=$(perl -ne 'if (/^i18n_catalog\(\) \{/ .. /^\}/) { if (/^([^\t]*)\t(.*)$/) { my ($k, $v) = ($1, $2); my $a = () = $k =~ /%s/g; my $b = () = $v =~ /%s/g; print "écart : $k\n" if $a != $b; } }' "$SCRIPT")
check "même nombre de %s dans chaque traduction" test -z "$cat_ok"
missing=$(perl -e '
    local $/; my $s = <>;
    my %cat; if ($s =~ /^i18n_catalog\(\) \{\n(.*?)^\}/ms) { for (split /\n/, $1) { $cat{$1} = 1 if /^([^\t]*)\t/ } }
    while ($s =~ /(?<![\w-])(?:msg|ask) "((?:[^"\\]|\\.)*)"/g) {
        my $k = $1; next if $k =~ /\$/; $k =~ s/\\(["\$`\\])/$1/g;
        next if $k !~ /[A-Za-zÀ-ÿ]{3,}/ || $k =~ /^\s*sudo / || $k =~ /^\[simulation\] brew/;
        next if $k =~ /^\s*-\s+[~\w.\/*]+$/;     # simple nom de fichier : identique dans les deux langues
        print "sans traduction : $k\n" unless $cat{$k};
    }' "$SCRIPT")
check "chaque message a une traduction anglaise" test -z "$missing"
[ -z "$missing" ] || printf '%s\n' "$missing" | sed 's/^/        /'

echo "3. Sécurité"
new_home
marker="$T/PIEGE"
cmd=$(lib "echo \"sudo mv \$(shq '/x\$(touch $marker)\"y') /dest\"")
bash -c "${cmd/sudo mv/:}"
check "un chemin piégé dans une commande sudo affichée ne s'exécute pas" test ! -e "$marker"
check "Corbeille refusée hors du dossier perso" bash -c "! (HOME='$T' TOOLS_LANG=en CORE_ERASER_LIB=1 bash -c 'source \"$SCRIPT\"; trash_item /etc/hosts')"
touch "$T/Library/Preferences/com.test.keep.plist"
run exclude add "$T/Library/Preferences/com.test.keep.plist" >/dev/null
lib "DRY_RUN=0; trash_item \"\$HOME/Library/Preferences/com.test.keep.plist\"" >/dev/null
check "élément protégé jamais mis à la Corbeille" test -e "$T/Library/Preferences/com.test.keep.plist"
touch "$T/a.txt"; lib "DRY_RUN=0; trash_item \"\$HOME/a.txt\"" >/dev/null
touch "$T/a.txt"; lib "DRY_RUN=0; trash_item \"\$HOME/a.txt\"" >/dev/null
check "deux éléments du même nom : aucun écrasement dans la Corbeille" test -e "$T/.Trash/a.txt.1"
end_home

echo "4. Saisie"
new_home
out=$(printf '99\n' | run spotlight)
check "numéro hors limites refusé" grep -q "Invalid number: 99" <<< "$out"
out=$(printf '1 2\n' | run spotlight)
check "deux numéros refusés là où un seul est attendu" grep -q "One number only" <<< "$out"
end_home

echo "5. Restes d'apps (orphans)"
new_home
touch "$T/Library/Preferences/com.test.coreeraser.leftover.plist"
out=$(echo "" | run orphans)
check "un faux reste est détecté" grep -q "com.test.coreeraser.leftover.plist" <<< "$out"
n=$(awk '/com.test.coreeraser.leftover.plist/ { print $1 }' <<< "$out")
printf '%s\nyes\n' "$n" | run --dry-run orphans >/dev/null
check "simulation : rien n'est déplacé" test -e "$T/Library/Preferences/com.test.coreeraser.leftover.plist"
printf 'x %s\n' "$n" | run orphans >/dev/null
out=$(echo "" | run orphans)
check "après « x N », le reste est protégé et n'est plus signalé" bash -c "! grep -q com.test.coreeraser.leftover.plist <<< \"\$1\"" _ "$out"
end_home

echo "6. Désinstallation d'une fausse app (app-uninstall)"
new_home
fake_app "CoreEraserTest" "com.test.coreeraser.app"
mkdir -p "$T/Library/Caches/com.test.coreeraser.app"
touch "$T/Library/Preferences/com.test.coreeraser.app.plist" "$T/Library/Preferences/com.test.other.plist"
n=$(echo "" | run app-uninstall | awk '$2 == "CoreEraserTest" { print $1 }')
# Cases à cocher : tout est coché ; on décoche le cache (repéré par son numéro), puis « e » valide
list=$(printf '%s\nq\n' "$n" | run app-uninstall)
c=$(awk '/\[x\].*Library\/Caches\/com.test.coreeraser.app$/ { print $1; exit }' <<< "$list")
check "les éléments de l'app sont proposés en cases cochées" test "$(grep -c '\[x\]' <<< "$list")" = 3
printf '%s\n%s\ne\nyes\n' "$n" "$c" | run app-uninstall >/dev/null
check "l'app est à la Corbeille" test -e "$T/.Trash/CoreEraserTest.app"
check "ses réglages sont à la Corbeille" test -e "$T/.Trash/com.test.coreeraser.app.plist"
check "l'élément décoché (son cache) reste en place" test -d "$T/Library/Caches/com.test.coreeraser.app"
check "le fichier d'une autre app reste en place" test -e "$T/Library/Preferences/com.test.other.plist"
end_home

echo "6b. Caches : choix par élément (user-clean)"
new_home
mkdir -p "$T/Library/Logs/keep.me" "$T/Library/Logs/drop.me"
touch "$T/Library/Logs/keep.me/a.log" "$T/Library/Logs/drop.me/b.log"
# Catégorie 3 (journaux) : on décoche keep.me, puis « e » valide
list=$(printf '3\nq\n' | run user-clean)
k=$(awk '/\[x\].*Logs\/keep.me$/ { print $1; exit }' <<< "$list")
printf '3\n%s\ne\nyes\n' "$k" | run user-clean >/dev/null
check "l'élément coché est vidé" test ! -e "$T/Library/Logs/drop.me"
check "l'élément décoché reste" test -e "$T/Library/Logs/keep.me/a.log"
end_home

echo "7. Mac sans Claude Code"
new_home
rmdir "$T/.claude"
check "--version affiche la version" grep -q "^core-eraser [0-9]*\.[0-9]*\.[0-9]*$" <<< "$(run --version)"
check "une commande ordinaire fonctionne sans ~/.claude" grep -q "Index state" <<< "$(echo "" | run spotlight)"
check "une commande Claude Code signale le dossier manquant" grep -q "Folder not found" <<< "$(run conv-list)"
end_home

echo "8. Mode api (piloté par l'app, sans question)"
new_home
fake_app "CoreEraserTest" "com.test.coreeraser.app"
touch "$T/Library/Preferences/com.test.coreeraser.app.plist" "$T/Library/Preferences/com.test.coreeraser.leftover.plist"
api() { run api "$@" </dev/null; }
out=$(api list orphans)
check "list orphans : 5 colonnes, reste détecté" bash -c "awk -F'\t' '/com.test.coreeraser.leftover.plist/ && NF == 5 { f = 1 } END { exit !f }' <<< \"\$1\"" _ "$out"
check "list apps : la fausse app est listée, fermée" grep -q "^0	[0-9]*	$T/Applications/CoreEraserTest.app$" <<< "$(api list apps)"
check "list app-files : réglages de l'app" grep -q "com.test.coreeraser.app.plist$" <<< "$(api list app-files "$T/Applications/CoreEraserTest.app")"
check "list user-clean : 3 lignes" test "$(api list user-clean | wc -l | tr -d ' ')" = 3
check "list system-clean : 3 lignes avec commande sudo" test "$(api list system-clean | grep -c '	sudo find ')" = 3
api exclude-add "$T/Library/Preferences/com.test.coreeraser.leftover.plist" >/dev/null
check "exclude-add puis list excludes" grep -q "com.test.coreeraser.leftover.plist" <<< "$(api list excludes)"
api trash "$T/Library/Preferences/com.test.coreeraser.leftover.plist" >/dev/null; rc=$?
check "trash d'un élément protégé : refusé (code non nul, fichier intact)" test "$rc" -ne 0 -a -e "$T/Library/Preferences/com.test.coreeraser.leftover.plist"
api exclude-remove "$T/Library/Preferences/com.test.coreeraser.leftover.plist"
run --dry-run api trash "$T/Library/Preferences/com.test.coreeraser.leftover.plist" >/dev/null </dev/null
check "simulation : rien n'est déplacé" test -e "$T/Library/Preferences/com.test.coreeraser.leftover.plist"
api trash "$T/Library/Preferences/com.test.coreeraser.leftover.plist" >/dev/null
check "exclude-remove puis trash : à la Corbeille" test -e "$T/.Trash/com.test.coreeraser.leftover.plist"
mkdir -p "$T/Library/Logs/one.log.d" "$T/Library/Logs/two.log.d"
check "list user-clean-items : un journal par ligne" test "$(api list user-clean-items 2 | grep -c 'Library/Logs/')" = 2
api clear "$T/Library/Logs/one.log.d" >/dev/null
check "clear : l'élément visé est vidé, pas son voisin" test ! -e "$T/Library/Logs/one.log.d" -a -e "$T/Library/Logs/two.log.d"
api clear "$T/Library/Preferences" >/dev/null; rc=$?
check "clear hors caches et journaux : refusé" test "$rc" -eq 2 -a -d "$T/Library/Preferences"
mkdir -p "$T/.npm/_npx/aaa" "$T/.npm/_npx/bbb"
printf '{\n  "_npx": {\n    "packages": [\n      "tool-a@1.0.0"\n    ]\n  }\n}\n' > "$T/.npm/_npx/aaa/package.json"
check "npx-tools : nom de l'outil lu" grep -q $'\ttool-a@1.0.0\t' <<< "$(api list npx-tools)"
bash -c 'sleep 30; :' "$T/.npm/_npx/bbb/x" & busy_pid=$!
sleep 1
check "npx-tools : outil en cours d'utilisation repéré" grep -q $'\t1\t'"$T/.npm/_npx/bbb"'$' <<< "$(api list npx-tools)"
api npx-remove "$T/.npm/_npx/bbb" >/dev/null
check "npx-remove : outil en cours d'utilisation gardé" test -d "$T/.npm/_npx/bbb"
{ kill "$busy_pid"; wait "$busy_pid"; } 2>/dev/null
api npx-remove "$T/.npm/_npx/aaa" >/dev/null
check "npx-remove : outil supprimé" test ! -e "$T/.npm/_npx/aaa"
api npx-remove "$T/Library/Preferences" >/dev/null; rc=$?
check "npx-remove hors dossier npx : refusé" test "$rc" -eq 2 -a -d "$T/Library/Preferences"
api plugin-remove "$T/Library/Preferences" >/dev/null; rc=$?
check "plugin-remove sur un chemin hors liste : refusé" test "$rc" -eq 2 -a -d "$T/Library/Preferences"
api service-remove "$T/Library/Preferences" >/dev/null; rc=$?
check "service-remove sur un chemin hors liste : refusé" test "$rc" -eq 2 -a -d "$T/Library/Preferences"
api pkg-forget com.test.inconnu >/dev/null; rc=$?
check "pkg-forget sur un paquet inconnu : refusé" test "$rc" -eq 2
check "sentinel status : inactive au départ" test "$(api sentinel status)" = 0
check "dns-flush : commande sudo affichée" grep -q "sudo dscacheutil -flushcache" <<< "$(api text dns-flush)"
out=$(api text tm-status)
check "tm-status : aucun texte français en anglais" test -z "$(grep aucune <<< "$out")"
api exclude-add "$T/Library/Logs" >/dev/null
api exclude-add "$T/Library/Preferences" >/dev/null
api exclude-remove "$T/Library/Logs" "$T/Library/Preferences" >/dev/null
check "exclude-remove : plusieurs éléments retirés d'un coup" test -z "$(api list excludes)"
check "tm-clean status : inactif au départ" test "$(api tm-clean status)" = 0
# Disque Time Machine simulé et notification coupée : les journaux sont vidés, puis rien avant 20 h
mkdir -p "$T/Library/Logs/old.log.d"
lib 'tm_dest() { echo /Volumes/TM; }; osascript() { :; }; tm_clean_check' >/dev/null
check "tm-clean-check : journaux vidés quand le disque est branché" test ! -e "$T/Library/Logs/old.log.d" -a -f "$T/Library/Application Support/io.github.benjaminbusselet.core-eraser/tm-clean-last"
touch "$T/Library/Logs/new.log"
lib 'tm_dest() { echo /Volumes/TM; }; osascript() { :; }; tm_clean_check' >/dev/null
check "tm-clean-check : pas de second nettoyage avant 20 h" test -e "$T/Library/Logs/new.log"
check "cprintf : un mot accentué occupe autant de colonnes qu'un mot sans accent" \
    test "$(lib 'cprintf "%-10s|" "Installé"' | sed 's/é/e/')" = "$(lib 'cprintf "%-10s|" "Installe"')"
check "cprintf : coupe en caractères" test "$(lib 'cprintf "%-3.3s|" "Été!"')" = "Été|"
api spotlight-rebuild /nope >/dev/null; rc=$?
check "spotlight-rebuild sur un disque inconnu : refusé" test "$rc" -eq 2
api tm-exclude-add "$T/absent" >/dev/null; rc=$?
check "tm-exclude-add sur un chemin absent : refusé" test "$rc" -eq 2
api lipo-app "$T/Applications/Absent.app" >/dev/null; rc=$?
check "lipo-app sur une app hors liste : refusé" test "$rc" -eq 2
api conv-trash not-an-id >/dev/null; rc=$?
check "conv-trash sur un id invalide : refusé" test "$rc" -ne 0
printf 'ls\n' > "$T/.zsh_history"
api zsh-history >/dev/null
check "zsh-history : historique remplacé par un fichier vide" test -f "$T/.zsh_history" -a ! -s "$T/.zsh_history"
# Menu : une tâche interrompue (numéro invalide) ramène au menu ; « Quitter » ferme le script
out=$(printf '5\n1\n7\n\n9\n' | HOME="$T" TOOLS_LANG=en "$SCRIPT" 2>&1)
check "menu : retour au menu après une tâche, puis Quitter" test "$(grep -c 'choose a category' <<< "$out")" -eq 2 -a -n "$(grep Goodbye <<< "$out")"
api list inconnu >/dev/null; rc=$?
check "demande inconnue : code 2" test "$rc" -eq 2
check "version" test "$(api version)" = "$(run --version | awk '{ print $2 }')"
end_home

echo "9. Langues"
new_home
check "anglais par défaut" grep -q "^core-eraser: command-line" <<< "$(HOME="$T" "$SCRIPT" -h 2>&1)"
run lang fr >/dev/null
check "« lang fr » est mémorisé" grep -qx fr "$T/Library/Application Support/io.github.benjaminbusselet.core-eraser/lang"
check "l'aide passe en français" grep -q "^core-eraser : entretien" <<< "$(HOME="$T" "$SCRIPT" -h 2>&1)"
# orphans plutôt que user-clean : ce dernier pose une question de plus quand un navigateur est ouvert
touch "$T/Library/Preferences/com.test.coreeraser.leftover.plist"
n=$(echo "" | LANG_TEST=en run orphans | awk '/com.test.coreeraser.leftover.plist/ { print $1 }')
out=$(printf '%s\noui\n' "$n" | LANG_TEST=en run --dry-run orphans)
check "« oui » est accepté en anglais" grep -q "simulation" <<< "$out"
end_home

echo
echo "Résultat : $pass réussi(s), $fail échec(s)"
[ "$fail" -eq 0 ]
