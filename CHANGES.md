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

**Star animation refactor & player-switch transition** — Intro star and player-switch share a unified `StarAnim` state (`StarOrigin`, `StarTarget`, `StarAnimContext`). `ACTION_SWITCH` introduced so the player-pointer swap is deferred until the animation completes. `RedrawActorAtTile` added to restore actors when trail/background tiles refresh. `LevelCompleteHold` / `LEVEL_COMPLETE_HOLD_TICKS` added so a completed level is held on-screen briefly before the wipe begins.

**Cloud z-order via copper BPLCON2 patches** — `ActionCloudActors` patches two `WAIT+MOVE(BPLCON2)` pairs in the copper list to give bitplane priority over sprites for the exact scanlines occupied by the cloud tile; a `CloudCopperRestartNeeded` flag and VBlank restart logic apply the change safely. *(Later superseded — see HW sprite conversion below.)*

**Cloud death converted to hardware sprites** — Cloud frames converted to unattached Amiga HW sprite format (`assets/cloud_hw_sprites.bin`, `assets/particle_hw_sprites.bin`). `ActionCloudActors` simplified: clouds blit to bitplanes; all mid-screen BPLCON2 copper-patch code (`PatchCloudCopperBPLCON2`, `ResetCloudCopperBPLCON2`, `CloudCopperRestartNeeded`) and associated VBlank restart handling removed. Tool `tools/convert_cloud_sprites.py` added to generate the HW sprite assets.

**Title screen — dual parallax stars & palette cycle** — `TitleSetup` now initialises two star arrays: fast stars on bitplane 3 (`TitleStars`) and slow stars on bitplane 4 (`TitleSlowStars`). `BlitStar32Slow` added for the slow layer. `TitleCycleColours` and `TitleCycleTable` update `COLOR01–COLOR07` each VBlank for a shifting colour wash over the logo. Star colours locked per palette range: `COLOR08–COLOR15` = fast-star colour, `COLOR16–COLOR31` = slow-star colour.

**Undo / rewind system** — New `include/resources/undo.asm` implements a circular snapshot-based undo allowing step-back up to `UNDO_BUFFER_SIZE - 1` moves (default 8). `InitUndoBuffer` resets the buffer at level load and takes an initial snapshot. `TakeSnapshot` is called after every move settles. `UndoMove` restores the previous player and actor structs and redraws the screen. `F9` in `ActionIdle` triggers `UndoMove`. Frozen player's static tile redrawn explicitly after restore so the non-active character remains visible. Bug fix: `UndoDrawActors` (full-scan over `MAX_ACTORS`) replaces `DrawStaticActors` in the undo path to avoid misses caused by `CleanActors` shrinking `ActorCount`.

**Title gradient copper sub-list** — `assets/gradient.s` (generated with gradient-blaster for Amiga OCS) appended immediately after `cpTitle` in chip RAM, changing `COLOR00` per scanline to produce a vertical gradient behind the logo. `COPPER_HALT` removed from `copperlists.asm`; the gradient sub-list terminates `cpTitle` itself. `TitleStarDraw` Y-modulation range widened (±8 → ±63 pixels) by adjusting arithmetic shifts.

**Title star palette & plane clear fixes** — `COLOR08–COLOR15` and `COLOR16–COLOR31` filled by loop (not two explicit writes) so stars stay visible at all logo-pixel palette phases. Bitplane 3 and 4 zero-filled at the start of `TitleStarDraw` to prevent trailing star artifacts. `TitleCycleColours` removed from the `.nostart` path.

**Actor pool clear fix** — `TurboClear` in `LevelInit` now starts from `Actors(a5)` (the base of the actor pool array) rather than `ActorList`, ensuring the full `Actor_Sizeof × MAX_ACTORS` region is zeroed.
