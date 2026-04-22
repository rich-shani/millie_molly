#!/usr/bin/env python3
"""
Edit Millie and Molly level data in levels.bin.

Allows setting block types at specific coordinates and writing back to the binary file.
"""

import sys
import os
from pathlib import Path

# Block type constants
BLOCK_TYPES = {
    "EMPTY": 0,
    ".": 0,
    "LADDER": 1,
    "H": 1,
    "ENEMYFALL": 2,
    "E": 2,
    "PUSH": 3,
    "B": 3,
    "DIRT": 4,
    "D": 4,
    "SOLID": 5,
    "#": 5,
    "ENEMYFLOAT": 6,
    "F": 6,
    "MILLIESTART": 7,
    "M": 7,
    "MOLLYSTART": 8,
    "m": 8,
}

BLOCK_NAMES = {
    0: "EMPTY",
    1: "LADDER",
    2: "ENEMYFALL",
    3: "PUSH",
    4: "DIRT",
    5: "SOLID",
    6: "ENEMYFLOAT",
    7: "MILLIESTART",
    8: "MOLLYSTART",
}

# Color codes
class Colors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"

SYMBOLS = {
    0: (Colors.DIM + "." + Colors.RESET, "Empty space"),
    1: (Colors.CYAN + "H" + Colors.RESET, "Ladder"),
    2: (Colors.RED + "E" + Colors.RESET, "Enemy (falls)"),
    3: (Colors.YELLOW + "B" + Colors.RESET, "Block (pushable)"),
    4: (Colors.YELLOW + "D" + Colors.RESET, "Dirt (breakable)"),
    5: (Colors.BOLD + "#" + Colors.RESET, "Solid wall"),
    6: (Colors.RED + "F" + Colors.RESET, "Enemy (floats)"),
    7: (Colors.GREEN + "M" + Colors.RESET, "Millie start"),
    8: (Colors.GREEN + "m" + Colors.RESET, "Molly start"),
}

def get_levels_bin_path():
    """Find the levels.bin file."""
    script_dir = Path(__file__).parent
    levels_bin = script_dir.parent / "assets" / "Levels" / "levels.bin"

    if not levels_bin.exists():
        print(f"Error: Could not find {levels_bin}")
        sys.exit(1)

    return levels_bin

def read_level(levels_bin_path, level_id):
    """Read a single level from levels.bin."""
    with open(levels_bin_path, "rb") as f:
        f.seek(level_id * 88)
        level_data = f.read(88)

    # Convert to 2D grid
    grid = []
    for row in range(8):
        row_data = level_data[row * 11:(row + 1) * 11]
        grid.append(list(row_data))

    return grid

def write_level(levels_bin_path, level_id, grid):
    """Write a level back to levels.bin."""
    # Convert 2D grid back to bytes
    level_data = bytearray()
    for row in grid:
        for cell in row:
            level_data.append(cell)

    # Write back to file
    with open(levels_bin_path, "r+b") as f:
        f.seek(level_id * 88)
        f.write(level_data)

def display_level(grid, title=""):
    """Display a level grid."""
    if title:
        print(f"\n{Colors.BOLD}{title}{Colors.RESET}")
    print("=" * 50)

    print("    ", end="")
    for col in range(11):
        print(f"{col:2d} ", end="")
    print()

    for row_idx, row in enumerate(grid):
        print(f"{row_idx:2d}: ", end="")
        for cell in row:
            symbol, _ = SYMBOLS.get(cell, ("?", "Unknown"))
            print(f"{symbol}  ", end="")
        print()

def set_block(grid, col, row, block_type):
    """Set a block at the specified coordinate."""
    if col < 0 or col >= 11 or row < 0 or row >= 8:
        print(f"Error: Coordinates ({col}, {row}) out of range")
        return False

    if block_type < 0 or block_type > 8:
        print(f"Error: Block type {block_type} out of range")
        return False

    old_block = grid[row][col]
    grid[row][col] = block_type
    print(f"Set ({col}, {row}) from {BLOCK_NAMES.get(old_block, '?')} to {BLOCK_NAMES.get(block_type, '?')}")
    return True

def get_block(grid, col, row):
    """Get the block type at the specified coordinate."""
    if col < 0 or col >= 11 or row < 0 or row >= 8:
        print(f"Error: Coordinates ({col}, {row}) out of range")
        return None

    return grid[row][col]

def main():
    levels_bin_path = get_levels_bin_path()

    if len(sys.argv) < 2:
        print("Millie and Molly Level Editor")
        print("=" * 50)
        print("\nUsage:")
        print(f"  {sys.argv[0]} <level_id> get <col> <row>")
        print(f"    - Show what block is at the specified position")
        print()
        print(f"  {sys.argv[0]} <level_id> set <col> <row> <block_type>")
        print(f"    - Set a block at the specified position")
        print()
        print(f"  {sys.argv[0]} <level_id> view")
        print(f"    - Display the level")
        print()
        print("Block types (use any of these):")
        print("  0/.         = EMPTY")
        print("  1/H         = LADDER")
        print("  2/E         = ENEMYFALL")
        print("  3/B         = PUSH")
        print("  4/D         = DIRT")
        print("  5/#         = SOLID")
        print("  6/F         = ENEMYFLOAT")
        print("  7/M         = MILLIESTART")
        print("  8/m         = MOLLYSTART")
        print()
        print("Examples:")
        print(f"  {sys.argv[0]} 26 view")
        print(f"  {sys.argv[0]} 26 get 5 3")
        print(f"  {sys.argv[0]} 26 set 0 0 H")
        print(f"  {sys.argv[0]} 26 set 5 5 M")
        return

    try:
        level_id = int(sys.argv[1])
        if level_id < 0 or level_id >= 100:
            print(f"Error: Level {level_id} out of range (0-99)")
            return

        grid = read_level(levels_bin_path, level_id)

        if len(sys.argv) < 3:
            display_level(grid, f"Level {level_id}")
            return

        command = sys.argv[2].lower()

        if command == "view":
            display_level(grid, f"Level {level_id}")

        elif command == "get":
            if len(sys.argv) < 5:
                print("Error: get requires <col> <row>")
                return
            col = int(sys.argv[3])
            row = int(sys.argv[4])
            block = get_block(grid, col, row)
            if block is not None:
                print(f"Block at ({col}, {row}): {BLOCK_NAMES.get(block, '?')} ({block})")

        elif command == "set":
            if len(sys.argv) < 6:
                print("Error: set requires <col> <row> <block_type>")
                return
            col = int(sys.argv[3])
            row = int(sys.argv[4])
            block_str = sys.argv[5]

            # Parse block type
            if block_str.isdigit():
                block_type = int(block_str)
            else:
                block_type = BLOCK_TYPES.get(block_str.upper())
                if block_type is None:
                    print(f"Error: Unknown block type '{block_str}'")
                    return

            if set_block(grid, col, row, block_type):
                write_level(levels_bin_path, level_id, grid)
                print(f"Wrote level {level_id} back to {levels_bin_path}")
                display_level(grid, f"Level {level_id} (updated)")
        else:
            print(f"Error: Unknown command '{command}'")

    except (ValueError, IndexError) as e:
        print(f"Error: Invalid arguments")
        print(f"Details: {e}")

if __name__ == "__main__":
    main()
