#!/bin/bash
# bash appimages_test.sh — runs appimages.sh in a scratch $HOME against a fake
# AppImage (a script that answers --appimage-extract from a tree next to it)
# and a curl stub that "downloads" another fake.
set -euo pipefail
script=$(cd "$(dirname "$0")" && pwd)/appimages.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export HOME=$t/home; unset XDG_DATA_HOME XDG_CACHE_HOME APPIMAGES_DIR
mkdir -p "$HOME/AppImages" "$t/bin"
apps=$HOME/.local/share/applications
icons=$HOME/.local/share/icons/hicolor
fail() { echo "FAIL: $*"; exit 1; }
run() { PATH="$t/bin:$PATH" bash "$script" "$@"; }

# fake <path> <version>: an AppImage whose squashfs is $path.tree.
fake() {
  local tree=$1.tree
  rm -rf "$tree"; mkdir -p "$tree/usr/share/icons/hicolor/512x512/apps"
  printf '\x89PNG\r\n\x1a\n%s' "$2" > "$tree/usr/share/icons/hicolor/512x512/apps/orca-ide.png"
  ln -s usr/share/icons/hicolor/512x512/apps/orca-ide.png "$tree/orca-ide.png"
  ln -s orca-ide.png "$tree/.DirIcon"
  cat > "$tree/orca-ide.desktop" <<EOF
[Desktop Entry]
Name=Orca
Exec=AppRun %U
TryExec=AppRun
Icon=orca-ide
X-AppImage-Version=$2
MimeType=text/markdown;text/csv;x-scheme-handler/orca;

[Desktop Action New]
Name=New window
Exec=AppRun --new-window
EOF
  cat > "$1" <<EOF
#!/bin/bash
case \$1 in
  --appimage-updateinformation) echo 'gh-releases-zsync|a|orca|latest|Orca-*.AppImage.zsync' ;;
  --appimage-extract)
    out=\$PWD/squashfs-root; mkdir -p "\$out"; cd '$tree'
    find . -mindepth 1 | sed 's|^\./||' | while read -r f; do
      if [[ \$f == \$2 ]]; then cp -P --parents "\$f" "\$out/"; fi
    done ;;
esac
EOF
}

app=$HOME/AppImages/Orca.AppImage
fake "$app" 1.0.0   # not executable yet, as a browser saves it
launcher=$apps/appimage-orca-ide.desktop

# list: metadata out of the AppImage, not in the menu yet.
out=$(run list)
[[ $(jq -r '.[0] | [.file, .id, .name, .version, .registered, .update] | join(" ")' <<<"$out") == "Orca.AppImage orca-ide Orca 1.0.0 false gh-releases-zsync|a|orca|latest|Orca-*.AppImage.zsync" ]] || fail "list: $out"
[[ -f $(jq -r '.[0].icon' <<<"$out") ]] || fail "list: no cached icon"
[[ -x $app ]] || fail "list: AppImage not made executable"

# add: launcher on the full path, own icon, no TryExec, no text/* types, path recorded.
run add "$app"
[[ -f $launcher ]] || fail "add: no launcher"
grep -qxF "Exec=\"$app\" %U" "$launcher" || fail "add: Exec: $(cat "$launcher")"
grep -qxF "Exec=\"$app\" --new-window" "$launcher" || fail "add: action Exec"
grep -qxF "Icon=appimage-orca-ide" "$launcher" || fail "add: Icon"
grep -qxF "MimeType=x-scheme-handler/orca;" "$launcher" || fail "add: MimeType"
grep -qxF "X-AppImage-Path=$app" "$launcher" || fail "add: X-AppImage-Path"
grep -q '^TryExec=' "$launcher" && fail "add: TryExec kept"
[[ -f $icons/512x512/apps/appimage-orca-ide.png ]] || fail "add: icon"
[[ $(run list | jq '.[0].registered') == true ]] || fail "list after add"

# The app replaced itself (self-update): list refreshes the launcher.
fake "$app" 2.0.0; touch -d '+1 min' "$app"
[[ $(run list | jq -r '.[0].version') == 2.0.0 ]] || fail "list after self-update"
grep -qxF "X-AppImage-Version=2.0.0" "$launcher" || fail "launcher not refreshed"

# unregister: launcher and icon go, the file stays.
run unregister "$app"
[[ ! -e $launcher && ! -e $icons/512x512/apps/appimage-orca-ide.png && -f $app ]] || fail "unregister"

# update: downloaded over the file; a registered app gets a fresh launcher.
run add "$app"
fake "$t/new.AppImage" 3.0.0
printf '#!/bin/bash\n[[ $CURL_FAIL ]] && exit 22\nwhile [[ $1 ]]; do [[ $1 == -o ]] && { cp %q "$2"; shift; }; shift; done\n' "$t/new.AppImage" > "$t/bin/curl"
chmod +x "$t/bin/curl"
CURL_FAIL=1 run update "$app" https://x/Orca-3.AppImage 2>/dev/null && fail "update: failed download reported ok"
grep -qxF "X-AppImage-Version=2.0.0" "$launcher" || fail "update: failed download touched the app"
[[ -z $(ls -A "$HOME/AppImages" | grep -v '^Orca.AppImage') ]] || fail "update: partial file left"
run update "$app" https://x/Orca-3.AppImage
[[ -x $app ]] || fail "update: not executable"
grep -qxF "X-AppImage-Version=3.0.0" "$launcher" || fail "update: launcher not refreshed"

# The file vanished: list drops its launcher, icon and cache.
mv "$app" "$t/away.AppImage"
[[ $(run list) == "[]" ]] || fail "list without files"
[[ ! -e $launcher && ! -e $icons/512x512/apps/appimage-orca-ide.png ]] || fail "orphan launcher kept"
[[ -z $(ls -A "$HOME/.cache/appimages") ]] || fail "orphan cache kept"

# delete: file, launcher, icon and cache.
mv "$t/away.AppImage" "$app"
run add "$app"
run delete "$app"
[[ ! -e $app && ! -e $launcher && ! -e $icons/512x512/apps/appimage-orca-ide.png && -z $(ls -A "$HOME/.cache/appimages") ]] || fail "delete"

# A path outside the folder is refused.
run add "$t/new.AppImage" 2>/dev/null && fail "add outside the folder"

echo ok
