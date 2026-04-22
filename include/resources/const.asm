
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; const.asm  -  Global Constants
;==============================================================================
;
; All compile-time constants are defined here.  Nothing in this file emits
; any code or data bytes; it is purely symbol definitions (equates).
;
; Naming convention:
;   FOO_BAR   = a plain value
;   FOOB_X    = bit NUMBER  (B = Bit, for use with BTST/BSET/BCLR)
;   FOOF_X    = bit MASK    (F = Flag, i.e. 1<<bit, for use with AND/OR)
;
; Register conventions used throughout the codebase:
;   a5 = Variables structure base pointer (set once, never changed)
;   a6 = $dff000  CUSTOM chip base       (set once, never changed)
;   a4 = current Player structure pointer
;   a3 = current Actor  structure pointer
;
;==============================================================================


;------------------------------------------------------------------------------
; DMA control word written to DMACON to enable all subsystems we need.
;
; The Amiga custom chip Agnus controls Direct Memory Access for all subsystems.
; Writing to DMACON with bit 15 (SETCLR) set enables the listed channels.
; All channels must be individually enabled AND the MASTER bit must be set.
;
; DMAF_SETCLR  bit 15 - enable the bits that follow (vs. clear them)
; DMAF_MASTER  bit  9 - master DMA enable gate (mandatory)
; DMAF_RASTER  bit  8 - Bitplane (raster scan) DMA
; DMAF_COPPER  bit  7 - Copper coprocessor DMA
; DMAF_BLITTER bit  6 - Blitter DMA
; DMAF_SPRITE  bit  5 - Hardware sprite DMA
;
; The ! operator in DEVPAC/ASM-ONE is bitwise OR evaluated at assembly time.
;------------------------------------------------------------------------------
BASE_DMA            = DMAF_SETCLR|DMAF_MASTER|DMAF_RASTER|DMAF_COPPER|DMAF_BLITTER!DMAF_SPRITE


;------------------------------------------------------------------------------
; Maximum number of actor slots allocated in the actor pool.
; One slot per map cell is the theoretical maximum (if every cell held an actor).
; MAP_SIZE is defined below.
;------------------------------------------------------------------------------
MAX_ACTORS          = MAP_SIZE


;------------------------------------------------------------------------------
; Display Window registers  (DIWSTRT / DIWSTOP)
;
; The Amiga display window tells Denise which part of the raster scan to make
; visible.  Outside the window, Denise outputs the background colour (COLOR00).
;
; DIWSTRT  = (V_start[7:0] << 8) | H_start[7:0]
; DIWSTOP  = (V_stop[7:0]  << 8) | H_stop[7:0]
;
; Horizontal values are in colour-clock units (one colour clock = 2 lo-res pixels).
; $81 is the standard PAL/NTSC left-edge value.  Subtracting 16 shifts the window
; 16 colour clocks to the left to accommodate the sprite positioning offset used
; in ShowSprite (sprites need extra room on the left side).
;
; Vertical values are raster line numbers.
; Line $2c (44) is the standard top of the display area.
;------------------------------------------------------------------------------
WINDOW_X_START      = $81-16       ; horizontal display start (colour-clocks)
WINDOW_X_STOP       = $c1          ; horizontal display stop
WINDOW_Y_START      = $2c          ; vertical display start  (raster line 44)
WINDOW_Y_STOP       = $2c-40       ; vertical display stop   (low 8 bits only, wraps)


;------------------------------------------------------------------------------
; Player sprite sheet frame offsets.
;
; The hardware sprite data (realsprites.bin) is a flat array of sprite frames.
; Each frame is SPRITE_SIZE bytes (see below).  These constants are frame-index
; offsets added to the base sprite index to select the correct animation cell.
;
; Layout (Molly base = 0, Millie base = 48):
;   +0  .. +3    idle / generic standing
;   +4  .. +11   walk right (8 frames)
;   +16 .. +19   on-ladder climbing (4 frames)
;   +19          ladder freeze frame (static when idle on ladder)
;   +28 .. +31   falling (4 frames)
;   PLAYER_SPRITE_LEFT_OFFSET added to mirror the right-facing frames for left
;------------------------------------------------------------------------------
PLAYER_SPRITE_LEFT_OFFSET   = 32   ; frame offset for left-facing versions
PLAYER_SPRITE_LADDER_OFFSET = 16   ; frame offset for on-ladder frames
PLAYER_SPRITE_LADDER_IDLE   = 19   ; single frame used when frozen on ladder
PLAYER_SPRITE_FALL_OFFSET   = 28   ; frame offset for falling animation
PLAYER_SPRITE_WALK_OFFSET   = 4    ; frame offset for walking animation

;------------------------------------------------------------------------------
; Landing impact smoke animation
;
; When an actor finishes a fall, a 4-frame smoke animation (SPRITE_SMOKE_A..D)
; is blitted over the actor's landed tile for IMPACT_FRAME_TICKS VBlanks per
; frame (16 VBlanks total at 50 Hz ≈ 320 ms).
;
; Sprite sheet indices 98..101 are the smoke cloud frames in sprites.bin
; (row 8, columns 2..5 of the 12×12 grid).
;
; IMPACT_TOTAL_TICKS = IMPACT_FRAME_TICKS * IMPACT_FRAMES = 16
;   Actor_ImpactTick counts 1..IMPACT_TOTAL_TICKS while animating; 0 = idle.
;------------------------------------------------------------------------------
SPRITE_SMOKE_A      = 98    ; smoke puff frame 0 (row 8, col 2)
SPRITE_SMOKE_B      = 99    ; smoke puff frame 1 (row 8, col 3)
SPRITE_SMOKE_C      = 100   ; smoke puff frame 2 (row 8, col 4)
SPRITE_SMOKE_D      = 101   ; smoke puff frame 3 (row 8, col 5)
IMPACT_FRAMES       = 4     ; number of smoke animation frames
IMPACT_FRAME_TICKS  = 4     ; VBlanks displayed per frame
IMPACT_TOTAL_TICKS  = IMPACT_FRAME_TICKS*IMPACT_FRAMES   ; 16 total VBlanks


;------------------------------------------------------------------------------
; Sine / easing table parameters.
;
; sin.bin contains a full-period sine table of SINE_ANGLES signed 16-bit words.
; Values span -$7fff to +$7fff  (i.e. -32767 to +32767).
;
; To look up the sine of an angle (in the range 0..SINE_ANGLES-1):
;   index = angle_in_degrees * SINE_ANGLES / 360
;   value = word at  Sinus + index*2
;
; SINE_x constants are pre-computed table indices for common angles,
; avoiding division at run time.
;
; The quadratic.bin / quartic.bin tables use the same index range and are used
; for easing curves (smooth acceleration / deceleration during movement).
;------------------------------------------------------------------------------
SINE_ANGLES         = (SinusEnd-Sinus)/2    ; total entries in sine table
SINE_RANGE          = $7fff                 ; maximum table value (32767)
SINE_0              = 0                     ; table index for   0 degrees
SINE_1              = SINE_ANGLES/360       ; table index for   1 degree
SINE_45             = SINE_ANGLES/8         ; table index for  45 degrees
SINE_90             = SINE_ANGLES/4         ; table index for  90 degrees
SINE_180            = SINE_90*2             ; table index for 180 degrees
SINE_270            = SINE_90*3             ; table index for 270 degrees


;------------------------------------------------------------------------------
; Number of animated star objects on the title screen.
;------------------------------------------------------------------------------
TITLE_STAR_COUNT    = 4


;------------------------------------------------------------------------------
; Pre-combined display window register values written into the copper list.
; Constructed from the individual X/Y constants above.
;------------------------------------------------------------------------------
WINDOW_START        = (WINDOW_Y_START<<8)|WINDOW_X_START
WINDOW_STOP         = (WINDOW_Y_STOP<<8)|WINDOW_X_STOP


;------------------------------------------------------------------------------
; Bitplane DMA fetch window  (DDFSTRT / DDFSTOP)
;
; These registers tell Agnus on each raster line when to start and stop reading
; bitplane data from Chip RAM to feed Denise.
;
; Values are in units of colour-clocks / 2  (i.e. every 4 pixels in lo-res).
; FETCH_START = $30 is standard for a screen starting at colour-clock $81.
; FETCH_STOP  = $d0 is the standard stop for a 336-pixel wide screen.
;
; If these are wrong, you will see the display shift horizontally or have
; missing pixels on the left/right edges.
;------------------------------------------------------------------------------
FETCH_START         = $38-8        ; bitplane DMA fetch start ($30)
FETCH_STOP          = $d0          ; bitplane DMA fetch stop


;------------------------------------------------------------------------------
; Screen / bitplane geometry.
;
; The game uses a 5-bitplane interleaved screen stored in Chip RAM.
; 5 bitplanes = 2^5 = 32 colours.
;
; Three full-screen buffers are maintained:
;   NonDisplayScreen   - the clean background (walls, ladders, shadows only)
;   DisplayScreen - working copy, actors drawn on top of NonDisplayScreen
;   Screen1/2    - double-buffer for display (currently unused in this build)
;
; SCREEN_STRIDE  - byte offset between the start of one row (plane 0) and the
;                  next row (plane 0) in an interleaved layout.
;                  = SCREEN_DEPTH * SCREEN_WIDTH_BYTE = 5 * 42 = 210 bytes
;
; SCREEN_MOD    - value written to BPL1MOD / BPL2MOD in the copper list.
;                  After Agnus has fetched each row of plane 0, it adds this
;                  modulo to skip forward over the remaining 4 planes so that
;                  the next fetch begins at the correct address for plane 0 of
;                  the following row.
;                  = (SCREEN_DEPTH - 1) * SCREEN_WIDTH_BYTE = 4 * 42 = 168
;------------------------------------------------------------------------------
SCREEN_WIDTH        = TILE_WIDTH*WALL_PAPER_WIDTH       ; 24 * 14 = 336 pixels
SCREEN_WIDTH_BYTE   = SCREEN_WIDTH/8                    ; 336/8   =  42 bytes/row
SCREEN_HEIGHT       = TILE_HEIGHT*WALL_PAPER_HEIGHT     ; 24 *  9 = 216 pixels
SCREEN_DEPTH        = 5                                 ; bitplanes -> 32 colours
SCREEN_MOD          = SCREEN_WIDTH_BYTE*(SCREEN_DEPTH-1); 42 * 4  = 168
SCREEN_SIZE         = SCREEN_WIDTH_BYTE*SCREEN_HEIGHT*SCREEN_DEPTH ; 42*216*5 = 45360 bytes
SCREEN_STRIDE       = SCREEN_DEPTH*SCREEN_WIDTH_BYTE    ; 5 * 42  = 210 bytes
SCREEN_COLORS       = 32                                ; palette entries


;------------------------------------------------------------------------------
; Wallpaper (background tile grid) dimensions.
;
; WALL_PAPER_WIDTH / HEIGHT defines the full tile grid including the solid
; border cells around the playable area.  Total = 14 x 9 = 126 cells.
;
; GAME_MAP_SIZE adds one extra row (the ceiling) above WALL_PAPER_HEIGHT,
; used to hold the permanent solid top border row of tiles.
;------------------------------------------------------------------------------
WALL_PAPER_WIDTH    = 14
WALL_PAPER_HEIGHT   = 9
WALL_PAPER_SIZE     = WALL_PAPER_WIDTH*WALL_PAPER_HEIGHT    ; 126 cells
GAME_MAP_SIZE       = WALL_PAPER_WIDTH*(WALL_PAPER_HEIGHT+1); 140 cells (inc. ceiling)


;------------------------------------------------------------------------------
; Logical game map dimensions.
;
; The playable area inside the solid border is MAP_WIDTH x MAP_HEIGHT = 11 x 8.
; Level data files contain exactly MAP_SIZE = 88 bytes per level.
; The map is centred within the wallpaper grid (one column of solid tiles on
; each side, one row of solid tiles top and bottom).
;------------------------------------------------------------------------------
MAP_WIDTH           = 11           ; playable tile columns
MAP_HEIGHT          = 8            ; playable tile rows
MAP_SIZE            = MAP_WIDTH*MAP_HEIGHT  ; 88 bytes per level


;------------------------------------------------------------------------------
; Block type identifiers (stored in GameMap / WallpaperWork arrays).
;
; Each byte in the map arrays holds one of these values.
; The InitObject dispatcher in actors.asm uses BLOCK_xxx to choose the correct
; actor initialisation routine.
; PlayerTryMove uses BLOCK_xxx to decide what the player can do when attempting
; to enter that cell (move, push, kill, climb, etc.).
;------------------------------------------------------------------------------
BLOCK_EMPTY         = 0    ; open space - player and actors may enter freely
BLOCK_LADDER        = 1    ; ladder column - player can climb up/down
BLOCK_ENEMYFALL     = 2    ; enemy subject to gravity (falls if unsupported)
BLOCK_PUSH          = 3    ; pushable block - player slides it horizontally
BLOCK_DIRT          = 4    ; breakable dirt - player destroys it on contact
BLOCK_SOLID         = 5    ; impassable wall - nothing passes through
BLOCK_ENEMYFLOAT    = 6    ; floating enemy - not affected by gravity
BLOCK_MILLIESTART   = 7    ; Millie start position marker in level data
BLOCK_MOLLYSTART    = 8    ; Molly start position marker in level data
BLOCK_MILLIELADDER  = 9    ; map cell occupied by Millie while on a ladder
BLOCK_MOLLYLADDER   = 10   ; map cell occupied by Molly while on a ladder


;------------------------------------------------------------------------------
; Tile dimensions.
;
; Tiles are displayed at 24x24 pixels but stored in 32-pixel-wide bitplane rows
; (TILE_WIDTHF = 32) so each row is exactly one longword wide per bitplane.
; This makes blitter operations more efficient as no byte-alignment code is needed
; for tile source data (only for the screen destination offset).
;
; TILE_SIZE  = total bytes for one tile across all SCREEN_DEPTH bitplanes:
;              (32/8) bytes/row * SCREEN_DEPTH planes * TILE_HEIGHT rows
;              = 4 * 5 * 24 = 480 bytes
;
; SHADOW_SIZE = bytes for one shadow graphic (single bitplane, 32 wide, 24 tall):
;              (32/8) * 24 = 96 bytes
;------------------------------------------------------------------------------
TILE_WIDTH          = 24           ; displayed pixel width
TILE_HEIGHT         = 24           ; displayed pixel height
TILE_WIDTHF         = 32           ; stored pixel width (rounded up to longword)
TILE_SIZE           = (TILE_WIDTHF/8)*SCREEN_DEPTH*TILE_HEIGHT  ; 480 bytes per tile
SHADOW_SIZE         = (TILE_WIDTHF/8)*TILE_HEIGHT               ;  96 bytes per shadow


;------------------------------------------------------------------------------
; Tile grid coverage of the screen (for loop bounds in rendering routines).
;------------------------------------------------------------------------------
TILE_SCREEN_WIDTH   = SCREEN_WIDTH/TILE_WIDTH   ; 336/24 = 14 columns
TILE_SCREEN_HEIGHT  = SCREEN_HEIGHT/TILE_HEIGHT ; 216/24 =  9 rows


;------------------------------------------------------------------------------
; Hardware sprite structure size (bytes).
;
; Each Amiga hardware sprite structure in memory contains:
;   Word 0  - SPRxPOS : V_START[7:0] and H_START[8:1]
;   Word 1  - SPRxCTL : V_STOP[7:0], attach bit, H_START LSB, V_START/STOP bit 8
;   Rows 1..TILE_HEIGHT  - 2 words of pixel data per row (4 bytes each)
;   2 words of zeros to terminate the sprite
;
; Total = 4 (header) + (TILE_HEIGHT * 4) (data) + 4 (terminator) = 104 bytes.
;
; The player uses FOUR hardware sprites (two attached pairs) to achieve a
; 32-pixel-wide, 4-colour sprite image for 24 pixels of visible width.
; Pairs 0+1 form the left half, pairs 2+3 form the right half.
; Attaching sprites gives an extra 2 bits of colour depth per pair.
;------------------------------------------------------------------------------
SPRITE_SIZE         = 4+(TILE_HEIGHT*4)+4       ; 104 bytes per sprite structure

; Hardware sprite channel assignment:
;   SPR0-3  player character (two attached pairs, 24px wide, 16 colours)
;   SPR4-7  unused (NullSprite)
HW_FRAME_SIZE       = 4*SPRITE_SIZE             ; 416 bytes per frame (realsprites.bin)

; Byte offsets into the cpSprites copper list block (8 bytes per channel pair: PTH+PTL).
SPRITE_CH_SIZE      = 8                         ; bytes per sprite channel entry in copper list
SPRITE_00_OFFSET    = 0*SPRITE_CH_SIZE          ; SPR0PTH/L  - player left  half (attached pair 0)
SPRITE_02_OFFSET    = 2*SPRITE_CH_SIZE          ; SPR2PTH/L  - player right half (attached pair 1)
SPRITE_04_OFFSET    = 4*SPRITE_CH_SIZE          ; SPR4PTH/L  - unused (NullSprite)
SPRITE_06_OFFSET    = 6*SPRITE_CH_SIZE          ; SPR6PTH/L  - unused (NullSprite)


;------------------------------------------------------------------------------
; Default starting level (0-based index into levels.bin).
;------------------------------------------------------------------------------
START_LEVEL         = 20


;------------------------------------------------------------------------------
; Tile indices into the current loaded tileset (TileSet buffer in Chip RAM).
;
; WallPaperWalls / WallpaperMakeLadders write these values into WallpaperWork
; and WallpaperLadders respectively.  DrawTile / PasteTile then use them to
; select the correct 480-byte block from TileSet to blit to the screen.
;
; Wall tiles (0-8):
;   Single-cell walls, runs with left/right end-caps, 6 interior variants.
; Push tile  (9):    the pushable crate graphic.
; Ladder tiles (10-15):
;   Combinations of: top-cap vs. free-top, middle, bottom-cap.
; Dirt tiles (16-19):
;   4 variants depending on left/right neighbours (for seamless joins).
; Enemy tiles (20-27):
;   4 animation frames each for the falling and floating enemy types.
; Background tile (28):
;   Plain background, used wherever there is no solid wall or game object.
;------------------------------------------------------------------------------
TILE_WALLSINGLE     = 0    ; isolated single wall block
TILE_WALLLEFT       = 1    ; left end-cap of a horizontal wall run
TILE_WALLA          = 2    ; wall interior: random variant A
TILE_WALLB          = 3    ; wall interior: random variant B
TILE_WALLC          = 4    ; wall interior: random variant C
TILE_WALLD          = 5    ; wall interior: random variant D
TILE_WALLE          = 6    ; wall interior: random variant E
TILE_WALLF          = 7    ; wall interior: random variant F
TILE_WALLRIGHT      = 8    ; right end-cap of a horizontal wall run
TILE_PUSH           = 9    ; pushable block
TILE_LADDERA        = 10   ; ladder top, solid above  (resting on ceiling)
TILE_LADDERB        = 11   ; ladder top, free above
TILE_LADDERC        = 12   ; ladder middle section
TILE_LADDERD        = 13   ; ladder bottom section
TILE_LADDERE        = 14   ; ladder bottom, free top
TILE_LADDERF        = 15   ; ladder single-cell, free top
TILE_DIRTA          = 16   ; dirt, no neighbours
TILE_DIRTB          = 17   ; dirt, right neighbour present
TILE_DIRTC          = 18   ; dirt, left neighbour present
TILE_DIRTD          = 19   ; dirt, both neighbours (centre of a run)
TILE_ENEMYFALLA     = 20   ; falling enemy, frame 0
TILE_ENEMYFALLB     = 21   ; falling enemy, frame 1
TILE_ENEMYFALLC     = 22   ; falling enemy, frame 2
TILE_ENEMYFALLD     = 23   ; falling enemy, frame 3
TILE_ENEMYFLOATA    = 24   ; floating enemy, frame 0
TILE_ENEMYFLOATB    = 25   ; floating enemy, frame 1
TILE_ENEMYFLOATC    = 26   ; floating enemy, frame 2
TILE_ENEMYFLOATD    = 27   ; floating enemy, frame 3
TILE_BACK           = 28   ; empty background cell


;------------------------------------------------------------------------------
; Sprite-set and tile-set sizes.
;
; The actor sprite sheet (sprites.bin) contains 12*12 = 144 individual 24x24
; tile frames for all actor types and animation states.
;
; TILESET_COUNT = total tile types in the loaded tile set:
;   (8*3) = 24 wall types across 3 groups  +  5 additional special tiles
;   This matches the layout of the tiles_N.pak compressed assets.
;------------------------------------------------------------------------------
SPRITESET_COUNT     = 12*12                         ; 144 sprite frames
SPRITESET_SIZE      = TILE_SIZE*SPRITESET_COUNT     ; 144 * 480 = 69120 bytes
TILESET_COUNT       = (8*3)+5                       ; 29 tile types
TILESET_SIZE        = TILE_SIZE*TILESET_COUNT       ; 29 * 480 = 13920 bytes


;------------------------------------------------------------------------------
; Raw CIA keyboard scan-codes for function keys F1-F10.
;
; The CIA-A chip receives serial data from the keyboard controller.
; After de-serialising, the scan-code byte is bit-rotated and inverted by the
; interrupt handler (see keyboard.asm) to give these 7-bit values.
; They are stored as non-zero bytes in the Keys[] array (indexed by scan-code).
; A non-zero entry means the key is currently pressed.
;
; F1 = $50, F2 = $51 ... F10 = $59
; Used by LevelTest in main.asm to navigate levels during development.
;------------------------------------------------------------------------------
KEY_F1              = $50
KEY_F2              = $51
KEY_F3              = $52
KEY_F4              = $53
KEY_F5              = $54
KEY_F6              = $55
KEY_F7              = $56
KEY_F8              = $57
KEY_F9              = $58
KEY_F10             = $59


;------------------------------------------------------------------------------
; Control input bit definitions.
;
; ReadControls (controls.asm) packs the current digital input state into a
; single byte:
;
;   bit 4 = Fire / Space  -> switch the active player
;   bit 3 = Right
;   bit 2 = Left
;   bit 1 = Down
;   bit 0 = Up
;
; ControlsTrigger  = bits set on the frame a key was FIRST pressed (edge detect)
; ControlsHold     = bits set whenever a key IS held down
;
; CONTROLB_x  = bit position (use with BTST #CONTROLB_x,reg)
; CONTROLF_x  = bit mask     (use with AND.B #CONTROLF_x,reg then TST)
;------------------------------------------------------------------------------
CONTROLB_UP         = 0
CONTROLB_DOWN       = 1
CONTROLB_LEFT       = 2
CONTROLB_RIGHT      = 3
CONTROLB_FIRE       = 4

CONTROLF_UP         = 1<<0  ; $01
CONTROLF_DOWN       = 1<<1  ; $02
CONTROLF_LEFT       = 1<<2  ; $04
CONTROLF_RIGHT      = 1<<3  ; $08
CONTROLF_FIRE       = 1<<4  ; $10


;------------------------------------------------------------------------------
; Game action state-machine values  (stored in ActionStatus).
;
; Each value selects a handler in the JMPINDEX dispatch table at PlayerLogic.
; Only one action can be active at a time; it runs every VBlank until complete,
; then returns to ACTION_IDLE.
;
; ACTION_IDLE        - polling for player input each frame
; ACTION_MOVE        - smooth tile-to-tile movement animation (24 pixel steps)
; ACTION_FALL        - player and actors falling under gravity (eased)
; ACTION_PLAYERPUSH  - animating a pushed block sliding to its new position
;------------------------------------------------------------------------------
ACTION_IDLE         = 0
ACTION_MOVE         = 1
ACTION_FALL         = 2
ACTION_PLAYERPUSH   = 3
ACTION_INTRO        = 4     ; level intro star animation
ACTION_SWITCH       = 5     ; player switch star animation (same body as ACTION_INTRO)

;------------------------------------------------------------------------------
; Enemy tile animation
;
; TILE_ENEMYFALL and TILE_ENEMYFLOAT each have 4 animation frames (A..D).
; AnimateEnemies cycles through them at ENEMY_ANIM_TICKS VBlanks per frame,
; giving a 2fps animation rate on 50Hz PAL hardware.
;   frame_index = (TickCounter / ENEMY_ANIM_TICKS) & 3
;------------------------------------------------------------------------------
ENEMY_ANIM_TICKS    = 12    ; VBlanks per enemy animation frame


;------------------------------------------------------------------------------
; Level intro star animation
;
; At the start of each level a large blue star (SPRITE_STAR_LARGE) travels from
; the corner of the screen diagonally opposite to Molly's start position toward
; that start position, leaving a trail of small white stars (SPRITE_STAR_SMALL)
; that fade out after INTRO_TRAIL_LIFE VBlanks.
;
; Movement is tile-by-tile: one tile step every INTRO_STEP_TICKS VBlanks.
; Trail pool (INTRO_TRAIL_MAX slots) is large enough to hold all concurrent
; particles: INTRO_TRAIL_LIFE / INTRO_STEP_TICKS = 40 / 4 = 10 active at once.
;
; Sprite sheet (sprites.bin, 12×12 grid, index = row*12 + col):
;   SPRITE_STAR_LARGE  row 11, col 11  = 11*12 + 11 = 143
;   SPRITE_STAR_SMALL  row 11, col  9  = 11*12 +  9 = 141
;------------------------------------------------------------------------------
SPRITE_STAR_LARGE   = 143   ; large blue star       (row 11, col 11)
SPRITE_STAR_SMALL   = 141   ; small white star      (row 11, col  9)
INTRO_STEP_TICKS    = 6     ; VBlanks per one-tile step
INTRO_TRAIL_LIFE    = 40    ; VBlanks each trail particle remains visible
INTRO_TRAIL_MAX     = 16    ; trail pool size (>= INTRO_TRAIL_LIFE/INTRO_STEP_TICKS = 10 active steps)
INTRO_HOLD_TICKS    = 60    ; VBlanks the large star holds at the target before the intro ends (~1.2s PAL)
SWITCH_HOLD_TICKS   = 20    ; VBlanks the large star holds during player-switch transition (~0.4s PAL)


;------------------------------------------------------------------------------
; Enemy death cloud animation
;
; When an enemy is killed by the player, a 7-frame cloud animation plays at
; the enemy's tile position.
;
; Sprite sheet (sprites.bin, 12×12 grid, index = row*12 + col):
;   row 11, cols 0..6 → indices 132..138
;
; CLOUD_TOTAL_TICKS = CLOUD_FRAME_TICKS * CLOUD_FRAMES = 42 VBlanks (~840ms PAL)
;   Actor_CloudTick counts 1..CLOUD_TOTAL_TICKS while animating; 0 = idle.
;------------------------------------------------------------------------------
SPRITE_CLOUD_A      = 132   ; cloud frame 0  (row 11, col 0)
SPRITE_CLOUD_B      = 133   ; cloud frame 1  (row 11, col 1)
SPRITE_CLOUD_C      = 134   ; cloud frame 2  (row 11, col 2)
SPRITE_CLOUD_D      = 135   ; cloud frame 3  (row 11, col 3)
SPRITE_CLOUD_E      = 136   ; cloud frame 4  (row 11, col 4)
SPRITE_CLOUD_F      = 137   ; cloud frame 5  (row 11, col 5)
SPRITE_CLOUD_G      = 138   ; cloud frame 6  (row 11, col 6)
CLOUD_FRAMES        = 7
CLOUD_FRAME_TICKS   = 9
CLOUD_TOTAL_TICKS   = CLOUD_FRAME_TICKS*CLOUD_FRAMES   ; 63


;------------------------------------------------------------------------------
; Level wipe transition
;
; At the end of each level a screen-wipe effect progressively blacks out every
; tile before the next level loads.  The pattern is chosen at random from
; NUM_WIPE_PATTERNS effects each time.
;
; WipeOppositeTable (in mapstuff.asm) maps each pattern index to its
; directional inverse so a future reveal animation can use the matching effect.
;
; LEVEL_WIPE        - GameStatus value while the wipe is running (state 3)
; LEVEL_HOLD        - GameStatus value while the all-black hold is active (state 4)
; LEVEL_REVEAL      - GameStatus value while the tile-by-tile reveal plays (state 5)
; NUM_WIPE_PATTERNS - distinct wipe effects; MUST be a power of 2
; WIPE_SPEED        - tiles blitted black per VBlank
;                     126 tiles / 2 = 63 frames ≈ 1.26 s at 50 Hz PAL
; WIPE_HOLD_TICKS   - extra frames to hold all-black before loading next level
; WIPE_CENTER_X/Y   - tile coords of the screen centre for radial patterns
; WIPE_MAX_DIST     - max Chebyshev distance from (7,4) in the 14×9 grid
;
; Pattern indices  (also used as WipeOppositeTable indices):
;   WIPE_TOP_BOTTOM  (0) - row by row, top → bottom
;   WIPE_BOTTOM_TOP  (1) - row by row, bottom → top
;   WIPE_LEFT_RIGHT  (2) - column by column, left → right
;   WIPE_RIGHT_LEFT  (3) - column by column, right → left
;   WIPE_DIAG_TLBR   (4) - diagonal stripes, top-left → bottom-right
;   WIPE_DIAG_BRTL   (5) - diagonal stripes, bottom-right → top-left
;   WIPE_CENTER_OUT  (6) - from centre tile outward (Chebyshev distance)
;   WIPE_CENTER_IN   (7) - from edges inward to centre
;------------------------------------------------------------------------------
GAME_INIT           = 0     ; GameStatus: initialze status when Game loads
GAME_TITLE          = 1     ; GameStatus: display title screen
GAME_RUN            = 2     ; GameStatus: level is setup, and ready/playing'

LEVEL_INIT          = 3     ; GameStatus: initializing a new level (loading data, etc.) 
LEVEL_WIPE          = 4     ; GameStatus: wipe in progress (tiles blitted black)
LEVEL_HOLD          = 5     ; GameStatus: hold all-black while next level loads
LEVEL_REVEAL        = 6     ; GameStatus: reverse-wipe reveal of the new level

NUM_WIPE_PATTERNS   = 8     ; must be a power of 2 (AND mask used for selection)
WIPE_SPEED          = 4     ; tiles blitted per VBlank (63 frames ≈ 1.26s PAL)
WIPE_HOLD_TICKS             = 20    ; frames to hold black before loading next level (~0.4s)
LEVEL_COMPLETE_HOLD_TICKS   = 40    ; frames to pause on the finished level before the wipe starts (~0.8s PAL)

WIPE_CENTER_X       = 7     ; centre tile column (0-based, 14-column grid)
WIPE_CENTER_Y       = 4     ; centre tile row    (0-based,  9-row   grid)
WIPE_MAX_DIST       = 7     ; max Chebyshev distance from (7,4) in 14×9 grid

WIPE_TOP_BOTTOM     = 0
WIPE_BOTTOM_TOP     = 1
WIPE_LEFT_RIGHT     = 2
WIPE_RIGHT_LEFT     = 3
WIPE_DIAG_TLBR      = 4
WIPE_DIAG_BRTL      = 5
WIPE_CENTER_OUT     = 6
WIPE_CENTER_IN      = 7



