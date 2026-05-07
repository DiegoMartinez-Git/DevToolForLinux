#!/usr/bin/env bash
# =============================================================================
#  DevTools v3.0 - Instalador / Actualizador de herramientas de desarrollo
#  Compatible: Debian/Ubuntu, Arch Linux, Fedora
#  Uso:        bash devtools.sh [--dry-run] [--quiet] [--only <grupo>]
# =============================================================================

# ── Modo estricto ──────────────────────────────────────────────────────────
set -eo pipefail
shopt -s extglob

# ── Configuracion ──────────────────────────────────────────────────────────
readonly SCRIPT_VERSION="3.0.0"
readonly LOG_DIR="${HOME}/.devtools"
readonly LOG_FILE="${LOG_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
readonly MIN_DISK_MB=5120
readonly DELIM='§'   # Separador de campos: no aparece en comandos shell

# ── Colores (escapes ANSI reales) ──────────────────────────────────────────
declare -r C_RESET=$'\033[0m'
declare -r C_BOLD=$'\033[1m'
declare -r C_DIM=$'\033[2m'
declare -r C_RED=$'\033[31m'
declare -r C_GREEN=$'\033[32m'
declare -r C_YELLOW=$'\033[33m'
declare -r C_BLUE=$'\033[34m'
declare -r C_CYAN=$'\033[36m'
declare -r C_WHITE=$'\033[37m'
declare -r BG_RED=$'\033[41m'

# ── Iconos ─────────────────────────────────────────────────────────────────
readonly ICON_OK="${C_GREEN}✔${C_RESET}"
readonly ICON_FAIL="${C_RED}✘${C_RESET}"
readonly ICON_INFO="${C_BLUE}●${C_RESET}"
readonly ICON_WARN="${C_YELLOW}▲${C_RESET}"

# ── Globales ───────────────────────────────────────────────────────────────
DRY_RUN=false
QUIET=false
ONLY_GROUP=""
OS_ID=""
PKG_MANAGER=""
ARCH=""
TOTAL_TOOLS=0
INSTALLED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# ── Trap ───────────────────────────────────────────────────────────────────
trap 'printf "\n%b ERROR inesperado (codigo %d). Log: %s%b\n" "$BG_RED" "$?" "$LOG_FILE" "$C_RESET" >&2' ERR

# =============================================================================
#  HERRAMIENTAS
#  Formato: name § check_cmd § type § package § version_flag § group
#  type: apt | pacman | dnf | curl | npm | pipx | repo | flatpak | custom
#  check_cmd admite || (segun tipo shell, no rompe el parser porque usamos §)
# =============================================================================
readonly TOOLS=(
  "curl§curl --version§apt§curl§--version§core"
  "ca-certificates§[ -f /etc/ssl/certs/ca-certificates.crt ]§apt§ca-certificates§§core"
  "gnupg§gpg --version§apt§gnupg§--version§core"
  "git§git --version§apt§git§--version§core"
  "python3§python3 --version§apt§python3§--version§lang"
  "python3-pip§bash -c 'pip3 --version 2>/dev/null || pip --version'§apt§python3-pip§--version§lang"
  "pipx§pipx --version§apt§pipx§--version§lang"
  "fnm§fnm --version§curl§fnm§--version§lang"
  "Node.js (LTS)§node --version§custom§node§--version§lang"
  "npm§npm --version§custom§npm§--version§lang"
  "zsh§zsh --version§apt§zsh§--version§shell"
  "Oh My Zsh§[ -d ${HOME}/.oh-my-zsh ]§custom§ohmyzsh§§shell"
  "fzf§fzf --version§apt§fzf§--version§shell"
  "ripgrep§rg --version§apt§ripgrep§--version§shell"
  "fd§bash -c 'fdfind --version 2>/dev/null || fd --version'§apt§fd-find§--version§shell"
  "bat§bash -c 'batcat --version 2>/dev/null || bat --version'§apt§bat§--version§shell"
  "eza§eza --version§apt§eza§--version§shell"
  "zoxide§zoxide --version§curl§zoxide§--version§shell"
  "jq§jq --version§apt§jq§--version§data"
  "yq§yq --version§pipx§yq§--version§data"
  "tmux§tmux -V§apt§tmux§-V§shell"
  "btm§btm --version§apt§bottom§--version§monitor"
  "ncdu§ncdu --version§apt§ncdu§--version§monitor"
  "lazygit§lazygit --version§repo§lazygit§--version§git"
  "GitHub CLI§gh --version§repo§gh§--version§git"
  "Docker§docker --version§curl§docker§--version§container"
  "VS Code§code --version§repo§code§--version§editor"
  "Brave§brave-browser --version§repo§brave-browser§--version§browser"
  "Obsidian§flatpak info md.obsidian.Obsidian &>/dev/null§flatpak§md.obsidian.Obsidian§§notes"
  "Ollama§ollama --version§curl§ollama§--version§ia"
  "Claude Code§claude --version§npm§@anthropic-ai/claude-code§--version§ia"
  "DeepSeek TUI§deepseek --version§npm§deepseek-tui§--version§ia"
  "Antigravity§antigravity --version§npm§antigravity§--version§ia"
)

# =============================================================================
#  UTILIDADES
# =============================================================================

log_msg() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE"; }

info()   { $QUIET || printf '%b  %b %s\n'   "$ICON_INFO" "$*" "${C_RESET}"; log_msg "INFO  $*"; }
ok()     { $QUIET || printf '%b  %b %s\n'   "$ICON_OK"   "$*" "${C_RESET}"; log_msg "OK    $*"; }
warn()   {           printf '%b  %b %s\n'   "$ICON_WARN" "$*" "${C_RESET}" >&2; log_msg "WARN  $*"; }
err()    {           printf '%b  %b %s\n'   "$ICON_FAIL" "$*" "${C_RESET}" >&2; log_msg "ERROR $*"; }

section() {
  $QUIET || printf '\n%b%s%b\n' "${C_CYAN}${C_BOLD}" "── $* ──" "${C_RESET}"
  log_msg "── $* ──"
}

die() {
  printf '\n%b ERROR %b %b%s%b\n' "$BG_RED" "$C_RESET" "$C_RED" "$*" "$C_RESET" >&2
  log_msg "FATAL: $*"
  exit 1
}

check_cmd() {
  local cmd="$1"
  if [[ "$cmd" == \[* ]]; then
    # Expresion condicional: [ -d ... ] o similar
    eval "$cmd" 2>/dev/null || return 1
  elif [[ "$cmd" == bash\ -c* ]]; then
    # Comando envuelto en bash -c para proteger ||
    eval "$cmd" 2>/dev/null || return 1
  else
    # Comando simple con posible `||` dentro (protegido por el bash -c wrapper)
    command -v "${cmd%% *}" &>/dev/null || return 1
  fi
}

get_version() {
  local check_cmd="$1" flag="$2" raw
  if [[ "$check_cmd" == \[* ]]; then
    printf 'instalado'
  elif [[ "$check_cmd" == bash\ -c* ]]; then
    # Ejecutar con bash -c
    raw=$(bash -c "${check_cmd#bash -c }" 2>/dev/null | head -1) || true
    printf '%s' "${raw:-instalado}"
  elif [[ -n "$flag" ]]; then
    raw=$(eval "${check_cmd%% *} $flag" 2>/dev/null | head -1) || true
    printf '%s' "${raw:-desconocida}"
  else
    printf 'instalado'
  fi
}

# Parsear un registro de herramienta
parse_tool() {
  # Uso: parse_tool "campo§campo§..." → establece name,check,type,pkg,flag,group
  local tool="$1"
  IFS="$DELIM" read -r name check type pkg flag group <<< "$tool"
  # Exportar para que el llamador use estas variables globales
  T_NAME="$name"; T_CHECK="$check"; T_TYPE="$type"
  T_PKG="$pkg"; T_FLAG="$flag"; T_GROUP="$group"
}

# =============================================================================
#  DETECCION DE SISTEMA
# =============================================================================

detect_os() {
  section "Detectando sistema operativo"
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    case "${ID:-unknown}" in
      ubuntu|debian|linuxmint|pop|elementary|zorin|raspbian)
        OS_ID="debian"; PKG_MANAGER="apt" ;;
      arch|manjaro|endeavouros|garuda|artix)
        OS_ID="arch";   PKG_MANAGER="pacman" ;;
      fedora|rhel|centos|rocky|almalinux)
        OS_ID="fedora"; PKG_MANAGER="dnf" ;;
      *) die "Distribucion no soportada: ${ID:-desconocida}" ;;
    esac
  else
    die "No se encuentra /etc/os-release"
  fi
  ARCH=$(uname -m)
  ok "Sistema: ${C_BOLD}${OS_ID}${C_RESET} (${PKG_MANAGER}) - ${ARCH}"
}

# =============================================================================
#  COMPROBACIONES
# =============================================================================

check_connectivity() {
  section "Verificando conectividad"
  if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
    ok "Conexion a Internet: OK"
  else
    die "Sin conexion a Internet"
  fi
}

check_disk() {
  section "Verificando espacio en disco"
  local avail
  avail=$(df --output=avail / 2>/dev/null | tail -1 | tr -d ' ') || \
  avail=$(df -k / 2>/dev/null | awk 'NR==2 {print $4}') || avail=99999999
  local avail_mb=$(( avail / 1024 ))
  (( avail_mb >= MIN_DISK_MB )) || die "Espacio insuficiente: ${avail_mb} MB (min: ${MIN_DISK_MB})"
  ok "Espacio: ${avail_mb} MB libres"
}

sudo_cache() {
  section "Cacheando credenciales sudo"
  if command -v sudo &>/dev/null && sudo -v 2>/dev/null; then
    ok "Permisos sudo OK"
    ( while true; do sudo -n true 2>/dev/null; sleep 60; kill -0 $$ 2>/dev/null || exit; done ) &
  elif command -v sudo &>/dev/null; then
    warn "No se pudo cachear sudo"
  else
    warn "sudo no encontrado"
  fi
}

# =============================================================================
#  BANNER Y MENU
# =============================================================================

banner() {
  clear 2>/dev/null || true
  printf '%b' "${C_CYAN}${C_BOLD}"
  cat << 'ENDOFBANNER'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║           ██████╗ ███████╗██╗   ██╗                      ║
║           ██╔══██╗██╔════╝██║   ██║                      ║
║           ██║  ██║█████╗  ██║   ██║                      ║
║           ██║  ██║██╔══╝  ╚██╗ ██╔╝                      ║
║           ██████╔╝███████╗ ╚████╔╝                       ║
║           ╚═════╝ ╚══════╝  ╚═══╝                        ║
║                                                          ║
║           Herramientas de Desarrollo                     ║
║               con Inteligencia Artificial                ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
ENDOFBANNER
  printf '%b' "${C_RESET}"
  printf '  %bVersion %s  |  %s  |  Debian / Arch / Fedora%b\n\n' \
    "${C_DIM}" "$SCRIPT_VERSION" "$(date +%Y)" "${C_RESET}"
}

menu() {
  printf '  %b[1]%b  Instalar / Actualizar herramientas\n' "${C_BOLD}${C_GREEN}" "${C_RESET}"
  printf '  %b[2]%b  Cancelar\n\n' "${C_BOLD}${C_RED}" "${C_RESET}"
  local choice
  while true; do
    read -r -p "  Selecciona una opcion [1-2]: " choice
    case "$choice" in
      1) return 0 ;;
      2) printf '\n  %bCancelado.%b\n\n' "${C_YELLOW}" "${C_RESET}"; exit 0 ;;
      *) printf '  %bOpcion invalida. Elige 1 o 2.%b\n' "${C_RED}" "${C_RESET}" ;;
    esac
  done
}

# =============================================================================
#  COMPROBACION DE ESTADO
# =============================================================================

tool_status() {
  local name="$1" check="$2" flag="$3" ver icon
  if check_cmd "$check" 2>/dev/null; then
    ver=$(get_version "$check" "$flag")
    icon="$ICON_OK"
  else
    ver="no instalado"
    icon="$ICON_FAIL"
  fi
  printf '  %b  %-28s %b%s%b\n' "$icon" "$name" "${C_DIM}" "$ver" "${C_RESET}"
}

status_all() {
  section "Estado actual de las herramientas"
  printf '\n'
  for tool in "${TOOLS[@]}"; do
    parse_tool "$tool"
    tool_status "$T_NAME" "$T_CHECK" "$T_FLAG"
  done
  printf '\n'
}

# =============================================================================
#  INSTALADORES
# =============================================================================

update_pkg_index() {
  case "$PKG_MANAGER" in
    apt)    $DRY_RUN || sudo apt-get update -qq 2>> "$LOG_FILE" || true ;;
    pacman) $DRY_RUN || sudo pacman -Sy --noconfirm &>> "$LOG_FILE" || true ;;
    dnf)    $DRY_RUN || sudo dnf check-update -q &>> "$LOG_FILE" || true ;;
  esac
}

install_apt() {
  local pkg="$1"
  if dpkg -l "$pkg" &>/dev/null 2>&1; then
    info "${pkg}: actualizando..."
    $DRY_RUN || sudo apt-get install --only-upgrade -y "$pkg" &>> "$LOG_FILE" || return 1
  else
    $DRY_RUN || sudo apt-get install -y "$pkg" &>> "$LOG_FILE" || return 1
  fi
}

install_pacman() {
  $DRY_RUN || sudo pacman -S --noconfirm --needed "$1" &>> "$LOG_FILE" || return 1
}

install_dnf() {
  $DRY_RUN || sudo dnf install -y "$1" &>> "$LOG_FILE" || return 1
}

install_curl_script() {
  local name="$1" pkg="$2"
  case "$pkg" in
    fnm)
      $DRY_RUN && return 0
      if ! check_cmd "fnm --version" 2>/dev/null; then
        curl -fsSL https://fnm.vercel.app/install | bash &>> "$LOG_FILE" || return 1
      fi
      export FNM_PATH="${HOME}/.local/share/fnm"
      [[ -s "$FNM_PATH/fnm" ]] && export PATH="$FNM_PATH:$PATH"
      ;;
    zoxide)   $DRY_RUN || curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh &>> "$LOG_FILE" || return 1 ;;
    ollama)   $DRY_RUN || curl -fsSL https://ollama.com/install.sh | sh &>> "$LOG_FILE" || return 1 ;;
    docker)
      $DRY_RUN || curl -fsSL https://get.docker.com | sh &>> "$LOG_FILE" || return 1
      $DRY_RUN || sudo usermod -aG docker "$USER" 2>/dev/null || true
      ;;
    *) warn "No hay instalador curl para: $pkg"; return 1 ;;
  esac
}

install_npm() {
  $DRY_RUN || npm install -g "$1" &>> "$LOG_FILE" || return 1
}

install_pipx() {
  $DRY_RUN || pipx install "$1" &>> "$LOG_FILE" || return 1
}

install_repo() {
  local name="$1" pkg="$2"
  case "$OS_ID" in
    debian)
      case "$pkg" in
        gh)
          if ! check_cmd "gh --version" 2>/dev/null; then
            $DRY_RUN || {
              curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg &>/dev/null
              echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
              sudo apt-get update -qq && sudo apt-get install -y gh
            } &>> "$LOG_FILE" || return 1
          else install_apt "gh" || return 1; fi
          ;;
        lazygit)
          $DRY_RUN || { sudo add-apt-repository -y ppa:lazygit-team/release &>/dev/null
            sudo apt-get update -qq && sudo apt-get install -y lazygit; } &>> "$LOG_FILE" || return 1 ;;
        code)
          if ! check_cmd "code --version" 2>/dev/null; then
            $DRY_RUN || { curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
              | gpg --dearmor | sudo tee /usr/share/keyrings/packages.microsoft.gpg >/dev/null
              echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
              | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
              sudo apt-get update -qq && sudo apt-get install -y code; } &>> "$LOG_FILE" || return 1
          else install_apt "code" || return 1; fi
          ;;
        brave-browser)
          if ! check_cmd "brave-browser --version" 2>/dev/null; then
            $DRY_RUN || { sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
              https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
              echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
              | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
              sudo apt-get update -qq && sudo apt-get install -y brave-browser; } &>> "$LOG_FILE" || return 1
          else install_apt "brave-browser" || return 1; fi
          ;;
        *) install_apt "$pkg" || return 1 ;;
      esac ;;
    arch)
      case "$pkg" in
        gh) install_pacman "github-cli" ;; lazygit) install_pacman "lazygit" ;;
        code) install_pacman "code" ;; brave-browser) install_pacman "brave-bin" ;;
        *) install_pacman "$pkg" ;;
      esac || return 1 ;;
    fedora)
      case "$pkg" in
        gh) $DRY_RUN || { sudo dnf install -y dnf5-plugins &>/dev/null
          sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo &>/dev/null
          sudo dnf install -y gh; } &>> "$LOG_FILE" || return 1 ;;
        lazygit) install_dnf "lazygit" || return 1 ;;
        code) $DRY_RUN || { sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
          printf '[code]\nname=VS Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' \
          | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
          sudo dnf check-update -q && sudo dnf install -y code; } &>> "$LOG_FILE" || return 1 ;;
        brave-browser) $DRY_RUN || { sudo dnf install -y dnf5-plugins &>/dev/null
          sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo &>/dev/null
          sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
          sudo dnf install -y brave-browser; } &>> "$LOG_FILE" || return 1 ;;
        *) install_dnf "$pkg" || return 1 ;;
      esac ;;
  esac
}

install_flatpak() {
  if ! command -v flatpak &>/dev/null; then
    install_apt flatpak 2>/dev/null || install_pacman flatpak 2>/dev/null || install_dnf flatpak 2>/dev/null || {
      warn "No se pudo instalar flatpak"; return 1; }
  fi
  $DRY_RUN || flatpak install -y flathub "$1" &>> "$LOG_FILE" || return 1
}

install_custom() {
  local name="$1" pkg="$2"
  case "$pkg" in
    node)
      export FNM_PATH="${HOME}/.local/share/fnm"
      [[ -s "$FNM_PATH/fnm" ]] && export PATH="$FNM_PATH:$PATH"
      if command -v fnm &>/dev/null; then
        $DRY_RUN || fnm install --lts &>> "$LOG_FILE" || return 1
        $DRY_RUN || fnm default lts-latest &>> "$LOG_FILE" || return 1
      else warn "fnm no disponible"; return 1; fi
      ;;
    npm)
      $DRY_RUN || npm install -g npm@latest &>> "$LOG_FILE" || return 1 ;;
    ohmyzsh)
      if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
        $DRY_RUN || { sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
          git clone https://github.com/zsh-users/zsh-autosuggestions \
            "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" 2>/dev/null || true
          git clone https://github.com/zsh-users/zsh-syntax-highlighting \
            "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" 2>/dev/null || true
        } &>> "$LOG_FILE" || return 1
      else $DRY_RUN || zsh -c "omz update" &>> "$LOG_FILE" || true; fi
      ;;
    *) warn "No hay instalador custom: $pkg"; return 1 ;;
  esac
}

# =============================================================================
#  INSTALACION PRINCIPAL
# =============================================================================

progress_bar() {
  local current="$1" total="$2" name="$3" pct=$(( current * 100 / total ))
  local filled=$(( pct / 4 )) empty=$(( 25 - filled )) i
  printf '\r  [%b' "${C_CYAN}"
  for ((i=0; i<filled; i++)); do printf '#'; done
  printf '%b' "${C_DIM}"
  for ((i=0; i<empty; i++)); do printf '.'; done
  printf '%b] %2d/%2d (%3d%%)  %-30s' "${C_RESET}" "$current" "$total" "$pct" "${name:0:30}"
}

install_all() {
  section "Instalando / Actualizando herramientas"
  printf '\n'
  update_pkg_index

  TOTAL_TOOLS=${#TOOLS[@]}
  local current=0 had_it install_ok

  for tool in "${TOOLS[@]}"; do
    parse_tool "$tool"

    if [[ -n "$ONLY_GROUP" && "$T_GROUP" != "$ONLY_GROUP" ]]; then
      ((SKIPPED_COUNT++)) || true; continue
    fi

    ((current++)) || true
    progress_bar "$current" "$TOTAL_TOOLS" "$T_NAME"

    had_it=false
    check_cmd "$T_CHECK" 2>/dev/null && had_it=true

    install_ok=false
    case "$T_TYPE" in
      apt)     install_apt "$T_PKG"          && install_ok=true ;;
      pacman)  install_pacman "$T_PKG"       && install_ok=true ;;
      dnf)     install_dnf "$T_PKG"          && install_ok=true ;;
      curl)    install_curl_script "$T_NAME" "$T_PKG" && install_ok=true ;;
      npm)     install_npm "$T_PKG"          && install_ok=true ;;
      pipx)    install_pipx "$T_PKG"         && install_ok=true ;;
      repo)    install_repo "$T_NAME" "$T_PKG" && install_ok=true ;;
      flatpak) install_flatpak "$T_PKG"      && install_ok=true ;;
      custom)  install_custom "$T_NAME" "$T_PKG" && install_ok=true ;;
      *)       warn "Tipo desconocido: $T_TYPE" ;;
    esac

    if $DRY_RUN; then
      $had_it && printf ' %b(act.)%b' "${C_YELLOW}" "${C_RESET}" \
               || printf ' %b(inst.)%b' "${C_RED}" "${C_RESET}"
    fi

    if $install_ok || $DRY_RUN; then ((INSTALLED_COUNT++)) || true
    else ((FAILED_COUNT++)) || true; fi
    printf '\n'
  done
  printf '\n'
}

# =============================================================================
#  RESUMEN
# =============================================================================

summary() {
  section "Resumen de instalacion"
  printf '\n  %-30s %-8s %s\n' "HERRAMIENTA" "ESTADO" "VERSION"
  printf '  %-30s %-8s %s\n' "────────────────────────────" "──────" "──────"

  for tool in "${TOOLS[@]}"; do
    parse_tool "$tool"
    [[ -n "$ONLY_GROUP" && "$T_GROUP" != "$ONLY_GROUP" ]] && continue

    local icon="$ICON_FAIL" ver="FALLO"
    if check_cmd "$T_CHECK" 2>/dev/null; then
      ver=$(get_version "$T_CHECK" "$T_FLAG"); icon="$ICON_OK"
    fi
    printf '  %b%-30s%b  %s  %b%s%b\n' "${C_BOLD}" "$T_NAME" "${C_RESET}" "$icon" "${C_DIM}" "${ver:0:45}" "${C_RESET}"
  done

  printf '\n  %bResultado:%b\n' "${C_BOLD}" "${C_RESET}"
  printf '    Instalado/Actualizado: %b%d%b\n' "${C_GREEN}" "$INSTALLED_COUNT" "${C_RESET}"
  printf '    Fallos:                %b%d%b\n' "${C_RED}"   "$FAILED_COUNT"    "${C_RESET}"
  [[ $SKIPPED_COUNT -gt 0 ]] && printf '    Omitidos (filtro):     %b%d%b\n' "${C_DIM}" "$SKIPPED_COUNT" "${C_RESET}"
  printf '\n  %bLog: %s%b\n\n' "${C_DIM}" "$LOG_FILE" "${C_RESET}"

  if check_cmd "zsh --version" 2>/dev/null && [[ "${SHELL:-}" != *zsh* ]]; then
    printf '  %b[!] zsh instalada. Default: chsh -s %s%b\n\n' "${C_YELLOW}" "$(command -v zsh)" "${C_RESET}"
  fi
  if check_cmd "docker --version" 2>/dev/null; then
    printf '  %b[!] Docker: cierra sesion para usar sin sudo.%b\n\n' "${C_YELLOW}" "${C_RESET}"
  fi
  if check_cmd "fnm --version" 2>/dev/null; then
    printf '  %b[!] fnm: anade a .bashrc/.zshrc: %b\n    export PATH="$HOME/.local/share/fnm:$PATH"\n    eval "$(fnm env)"%b\n\n' "${C_YELLOW}" "${C_DIM}" "${C_RESET}"
  fi
}

# =============================================================================
#  MAIN
# =============================================================================

main() {
  mkdir -p "$LOG_DIR"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=true; shift ;;
      --quiet)   QUIET=true;   shift ;;
      --only)    ONLY_GROUP="$2"; shift 2
        case "$ONLY_GROUP" in
          ia|shell|lang|git|data|container|editor|browser|notes|monitor|core) ;;
          *) die "Grupo '$ONLY_GROUP' no valido" ;;
        esac ;;
      --help|-h)
        printf 'Uso: %s [--dry-run] [--quiet] [--only grupo]\n' "$0"
        printf 'Grupos: ia shell core lang git data container editor browser notes monitor\n'
        exit 0 ;;
      *) die "Argumento: $1" ;;
    esac
  done

  $DRY_RUN && warn "MODO DRY-RUN"

  detect_os
  check_connectivity
  check_disk
  sudo_cache
  banner
  status_all
  menu
  printf '\n'
  install_all
  summary
  printf '%bDevTools v%s completado.%b\n' "${C_GREEN}${C_BOLD}" "$SCRIPT_VERSION" "${C_RESET}"
}

main "$@"
