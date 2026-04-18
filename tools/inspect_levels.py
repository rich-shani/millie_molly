#!/usr/bin/env python3
"""
Inspect Millie and Molly level data files.

Reads levels.bin and displays level maps in human-readable format.
Each level is 88 bytes (11 columns x 8 rows).
"""

import sys
import os
from pathlib import Path

# Block type constants
BLOCK_TYPES = {
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

# Color codes for terminal output
class Colors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    MAGENTA = "\033[95m"
    CYAN = "\033[96m"

# Colored symbols for each block type
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
    """Find the levels.bin file relative to this script."""
    script_dir = Path(__file__).parent
    levels_bin = script_dir.parent / "assets" / "Levels" / "levels.bin"

    if not levels_bin.exists():
        print(f"Error: Could not find {levels_bin}")
        sys.exit(1)

    return levels_bin

def read_levels(levels_bin_path):
    """Read and parse all levels from levels.bin."""
    with open(levels_bin_path, "rb") as f:
        data = f.read()

    # Each level is 88 bytes (11 columns x 8 rows)
    MAP_WIDTH = 11
    MAP_HEIGHT = 8
    LEVEL_SIZE = MAP_WIDTH * MAP_HEIGHT

    num_levels = len(data) // LEVEL_SIZE

    levels = []
    for level_id in range(num_levels):
        offset = level_id * LEVEL_SIZE
        level_data = data[offset:offset + LEVEL_SIZE]

        # Convert to 2D grid
        grid = []
        for row in range(MAP_HEIGHT):
            row_data = level_data[row * MAP_WIDTH:(row + 1) * MAP_WIDTH]
            grid.append(list(row_data))

        levels.append({
            'id': level_id,
            'grid': grid,
            'raw': level_data
        })

    return levels, num_levels

def display_level(level, show_coords=True):
    """Display a single level in a readable format."""
    print(f"\n{Colors.BOLD}Level {level['id']:2d}{Colors.RESET}")
    print("=" * 50)

    grid = level['grid']

    # Column headers
    if show_coords:
        print("    ", end="")
        for col in range(len(grid[0])):
            print(f"{col:2d} ", end="")
        print()

    # Row data
    for row_idx, row in enumerate(grid):
        if show_coords:
            print(f"{row_idx:2d}: ", end="")

        for cell in row:
            symbol, _ = SYMBOLS.get(cell, ("?", "Unknown"))
            print(f"{symbol}  ", end="")

        print()

    # Summary
    millie_pos = None
    molly_pos = None

    for row_idx, row in enumerate(grid):
        for col_idx, cell in enumerate(row):
            if cell == 7:  # MILLIESTART
                millie_pos = (col_idx, row_idx)
            elif cell == 8:  # MOLLYSTART
                molly_pos = (col_idx, row_idx)

    print()
    if millie_pos:
        print(f"  Millie start: ({millie_pos[0]}, {millie_pos[1]})")
    else:
        print(f"  {Colors.RED}Millie start: NOT DEFINED{Colors.RESET}")

    if molly_pos:
        print(f"  Molly start:  ({molly_pos[0]}, {molly_pos[1]})")
    else:
        print(f"  {Colors.RED}Molly start: NOT DEFINED{Colors.RESET}")

    # Block counts
    block_counts = {}
    for row in grid:
        for cell in row:
            block_type = BLOCK_TYPES.get(cell, f"Unknown({cell})")
            block_counts[block_type] = block_counts.get(block_type, 0) + 1

    print("\n  Block counts:")
    for block_type, count in sorted(block_counts.items()):
        symbol, desc = SYMBOLS.get([k for k, v in BLOCK_TYPES.items() if v == block_type][0], ("?", ""))
        print(f"    {symbol} {block_type:12s}: {count:2d}")

def main():
    levels_bin_path = get_levels_bin_path()
    levels, num_levels = read_levels(levels_bin_path)

    print(f"Loaded {num_levels} levels from {levels_bin_path}")

    if len(sys.argv) < 2:
        # Show usage
        print("\nUsage:")
        print(f"  {sys.argv[0]} <level_id>       - Show a specific level")
        print(f"  {sys.argv[0]} all              - Show all levels")
        print(f"  {sys.argv[0]} missing          - Show levels with missing Millie or Molly start")
        print(f"  {sys.argv[0]} <start> <end>    - Show levels from start to end (inclusive)")
        print()
        print("Examples:")
        print(f"  {sys.argv[0]} 26")
        print(f"  {sys.argv[0]} 0 10")
        print(f"  {sys.argv[0]} missing")
        return

    if sys.argv[1] == "all":
        # Show all levels
        for level in levels:
            display_level(level)
    elif sys.argv[1] == "missing":
        # Show levels with missing player starts
        print("\nLevels with missing player starts:")
        print("=" * 50)
        for level in levels:
            millie_found = False
            molly_found = False

            for row in level['grid']:
                for cell in row:
                    if cell == 7:
                        millie_found = True
                    elif cell == 8:
                        molly_found = True

            if not millie_found or not molly_found:
                missing = []
                if not millie_found:
                    missing.append("Millie")
                if not molly_found:
                    missing.append("Molly")
                print(f"Level {level['id']:2d}: Missing {', '.join(missing)}")
    else:
        # Show specific level(s)
        try:
            if len(sys.argv) == 2:
                level_id = int(sys.argv[1])
                if 0 <= level_id < num_levels:
                    display_level(levels[level_id])
                else:
                    print(f"Error: Level {level_id} out of range (0-{num_levels-1})")
            else:
                start = int(sys.argv[1])
                end = int(sys.argv[2])
                for level_id in range(start, min(end + 1, num_levels)):
                    display_level(levels[level_id])
        except ValueError:
            print("Error: Invalid argument")

if __name__ == "__main__":
    main()
