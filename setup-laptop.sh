#!/usr/bin/env bash
# Instalación de una laptop nueva con los comandos que uso.
# curl -fsSL https://raw.githubusercontent.com/alejogtz/alejogtz/main/setup-laptop.sh | bash
set -euo pipefail

# curl | bash deja stdin en el pipe. sudo tiene que leer la contraseña de la terminal.
run_sudo() {
  if [[ -r /dev/tty ]]; then
    sudo "$@" </dev/tty
  else
    sudo "$@"
  fi
}

# --- Dotfiles (repo bare en ~/.cfg) ---
if [[ ! -d "$HOME/.cfg" ]]; then
  git clone --bare git@github.com:alejogtz/configs.git "$HOME/.cfg"
fi

conf() {
  /usr/bin/git --git-dir="$HOME/.cfg/" --work-tree="$HOME" "$@"
}

# Git lista cada archivo en conflicto en una línea indentada. Con set -e y
# pipefail, ese fallo no puede ir en un pipeline: abortaría el script.
backup_checkout_conflicts() {
  local backup="$HOME/.cfg-backup"
  local line path
  mkdir -p "$backup"
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]+[^[:space:]]+$ ]] || continue
    path="${line#"${line%%[![:space:]]*}"}"
    mkdir -p "$backup/$(dirname "$path")"
    mv "$HOME/$path" "$backup/$path"
  done
}

checkout_log=$(mktemp)
if ! conf checkout >"$checkout_log" 2>&1; then
  backup_checkout_conflicts <"$checkout_log"
  conf checkout
fi
rm -f "$checkout_log"

conf config --local status.showUntrackedFiles no

# --- cheat 4.2.3 ---
# Aparta un directorio que ya exista y no sea el repo que vamos a clonar.
move_aside_if_present() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  local backup="$HOME/.cfg-backup/${path#"$HOME"/}"
  mkdir -p "$(dirname "$backup")"
  if [[ -e "$backup" ]]; then
    backup="${backup}.$(date +%Y%m%d%H%M%S)"
  fi
  mv "$path" "$backup"
}

if ! { [[ -x /usr/bin/cheat ]] && [[ "$(/usr/bin/cheat --version 2>/dev/null || true)" == "4.2.3" ]]; }; then
  curl -sSL https://github.com/cheat/cheat/releases/download/4.2.3/cheat-linux-amd64.gz --insecure -o "$HOME/cheat.gz"
  gzip -c -d "$HOME/cheat.gz" >"$HOME/cheat" && rm "$HOME/cheat.gz"
  chmod +x "$HOME/cheat"
  if [[ -e /usr/bin/cheat ]]; then
    run_sudo mkdir -p "$HOME/.cfg-backup/usr/bin"
    run_sudo mv /usr/bin/cheat "$HOME/.cfg-backup/usr/bin/cheat"
  fi
  run_sudo mv "$HOME/cheat" /usr/bin/cheat
  run_sudo chmod +x /usr/bin/cheat
fi

community="$HOME/.config/cheat/cheatsheets/community"
if [[ ! -d "$community/.git" ]]; then
  move_aside_if_present "$community"
  mkdir -p "$(dirname "$community")"
  git clone https://github.com/cheat/cheatsheets.git "$community"
fi

# En master este script ya no existe (404). La copia que coincide con cheat 4.2.3 está en ese tag.
mkdir -p "$HOME/.local/bin"
curl --insecure -fsSL https://raw.githubusercontent.com/cheat/cheat/4.2.3/scripts/git/cheatsheets -o "$HOME/.local/bin/cheatsheets"
chmod +x "$HOME/.local/bin/cheatsheets"

personal="$HOME/.config/cheat/cheatsheets/personal"
if [[ ! -d "$personal/.git" ]]; then
  move_aside_if_present "$personal"
  git clone git@github.com:alejogtz/cheatsheets.git "$personal"
fi

sed -i -e 's/^style: monokai/style: arduino/' "$HOME/.config/cheat/conf.yml"
