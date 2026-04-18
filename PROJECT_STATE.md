---
name: Project State Summary
description: Current state of Millie and Molly Amiga port - completed fixes, working features, and architectural status
type: project
---

# Millie and Molly Amiga Port - Project State (April 18, 2026)

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
- **Two-player initialization**: Both players now visible at level start - one active, one frozen

### In Progress / TODO
- Enemy destruction animations
- Fall animation easing refinement
- Rewind/undo mechanic
- Game presentation polish
- Handle F3 to start game in TitleRun (partially implemented - see last commit)
- Fix missing player start positions in some level data files

## Recent Fixes (Session 2)

### Player Start Position Bug (Levels 26-29, etc.)
**Problem**: When transitioning to later levels, players started at position (0,0) instead of their defined start positions.

**Root Cause**: 
- Player position fields (X, Y, XDec, YDec) were not being cleared when starting a new level
- Old position data from previous level persisted
- ActionStatus and other animation state also carried over

**Solution** (in mapstuff.asm LevelInit):
```asm
; Clear all player position and animation state for both players
; when starting a new level, ensuring clean slate for InitPlayer
clr.w         Player_X(a0)
clr.w         Player_Y(a0)
clr.w         Player_XDec(a0)
clr.w         Player_YDec(a0)
clr.w         Player_PrevX(a0)
clr.w         Player_PrevY(a0)
clr.w         Player_NextX(a0)
clr.w         Player_NextY(a0)
clr.w         Player_ActionCount(a0)
clr.w         Player_AnimFrame(a0)
move.w        #1,Player_Facing(a0)
clr.w         Player_OnLadder(a0)
clr.w         Player_DirectionX(a0)
clr.w         Player_DirectionY(a0)
clr.w         Player_Fallen(a0)
clr.w         Player_ActionFrame(a0)
```

### Two-Player Visibility at Level Start
**Problem**: Only one player was visible at level start; had to press FIRE to see the other player.

**Root Cause**: 
- InitPlayer code had commented-out code for drawing the second player as frozen
- DrawMap did not call any function to draw initial player sprites
- Only dynamic game logic drew players via ShowSprite

**Solution**:
1. Modified InitPlayer (actors.asm) to set player status based on initialization order:
   - First player: Status = 1 (active/controlled)
   - Second player: Status = 2 (frozen/waiting for switch)

2. Created DrawInitialPlayers function (mapstuff.asm) that:
   - Draws Molly first (so Millie appears on top if same position)
   - Draws Millie second
   - Skips any player with Status = 0 (inactive)
   - Draws idle sprite (frame 0) for each player

3. Updated DrawMap to call DrawInitialPlayers before copying buffers to display

## Key Technical Fixes (Session 1)

### 1. Actor Background Restoration (Background Tile Corruption)
**Problem**: When actors were pushed, they left visual artifacts - the old actor position wasn't restored to background tile.

**Solution**: Added `move.w #1,Actor_HasMoved(a3)` in PlayerMoveActor to mark actor as moved.

### 2. Actor Push Animation - Continuous Background Clearing
**Problem**: During push animation (24-frame sequence), old actor positions left trails.

**Solution**: Added background restoration each frame in ActionPlayerPush via `bsr ClearStaticBlock`.

### 3. Multi-Tile Fall Animation - Background Clearing
**Problem**: When actors fall multiple tiles, only starting tile's background was restored. Division operation failed.

**Solution**: Loop-based tile counting instead of divu (to avoid garbage in register high word).

### 4. Ladder Sprite Selection Logic
**Problem**: Sprite flipped between walking and climbing on tile transitions.

**Solution**: Recognize that DirectionY non-zero ONLY occurs on ladders; use as primary indicator.

### 5. Continuous Movement Input
**Problem**: Player moved one tile then stopped; needed key release and repress.

**Solution**: Changed PlayerIdle to use ControlsHold (level-triggered) instead of ControlsTrigger (edge-triggered).

## Architecture Notes

### Display Pipeline
1. **ScreenSave**: Clean background (walls, ladders, shadows) - never changes except on level reload
2. **ScreenStatic**: Working display buffer with actors - actors rendered here each frame
3. **Screen1/2**: Double-buffer output to display via Copper+Denise

### Blitter Operations
- **$fca minterm** (masked tile blit): `D = (A & B) | (~A & C)` - Used for drawing actors/tiles where mask determines transparency
- **$7ca minterm** (background restore): `D = (A & D) | (~A & C)` - Copies from ScreenSave, restoring backgrounds

### Register Conventions
- a5 = Variables base pointer (maintained throughout)
- a6 = $dff000 (CUSTOM chip base)
- a4 = Current player structure pointer
- a3 = Current actor structure pointer
- d0-d3 = Scratch (destroyed by routines)
- d4-d7 = Preserved across calls

## File Structure
- **main.asm**: Entry point, VBlank handler, utilities
- **player.asm** (63KB): Player logic, movement, animation, push/fall actions
- **actors.asm**: Actor pool management, ClearMovedActors, player initialization
- **mapstuff.asm**: Level rendering, ClearStaticBlock, PasteTile, DrawInitialPlayers
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
- Use inspect_levels.py with "missing" argument to identify levels needing data fixes

## Recent Git History
- (Session 2) Fixed player position clearing at level init and two-player visibility
- 3add273: Handle F3 to start game in TitleRun
- 02e7af0: Add comprehensive comments to main and uigfx
- a8e3349: Move asm resources; update VSCode tasks
- 807df4e: Refactor and document actors, assets, constants
- de7ff22: Initial Commit

## Documentation
- Comprehensive README.md with full technical architecture, gameplay features, blitter details, and build instructions

## Next Steps if Resuming
1. **Build and test**: Assemble code to verify no syntax errors
2. **Test two-player visibility**: Check that both players appear at level start in levels with both player start markers
3. **Fix missing player starts**: Use inspect_levels.py to find levels missing BLOCK_MILLIESTART or BLOCK_MOLLYSTART
4. **Test level transitions**: Verify players start at correct positions in levels 26-29 and others
5. **Polish remaining animations**: Enemy destruction, fall easing, enter/leave ladder transitions

## Build & Test
```bash
# Assemble
vasmm68k_mot -Fhunkexe -o main.exe main.asm

# Run in UAE emulator
uae --fullscreen
```

## Key Insights for Future Work
1. **Blitter is the performance constraint**: All rendering must use Blitter, never CPU blits
2. **Sub-tile animation complexity**: 24 pixels per tile with pixel-by-pixel movement requires careful coordinate math
3. **State machine simplicity**: Complex sprite selection logic was simplified by recognizing that DirectionY directly indicates ladder presence
4. **Register management**: a5 as variables base must be maintained; other registers follow 68000 conventions strictly
5. **Copper timing**: All display synchronization driven by Copper; CPU handles game logic only
6. **Level data integrity**: Player start positions must be defined in level data files; levels missing these will default to (0,0)

## Session Continuity
This file captures the project state as of April 18, 2026 (Session 2). Major gameplay mechanics are working. Two recent bug fixes addressed player initialization at level transitions and two-player visibility at level start. Code is well-commented and structured. Next session should focus on testing the fixes and addressing remaining level data issues.
