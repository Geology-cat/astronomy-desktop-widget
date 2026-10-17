#!/bin/zsh
set -euo pipefail

# macOS 10.12〜12 用のアプリ（AppKit 版）をビルドします。
# SwiftPM では対象 OS をターゲットごとに分けられないため、swiftc を直接呼びます。
# 10.12〜10.14.3 には Swift ランタイムが OS に含まれないので、アプリ内の Frameworks に同梱します。
script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_name="天文情報ウィジェット Legacy"
dist_dir="$project_dir/dist"
app_bundle="$dist_dir/$app_name.app"
contents_dir="$app_bundle/Contents"
resources_dir="$contents_dir/Resources"
frameworks_dir="$contents_dir/Frameworks"
build_dir="$project_dir/.build/legacy"
icon_work_dir="$build_dir/AppIcon.iconset"
binary_path="$build_dir/AstronomyWidget"
toolchain_lib="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib"
runtime_dir="$toolchain_lib/swift-5.0/macosx"

if [[ ! -d "$runtime_dir" ]]; then
  print -u2 "後方互換用のSwiftランタイムが見つかりません: $runtime_dir"
  exit 1
fi

cd "$project_dir"
mkdir -p "$build_dir"
# 10.12 の Mac はすべて Intel なので x86_64 のみでビルドします。
xcrun swiftc \
  -swift-version 5 \
  -O \
  -target x86_64-apple-macosx10.12 \
  -module-name AstronomyWidgetLegacy \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  Sources/AstronomyCore/*.swift \
  Legacy/Sources/*.swift \
  -o "$binary_path"

mkdir -p "$dist_dir"
if [[ -e "$app_bundle" ]]; then
  rm -rf "$app_bundle"
fi
mkdir -p "$contents_dir/MacOS" "$resources_dir" "$frameworks_dir"
cp "$binary_path" "$contents_dir/MacOS/AstronomyWidget"
cp "$project_dir/Legacy/Info.plist" "$contents_dir/Info.plist"

# 実行ファイルが参照する Swift ライブラリを、依存関係ごと Frameworks へコピーします。
xcrun swift-stdlib-tool --copy \
  --scan-executable "$contents_dir/MacOS/AstronomyWidget" \
  --platform macosx \
  --source-libraries "$runtime_dir" \
  --destination "$frameworks_dir"

rm -rf "$icon_work_dir"
mkdir -p "$icon_work_dir"
base_icon="$build_dir/AppIcon-1024.png"
sips -s format png "$project_dir/Resources/AppIcon.svg" --out "$base_icon" >/dev/null
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$base_icon" --out "$icon_work_dir/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  sips -z "$double_size" "$double_size" "$base_icon" --out "$icon_work_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_work_dir" -o "$resources_dir/AppIcon.icns"

codesign --force --deep --sign - "$app_bundle"
print "$app_bundle"
