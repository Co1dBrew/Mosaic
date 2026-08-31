#!/usr/bin/env bash
#
# 真机发布前核对。
#
# 与 `verify_release.sh` **分开**，理由是两者的前提不同：
#   - `verify_release.sh` 只要一台 Mac 就能跑，所以它可以进 CI、可以每次提交都跑。
#   - 这一份需要一台**已连接、已信任、已开开发者模式**的 iPhone。
#
# 把两者合成一个脚本的代价是：CI 上永远拿不到设备，于是整个脚本被跳过，
# 连那些本来不需要设备的检查也一起失效 —— 「一个总是被跳过的 Gate 等于没有 Gate」。
#
# 它检查的是**真机产物**：`verify_release.sh` 验的是模拟器切片（x86_64/arm64-sim），
# 而用户装到手机上的是 arm64 的那一份。`#if DEBUG` 与资源打包在两条流水线上
# 各走各的，只验模拟器切片证明不了发布包。
#
#   用法：tools/verify_device.sh [device-udid]
#         tools/verify_device.sh --with-bench [device-udid]   # 连真机基准一起跑（慢，十几分钟）
#
set -euo pipefail
cd "$(dirname "$0")/.."

WITH_BENCH=0
if [ "${1:-}" = "--with-bench" ]; then WITH_BENCH=1; shift; fi

FAIL=0
say() { printf '%s\n' "$*"; }
ok()  { say "  ✅ $*"; }
bad() { say "  ❌ $*"; FAIL=1; }

# ── 0 · 找设备 ──
#
# **不硬编码 udid。** 上一轮的交接文档里写死了一个，换台手机就变成一句谎话。
say "── 0 · 设备发现 ──"
UDID="${1:-}"
LINE=""
if [ -z "$UDID" ]; then
  # `xctrace list devices` 的「== Devices ==」段里，除 Mac 之外的第一台就是连着的 iPhone/iPad。
  LINE=$(xcrun xctrace list devices 2>/dev/null \
         | awk '/^== Devices ==/{f=1;next} /^== Devices Offline ==|^== Simulators ==/{f=0} f' \
         | grep -v "^$" | grep -vi "^MacBook\|^Mac \|^iMac\|^Mac Studio\|^Mac mini" | head -1)
  UDID=$(printf '%s' "$LINE" | sed -n 's/.*(\([0-9A-Fa-f-]\{25,\}\))$/\1/p')
else
  LINE=$(xcrun xctrace list devices 2>/dev/null | grep "$UDID" | head -1)
fi

if [ -z "$UDID" ]; then
  say "  ❌ 没有发现已连接的真机。"
  say ""
  say "  这不是「跳过」的理由 —— 先按顺序查这四件事："
  say "    1. 数据线连着，手机已解锁，且在手机上点过「信任此电脑」"
  say "    2. 手机 ▸ 设置 ▸ 隐私与安全性 ▸ 开发者模式 = 开（改完要重启手机）"
  say "    3. Xcode ▸ Window ▸ Devices and Simulators 里能看到它"
  say "    4. \`xcrun xctrace list devices\` 的「== Devices ==」段里有它"
  exit 1
fi
ok "设备：${LINE}"
say "     udid=$UDID"

DEST="platform=iOS,id=$UDID"

# ── 1 · Debug 真机构建 ──
say ""
say "── 1 · Debug 真机构建（签名链路）──"
if xcodebuild build -scheme Mosaic -project App/Mosaic.xcodeproj \
     -configuration Debug -destination "$DEST" -allowProvisioningUpdates \
     -derivedDataPath App/build/DDDevice > /tmp/mosaic-device-debug.log 2>&1; then
  ok "Debug BUILD SUCCEEDED"
  IDENTITY=$(grep -m1 "Signing Identity:" /tmp/mosaic-device-debug.log | sed 's/.*Signing Identity: *//')
  say "     签名身份：${IDENTITY:-未知}"
else
  bad "Debug 真机构建失败 —— 日志 /tmp/mosaic-device-debug.log"
  # 签名失败时把最有用的那几行直接贴出来，省一次「再去翻日志」。
  grep -i "error:\|Provisioning\|Signing" /tmp/mosaic-device-debug.log | tail -8 || true
fi

# ── 2 · Release 真机构建 ──
say ""
say "── 2 · Release 真机构建（这才是用户装的那一份）──"
if xcodebuild build -scheme Mosaic -project App/Mosaic.xcodeproj \
     -configuration Release -destination "$DEST" -allowProvisioningUpdates \
     -derivedDataPath App/build/DDDeviceRelease > /tmp/mosaic-device-release.log 2>&1; then
  ok "Release BUILD SUCCEEDED"
else
  bad "Release 真机构建失败 —— 日志 /tmp/mosaic-device-release.log"
  grep -i "error:" /tmp/mosaic-device-release.log | tail -8 || true
fi

APP=$(find App/build/DDDeviceRelease/Build/Products/Release-iphoneos -name "Mosaic.app" -maxdepth 2 2>/dev/null | head -1)

if [ -n "$APP" ]; then
  say ""
  say "── 3 · 真机 Release 产物 ──"
  ARCHS=$(lipo -archs "$APP/Mosaic" 2>/dev/null || echo "?")
  if printf '%s' "$ARCHS" | grep -q "arm64"; then ok "架构 $ARCHS"; else bad "架构 $ARCHS —— 真机包必须是 arm64"; fi

  # Developer Tools 在**真机 Release 切片**里也必须 0 符号。
  for sym in DeveloperModeView RetrievalLabView ReleaseGateView EvalDatasetView RetrievalTraceView; do
    n=$(nm -a "$APP/Mosaic" 2>/dev/null | grep -c "$sym" || true)
    if [ "$n" -eq 0 ]; then ok "$sym：0 个符号"; else bad "$sym：$n 个符号 —— 内部工具进了真机发布包"; fi
  done
  if strings "$APP/Mosaic" | grep -q "开发者工具"; then
    bad "真机二进制里仍有「开发者工具」字符串"
  else
    ok "「开发者工具」字符串：0 处"
  fi

  [ -f "$APP/PrivacyInfo.xcprivacy" ] && ok "隐私清单已打进真机包" || bad "真机包缺 PrivacyInfo.xcprivacy"
  if xcrun assetutil --info "$APP/Assets.car" 2>/dev/null | grep -q "AppIcon"; then
    ok "AppIcon 已编译进真机包的 Assets.car"
  else
    bad "真机包缺 AppIcon —— 主屏会是白图标"
  fi

  # 生产检索配置：**从二进制里读，不从源码读。**
  # 源码写着 keyword 而编译进去的是别的东西，正是这个脚本要拦的那类事。
  if strings "$APP/Mosaic" | grep -q "retrieval-v2-keyword"; then
    ok "生产检索配置版本号在包里：retrieval-v2-keyword（PRODUCTION_RETRIEVAL = KEYWORD）"
  else
    bad "包里找不到 retrieval-v2-keyword —— 生产配置与产品决策不一致"
  fi
fi

# ── 4 · 真机基准（可选）──
if [ "$WITH_BENCH" -eq 1 ]; then
  say ""
  say "── 4 · MosaicBench（真机 · Release · 十几分钟）──"
  if xcodebuild test -scheme MosaicBench -project App/Mosaic.xcodeproj \
       -configuration Release -destination "$DEST" -allowProvisioningUpdates \
       -derivedDataPath App/build/DDBench > /tmp/mosaic-device-bench.log 2>&1; then
    ok "MosaicBench 全部通过 —— 数字见 /tmp/mosaic-device-bench.log"
  else
    bad "MosaicBench 失败 —— 日志 /tmp/mosaic-device-bench.log"
  fi
  # skip 必须显形：这套用例在模拟器上按设计 skip，在真机上 skip 就是个问题。
  SKIPPED=$(grep -c "was skipped" /tmp/mosaic-device-bench.log || true)
  if [ "$SKIPPED" -eq 0 ]; then
    ok "0 条 skip"
  else
    say "  ⚠️  $SKIPPED 条 skip —— 逐条看原因（缺云端凭据是允许的，缺本地模型不是）"
    grep "was skipped" /tmp/mosaic-device-bench.log | sed 's/^/     /' | head -10 || true
  fi
fi

say ""
if [ "$FAIL" -eq 0 ]; then say "全部通过。"; else say "有未通过项，见上。"; fi
exit "$FAIL"
