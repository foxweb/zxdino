"""Chrome-dino sprites for a 16-colour-clash-free ZX Spectrum screen.

Bitmaps live in sprites/*.gif (opaque pixel = ink). Edit the GIFs, then run
art.py / build.py to regenerate sprites.inc.
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

_SPRITES_DIR = Path(__file__).resolve().parent / "sprites"

# Order matches former ASCII tables; each name → sprites/<name>.gif
SPRITE_NAMES = (
    "dino_run1",
    "dino_run2",
    "dino_jump",
    "dino_dead",
    "dino_duck1",
    "dino_duck2",
    "cac_small",
    "cac_tall",
    "cac_wide",
    "bird1",
    "bird2",
    "cloud",
)


def parse(rows: list[str]) -> tuple[int, int, bytes]:
    width = len(rows[0])
    if width % 8:
        raise ValueError(f"width {width} not multiple of 8")
    for i, row in enumerate(rows):
        if len(row) != width:
            raise ValueError(f"row {i} width {len(row)} != {width}")
        if any(ch not in ".#" for ch in row):
            raise ValueError(f"bad pixel on row {i}")
    byte_w = width // 8
    out = []
    for row in rows:
        for b in range(byte_w):
            val = 0
            for bit in range(8):
                if row[b * 8 + bit] == "#":
                    val |= 0x80 >> bit
            out.append(val)
    return byte_w, len(rows), bytes(out)


def load_gif_bitmap(path: Path) -> list[str]:
    """Первый кадр GIF → строки '.'/'#' (непрозрачный пиксель = чернила)."""
    data = path.read_bytes()
    if data[:6] not in (b"GIF87a", b"GIF89a"):
        raise ValueError(f"{path}: not a GIF")
    w, h = struct.unpack_from("<HH", data, 6)
    packed = data[10]
    i = 13
    if packed >> 7:
        i += 3 * (2 << (packed & 7))
    transparent = None
    while data[i] == 0x21:
        i += 1
        label = data[i]
        i += 1
        blocks = []
        while True:
            blk = data[i]
            i += 1
            if blk == 0:
                break
            blocks.append(data[i : i + blk])
            i += blk
        if label == 0xF9 and blocks and (blocks[0][0] & 1):
            transparent = blocks[0][3]
    if data[i] != 0x2C:
        raise ValueError(f"{path}: missing image descriptor")
    i += 1
    _l, _t, iw, ih = struct.unpack_from("<HHHH", data, i)
    i += 8
    ipacked = data[i]
    i += 1
    if ipacked >> 7:
        i += 3 * (2 << (ipacked & 7))
    min_code_size = data[i]
    i += 1
    lzw = bytearray()
    while True:
        blk = data[i]
        i += 1
        if blk == 0:
            break
        lzw += data[i : i + blk]
        i += blk

    clear = 1 << min_code_size
    end = clear + 1
    code_size = min_code_size + 1
    next_code = end + 1
    table = {c: bytes([c]) for c in range(clear)}
    bits = bitbuf = pos = 0

    def read_code():
        nonlocal bits, bitbuf, pos, code_size
        while bits < code_size:
            if pos >= len(lzw):
                return None
            bitbuf |= lzw[pos] << bits
            pos += 1
            bits += 8
        code = bitbuf & ((1 << code_size) - 1)
        bitbuf >>= code_size
        bits -= code_size
        return code

    out = bytearray()
    prev = None
    expected = iw * ih
    while len(out) < expected:
        code = read_code()
        if code is None or code == end:
            break
        if code == clear:
            code_size = min_code_size + 1
            next_code = end + 1
            table = {c: bytes([c]) for c in range(clear)}
            prev = None
            continue
        if code in table:
            entry = table[code]
        elif code == next_code and prev is not None:
            entry = prev + prev[:1]
        else:
            raise ValueError(f"{path}: bad LZW code {code}")
        out += entry
        if prev is not None and next_code < 4096:
            table[next_code] = prev + entry[:1]
            next_code += 1
            if next_code == (1 << code_size) and code_size < 12:
                code_size += 1
        prev = entry

    if w != iw or h != ih:
        raise ValueError(f"{path}: frame {iw}x{ih} != logical {w}x{h}")
    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            idx = out[y * w + x]
            on = idx != transparent if transparent is not None else idx != 0
            row.append("#" if on else ".")
        rows.append("".join(row))
    return rows


def load_sprites() -> dict[str, list[str]]:
    sprites = {}
    for name in SPRITE_NAMES:
        path = _SPRITES_DIR / f"{name}.gif"
        rows = load_gif_bitmap(path)
        parse(rows)
        sprites[name] = rows
    return sprites


SPRITES = load_sprites()


def asm_bytes(name, data):
    lines = [f"{name}:"]
    for i in range(0, len(data), 8):
        chunk = data[i : i + 8]
        lines.append("        db " + ", ".join(f"${b:02X}" for b in chunk))
    return "\n".join(lines)


def preshift(rows):
    """8 кадров по height*3 байта: сдвиг вправо на 0..7 пикселей."""
    bw, height, data = parse(rows)
    out = []
    for shift in range(8):
        for y in range(height):
            b0 = data[y * bw]
            b1 = data[y * bw + 1] if bw > 1 else 0
            bits = ((b0 << 16) | (b1 << 8)) >> shift
            out.append((bits >> 16) & 0xFF)
            out.append((bits >> 8) & 0xFF)
            out.append(bits & 0xFF)
    return height, bytes(out)


def sprites_inc():
    parts = [
        "; Generated by art.py — do not edit.",
        "; Каждый спрайт: 8 сдвигов, в строке 3 байта (пиксели уезжают вправо).",
    ]
    for name, rows in SPRITES.items():
        _h, data = preshift(rows)
        parts.append(asm_bytes(name, data))
        parts.append("")
    return "\n".join(parts) + "\n"


if __name__ == "__main__":
    dest = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("sprites.inc")
    dest.write_text(sprites_inc())
    for name, rows in SPRITES.items():
        h, data = preshift(rows)
        print(f"{name}: h={h} preshifted {len(data)} bytes")
