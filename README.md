# DevTools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/shell-bash-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![OS: Debian/Arch/Fedora](https://img.shields.io/badge/OS-Debian%20%7C%20Arch%20%7C%20Fedora-blue)]()

Script de instalacion y actualizacion automatica de herramientas de desarrollo con Inteligencia Artificial para Linux. 30 herramientas en un solo comando.

```
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
╚══════════════════════════════════════════════════════╝
```

## Instalacion rapida

```bash
curl -fsSL https://raw.githubusercontent.com/dimnova/devtools/main/devtools.sh | bash
```

O clonando el repositorio:

```bash
git clone https://github.com/dimnova/devtools.git
cd devtools
chmod +x devtools.sh
./devtools.sh
```

## Compatibilidad

| Distribucion | Soporte |
|-------------|---------|
| Ubuntu / Debian / Mint / Pop!_OS / Zorin | Completo |
| Arch Linux / Manjaro / EndeavourOS / Garuda | Completo |
| Fedora / RHEL / CentOS / Rocky / AlmaLinux | Completo |

## Uso

```bash
./devtools.sh                # Modo interactivo
./devtools.sh --dry-run      # Ver que se instalaria sin cambios
./devtools.sh --quiet        # Solo muestra errores
./devtools.sh --only ia      # Solo herramientas de IA
./devtools.sh --only shell   # Solo herramientas de terminal
./devtools.sh --only core    # Solo basicas (git, python, node, npm)
./devtools.sh --help         # Ayuda
```

## Flujo del script

1. Detecta el sistema operativo (Debian, Arch o Fedora)
2. Verifica conectividad a Internet y espacio en disco
3. Muestra el estado actual de las 30 herramientas (instalado / no instalado)
4. Menu interactivo: instalar o cancelar
5. Instala o actualiza cada herramienta desde sus fuentes oficiales
6. Barra de progreso en tiempo real con colores
7. Resumen final con estado de cada herramienta
8. Log completo guardado en `~/.devtools/install_YYYYMMDD_HHMMSS.log`

## Herramientas incluidas (30)

| Categoria | Herramientas |
|-----------|-------------|
| **Agentes IA** | Claude Code, DeepSeek TUI, Antigravity, Ollama |
| **Editor** | Visual Studio Code |
| **Navegador** | Brave Browser |
| **Terminal** | zsh + Oh My Zsh (plugins: autosuggestions, syntax-highlighting), fzf, ripgrep, fd, bat, eza, zoxide, tmux |
| **Versionado** | Git, GitHub CLI (`gh`), lazygit |
| **Lenguajes** | Python 3, pip, pipx, fnm (gestor Node.js), Node.js (LTS), npm |
| **Contenedores** | Docker |
| **Procesamiento datos** | jq, yq |
| **Monitor** | bottom (`btm`), ncdu |
| **Notas** | Obsidian |

### Detalle por herramienta

| # | Herramienta | Metodo | Fuente |
|---|------------|--------|--------|
| 1 | `git` | Gestor de paquetes | Repo oficial de la distro |
| 2 | `python3` | Gestor de paquetes | Repo oficial de la distro |
| 3 | `pip` | Gestor de paquetes | Repo oficial de la distro |
| 4 | `pipx` | Gestor de paquetes | Repo oficial de la distro |
| 5 | `fnm` | curl | [fnm.vercel.app](https://fnm.vercel.app) |
| 6 | `node` (LTS) | fnm | Node.js via fnm |
| 7 | `npm` | npm | Actualizado via npm |
| 8 | `zsh` | Gestor de paquetes | Repo oficial de la distro |
| 9 | Oh My Zsh | curl | [ohmyz.sh](https://ohmyz.sh) |
| 10 | `fzf` | Gestor de paquetes | Repo oficial |
| 11 | `ripgrep` | Gestor de paquetes | Repo oficial |
| 12 | `fd` | Gestor de paquetes | Repo oficial |
| 13 | `bat` | Gestor de paquetes | Repo oficial |
| 14 | `eza` | Gestor de paquetes | Repo oficial |
| 15 | `zoxide` | curl | [ajeetdsouza/zoxide](https://github.com/ajeetdsouza/zoxide) |
| 16 | `jq` | Gestor de paquetes | Repo oficial |
| 17 | `yq` | pipx | [mikefarah/yq](https://github.com/mikefarah/yq) |
| 18 | `tmux` | Gestor de paquetes | Repo oficial |
| 19 | `btm` (bottom) | Gestor de paquetes | Repo oficial |
| 20 | `ncdu` | Gestor de paquetes | Repo oficial |
| 21 | `lazygit` | PPA / repo | [jesseduffield/lazygit](https://github.com/jesseduffield/lazygit) |
| 22 | GitHub CLI (`gh`) | Repo GitHub | [cli.github.com](https://cli.github.com) |
| 23 | Docker | curl | [get.docker.com](https://get.docker.com) |
| 24 | VS Code | Repo Microsoft | [code.visualstudio.com](https://code.visualstudio.com) |
| 25 | Brave | Repo Brave | [brave.com](https://brave.com) |
| 26 | Obsidian | flatpak | [flathub.org](https://flathub.org) |
| 27 | Ollama | curl | [ollama.com](https://ollama.com) |
| 28 | Claude Code | npm | [@anthropic-ai/claude-code](https://www.npmjs.com/package/@anthropic-ai/claude-code) |
| 29 | DeepSeek TUI | npm | [deepseek-tui](https://www.npmjs.com/package/deepseek-tui) |
| 30 | Antigravity | npm | npm registry |

## Opciones

| Flag | Descripcion |
|------|------------|
| `--dry-run` | Simula la ejecucion sin instalar nada |
| `--quiet` | Solo muestra errores (ideal para scripts) |
| `--only ia` | Solo herramientas de IA (Claude Code, DeepSeek TUI, Antigravity, Ollama) |
| `--only shell` | Solo herramientas de terminal (zsh, fzf, bat, etc.) |
| `--only core` | Solo basicas (git, python3, pip, pipx, fnm, node, npm) |
| `--only lang` | Solo lenguajes y gestores de versiones |
| `--only git` | Solo herramientas de Git |
| `--only data` | Solo procesamiento de datos (jq, yq) |
| `--only container` | Solo Docker |
| `--only editor` | Solo VS Code |
| `--only browser` | Solo Brave |
| `--only notes` | Solo Obsidian |
| `--only monitor` | Solo btm y ncdu |
| `--help` | Muestra esta ayuda |

## Logs

Cada ejecucion genera un log en `~/.devtools/install_YYYYMMDD_HHMMSS.log` con el detalle completo de cada instalacion.

```bash
cat ~/.devtools/install_20260507_113000.log
```

## Requisitos

- Linux (Debian/Ubuntu, Arch o Fedora)
- Conexion a Internet
- 5 GB de espacio libre en disco
- `sudo` (para instalaciones del sistema)

## Personalizacion

Edita el array `TOOLS` en `devtools.sh` para anadir o quitar herramientas. Cada entrada sigue el formato:

```
"Nombre|comando_check|tipo_instalador|nombre_paquete|flag_version|grupo"
```

Tipos de instalador disponibles: `apt`, `pacman`, `dnf`, `curl`, `npm`, `pipx`, `repo`, `flatpak`, `custom`

