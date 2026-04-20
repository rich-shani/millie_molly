---
name: Project State Summary
description: Current state of Millie and Molly Amiga port - completed fixes, working features, and architectural status
type: project
---

# Millie and Molly Amiga Port - Project State (April 19, 2026)

## Overview
Amiga 500/600/1200 port of the puzzle-platformer game Millie and Molly, written in 68000 assembly with Blitter/Copper/DMA programming. Game is functionally playable with core mechanics working.

## Current Status

### Completed Features ✅
- **Core gameplay loop**: Player movement, pushing blocks, climbing ladders, falling under gravity
- **Actor system**: Dynamic pool with gravity physics, collision detection, push/fall mechanics
- **Blitter rendering**: All tile rendering using hardware Blitter with proper minterm operations ($fca for masked blitting, $7ca for background restoration)
- **Player animation**: Sub-tile pixel-by-pixel movement with frame-based animation
- **Ladder mechanics**: Proper sprite selection (climbing vs walking) based on vertical movement direction
- **Continuous movement**: Key hold detection using ControlsHold (level-triggered) rather than ControlsTrigger (edge-triggered)
- **Enemy types**: Falling enemies (BLOCK_ENEMYFALL), floating enemies (BLOCK_ENEMYFLOAT), pushable blocks (BLOCK_PUSH), breakable dirt (BLOCK_DIRT)
- **Level system**: Multiple tileset variations with theme switching; START_LEVEL = 18
- **Title screen**: Working title state with star animation
- **Two-player initialization**: Both players visible at level start - one active, one frozen
- **Level intro animation**: Large blue star travels diagonally to Molly's start tile, leaving a trail of small white stars (SPRITE_STAR_SMALL), holds for INTRO_HOLD_TICKS (60 frames), then bursts into 8 radial SPRITE_STAR_TINY stars (ACTION_BURST) before transitioning to gameplay
- **LevelInitPlayers**: Player_X/Y set from GameMap scan before LevelIntroSetup reads them, fixing intro star always targeting (0,0)
- **Enemy tile animation**: BLOCK_ENEMYFALL and BLOCK_ENEMYFLOAT cycle through 4 tile frames (A→B→C→D) every ENEMY_ANIM_TICKS VBlanks; all enemies animate in sync; falling/impact actors skipped
- **Enemy death cloud animation**: When PlayerKillEnemy kills an enemy, a 7-frame cloud puff (SPRITE_CLOUD_A..G) plays at the enemy's tile for CLOUD_TOTAL_TICKS (42 VBlanks, ~840ms PAL)

### In Progress / TODO
- **Actor fall blit mask bug**: When an actor falls and lands, the background under the tile is not shown correctly at the final position (transparent areas show stale actor graphics instead of background). Root cause identified (ClearStaticBlock uses tile-rounded Y coordinates, missing sub-pixel spillover into the landing tile) but fix not yet verified — previous attempt reverted.
- **Cloud animation z-order**: Cloud plays in bitplanes; player uses hardware sprites (always in front of bitplanes). Copper BPLCON2 trick (Option 1) was agreed upon but not yet implemented — would insert WAIT+MOVE pairs into cpTest copper list to give bitplane priority over sprites for the cloud tile's scanlines only.
- Fall animation easing refinement
- Rewind/undo mechanic
- Game presentation polish
- Handle F3 to start game in TitleRun (partially implemented - see last commit)
- Fix missing player start positions in some level data files

## Session 5 Work (April 19, 2026)

### Enemy Tile Animation (NEW FEATURE)

Enemies now visually animate through their 4 tile frames while alive on screen.

**Implementation** (`actors.asm` — `AnimateEnemies`):
- Called every VBlank from `GameRun` (after `ActionCloudActors`)
- Fires only when `TickCounter % ENEMY_ANIM_TICKS == 0` (every 12 ticks at current setting)
- Frame index: `(TickCounter / ENEMY_ANIM_TICKS) & 3` → 0..3, same for all enemies (in sync)
- For each live, non-falling, non-impact actor of type `BLOCK_ENEMYFALL` or `BLOCK_ENEMYFLOAT`:
  - Updates `Actor_SpriteOffset` to `TILE_ENEMYFALLA + frame` or `TILE_ENEMYFLOATA + frame`
  - `ClearStaticBlock` + `ActorDrawStatic` to redraw with new frame
  - `PUSHM d5/a2` / `POPM d5/a2` around `ActorDrawStatic` (PasteTile clobbers a2)

**Constants** (`const.asm`):
```
ENEMY_ANIM_TICKS = 12   ; VBlanks per animation frame (user-adjustable)
```

### Enemy Death Cloud Animation (NEW FEATURE)

When an enemy is killed, a 7-frame cloud puff animation plays at the enemy's tile.

**Implementation:**
- **`struct.asm`**: Added `Actor_CloudTick: rs.w 1` (0=idle, 1..CLOUD_TOTAL_TICKS=animating)
- **`variables.asm`**: Added `CloudActors: rs.l MAP_SIZE` and `CloudActorsCount: rs.w 1`
- **`mapstuff.asm`** (`LevelInit`): Added `clr.w CloudActorsCount(a5)` to reset pool at level load
- **`player.asm`** (`PlayerKillActor`): On killing a `BLOCK_ENEMYFALL` or `BLOCK_ENEMYFLOAT` actor, stores actor pointer in `CloudActors`, sets `Actor_CloudTick = 1`; other types (dirt, push) skipped
- **`player.asm`** (`ActionCloudActors`): Iterates `CloudActors[0..CloudActorsCount-1]` each frame:
  - Skips entries with `Actor_CloudTick == 0` (done)
  - Frame index: `(Actor_CloudTick - 1) / CLOUD_FRAME_TICKS`
  - Draws: `ClearStaticBlock` → `DrawSprite(SPRITE_CLOUD_A + frame, tile_pixel_X, tile_pixel_Y)`
  - On all 7 frames shown: final `ClearStaticBlock`, clears `Actor_CloudTick`
  - `PUSH/POP a2` around `DrawSprite` (clobbers a2)
- **`gamestatus.asm`** (`GameRun`): `bsr ActionCloudActors` called every frame before `AnimateEnemies`

**Constants** (`const.asm`):
```
SPRITE_CLOUD_A..G = 132..138   ; row 11, cols 0-6 of sprites.bin
CLOUD_FRAMES        = 7
CLOUD_FRAME_TICKS   = 6
CLOUD_TOTAL_TICKS   = 42       ; ~840ms PAL
```

**Unresolved — Cloud z-order vs player sprite:**
Hardware sprites (the player character, channels 0-3) are always composited in front of bitplane data by the Amiga display hardware. The cloud (drawn to ScreenStatic bitplanes) therefore appears behind the player. The agreed fix is the Copper BPLCON2 trick:
- Add `cpCloudPri` slot to `cpTest` copper list (two WAIT+MOVE pairs before COPPER_HALT)
- Inactive state: both WAITs at VP=$EC (bottom border row, no sprites present) → zero-height window, no artifact
- Active state: WAIT(cloud_top_scanline) + MOVE(BPLCON2,$0000) then WAIT(cloud_bottom+1) + MOVE(BPLCON2,$0024) → bitplanes in front for exactly the cloud tile's 24 scanlines
- `ActionCloudActors` patches the two WAIT VP bytes each frame
- **NOT YET IMPLEMENTED** — ready to build in the next session

## Session 4 Work (April 19, 2026)

### LevelInitPlayers — Fix intro star targeting (0,0) instead of Molly's position

**Problem**: `LevelIntroSetup` reads `Molly.Player_X/Y` to set `IntroTargX/Y`, but at that point `Player_X/Y` was still 0,0 — `InitGameObjects` (which sets them as a side effect) hadn't run yet. The intro star always travelled to the top-left corner.

**Solution**: Added `LevelInitPlayers` function to `mapstuff.asm`, called from `LevelInit` immediately after `WallPaperLoadLevel` (which populates `GameMap`):
- Scans the full 14×9 `GameMap` for `BLOCK_MILLIESTART` (7) and `BLOCK_MOLLYSTART` (8)
- Writes tile column/row directly into `Millie.Player_X/Y` and `Molly.Player_X/Y`
- Uses `PUSHALL`/`POPALL`; runs before `WallPaperWalls`, `InitGameObjects`, and `LevelIntroSetup`

`LevelInit` sequence is now:
```
WallPaperLoadBase → WallPaperLoadLevel → LevelInitPlayers → WallPaperWalls
→ WallpaperMakeLadders → WallpaperMakeShadows → InitGameObjects
```

### Level Intro Animation Refinements

**Final implementation:**
- Trail particles always use `SPRITE_STAR_SMALL`
- `IntroDone` doubles as hold-countdown: 0 = travelling, `INTRO_HOLD_TICKS`..1 = holding
- On hold expiry: burst of 8 radial `SPRITE_STAR_TINY` stars (ACTION_BURST, 8 directions × 45°) at 0.5px/frame for BURST_LIFE frames, then ACTION_IDLE

**Constants** (`const.asm`):
```
INTRO_STEP_TICKS = 6      ; VBlanks per tile step
INTRO_TRAIL_LIFE = 40     ; frames each trail particle lives
INTRO_TRAIL_MAX  = 16     ; trail pool slots
INTRO_HOLD_TICKS = 60     ; frames large star holds at target (~1.2s PAL)
BURST_STAR_COUNT = 8      ; radial burst stars
BURST_LIFE       = 50     ; VBlanks burst runs (~1.0s PAL)
SPRITE_STAR_TINY = 140    ; burst star sprite (row 11, col 8)
```

## Session 3 Work (April 19, 2026)

### Actor Landing Impact Animation

When an actor finishes a fall, a 4-frame smoke/puff animation plays over the landed tile.

**Implementation:**
- `Actor_ImpactTick` (word) in Actor struct — 0=idle, 1..IMPACT_TOTAL_TICKS=animating
- `SPRITE_SMOKE_A..D = 98..101` (row 8, cols 2–5); `IMPACT_FRAMES=4`, `IMPACT_FRAME_TICKS=4`, `IMPACT_TOTAL_TICKS=16`
- `ActionFallActors` (player.asm): on fall completion sets `Actor_ImpactTick=1`; each tick: `ClearStaticBlock` + `ActorDrawStatic` + `DrawSprite` smoke overlay

**Note**: Smoke frames at indices 98–101 provisional — verify against sprites.bin in UAE.

## Recent Fixes (Sessions 1–2)

1. **Player Start Position Bug**: Clear all player position/animation state in `LevelInit` before `InitPlayer`
2. **Two-Player Visibility**: `DrawInitialPlayers` draws both players after `DrawMap`
3. **Actor Background Restoration**: `move.w #1,Actor_HasMoved(a3)` in `PlayerMoveActor`
4. **Push Animation Clearing**: `bsr ClearStaticBlock` each frame in `ActionPlayerPush`
5. **Multi-Tile Fall Clearing**: Loop-based tile counting instead of `divu`
6. **Ladder Sprite Selection**: DirectionY non-zero = on ladder
7. **Continuous Movement**: `ControlsHold` instead of `ControlsTrigger`

## Architecture Notes

### Display Pipeline
1. **ScreenSave**: Clean background (walls, ladders, shadows) — never modified at runtime
2. **ScreenStatic**: Working display buffer; Copper list points directly at its bitplanes — all blits are immediately visible (no copy step needed each frame)
3. **Screen1/2**: Used for CopyStaticToBuffers at level load only

### Blitter Operations
- **$fca minterm** (masked tile blit): `D = (A & B) | (~A & C)` — draws actors/tiles with transparency
- **$7ca minterm** (background restore): `D = (A & D) | (~A & C)` — copies from ScreenSave

### Register Conventions
- a5 = Variables base pointer (maintained throughout)
- a6 = $dff000 (CUSTOM chip base)
- a4 = Current player structure pointer
- a3 = Current actor structure pointer
- d0-d3 = Scratch (destroyed by routines)
- d4-d7 = Preserved across calls

### Hardware Sprite vs Bitplane Priority
- Player character uses hardware sprite channels 0-3 (two attached pairs)
- Hardware sprites are always in front of bitplane data (BPLCON2=$0024 default)
- To layer bitplane content over sprites: insert WAIT+MOVE(BPLCON2) pairs in copper list
- This technique is planned for the cloud death animation (see TODO above)

## File Structure
- **main.asm**: Entry point, VBlank handler, utilities
- **player.asm**: Player logic, movement, animation, push/fall/intro/burst/cloud actions
- **actors.asm**: Actor pool management, AnimateEnemies, ClearMovedActors, player init
- **mapstuff.asm**: Level rendering, ClearStaticBlock, PasteTile, DrawInitialPlayers, LevelInitPlayers
- **gamestatus.asm**: Game state machine (TitleSetup, TitleRun, GameRun)
- **title.asm**: Title screen implementation
- **controls.asm**: Control input handling
- **keyboard.asm**: CIA-A keyboard interrupt
- **struct.asm**: Data structure definitions (Player, Actor with CloudTick)
- **const.asm**: Global constants
- **macros.asm**: Utility macros (JMPINDEX, WAITBLIT, PUSH/POP/PUSHM/POPM, etc)
- **copperlists.asm**: Copper list initialization (cpTest, cpTitle)
- **variables.asm**: BSS memory layout (includes CloudActors pool)
- **assets.asm**: Asset loading and decompression
- **spritetools.asm**: Hardware sprite utilities
- **zx0_faster.asm**: ZX0 decompression
- **tools.asm**: Utility routines (TurboClear, etc)

## Tools Created
- **tools/inspect_levels.py**: Read and display levels.bin data as human-readable text
  - `python3 inspect_levels.py 26` - Show level 26
  - `python3 inspect_levels.py all` - Show all levels
  - `python3 inspect_levels.py missing` - Show levels with missing Millie or Molly start

- **tools/edit_levels.py**: Edit level data and write back to levels.bin
  - `python3 edit_levels.py 26 view` - Display level 26
  - `python3 edit_levels.py 26 get 5 3` - Show block at (5,3)
  - `python3 edit_levels.py 26 set 0 0 H` - Set ladder at (0,0)

## Known Issues
- Some level data files may be missing BLOCK_MILLIESTART or BLOCK_MOLLYSTART markers — use `inspect_levels.py missing`
- Actor fall blit mask bug: stale graphics at sub-pixel landing position (root cause known, fix pending)
- Smoke puff impact animation untested in UAE — sprite indices 98–101 provisional
- Cloud death animation untested in UAE — sprite indices 132–138 provisional
- Cloud appears behind player sprite (hardware sprite always in front of bitplanes) — copper fix designed, not yet coded

## Next Steps if Resuming
1. **Build and test**: `vasmm68k_mot -Fhunkexe -o main.exe main.asm`
2. **Test enemy animation**: Load any level with enemies — verify tiles cycle A→B→C→D smoothly; adjust `ENEMY_ANIM_TICKS` in `const.asm` if speed is wrong
3. **Test cloud death**: Kill an enemy — verify 7-frame cloud puff plays at the tile; adjust `SPRITE_CLOUD_A` index if wrong frames appear
4. **Implement copper cloud z-order fix**: Add `cpCloudPri` to `cpTest` copper list; patch VP bytes from `ActionCloudActors`
5. **Fix actor fall blit mask bug**: Clear the sub-pixel Y spillover row before the final `DrawActor` call
6. **Fix missing player starts**: `python3 tools/inspect_levels.py missing`

## Build & Test
```bash
vasmm68k_mot -Fhunkexe -o main.exe main.asm
uae --fullscreen
```

## Key Insights for Future Work
1. **Blitter is the performance constraint**: All rendering must use Blitter, never CPU blits
2. **ScreenStatic IS the display**: Copper patches cpPlanes to point directly at ScreenStatic bitplanes — blits are immediately visible; no per-frame copy needed
3. **Sub-tile animation complexity**: 24 pixels per tile with pixel-by-pixel movement requires careful coordinate math
4. **State machine simplicity**: DirectionY non-zero directly indicates ladder presence
5. **Register management**: a5 as variables base must be maintained throughout; PUSHALL/POPALL used by ClearStaticBlock
6. **Level data integrity**: Player start positions must exist in level data; `LevelInitPlayers` now sets Player_X/Y from GameMap scan
7. **IntroDone dual use**: 0 = travelling, positive = hold countdown — avoids adding a separate variable
8. **Hardware sprite priority**: Sprites 0-3 always in front of bitplanes; use BPLCON2 copper trick to invert for specific scanline ranges
9. **Enemy animation sync**: Deriving frame index from TickCounter (global timer) keeps all enemies in sync without per-actor state

## Session Continuity
This file captures the project state as of April 19, 2026 (Session 5). Session 5 added: enemy tile cycling animation (AnimateEnemies in actors.asm), enemy death cloud puff animation (ActionCloudActors / PlayerKillActor in player.asm), and designed (but did not implement) the copper BPLCON2 z-order fix for cloud-over-player. All new features are untested in UAE. Next session should build, test both new animations, then implement the copper cloud z-order fix.
