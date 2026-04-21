# Millie and Molly - Changes Since Initial Commit

**Refactor & documentation pass** — Actors, assets, and constants reorganised and fully commented. Assembly resources moved into `include/resources/`; VSCode tasks updated.

**Comprehensive comments** — `main.asm` and `uigfx.asm` documented throughout.

**F3 starts game from title** — `TitleRun` handles the F3 key to transition directly into gameplay.

**Player animation & background blitting improvements** — Smoother sub-tile sprite selection; background restoration blits corrected.

**Level init player state clear** — All player position/animation fields reset at level load to prevent stale state carrying between levels. Added `inspect_levels.py` and `edit_levels.py` tools for reading and editing `levels.bin`.

**Actor landing smoke animation** — When an actor finishes a fall, a 4-frame smoke/puff sprite plays over the landed tile (`Actor_ImpactTick`).

**Level-start star intro animation** — A large blue star travels diagonally to Molly's start tile leaving a trail of small white stars, holds, then bursts into 8 radial tiny stars before gameplay begins.

**Enemy tile animation, death cloud & burst effects** — Enemies cycle through 4 tile frames while alive. Killing an enemy plays a 7-frame cloud puff. Intro star hold ends with an 8-direction radial star burst. Fixed intro star always targeting (0,0) by scanning `GameMap` for player starts before `LevelIntroSetup` runs.

**End-of-level wipe & reveal transition** — Full screen wipe (tiles blitted black one by one in a shuffled order) followed by a reveal (tiles restored from `NonDisplayScreen` in reverse order). Level transition state machine: `LEVEL_INIT → LEVEL_WIPE → LEVEL_HOLD → LEVEL_REVEAL → GAME_RUN`.

**State machine & naming cleanup** — `LEVEL_RUN` renamed `GAME_RUN`; transition states refactored into discrete handlers; `LevelSetup` moved; `WipeFillTable` added for pattern dispatch.

**Screen buffer rename** — Buffers renamed `DisplayScreen` / `NonDisplayScreen` for clarity.

**`WipeBlitWhite` routine** — New blitter routine to one-fill a tile white (minterm `$FA`), paired with the existing `WipeBlitBlack`.

**Reveal setup** — `LevelRevealSetup` builds the next level into `NonDisplayScreen` and reverses the wipe tile order for the reveal phase.

**Game init flow refactor** — Level drawing deferred; init sequence tightened.

**Accelerating fall physics** — Player and actor falls replaced from ease-out quadratic table lookup to constant-acceleration (velocity accumulates each frame). Actor fall overshoot fixed: `Actor_YDec` clamped to `Actor_FallY` before `DrawActor` to prevent sprite bleeding into the tile below.

**Ladder top bug fix** — Player no longer continues climbing after leaving a ladder tile when Left/Right is also held; `DirectionY` is now cleared before input checks so it cannot bleed from the previous frame.
