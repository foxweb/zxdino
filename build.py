#!/usr/bin/env python3
"""Assemble the Spectrum dino and pack TAP / Z80 images."""

import struct
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ROM = Path("/Users/foxweb/Downloads/Fuse for macOS/Fuse.app/Contents/Resources/48.rom")
LIBZ80 = Path("/tmp/libz80-master")
ORG = 0x8000

DAY = [
    (0, 0, 0),
    (0, 0, 205),
    (205, 0, 0),
    (205, 0, 205),
    (0, 205, 0),
    (0, 205, 205),
    (205, 205, 0),
    (205, 205, 205),
]
BRIGHT = [
    (0, 0, 0),
    (0, 0, 255),
    (255, 0, 0),
    (255, 0, 255),
    (0, 255, 0),
    (0, 255, 255),
    (255, 255, 0),
    (255, 255, 255),
]


def zx_number(n: int) -> bytes:
    return str(n).encode("ascii") + bytes((0x0E, 0x00, 0x00, n & 0xFF, (n >> 8) & 0xFF, 0x00))


def basic_loader() -> bytes:
    # 10 BORDER 0: PAPER 0: INK 7: CLEAR 32767: LOAD "" CODE: RANDOMIZE USR 32768
    body = bytearray()
    body.append(0xE7)
    body += zx_number(0)
    body.append(0x3A)
    body.append(0xDA)
    body += zx_number(0)
    body.append(0x3A)
    body.append(0xD9)
    body += zx_number(7)
    body.append(0x3A)
    body.append(0xFD)
    body += zx_number(32767)
    body.append(0x3A)
    body.append(0xEF)
    body += b'""'
    body.append(0xAF)
    body.append(0x3A)
    body.append(0xF9)
    body.append(0xC0)
    body += zx_number(32768)
    body.append(0x0D)
    return bytes((0x00, 0x0A)) + len(body).to_bytes(2, "little") + body


def tap_block(flag: int, data: bytes) -> bytes:
    payload = bytes((flag,)) + data
    checksum = 0
    for b in payload:
        checksum ^= b
    payload += bytes((checksum,))
    return len(payload).to_bytes(2, "little") + payload


def header(kind: int, name: str, length: int, p1: int, p2: int) -> bytes:
    raw = name.encode("ascii")[:10].ljust(10)
    return bytes((kind,)) + raw + struct.pack("<HHH", length, p1, p2)


def make_tap(code: bytes) -> bytes:
    prog = basic_loader()
    blocks = [
        tap_block(0x00, header(0, "dino", len(prog), 10, len(prog))),
        tap_block(0xFF, prog),
        tap_block(0x00, header(3, "dino-code", len(code), ORG, 0x8000)),
        tap_block(0xFF, code),
    ]
    return b"".join(blocks)


def make_z80(code: bytes) -> bytes:
    ram = bytearray(49152)
    ram[ORG - 16384 : ORG - 16384 + len(code)] = code
    hdr = bytearray(30)
    hdr[6] = ORG & 0xFF
    hdr[7] = (ORG >> 8) & 0xFF
    hdr[8] = 0xF0
    hdr[9] = 0xFC
    hdr[10] = 0x3F
    hdr[12] = 0  # uncompressed, border 0
    hdr[23] = 0x3A
    hdr[24] = 0x5C  # IY
    hdr[27] = 0  # DI
    hdr[28] = 0
    hdr[29] = 1  # IM 1, code switches to IM 2
    return bytes(hdr) + ram


def parse_labels(text: str) -> dict:
    labels = {}
    for line in text.splitlines():
        if "equ" not in line:
            continue
        name, _, value = line.partition(":")
        value = value.replace("equ", "").strip().lstrip("$")
        labels[name.strip()] = int(value, 16)
    return labels


def write_png(path: Path, width: int, height: int, rgb: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + rgb[y * width * 3 : (y + 1) * width * 3] for y in range(height))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def scr_to_png(scr: bytes, path: Path, scale: int = 3) -> None:
    pixels = scr[:6144]
    attrs = scr[6144:6912]
    bw, bh = 32 * 8 * scale, 24 * 8 * scale
    buf = bytearray(bw * bh * 3)
    for cy in range(24):
        for cx in range(32):
            attr = attrs[cy * 32 + cx]
            pal = BRIGHT if attr & 0x40 else DAY
            ink = pal[attr & 7]
            paper = pal[(attr >> 3) & 7]
            for py in range(8):
                y = cy * 8 + py
                addr = ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | cx
                bits = pixels[addr]
                for px in range(8):
                    color = ink if bits & (0x80 >> px) else paper
                    x0 = (cx * 8 + px) * scale
                    y0 = y * scale
                    for sy in range(scale):
                        row = (y0 + sy) * bw + x0
                        for sx in range(scale):
                            i = (row + sx) * 3
                            buf[i : i + 3] = bytes(color)
    write_png(path, bw, bh, buf)


def assemble() -> tuple[bytes, dict]:
    subprocess.check_call([sys.executable, str(ROOT / "art.py"), str(ROOT / "sprites.inc")])
    lab = ROOT / "dino.lab"
    bin_path = ROOT / "dino.bin"
    subprocess.check_call(
        [
            "z80asm",
            f"--output={bin_path}",
            f"--label={lab}",
            str(ROOT / "dino.asm"),
        ],
        cwd=ROOT,
    )
    code = bin_path.read_bytes()
    labels = parse_labels(lab.read_text())
    if labels.get("start") != ORG:
        raise SystemExit(f"start label is {labels.get('start')}, expected {ORG}")
    return code, labels


def build_images(code: bytes) -> None:
    (ROOT / "dino.tap").write_bytes(make_tap(code))
    (ROOT / "dino.z80").write_bytes(make_z80(code))
    print(f"code {len(code)} bytes")
    print(f"tap  {(ROOT / 'dino.tap').stat().st_size} bytes")
    print(f"z80  {(ROOT / 'dino.z80').stat().st_size} bytes")


def ensure_runner() -> Path:
    exe = ROOT / "tools" / "runspec"
    src = ROOT / "tools" / "runspec.c"
    if not LIBZ80.exists():
        raise SystemExit(f"libz80 not found at {LIBZ80}")
    subprocess.check_call(
        [
            "cc",
            "-O2",
            f"-I{LIBZ80}",
            "-o",
            str(exe),
            str(src),
            str(LIBZ80 / "z80.c"),
        ]
    )
    return exe


def write_watch(labels: dict, path: Path) -> None:
    names = [
        "state",
        "frame",
        "dino_y",
        "dino_vy",
        "score",
        "speed",
        "night",
        "obs",
        "spawn_t",
        "hi_score",
    ]
    lines = [f"{name} {labels[name]:04x}" for name in names]
    path.write_text("\n".join(lines) + "\n")


def run_case(exe: Path, mode: str, frames: int) -> Path:
    out = ROOT / "preview" / mode
    out.mkdir(parents=True, exist_ok=True)
    subprocess.check_call(
        [str(exe), str(ROM), str(ROOT / "dino.bin"), str(ROOT / "preview" / "watch.txt"), str(out), mode, str(frames)]
    )
    for scr in sorted(out.glob("*.scr")):
        scr_to_png(scr.read_bytes(), scr.with_suffix(".png"))
    return out


def main() -> None:
    code, labels = assemble()
    build_images(code)
    if not ROM.exists():
        print("ROM missing, skipped emulation")
        return
    exe = ensure_runner()
    preview = ROOT / "preview"
    preview.mkdir(exist_ok=True)
    write_watch(labels, preview / "watch.txt")
    run_case(exe, "wait", 30)
    run_case(exe, "die", 400)
    run_case(exe, "play", 700)


if __name__ == "__main__":
    main()
