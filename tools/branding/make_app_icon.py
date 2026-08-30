#!/usr/bin/env python3
"""生成 App 图标（1024×1024）。

# 这是一个**临时品牌资产**

`DECISION_CONFIG: RELEASE_TARGET = TESTFLIGHT_EXTERNAL_BETA_READY`。
TestFlight 要求有图标，而这个项目还没有最终品牌设计 —— 缺图标不该把整条
发布路径卡住。所以这里画一个干净、可发布质量的图，并在 `README` 与
`PROJECT_STATUS` 里标为 **replaceable branding asset**。

# 为什么是脚本而不是一张提交进仓库的 PNG

图标要能被重新生成：改一个颜色不必去翻设计工具，而且 diff 能看懂改了什么。
产物 PNG 仍然提交（构建需要它），但**它的来源是这个脚本**。

# 形取自产品名

「万象记 / Mosaic」——**马赛克**：若干小块拼成一整幅。
九宫格瓷砖，尺寸与不透明度略有变化，避免呆板的方格纸感。
底色用 App 的 AccentColor（#0A84FF）到深蓝的对角渐变。

用法：

    python3 tools/branding/make_app_icon.py
"""

import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "App/Mosaic/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")

S = 1024
ACCENT = (10, 132, 255)      # #0A84FF —— 与 AccentColor 一致
DEEP = (4, 46, 120)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def main():
    img = Image.new("RGB", (S, S), ACCENT)
    px = img.load()
    # 对角渐变。逐像素够快（1M 像素，一次性脚本），不值得引入 numpy。
    for y in range(S):
        for x in range(S):
            px[x, y] = lerp(ACCENT, DEEP, (x + y) / (2 * S - 2))

    overlay = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)

    # 九宫格瓷砖。留白比瓷砖窄，整体重心略偏上 —— iOS 图标在圆角遮罩下
    # 视觉重心会下沉，正中对齐反而显得偏低。
    margin, gap = 168, 26
    inner = S - margin * 2
    tile = (inner - gap * 2) / 3
    top = margin - 18

    # 每块的不透明度。中间一块最实，四角最淡 —— 让眼睛先落在中心。
    alpha_grid = [
        [0.42, 0.62, 0.42],
        [0.62, 1.00, 0.62],
        [0.42, 0.62, 0.42],
    ]
    for row in range(3):
        for col in range(3):
            x0 = margin + col * (tile + gap)
            y0 = top + row * (tile + gap)
            a = int(255 * alpha_grid[row][col])
            # 中心块稍大一点点，强化「拼起来的一整幅」而不是「九个格子」。
            grow = 10 if (row, col) == (1, 1) else 0
            d.rounded_rectangle(
                [x0 - grow, y0 - grow, x0 + tile + grow, y0 + tile + grow],
                radius=int(tile * 0.24),
                fill=(255, 255, 255, a),
            )

    img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, "PNG")
    print(f"写入 {os.path.relpath(OUT, ROOT)}  ({img.size[0]}×{img.size[1]})")


if __name__ == "__main__":
    main()
