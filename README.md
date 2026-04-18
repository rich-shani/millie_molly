# Millie and Molly - Amiga Port

A faithful Amiga port of the classic puzzle-platformer game **Millie and Molly**, featuring native 68000 assembly programming with extensive use of Amiga custom chips (Blitter, Copper, and Agnus).

## Overview

This is a complete reimplementation of the Millie and Molly puzzle game for the Commodore Amiga, written entirely in 68000 assembly language. The port showcases advanced Amiga programming techniques including:

- **Blitter-accelerated graphics** - All tile rendering uses the Amiga's hardware Blitter for optimal performance
- **Copper programming** - Hardware interrupt-driven vertical-blank synchronization and palette management
- **Custom DMA control** - Direct Memory Access configuration for bitplane, sprite, and Copper data
- **Real-time animation** - Smooth pixel-by-pixel character movement with sub-tile animation frames
- **Dynamic actor management** - Efficient actor pool system with gravity physics and collision detection

## Gameplay Features

### Core Mechanics

- **Two-player puzzle platforming** - Control Millie and Molly to solve level puzzles
- **Gravity physics** - Characters and objects fall under gravity with realistic easing
- **Interactive elements**:
  - **Ladders** - Climb up and down with dedicated climbing animations
  - **Pushable blocks** - Slide blocks horizontally to solve puzzles
  - **Breakable dirt** - Destroy dirt blocks by walking through them
  - **Enemies** - Falling and floating enemies with gravity physics
  - **Walls and platforms** - Navigate solid obstacles with varied tileset graphics

### Player Controls

| Input | Action |
|-------|--------|
| **Arrow Keys** | Move left/right, climb ladders up/down |
| **FIRE/Space** | Switch between Millie and Molly |
| **F1-F2** | Navigate levels (debug) |

### Level Progression

- **Dynamic level system** - Multiple tileset variations with randomized wall patterns
- **Level completion** - Destroy all enemies to complete a level
- **Asset switching** - Each level uses appropriately themed tile graphics and palettes

## Technical Architecture

### System Requirements

- **Amiga 500/600/1200** or compatible system
- **512 KB Chip RAM** minimum
- **68000 processor** at 7.16 MHz (PAL) or 7.86 MHz (NTSC)

### Display Specifications

- **Resolution**: 336×216 pixels (PAL)
- **Color depth**: 5 bitplanes = 32 colors
- **Screen buffers**: 
  - `ScreenSave` - Clean background (walls, ladders, shadows)
  - `ScreenStatic` - Working display buffer with actors
  - `Screen1/2` - Display output buffers

### Video Memory Layout

```
ScreenSave:    45,360 bytes (336×216×5 planes)
ScreenStatic:  45,360 bytes (working display)
TileSet:       13,920 bytes (29 tiles × 5 planes × 24×24 pixels)
Sprites:       69,120 bytes (144 actor sprite frames)
```

### Frame Timing

- **VBlank interrupt** at ~50 Hz (PAL) - Drives all game logic and animation
- **Sub-frame animation** - Actors animate at 1 pixel per frame during movement
- **Input polling** - Keyboard state sampled each VBlank via CIA-A serial interface

## Blitter Programming

### Tile Rendering

All tile rendering uses the **Amiga Blitter** with minterm operations for transparent blitting:

```
Minterm $fca: D = (A & B) | (~A & C)
  A = TileMask (per-tile transparency mask)
  B = TileSet (tile graphics)
  C = ScreenStatic (destination buffer)
  D = ScreenStatic (output)
```

Result: Where mask A=1, output tile; where A=0, preserve background.

### Background Restoration

When actors move or fall through tiles:

```
Minterm $7ca: D = (A & D) | (~A & C)
  A = constant $ffff (full mask)
  B = ScreenSave (clean background)
  C = ScreenStatic (current display)
  D = ScreenStatic (output)
```

Copies background tile from `ScreenSave`, restoring pixels behind animated actors.

## Project Structure

```
MillieMolly/
├── main.asm                    # Entry point, VBlank handler, utilities
├── include/resources/
│   ├── actors.asm             # Actor pool management, initialization
│   ├── player.asm             # Player logic, movement, animation (63KB)
│   ├── mapstuff.asm           # Level rendering, Blitter operations
│   ├── gamestatus.asm         # Game state machine
│   ├── title.asm              # Title screen logic
│   ├── controls.asm           # Keyboard input handling
│   ├── keyboard.asm           # CIA-A keyboard interrupt handler
│   ├── struct.asm             # Data structure definitions
│   ├── const.asm              # Global constants (block types, tile indices)
│   ├── macros.asm             # Utility macros (JMPINDEX, WAITBLIT, etc)
│   ├── copperlists.asm        # Copper list initialization
│   ├── variables.asm          # BSS memory layout
│   ├── assets.asm             # Asset loading and decompression
│   ├── spritetools.asm        # Hardware sprite utilities
│   ├── zx0_faster.asm         # ZX0 decompression engine
│   └── tools.asm              # Utility routines (TurboClear, etc)
├── assets/
│   ├── Tiles/                 # Tile graphics source files
│   ├── Levels/                # Level data files
│   ├── sprites.bin            # Uncompressed actor sprite sheet
│   ├── sprites.pal            # 16-color palette for actors
│   ├── Tiles_[0-4].png        # 5 tileset variations
│   ├── shadows.bin            # Shadow shape overlays
│   ├── sin.bin                # Sine table for easing
│   ├── quadratic.bin          # Quadratic easing curve
│   ├── levelfont.bin          # Level counter font
│   ├── title.raw              # Title screen graphics
│   └── test.bin               # Test assets
├── build/
│   └── main.o                 # Assembled object file
├── uae/                        # UAE emulator configs
└── .vscode/                    # VSCode build tasks
```

## Game Architecture

### Actor System

**Actor Structure** (per-actor data):
- Position (tile X/Y)
- Animation state (frame index, animation counter)
- Movement state (previous position, delta offsets for sub-tile animation)
- Physics (can fall, falling state, fall distance)
- Status (alive/dead)

**Actor Types**:
- `BLOCK_ENEMYFALL` - Enemy subject to gravity
- `BLOCK_ENEMYFLOAT` - Floating enemy (no gravity)
- `BLOCK_PUSH` - Pushable block
- `BLOCK_DIRT` - Breakable dirt block

**Actor Lifecycle**:
1. **Initialization** - Created at level start from map data
2. **Animation** - Animated via `ClearActor`/`DrawActor` during state changes
3. **Physics** - Fall under gravity if unsupported
4. **Cleanup** - Removed when destroyed by player or level changes

### Player State Machine

```
ActionStatus values:
  ACTION_IDLE (0)      → ActionIdle
  ACTION_MOVE (1)      → ActionMove (24-frame animation)
  ACTION_FALL (2)      → ActionFall (eased quadratic fall)
  ACTION_PLAYERPUSH (3)→ ActionPlayerPush (12-frame push animation)
```

**Movement Flow**:
1. `ActionIdle` reads controls
2. `PlayerTryMove` determines what can be done (walk, push, climb, kill enemy)
3. Action handler advances animation state each VBlank
4. When complete, returns to `ActionIdle`

### Rendering Pipeline

```
Initial Level Setup (DrawMap):
  1. TurboClear(ScreenSave)       → Blank starting canvas
  2. SetLevelAssets()              → Load tileset and palette
  3. GenTileMask()                 → Build transparency masks
  4. WallPaperLoadBase()           → Load border template
  5. WallPaperLoadLevel()          → Copy level data into maps
  6. WallPaperWalls()              → Build wall tile variants
  7. WallpaperMakeLadders()        → Build ladder overlays
  8. WallpaperMakeShadows()        → Build shadow overlays
  9. InitGameObjects()             → Create actors from map
  10. DrawWalls()                   → Render backgrounds to ScreenSave
  11. DrawLadders()                 → Overlay ladders
  12. DrawShadows()                 → Overlay shadows
  13. CopySaveToStatic()            → Copy to ScreenStatic
  14. DrawStaticActors()            → Blit actors
  15. CopyStaticToBuffers()         → Copy to display output

Per-Frame Rendering (GameRun):
  1. PlayerLogic()                  → Advance action state
  2. ClearMovedActors()             → Erase old positions
  3. Display via Copper+Denise      → Custom chip outputs pixels
```

### Ladder Animation System

The ladder system uses an intelligent sprite selection system:

- **Climbing sprite** shown when:
  - Moving vertically (UP or DOWN) on a ladder
  - Moving on a ladder with more ladder cells adjacent

- **Walking sprite** shown when:
  - Moving horizontally away from ladder
  - At bottom of ladder, not moving upward
  - Not on a ladder cell

This ensures smooth transitions between climbing and walking animations based on player input and position.

## Building

### Prerequisites

- **VASM assembler** (`vasmm68k_mot`) - 68000 Motorola syntax assembler
- **Python 3.x** - For asset build scripts (if included)
- **UAE emulator** - For testing (optional)

### Build Command

```bash
# Assemble main program
vasmm68k_mot -Fhunkexe -o main.exe main.asm

# Run in emulator
uae --fullscreen
```

### Build Output

- **main.o** - Assembled object file
- **main.exe** - Final executable disk image (when linked)

## Key Technical Achievements

### Blitter Optimization

- **Masked tile blitting** with shift-aware modulo calculations
- **Background restoration** during pixel-by-pixel animation
- **Shadow overlays** using per-plane OR operations
- **Button graphics** with dynamic digit rendering for level counter

### Custom Chip Programming

- **Copper list generation** for palette management and display timing
- **VBlank interrupt handler** for synchronized game updates
- **DMA control** for Blitter, Bitplanes, Sprites, and Copper
- **CIA keyboard interrupt** for real-time input

### Performance

- All tile rendering uses the Blitter (no CPU blits)
- Actor animation uses localized blitter operations
- Copper handles timing—CPU runs game logic
- Efficient actor pooling with O(N) update cost

## Development Status

### Completed

✅ Core gameplay loop (move, push, climb, fall)  
✅ Actor physics and gravity  
✅ Ladder climbing mechanics  
✅ Level system with multiple tilesets  
✅ Blitter-accelerated rendering  
✅ Player animation and sprite selection  
✅ Enemy AI (falling and floating)  
✅ Dirt destruction mechanics  

### In Progress / TODO

⏳ Enemy destruction animations  
⏳ Fall animation easing  
⏳ Enter/leave ladder animations  
⏳ Kick animations  
⏳ Rewind/undo mechanic  
⏳ Game presentation polish  

## Register Conventions

Throughout the codebase:

```
a5 = Variables base pointer (maintained throughout)
a6 = $dff000 (CUSTOM chip base)
a4 = Current player structure pointer
a3 = Current actor structure pointer

d0-d3 = General scratch registers (destroyed by called routines)
d4-d7 = Preserved across subroutine calls
```

## References & Documentation

- **Commodore Amiga Hardware Reference Manual** - Custom chip programming
- **68000 Programmer's Reference** - Motorola assembly syntax
- **VASM Documentation** - Assembler-specific features
- **Amiga Display Database** - Display timing and resolutions

## License

Educational/hobby project. Original Millie and Molly concept adapted for Amiga.

## Author Notes

This port demonstrates authentic Amiga programming techniques from the golden era of 1980s-90s computer graphics. Every optimization trades off CPU cycles against hardware capabilities—the Blitter is leveraged wherever possible, and the Copper handles all display timing synchronization. The result is a smooth, responsive game that runs efficiently on original Amiga hardware.

The codebase serves as both a playable game and an educational reference for Amiga assembly programming, showing how to:
- Use the Blitter effectively for graphics
- Manage VBlank interrupts for game timing
- Implement actor systems with gravity physics
- Create smooth animations with sub-tile pixel movement
- Handle complex game state machines in real-time

---

**Current Build Date**: April 18, 2026  
**Last Working Feature**: Ladder climbing with correct sprite selection based on movement direction
