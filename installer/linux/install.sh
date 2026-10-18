#!/bin/sh
# TitleSync – Setup für OBS Studio unter Linux (alle Distributionen, OBS normal oder als Flatpak)
# TitleSync – setup for OBS Studio on Linux (any distribution, regular OBS or Flatpak)
#
#   ./install.sh  oder Doppelklick auf das AppImage    installieren / aktualisieren – install / update
#   ./install.sh --uninstall                            entfernen – remove
#
# Das Plugin landet im Benutzerordner von OBS, root-Rechte sind nicht nötig.
# Ohne Terminal (Doppelklick) erscheinen Fenster über zenity oder kdialog.

set -u

name=titlesync
need_major=31
need_minor=1
flatpak_id=com.obsproject.Studio
here=${APPDIR:-$(cd "$(dirname "$0")" && pwd)}
config="${XDG_CONFIG_HOME:-$HOME/.config}"
native_dir="$config/obs-studio/plugins/$name"
flatpak_dir="$HOME/.var/app/$flatpak_id/config/obs-studio/plugins/$name"

case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
de*) de=1 ;;
*) de= ;;
esac
t() { if [ -n "$de" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

# Ausgabe: im Terminal als Text, sonst als Fenster
gui=
if [ ! -t 1 ]; then
	if command -v zenity >/dev/null 2>&1; then
		gui=zenity
	elif command -v kdialog >/dev/null 2>&1; then
		gui=kdialog
	else
		gui=notify
	fi
fi

show() { # $1 = info|error, $2 = Text
	case $gui in
	zenity) zenity "--$1" --title=TitleSync --width=480 --no-markup --text="$2" 2>/dev/null ;;
	kdialog) if [ "$1" = error ]; then kdialog --title TitleSync --error "$2"; else kdialog --title TitleSync --msgbox "$2"; fi 2>/dev/null ;;
	notify) command -v notify-send >/dev/null 2>&1 && notify-send TitleSync "$2" ;;
	*) if [ "$1" = error ]; then printf '%s\n' "$2" >&2; else printf '%s\n' "$2"; fi ;;
	esac
}
fail() {
	show error "$1"
	exit 1
}
ask() { # $1 = Frage, $2 = Ja-Knopf, $3 = Nein-Knopf; Erfolg = Ja
	case $gui in
	zenity) zenity --question --title=TitleSync --width=480 --no-markup --text="$1" --ok-label="$2" --cancel-label="$3" 2>/dev/null ;;
	kdialog) kdialog --title TitleSync --yesno "$1" --yes-label "$2" --no-label "$3" 2>/dev/null ;;
	notify) return 0 ;;
	*)
		printf '%s [%s = Enter / %s = n] ' "$1" "$2" "$3"
		read -r answer || return 0
		case $answer in n | N | no | nein | Nein) return 1 ;; esac
		return 0
		;;
	esac
}

version_ok() { # $1 = z. B. 32.1.1; unbekannte Version blockiert nicht
	major=${1%%.*}
	rest=${1#*.}
	minor=${rest%%.*}
	case "$major$minor" in '' | *[!0-9]*) return 0 ;; esac
	[ "$major" -gt $need_major ] || { [ "$major" -eq $need_major ] && [ "$minor" -ge $need_minor ]; }
}

if [ "$(id -u)" = 0 ]; then
	fail "$(t 'Bitte ohne sudo starten – TitleSync wird nur für deinen Benutzer installiert.' \
		'Please run without sudo – TitleSync is installed for your user only.')"
fi

if pgrep -x obs >/dev/null 2>&1; then
	fail "$(t 'OBS läuft noch. Bitte OBS schließen und das Setup erneut starten.' \
		'OBS is still running. Please close OBS and start the setup again.')"
fi

uninstall() {
	rm -rf "$native_dir" "$flatpak_dir"
	show info "$(t 'TitleSync wurde entfernt. Deine Einstellungen bleiben erhalten.' \
		'TitleSync has been removed. Your settings are kept.')"
	exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

if [ ! -f "$here/$name/bin/64bit/$name.so" ]; then
	fail "$(t 'Plugin-Dateien nicht gefunden. Bitte das Archiv vollständig entpacken und install.sh aus dem entpackten Ordner starten.' \
		'Plugin files not found. Please extract the whole archive and run install.sh from the extracted folder.')"
fi

if [ -d "$native_dir" ] || [ -d "$flatpak_dir" ]; then
	ask "$(t 'TitleSync ist bereits installiert. Aktualisieren oder entfernen?' \
		'TitleSync is already installed. Update or remove it?')" \
		"$(t 'Aktualisieren' 'Update')" "$(t 'Entfernen' 'Remove')" || uninstall
fi

# Welche OBS-Installationen gibt es? Normal (Paketverwaltung) und/oder Flatpak
native_ver=
native=
if command -v obs >/dev/null 2>&1; then
	native=1
	native_ver=$(obs --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
fi
flatpak_ver=
flatpak=
if command -v flatpak >/dev/null 2>&1; then
	line=$(flatpak list --app --columns=application,version 2>/dev/null | awk -v id=$flatpak_id '$1 == id { print; exit }')
	if [ -n "$line" ]; then
		flatpak=1
		flatpak_ver=$(printf '%s\n' "$line" | awk '{ print $2 }')
	fi
fi

if [ -z "$native" ] && [ -z "$flatpak" ]; then
	fail "$(t 'OBS Studio wurde nicht gefunden. Bitte zuerst OBS installieren (Paketverwaltung oder Flathub) und das Setup danach erneut starten.' \
		'OBS Studio was not found. Please install OBS first (package manager or Flathub) and start the setup again.')"
fi

# Zielordner als Positionsparameter, damit Leerzeichen im Pfad nicht stören
set --
skipped=
if [ -n "$native" ]; then
	if ! version_ok "$native_ver"; then
		skipped="$skipped OBS $native_ver"
	else
		for system_copy in /usr/lib/obs-plugins/$name.so /usr/lib/*/obs-plugins/$name.so /usr/lib64/obs-plugins/$name.so; do
			if [ -f "$system_copy" ]; then
				fail "$(t "TitleSync ist bereits systemweit installiert ($system_copy, z. B. über das .deb-Paket). Bitte zuerst entfernen (sudo apt remove $name), sonst lädt OBS das Plugin doppelt." \
					"TitleSync is already installed system-wide ($system_copy, e.g. via the .deb package). Please remove it first (sudo apt remove $name), otherwise OBS loads the plugin twice.")"
			fi
		done
		set -- "$@" "$native_dir"
	fi
fi
if [ -n "$flatpak" ]; then
	if version_ok "$flatpak_ver"; then
		set -- "$@" "$flatpak_dir"
	else
		skipped="$skipped OBS-Flatpak $flatpak_ver"
	fi
fi

skipped=${skipped# }
if [ $# -eq 0 ]; then
	fail "$(t "Dein OBS ist zu alt ($skipped). TitleSync braucht OBS $need_major.$need_minor oder neuer – bitte OBS aktualisieren." \
		"Your OBS is too old ($skipped). TitleSync needs OBS $need_major.$need_minor or newer – please update OBS.")"
fi

for dir in "$@"; do
	rm -rf "$dir"
	mkdir -p "$dir" || fail "$(t 'Ordner konnte nicht angelegt werden:' 'Could not create folder:') $dir"
	cp -R "$here/$name/." "$dir/" || fail "$(t 'Kopieren fehlgeschlagen nach' 'Copying failed to') $dir"
	chmod -R u+w "$dir"
done

message="$(t 'TitleSync wurde installiert. OBS starten → Docks → TitleSync.' \
	'TitleSync has been installed. Start OBS → Docks → TitleSync.')"
for dir in "$@"; do message="$message
  $dir"; done
if [ -n "$skipped" ]; then
	message="$message

$(t "Übersprungen, weil zu alt: $skipped (OBS $need_major.$need_minor oder neuer nötig)." \
		"Skipped because too old: $skipped (OBS $need_major.$need_minor or newer needed).")"
fi
if ! command -v ollama >/dev/null 2>&1; then
	message="$message

$(t 'Für die lokale KI fehlt noch Ollama. Im Terminal installieren:' 'Ollama is still missing for the local AI. Install it in a terminal:')
  curl -fsSL https://ollama.com/install.sh | sh
  ollama pull qwen3-vl:4b-instruct
$(t 'Alternativ in TitleSync einen Online-Anbieter wählen.' 'Or choose an online provider in TitleSync.')"
fi
show info "$message"
