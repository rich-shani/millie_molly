# Millie and Molly - Amiga Port

An Amiga port of the puzzle-platformer game **Millie and Molly**, featuring native 68000 assembly programming with extensive use of Amiga custom chips (Blitter, Copper, and Agnus).

## Overview

The game targets OCS/ECS hardware at PAL 50 Hz, uses five bitplanes (32 colours), four hardware sprite channels (two attached pairs for the player characters), and drives the blitter exclusively for tile rendering, background restoration,
and screen wipe transitions.

- **Blitter-accelerated graphics** - All tile rendering uses the Amiga's hardware Blitter for optimal performance
- **Copper programming** - Hardware interrupt-driven vertical-blank synchronization and palette management
- **Custom DMA control** - Direct Memory Access configuration for bitplane, sprite, and Copper data
- **Real-time animation** - Smooth pixel-by-pixel character movement with sub-tile animation frames
- **Dynamic actor management** - Efficient actor pool system with gravity physics and collision detection

## Gameplay Features

### Core Mechanics

- **Two-player puzzle platforming** - Control Millie and Molly to solve level puzzles
- **Gravity physics** - Characters and objects fall under genuine constant-acceleration physics (slow→fast)
- **Interactive elements**:
  - **Ladders** - Climb up and down with dedicated climbing animations
  - **Pushable blocks** - Slide blocks horizontally to solve puzzles
  - **Breakable dirt** - Destroy dirt blocks by walking through them
  - **Enemies** - Falling and floating enemies with animated tiles; enemy death triggers a 7-frame cloud puff animation
  - **Walls and platforms** - Navigate solid obstacles with varied tileset graphics
- **Undo / rewind** - Press F9 to step back up to 8 moves using a circular snapshot buffer

### Player Controls

| Input | Action |
|-------|--------|
| **Arrow Keys** | Move left/right, climb ladders up/down |
| **FIRE/Space** | Switch between Millie and Molly |
| **F1-F2**     | Navigate levels (debug) |
| **F3**        | Start game (from Title Screen) |
| **F9**        | Undo last move (up to 8 steps) |

### Level Progression

- **Dynamic level system** - Multiple tileset variations with randomized wall patterns
- **Level completion** - Destroy all enemies to complete a level; triggers a tile-based black wipe then reverse reveal of the next level
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
  - `NonDisplayScreen` - Clean background (walls, ladders, shadows)
  - `DisplayScreen` - Working display buffer with actors
  - `Screen1/2` - Display output buffers

### Video Memory Layout

```
NonDisplayScreen:    45,360 bytes (336×216×5 planes)
DisplayScreen:  45,360 bytes (working display)
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
  C = DisplayScreen (destination buffer)
  D = DisplayScreen (output)
```

Result: Where mask A=1, output tile; where A=0, preserve background.

### Background Restoration

When actors move or fall through tiles:

```
Minterm $7ca: D = (A & D) | (~A & C)
  A = constant $ffff (full mask)
  B = NonDisplayScreen (clean background)
  C = DisplayScreen (current display)
  D = DisplayScreen (output)
```

Copies background tile from `NonDisplayScreen`, restoring pixels behind animated actors.

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
│   ├── undo.asm               # Snapshot-based undo/rewind system
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
- `Actor_ImpactTick` — landing smoke puff animation counter (4 frames)
- `Actor_CloudTick` — enemy death cloud animation counter (7 frames)

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
  ACTION_FALL (2)      → ActionFall (constant-acceleration fall, slow→fast)
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
  1. TurboClear(NonDisplayScreen)       → Blank starting canvas
  2. SetLevelAssets()              → Load tileset and palette
  3. GenTileMask()                 → Build transparency masks
  4. WallPaperLoadBase()           → Load border template
  5. WallPaperLoadLevel()          → Copy level data into maps
  6. WallPaperWalls()              → Build wall tile variants
  7. WallpaperMakeLadders()        → Build ladder overlays
  8. WallpaperMakeShadows()        → Build shadow overlays
  9. InitGameObjects()             → Create actors from map
  10. DrawWalls()                   → Render backgrounds to NonDisplayScreen
  11. DrawLadders()                 → Overlay ladders
  12. DrawShadows()                 → Overlay shadows
  13. CopySaveToStatic()            → Copy to DisplayScreen
  14. DrawStaticActors()            → Blit actors
  15. CopyStaticToBuffers()         → Copy to display output

Per-Frame Rendering (GameRun):
  1. PlayerLogic()                  → Advance action state
  2. ClearMovedActors()             → Erase old positions
  3. Display via Copper+Denise      → Custom chip outputs pixels
```

### Undo / Rewind System

Pressing **F9** steps the game back one move at a time, up to `UNDO_BUFFER_SIZE - 1` moves (default 8).

**Implementation** (`undo.asm`):
- **`TakeSnapshot`** — called after every move settles; copies the full player and actor state into a circular `SnapshotBuffer` indexed by `SnapshotHead`
- **`UndoMove`** — decrements `SnapshotHead`, restores player and actor structs from the saved snapshot, redraws the map and all actors via `UndoDrawActors`
- **`UndoDrawActors`** — full-scan actor draw that iterates all `MAX_ACTORS` slots regardless of `ActorCount`, avoiding misses caused by `CleanActors` shrinking the live count
- **`InitUndoBuffer`** — called at level load to reset `SnapshotHead` and `SnapshotCount`; an initial snapshot is taken immediately so the player can always undo back to the level start state

**Why not a simple move-log?** Because actors cascade (fall, get pushed) after every player action. Snapshotting the complete struct state is simpler and more robust than replaying a log in reverse.

### Title Screen

The title screen (`title.asm`) runs as a standalone state before gameplay.

- **Two parallax star layers** — fast stars on bitplane 3, slow stars on bitplane 4; each layer has independent X/Y velocity and wraps at screen edges
- **Palette cycling** — `TitleCycleColours` updates `COLOR01–COLOR07` each VBlank via the copper list, creating a shifting colour wash over the logo
- **Star colours** — `COLOR08–COLOR15` locked to the fast-star colour; `COLOR16–COLOR31` to the slow-star colour so stars remain visible over logo pixels at all palette phases
- **Sine wobble** — star Y positions use a sine table for vertical undulation
- **F3 to start** — title polls F3 via `ControlsTrigger` and transitions to `LEVEL_INIT`

### Level Transition

When the last enemy is killed the game runs a tile-based wipe/reveal:

1. **`LevelWipeSetup`** — builds a shuffled ordered list of all `14×9` tile positions
2. **`LevelWipeRun`** — blits each tile to solid black (`WipeBlitBlack`, minterm `$0A`) one per tick until the screen is dark
3. **`LevelRevealSetup`** — renders the next level into `NonDisplayScreen`, computes the reversed tile order
4. **`LevelRevealRun`** — blits tiles back to white (`WipeBlitWhite`, minterm `$FA`) then restores the live level graphics

`GameStatusRun` dispatches `GAME_WIPE → GAME_REVEAL` states; player logic is suspended during the transition.

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
- **White/black wipe transitions** using minterms `$FA` and `$0A` for tile-fill effects
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
✅ Actor physics and gravity (constant acceleration — slow→fast)  
✅ Ladder climbing mechanics  
✅ Level system with multiple tilesets  
✅ Blitter-accelerated rendering  
✅ Player animation and sprite selection  
✅ Enemy AI (falling and floating) with 4-frame tile animation  
✅ Dirt destruction mechanics  
✅ Enemy death cloud puff animation (7-frame HW sprite)  
✅ Actor landing smoke puff animation (4-frame)  
✅ Level intro star animation with trail and hold  
✅ Level-complete tile wipe and reverse reveal transition  
✅ Title screen with dual parallax star layers and palette cycling  
✅ Undo / rewind mechanic (F9, up to 8 moves, circular snapshot buffer)  
✅ Two-player initialization (Millie active, Molly frozen)  

### In Progress / TODO

⏳ Enter/leave ladder animations  
⏳ Kick animations  
⏳ Game presentation polish  
⏳ Fix missing player start positions in some level data files  

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

**Current Build Date**: April 22, 2026  
**Last Working Feature**: Undo/rewind system (F9) with circular snapshot buffer; title screen dual parallax stars and palette cycling
