#!/usr/bin/env bash
# =============================================================================
#  DevTools - Instalador / Actualizador de herramientas de desarrollo con IA
#  Compatible: Debian/Ubuntu, Arch Linux, Fedora
#  Version:    1.0.0
# =============================================================================
set -euo pipefail

# ── Configuracion ──────────────────────────────────────────────────────────
readonly SCRIPT_NAME="DevTools"
readonly SCRIPT_VERSION="1.0.0"
readonly LOG_DIR="${HOME}/.devtools"
readonly LOG_FILE="${LOG_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
readonly MIN_DISK_MB=5120

# ── Colores ────────────────────────────────────────────────────────────────
declare -r C_RESET='\033[0m'
declare -r C_BOLD='\033[1m'
declare -r C_DIM='\033[2m'
declare -r C_RED='\033[31m'
declare -r C_GREEN='\033[32m'
declare -r C_YELLOW='\033[33m'
declare -r C_BLUE='\033[34m'
declare -r C_CYAN='\033[36m'
declare -r C_WHITE='\033[37m'
declare -r BG_RED='\033[41m'
declare -r BG_GREEN='\033[42m'

# ── Globales ────────────────────────────────────────────────────────────────
DRY_RUN=false
QUIET=false
ONLY_GROUP=""
OS_ID=""
PKG_MANAGER=""
TOTAL_TOOLS=0
INSTALLED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# =============================================================================
#  HERRAMIENTAS (name|check_cmd|install_type|package|version_flag|group)
#  install_type: apt | pacman | dnf | curl | npm | pipx | repo | flatpak | custom
# =============================================================================
readonly TOOLS=(
  "git|git --version|apt|git|--version|core"
  "python3|python3 --version|apt|python3|--version|lang"
  "pip|pip --version|apt|python3-pip|--version|lang"
  "pipx|pipx --version|apt|pipx|--version|lang"
  "fnm|fnm --version|curl|fnm|--version|lang"
  "node (via fnm)|node --version|custom|node|--version|lang"
  "npm|npm --version|custom|npm|--version|lang"
  "zsh|zsh --version|apt|zsh|--version|shell"
  "Oh My Zsh|[ -n \"$ZSH\" ] && echo ok|custom|ohmyzsh||shell"
  "fzf|fzf --version|apt|fzf|--version|shell"
  "ripgrep|rg --version|apt|ripgrep|--version|shell"
  "fd|fd --version|apt|fd-find|--version|shell"
  "bat|bat --version|apt|bat|--version|shell"
  "eza|eza --version|apt|eza|--version|shell"
  "zoxide|zoxide --version|curl|zoxide|--version|shell"
  "jq|jq --version|apt|jq|--version|data"
  "yq|yq --version|pipx|yq|--version|data"
  "tmux|tmux -V|apt|tmux|-V|shell"
  "btm|btm --version|apt|bottom|--version|monitor"
  "ncdu|ncdu --version|apt|ncdu|--version|monitor"
  "lazygit|lazygit --version|repo|lazygit|--version|git"
  "GitHub CLI|gh --version|repo|gh|--version|git"
  "Docker|docker --version|curl|docker|--version|container"
  "VS Code|code --version|repo|code|--version|editor"
  "Brave|brave-browser --version|repo|brave-browser|--version|browser"
  "Obsidian|obsidian --version|flatpak|md.obsidian.Obsidian|--version|notes"
  "Ollama|ollama --version|curl|ollama|--version|ia"
  "Claude Code|claude --version|npm|@anthropic-ai/claude-code|--version|ia"
  "DeepSeek TUI|deepseek --version|npm|deepseek-tui|--version|ia"
  "Antigravity|antigravity --version|npm|antigravity|--version|ia"
)

# =============================================================================
#  UTILIDADES
# =============================================================================

log_msg() { echo -e "$(date '+%H:%M:%S') $*" >> "$LOG_FILE"; }
info()   { $QUIET || echo -e "${C_BLUE}[*]${C_RESET} $*"; log_msg "[INFO]  $*"; }
ok()     { $QUIET || echo -e "${C_GREEN}[+]${C_RESET} $*"; log_msg "[OK]    $*"; }
warn()   { echo -e "${C_YELLOW}[!]${C_RESET} $*" >&2; log_msg "[WARN]  $*"; }
err()    { echo -e "${C_RED}[X]${C_RESET} $*" >&2; log_msg "[ERROR] $*"; }
section(){ $QUIET || echo -e "\n${C_CYAN}${C_BOLD}── $* ──${C_RESET}"; log_msg "── $* ──"; }

die() {
  echo -e "\n${BG_RED}${C_WHITE} ERROR ${C_RESET} ${C_RED}$*${C_RESET}" >&2
  log_msg "FATAL: $*"
  exit 1
}

check_cmd() {
  local cmd="$1"
  # Si el comando empieza con [, es una expresion condicional
  if [[ "$cmd" == \[* ]]; then
    eval "$cmd" 2>/dev/null
  else
    command -v "${cmd%% *}" &>/dev/null
  fi
}

get_version() {
  local check_cmd="$1" flag="$2"
  if [[ "$check_cmd" == \[* ]]; then
    echo "instalado"
  elif [[ -n "$flag" ]]; then
    eval "${check_cmd%% *} $flag" 2>/dev/null | head -1 || echo "desconocida"
  else
    echo "instalado"
  fi
}

# =============================================================================
#  DETECCION DE SISTEMA
# =============================================================================

detect_os() {
  section "Detectando sistema operativo"

  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    case "$ID" in
      ubuntu|debian|linuxmint|pop|elementary|zorin) OS_ID="debian"; PKG_MANAGER="apt" ;;
      arch|manjaro|endeavouros|garuda)               OS_ID="arch";   PKG_MANAGER="pacman" ;;
      fedora|rhel|centos|rocky|almalinux)            OS_ID="fedora"; PKG_MANAGER="dnf" ;;
      *) die "Distribucion no soportada: $ID. Solo Debian/Ubuntu, Arch, Fedora." ;;
    esac
  else
    die "No se encuentra /etc/os-release. Sistema no soportado."
  fi

  ARCH=$(uname -m)
  ok "Sistema detectado: ${C_BOLD}$OS_ID${C_RESET} ($PKG_MANAGER) - $ARCH"
}

# =============================================================================
#  COMPROBACIONES PREVIAS
# =============================================================================

check_connectivity() {
  section "Verificando conectividad"
  if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
    ok "Conexion a Internet: OK"
  else
    die "Sin conexion a Internet. Comprueba tu red."
  fi
}

check_disk() {
  section "Verificando espacio en disco"
  local avail
  avail=$(df --output=avail / 2>/dev/null | tail -1 | tr -d ' ') || avail=99999999
  local avail_mb=$(( avail / 1024 ))
  if (( avail_mb < MIN_DISK_MB )); then
    die "Espacio insuficiente: ${avail_mb} MB libres (minimo: ${MIN_DISK_MB} MB)"
  fi
  ok "Espacio disponible: ${avail_mb} MB"
}

sudo_cache() {
  section "Cacheando credenciales sudo"
  if sudo -v 2>/dev/null; then
    ok "Permisos sudo OK"
    # Mantener sudo vivo en background
    ( while true; do sudo -n true; sleep 60; kill -0 $$ || exit; done ) 2>/dev/null &
  else
    warn "No se pudo obtener sudo. Algunas instalaciones pueden fallar."
  fi
}

# =============================================================================
#  BANNER Y MENU
# =============================================================================

banner() {
  clear
  echo -e "${C_CYAN}${C_BOLD}"
  cat << 'EOF'
╔══════════════════════════════════════════════════════╗
║                                                      ║
║         ██████╗ ███████╗██╗   ██╗                    ║
║         ██╔══██╗██╔════╝██║   ██║                    ║
║         ██║  ██║█████╗  ██║   ██║                    ║
║         ██║  ██║██╔══╝  ╚██╗ ██╔╝                    ║
║         ██████╔╝███████╗ ╚████╔╝                     ║
║         ╚═════╝ ╚══════╝  ╚═══╝                      ║
║                                                      ║
║         Herramientas de Desarrollo                   ║
║             con Inteligencia Artificial              ║
║                                                      ║
╚══════════════════════════════════════════════════════╝
EOF
  echo -e "${C_RESET}"
  echo -e "  ${C_DIM}Version ${SCRIPT_VERSION}  |  $(date +%Y)  |  Compatible Debian/Arch/Fedora${C_RESET}"
  echo ""
}

menu() {
  echo -e "  ${C_BOLD}${C_GREEN}[1]${C_RESET}  Instalar / Actualizar herramientas"
  echo -e "  ${C_BOLD}${C_RED}[2]${C_RESET}  Cancelar"
  echo ""

  local choice
  while true; do
    read -r -p "  Selecciona una opcion [1-2]: " choice
    case "$choice" in
      1) return 0 ;;
      2) echo -e "\n  ${C_YELLOW}Cancelado. Hasta pronto.${C_RESET}\n"; exit 0 ;;
      *) echo -e "  ${C_RED}Opcion invalida. Elige 1 o 2.${C_RESET}" ;;
    esac
  done
}

# =============================================================================
#  COMPROBACION DE ESTADO
# =============================================================================

tool_status() {
  local name="$1" check="$2" flag="$4"
  local icon ver

  if check_cmd "$check"; then
    ver=$(get_version "$check" "$flag")
    icon="${C_GREEN}✔${C_RESET}"
  else
    ver="no instalado"
    icon="${C_RED}✘${C_RESET}"
  fi
  printf "  %s  %-22s %s\n" "$icon" "$name" "${C_DIM}$ver${C_RESET}"
}

status_all() {
  section "Estado actual de las herramientas"
  echo ""

  local IFS='|'
  for tool in "${TOOLS[@]}"; do
    local parts=($tool)
    tool_status "${parts[0]}" "${parts[1]}" "" "${parts[4]}"
  done
  echo ""
}

# =============================================================================
#  INSTALADORES POR TIPO
# =============================================================================

update_pkg_index() {
  case "$PKG_MANAGER" in
    apt)    $DRY_RUN || sudo apt-get update -qq ;;
    pacman) $DRY_RUN || sudo pacman -Sy --noconfirm &>/dev/null ;;
    dnf)    $DRY_RUN || sudo dnf check-update -q &>/dev/null || true ;;
  esac
}

install_apt() {
  local pkg="$1"
  if dpkg -l "$pkg" &>/dev/null; then
    warn "$pkg ya instalado via apt. Intentando actualizar..."
    $DRY_RUN || sudo apt-get install --only-upgrade -y "$pkg" &>> "$LOG_FILE"
  else
    $DRY_RUN || sudo apt-get install -y "$pkg" &>> "$LOG_FILE"
  fi
}

install_pacman() {
  local pkg="$1"
  $DRY_RUN || sudo pacman -S --noconfirm --needed "$pkg" &>> "$LOG_FILE"
}

install_dnf() {
  local pkg="$1"
  $DRY_RUN || sudo dnf install -y "$pkg" &>> "$LOG_FILE"
}

install_curl_script() {
  local name="$1" pkg="$2"
  case "$pkg" in
    fnm)
      if ! check_cmd "fnm --version"; then
        $DRY_RUN || curl -fsSL https://fnm.vercel.app/install | bash &>> "$LOG_FILE"
        export FNM_PATH="${HOME}/.local/share/fnm"
        [ -s "$FNM_PATH/fnm" ] && export PATH="$FNM_PATH:$PATH"
      fi
      ;;
    zoxide)
      $DRY_RUN || curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh &>> "$LOG_FILE"
      ;;
    ollama)
      $DRY_RUN || curl -fsSL https://ollama.com/install.sh | sh &>> "$LOG_FILE"
      ;;
    docker)
      $DRY_RUN || curl -fsSL https://get.docker.com | sh &>> "$LOG_FILE"
      $DRY_RUN || sudo usermod -aG docker "$USER" 2>/dev/null || true
      ;;
    *)
      warn "No hay instalador curl para: $pkg"
      return 1
      ;;
  esac
}

install_npm_global() {
  local pkg="$1"
  $DRY_RUN || npm install -g "$pkg" &>> "$LOG_FILE"
}

install_pipx() {
  local pkg="$1"
  $DRY_RUN || pipx install "$pkg" &>> "$LOG_FILE"
}

install_repo() {
  local name="$1" pkg="$2"
  case "$OS_ID" in
    debian)
      case "$pkg" in
        gh)
          if ! check_cmd "gh --version"; then
            $DRY_RUN || (curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg &>/dev/null)
            $DRY_RUN || (echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null)
            $DRY_RUN || (sudo apt-get update -qq && sudo apt-get install -y gh)
          else
            install_apt "gh"
          fi
          ;;
        lazygit)
          $DRY_RUN || (sudo add-apt-repository -y ppa:lazygit-team/release &>/dev/null && sudo apt-get update -qq && sudo apt-get install -y lazygit)
          ;;
        code)
          if ! check_cmd "code --version"; then
            $DRY_RUN || (curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/packages.microsoft.gpg > /dev/null)
            $DRY_RUN || (echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null)
            $DRY_RUN || (sudo apt-get update -qq && sudo apt-get install -y code)
          else
            install_apt "code"
          fi
          ;;
        brave-browser)
          if ! check_cmd "brave-browser --version"; then
            $DRY_RUN || (sudo curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg | sudo tee /usr/share/keyrings/brave-browser-archive-keyring.gpg > /dev/null)
            $DRY_RUN || (echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null)
            $DRY_RUN || (sudo apt-get update -qq && sudo apt-get install -y brave-browser)
          else
            install_apt "brave-browser"
          fi
          ;;
        *) install_apt "$pkg" ;;
      esac
      ;;
    arch)
      case "$pkg" in
        gh)        install_pacman "github-cli" ;;
        lazygit)   install_pacman "lazygit" ;;
        code)      install_pacman "code" ;;
        brave-browser) install_pacman "brave-bin" ;;  # AUR
        *)         install_pacman "$pkg" ;;
      esac
      ;;
    fedora)
      case "$pkg" in
        gh)
          $DRY_RUN || sudo dnf install -y dnf5-plugins &>/dev/null
          $DRY_RUN || (sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo &>/dev/null && sudo dnf install -y gh)
          ;;
        lazygit)   install_dnf "lazygit" ;;
        code)
          $DRY_RUN || (sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc && sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo' && sudo dnf check-update -q && sudo dnf install -y code)
          ;;
        brave-browser)
          $DRY_RUN || (sudo dnf install -y dnf5-plugins &>/dev/null)
          $DRY_RUN || (sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo &>/dev/null && sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc && sudo dnf install -y brave-browser)
          ;;
        *) install_dnf "$pkg" ;;
      esac
      ;;
  esac
}

install_flatpak() {
  local pkg="$1"
  if ! command -v flatpak &>/dev/null; then
    install_apt "flatpak" || install_pacman "flatpak" || install_dnf "flatpak"
  fi
  $DRY_RUN || flatpak install -y flathub "$pkg" &>> "$LOG_FILE"
}

install_custom() {
  local name="$1" pkg="$2"
  case "$pkg" in
    node)
      # fnm debe estar ya instalado para que esto funcione
      export FNM_PATH="${HOME}/.local/share/fnm"
      [ -s "$FNM_PATH/fnm" ] && export PATH="$FNM_PATH:$PATH"
      if command -v fnm &>/dev/null; then
        $DRY_RUN || fnm install --lts &>> "$LOG_FILE"
        $DRY_RUN || fnm default lts-latest &>> "$LOG_FILE"
      fi
      ;;
    npm)
      $DRY_RUN || npm install -g npm@latest &>> "$LOG_FILE"
      ;;
    ohmyzsh)
      if [ ! -d "${HOME}/.oh-my-zsh" ]; then
        $DRY_RUN || sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended &>> "$LOG_FILE"
        # Plugins
        $DRY_RUN || git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" 2>/dev/null || true
        $DRY_RUN || git clone https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" 2>/dev/null || true
      else
        # Actualizar OMZ
        $DRY_RUN || zsh -c "omz update" &>> "$LOG_FILE" || true
      fi
      ;;
    *)
      warn "No hay instalador custom para: $pkg"
      return 1
      ;;
  esac
}

# =============================================================================
#  INSTALACION PRINCIPAL
# =============================================================================

progress_bar() {
  local current="$1" total="$2" name="$3"
  local pct=$(( current * 100 / total ))
  local filled=$(( pct / 4 ))
  local empty=$(( 25 - filled ))
  printf "\r  [${C_CYAN}"
  for ((i=0; i<filled; i++)); do printf "#"; done
  printf "${C_DIM}"
  for ((i=0; i<empty; i++)); do printf "."; done
  printf "${C_RESET}] %2d/%2d (%3d%%)  %-30s" "$current" "$total" "$pct" "${name:0:30}"
}

install_all() {
  section "Instalando / Actualizando herramientas"
  echo ""

  update_pkg_index

  TOTAL_TOOLS=${#TOOLS[@]}
  local current=0

  local IFS='|'
  for tool in "${TOOLS[@]}"; do
    local parts=($tool)
    local name="${parts[0]}"
    local check="${parts[1]}"
    local type="${parts[2]}"
    local pkg="${parts[3]}"
    local flag="${parts[4]}"
    local group="${parts[5]}"

    # Filtrar por grupo si --only esta activo
    if [[ -n "$ONLY_GROUP" && "$group" != "$ONLY_GROUP" ]]; then
      ((SKIPPED_COUNT++))
      continue
    fi

    ((current++))
    progress_bar "$current" "$TOTAL_TOOLS" "$name"

    # Comprobar estado previo
    local had_it=false
    check_cmd "$check" && had_it=true

    # Instalar
    local install_ok=false
    case "$type" in
      apt)    install_apt "$pkg" && install_ok=true ;;
      pacman) install_pacman "$pkg" && install_ok=true ;;
      dnf)    install_dnf "$pkg" && install_ok=true ;;
      curl)   install_curl_script "$name" "$pkg" && install_ok=true ;;
      npm)    install_npm_global "$pkg" && install_ok=true ;;
      pipx)   install_pipx "$pkg" && install_ok=true ;;
      repo)   install_repo "$name" "$pkg" && install_ok=true ;;
      flatpak) install_flatpak "$pkg" && install_ok=true ;;
      custom) install_custom "$name" "$pkg" && install_ok=true ;;
      *)      warn "Tipo desconocido: $type" ;;
    esac

    if $DRY_RUN; then
      $had_it && echo -ne " ${C_YELLOW}(actualizaria)${C_RESET}" || echo -ne " ${C_RED}(instalaria)${C_RESET}"
    fi

    if $install_ok || $DRY_RUN; then
      ((INSTALLED_COUNT++))
    else
      ((FAILED_COUNT++))
    fi

    echo ""
  done
  echo ""
}

# =============================================================================
#  RESUMEN FINAL
# =============================================================================

summary() {
  section "Resumen de instalacion"
  echo ""

  # Tabla final
  printf "  %-25s %-12s %s\n" "HERRAMIENTA" "ESTADO" "VERSION"
  printf "  %-25s %-12s %s\n" "──────────────────────" "──────────" "────────"

  local IFS='|'
  for tool in "${TOOLS[@]}"; do
    local parts=($tool)
    local name="${parts[0]}"
    local check="${parts[1]}"
    local flag="${parts[4]}"
    local group="${parts[5]}"

    [[ -n "$ONLY_GROUP" && "$group" != "$ONLY_GROUP" ]] && continue

    local icon ver
    if check_cmd "$check"; then
      ver=$(get_version "$check" "$flag")
      icon="${C_GREEN}OK${C_RESET}"
    else
      ver="FALLO"
      icon="${C_RED}FAIL${C_RESET}"
    fi
    printf "  %-25s %b%-12s${C_RESET} ${C_DIM}%s${C_RESET}\n" "$name" "$icon" "" "${ver:0:40}"
  done

  echo ""
  echo -e "  ${C_BOLD}Resultado:${C_RESET}"
  echo -e "    ${C_GREEN}Instalado/Actualizado:${C_RESET} $INSTALLED_COUNT"
  echo -e "    ${C_RED}Fallos:${C_RESET}               $FAILED_COUNT"
  [[ $SKIPPED_COUNT -gt 0 ]] && echo -e "    ${C_DIM}Omitidos (filtro):${C_RESET}      $SKIPPED_COUNT"
  echo ""
  echo -e "  ${C_DIM}Log guardado en: $LOG_FILE${C_RESET}"
  echo ""

  # Sugerir cambiar shell a zsh
  if check_cmd "zsh --version" && [[ "$SHELL" != *zsh* ]]; then
    echo -e "  ${C_YELLOW}[!] zsh instalada pero no es tu shell por defecto.${C_RESET}"
    echo -e "  ${C_YELLOW}    Ejecuta: chsh -s \$(which zsh)${C_RESET}"
    echo ""
  fi

  # Sugerir reiniciar para grupos
  if check_cmd "docker --version"; then
    echo -e "  ${C_YELLOW}[!] Docker instalado. Cierra sesion y vuelve a entrar para usar docker sin sudo.${C_RESET}"
    echo ""
  fi
}

# =============================================================================
#  MAIN
# =============================================================================

main() {
  mkdir -p "$LOG_DIR"

  # Parsear argumentos
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)  DRY_RUN=true; shift ;;
      --quiet)    QUIET=true; shift ;;
      --only)
        ONLY_GROUP="$2"; shift 2
        case "$ONLY_GROUP" in
          ia|shell|lang|git|data|container|editor|browser|notes|monitor|core) ;;
          *) die "Grupo '$ONLY_GROUP' no valido. Usa: ia, shell, core, lang, git, data, container, editor, browser, notes, monitor" ;;
        esac
        ;;
      --help|-h)
        echo "Uso: $0 [--dry-run] [--quiet] [--only <grupo>]"
        echo ""
        echo "Opciones:"
        echo "  --dry-run    Mostrar que se instalaria sin hacer cambios"
        echo "  --quiet      Salida minima (solo errores)"
        echo "  --only ia    Solo herramientas IA"
        echo "  --only shell Solo herramientas de terminal"
        echo "  --only core  Solo herramientas basicas (git, python, node, npm)"
        echo ""
        echo "Grupos: ia, shell, core, lang, git, data, container, editor, browser, notes, monitor"
        exit 0
        ;;
      *) die "Argumento desconocido: $1. Usa --help." ;;
    esac
  done

  $DRY_RUN && warn "MODO DRY-RUN: no se realizaran cambios."

  detect_os
  check_connectivity
  check_disk
  sudo_cache
  banner
  status_all
  menu

  echo ""
  install_all

  summary
}

main "$@"
