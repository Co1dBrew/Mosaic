#!/usr/bin/env bash
#
# Release 构建的发布前核对。
#
# 它检查的是**产物**，不是源码：`#if DEBUG` 写对了没有，只有看编译结果才知道。
# 之前这几项靠人工在终端里 grep，一次性的核对没有人会第二次做。
#
#   用法：tools/verify_release.sh [模拟器名]
#
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${1:-iPhone 17 Pro}"
DD="App/build/DDRelease"
FAIL=0

say() { printf '%s\n' "$*"; }
ok()  { say "  ✅ $*"; }
bad() { say "  ❌ $*"; FAIL=1; }

say "── Release 构建 ──"
xcodebuild build -scheme Mosaic -project App/Mosaic.xcodeproj \
  -configuration Release -destination "platform=iOS Simulator,name=$DEST" \
  -derivedDataPath "$DD" > /tmp/mosaic-release-build.log 2>&1 \
  || { say "构建失败，日志见 /tmp/mosaic-release-build.log"; exit 1; }

APP=$(find "$DD/Build/Products/Release-iphonesimulator" -name "Mosaic.app" -maxdepth 2 | head -1)
[ -n "$APP" ] || { say "找不到 Mosaic.app"; exit 1; }
ok "构建成功：$APP"

say ""
say "── 1 · Developer Tools 不在 Release 里 ──"
# 检查符号而不是文件：`#if DEBUG` 之下文件仍然参与编译，只是产不出符号。
for sym in DeveloperModeView RetrievalLabView ReleaseGateView EvalDatasetView RetrievalTraceView; do
  n=$(nm -a "$APP/Mosaic" 2>/dev/null | grep -c "$sym" || true)
  if [ "$n" -eq 0 ]; then ok "$sym：0 个符号"; else bad "$sym：$n 个符号 —— 内部工具进了发布包"; fi
done
if strings "$APP/Mosaic" | grep -q "开发者工具"; then
  bad "二进制里仍有「开发者工具」字符串"
else
  ok "「开发者工具」字符串：0 处"
fi

say ""
say "── 2 · 发布必需的资源 ──"
[ -f "$APP/PrivacyInfo.xcprivacy" ] && ok "隐私清单已打包" || bad "缺 PrivacyInfo.xcprivacy"
if xcrun assetutil --info "$APP/Assets.car" 2>/dev/null | grep -q "AppIcon"; then
  ok "AppIcon 已编译进 Assets.car"
else
  bad "AppIcon 缺失 —— TestFlight 会拒收"
fi

say ""
say "── 3 · Info.plist 的权限说明与实际用途一致 ──"
PLIST="$APP/Info.plist"
declare -a REQUIRED=(NSCameraUsageDescription NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription)
for key in "${REQUIRED[@]}"; do
  if plutil -extract "$key" raw "$PLIST" >/dev/null 2>&1; then ok "$key 存在"; else bad "缺 $key"; fi
done
# 用不到的用途说明是一句关于 App 行为的错误陈述，同样算失败。
if plutil -extract NSPhotoLibraryUsageDescription raw "$PLIST" >/dev/null 2>&1; then
  bad "NSPhotoLibraryUsageDescription 不该存在 —— 选图走 PhotosPicker，不需要相册权限"
else
  ok "没有多余的相册权限说明"
fi

say ""
say "── 4 · CloudKit 能力标记与 entitlements 一致 ──"
FLAG=$(plutil -extract MosaicCloudKitEnabled raw "$PLIST" 2>/dev/null || echo "NO")
# 用 plutil 读**真实的键**，不用 grep：entitlements 里有一段注释掉的模板，
# grep 会把注释里的字符串也算上（第一版就是这样误报的）。
if plutil -extract com.apple.developer.icloud-container-identifiers raw \
     App/Mosaic/Mosaic.entitlements >/dev/null 2>&1; then ENT=1; else ENT=0; fi
if [ "$FLAG" = "NO" ] && [ "$ENT" -eq 0 ]; then
  ok "两边都是「无 CloudKit」——设置页会显示「此版本不提供」"
elif [ "$FLAG" != "NO" ] && [ "$ENT" -gt 0 ]; then
  ok "两边都声明了 CloudKit"
else
  bad "不一致：Info.plist=$FLAG，entitlements 里的容器声明数=$ENT"
fi

say ""
if [ "$FAIL" -eq 0 ]; then say "全部通过。"; else say "有未通过项，见上。"; fi
exit "$FAIL"
