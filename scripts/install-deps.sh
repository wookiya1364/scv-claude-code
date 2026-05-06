#!/usr/bin/env bash
#
# install-deps.sh — Detect missing SCV external dependencies and either print
# the right install command for the current OS or run it.
#
# Usage:
#   bash install-deps.sh             # default: --check
#   bash install-deps.sh --check     # report missing + recommended install command
#   bash install-deps.sh --install   # actually run the install (sudo prompts may appear)
#   bash install-deps.sh --print     # print install commands for ALL supported OSes (info)
#
# Tools handled (system CLIs only):
#   git, gh, glab, curl, jq, ffmpeg, python3
#
# Out of scope (different distribution channel):
#   graphify (Claude Code skill — see https://github.com/safishamsi/graphify)
#
# Supported OS / package manager:
#   macOS              → brew
#   Linux Debian/Ubuntu → apt
#   Linux Fedora/RHEL  → dnf
#   Linux Arch         → pacman
#   Linux openSUSE     → zypper
#   Linux Alpine       → apk
#   Windows (Git Bash) → winget (default), scoop / choco (alternatives)
#   Unknown            → print all-OS reference + abort
#
# Verification status: install commands are documented per upstream packaging
# guides. The repository author has end-to-end-verified Linux/apt only.
# macOS / Windows / other Linux distros are best-effort — please open an issue
# if a command needs adjustment.

set -u

MODE="${1:---check}"
case "$MODE" in
  --check|--install|--print) ;;
  -h|--help)
    sed -n '2,/^set -u/{ /^set -u/!p; }' "$0" | sed 's/^# \?//'
    exit 0
    ;;
  *)
    echo "ERROR: unknown mode '$MODE'. Use --check / --install / --print." >&2
    exit 2
    ;;
esac

# ---------- Tools list (order = display order) ------------------------------

TOOLS=(git gh glab curl jq ffmpeg python3)

# Tier (used for non-zero exit on --check):
#   required:    breaks core flows when missing → exit 1
#   recommended: breaks one platform/feature    → exit 0 with warning
#   optional:    graceful degrade               → exit 0 with note
declare -A TIER
TIER[git]=required
TIER[gh]=recommended
TIER[glab]=recommended
TIER[curl]=recommended
TIER[jq]=recommended
TIER[ffmpeg]=optional
TIER[python3]=optional

# Human-readable purpose
declare -A PURPOSE
PURPOSE[git]="git operations (core)"
PURPOSE[gh]="GitHub PR auto-create (SCV_PR_PLATFORM=github)"
PURPOSE[glab]="GitLab MR auth (preferred over GITLAB_TOKEN .env)"
PURPOSE[curl]="GitLab MR + Slack/Discord HTTP"
PURPOSE[jq]="JSON parsing for GitLab MR + Notifier"
PURPOSE[ffmpeg]="PR video → GIF inline preview"
PURPOSE[python3]="attachments_status cache parsing"

# ---------- OS / PM detection -----------------------------------------------

detect_os() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) echo "macos" ;;
    Linux)
      if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}${ID_LIKE:-}" in
          *debian*|*ubuntu*) echo "linux-debian" ;;
          *fedora*|*rhel*|*centos*) echo "linux-fedora" ;;
          *arch*|*manjaro*) echo "linux-arch" ;;
          *suse*|*opensuse*) echo "linux-suse" ;;
          *alpine*) echo "linux-alpine" ;;
          *) echo "linux-unknown" ;;
        esac
      else
        echo "linux-unknown"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

detect_pm() {
  case "$1" in
    macos)
      if command -v brew >/dev/null 2>&1; then echo "brew"
      else echo "missing-brew"; fi ;;
    linux-debian)
      if command -v apt-get >/dev/null 2>&1; then echo "apt"
      else echo "missing-apt"; fi ;;
    linux-fedora)
      if command -v dnf >/dev/null 2>&1; then echo "dnf"
      elif command -v yum >/dev/null 2>&1; then echo "yum"
      else echo "missing-dnf"; fi ;;
    linux-arch)
      if command -v pacman >/dev/null 2>&1; then echo "pacman"
      else echo "missing-pacman"; fi ;;
    linux-suse)
      if command -v zypper >/dev/null 2>&1; then echo "zypper"
      else echo "missing-zypper"; fi ;;
    linux-alpine)
      if command -v apk >/dev/null 2>&1; then echo "apk"
      else echo "missing-apk"; fi ;;
    linux-unknown) echo "unknown-pm" ;;
    windows)
      if command -v winget >/dev/null 2>&1; then echo "winget"
      elif command -v scoop >/dev/null 2>&1; then echo "scoop"
      elif command -v choco >/dev/null 2>&1; then echo "choco"
      else echo "missing-winget"; fi ;;
    *) echo "unknown-pm" ;;
  esac
}

# ---------- Install command lookup ------------------------------------------
#
# install_cmd <os> <pm> <tool>  → echoes the exact shell command to install
# <tool> on <os> with <pm>. Returns 1 if no canonical command is known.

install_cmd() {
  local os="$1" pm="$2" tool="$3"
  case "$os:$pm:$tool" in
    # macOS / Homebrew
    macos:brew:git)     echo "brew install git" ;;
    macos:brew:gh)      echo "brew install gh" ;;
    macos:brew:glab)    echo "brew install glab" ;;
    macos:brew:curl)    echo "brew install curl" ;;
    macos:brew:jq)      echo "brew install jq" ;;
    macos:brew:ffmpeg)  echo "brew install ffmpeg" ;;
    macos:brew:python3) echo "brew install python3" ;;

    # Debian/Ubuntu / apt
    linux-debian:apt:git)     echo "sudo apt update && sudo apt install -y git" ;;
    linux-debian:apt:curl)    echo "sudo apt update && sudo apt install -y curl" ;;
    linux-debian:apt:jq)      echo "sudo apt update && sudo apt install -y jq" ;;
    linux-debian:apt:ffmpeg)  echo "sudo apt update && sudo apt install -y ffmpeg" ;;
    linux-debian:apt:python3) echo "sudo apt update && sudo apt install -y python3" ;;
    linux-debian:apt:gh)
      cat <<'EOF'
# gh on Debian/Ubuntu (official repo) — multi-step:
sudo mkdir -p -m 755 /etc/apt/keyrings && \
  out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg && \
  cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
  sudo apt update && sudo apt install -y gh
EOF
      ;;
    linux-debian:apt:glab)
      cat <<'EOF'
# glab on Debian/Ubuntu — official .deb (no apt repo):
DEB=/tmp/glab.deb && curl -L -o $DEB \
  "https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest/downloads/glab_$(uname -m | sed s/x86_64/amd64/).deb" && \
  sudo dpkg -i $DEB && rm -f $DEB
EOF
      ;;

    # Fedora/RHEL/CentOS / dnf
    linux-fedora:dnf:git)     echo "sudo dnf install -y git" ;;
    linux-fedora:dnf:curl)    echo "sudo dnf install -y curl" ;;
    linux-fedora:dnf:jq)      echo "sudo dnf install -y jq" ;;
    linux-fedora:dnf:ffmpeg)  echo "sudo dnf install -y ffmpeg  # may require RPM Fusion repo" ;;
    linux-fedora:dnf:python3) echo "sudo dnf install -y python3" ;;
    linux-fedora:dnf:gh)
      echo "sudo dnf install -y dnf-plugins-core && sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo && sudo dnf install -y gh"
      ;;
    linux-fedora:dnf:glab)
      cat <<'EOF'
# glab on Fedora — official .rpm (no dnf repo):
RPM=/tmp/glab.rpm && curl -L -o $RPM \
  "https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest/downloads/glab_$(uname -m).rpm" && \
  sudo rpm -i $RPM && rm -f $RPM
EOF
      ;;
    # yum is a fallback for older RHEL/CentOS — same packages, different command
    linux-fedora:yum:git)     echo "sudo yum install -y git" ;;
    linux-fedora:yum:curl)    echo "sudo yum install -y curl" ;;
    linux-fedora:yum:jq)      echo "sudo yum install -y jq" ;;
    linux-fedora:yum:ffmpeg)  echo "sudo yum install -y ffmpeg  # may require RPM Fusion / EPEL" ;;
    linux-fedora:yum:python3) echo "sudo yum install -y python3" ;;
    linux-fedora:yum:gh)
      echo "sudo yum install -y yum-utils && sudo yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo && sudo yum install -y gh"
      ;;
    linux-fedora:yum:glab)
      echo "# glab on yum — same .rpm flow as dnf. See https://gitlab.com/gitlab-org/cli/-/releases"
      ;;

    # Arch / pacman
    linux-arch:pacman:git)     echo "sudo pacman -S --noconfirm git" ;;
    linux-arch:pacman:gh)      echo "sudo pacman -S --noconfirm github-cli" ;;
    linux-arch:pacman:glab)    echo "sudo pacman -S --noconfirm glab" ;;
    linux-arch:pacman:curl)    echo "sudo pacman -S --noconfirm curl" ;;
    linux-arch:pacman:jq)      echo "sudo pacman -S --noconfirm jq" ;;
    linux-arch:pacman:ffmpeg)  echo "sudo pacman -S --noconfirm ffmpeg" ;;
    linux-arch:pacman:python3) echo "sudo pacman -S --noconfirm python" ;;

    # openSUSE / zypper
    linux-suse:zypper:git)     echo "sudo zypper install -y git" ;;
    linux-suse:zypper:gh)      echo "sudo zypper install -y gh" ;;
    linux-suse:zypper:glab)
      echo "# glab on openSUSE — official .rpm (no zypper repo):" \
        "RPM=/tmp/glab.rpm && curl -L -o \$RPM 'https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest/downloads/glab_\$(uname -m).rpm' && sudo zypper install --allow-unsigned-rpm -y \$RPM && rm -f \$RPM"
      ;;
    linux-suse:zypper:curl)    echo "sudo zypper install -y curl" ;;
    linux-suse:zypper:jq)      echo "sudo zypper install -y jq" ;;
    linux-suse:zypper:ffmpeg)  echo "sudo zypper install -y ffmpeg  # may require Packman repo" ;;
    linux-suse:zypper:python3) echo "sudo zypper install -y python3" ;;

    # Alpine / apk
    linux-alpine:apk:git)     echo "sudo apk add git" ;;
    linux-alpine:apk:gh)      echo "sudo apk add github-cli  # community repo required" ;;
    linux-alpine:apk:glab)
      echo "# glab on Alpine — no official package. Use the static binary:" \
        "curl -L -o /tmp/glab.tar.gz 'https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest/downloads/glab_\$(uname -m | sed s/x86_64/amd64/).tar.gz' && tar -xzf /tmp/glab.tar.gz -C /tmp && sudo mv /tmp/bin/glab /usr/local/bin/"
      ;;
    linux-alpine:apk:curl)    echo "sudo apk add curl" ;;
    linux-alpine:apk:jq)      echo "sudo apk add jq" ;;
    linux-alpine:apk:ffmpeg)  echo "sudo apk add ffmpeg" ;;
    linux-alpine:apk:python3) echo "sudo apk add python3" ;;

    # Windows / winget (modern default)
    windows:winget:git)     echo "winget install --id Git.Git -e" ;;
    windows:winget:gh)      echo "winget install --id GitHub.cli -e" ;;
    windows:winget:glab)    echo "winget install --id GitLab.GLab -e" ;;
    windows:winget:curl)    echo "# curl ships with Windows 10+. If missing: winget install --id cURL.cURL -e" ;;
    windows:winget:jq)      echo "winget install --id jqlang.jq -e" ;;
    windows:winget:ffmpeg)  echo "winget install --id Gyan.FFmpeg -e" ;;
    windows:winget:python3) echo "winget install --id Python.Python.3.12 -e" ;;

    # Windows / scoop (alternative)
    windows:scoop:git)     echo "scoop install git" ;;
    windows:scoop:gh)      echo "scoop install gh" ;;
    windows:scoop:glab)    echo "scoop install glab" ;;
    windows:scoop:curl)    echo "scoop install curl" ;;
    windows:scoop:jq)      echo "scoop install jq" ;;
    windows:scoop:ffmpeg)  echo "scoop install ffmpeg" ;;
    windows:scoop:python3) echo "scoop install python" ;;

    # Windows / choco (legacy alternative)
    windows:choco:git)     echo "choco install -y git" ;;
    windows:choco:gh)      echo "choco install -y gh" ;;
    windows:choco:glab)    echo "choco install -y glab" ;;
    windows:choco:curl)    echo "choco install -y curl" ;;
    windows:choco:jq)      echo "choco install -y jq" ;;
    windows:choco:ffmpeg)  echo "choco install -y ffmpeg" ;;
    windows:choco:python3) echo "choco install -y python" ;;

    *) return 1 ;;
  esac
}

# ---------- Helpers ---------------------------------------------------------

is_installed() { command -v "$1" >/dev/null 2>&1; }

# Pretty-print a missing-tool row.
emit_missing_row() {
  local tool="$1" tier="$2" cmd="$3"
  local mark
  case "$tier" in
    required)    mark="[✗]" ;;
    recommended) mark="[✗]" ;;
    optional)    mark="[△]" ;;
    *)           mark="[?]" ;;
  esac
  printf '  %s %-8s %s\n' "$mark" "$tool" "${PURPOSE[$tool]}"
  if [[ -n "$cmd" ]]; then
    # Indent multi-line commands.
    while IFS= read -r line; do
      printf '      %s\n' "$line"
    done <<< "$cmd"
  fi
}

emit_pm_missing() {
  local os="$1" pm="$2"
  case "$pm" in
    missing-brew)
      echo "  Homebrew not installed. See https://brew.sh — run:"
      echo "    /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
      ;;
    missing-apt|missing-dnf|missing-pacman|missing-zypper|missing-apk)
      echo "  No supported Linux package manager detected. SCV expects one of: apt / dnf / pacman / zypper / apk."
      ;;
    missing-winget)
      echo "  No supported Windows package manager detected. Install one:"
      echo "    - winget (Windows 10+ App Installer): https://aka.ms/getwinget"
      echo "    - scoop:                              https://scoop.sh"
      echo "    - chocolatey:                         https://chocolatey.org/install"
      ;;
    unknown-pm)
      echo "  Unknown OS or package manager. SCV's install-deps.sh cannot auto-install here."
      echo "  Install each missing tool manually using your distro's documentation."
      ;;
  esac
}

# ---------- Modes -----------------------------------------------------------

mode_check_or_install() {
  local mode="$1"  # check | install
  local os pm
  os=$(detect_os)
  pm=$(detect_pm "$os")

  echo "OS detected:        $os"
  echo "Package manager:    $pm"
  echo ""

  # Bail early on missing PM
  if [[ "$pm" == missing-* || "$pm" == "unknown-pm" ]]; then
    emit_pm_missing "$os" "$pm"
    echo ""
    echo "Re-run after installing a package manager. graphify (Claude Code skill)"
    echo "is separate — see https://github.com/safishamsi/graphify"
    return 2
  fi

  local missing_required=()
  local missing_other=()

  echo "Dependency check:"
  for tool in "${TOOLS[@]}"; do
    if is_installed "$tool"; then
      printf '  [✓] %-8s %s\n' "$tool" "${PURPOSE[$tool]}"
      continue
    fi

    local cmd
    if cmd=$(install_cmd "$os" "$pm" "$tool"); then
      :
    else
      cmd="# no canonical install command known — see upstream docs"
    fi

    emit_missing_row "$tool" "${TIER[$tool]}" "$cmd"

    if [[ "$mode" == "install" ]]; then
      echo ""
      echo "Installing $tool..."
      # Run the (possibly multi-line) command in a subshell.
      bash -c "$cmd"
      local rc=$?
      if [[ $rc -ne 0 ]]; then
        echo "ERROR: install of '$tool' failed (exit $rc). Continuing." >&2
      fi
    fi

    case "${TIER[$tool]}" in
      required)    missing_required+=("$tool") ;;
      recommended) missing_other+=("$tool") ;;
      optional)    missing_other+=("$tool") ;;
    esac
  done

  echo ""
  echo "graphify (Claude Code skill, optional):"
  if [[ -f "$HOME/.claude/skills/graphify/SKILL.md" ]] || \
     compgen -G "$HOME/.claude/plugins/cache/*/skills/graphify/SKILL.md" >/dev/null 2>&1; then
    echo "  [✓] graphify   skill installed (token-efficient graph queries)"
  else
    echo "  [△] graphify   not installed — token-efficient graph queries unavailable"
    echo "      See https://github.com/safishamsi/graphify"
  fi

  echo ""
  if [[ ${#missing_required[@]} -gt 0 ]]; then
    echo "Result: REQUIRED tools missing: ${missing_required[*]}"
    return 1
  elif [[ ${#missing_other[@]} -gt 0 ]]; then
    echo "Result: All required tools installed. Some recommended/optional missing — SCV will graceful-degrade."
    return 0
  else
    echo "Result: All deps installed."
    return 0
  fi
}

mode_print() {
  local oses=(macos linux-debian linux-fedora linux-arch linux-suse linux-alpine windows)
  local pms_for
  declare -A pms_for=(
    [macos]="brew"
    [linux-debian]="apt"
    [linux-fedora]="dnf"
    [linux-arch]="pacman"
    [linux-suse]="zypper"
    [linux-alpine]="apk"
    [windows]="winget"
  )

  echo "Reference install commands per OS / package manager."
  echo "(For a different PM on Windows, use 'scoop' or 'choco' — see README.)"
  echo ""

  for os in "${oses[@]}"; do
    local pm="${pms_for[$os]}"
    echo "── $os ($pm) ──"
    for tool in "${TOOLS[@]}"; do
      local cmd
      if cmd=$(install_cmd "$os" "$pm" "$tool"); then
        echo "  $tool:"
        while IFS= read -r line; do
          printf '    %s\n' "$line"
        done <<< "$cmd"
      else
        echo "  $tool: (no canonical command — see upstream docs)"
      fi
    done
    echo ""
  done

  echo "graphify (Claude Code skill, all OSes):"
  echo "  See https://github.com/safishamsi/graphify"
  echo "  Manual placement: copy SKILL.md to \$HOME/.claude/skills/graphify/SKILL.md"
}

# ---------- Main ------------------------------------------------------------

case "$MODE" in
  --check)   mode_check_or_install check ;;
  --install) mode_check_or_install install ;;
  --print)   mode_print ;;
esac
