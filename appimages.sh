#!/bin/bash
# AppImages in ~/AppImages and their launchers in the app menu, for Panel.qml.
#   list                         JSON of every AppImage in the folder; refreshes the launcher
#                                of a file that changed (self-update), drops orphaned ones
#   add|unregister|delete <file>
#   release <owner/repo> [tag]   GitHub release JSON (latest by default)
#   update <file> <url>          download over the file
set -euo pipefail

dir=${APPIMAGES_DIR:-$HOME/AppImages}
data=${XDG_DATA_HOME:-$HOME/.local/share}
apps=$data/applications
icons=$data/icons/hicolor
cache=${XDG_CACHE_HOME:-$HOME/.cache}/appimages
shopt -s nullglob nocaseglob

# First value of a key in a .desktop file.
field() {
  sed -n "0,/^$2=/s/^$2=//p" "$1"
}

# Pulls the top-level .desktop, the icon and the update info out of the AppImage
# into the cache, unless the cache already matches the file's mtime and size.
# Succeeds only when it extracted anew.
inspect() {
  local app=$1 c=$cache/${1##*/} stamp tmp
  stamp=$(stat -c '%Y %s' "$app")
  if [[ -f $c/stamp && $(<"$c/stamp") == "$stamp" ]]; then
    return 1
  fi
  chmod +x "$app"
  rm -rf "$c"
  mkdir -p "$c"
  tmp=$(mktemp -d)
  (
    cd "$tmp"
    timeout 30 "$app" --appimage-extract '*.desktop' >/dev/null 2>&1 || true
    timeout 30 "$app" --appimage-extract .DirIcon >/dev/null 2>&1 || true
    # .DirIcon is usually a chain of symlinks into usr/share/icons.
    f=squashfs-root/.DirIcon
    for _ in 1 2 3 4 5; do
      [[ -L $f ]] || break
      target=$(readlink "$f")
      if [[ $target == /* ]]; then
        target=${target#/}
      else
        target=$(realpath -m --relative-to=squashfs-root "$(dirname "$f")/$target")
      fi
      timeout 30 "$app" --appimage-extract "$target" >/dev/null 2>&1 || true
      f=squashfs-root/$target
    done
    if [[ -f $f ]]; then
      if [[ $(file -b --mime-type "$f") == image/svg* ]]; then
        cp -L "$f" "$c/icon.svg"
      else
        cp -L "$f" "$c/icon.png"
      fi
    fi
    desktop=$(find squashfs-root -maxdepth 1 -name '*.desktop' -print -quit 2>/dev/null)
    if [[ -n $desktop ]]; then
      cp -L "$desktop" "$c/app.desktop"
      id=${desktop##*/}
      echo "${id%.desktop}" > "$c/id"
    else
      # No .desktop inside: a plain one named after the file.
      name=${app##*/}
      name=${name%.*}
      printf '[Desktop Entry]\nType=Application\nName=%s\nExec=AppRun\nTerminal=false\n' "$name" > "$c/app.desktop"
      tr -c 'A-Za-z0-9._-' '-' <<<"${name,,}" | sed 's/-*$//' > "$c/id"
    fi
  )
  timeout 10 "$app" --appimage-updateinformation 2>/dev/null > "$c/update" || true
  rm -rf "$tmp"
  echo "$stamp" > "$c/stamp"
}

launcher() {
  echo "$apps/appimage-$(<"$cache/${1##*/}/id").desktop"
}

registered() {
  local l
  l=$(launcher "$1")
  [[ -f $l ]] && grep -qxF "X-AppImage-Path=$1" "$l"
}

drop_icons() {
  rm -f "$icons"/*/apps/"appimage-$1".*
}

# The AppImage's own .desktop pointed at the file: own icon, no TryExec, no
# text/* types (or the app would open .md files), the path recorded for list.
# ponytail: path quoted, not escaped — a path with " ` $ \ would break Exec.
register() {
  local app=$1 c=$cache/${1##*/} id icon=""
  id=$(<"$c/id")
  drop_icons "$id"
  if [[ -f $c/icon.svg ]]; then
    mkdir -p "$icons/scalable/apps"
    cp "$c/icon.svg" "$icons/scalable/apps/appimage-$id.svg"
    icon=appimage-$id
  elif [[ -f $c/icon.png ]]; then
    mkdir -p "$icons/512x512/apps"
    cp "$c/icon.png" "$icons/512x512/apps/appimage-$id.png"
    icon=appimage-$id
  fi
  mkdir -p "$apps"
  awk -v path="$app" -v icon="$icon" '
    /^\[/ { print; if ($0 == "[Desktop Entry]") print "X-AppImage-Path=" path; next }
    /^(TryExec|X-AppImage-Path)=/ { next }
    /^Exec=/ {
      rest = substr($0, 6); i = index(rest, " ")
      print "Exec=\"" path "\"" (i ? substr(rest, i) : ""); next
    }
    /^Icon=/ && icon != "" { print "Icon=" icon; next }
    /^MimeType=/ {
      n = split(substr($0, 10), types, ";"); kept = ""
      for (k = 1; k <= n; k++) if (types[k] != "" && types[k] !~ /^text\//) kept = kept types[k] ";"
      if (kept != "") print "MimeType=" kept
      next
    }
    { print }
  ' "$c/app.desktop" > "$apps/.appimage-$id.desktop.tmp"
  mv -f "$apps/.appimage-$id.desktop.tmp" "$apps/appimage-$id.desktop"
  update-desktop-database "$apps" 2>/dev/null || true
}

unregister() {
  local app=$1 id
  inspect "$app" || true
  id=$(<"$cache/${app##*/}/id")
  if registered "$app"; then
    rm -f "$(launcher "$app")"
    drop_icons "$id"
    update-desktop-database "$apps" 2>/dev/null || true
  fi
}

# Launchers and cache entries whose AppImage is gone.
prune() {
  local l p id c
  for l in "$apps"/appimage-*.desktop; do
    p=$(field "$l" X-AppImage-Path)
    if [[ -n $p && ! -e $p ]]; then
      id=${l##*/appimage-}
      rm -f "$l"
      drop_icons "${id%.desktop}"
    fi
  done
  for c in "$cache"/*/; do
    c=${c%/}
    [[ -e $dir/${c##*/} ]] || rm -rf "$c"
  done
}

list() {
  local app c icon
  mkdir -p "$dir"
  prune
  for app in "$dir"/*.appimage; do
    if inspect "$app" && registered "$app"; then
      register "$app"
    fi
    c=$cache/${app##*/}
    icon=""
    [[ -f $c/icon.png ]] && icon=$c/icon.png
    [[ -f $c/icon.svg ]] && icon=$c/icon.svg
    jq -n --arg file "${app##*/}" --arg path "$app" --arg id "$(<"$c/id")" \
      --arg name "$(field "$c/app.desktop" Name)" --arg version "$(field "$c/app.desktop" X-AppImage-Version)" \
      --arg icon "$icon" --arg update "$(<"$c/update")" \
      --argjson registered "$(registered "$app" && echo true || echo false)" \
      --argjson mtime "$(stat -c %Y "$app")" \
      '{$file, $path, $id, $name, $version, $icon, $update, $registered, $mtime}'
  done | jq -s .
}

update() {
  local app=$1 url=$2 part
  part=$dir/.${app##*/}.part
  if curl -fsSL --retry 2 -o "$part" "$url"; then
    chmod +x "$part"
    mv -f "$part" "$app"
    if inspect "$app" && registered "$app"; then
      register "$app"
    fi
  else
    rm -f "$part"
    echo "download failed: $url" >&2
    exit 1
  fi
}

release() {
  local url=https://api.github.com/repos/$1/releases/latest
  if [[ ${2:-latest} != latest ]]; then
    url=https://api.github.com/repos/$1/releases/tags/$2
  fi
  curl -fsSL -H 'Accept: application/vnd.github+json' "$url"
}

# Only files right in the folder: the paths come from the panel.
file_arg() {
  if [[ $(dirname -- "$1") != "$dir" || ! -f $1 ]]; then
    echo "not an AppImage in $dir: $1" >&2
    exit 1
  fi
}

case ${1:-} in
  list) list ;;
  add) file_arg "$2"; inspect "$2" || true; register "$2" ;;
  unregister) file_arg "$2"; unregister "$2" ;;
  delete) file_arg "$2"; unregister "$2"; rm -f "$2"; rm -rf "${cache:?}/${2##*/}" ;;
  release) release "$2" "${3:-latest}" ;;
  update) file_arg "$2"; update "$2" "$3" ;;
  *) echo "usage: ${0##*/} list | add|unregister|delete <file> | release <owner/repo> [tag] | update <file> <url>" >&2; exit 2 ;;
esac
