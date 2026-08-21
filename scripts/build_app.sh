#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
configuration="release"
app_name="天文情報ウィジェット"
dist_dir="$project_dir/dist"
app_bundle="$dist_dir/$app_name.app"
contents_dir="$app_bundle/Contents"
resources_dir="$contents_dir/Resources"
icon_work_dir="$project_dir/.build/AppIcon.iconset"

cd "$project_dir"
swift build -c "$configuration" --arch x86_64 --arch arm64

binary_path="$project_dir/.build/apple/Products/Release/AstronomyWidget"
if [[ ! -x "$binary_path" ]]; then
  print -u2 "ビルド済み実行ファイルが見つかりません: $binary_path"
  exit 1
fi

mkdir -p "$dist_dir"
if [[ -e "$app_bundle" ]]; then
  rm -rf "$app_bundle"
fi
mkdir -p "$contents_dir/MacOS" "$resources_dir"
cp "$binary_path" "$contents_dir/MacOS/AstronomyWidget"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"

rm -rf "$icon_work_dir"
mkdir -p "$icon_work_dir"
base_icon="$project_dir/.build/AppIcon-1024.png"
sips -s format png "$project_dir/Resources/AppIcon.svg" --out "$base_icon" >/dev/null
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$base_icon" --out "$icon_work_dir/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  sips -z "$double_size" "$double_size" "$base_icon" --out "$icon_work_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_work_dir" -o "$resources_dir/AppIcon.icns"

codesign --force --deep --sign - "$app_bundle"
print "$app_bundle"
