
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; variables.asm  -  Global Variable Block (RS layout in Fast RAM)
;==============================================================================
;
; This file defines the layout of the "Variables" block allocated in Fast RAM
; (section mem_fast, bss).  It uses RS directives so that the same symbol names
; work as both structure offsets AND as absolute addresses (since "Variables" is
; a real label at assembly time, and each RS name ends up being used as an
; offset from A5 which is permanently loaded with the Variables address).
;
; Convention:  a5 = Variables base pointer throughout the entire program.
;              All fields are accessed as  FieldName(a5).
;
; RSRESET is used once at the top; each rs.x directive advances the RS counter
; and assigns the current count to the label.  rs.w 0 at the end captures
; the total byte count in Variables_sizeof, which is used to reserve the BSS
; block with  "Variables: ds.b Variables_sizeof".
;
;==============================================================================

                      rsreset

;------------------------------------------------------------------------------
; Level management
;------------------------------------------------------------------------------
LevelId:              rs.w    1   ; current level number (0-based index into levels.bin)
LevelPtr:             rs.l    1   ; pointer to current level's raw data in LevelData

;------------------------------------------------------------------------------
; Tile grid maps
;
; GameMapCeiling - the solid top border row (WALL_PAPER_WIDTH bytes).
;                  Always all BLOCK_SOLID; never modified at runtime.
; GameMap        - the live game map (WALL_PAPER_SIZE bytes = 14*9 = 126 bytes).
;                  Starts as a copy of the level data expanded into the border
;                  frame.  Modified during play as players/actors move and
;                  blocks are destroyed or pushed.
; WallpaperCheat - a hidden extra row of TILE_BACK bytes at the bottom edge,
;                  used to give the renderer a clean termination row.
; WallpaperWork  - the tile-type map used by DrawWalls to select wall graphics.
;                  Derived from GameMap by WallPaperWalls; each byte holds a
;                  TILE_xxx value rather than a BLOCK_xxx value.
; WallpaperLadders - overlay map for ladder tile indices.  Zero = no ladder.
;                    Built by WallpaperMakeLadders.
; WallpaperShadows - overlay shadow flags.  Non-zero = draw a shadow here.
;                    Built by WallpaperMakeShadows.  The value encodes which
;                    of 16 possible shadow shapes to draw.
;------------------------------------------------------------------------------
GameMapCeiling:       rs.b    WALL_PAPER_WIDTH    ; top border row (14 bytes)
GameMap:              rs.b    WALL_PAPER_SIZE     ; live game map  (126 bytes)
WallpaperCheat:       rs.b    WALL_PAPER_WIDTH    ; bottom dummy row (14 bytes)
WallpaperWork:        rs.b    WALL_PAPER_SIZE     ; rendered wall tile types
RandomSeed:           rs.l    1   ; LFSR random number seed (seeded from LevelId)
WallpaperLadders:     rs.b    WALL_PAPER_SIZE     ; ladder tile overlay (0=none)
WallpaperShadows:     rs.b    WALL_PAPER_SIZE     ; shadow shape flags  (0=none)

;------------------------------------------------------------------------------
; Asset management
;------------------------------------------------------------------------------
TilesetPtr:           rs.l    1   ; pointer to the decompressed TileSet in Chip RAM
AssetSet:             rs.w    1   ; current tileset variant index (0-4, from LevelAssetSet)

;------------------------------------------------------------------------------
; Game flow
;------------------------------------------------------------------------------
MoveId:               rs.w    1   ; incremented each time a player makes a move

;------------------------------------------------------------------------------
; Player records
;
; PlayerPtrs - two longword pointers:
;   PlayerPtrs+0 : pointer to the ACTIVE  player (a4 is loaded from here)
;   PlayerPtrs+4 : pointer to the FROZEN  player
;   Swapping these two pointers is how PlayerSwitch changes the active character.
;
; Millie / Molly - the actual Player structure data (Player_Sizeof bytes each).
;   Millie uses sprite frames starting at offset 48 in RealSprites.
;   Molly  uses sprite frames starting at offset  0 in RealSprites.
;------------------------------------------------------------------------------
PlayerPtrs:           rs.l    2   ; [0]=active player ptr, [1]=frozen player ptr
Millie:               rs.b    Player_Sizeof   ; Millie's player structure
Molly:                rs.b    Player_Sizeof   ; Molly's  player structure

;------------------------------------------------------------------------------
; Game state machine
;------------------------------------------------------------------------------
GameStatus:           rs.w    1   ; 0=TitleSetup, 1=TitleRun, 2=GameRun

;------------------------------------------------------------------------------
; Display buffers
;
; ScreenPtrs holds pointers to the two display buffers (Screen1 / Screen2)
; for double-buffering.  Currently Screen1 is used for both entries (single
; buffer mode) - double-buffering is partially implemented.
;------------------------------------------------------------------------------
ScreenPtrs:           rs.l    2   ; [0]=front buffer, [1]=back buffer pointers

;------------------------------------------------------------------------------
; Hardware sprite pointers
;
; 8 longword pointers, one per hardware sprite channel (SPR0..SPR7).
; Updated each VBlank by ShowSprite and then copied into the copper list
; sprite pointer entries (cpSprites) so that Agnus fetches the correct data.
; Sprites 0/1 = left half of player, 2/3 = right half.  Sprites 4-7 unused.
;------------------------------------------------------------------------------
SpritePtrs:           rs.l    8   ; 8 sprite data pointers

;------------------------------------------------------------------------------
; Actor pool
;
; ActorCount - number of active actors currently in the pool (updated by
;              CleanActors after kills).
; Actors     - the flat actor structure array.  Actor_Sizeof bytes per slot,
;              MAX_ACTORS slots = MAP_SIZE = 88 slots maximum.
;              Always accessed via the sorted ActorList pointer array.
;------------------------------------------------------------------------------
ActorCount:           rs.w    1   ; number of live actors
Actors:               rs.b    Actor_Sizeof*MAX_ACTORS  ; actor pool (88 * Actor_Sizeof bytes)

;------------------------------------------------------------------------------
; Timing and input
;------------------------------------------------------------------------------
TickCounter:          rs.w    1   ; VBlank counter, incremented every frame (~50Hz PAL)
ControlsTrigger:      rs.b    1   ; one-shot bits: set on the frame a key was first pressed
ControlsHold:         rs.b    1   ; continuous bits: set for every frame a key is held

;------------------------------------------------------------------------------
; Per-frame movement flags
;------------------------------------------------------------------------------
PlayerMoved:          rs.w    1   ; non-zero if the active player moved this frame
PlayerCount:          rs.w    1   ; number of player characters initialised for this level

;------------------------------------------------------------------------------
; Level completion / action status
;------------------------------------------------------------------------------
LevelComplete:        rs.w    1   ; set to 1 when all enemies are destroyed
ActionStatus:         rs.w    1   ; current action state: ACTION_IDLE/MOVE/FALL/PLAYERPUSH

;------------------------------------------------------------------------------
; Push-block action state
;
; PushedActor   - pointer to the actor struct of the block being pushed.
;                 Valid only while ActionStatus = ACTION_PLAYERPUSH.
; ActionCounter - frame counter for the current push animation.
;------------------------------------------------------------------------------
PushedActor:          rs.l    1   ; pointer to the actor being pushed
ActionCounter:        rs.w    1   ; push animation frame counter (0..PUSH_STEPS-1)

;------------------------------------------------------------------------------
; Title screen
;
; TitleStars - array of TITLE_STAR_COUNT (4) star records, each a word pair:
;   word 0 = X position (pixel, wraps at 3*32)
;   word 1 = Y position (pixel, wraps at TITLE_STAR_COUNT*32*3)
;   Stars are rendered by BlitStar32 on plane 4 of ScreenStatic.
;------------------------------------------------------------------------------
TitleStars:           rs.l    TITLE_STAR_COUNT    ; 4 star {X,Y} word pairs

;------------------------------------------------------------------------------
; Fallen actor list
;
; FallenActors      - array of actor pointers for actors that are currently
;                     in a fall animation (Actor_HasFalled set).  Filled by
;                     ActorFallAll, processed by ActionFallActors each frame.
; FallenActorsCount - number of valid entries in FallenActors.
;------------------------------------------------------------------------------
FallenActors:         rs.l    MAP_SIZE    ; up to 88 pointers (one per map cell)
FallenActorsCount:    rs.w    1           ; number of currently-falling actors

;------------------------------------------------------------------------------
; Pre-computed blitter clear masks
;
; ClearMasks holds 16 longword mask values (one per possible X sub-tile pixel
; offset 0..15) used by ClearActor to cleanly erase an actor from ScreenStatic.
; Built at startup by CreateClearMasks.
; Indexed as:  (a2, d1.w*4)  where d1 = d0 AND $f  (pixel offset mod 16).
;------------------------------------------------------------------------------
ClearMasks:           rs.l    TILE_WIDTH  ; 24 longs (only 16 used; TILE_WIDTH = 24)

;------------------------------------------------------------------------------
; Sorted actor pointer list
;
; ActorSlotPtr - write pointer into ActorList, advanced as actors are allocated
;                by GetActorSlot.  Reset to &ActorList at the start of each level.
; ActorList    - array of longword pointers to active Actor structures, sorted
;                by Y position (largest Y first) by SortActors so that actors
;                closer to the bottom are drawn last (i.e. on top).
;------------------------------------------------------------------------------
ActorSlotPtr:         rs.l    1           ; current write pointer into ActorList
ActorList:            rs.l    MAP_SIZE    ; sorted actor pointer array (88 entries max)

;------------------------------------------------------------------------------
; Level intro star animation state
;
; IntroStarX/Y   - current tile position of the large travelling star
; IntroTargX/Y   - destination tile (Molly's start position)
; IntroTick      - countdown to next step (INTRO_STEP_TICKS..1; step at 0)
; IntroDone      - 0 = travelling, INTRO_HOLD_TICKS..1 = holding at target, triggers end at 1
; IntroWriteIdx  - next slot index to write in the circular trail pool
; IntroTrailX/Y  - tile position of each trail particle (INTRO_TRAIL_MAX slots)
; IntroTrailLife - remaining life of each trail particle (0 = inactive)
;------------------------------------------------------------------------------
IntroStarX:           rs.w    1
IntroStarY:           rs.w    1
IntroTargX:           rs.w    1
IntroTargY:           rs.w    1
IntroTick:            rs.w    1
IntroDone:            rs.w    1
IntroWriteIdx:        rs.w    1
IntroTrailX:          rs.w    INTRO_TRAIL_MAX
IntroTrailY:          rs.w    INTRO_TRAIL_MAX
IntroTrailLife:       rs.w    INTRO_TRAIL_MAX

;------------------------------------------------------------------------------
; Burst star animation state
;
; After the large intro star holds at Molly's tile, BURST_STAR_COUNT small stars
; radiate outward in a circle (one per 45°) for BURST_LIFE frames.
; Positions are stored in 16.16 fixed-point (upper word = integer pixel).
; Velocity is applied each frame via add.l from the BurstVelTable in player.asm.
;------------------------------------------------------------------------------
BurstLife:            rs.w    1                   ; countdown (BURST_LIFE..0)
BurstStarX:           rs.l    BURST_STAR_COUNT    ; 16.16 FP pixel X per star
BurstStarY:           rs.l    BURST_STAR_COUNT    ; 16.16 FP pixel Y per star

;------------------------------------------------------------------------------
; Cloud death animation actor list
;
; CloudActors      - array of actor pointers for actors currently playing a
;                   cloud death animation (Actor_CloudTick > 0).  Filled by
;                   PlayerKillActor; processed by ActionCloudActors each frame.
; CloudActorsCount - number of valid entries in CloudActors (never compacted;
;                   entries with CloudTick=0 are skipped by the processor).
;------------------------------------------------------------------------------
CloudActors:          rs.l    MAP_SIZE    ; up to 88 cloud animation actor pointers
CloudActorsCount:     rs.w    1           ; number of actors ever added (reset at level load)

Variables_sizeof:     rs.w    0           ; total size of the Variables block in bytes
