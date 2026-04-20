# Screen Buffers and Rendering — Millie and Molly Amiga Port

## Overview

The game uses four screen-sized buffers in Chip RAM, plus hardware sprites managed through the copper list. The key distinction is between **what the player sees** (DisplayScreen, displayed directly by the copper) and **the clean background reference** (NonDisplayScreen, never displayed directly).

---

## Screen Buffer Definitions

All four buffers are in Chip RAM (`section mem_chip, bss_c`) so the Blitter and Agnus DMA can access them. Each is `SCREEN_SIZE = 45,360 bytes`.

```
AllChip:
  NullSprite      - two zero longwords (terminated empty hardware sprite)
  ButtonMaskTemp  - working area for UI button compositing
  LevelCountTemp  - working area for level counter compositing
  TileSet         - decompressed tile bitplane data (13,920 bytes)
  TileMask        - blitter mask derived from TileSet (13,920 bytes)
  SpriteMask      - blitter mask for actor sprites (69,120 bytes)
  Screen1         - 45,360 bytes  (legacy double-buffer slot, not displayed)
  Screen2         - 45,360 bytes  (legacy double-buffer slot, not displayed)
  DisplayScreen    - 45,360 bytes  THE LIVE DISPLAY BUFFER
  NonDisplayScreen      - 45,360 bytes  clean background reference (never shown)
  ScreenMemEnd    - 200-byte guard region (sentinel = -1)
```

### DisplayScreen
The buffer that is **actually displayed on screen**. The copper list bitplane pointers (`BPL1PTH/L` through `BPL5PTH/L`) are permanently loaded with the physical address of DisplayScreen at startup and never changed at runtime. Every pixel the player sees comes from DisplayScreen.

Everything that draws to the screen — wall tiles, actor tiles, player sprites, the intro star — writes into DisplayScreen.

### NonDisplayScreen
A **clean copy of the background** with no actors on it. It contains walls, ladders, shadows, and the UI strip. Actors are never blitted here.

NonDisplayScreen is used as the source when erasing: to remove an actor from DisplayScreen, the corresponding tile area is copied back from NonDisplayScreen (restoring the clean background underneath). This is faster and more correct than trying to redraw from scratch.

### Screen1 / Screen2
Legacy double-buffer storage. The game was originally designed for double-buffering but currently runs in single-buffer mode: both `ScreenPtrs` entries point to `Screen1`, and the copper always points at `DisplayScreen`. Screen1 and Screen2 receive a copy of DisplayScreen at level load time via `CopyStaticToBuffers`, but are not otherwise used during gameplay.

---

## Memory Layout: Interleaved Bitplanes

The screen is **336 × 216 pixels, 5 bitplanes** (32 colours). The bitplanes are interleaved row-by-row in the Amiga's standard planar format:

```
Row 0, Plane 0:  42 bytes
Row 0, Plane 1:  42 bytes
Row 0, Plane 2:  42 bytes
Row 0, Plane 3:  42 bytes
Row 0, Plane 4:  42 bytes
Row 1, Plane 0:  42 bytes
...
```

Key metrics:
| Constant          | Value  | Meaning                                         |
|-------------------|--------|-------------------------------------------------|
| `SCREEN_WIDTH`    | 336 px | 14 tiles × 24 pixels                           |
| `SCREEN_HEIGHT`   | 216 px | 9 tiles × 24 pixels                            |
| `SCREEN_DEPTH`    | 5      | bitplanes                                       |
| `SCREEN_WIDTH_BYTE` | 42   | bytes per row per plane (336 / 8)              |
| `SCREEN_STRIDE`   | 210    | bytes from one row start to the next (5 × 42)  |
| `SCREEN_MOD`      | 168    | blitter modulo: (SCREEN_DEPTH−1) × 42          |
| `SCREEN_SIZE`     | 45,360 | total bytes (42 × 216 × 5)                     |

`SCREEN_STRIDE` is how the code steps vertically through the buffer: to move down one row of pixels, add 210 to any plane-0 address.

The blitter `BLTCMOD` / `BLTDMOD` are set to `TILE_BLT_MOD` (= `SCREEN_MOD` = 168) so after each 32-pixel-wide blitter row the pointer skips over the remaining four planes' worth of data to land on the next row of the same plane.

---

## How the Copper Displays DisplayScreen

At startup `GameCopperInit` patches the static copper list (`cpTest`) by writing the physical addresses of all five bitplanes of DisplayScreen into the `cpPlanes` section:

```asm
move.l  #DisplayScreen, d0
; loop SCREEN_DEPTH times:
;   write high word to BPLxPTH, low word to BPLxPTL
;   advance d0 by SCREEN_WIDTH_BYTE (= 42) for the next plane
```

Because the bitplanes are interleaved, each plane starts 42 bytes after the previous one within the same buffer. The copper list is never updated during gameplay — Agnus always fetches from DisplayScreen. Any write to DisplayScreen is visible on the very next frame.

Hardware sprites are managed separately (see below).

---

## Tile Format

Each tile is **24 pixels wide × 24 pixels tall**, stored as **32 pixels wide** (padded to a full longword per row per plane):

```
Tile size = (32/8) bytes/row × 5 planes × 24 rows = 480 bytes per tile
```

All tiles in TileSet are packed consecutively: tile N starts at `TileSet + N × 480`.

TileMask is a parallel array at the same layout: `TileMask + N × 480` is the blitter mask for tile N. Generated by `GenTileMask`.

---

## Blitter Operations

All rendering uses the Amiga Blitter. The main minterms:

| Minterm | Code  | Operation                    | Used by                              |
|---------|-------|------------------------------|--------------------------------------|
| `$FCA`  | A&B\|~A&C | mask-select: A=1→tile(B), A=0→background(C) | PasteTile, DrawSprite, ActorDrawStatic |
| `$7CA`  | ~A&B&C \| A&B \| ~A&~B&C | equivalent: copy B→D where mask=1, keep C→D where mask=0 | RestoreBackgroundTile, ClearPlayer |
| `$0A`   | ~A&C  | zero pixels in tile area, preserve guard bits | WipeBlitBlack                       |
| `$D0C`  | A\|B  | OR shadow pixels onto destination | ShadowTile                       |

Blitter channels:
- **A** = mask (TileMask, SpriteMask, or constant `$FFFF` from `BLTADAT`)
- **B** = source graphic (TileSet data, Sprites data, or NonDisplayScreen)
- **C** = destination background (DisplayScreen or NonDisplayScreen, for guard-bit preservation)
- **D** = output (DisplayScreen or NonDisplayScreen)

For a 24-pixel-wide tile blit into a buffer that is a multiple of 16 bits wide, tiles at pixel columns 0, 48, 96 … are word-aligned (shift = 0); tiles at pixel columns 24, 72, 120 … have a 1-byte (8-bit) shift. The shift is packed into bits 15:12 of BLTCON0 and the first/last word masks (`BLTAFWM` / `BLTALWM`) are set to `$FFFF/$FF00` (shift 0) or `$00FF/$FFFF` (shift 8) accordingly.

---

## Building the Background: NonDisplayScreen

`NonDisplayScreen` is built fresh at the start of every level by a fixed pipeline. Nothing outside this pipeline writes to NonDisplayScreen.

### DrawMap pipeline (called at level load)

```
LevelInit
  └─ TurboClear(NonDisplayScreen)        zero the entire buffer
  └─ SetLevelAssets                decompress TileSet, load palette
  └─ GenTileMask                   build TileMask from TileSet
  └─ WallPaperLoadBase/Level       build GameMap, WallpaperWork
  └─ WallpaperMakeLadders          build WallpaperLadders overlay
  └─ WallpaperMakeShadows          build WallpaperShadows overlay
  └─ InitGameObjects               create actor structs

DrawWalls       → NonDisplayScreen   (DrawTile: opaque blit, minterm not documented inline but tiles fill background)
DrawButtons     → NonDisplayScreen   (DrawLevelCounter + DrawButton: masked blit minterm $FCA)
DrawLadders     → NonDisplayScreen   (PasteTile: masked blit minterm $FCA, transparent)
DrawShadows     → NonDisplayScreen   (ShadowTile: OR-blit minterm $D0C)

CopySaveToStatic               CPU longword copy: NonDisplayScreen → DisplayScreen
DrawStaticActors               PasteTile each actor tile → DisplayScreen
DrawInitialPlayers             blit frozen-player sprites → DisplayScreen
LevelIntroSetup                hides hardware sprites; sets ActionStatus = ACTION_INTRO
CopyStaticToBuffers            CPU longword copy: DisplayScreen → Screen1 AND Screen2
```

After this pipeline:
- **NonDisplayScreen** = walls + UI buttons + ladders + shadows (no actors, no players)
- **DisplayScreen** = NonDisplayScreen content + all actor tiles + frozen player sprites
- **Screen1/Screen2** = copy of DisplayScreen (for the legacy double-buffer path, currently unused)

---

## Drawing Actors onto DisplayScreen

### ActorDrawStatic / PasteTile

To draw an actor tile at its current tile position:

```asm
ActorDrawStatic:
    d0 = Actor_X * 24   (pixel X)
    d1 = Actor_Y * 24   (pixel Y)
    d2 = Actor_SpriteOffset (index into TileSet / Sprites)
    a1 = DisplayScreen
    bsr PasteTile
```

`PasteTile` does a blitter blit using minterm `$FCA` (A&B | ~A&C):
- A = TileMask[d2]   — the tile's transparency mask
- B = TileSet[d2]    — the tile's pixel data
- C = D = DisplayScreen at the computed pixel address

Where mask = 1: actor pixel appears. Where mask = 0: existing DisplayScreen pixel is preserved. This correctly composites the actor over whatever background is already in DisplayScreen.

### DrawSprite (player cloud animations, frozen player)

Same minterm `$FCA`, but reads from `Sprites` (the actor sprite sheet) and `SpriteMask` rather than `TileSet`/`TileMask`. Always targets DisplayScreen.

---

## Erasing Actors from DisplayScreen

When an actor moves or dies, its previous tile position must be erased from DisplayScreen. Rather than redrawing the background from scratch, the clean background is **copied from NonDisplayScreen**.

### RestoreBackgroundTile (tile-aligned erase)

```asm
; d0 = tile X, d1 = tile Y
RestoreBackgroundTile:
    a0 = NonDisplayScreen  (source: clean background)
    a1 = DisplayScreen (destination: live display)
    ; Blitter: minterm $7CA, A = constant $FFFF from BLTADAT
    ; gated by BLTAFWM/BLTALWM to restrict to tile width
    ; B = NonDisplayScreen, C = D = DisplayScreen
    ; Result: within the masked tile area, D = B (NonDisplayScreen overwrites DisplayScreen)
```

Used by `ClearMovedActors`, `PlayerKillActor`, `LevelRevealSetup` (via `LevelTransitionRun`), and the intro star trail.

### ClearPlayer / ClearActor

Identical blitter logic to `RestoreBackgroundTile` but take pixel coordinates rather than tile coordinates. `ClearActor` additionally uses the pre-computed `ClearMasks` table to handle arbitrary sub-tile X offsets (actors can be mid-tile during movement animations).

---

## Hardware Sprites (Player Characters)

The player characters (Millie and Molly) are displayed as **Amiga hardware sprites**, not as blitted tiles. Hardware sprites are overlaid by the sprite DMA independently of the bitplane display — they appear on top of DisplayScreen without any blitter writes.

### SpritePtrs and the copper list

`SpritePtrs(a5)` holds eight longword addresses — one per hardware sprite channel (SPR0..SPR7). Each frame, `ShowSprite` writes the chosen sprite frame address into the appropriate slots, and the copper list (`cpSprites`) is patched with the physical addresses so Agnus fetches the correct sprite data.

Sprites 0/1 form the left half of the displayed player; sprites 2/3 form the right half. Sprites 4–7 are unused.

### Hiding sprites

To hide the player during the level wipe, `LevelWipeSetup` sets all four `SpritePtrs` entries to `NullSprite` (two zero longwords in Chip RAM) and patches `cpSprites` immediately. `NullSprite`'s terminator pattern causes Agnus to output transparent pixels for that channel.

---

## Level Transition: Wipe and Reveal

The level-end transition demonstrates how the two buffers work together:

### LEVEL_WIPE phase (GameStatus = 3)

`LevelTransitionRun` calls `WipeBlitBlack` for `WIPE_SPEED` tiles per frame. `WipeBlitBlack` uses minterm `$0A` (~A&C) with A = constant `$FFFF` gated by the tile-width masks:
- Within the tile area: A=`$FFFF`, so ~A=0, result = 0 (black pixels written to DisplayScreen)
- Outside the tile area: A=0, so ~A=`$FFFF`, result = C (DisplayScreen pixels preserved)

Only DisplayScreen is modified; NonDisplayScreen is untouched.

### LEVEL_HOLD phase (GameStatus = 4)

Counts down `WIPE_HOLD_TICKS` frames (all-black screen). When zero, calls `LevelRevealSetup`.

### LevelRevealSetup

Builds the new level into NonDisplayScreen only (runs `LevelInit → DrawWalls → DrawButtons → DrawLadders → DrawShadows → LevelIntroSetup`). Skips `CopySaveToStatic`, `DrawStaticActors`, and `CopyStaticToBuffers` — DisplayScreen stays black. Reverses `WipeTileX/Y` for the opposite traversal order, sets GameStatus = `LEVEL_REVEAL`.

### LEVEL_REVEAL phase (GameStatus = 5)

`LevelTransitionRun` calls `RestoreBackgroundTile` for `WIPE_SPEED` tiles per frame. Each call copies that tile area from NonDisplayScreen into DisplayScreen, progressively revealing the new level background from black. When all 126 tiles are restored, `DrawStaticActors` blits the actor tiles on top and `GameStatus` returns to `LEVEL_RUN` (2).

---

## Summary: What Writes Where

| Operation                  | Writes to    | Reads from            |
|----------------------------|--------------|-----------------------|
| DrawWalls / DrawTile       | NonDisplayScreen   | TileSet               |
| DrawLadders / PasteTile    | NonDisplayScreen   | TileSet, TileMask     |
| DrawShadows / ShadowTile   | NonDisplayScreen   | Shadows data          |
| DrawButtons                | NonDisplayScreen   | Button graphics       |
| CopySaveToStatic           | DisplayScreen | NonDisplayScreen            |
| DrawStaticActors / PasteTile | DisplayScreen | TileSet, TileMask   |
| DrawSprite (cloud/frozen)  | DisplayScreen | Sprites, SpriteMask   |
| RestoreBackgroundTile           | DisplayScreen | NonDisplayScreen            |
| ClearPlayer / ClearActor   | DisplayScreen | NonDisplayScreen            |
| WipeBlitBlack              | DisplayScreen | DisplayScreen (guard bits) |
| ShowSprite (hardware sprite) | cpSprites copper list | SpritePtrs |
| CopyStaticToBuffers        | Screen1, Screen2 | DisplayScreen       |
| Copper / Agnus display     | (video output) | DisplayScreen        |

**The invariant**: NonDisplayScreen always holds a clean background. DisplayScreen is the composited frame that is displayed. Erasing anything from DisplayScreen is done by copying the corresponding area from NonDisplayScreen.
