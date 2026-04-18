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

### In Progress / TODO
- Enemy destruction animations
- Fall animation easing refinement
- Rewind/undo mechanic
- Game presentation polish
- Handle F3 to start game in TitleRun (partially implemented - see last commit)

## Key Technical Fixes Completed

### 1. Actor Background Restoration (Background Tile Corruption)
**Problem**: When actors were pushed, they left visual artifacts - the old actor position wasn't restored to background tile.

**Root Cause**: 
- PlayerMoveActor was updating Actor_X but NOT setting Actor_HasMoved flag
- ClearMovedActors function checks this flag to know which actors need background restoration

**Solution**: 
```asm
; In PlayerMoveActor (player.asm ~line 1108):
move.w      #1,Actor_HasMoved(a3)  ; Mark actor as moved so background gets restored
```

**Related Code**:
- `ClearMovedActors` in actors.asm iterates all actors with HasMoved=1, calls `ClearStaticBlock` to restore each from ScreenSave
- `ClearStaticBlock` in mapstuff.asm uses minterm $7ca to copy clean background from ScreenSave to ScreenStatic
- Must be called BEFORE DrawActor to prevent animation trails

### 2. Actor Push Animation - Continuous Background Clearing
**Problem**: During push animation (24-frame sequence), old actor positions left trails.

**Solution**: Added background restoration each frame in ActionPlayerPush:
```asm
; In ActionPlayerPush (player.asm ~line 206):
bsr         ClearStaticBlock        ; Restore background before drawing
bsr         DrawActor               ; Draw actor at new animation frame position
```

This ensures background is refreshed before each frame of the push animation, preventing visual trails.

### 3. Multi-Tile Fall Animation - Background Clearing
**Problem**: When actors fall multiple tiles, only the starting tile's background was being restored. Used divu which failed because high word of d2 contained garbage.

**Solution**: Loop-based tile counting instead of division:
```asm
; Count how many full tiles fallen (YDec accumulates sub-tile pixels)
move.w      Actor_YDec(a3),d2
moveq       #0,d4                   ; d4 = tile count
.tilecount
cmp.w       #24,d2                  ; One tile = 24 pixels
bcs         .tilesdone
addq.w      #1,d4
sub.w       #24,d2
bra         .tilecount
.tilesdone
add.w       d4,d1                   ; d1 = PrevY + tiles fallen (new starting tile)
```

Then loop to clear all affected tiles. Why divu failed: `move.w` loads only low 16 bits; high word of d2 contains garbage, causing divu to produce incorrect results.

### 4. Ladder Sprite Selection Logic
**Problem**: Sprite flipped between walking and climbing on tile transitions, breaking animation continuity.

**Root Cause**: Complex multi-condition logic checking different aspects of movement caused sprite to flip as player crossed tile boundaries.

**User's Elegant Solution**: 
Key insight: **Vertical movement (DirectionY non-zero) ONLY occurs on ladders**. Use this as the primary indicator:

```asm
; In PlayerShowWalkAnim (player.asm ~line 906):
; If moving vertically, we're on a ladder - show climbing sprite
move.b      Player_DirectionY(a4),d0
bne         .show_climbing_sprite   ; Non-zero = moving vertically = on ladder
```

Then check edge cases for bottom-of-ladder transitions:
- At bottom of tile (YDec >= 20): show climbing sprite only if DirectionY non-zero (user pressing UP key)
- Animation cycles: 0-3 for ladder, 0-7 for walking (controlled by Player_OnLadder flag)

This approach avoids flipping by recognizing that tile transitions don't change the fundamental fact that vertical movement = ladder presence.

### 5. Continuous Movement Input
**Problem**: Player moved one tile then stopped; had to release and repress key to move again.

**Solution**: Changed PlayerIdle to use `ControlsHold` instead of `ControlsTrigger`:
- `ControlsTrigger`: Edge-triggered (fires once on key press)
- `ControlsHold`: Level-triggered (fires every frame key is held)

This allows smooth continuous movement while key is held down.

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
- **actors.asm**: Actor pool management, ClearMovedActors function
- **mapstuff.asm**: Level rendering, ClearStaticBlock, PasteTile
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

## Recent Git History
- 3add273: Handle F3 to start game in TitleRun
- 02e7af0: Add comprehensive comments to main and uigfx
- a8e3349: Move asm resources; update VSCode tasks
- 807df4e: Refactor and document actors, assets, constants
- de7ff22: Initial Commit

## Documentation
- Comprehensive README.md created with full technical architecture, gameplay features, blitter details, and build instructions

## Next Steps if Resuming
1. **Test title screen F3 start**: Last commit attempted to handle F3 key to transition from title to gameplay
2. **Polish remaining animations**: Enemy destruction, fall easing, enter/leave ladder transitions
3. **Performance profiling**: Profile on real hardware or UAE to identify optimization opportunities
4. **Testing coverage**: Test all edge cases in ladder transitions, enemy collisions, level completion

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

## Session Continuity
This file captures the project state as of April 18, 2026. All major gameplay mechanics are working. The code is well-commented and structured. Next session should focus on testing the F3 title-to-gameplay transition and any remaining polish tasks.
