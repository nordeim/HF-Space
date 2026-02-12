#!/bin/bash
# Homebrew Non‑Interactive Installer for Debian Linux (trixie)
# Usage: bash install-homebrew-noninteractive.sh
# No options, no prompts, no sudo escalation for Homebrew files.
# https://chat.deepseek.com/share/590yjj98hxl0w4dhcc

set -u

abort() {
  printf "%s\n" "$@" >&2
  exit 1
}

# Force non‑interactive mode – we never want prompts
export NONINTERACTIVE=1
# Unset any conflicting environment variables
unset INTERACTIVE CI

# Bash is required
if [ -z "${BASH_VERSION:-}" ]; then
  abort "Bash is required to interpret this script."
fi

# Prevent POSIX mode (breaks process substitution)
if [[ -n "${POSIXLY_CORRECT+1}" ]]; then
  abort "Bash must not run in POSIX mode. Please unset POSIXLY_CORRECT and try again."
fi

# Do not run as root
if [[ $EUID -eq 0 ]]; then
  abort "This script must NOT be run as root. It installs Homebrew in your home directory."
fi

# ----------------------------------------------------------------------
# Output helpers (coloured only if interactive TTY, but we keep for clarity)
if [[ -t 1 ]]; then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"
tty_underline="$(tty_escape "4;39")"

shell_join() {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"; do
    printf " %s" "${arg// /\ }"
  done
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

ohai() {
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
  printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")" >&2
}

# ----------------------------------------------------------------------
# Ensure USER is set
if [[ -z "${USER-}" ]]; then
  USER="$(chomp "$(id -un)")"
  export USER
fi

# ----------------------------------------------------------------------
# Linux‑only installation paths
HOMEBREW_PREFIX="/home/${USER}/.linuxbrew"
HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}/Homebrew"
HOMEBREW_CACHE="${HOME}/.cache/Homebrew"
HOMEBREW_CORE="${HOMEBREW_REPOSITORY}/Library/Taps/homebrew/homebrew-core"

export HOMEBREW_NO_ANALYTICS_THIS_RUN=1
export HOMEBREW_NO_ANALYTICS_MESSAGE_OUTPUT=1

# ----------------------------------------------------------------------
# Tool detection & version requirements
REQUIRED_RUBY_VERSION=3.4
REQUIRED_GLIBC_VERSION=2.13
REQUIRED_CURL_VERSION=7.41.0
REQUIRED_GIT_VERSION=2.7.0

# ----------------------------------------------------------------------
# Utility functions (kept from original)
execute() {
  if ! "$@"; then
    abort "$(printf "Failed during: %s" "$(shell_join "$@")")"
  fi
}

retry() {
  local tries="$1" n="$1" pause=2
  shift
  if ! "$@"; then
    while [[ $((--n)) -gt 0 ]]; do
      warn "$(printf "Trying again in %d seconds: %s" "${pause}" "$(shell_join "$@")")"
      sleep "${pause}"
      ((pause *= 2))
      if "$@"; then
        return
      fi
    done
    abort "$(printf "Failed %d times doing: %s" "${tries}" "$(shell_join "$@")")"
  fi
}

major_minor() {
  echo "${1%%.*}.$(x="${1#*.}"; echo "${x%%.*}")"
}

version_ge() {
  [[ "${1%.*}" -gt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -ge "${2#*.}" ]]
}

version_lt() {
  [[ "${1%.*}" -lt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -lt "${2#*.}" ]]
}

which() {
  type -P "$@"
}

find_tool() {
  if [[ $# -ne 1 ]]; then return 1; fi
  local executable
  while read -r executable; do
    if [[ "${executable}" != /* ]]; then
      warn "Ignoring ${executable} (relative paths don't work)"
    elif "test_$1" "${executable}"; then
      echo "${executable}"
      break
    fi
  done < <(which -a "$1")
}

test_curl() {
  [[ -x "$1" ]] || return 1
  [[ "$1" == "/snap/bin/curl" ]] && return 1
  local curl_version_output curl_name_and_version
  curl_version_output="$("$1" --version 2>/dev/null)"
  curl_name_and_version="${curl_version_output%% (*}"
  version_ge "$(major_minor "${curl_name_and_version##* }")" "$(major_minor "${REQUIRED_CURL_VERSION}")"
}

test_git() {
  [[ -x "$1" ]] || return 1
  local git_version_output
  git_version_output="$("$1" --version 2>/dev/null)"
  if [[ "${git_version_output}" =~ "git version "([^ ]*).* ]]; then
    version_ge "$(major_minor "${BASH_REMATCH[1]}")" "$(major_minor "${REQUIRED_GIT_VERSION}")"
  else
    abort "Unexpected Git version: '${git_version_output}'!"
  fi
}

test_ruby() {
  [[ -x "$1" ]] || return 1
  "$1" --enable-frozen-string-literal --disable=gems,did_you_mean,rubyopt -rrubygems -e \
    "abort if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('${REQUIRED_RUBY_VERSION}')" 2>/dev/null
}

no_usable_ruby() {
  [[ -z "$(find_tool ruby)" ]] || ! ruby -e "require 'erb'"
}

outdated_glibc() {
  local glibc_version
  glibc_version="$(ldd --version | head -n1 | grep -o '[0-9.]*$' | grep -o '^[0-9]\+\.[0-9]\+')"
  version_lt "${glibc_version}" "${REQUIRED_GLIBC_VERSION}"
}

# ----------------------------------------------------------------------
# Dependency installation (non‑interactive sudo if available)
install_debian_deps() {
  if ! command -v sudo >/dev/null; then
    abort "sudo is not installed. Please install curl, git, and build-essential manually."
  fi

  # Check if we can run sudo non‑interactively
  if ! sudo -n true 2>/dev/null; then
    warn "sudo requires a password or TTY – cannot install dependencies automatically."
    warn "Please ensure the following packages are installed: curl, git, build-essential."
    return 1
  fi

  local pkgs=()
  command -v curl >/dev/null || pkgs+=(curl)
  command -v git >/dev/null || pkgs+=(git)
  # Check for build-essential via dpkg
  if ! dpkg -s build-essential >/dev/null 2>&1; then
    pkgs+=(build-essential)
  fi

  if [[ ${#pkgs[@]} -gt 0 ]]; then
    ohai "Installing missing packages: ${pkgs[*]}"
    sudo -n apt-get update -qq
    sudo -n apt-get install -y -qq "${pkgs[@]}"
  fi
}

# ----------------------------------------------------------------------
# Main installation
ohai "Homebrew non‑interactive installer for Debian Linux"

# 1. Install dependencies (if possible)
install_debian_deps || true   # continue even if sudo fails, we will check tools anyway

# 2. Verify curl
if ! command -v curl >/dev/null; then
  abort "curl is required. Please install it (e.g., sudo apt install curl)."
fi
USABLE_CURL="$(find_tool curl)"
if [[ -z "${USABLE_CURL}" ]]; then
  abort "cURL version ${REQUIRED_CURL_VERSION} or newer is required. Please upgrade."
elif [[ "${USABLE_CURL}" != /usr/bin/curl ]]; then
  export HOMEBREW_CURL_PATH="${USABLE_CURL}"
  ohai "Found cURL: ${HOMEBREW_CURL_PATH}"
fi

# 3. Verify git
if ! command -v git >/dev/null; then
  abort "Git is required. Please install it (e.g., sudo apt install git)."
fi
USABLE_GIT="$(find_tool git)"
if [[ -z "${USABLE_GIT}" ]]; then
  abort "Git version ${REQUIRED_GIT_VERSION} or newer is required. Please upgrade."
elif [[ "${USABLE_GIT}" != /usr/bin/git ]]; then
  export HOMEBREW_GIT_PATH="${USABLE_GIT}"
  ohai "Found Git: ${HOMEBREW_GIT_PATH}"
fi

# 4. Check Ruby (optional, portable fallback)
if no_usable_ruby; then
  if outdated_glibc; then
    abort "Glibc too old. Your system does not meet Homebrew on Linux requirements."
  else
    export HOMEBREW_FORCE_VENDOR_RUBY=1
    ohai "Forcing vendor Ruby (system Ruby missing or too old)"
  fi
fi

# 5. Create directories (no sudo – user owns /home/user)
ohai "Creating Homebrew directories"
execute mkdir -p "${HOMEBREW_PREFIX}"
execute mkdir -p "${HOMEBREW_REPOSITORY}"
execute mkdir -p "${HOMEBREW_CACHE}"

# 6. Clone/update Homebrew/brew
ohai "Downloading and installing Homebrew/brew"
(
  cd "${HOMEBREW_REPOSITORY}" >/dev/null || exit 1

  # Use default remote, allow override via env
  HOMEBREW_BREW_GIT_REMOTE="${HOMEBREW_BREW_GIT_REMOTE:-https://github.com/Homebrew/brew}"
  HOMEBREW_CORE_GIT_REMOTE="${HOMEBREW_CORE_GIT_REMOTE:-https://github.com/Homebrew/homebrew-core}"

  execute "${USABLE_GIT}" -c init.defaultBranch=main init --quiet
  execute "${USABLE_GIT}" config remote.origin.url "${HOMEBREW_BREW_GIT_REMOTE}"
  execute "${USABLE_GIT}" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  execute "${USABLE_GIT}" config --bool fetch.prune true
  execute "${USABLE_GIT}" config --bool core.autocrlf false
  execute "${USABLE_GIT}" config --bool core.symlinks true

  retry 5 "${USABLE_GIT}" fetch --quiet --force origin
  retry 5 "${USABLE_GIT}" fetch --quiet --force --tags origin

  execute "${USABLE_GIT}" remote set-head origin --auto >/dev/null

  LATEST_GIT_TAG="$("${USABLE_GIT}" -c column.ui=never tag --list --sort=-version:refname | head -n1)"
  if [[ -z "${LATEST_GIT_TAG}" ]]; then
    abort "Failed to query latest Homebrew/brew Git tag."
  fi
  execute "${USABLE_GIT}" checkout --quiet --force -B stable "${LATEST_GIT_TAG}"

  if [[ "${HOMEBREW_REPOSITORY}" != "${HOMEBREW_PREFIX}" ]]; then
    # Symlink brew into bin
    execute mkdir -p "${HOMEBREW_PREFIX}/bin"
    execute ln -sf "../Homebrew/bin/brew" "${HOMEBREW_PREFIX}/bin/brew"
  fi
)

# 7. Run brew update to complete setup
ohai "Running brew update..."
execute "${HOMEBREW_PREFIX}/bin/brew" update --force --quiet

echo 'eval "\$(/home/user/.linuxbrew/bin/brew shellenv)"' >> /home/user/.bashrc
echo 'eval "\$(/home/user/.linuxbrew/bin/brew shellenv)"' >> /home/user/.profile
eval "$(/home/user/.linuxbrew/bin/brew shellenv)"
which brew && brew install beautifulsoup4 charset-normalizer defusedxml flatbuffers httptools magika markdownify markitdown mpmath numpy onnxruntime packaging protobuf python-dotenv PyYAML requests six soupsieve sympy urllib3 uvloop watchfiles websockets

# ----------------------------------------------------------------------
# Completion
ohai "Installation successful!"
echo

cat <<EOS
${tty_bold}Homebrew is now installed to:${tty_reset}
  ${HOMEBREW_PREFIX}

${tty_bold}Next steps:${tty_reset}
1. Add Homebrew to your PATH by running:

   echo 'eval "\$(${HOMEBREW_PREFIX}/bin/brew shellenv)"' >> ~/.bashrc
   eval "\$(${HOMEBREW_PREFIX}/bin/brew shellenv)"

2. Verify the installation:

   brew doctor

3. (Optional) Install build tools (if not already present):

   brew install gcc

For more documentation: ${tty_underline}https://docs.brew.sh${tty_reset}

EOS
