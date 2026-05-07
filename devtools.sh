#!/usr/bin/env bash
# =============================================================================
#  DevTools v6.1 - Literal Code Fix (Antigravity Unchained)
# =============================================================================

set -eo pipefail
shopt -s extglob

# ── Forzar entorno y rutas en tiempo de ejecucion ──────────────────────────
export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.cargo/bin:$PATH"

# ── Configuracion ──────────────────────────────────────────────────────────
readonly SCRIPT_VERSION="6.1.0"
readonly LOG_DIR="${HOME}/.devtools"
readonly STATE_DIR="${LOG_DIR}/state"
readonly LOG_FILE="${LOG_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
readonly MIN_DISK_MB=5120
readonly DELIM='§'
readonly UPDATE_CACHE_SEC=86400 # 24 horas

# ── Colores ────────────────────────────────────────────────────────────────
declare -r C_RESET=$'\033[0m'
declare -r C_BOLD=$'\033[1m'
declare -r C_DIM=$'\033[2m'
declare -r C_RED=$'\033[31m'
declare -r C_GREEN=$'\033[32m'
declare -r C_YELLOW=$'\033[33m'
declare -r C_CYAN=$'\033[36m'
declare -r BG_RED=$'\033[41m'

# ── Iconos ─────────────────────────────────────────────────────────────────
readonly ICON_OK="${C_GREEN}✔${C_RESET}"
readonly ICON_FAIL="${C_RED}✘${C_RESET}"

# ── Globales ───────────────────────────────────────────────────────────────
DRY_RUN=false
QUIET=false
OS_ID=""
PKG_MANAGER=""
TOTAL_TOOLS=0
INSTALLED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0
declare -a SELECTED_TOOLS_ARRAY

trap 'printf "\n%b ERROR inesperado (codigo %d). Revisa el log: %s%b\n" "$BG_RED" "$?" "$LOG_FILE" "$C_RESET" >&2' ERR

# =============================================================================
#  HERRAMIENTAS
# =============================================================================
readonly TOOLS=(
  "curl§curl --version§apt§curl§--version§core"
  "apt-tools§bash -c 'dpkg -s apt-transport-https software-properties-common &>/dev/null'§apt§ca-certificates apt-transport-https software-properties-common§§core"
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
  "btm§btm --version§custom§btm§--version§monitor"
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
  "Antigravity§antigravity§repo§antigravity§§ia" 
)

# =============================================================================
#  FUNCIONES DE APOYO
# =============================================================================
log_msg() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE"; }
die() { printf '\n%b FATAL %b %b%s%b\n' "$BG_RED" "$C_RESET" "$C_RED" "$*" "$C_RESET" >&2; log_msg "FATAL: $*"; exit 1; }

check_cmd() {
  if [[ "$1" == \[* ]] || [[ "$1" == bash\ -c* ]]; then
    eval "$1" 2>/dev/null || return 1
  else
    command -v "${1%% *}" &>/dev/null || return 1
  fi
}

get_version() {
  if [[ "$1" == \[* ]]; then printf 'instalado'
  elif [[ "$1" == bash\ -c* ]]; then
    local raw; raw=$(bash -c "${1#bash -c }" 2>/dev/null | head -1) || true
    printf '%s' "${raw:-instalado}"
  elif [[ -n "$2" ]]; then
    local raw; raw=$(eval "${1%% *} $2" 2>/dev/null | head -1) || true
    printf '%s' "${raw:-desconocida}"
  else printf 'instalado'; fi
}

parse_tool() {
  IFS="$DELIM" read -r T_NAME T_CHECK T_TYPE T_PKG T_FLAG T_GROUP <<< "$1"
}

# =============================================================================
#  SUDO Y PERMISOS
# =============================================================================
require_sudo() {
  clear
  printf "%bATENCION: Este instalador requiere privilegios de administrador (root)%b\n" "${C_YELLOW}${C_BOLD}" "${C_RESET}"
  printf "Por favor, introduce tu contraseña para continuar.\n\n"
  
  if ! sudo -v; then
    die "Autenticacion fallida o cancelada. El script no puede continuar."
  fi
  
  ( while true; do sudo -n true 2>/dev/null; sleep 60; kill -0 $$ 2>/dev/null || exit; done ) &
  log_msg "Sudo autenticado y mantenido en segundo plano."
}

# =============================================================================
#  AUTOCONFIGURAR RUTAS
# =============================================================================
patch_rc_file() {
  local rc_file="$1"
  [[ -f "$rc_file" ]] || return 0
  if ! grep -q "# DevTools Paths" "$rc_file"; then
    printf '\n# DevTools Paths\n' >> "$rc_file"
    printf 'export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.cargo/bin:$PATH"\n' >> "$rc_file"
    printf 'export FNM_PATH="$HOME/.local/share/fnm"\n' >> "$rc_file"
    printf 'if [ -d "$FNM_PATH" ]; then\n  export PATH="$FNM_PATH:$PATH"\n  eval "$(fnm env)"\nfi\n' >> "$rc_file"
  fi
}

# =============================================================================
#  BANNER Y MENU INTERACTIVO
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
  printf '  %bVersion %s  |  %s  |  Debian / Arch / Fedora%b\n\n' "${C_DIM}" "$SCRIPT_VERSION" "$(date +%Y)" "${C_RESET}"
}

menu_interactivo() {
  if ! command -v whiptail &>/dev/null; then
    printf "  Instalando dependencias de la interfaz...\n"
    case "$PKG_MANAGER" in
      apt) sudo apt-get install -y whiptail &>/dev/null ;;
      pacman) sudo pacman -Sy --noconfirm libnewt &>/dev/null ;;
      dnf) sudo dnf install -y newt &>/dev/null ;;
    esac
  fi

  local opciones=()
  for tool in "${TOOLS[@]}"; do
    parse_tool "$tool"
    opciones+=("$T_NAME" "Grupo: $T_GROUP" "ON")
  done

  local SELECCION
  SELECCION=$(whiptail --title "DevTools v$SCRIPT_VERSION" --checklist \
    "Selecciona las herramientas a instalar o actualizar.\n(Usa ESPACIO para marcar/desmarcar y ENTER para confirmar):" \
    25 80 15 "${opciones[@]}" 3>&1 1>&2 2>&3) || true

  if [[ -z "$SELECCION" ]]; then
    printf '\n  %bInstalacion cancelada por el usuario.%b\n\n' "${C_YELLOW}" "${C_RESET}"
    exit 0
  fi

  eval set -- $SELECCION
  SELECTED_TOOLS_ARRAY=("$@")
  
  printf '  %bHas seleccionado %d herramientas para instalar/verificar.%b\n\n' "${C_CYAN}" "${#SELECTED_TOOLS_ARRAY[@]}" "${C_RESET}"
}

# =============================================================================
#  INSTALADORES ESPECIFICOS
# =============================================================================
install_apt() { $DRY_RUN || sudo apt-get install -y $1 &>> "$LOG_FILE" || return 1; }
install_pacman() { $DRY_RUN || sudo pacman -S --noconfirm --needed "$1" &>> "$LOG_FILE" || return 1; }
install_dnf() { $DRY_RUN || sudo dnf install -y "$1" &>> "$LOG_FILE" || return 1; }

load_fnm() {
  export FNM_PATH="${HOME}/.local/share/fnm"
  if [[ -d "$FNM_PATH" ]]; then
    export PATH="$FNM_PATH:$PATH"
    eval "$(fnm env)" 2>/dev/null || true
  fi
}

install_curl_script() {
  case "$2" in
    fnm)
      if ! check_cmd "fnm --version" 2>/dev/null; then
        $DRY_RUN || curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell &>> "$LOG_FILE" || return 1
      fi
      load_fnm ;;
    zoxide) $DRY_RUN || curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh &>> "$LOG_FILE" || return 1 ;;
    ollama) $DRY_RUN || curl -fsSL https://ollama.com/install.sh | sh &>> "$LOG_FILE" || return 1 ;;
    docker)
      $DRY_RUN || { 
        curl -fsSL https://get.docker.com | sudo sh || sudo apt-get install -y docker.io docker-compose
        sudo usermod -aG docker "$USER" 2>/dev/null || true
      } &>> "$LOG_FILE" || return 1 ;;
    *) return 1 ;;
  esac
}

install_npm() {
  load_fnm
  mkdir -p "$HOME/.npm-global/bin"
  npm config set prefix "$HOME/.npm-global" 2>/dev/null || true
  $DRY_RUN || npm install -g "$1" &>> "$LOG_FILE" || return 1
}

install_pipx() { $DRY_RUN || pipx install "$1" &>> "$LOG_FILE" || return 1; }

install_repo() {
  local pkg="$2"
  if [[ "$OS_ID" == "debian" ]]; then
    $DRY_RUN || sudo mkdir -p -m 755 /etc/apt/keyrings
    
    case "$pkg" in
      gh)
        if ! check_cmd "gh --version" 2>/dev/null; then
          $DRY_RUN || { curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
            sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
            sudo apt-get update -qq || true; sudo apt-get install -y gh; } &>> "$LOG_FILE" || return 1
        else install_apt "gh" || return 1; fi ;;
      lazygit)
        $DRY_RUN || {
          local LAZYGIT_VERSION
          LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
          curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
          tar xf lazygit.tar.gz lazygit; sudo install lazygit /usr/local/bin; rm lazygit.tar.gz lazygit
        } &>> "$LOG_FILE" || return 1 ;;
      code)
        if ! check_cmd "code --version" 2>/dev/null; then
          $DRY_RUN || { curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg
            sudo chmod go+r /etc/apt/keyrings/packages.microsoft.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
            sudo apt-get update -qq || true; sudo apt-get install -y code; } &>> "$LOG_FILE" || return 1
        else install_apt "code" || return 1; fi ;;
      brave-browser)
        if ! check_cmd "brave-browser --version" 2>/dev/null; then
          $DRY_RUN || { curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg | sudo tee /etc/apt/keyrings/brave-browser-archive-keyring.gpg >/dev/null
            sudo chmod go+r /etc/apt/keyrings/brave-browser-archive-keyring.gpg
            echo "deb [signed-by=/etc/apt/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
            sudo apt-get update -qq || true; sudo apt-get install -y brave-browser; } &>> "$LOG_FILE" || return 1
        else install_apt "brave-browser" || return 1; fi ;;
      antigravity)
        if ! check_cmd "antigravity" 2>/dev/null; then
          printf "\n    [>] Ejecutando instalacion directa de Antigravity...\n"
          # Literalmente tu codigo, sin ocultar output en el log
          sudo mkdir -p /etc/apt/keyrings
          curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg || return 1
          echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null || return 1
          sudo apt update || true
          sudo apt install -y antigravity || return 1
        else 
          install_apt "antigravity" || return 1
        fi ;;
      *) install_apt "$pkg" || return 1 ;;
    esac
  elif [[ "$OS_ID" == "arch" ]]; then
    case "$pkg" in
      gh) install_pacman "github-cli" ;; lazygit) install_pacman "lazygit" ;;
      code) install_pacman "code" ;; brave-browser) install_pacman "brave-bin" ;; *) install_pacman "$pkg" ;;
    esac || return 1
  elif [[ "$OS_ID" == "fedora" ]]; then
    case "$pkg" in
      gh) $DRY_RUN || { sudo dnf install -y dnf5-plugins &>/dev/null; sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo &>/dev/null; sudo dnf install -y gh; } &>> "$LOG_FILE" || return 1 ;;
      lazygit) install_dnf "lazygit" || return 1 ;;
      code) $DRY_RUN || { sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc; printf '[code]\nname=VS Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null; sudo dnf check-update -q && sudo dnf install -y code; } &>> "$LOG_FILE" || return 1 ;;
      brave-browser) $DRY_RUN || { sudo dnf install -y dnf5-plugins &>/dev/null; sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo &>/dev/null; sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc; sudo dnf install -y brave-browser; } &>> "$LOG_FILE" || return 1 ;;
      *) install_dnf "$pkg" || return 1 ;;
    esac
  fi
}

install_flatpak() {
  if ! command -v flatpak &>/dev/null; then
    install_apt flatpak 2>/dev/null || install_pacman flatpak 2>/dev/null || install_dnf flatpak 2>/dev/null || return 1
  fi
  
  $DRY_RUN || sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &>> "$LOG_FILE" || true
  $DRY_RUN || sudo flatpak install -y flathub "$1" &>> "$LOG_FILE" || return 1

  if [[ "$1" == "md.obsidian.Obsidian" ]]; then
    mkdir -p "$HOME/.local/bin"
    echo '#!/usr/bin/env bash' > "$HOME/.local/bin/obsidian"
    echo 'exec flatpak run md.obsidian.Obsidian "$@"' >> "$HOME/.local/bin/obsidian"
    chmod +x "$HOME/.local/bin/obsidian"
  fi
}

install_custom() {
  case "$2" in
    node) load_fnm; if command -v fnm &>/dev/null; then $DRY_RUN || { fnm install --lts && fnm default lts-latest; } &>> "$LOG_FILE" || return 1; else return 1; fi ;;
    npm) load_fnm; $DRY_RUN || npm install -g npm@latest &>> "$LOG_FILE" || return 1 ;;
    ohmyzsh) if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then $DRY_RUN || { sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; } &>> "$LOG_FILE" || return 1; else $DRY_RUN || zsh -c "omz update" &>> "$LOG_FILE" || true; fi ;;
    btm) if ! command -v cargo &>/dev/null; then $DRY_RUN || sudo apt-get install -y cargo &>> "$LOG_FILE" || return 1; fi; $DRY_RUN || cargo install bottom --locked &>> "$LOG_FILE" || return 1 ;;
    *) return 1 ;;
  esac
}

# =============================================================================
#  MOTOR PRINCIPAL
# =============================================================================
main() {
  mkdir -p "$LOG_DIR" "$STATE_DIR" "$HOME/.local/bin" "$HOME/.npm-global/bin"
  
  patch_rc_file "$HOME/.bashrc"
  patch_rc_file "$HOME/.zshrc"

  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    case "${ID:-unknown}" in
      ubuntu|debian|linuxmint|pop) OS_ID="debian"; PKG_MANAGER="apt" ;;
      arch|manjaro|endeavouros) OS_ID="arch"; PKG_MANAGER="pacman" ;;
      fedora|rhel|centos) OS_ID="fedora"; PKG_MANAGER="dnf" ;;
      *) die "Sistema no soportado." ;;
    esac
  else die "Sistema no soportado."; fi

  # 1. PEDIR SUDO
  require_sudo

  # 2. MOSTRAR BANNER Y MENÚ INTERACTIVO
  banner
  menu_interactivo

  # 3. ACTUALIZAR CACHÉ DEL SISTEMA
  local apt_cache_file="/var/cache/apt/pkgcache.bin"
  local skip_pkg_update=false
  if [[ "$PKG_MANAGER" == "apt" && -f "$apt_cache_file" ]]; then
    local last_pkg_upd=$(stat -c %Y "$apt_cache_file" 2>/dev/null || echo 0)
    local now=$(date +%s)
    if (( now - last_pkg_upd < UPDATE_CACHE_SEC )); then
      skip_pkg_update=true
    fi
  fi

  if ! $skip_pkg_update; then
    printf "  Actualizando indices del sistema...\n"
    case "$PKG_MANAGER" in
      apt) sudo apt-get update -qq 2>> "$LOG_FILE" || true ;;
      pacman) sudo pacman -Sy --noconfirm &>> "$LOG_FILE" || true ;;
      dnf) sudo dnf check-update -q &>> "$LOG_FILE" || true ;;
    esac
  fi

  TOTAL_TOOLS=${#SELECTED_TOOLS_ARRAY[@]}
  local current=0

  # 4. BUCLE DE INSTALACIÓN (Solo las seleccionadas)
  for st in "${SELECTED_TOOLS_ARRAY[@]}"; do
    for tool in "${TOOLS[@]}"; do
      parse_tool "$tool"
      if [[ "$T_NAME" == "$st" ]]; then
        
        ((current++)) || true
        printf '\r  [%2d/%2d] Procesando %-25s ' "$current" "$TOTAL_TOOLS" "${T_NAME:0:25}"

        local had_it=false
        check_cmd "$T_CHECK" 2>/dev/null && had_it=true

        local state_file="$STATE_DIR/$(echo "$T_NAME" | tr -d ' /()')"
        local skip_update=false

        if $had_it && [[ -f "$state_file" ]]; then
          local last_upd=$(stat -c %Y "$state_file" 2>/dev/null || echo 0)
          local now=$(date +%s)
          if (( now - last_upd < UPDATE_CACHE_SEC )); then
            skip_update=true
          fi
        fi

        if $skip_update; then
          ((SKIPPED_COUNT++)) || true
          printf '%bOMITIDO (Act. <24h)%b\n' "${C_DIM}" "${C_RESET}"
          break
        fi

        local install_ok=false
        case "$T_TYPE" in
          apt) install_apt "$T_PKG" && install_ok=true ;;
          pacman) install_pacman "$T_PKG" && install_ok=true ;;
          dnf) install_dnf "$T_PKG" && install_ok=true ;;
          curl) install_curl_script "$T_NAME" "$T_PKG" && install_ok=true ;;
          npm) install_npm "$T_PKG" && install_ok=true ;;
          pipx) install_pipx "$T_PKG" && install_ok=true ;;
          repo) install_repo "$T_NAME" "$T_PKG" && install_ok=true ;;
          flatpak) install_flatpak "$T_PKG" && install_ok=true ;;
          custom) install_custom "$T_NAME" "$T_PKG" && install_ok=true ;;
        esac

        if $install_ok; then
          ((INSTALLED_COUNT++)) || true
          touch "$state_file"
          printf '%bOK%b\n' "${C_GREEN}" "${C_RESET}"
        else
          ((FAILED_COUNT++)) || true
          printf '%bFAIL%b\n' "${C_RED}" "${C_RESET}"
        fi
        
        break
      fi
    done
  done

  # 5. RESUMEN FINAL
  printf '\n%bInstalacion terminada.%b\n' "${C_BOLD}" "${C_RESET}"
  printf 'Exitosos: %b%d%b | Omitidos: %b%d%b | Fallos: %b%d%b\n\n' "${C_GREEN}" "$INSTALLED_COUNT" "${C_RESET}" "${C_DIM}" "$SKIPPED_COUNT" "${C_RESET}" "${C_RED}" "$FAILED_COUNT" "${C_RESET}"
  
  printf '%b¡IMPORTANTE: Cierra esta terminal por completo y abre una nueva para aplicar todos los cambios!%b\n\n' "${BG_RED}${C_WHITE}" "${C_RESET}"
}

main "$@"
