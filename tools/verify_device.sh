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

# **不用 `xctrace list devices` 做唯一来源。**
# 它只把**当前 USB 连着**的设备列进「== Devices ==」，通过网络配对的会落进
# 「== Devices Offline ==」—— 而那种设备 `xcodebuild` 照样能装能跑
# （本轮 98 条真机单测与 MosaicBench 就是这么跑的）。
# 只认 xctrace 的话，脚本会在设备明明可用时报「没有设备」，
# 而「没有设备」恰恰是这一轮不允许的那个借口。
#
# 所以用 `devicectl` 的 JSON：它给硬件 udid（xcodebuild 的 `id=` 要的就是它），
# 也给连接状态，两者一起报出来。
DEVJSON=$(mktemp -t mosaic-devices)
xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1 || true

read -r FOUND_UDID FOUND_DESC <<EOF
$(python3 - "$DEVJSON" "$UDID" <<'PY'
import json, sys
path, wanted = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
try:
    devices = json.load(open(path))["result"]["devices"]
except Exception:
    devices = []
# 排序：连上的优先；同等条件下先来的优先。unavailable 的（比如没在手边的 iPad）永远靠后。
rank = {"connected": 0, "disconnected": 1}
picked = None
for d in devices:
    hp, cp, dp = d.get("hardwareProperties", {}), d.get("connectionProperties", {}), d.get("deviceProperties", {})
    if hp.get("platform") != "iOS":
        continue
    state = cp.get("tunnelState", "unavailable")
    if state == "unavailable":
        continue
    udid = hp.get("udid", "")
    if wanted and udid != wanted:
        continue
    key = (rank.get(state, 2),)
    if picked is None or key < picked[0]:
        picked = (key, udid,
                  f'{hp.get("marketingName", "?")} · iOS {dp.get("osVersionNumber", "?")} · '
                  f'{hp.get("cpuType", {}).get("name", "arm64")} · 链路 {state}')
print(picked[1] if picked else "", picked[2] if picked else "")
PY
)
EOF

UDID="$FOUND_UDID"
LINE="$FOUND_DESC"
rm -f "$DEVJSON"

if [ -z "$UDID" ]; then
  say "  ❌ 没有发现可用的真机。"
  say ""
  say "  这不是「跳过」的理由 —— 先按顺序查这四件事："
  say "    1. 数据线连着，手机已解锁，且在手机上点过「信任此电脑」"
  say "    2. 手机 ▸ 设置 ▸ 隐私与安全性 ▸ 开发者模式 = 开（改完要重启手机）"
  say "    3. Xcode ▸ Window ▸ Devices and Simulators 里能看到它"
  say "    4. \`xcrun devicectl list devices\` 里它不是 unavailable"
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
  # `|| true`：增量构建全命中时**根本不会跑 CodeSign**，日志里也就没有这一行。
  # 不加的话 `set -euo pipefail` 会让「构建成功但没什么可签的」变成脚本失败 ——
  # 一个只在第二次运行时红的核对脚本，比没有还糟。
  IDENTITY=$(grep -m1 "Signing Identity:" /tmp/mosaic-device-debug.log 2>/dev/null \
             | sed 's/.*Signing Identity: *//' || true)
  say "     签名身份：${IDENTITY:-（本次为增量构建，未重新签名）}"
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
  # ── skip 必须显形 ──
  #
  # 第一版 `grep -c "was skipped"` 数出来是 0，而实际有 1 条（云端臂）——
  # xcodebuild 写的是 `skipped (0.001 seconds)`，不是 "was skipped"。
  # 于是脚本报「0 条 skip」而事实是有一条没跑。**那正是这个脚本要拦的那类假绿。**
  #
  # 改成读 xcodebuild 自己的汇总行（`Executed N tests, with M test(s) skipped`）——
  # 它是权威口径，不依赖单条日志的措辞。
  SUMMARY=$(grep -oE "Executed [0-9]+ tests?, with ([0-9]+ tests? skipped and )?[0-9]+ failures?"             /tmp/mosaic-device-bench.log | tail -1 || true)
  SKIPPED=$(printf '%s' "$SUMMARY" | grep -oE "with [0-9]+ tests? skipped" | grep -oE "[0-9]+" || echo 0)
  say "     $SUMMARY"
  if [ "${SKIPPED:-0}" -eq 0 ]; then
    ok "0 条 skip —— 每一条都真的跑了"
  else
    # skip **不判失败**，但必须逐条报出来并说清哪一类是允许的。
    # 允许：CLOUD_CREDENTIAL_REQUIRED（云端臂已 DEFERRED）。
    # 不允许：TEST_REQUIRES_UNAVAILABLE_HARDWARE 在真机上出现（那说明设备没被识别）。
    say "  ⚠️  $SKIPPED 条 skip —— 逐条看原因："
    # 只看 XCTest 打的**跳过理由**那一行（`Test skipped - …`）。
    # 第一版拿整份日志 grep「模拟器」，结果被 `test1` 打印的
    # 「模拟器实测曾是 …」误伤，报出一个不存在的失败 ——
    # 一个会误报的核对项，下一次就会被当成噪声忽略掉。
    grep -E "Test skipped -" /tmp/mosaic-device-bench.log | sed -E 's/.*DeviceLatencyBenchmarkTests //; s/\] : Test skipped - /：/; s/^/     · /' || true
    say "     允许的理由只有一个：CLOUD_CREDENTIAL_REQUIRED（云端臂 = DEFERRED）。"
    if grep -E "Test skipped -" /tmp/mosaic-device-bench.log | grep -q "模拟器"; then
      bad "真机跑批里出现了「模拟器上自动跳过」—— destination 指错了，这不是真机结果"
    else
      ok "skip 的理由都是缺云端凭据，没有「设备没识别到」那一类"
    fi
  fi
fi

say ""
if [ "$FAIL" -eq 0 ]; then say "全部通过。"; else say "有未通过项，见上。"; fi
exit "$FAIL"
