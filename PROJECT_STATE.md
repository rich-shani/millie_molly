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
- **Level system**: Multiple tileset variations with theme switching
- **Title screen**: Working title state with star animation
- **Two-player initialization**: Both players visible at level start - one active, one frozen
- **Level intro animation**: Large blue star travels diagonally to Molly's start tile, leaving a trail of small white stars, then holds at the target for INTRO_HOLD_TICKS before disappearing and transitioning to gameplay
- **LevelInitPlayers**: Player_X/Y set from GameMap scan before LevelIntroSetup reads them, fixing intro star always targeting (0,0)

### In Progress / TODO
- **Actor fall blit mask bug**: When an actor falls and lands, the background under the tile is not shown correctly at the final position (transparent areas show stale actor graphics instead of background). Root cause identified (ClearStaticBlock uses tile-rounded Y coordinates, missing sub-pixel spillover into the landing tile) but fix not yet verified — previous attempt reverted.
- Enemy destruction animations
- Fall animation easing refinement
- Rewind/undo mechanic
- Game presentation polish
- Handle F3 to start game in TitleRun (partially implemented - see last commit)
- Fix missing player start positions in some level data files

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

The intro star animation (`ActionIntro` in `player.asm`) was simplified and improved across several iterations:

**Final implementation:**
- Trail particles always use `SPRITE_STAR_SMALL` (removed `SPRITE_STAR_TINY` and all bit-test sprite selection logic)
- Trail aging loop runs unconditionally every frame — small stars fade on their natural schedule both during travel and during the hold period
- `IntroDone` doubles as a hold-countdown: 0 = travelling, `INTRO_HOLD_TICKS`..1 = holding at target
- On arrival at target: `IntroDone` set to `INTRO_HOLD_TICKS` (60 frames, ~1.2s PAL)
- During hold: large star redrawn each frame after the aging loop (trail clearing cannot erase it); no new scatter stars spawned
- On hold expiry: `ClearStaticBlock` erases the large star, `IntroClearAllTrail` clears any surviving trail particles, `DrawStaticActors` repairs the screen, then `ACTION_IDLE`

**Removed:**
- `SPRITE_STAR_TINY` constant (from `const.asm`) and all references
- `IntroTrailSubY` gravity/fall drift experiment (reverted; `variables.asm`, `player.asm`, `mapstuff.asm` cleaned up)
- Two-pass (clear-all / draw-all) trail aging experiment (reverted back to single-pass)

**Constants** (`const.asm`):
```
INTRO_STEP_TICKS = 6      ; VBlanks per tile step
INTRO_TRAIL_LIFE = 40     ; frames each trail particle lives
INTRO_TRAIL_MAX  = 16     ; trail pool slots
INTRO_HOLD_TICKS = 60     ; frames large star holds at target (~1.2s PAL)
```

## Session 3 Work (April 19, 2026)

### Actor Landing Impact Animation (NEW FEATURE)

When an actor finishes a fall, a 4-frame smoke/puff animation plays over the landed tile.

**Implementation:**
- Added `Actor_ImpactTick` (word) to Actor struct in `struct.asm` — 0 = idle, 1..16 = animation in progress
- Added smoke sprite constants to `const.asm`:
  - `SPRITE_SMOKE_A..D = 98..101` (row 8, cols 2–5 of the 12×12 sprites.bin sprite sheet)
  - `IMPACT_FRAMES = 4`, `IMPACT_FRAME_TICKS = 4`, `IMPACT_TOTAL_TICKS = 16` (~320ms at 50Hz)
- Extended `ActionFallActors` in `player.asm`:
  - On fall completion: sets `Actor_ImpactTick = 1`
  - `.check_impact` section: iterates FallenActors list; each tick does `ClearStaticBlock` + `ActorDrawStatic` + `DrawSprite` (smoke overlay)
  - `d6` counter includes impact-active actors so `ACTION_FALL` state stays active until all smoke animations complete
  - `a2` saved/restored with `PUSH`/`POP` around draw calls (both `PasteTile` and `DrawSprite` overwrite it)

**Sprite sheet note**: Smoke frames at indices 98–101 (row 8, cols 2–5 of the 12×12 grid). Untested in UAE — indices provisional.

### Actor Fall Blit Mask Investigation

Root cause identified but not yet fixed:
- `ClearStaticBlock` uses tile-rounded Y, missing sub-pixel spillover into the next tile
- `DrawActor` blits at sub-pixel position, spilling into the tile below
- Spill rows accumulate stale graphics; transparent areas of the final blit show old content

## Recent Fixes (Session 2)

### Player Start Position Bug (Levels 26-29, etc.)
Player position fields (X, Y, XDec, YDec) were not cleared on level start; old data persisted.
**Solution**: Clear all player position and animation state in `LevelInit` before `InitPlayer` runs.

### Two-Player Visibility at Level Start
Only one player was visible at level start.
**Solution**: `InitPlayer` sets Status=1 (active) or Status=2 (frozen) by init order; `DrawInitialPlayers` (mapstuff.asm) draws both players after `DrawMap`; called before `CopyStaticToBuffers`.

## Key Technical Fixes (Session 1)

1. **Actor Background Restoration**: Added `move.w #1,Actor_HasMoved(a3)` in `PlayerMoveActor`
2. **Push Animation Clearing**: `bsr ClearStaticBlock` each frame in `ActionPlayerPush`
3. **Multi-Tile Fall Clearing**: Loop-based tile counting instead of `divu`
4. **Ladder Sprite Selection**: DirectionY non-zero = on ladder; use as primary indicator
5. **Continuous Movement**: `ControlsHold` (level-triggered) instead of `ControlsTrigger` (edge-triggered)

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

## File Structure
- **main.asm**: Entry point, VBlank handler, utilities
- **player.asm**: Player logic, movement, animation, push/fall/intro actions
- **actors.asm**: Actor pool management, ClearMovedActors, player initialization
- **mapstuff.asm**: Level rendering, ClearStaticBlock, PasteTile, DrawInitialPlayers, LevelInitPlayers
- **gamestatus.asm**: Game state machine (TitleSetup, TitleRun, GameRun)
- **title.asm**: Title screen implementation
- **controls.asm**: Control input handling
- **keyboard.asm**: CIA-A keyboard interrupt
- **struct.asm**: Data structure definitions
- **const.asm**: Global constants
- **macros.asm**: Utility macros (JMPINDEX, WAITBLIT, etc)
- **copperlists.asm**: Copper list initialization
- **variables.asm**: BSS memory layout
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
- Some level data files may be missing BLOCK_MILLIESTART or BLOCK_MOLLYSTART markers
- Use `inspect_levels.py missing` to identify levels needing data fixes
- Actor fall blit mask bug: stale graphics at sub-pixel landing position (root cause known, fix pending)
- Smoke puff impact animation untested in UAE — sprite indices 98–101 provisional

## Next Steps if Resuming
1. **Build and test**: `vasmm68k_mot -Fhunkexe -o main.exe main.asm`
2. **Test intro animation**: Load any level — verify large blue star travels to Molly's tile, trail stars fade, star holds for ~1.2s then disappears cleanly
3. **Test landing impact animation**: Push a block so it falls — verify smoke puff plays. Adjust `SPRITE_SMOKE_A..D` in `const.asm` if wrong frames appear
4. **Fix actor fall blit mask bug**: Clear the sub-pixel Y spillover row before the final `DrawActor` call
5. **Fix missing player starts**: `python3 tools/inspect_levels.py missing`
6. **Polish remaining animations**: Enemy destruction, fall easing, enter/leave ladder transitions

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
6. **Level data integrity**: Player start positions must exist in level data; `LevelInitPlayers` now sets Player_X/Y from GameMap scan before any intro logic reads them
7. **IntroDone dual use**: 0 = travelling, positive = hold countdown — avoids adding a separate variable

## Session Continuity
This file captures the project state as of April 19, 2026 (Session 4). Session 4 fixed the intro star targeting bug (LevelInitPlayers), simplified the trail star animation (SPRITE_STAR_SMALL only, single-pass aging), and added the large star hold-at-target behaviour with clean disappearance on expiry. All intro changes are untested in UAE. Next session should build, test the intro end-to-end, and then tackle the actor fall blit mask bug.
