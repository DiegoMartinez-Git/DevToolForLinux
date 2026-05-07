#!/usr/bin/env bash
# =============================================================================
#  DevTools v4.0 - Instalador a prueba de bombas (Fix Rutas + Wrappers)
# =============================================================================

set -eo pipefail
shopt -s extglob

# ── Forzar entorno y rutas en tiempo de ejecucion ──────────────────────────
export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.cargo/bin:$PATH"

# ── Configuracion ──────────────────────────────────────────────────────────
readonly SCRIPT_VERSION="4.0.0"
readonly LOG_DIR="${HOME}/.devtools"
readonly LOG_FILE="${LOG_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
readonly MIN_DISK_MB=5120
readonly DELIM='§'

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
ONLY_GROUP=""
OS_ID=""
PKG_MANAGER=""
TOTAL_TOOLS=0
INSTALLED_COUNT=0
FAILED_COUNT=0

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
  "Antigravity§antigravity --version§npm§antigravity§--version§ia"
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
#  AUTOCONFIGURAR RUTAS (MAGIA PARA QUE NO FALLE DEEPSEEK NI NODE)
# =============================================================================
patch_rc_file() {
  local rc_file="$1"
  [[ -f "$rc_file" ]] || return 0
  if ! grep -q "# DevTools Paths" "$rc_file"; then
    printf '\n# DevTools Paths\n' >> "$rc_file"
    printf 'export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.cargo/bin:$PATH"\n' >> "$rc_file"
    printf 'export FNM_PATH="$HOME/.local/share/fnm"\n' >> "$rc_file"
    printf 'if [ -d "$FNM_PATH" ]; then\n  export PATH="$FNM_PATH:$PATH"\n  eval "$(fnm env)"\nfi\n' >> "$rc_file"
    log_msg "Rutas inyectadas en $rc_file"
  fi
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
      $DRY_RUN && return 0
      if ! check_cmd "fnm --version" 2>/dev/null; then
        curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell &>> "$LOG_FILE" || return 1
      fi
      load_fnm ;;
    zoxide) $DRY_RUN || curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh &>> "$LOG_FILE" || return 1 ;;
    ollama) $DRY_RUN || curl -fsSL https://ollama.com/install.sh | sh &>> "$LOG_FILE" || return 1 ;;
    docker)
      $DRY_RUN || curl -fsSL https://get.docker.com | sh &>> "$LOG_FILE" || return 1
      $DRY_RUN || sudo usermod -aG docker "$USER" 2>/dev/null || true ;;
    *) return 1 ;;
  esac
}

install_npm() {
  load_fnm
  mkdir -p "$HOME/.npm-global/bin"
  npm config set prefix "$HOME/.npm-global"
  $DRY_RUN || npm install -g "$1" &>> "$LOG_FILE" || return 1
}

install_pipx() { $DRY_RUN || pipx install "$1" &>> "$LOG_FILE" || return 1; }

install_repo() {
  local pkg="$2"
  if [[ "$OS_ID" == "debian" ]]; then
    case "$pkg" in
      gh)
        if ! check_cmd "gh --version" 2>/dev/null; then
          $DRY_RUN || { curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg &>/dev/null
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
            sudo apt-get update -qq && sudo apt-get install -y gh; } &>> "$LOG_FILE" || return 1
        else install_apt "gh" || return 1; fi ;;
      lazygit)
        $DRY_RUN || { sudo add-apt-repository -y ppa:lazygit-team/release &>/dev/null
          sudo apt-get update -qq && sudo apt-get install -y lazygit; } &>> "$LOG_FILE" || return 1 ;;
      code)
        if ! check_cmd "code --version" 2>/dev/null; then
          $DRY_RUN || { curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/packages.microsoft.gpg >/dev/null
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
            sudo apt-get update -qq && sudo apt-get install -y code; } &>> "$LOG_FILE" || return 1
        else install_apt "code" || return 1; fi ;;
      brave-browser)
        if ! check_cmd "brave-browser --version" 2>/dev/null; then
          $DRY_RUN || { curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/brave-browser-archive-keyring.gpg &>/dev/null
            echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
            sudo apt-get update -qq && sudo apt-get install -y brave-browser; } &>> "$LOG_FILE" || return 1
        else install_apt "brave-browser" || return 1; fi ;;
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
  $DRY_RUN || flatpak install -y flathub "$1" &>> "$LOG_FILE" || return 1

  # CREAR ATAJO PARA OBSIDIAN
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
    ohmyzsh) if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then $DRY_RUN || { sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" 2>/dev/null || true; git clone https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" 2>/dev/null || true; } &>> "$LOG_FILE" || return 1; else $DRY_RUN || zsh -c "omz update" &>> "$LOG_FILE" || true; fi ;;
    btm) if ! command -v cargo &>/dev/null; then $DRY_RUN || sudo apt-get install -y cargo &>> "$LOG_FILE" || return 1; fi; $DRY_RUN || cargo install bottom --locked &>> "$LOG_FILE" || return 1 ;;
    *) return 1 ;;
  esac
}

# =============================================================================
#  MOTOR PRINCIPAL
# =============================================================================
main() {
  mkdir -p "$LOG_DIR" "$HOME/.local/bin" "$HOME/.npm-global/bin"
  
  # Auto-parchear shell rc
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

  if command -v sudo &>/dev/null; then sudo -v 2>/dev/null; fi

  clear 2>/dev/null || true
  printf '\n%b  DevTools v%s (Fix Edition)%b\n\n' "${C_CYAN}${C_BOLD}" "$SCRIPT_VERSION" "${C_RESET}"

  TOTAL_TOOLS=${#TOOLS[@]}
  local current=0

  case "$PKG_MANAGER" in
    apt) sudo apt-get update -qq 2>> "$LOG_FILE" || true ;;
    pacman) sudo pacman -Sy --noconfirm &>> "$LOG_FILE" || true ;;
    dnf) sudo dnf check-update -q &>> "$LOG_FILE" || true ;;
  esac

  for tool in "${TOOLS[@]}"; do
    parse_tool "$tool"
    ((current++)) || true
    
    # Barra de progreso minimalista
    printf '\r  [%2d/%2d] Instalando %-25s ' "$current" "$TOTAL_TOOLS" "${T_NAME:0:25}"

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
      printf '%bOK%b\n' "${C_GREEN}" "${C_RESET}"
    else
      ((FAILED_COUNT++)) || true
      printf '%bFAIL%b\n' "${C_RED}" "${C_RESET}"
    fi
  done

  printf '\n%bInstalacion terminada.%b\n' "${C_BOLD}" "${C_RESET}"
  printf 'Exitosos: %b%d%b | Fallos: %b%d%b\n\n' "${C_GREEN}" "$INSTALLED_COUNT" "${C_RESET}" "${C_RED}" "$FAILED_COUNT" "${C_RESET}"
  
  printf '%bATENCION: Para que los comandos funcionen, DEBES CERRAR ESTA TERMINAL Y ABRIR UNA NUEVA.%b\n' "${BG_RED}${C_WHITE}" "${C_RESET}"
}

main "$@"
