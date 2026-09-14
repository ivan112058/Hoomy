#!/usr/bin/env python3
"""生成 Android TV 首页 banner（票据 16）。

Android TV 要求应用提供 320×180 的 home screen banner，放在 `drawable-xhdpi`
（官方 checklist）。这是**生成脚本**，产物是
`android/app/src/main/res/drawable-xhdpi/banner.png`；用纯标准库写 PNG，
不引入 Pillow 之类的依赖。

视觉沿用 Hoomy 的 token（ADR-0003 / ADR-0013）：深色炭灰底、方块化布局、
播放态红与交互蓝点缀，不重新发明配色。文字用一份 5×7 点阵自绘，避免依赖
字体与本地化环境。

用法：

    python3 tool/generate_tv_banner.py
"""

import struct
import zlib
from pathlib import Path

WIDTH, HEIGHT = 320, 180

# 与 lib/core/theme/hoomy_theme.dart 的 token 逐值一致。
PAGE_BG = (0x25, 0x28, 0x2D)  # darkPageBackground
CARD = (0x34, 0x37, 0x3C)  # darkCard
PLAYING_RED = (0xE6, 0x40, 0x40)  # playingRed
INTERACTION_BLUE = (0x5C, 0x89, 0xF2)  # interactionBlue
WHITE = (0xFF, 0xFF, 0xFF)

# 5×7 点阵字模，够画 "HOOMY" 五个字母。
FONT = {
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
}

SCALE = 4
LETTER_ADVANCE = 5 * SCALE + 8


def blank_canvas():
    return [[PAGE_BG for _ in range(WIDTH)] for _ in range(HEIGHT)]


def fill_rect(canvas, x0, y0, x1, y1, color):
    for y in range(max(0, y0), min(HEIGHT, y1)):
        for x in range(max(0, x0), min(WIDTH, x1)):
            canvas[y][x] = color


def fill_circle(canvas, cx, cy, radius, color):
    for y in range(cy - radius, cy + radius + 1):
        for x in range(cx - radius, cx + radius + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= radius**2:
                fill_rect(canvas, x, y, x + 1, y + 1, color)


def draw_text(canvas, text, x, y, color):
    cursor = x
    for char in text:
        glyph = FONT[char]
        for row, bits in enumerate(glyph):
            for col, bit in enumerate(bits):
                if bit == "1":
                    fill_rect(
                        canvas,
                        cursor + col * SCALE,
                        y + row * SCALE,
                        cursor + (col + 1) * SCALE,
                        y + (row + 1) * SCALE,
                        color,
                    )
        cursor += LETTER_ADVANCE
    return cursor - 8


def text_width(text):
    return len(text) * LETTER_ADVANCE - 8


def draw_music_note(canvas, cx, cy):
    """一个白色的八分音符：符头 + 符干 + 符尾。"""
    fill_circle(canvas, cx, cy, 13, WHITE)
    fill_rect(canvas, cx + 9, cy - 34, cx + 15, cy, WHITE)
    fill_rect(canvas, cx + 15, cy - 34, cx + 34, cy - 27, WHITE)


def build_canvas():
    canvas = blank_canvas()

    # 左侧方块：直角封面块 + 音符，呼应「专辑网格」与「静止封面」。
    fill_rect(canvas, 24, 46, 112, 134, CARD)
    draw_music_note(canvas, 60, 104)

    # 右侧：应用名 + 播放红下划线。
    text = "HOOMY"
    x = 128 + (WIDTH - 24 - 128 - text_width(text)) // 2
    end = draw_text(canvas, text, x, 62, WHITE)
    fill_rect(canvas, x, 104, end, 110, PLAYING_RED)

    # 底部一条交互蓝：TV 上的焦点色，作为品牌色收边。
    fill_rect(canvas, 0, HEIGHT - 5, WIDTH, HEIGHT, INTERACTION_BLUE)
    return canvas


def write_png(canvas, path):
    raw = bytearray()
    for row in canvas:
        raw.append(0)  # filter type 0 (None)
        for pixel in row:
            raw.extend(pixel)

    def chunk(tag, payload):
        body = tag + payload
        return (
            struct.pack(">I", len(payload))
            + body
            + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def main():
    target = (
        Path(__file__).resolve().parent.parent
        / "android/app/src/main/res/drawable-xhdpi/banner.png"
    )
    write_png(build_canvas(), target)
    print(f"已生成 {target}")


if __name__ == "__main__":
    main()
