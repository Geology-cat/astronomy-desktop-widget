#!/bin/zsh
set -euo pipefail

# アプリ、README、Gatekeeper解除AppleScript、アプリケーションリンクをDMGへまとめます。
script_dir="${0:A:h}"
project_dir="${script_dir:h}"
output_dir="$project_dir/dist"
staging_dir="$project_dir/.build/dmg-staging"
rw_dmg="$project_dir/.build/AstronomyWidget-rw.dmg"
mount_dir=""
is_mounted=false

cleanup() {
  if [[ "$is_mounted" == true && -n "$mount_dir" ]]; then
    hdiutil detach "$mount_dir" -force >/dev/null 2>&1 || true
  fi
  rm -f "$rw_dmg"
}
trap cleanup EXIT

cd "$project_dir"
"$project_dir/scripts/build_app.sh"

app_bundle="$output_dir/天文情報ウィジェット.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_bundle/Contents/Info.plist")"
# osascriptへ環境変数で渡すため、内部ボリューム名は文字化けしないASCIIにします。
volume_name="Astronomy Widget $version"
final_dmg="$output_dir/天文情報ウィジェット-$version.dmg"
checksum_file="$final_dmg.sha256"

rm -rf "$staging_dir"
rm -f "$final_dmg" "$checksum_file" "$rw_dmg"
mkdir -p "$staging_dir"

ditto "$app_bundle" "$staging_dir/天文情報ウィジェット.app"
ditto "$project_dir/Distribution/README.txt" "$staging_dir/README.txt"
osacompile -o "$staging_dir/Gatekeeper解除.scpt" "$project_dir/Distribution/Gatekeeper解除.applescript"
ln -s /Applications "$staging_dir/アプリケーション"

# 読み書き可能なイメージでFinderのアイコン配置を保存し、圧縮DMGへ変換します。
hdiutil create \
  -volname "$volume_name" \
  -srcfolder "$staging_dir" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$rw_dmg" >/dev/null

attach_output="$(hdiutil attach "$rw_dmg" -readwrite -noverify -noautoopen)"
mount_dir="$(print -r -- "$attach_output" | awk -F '\t' 'END {print $NF}')"
test -d "$mount_dir"
is_mounted=true

DMG_VOLUME_NAME="$volume_name" osascript <<'APPLESCRIPT'
set volumeName to system attribute "DMG_VOLUME_NAME"

tell application "Finder"
  tell disk volumeName
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set bounds of container window to {160, 120, 920, 640}

    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 88
    set text size of viewOptions to 13
    set position of item "天文情報ウィジェット.app" to {155, 185}
    set position of item "アプリケーション" to {605, 185}
    set position of item "Gatekeeper解除.scpt" to {225, 355}
    set position of item "README.txt" to {535, 355}

    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$mount_dir" >/dev/null
is_mounted=false

hdiutil convert "$rw_dmg" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$final_dmg" >/dev/null

hdiutil verify "$final_dmg" >/dev/null
(cd "$output_dir" && shasum -a 256 "$(basename "$final_dmg")") | tee "$checksum_file"
print "DMG作成完了: $final_dmg"
