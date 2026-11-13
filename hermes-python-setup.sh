#!/usr/bin/env bash
# =============================================================================
# hermes-python-setup.sh – Python-Pakete in beide Hermes-Interpreter bringen
# =============================================================================
# Im Container arbeiten zwei Interpreter:
#   /opt/hermes/.venv   Werkzeug-Interpreter (execute_code) – im Image, root-eigen
#   /opt/data/.venv     Daten-venv (Terminal-Skripte)       – auf dem Mount
# Beide Listen liegen als Manifest im Image; denselben Satz verwendet der
# Dockerfile beim Bau. Damit können Image und laufender Container nicht
# auseinanderlaufen – eine Pflegestelle für beide.
#
# Aufruf im laufenden Container:
#   hermes-python-setup                    beide Interpreter aus den Manifesten
#   hermes-python-setup --tools-only       nur /opt/hermes/.venv
#   hermes-python-setup --data-only        nur /opt/data/.venv
#   hermes-python-setup --check            nur prüfen, Rückgabewert 1 bei Lücke
#   hermes-python-setup --upgrade          vorhandene Pakete mit aktualisieren
#   hermes-python-setup pandas openpyxl    Zusatzpakete, ohne das Image neu zu bauen
#
# Wiederholbar: uv installiert nur, was fehlt. Für /opt/hermes/.venv braucht es
# root – der Aufruf über docker exec ist standardmäßig root:
#   docker exec -it hermes hermes-python-setup
# =============================================================================
set -euo pipefail

MANIFEST_DIR="${HERMES_MANIFEST_DIR:-/opt/hermes}"
TOOLS_MANIFEST="${MANIFEST_DIR}/python-packages-tools.txt"
DATA_MANIFEST="${MANIFEST_DIR}/python-packages-data.txt"
TOOLS_PYTHON="/opt/hermes/.venv/bin/python"
DATA_PYTHON="/opt/data/.venv/bin/python"
DATA_VENV_DIR="/opt/data/.venv"
UV_GLOB="/opt/hermes/tools/uv-*/uv"

g_uv=""
g_mache_tools=1
g_mache_data=1
g_nur_pruefen=0
g_upgrade=0
g_status=0

usage() {
  cat <<'HILFE'
hermes-python-setup – Python-Pakete in beide Hermes-Interpreter bringen

  hermes-python-setup                  beide Interpreter aus den Manifesten
  hermes-python-setup --tools-only     nur /opt/hermes/.venv (root nötig)
  hermes-python-setup --data-only      nur /opt/data/.venv
  hermes-python-setup --check          nur prüfen, Rückgabewert 1 bei Lücke
  hermes-python-setup --upgrade        vorhandene Pakete mit aktualisieren
  hermes-python-setup paket [paket…]   Zusatzpakete für beide Interpreter
  hermes-python-setup -h               diese Hilfe

Manifeste (eine Pflegestelle, auch für den Image-Bau):
  /opt/hermes/python-packages-tools.txt   für den Werkzeug-Interpreter
  /opt/hermes/python-packages-data.txt    für das Daten-venv
HILFE
}

log() {
  printf '%s\n' "$*"
}

# uv aufrufbar machen: erst PATH, dann der Pfad im Basis-Image.
suche_uv() {
  if command -v uv >/dev/null 2>&1; then
    g_uv="$(command -v uv)"
    return 0
  fi
  local kandidat
  for kandidat in $UV_GLOB; do
    if [ -x "$kandidat" ]; then
      g_uv="$kandidat"
      return 0
    fi
  done
  log "FEHLER: uv nicht gefunden (weder im PATH noch unter ${UV_GLOB})."
  log "        Im Dockerfile verlinken:  ln -sf /opt/hermes/tools/uv-*/uv /usr/local/bin/uv"
  return 1
}

# Paketnamen aus einem Manifest: Kommentar- und Leerzeilen fallen weg.
manifest_pakete() {
  local datei="$1"
  grep -vE '^[[:space:]]*(#|$)' "$datei"
}

# Ist im Ziel-venv ein Schreibzugriff möglich?
schreibbar() {
  local verzeichnis="$1"
  [ -w "${verzeichnis}/lib" ] || [ -w "$verzeichnis" ]
}

# Installieren (oder prüfen) für einen Interpreter.
# $1 Bezeichnung, $2 venv-python, $3 venv-verzeichnis, $4 Manifest, Rest: Zusatzpakete
bearbeite() {
  local bezeichnung="$1"
  local venv_python="$2"
  local venv_dir="$3"
  local manifest="$4"
  shift 4
  local -a zusatz=("$@")
  local -a pakete=()
  local paket
  local -a fehlend=()

  if [ ! -x "$venv_python" ]; then
    log "  ${bezeichnung}: Interpreter fehlt (${venv_python}) – übersprungen."
    return 0
  fi
  if [ ! -f "$manifest" ]; then
    log "  ${bezeichnung}: Manifest fehlt (${manifest}) – übersprungen."
    g_status=1
    return 0
  fi

  while IFS= read -r paket; do
    pakete+=("$paket")
  done < <(manifest_pakete "$manifest")
  pakete+=("${zusatz[@]}")

  if [ "$g_nur_pruefen" = "1" ]; then
    local installiert
    installiert="$("$g_uv" pip list --python "$venv_python" 2>/dev/null \
      | awk '$1 != "" && $1 !~ /^-/ && tolower($1) != "package" { print tolower($1) }' | tr '_' '-')"
    for paket in "${pakete[@]}"; do
      local name="${paket%%[<>=!]*}"
      name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
      grep -qx -- "$name" <<<"$installiert" || fehlend+=("$paket")
    done
    if [ "${#fehlend[@]}" -eq 0 ]; then
      log "  ${bezeichnung}: vollständig (${#pakete[@]} Pakete geprüft)."
    else
      log "  ${bezeichnung}: ${#fehlend[@]} von ${#pakete[@]} fehlen – ${fehlend[*]}"
      g_status=1
    fi
    return 0
  fi

  if ! schreibbar "$venv_dir"; then
    log "  ${bezeichnung}: ${venv_dir} ist für $(id -un) nicht beschreibbar."
    log "     Als root aufrufen:  docker exec -it hermes hermes-python-setup"
    [ "$g_status" -eq 0 ] && g_status=3
    return 0
  fi

  local -a optionen=(--python "$venv_python")
  if [ "$g_upgrade" = "1" ]; then
    optionen+=(--upgrade)
  fi
  log "  ${bezeichnung}: installiere ${#pakete[@]} Paket(e) aus $(basename "$manifest")"
  if ! "$g_uv" pip install "${optionen[@]}" "${pakete[@]}"; then
    log "  ${bezeichnung}: Installation fehlgeschlagen."
    g_status=1
    return 0
  fi

  # Als root installiert -> Eigentümer zurückgeben, sonst kann der Nutzer
  # im Container später nichts mehr nachinstallieren.
  if [ "$(id -u)" = "0" ] && [ -d "$DATA_VENV_DIR" ]; then
    local eigentuemer
    eigentuemer="$(stat -c '%u:%g' /opt/data 2>/dev/null || echo '')"
    if [ -n "$eigentuemer" ]; then
      chown -R "$eigentuemer" "$DATA_VENV_DIR"
      log "  Eigentümer von ${DATA_VENV_DIR} bleibt ${eigentuemer}."
    fi
  fi
  return 0
}

main() {
  local -a zusatz=()
  local argument
  while [ $# -gt 0 ]; do
    argument="$1"
    case "$argument" in
      --tools-only) g_mache_data=0 ;;
      --data-only)  g_mache_tools=0 ;;
      --check)      g_nur_pruefen=1 ;;
      --upgrade)    g_upgrade=1 ;;
      -h|--help)    usage; return 0 ;;
      --*)          log "Unbekannter Schalter: ${argument}"; usage; return 2 ;;
      *)            zusatz+=("$argument") ;;
    esac
    shift
  done

  suche_uv || return 4
  log "uv: ${g_uv} ($("${g_uv}" --version 2>/dev/null | head -n 1))"
  if [ "$g_mache_tools" = "1" ]; then
    bearbeite "Werkzeug-venv  " "$TOOLS_PYTHON" "/opt/hermes/.venv" "$TOOLS_MANIFEST" "${zusatz[@]+"${zusatz[@]}"}"
  fi
  if [ "$g_mache_data" = "1" ]; then
    bearbeite "Daten-venv     " "$DATA_PYTHON" "$DATA_VENV_DIR" "$DATA_MANIFEST" "${zusatz[@]+"${zusatz[@]}"}"
  fi

  if [ "$g_nur_pruefen" = "1" ]; then
    if [ "$g_status" -eq 0 ]; then
      log "Ergebnis: alle Pakete vorhanden."
    else
      log "Ergebnis: Pakete fehlen (siehe oben)."
    fi
  fi
  return "$g_status"
}

main "$@"
