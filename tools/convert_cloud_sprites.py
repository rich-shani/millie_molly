#!/usr/bin/env python3
"""
convert_cloud_sprites.py - Convert cloud tiles to Amiga unattached hardware sprite format

Reads sprites.bin and sprites.pal, converts the 7 cloud death-animation frames
(SPRITE_CLOUD_A..G, tile indices 132-138) to two-sprite unattached format for
display on SPR0 and SPR1.

UNATTACHED SPRITE FORMAT
-------------------------
Two independent sprites (SPR0 and SPR1) placed side by side cover the 24px tile width:
  SPR0 at X:    pixels 0-15  (left half)
  SPR1 at X+16: pixels 16-23 (right 8px, left-justified in 16px sprite; rest transparent)

Each sprite uses 2-bit colour (3 colours + transparent) from COLOR17-COLOR19:
  2-bit index 0 = transparent
  2-bit index 1 = COLOR17 (dark)
  2-bit index 2 = COLOR18 (medium)
  2-bit index 3 = COLOR19 (bright)

Sprite data format per row (4 bytes = 2 words):
  word A (high word): high bit of 2-bit index for each pixel
  word B (low  word): low  bit of 2-bit index for each pixel
  pixel 0 in bit 15 (MSB), pixel 15 in bit 0 (LSB)

Memory layout per frame:
  [SPR0_data][SPR1_data] = 2 * SPRITE_SIZE = 208 bytes per frame

Colour quantisation from 4-bit hw sprite index to 2-bit unattached index:
  hw_index 0 -> transparent (index 0)
  hw_index 1-15 -> luminance (G+B from sprites.pal; R is always 0 in this game):
    lum  0-10 -> index 1 (dark,   COLOR17)
    lum 11-20 -> index 2 (medium, COLOR18)
    lum 21+   -> index 3 (bright, COLOR19)

OUTPUT
-------
assets/particle_hw_sprites.bin
  Cloud: 7 frames x 208 bytes = 1456 bytes total (dirt and smoke to be added)
"""

import struct
import os
import sys

TILE_HEIGHT = 24
TILE_WIDTHF = 32
PLANES      = 5
TILE_SIZE   = (TILE_WIDTHF // 8) * PLANES * TILE_HEIGHT  # 480 bytes
SPRITE_SIZE = 4 + (TILE_HEIGHT * 4) + 4                  # 104 bytes
HW_CLOUD_FRAME_SIZE = 2 * SPRITE_SIZE                     # 208 bytes

CLOUD_TILE_INDICES = list(range(132, 139))  # 7 frames: SPRITE_CLOUD_A..G


def read_palette(pal_path):
    """Read sprites.pal: 32 big-endian 16-bit words, each an Amiga 12-bit colour (0x0RGB)."""
    with open(pal_path, 'rb') as f:
        data = f.read(64)
    colors = []
    for i in range(32):
        word = struct.unpack_from('>H', data, i * 2)[0]
        r = (word >> 8) & 0xF
        g = (word >> 4) & 0xF
        b = (word >> 0) & 0xF
        colors.append((r, g, b))
    return colors


def get_pixel(sprites_bin, tile_idx, row, col):
    """Return 5-bit colour index of pixel (row, col) from interleaved tile data."""
    off = tile_idx * TILE_SIZE + row * PLANES * 4
    bit = 31 - col
    val = 0
    for p in range(PLANES):
        word = struct.unpack_from('>I', sprites_bin, off + p * 4)[0]
        val |= (((word >> bit) & 1) << p)
    return val


def to_hw_index(tile_pixel):
    """5-bit tile colour index -> 4-bit hardware sprite index (0=transparent)."""
    if tile_pixel == 0 or tile_pixel == 16:
        return 0
    if 1 <= tile_pixel <= 15:
        return 0  # tile palette entry; treat as transparent for sprites
    return tile_pixel - 16  # 17-31 -> 1-15


def to_2bit_index(hw_idx, palette):
    """4-bit hardware sprite index -> 2-bit unattached sprite index (0-3)."""
    if hw_idx == 0:
        return 0
    r, g, b = palette[16 + hw_idx]  # COLOR16+hw_idx = sprite palette entry
    lum = g + b                       # R is always 0 for this game's palette
    if lum <= 10:
        return 1  # dark   -> COLOR17
    elif lum <= 20:
        return 2  # medium -> COLOR18
    else:
        return 3  # bright -> COLOR19


def build_unattached_sprite(rows_2bit):
    """
    Build one 104-byte unattached sprite structure from rows of 2-bit colour indices.

    rows_2bit: list of 24 lists, each containing 16 two-bit indices (0-3).
    Returns SPRITE_SIZE bytes:
      Bytes  0-3:   header (zeroed; SpriteCoord fills this at runtime)
      Bytes  4-99:  24 rows x 4 bytes (word_A high bit, word_B low bit per pixel)
      Bytes 100-103: terminator (zeroed)
    """
    data = bytearray(SPRITE_SIZE)
    for row, row_pix in enumerate(rows_2bit):
        wa = wb = 0
        for col, c in enumerate(row_pix):
            bp = 15 - col          # bit position: pixel 0 -> MSB
            if (c >> 1) & 1:
                wa |= 1 << bp
            if (c >> 0) & 1:
                wb |= 1 << bp
        off = 4 + row * 4
        struct.pack_into('>HH', data, off, wa, wb)
    return bytes(data)


def convert_frame(sprites_bin, tile_idx, palette, name):
    """Convert one cloud tile to a 208-byte unattached sprite frame (SPR0 + SPR1)."""
    left_rows  = []   # columns 0-15  -> SPR0
    right_rows = []   # columns 16-23 left-justified, 24-31 transparent -> SPR1
    colors_seen = set()

    for row in range(TILE_HEIGHT):
        left_row  = []
        right_row = []

        for col in range(16):
            tp = get_pixel(sprites_bin, tile_idx, row, col)
            colors_seen.add(tp)
            left_row.append(to_2bit_index(to_hw_index(tp), palette))

        for col in range(16, 32):
            tp = get_pixel(sprites_bin, tile_idx, row, col)
            if col < 24:
                colors_seen.add(tp)
                right_row.append(to_2bit_index(to_hw_index(tp), palette))
            else:
                right_row.append(0)  # padding: cols 24-31 are transparent

        left_rows.append(left_row)
        right_rows.append(right_row)

    spr0 = build_unattached_sprite(left_rows)
    spr1 = build_unattached_sprite(right_rows)
    return spr0 + spr1, colors_seen


def preview_frame(sprites_bin, tile_idx, name):
    """Print a 24x24 ASCII art preview of the raw tile content."""
    CHARS = ' .,:;+*#@'
    print(f"  {name} (tile {tile_idx}):")
    for row in range(TILE_HEIGHT):
        line = '  |'
        for col in range(24):
            tp = get_pixel(sprites_bin, tile_idx, row, col)
            hi = to_hw_index(tp)
            line += CHARS[min(hi, len(CHARS) - 1)] if hi > 0 else ' '
        line += '|'
        print(line)
    print()


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sprites_path = os.path.join(root, 'assets', 'sprites.bin')
    pal_path     = os.path.join(root, 'assets', 'sprites.pal')
    output_path  = os.path.join(root, 'assets', 'particle_hw_sprites.bin')

    if not os.path.exists(sprites_path):
        print(f"ERROR: {sprites_path} not found.")
        sys.exit(1)
    if not os.path.exists(pal_path):
        print(f"ERROR: {pal_path} not found.")
        sys.exit(1)

    with open(sprites_path, 'rb') as f:
        sprites_bin = f.read()
    palette = read_palette(pal_path)

    show_preview = '--preview' in sys.argv or '-p' in sys.argv

    print(f"Sprite palette (COLOR16-COLOR19, used by SPR0/SPR1):")
    for i in range(16, 20):
        r, g, b = palette[i]
        print(f"  COLOR{i:02d}: #{r:X}{g:X}{b:X}  lum={g+b}")
    print()

    output = bytearray()
    print(f"Cloud frames ({len(CLOUD_TILE_INDICES)} frames, "
          f"tile indices {CLOUD_TILE_INDICES[0]}-{CLOUD_TILE_INDICES[-1]}):")

    for i, tile_idx in enumerate(CLOUD_TILE_INDICES):
        name = f'CLOUD_{i}'
        frame_data, colors_seen = convert_frame(sprites_bin, tile_idx, palette, name)

        hw_2bit = set()
        for tp in colors_seen:
            hi = to_hw_index(tp)
            hw_2bit.add(to_2bit_index(hi, palette))

        print(f"  [{i * HW_CLOUD_FRAME_SIZE:4d}] {name}: tile {tile_idx}, "
              f"tile_colors={sorted(colors_seen)}, 2bit_indices={sorted(hw_2bit)}, "
              f"{len(frame_data)} bytes")

        if show_preview:
            preview_frame(sprites_bin, tile_idx, name)

        output.extend(frame_data)

    with open(output_path, 'wb') as f:
        f.write(output)

    expected = len(CLOUD_TILE_INDICES) * HW_CLOUD_FRAME_SIZE
    print(f"\nWrote {len(output)} bytes -> {output_path}")
    if len(output) != expected:
        print(f"WARNING: expected {expected} bytes")

    print(f"\n; Assembly constants (const.asm):")
    print(f"HW_CLOUD_FRAME_SIZE = {HW_CLOUD_FRAME_SIZE}  ; 2 * SPRITE_SIZE = 208 bytes per frame")
    print(f"; Total: {len(output)} bytes ({len(CLOUD_TILE_INDICES)} frames x {HW_CLOUD_FRAME_SIZE})")


if __name__ == '__main__':
    main()
