#!/usr/bin/env python3
"""
make_icons.py - Generate minimal ICO files for GLUSH tray application.
Creates two 16x16 ICO icons:
  - icon_connected.ico    (blue circle)
  - icon_disconnected.ico (gray circle)

No external dependencies — uses only stdlib struct/zlib.
"""
import struct
import zlib
import sys
import os


def rgba_to_png(width: int, height: int, pixels: list[tuple[int, int, int, int]]) -> bytes:
    """Create a minimal PNG from RGBA pixel list."""
    def chunk(name: bytes, data: bytes) -> bytes:
        c = name + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    header = b"\x89PNG\r\n\x1a\n"
    ihdr_data = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # RGB
    # We'll use RGBA (colortype=6)
    ihdr_data = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    ihdr = chunk(b"IHDR", ihdr_data)

    raw_rows = b""
    for y in range(height):
        raw_rows += b"\x00"  # filter type None
        for x in range(width):
            r, g, b, a = pixels[y * width + x]
            raw_rows += bytes([r, g, b, a])

    idat = chunk(b"IDAT", zlib.compress(raw_rows, 9))
    iend = chunk(b"IEND", b"")
    return header + ihdr + idat + iend


def make_circle_pixels(size: int, r: int, g: int, b: int) -> list[tuple[int, int, int, int]]:
    """Draw an antialiased filled circle of given color on transparent background."""
    pixels = []
    cx = cy = (size - 1) / 2.0
    radius = (size - 2) / 2.0
    for y in range(size):
        for x in range(size):
            dist = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            # Smooth edge
            alpha = max(0.0, min(1.0, radius - dist + 0.5))
            pixels.append((r, g, b, int(alpha * 255)))
    return pixels


def png_to_ico(png_data: bytes, width: int, height: int) -> bytes:
    """Wrap a PNG image into a minimal ICO file."""
    # ICO header
    ico_header = struct.pack("<HHH", 0, 1, 1)  # reserved, type=1 (ICO), count=1
    # Image directory entry (16 bytes)
    png_size = len(png_data)
    offset = 6 + 16  # after header + one directory entry
    dir_entry = struct.pack(
        "<BBBBHHII",
        width if width < 256 else 0,   # width (0 = 256)
        height if height < 256 else 0, # height
        0,    # color count (0 = not palettized)
        0,    # reserved
        1,    # color planes
        32,   # bits per pixel
        png_size,
        offset,
    )
    return ico_header + dir_entry + png_data


def generate_icon(output_path: str, r: int, g: int, b: int, size: int = 16):
    pixels = make_circle_pixels(size, r, g, b)
    png_data = rgba_to_png(size, size, pixels)
    ico_data = png_to_ico(png_data, size, size)
    with open(output_path, "wb") as f:
        f.write(ico_data)
    print(f"[make_icons] Written: {output_path} ({len(ico_data)} bytes)")


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out_dir, exist_ok=True)

    # Connected = blue (#2CA5E0 = 44,165,224)
    generate_icon(os.path.join(out_dir, "icon_connected.ico"), 44, 165, 224)

    # Disconnected = gray (#888888 = 136,136,136)
    generate_icon(os.path.join(out_dir, "icon_disconnected.ico"), 136, 136, 136)

    print("[make_icons] Done.")


if __name__ == "__main__":
    main()
