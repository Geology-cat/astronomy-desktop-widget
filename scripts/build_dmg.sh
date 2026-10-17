#!/bin/zsh
set -euo pipefail

# アプリ、README、Gatekeeper解除AppleScript、アプリケーションリンクをDMGへまとめます。
# macOS 13以降用と、macOS 10.12〜12用（Legacy）の2つのDMGを作ります。
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

# 引数: アプリ名（.app を除く）、README のパス、DMG 名の接尾辞、ボリューム名の接尾辞、種別（standard／legacy）
make_dmg() {
  local app_name="$1"
  local readme_path="$2"
  local file_suffix="$3"
  local volume_suffix="$4"
  local app_kind="$5"
  local app_bundle="$output_dir/$app_name.app"
  local version
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_bundle/Contents/Info.plist")"
  # osascriptへ環境変数で渡すため、内部ボリューム名は文字化けしないASCIIにします。
  local volume_name="Astronomy Widget${volume_suffix} $version"
  local final_dmg="$output_dir/天文情報ウィジェット${file_suffix}-$version.dmg"
  local checksum_file="$final_dmg.sha256"

  rm -rf "$staging_dir"
  rm -f "$final_dmg" "$checksum_file" "$rw_dmg"
  mkdir -p "$staging_dir"

  ditto "$app_bundle" "$staging_dir/$app_name.app"
  ditto "$readme_path" "$staging_dir/README.txt"
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

  local attach_output
  attach_output="$(hdiutil attach "$rw_dmg" -readwrite -noverify -noautoopen)"
  mount_dir="$(print -r -- "$attach_output" | awk -F '\t' 'END {print $NF}')"
  test -d "$mount_dir"
  is_mounted=true

  # 環境変数の日本語は文字化けするため、アプリ名は種別（ASCII）から AppleScript 側で決めます。
  DMG_VOLUME_NAME="$volume_name" DMG_APP_KIND="$app_kind" osascript <<'APPLESCRIPT'
set volumeName to system attribute "DMG_VOLUME_NAME"
if (system attribute "DMG_APP_KIND") is "legacy" then
  set appItem to "天文情報ウィジェット Legacy.app"
else
  set appItem to "天文情報ウィジェット.app"
end if

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
    set position of item appItem to {155, 185}
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
}

cd "$project_dir"
"$project_dir/scripts/build_app.sh"
"$project_dir/scripts/build_legacy_app.sh"

make_dmg "天文情報ウィジェット" "$project_dir/Distribution/README.txt" "" "" standard
make_dmg "天文情報ウィジェット Legacy" "$project_dir/Distribution/README_Legacy.txt" "-Legacy" " Legacy" legacy
