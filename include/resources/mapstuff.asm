
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; mapstuff.asm  -  Level Rendering and Map Initialisation
;==============================================================================
;
; Handles everything related to drawing the game level into the screen buffers:
;
;   Level initialisation:
;     LevelInit        - clear buffers, load assets, build all map arrays
;     SetLevelAssets   - decompress correct tile set, set palette
;     WallPaperLoadBase  - copy base/border template into wallpaper arrays
;     WallPaperLoadLevel - copy level data from LevelData into GameMap/WallpaperWork
;     WallPaperWalls     - build tile-type array (WallpaperWork) from GameMap
;     WallpaperMakeLadders - build ladder tile overlay (WallpaperLadders)
;     WallpaperMakeShadows - build shadow shape overlay (WallpaperShadows)
;
;   Rendering to screen:
;     DrawMap           - master draw routine: init + walls + ladders + shadows + actors
;     DrawWalls         - blit all wall tiles (from WallpaperWork) into NonDisplayScreen
;     DrawLadders       - overlay ladder tiles onto NonDisplayScreen
;     DrawShadows       - overlay shadow graphics onto NonDisplayScreen
;     DrawTile          - blit a single 24x24 tile using the blitter (no mask)
;     PasteTile         - blit a tile with mask (transparency support)
;     ShadowTile        - blit a shadow graphic with per-plane OR operation
;     DrawActor         - blit a moving actor tile (with shift-aware masking)
;     DrawButtons       - draw UI buttons and level counter to NonDisplayScreen
;     DrawLevelCounter  - render the level number onto the counter graphic
;     DrawButton        - blit a single UI button graphic
;
;   Utilities:
;     GenTileMask       - generate the blitter mask for the current tile set
;     GenSpriteMask     - generate blitter mask for the sprite sheet
;     CopySaveToStatic  - copy NonDisplayScreen -> DisplayScreen
;     CopyStaticToBuffers - copy DisplayScreen -> Screen1 and Screen2
;
; Blitter background:
;   The 68000's internal speed is limited by its bus cycle time.  The Amiga's
;   custom Blitter chip performs DMA-driven block copies far faster.  All tile
;   rendering uses the Blitter with WAITBLIT between operations.
;
;   Blitter operation used for tiles (minterm $fca = A&B|~A&C):
;     A = mask  (TileMask or pre-computed)
;     B = tile  (TileSet data)
;     C = destination  (current screen content)
;     D = destination
;   Result: where mask A=1, D = tile (B); where mask A=0, D = background (C).
;   This achieves transparent blitting.
;
; Register convention:
;   a6 = $dff000 (CUSTOM)   a5 = Variables base
;
;==============================================================================


;==============================================================================
; DrawMap  -  Master level draw entry point
;
; Resets player/level state, fully initialises and renders the current level
; into NonDisplayScreen, then copies it to DisplayScreen and both screen buffers.
;
; Call order:
;   LevelInit        - build maps, load assets, create actors
;   DrawWalls        - render wall tile grid into NonDisplayScreen
;   DrawButtons      - render UI (level counter + buttons) into NonDisplayScreen
;   DrawLadders      - overlay ladder tiles onto NonDisplayScreen
;   DrawShadows      - overlay shadow graphics onto NonDisplayScreen
;   CopySaveToStatic - copy NonDisplayScreen to DisplayScreen (working display buffer)
;   DrawStaticActors - blit all actor tiles into DisplayScreen
;   CopyStaticToBuffers - copy DisplayScreen to Screen1 and Screen2
;==============================================================================

DrawMap:
    clr.w         PlayerCount(a5)        ; reset player count before re-init
    clr.w         LevelComplete(a5)      ; clear level completion flag
    clr.w         ActionStatus(a5)       ; reset action state to IDLE

    bsr           LevelInit              ; init maps, load assets, create actors
    bsr           DrawWalls              ; render wall/background tiles
    bsr           DrawButtons            ; render UI buttons and level counter
    bsr           DrawLadders            ; overlay ladder graphics
    bsr           DrawShadows            ; overlay shadow graphics

    rts

DrawPlayersAndActors:
    bsr           CopySaveToStatic       ; copy clean background to DisplayScreen
    bsr           DrawStaticActors       ; blit actor tiles on top of DisplayScreen
    bsr           DrawInitialPlayers     ; draw both players at level start

    rts 
    

;==============================================================================
; DrawButtons  -  Render the UI strip on the right side of the screen
;
; The right-hand UI area (from pixel column 304) contains:
;   - Level counter (level number display) at top
;   - 4 action buttons below (Undo, Hint, Reset, Switch - from Button0..3Raw)
;
; Pixel positions are hardcoded; buttons are 19 pixels tall with 43px spacing.
; The level counter occupies a slightly different width (6 bytes vs 4 bytes).
;
; DrawLevelCounter and DrawButton blit from their source graphics into NonDisplayScreen
; using the blitter with mask (minterm $fca, using pre-generated masks).
;==============================================================================

DrawButtons:
    move.w        #304-8-3,d0            ; X pixel position of level counter
    move.w        #14,d1                 ; Y pixel position of level counter
    moveq         #0,d2

    lea           LevelCountRaw,a0       ; source graphic for level counter background
    bsr           DrawLevelCounter       ; blit level counter with digit overlay

    add.w         #43,d1                 ; advance Y to first button position

    move.w        #304,d0                ; X position for action buttons
    lea           Button0Raw,a0
    bsr           DrawButton             ; button 0 (Undo)

    lea           Button1Raw,a0
    add.w         #43,d1                 ; next button Y
    bsr           DrawButton             ; button 1 (Hint)

    lea           Button2Raw,a0
    add.w         #43,d1
    bsr           DrawButton             ; button 2 (Reset)

    lea           Button3Raw,a0
    add.w         #43,d1
    bsr           DrawButton             ; button 3 (Switch)

    rts


;==============================================================================
; CopyStaticToBuffers  -  Copy DisplayScreen to both display buffers
;
; After building the static scene, this copies DisplayScreen into Screen1 and
; Screen2 so that both double-buffer targets start with the correct base image.
; (Currently both Screen1 entries point to Screen1 - true double-buffering
; would use Screen1 and Screen2 alternately.)
;
; Uses longword copies for speed (SCREEN_SIZE must be a multiple of 4).
;==============================================================================

CopyStaticToBuffers:
    lea           DisplayScreen,a0
    lea           Screen1,a1
    lea           Screen1,a2             ; NOTE: both point to Screen1 (single-buffer mode)
    move.w        #(SCREEN_SIZE/4)-1,d7  ; number of longwords - 1 (for DBRA)

.copy
    move.l        (a0)+,d0
    move.l        d0,(a1)+               ; copy to buffer 1
    move.l        d0,(a2)+               ; copy to buffer 2
    dbra          d7,.copy
    rts


;==============================================================================
; CopySaveToStatic  -  Copy NonDisplayScreen to DisplayScreen
;
; NonDisplayScreen contains the clean background (walls + ladders + shadows, no actors).
; This is copied to DisplayScreen at the start of each scene composition step
; so that actors can be blitted on top without permanently modifying the save copy.
;==============================================================================

CopySaveToStatic:
    lea           NonDisplayScreen,a0
    lea           DisplayScreen,a1
    move.w        #(SCREEN_SIZE/4)-1,d7

.copy
    move.l        (a0)+,(a1)+
    dbra          d7,.copy
    rts


;==============================================================================
; LevelInit  -  Initialise all state for a new level
;
; Sequence:
;   1. TurboClear NonDisplayScreen (blank starting canvas)
;   2. Clear Player_Status for both Millie and Molly (both inactive until placed)
;   3. Set PlayerPtrs: Millie -> [0], Molly -> [1]
;   4. SetLevelAssets: decompress tile set, set palette
;   5. GenTileMask: build blitter masks from tile graphics
;   6. Seed the random number generator from LevelId (for deterministic wall variants)
;   7. WallPaperLoadBase: load border/template row into GameMapCeiling + WallpaperWork
;   8. WallPaperLoadLevel: copy level data from LevelData into GameMap + WallpaperWork
;   9. WallPaperWalls: convert GameMap BLOCK_SOLID cells into wall tile types
;  10. WallpaperMakeLadders: build the ladder tile overlay (WallpaperLadders)
;  11. WallpaperMakeShadows: build the shadow shape overlay (WallpaperShadows)
;  12. InitGameObjects: scan GameMap, create actor structs for all objects
;==============================================================================

LevelInit:
    ; Clear the save screen buffer (background)
    lea           NonDisplayScreen,a0
    move.l        #SCREEN_SIZE,d7
    bsr           TurboClear

    ; Deactivate both players and clear their state until they are
    ; re-initialized from the level map
    lea           Millie(a5),a0
    clr.w         Player_Status(a0)      ; Millie inactive
    clr.w         Player_X(a0)           ; Clear tile position X
    clr.w         Player_Y(a0)           ; Clear tile position Y
    clr.w         Player_XDec(a0)        ; Clear sub-tile X offset
    clr.w         Player_YDec(a0)        ; Clear sub-tile Y offset
    clr.w         Player_PrevX(a0)       ; Clear previous X
    clr.w         Player_PrevY(a0)       ; Clear previous Y
    clr.w         Player_NextX(a0)       ; Clear destination X
    clr.w         Player_NextY(a0)       ; Clear destination Y
    clr.w         Player_ActionCount(a0) ; Clear action countdown
    clr.w         Player_AnimFrame(a0)   ; Clear animation frame
    move.w        #1,Player_Facing(a0)   ; Set facing to right
    clr.w         Player_OnLadder(a0)    ; Clear ladder state
    clr.w         Player_DirectionX(a0)  ; Clear directional input
    clr.w         Player_DirectionY(a0)  ; Clear directional input
    clr.w         Player_Fallen(a0)      ; Clear falling flag
    clr.w         Player_ActionFrame(a0) ; Clear action frame counter
    move.l        a0,PlayerPtrs(a5)      ; PlayerPtrs[0] -> Millie

    lea           Molly(a5),a0
    clr.w         Player_Status(a0)      ; Molly inactive
    clr.w         Player_X(a0)           ; Clear tile position X
    clr.w         Player_Y(a0)           ; Clear tile position Y
    clr.w         Player_XDec(a0)        ; Clear sub-tile X offset
    clr.w         Player_YDec(a0)        ; Clear sub-tile Y offset
    clr.w         Player_PrevX(a0)       ; Clear previous X
    clr.w         Player_PrevY(a0)       ; Clear previous Y
    clr.w         Player_NextX(a0)       ; Clear destination X
    clr.w         Player_NextY(a0)       ; Clear destination Y
    clr.w         Player_ActionCount(a0) ; Clear action countdown
    clr.w         Player_AnimFrame(a0)   ; Clear animation frame
    move.w        #1,Player_Facing(a0)   ; Set facing to right
    clr.w         Player_OnLadder(a0)    ; Clear ladder state
    clr.w         Player_DirectionX(a0)  ; Clear directional input
    clr.w         Player_DirectionY(a0)  ; Clear directional input
    clr.w         Player_Fallen(a0)      ; Clear falling flag
    clr.w         Player_ActionFrame(a0) ; Clear action frame counter
    move.l        a0,PlayerPtrs+4(a5)    ; PlayerPtrs[1] -> Molly

    bsr           SetLevelAssets         ; decompress tile set + set palette

    bsr           GenTileMask            ; build TileMask from TileSet (for masked blits)

    ; Seed the PRNG from the level ID so wall tile randomisation is reproducible.
    ; The magic constant $BABEFEED gives a good initial spread.
    move.l        #$BABEFEED,d0
    move.b        LevelId+1(a5),d0       ; mix in low byte of level ID
    move.l        d0,RandomSeed(a5)      ; store as new seed

    clr.w         CloudActorsCount(a5)   ; reset cloud animation list for new level

    bsr           WallPaperLoadBase      ; load border frame + clear ladder/shadow arrays
    bsr           WallPaperLoadLevel     ; copy level data into GameMap + WallpaperWork
    bsr           LevelInitPlayers       ; scan GameMap for player starts; set Player_X/Y
    bsr           WallPaperWalls         ; convert BLOCK_SOLID to wall tile graphics
    bsr           WallpaperMakeLadders   ; build ladder tile overlay
    bsr           WallpaperMakeShadows   ; build shadow flag overlay
    bsr           InitGameObjects        ; create actors for all game objects in map
    rts


;==============================================================================
; SetLevelAssets  -  Load and activate the correct tile set for the current level
;
; 1. Look up the tile set index for LevelId in LevelAssetSet[].
; 2. Load the first 16 palette colours from the corresponding tiles_N.pal.
; 3. Load the second 16 palette colours from sprites.pal (actor sprites).
; 4. Decompress the corresponding tiles_N.pak into TileSet (Chip RAM buffer).
; 5. Store TilesetPtr pointing at TileSet.
;
; The copper list palette section (cpPal) is updated in two halves:
;   colours  0-15: from TilesPal0/1/2/3/4 (background / wall tiles)
;   colours 16-31: from SpritePal (actor / player sprites)
;
; Tile set palette files are SCREEN_COLORS*2 bytes each (32 words = 64 bytes).
; The two halves are each SCREEN_COLORS/2 = 16 entries.
;==============================================================================

SetLevelAssets:
    moveq         #0,d0
    move.w        LevelId(a5),d0         ; d0 = current level index
    lea           LevelAssetSet,a0
    move.b        (a0,d0.w),d0           ; d0 = tile set index (0-4)
    move.w        d0,AssetSet(a5)        ; remember current set
    move.w        d0,d4                  ; keep a copy for the decompression step

    ; Load first 16 palette entries from the correct tile palette
    mulu          #SCREEN_COLORS*2,d0    ; byte offset = index * 32 words * 2 bytes
    lea           TilesPal0,a0           ; base of palette array
    add.w         d0,a0                  ; a0 -> palette for this tile set
    lea           cpPal,a1               ; a1 -> copper palette entries
    moveq         #(SCREEN_COLORS/2)-1,d7  ; 16 entries

.cloop1
    move.w        (a0)+,2(a1)            ; write palette word into copper MOVE data
    addq.l        #4,a1                  ; advance 4 bytes (reg+data pair)
    dbra          d7,.cloop1

    ; Load second 16 palette entries from sprite palette (shared across all tile sets)
    lea           SpritePal,a0
    moveq         #(SCREEN_COLORS/2)-1,d7

.cloop2
    move.w        (a0)+,2(a1)
    addq.l        #4,a1
    dbra          d7,.cloop2

    ; Decompress the selected tile set from Fast RAM into TileSet (Chip RAM).
    ; d4 = tile set index; multiply by 4 to get longword offset into TileAssets table.
    add.w         d4,d4                  ; index * 2
    add.w         d4,d4                  ; index * 4 (longword size)
    lea           TileAssets,a0
    move.l        (a0,d4.w),a0           ; a0 -> compressed tile data for this set
    lea           TileSet,a1             ; a1 -> decompression buffer in Chip RAM
    move.l        a1,TilesetPtr(a5)      ; store pointer for later use
    bsr           zx0_decompress         ; decompress ZX0 stream: a0->compressed, a1->output

    rts


;==============================================================================
; WallPaperLoadLevel  -  Copy level data from LevelData into game maps
;
; Reads MAP_WIDTH x MAP_HEIGHT bytes from the level data file and places them
; into the interior cells of both WallpaperWork and GameMap (the live game map).
;
; The map data is MAP_WIDTH (11) columns wide, but WallpaperWork is
; WALL_PAPER_WIDTH (14) columns wide (with a 1-cell solid border on each side
; and one column for the right-side UI area).
;
; The +1 offset on the destination advances past the left border column so
; that map data is written into columns 1..11, leaving columns 0 and 12-13
; as the solid/background border.
;
; The outer loop iterates MAP_HEIGHT (8) rows.
; The inner loop copies MAP_WIDTH (11) bytes, then skips 3 bytes
; (WALL_PAPER_WIDTH - MAP_WIDTH - 1 = 14 - 11 - 1 = 2, but +1 offset = 3 skip)
; to step over the remaining columns to the next row start.
;
; After building WallpaperWork, the same data is also copied to GameMap
; (the live game map used for collision detection and actor tracking).
;==============================================================================

WallPaperLoadLevel:
    ; Calculate offset into LevelData for the current level:
    ;   offset = LevelId * MAP_SIZE  (88 bytes per level)
    moveq         #0,d0
    move.w        LevelId(a5),d0
    lea           LevelData,a0
    mulu          #MAP_SIZE,d0           ; d0 = byte offset into level file
    add.w         d0,a0                  ; a0 -> start of current level data
    move.l        a0,LevelPtr(a5)        ; save for ladder/shadow routines

    ; Copy into WallpaperWork (skipping border cells)
    lea           WallpaperWork+1(a5),a1 ; +1 to skip the left border column
    moveq         #MAP_HEIGHT-1,d7

.line
    moveq         #MAP_WIDTH-1,d6

.copy
    move.b        (a0)+,(a1)+            ; copy one cell
    dbra          d6,.copy

    addq.w        #3,a1                  ; skip right border + padding columns
    dbra          d7,.line

    ; Also copy into GameMap (the live collision/logic map)
    move.l        LevelPtr(a5),a0        ; re-read level data pointer

    lea           GameMap+1(a5),a1       ; +1 to skip the left border column
    moveq         #MAP_HEIGHT-1,d7

.line2
    moveq         #MAP_WIDTH-1,d6

.copy2
    move.b        (a0)+,(a1)+
    dbra          d6,.copy2

    addq.w        #3,a1
    dbra          d7,.line2

    lea           GameMap(a5),a0         ; return a0 pointing at GameMap (for callers)
    rts


;==============================================================================
; LevelInitPlayers  -  Scan GameMap for player start markers; set Player_X/Y
;
; Called from LevelInit immediately after WallPaperLoadLevel so that both
; player structures have correct tile coordinates before LevelIntroSetup reads
; them (and before InitGameObjects creates actor slots).
;
; Scans the full WALL_PAPER_WIDTH x WALL_PAPER_HEIGHT grid.  When it finds
; BLOCK_MILLIESTART (7) or BLOCK_MOLLYSTART (8) it writes the tile column and
; row into the respective player structure's Player_X / Player_Y fields.
;
; Preserves all registers (PUSHALL / POPALL).
;==============================================================================

LevelInitPlayers:
    PUSHALL

    lea         GameMap(a5),a0          ; a0 -> start of live game map (14x9 bytes)
    moveq       #0,d2                   ; d2 = current row (0..WALL_PAPER_HEIGHT-1)

.row_loop
    moveq       #0,d1                   ; d1 = current column (0..WALL_PAPER_WIDTH-1)

.col_loop
    moveq       #0,d0
    move.b      (a0)+,d0                ; d0 = block type at (d1, d2)

    cmp.b       #BLOCK_MILLIESTART,d0
    bne         .check_molly

    ; Found Millie start — write tile coords to Millie struct
    lea         Millie(a5),a1
    move.w      d1,Player_X(a1)
    move.w      d2,Player_Y(a1)
    bra         .next_col

.check_molly
    cmp.b       #BLOCK_MOLLYSTART,d0
    bne         .next_col

    ; Found Molly start — write tile coords to Molly struct
    lea         Molly(a5),a1
    move.w      d1,Player_X(a1)
    move.w      d2,Player_Y(a1)

.next_col
    addq.w      #1,d1
    cmp.w       #WALL_PAPER_WIDTH,d1
    blt         .col_loop

    addq.w      #1,d2
    cmp.w       #WALL_PAPER_HEIGHT,d2
    blt         .row_loop

    POPALL
    rts


;==============================================================================
; WallpaperMakeShadows  -  Build the shadow flag overlay (WallpaperShadows)
;
; For each TILE_BACK (background) cell in WallpaperWork, checks the four
; neighbouring cells (left, top-left, top, top-right) to see if any of them
; are also background.  The result is a 4-bit flag word encoding which
; neighbours are non-background (i.e. cast a shadow edge).
;
; The shadow shape is determined by this 4-bit value (0-15), which maps to
; one of the pre-generated shadow graphics in Shadows (shadows.bin).
; ShadowTile looks up the shadow graphic index from the .shadowlist table.
;
; Neighbour offsets in the linear WallpaperWork array:
;   -1                   = left
;   -(WALL_PAPER_WIDTH+1) = top-left  (one row up, one column left)
;   -WALL_PAPER_WIDTH    = directly above
;   -WALL_PAPER_WIDTH-1  = top-right  (one row up, one column right)
;     [Note: "top-right" is labelled such because when scanning left-to-right,
;      this cell is to the upper-right of the current position]
;
; Only cells with tile type 28 (TILE_BACK = background) get shadow entries.
; Other tile types (walls, ladders etc.) don't need shadows.
;
; Output: WallpaperShadows[] - one byte per cell; 0 = no shadow, non-zero = shadow flags
;==============================================================================

WallpaperMakeShadows:
    lea           WallpaperWork(a5),a0   ; source: tile type map
    lea           WallpaperShadows(a5),a1; destination: shadow flags

    moveq         #WALL_PAPER_HEIGHT-1,d7

.lineloop
    moveq         #WALL_PAPER_WIDTH-1,d6

.nextblock
    cmp.b         #28,(a0)               ; is this a background (TILE_BACK) cell?
    bne           .next                  ; no shadow needed for non-background cells

    ; Check four neighbours and build a 4-bit shadow flag
    lea           .offsets,a2            ; a2 -> neighbour offset table
    moveq         #4-1,d5
    moveq         #0,d3                  ; d3 = shadow flag accumulator

.bitloop
    lsl.w         #1,d3                  ; shift flags left to make room for new bit
    move.w        (a2)+,d2               ; d2 = signed byte offset to neighbour
    cmp.b         #28,(a0,d2.w)          ; is the neighbour also background?
    beq           .noblock               ; yes = no wall edge here = no shadow bit
    addq.w        #1,d3                  ; no = wall edge present = set bit

.noblock
    dbra          d5,.bitloop

    move.b        d3,(a1)                ; store 4-bit shadow flag for this cell

.next
    addq.w        #1,a0                  ; advance to next cell
    addq.w        #1,a1
    dbra          d6,.nextblock
    dbra          d7,.lineloop

    lea           WallpaperShadows(a5),a1; restore a1 to start of shadows array
    rts

.offsets
    dc.w          -1                     ; left neighbour
    dc.w          -(WALL_PAPER_WIDTH+1)  ; top-left neighbour
    dc.w          -WALL_PAPER_WIDTH      ; directly above
    dc.w          -WALL_PAPER_WIDTH-1    ; top-right neighbour (scanning direction)


;==============================================================================
; WallpaperMakeLadders  -  Build the ladder tile overlay (WallpaperLadders)
;
; Scans the level data (LevelPtr) column by column, finding vertical runs of
; BLOCK_LADDER cells and assigning the correct tile types (top/middle/bottom
; segments) in WallpaperLadders[].
;
; Processes MAP_WIDTH (11) columns, each MAP_HEIGHT (8) rows tall.
; Ladders can span multiple rows.  The tile chosen for each row depends on
; whether it is the first, middle, last, or only cell of the run, and whether
; the cell directly above the top of the ladder rests on a solid wall.
;
; Tile selection via LadderDespatch:
;   d4 = 1 if the top of the ladder rests on a solid wall (or is at the top of the map)
;   d4 = 0 if the top is free (floating ladder - appears different graphically)
;
; WallpaperLadders is indexed the same way as WallpaperWork (WALL_PAPER_WIDTH stride).
; The +1 offset on the destination skips the left border column, matching the
; way level data is placed (MAP data starts at column 1 in the wallpaper grid).
;==============================================================================

WallpaperMakeLadders:
    move.l        LevelPtr(a5),a3        ; a3 -> raw level data (MAP_WIDTH wide rows)
    lea           WallpaperLadders+1(a5),a4  ; a4 -> ladder output (+1 for left border)
    moveq         #MAP_WIDTH-1,d7        ; iterate MAP_WIDTH columns

.colloop
    move.l        a3,a0                  ; a0 -> current column, start of data
    move.l        a4,a1                  ; a1 -> output position for this column

    moveq         #MAP_HEIGHT-1,d6       ; iterate MAP_HEIGHT rows
    moveq         #0,d0                  ; d0 = current ladder run length

.nexttile
    cmp.b         #BLOCK_LADDER,(a0)     ; is this cell a ladder?
    beq           .isladder              ; yes - extend or start run

    ; Not a ladder: if we are in a run, dispatch it now
    tst.w         d0
    beq           .next                  ; d0=0 means not in a run
    beq           .next                  ; (redundant BEQ - harmless)
    bsr           LadderDespatch         ; write tile types for the completed run
    bra           .next

.isladder
    ; First cell of a new run?
    tst.w         d0
    bne           .skipptr               ; already in a run - just extend

    ; Start of a new ladder run.  Determine if top is on solid ground.
    moveq         #1,d4                  ; assume solid above (top-cap style)
    cmp.l         a0,a3                  ; is this the very first cell of the level data?
    beq           .topline               ; yes - treat as solid above
    cmp.b         #BLOCK_SOLID,-MAP_WIDTH(a0)  ; is the cell directly above solid?
    beq           .topline               ; yes - top cap style
    moveq         #0,d4                  ; no - free top style

.topline
    move.l        a1,a2                  ; a2 -> start of output run (for LadderDespatch)

.skipptr
    addq.w        #1,d0                  ; increment run length

    ; If this is the LAST row and we are still in a ladder run, dispatch now
    tst.w         d6
    bne           .next
    bsr           LadderDespatch

.next
    add.w         #MAP_WIDTH,a0          ; advance source by one row (MAP_WIDTH stride)
    add.w         #WALL_PAPER_WIDTH,a1   ; advance output by one row (WALL_PAPER_WIDTH stride)
    dbra          d6,.nexttile

    addq.w        #1,a3                  ; advance source to next column
    addq.w        #1,a4                  ; advance output to next column
    dbra          d7,.colloop

    lea           WallpaperLadders(a5),a4
    rts


;==============================================================================
; LadderDespatch  -  Write tile type bytes for one ladder run into WallpaperLadders
;
; Called when a ladder run ends (either end of run or end of column).
;
; On entry:
;   d0 = run length (number of cells in this ladder)
;   d4 = 1 if top rests on solid (solid top cap), 0 if free-floating top
;   a2 = pointer to start of the run in WallpaperLadders
;
; Tile assignments (using TILE_LADDER? constants):
;   Single-cell ladder (d0 = 1):
;     d4 = 1 -> TILE_LADDERA  (sits on solid)
;     d4 = 0 -> TILE_LADDERF  (free floating single)
;
;   Multi-cell ladder (d0 >= 2):
;     Top cell:
;       d4 = 1 -> TILE_LADDERB (solid top)
;       d4 = 0 -> TILE_LADDERE (free top)
;     Middle cells (d0 - 2 of them): TILE_LADDERC
;     Bottom cell: TILE_LADDERD
;
; After dispatch, d0 is reset to 0 (start of new run detection).
;==============================================================================

LadderDespatch:
    cmp.w         #1,d0
    beq           .isone                 ; single-cell ladder - special case

    ; Multi-cell ladder: write top, middle(s), bottom
    moveq         #14,d3                 ; default top = TILE_LADDERE (free top)
    tst.w         d4
    beq           .walk2
    moveq         #11,d3                 ; solid top = TILE_LADDERB

.walk2
    move.b        d3,(a2)                ; write top cell tile
    add.w         #WALL_PAPER_WIDTH,a2   ; advance to next row
    subq.w        #2,d0                  ; subtract top + bottom; remaining = middle count
    beq           .last                  ; d0=0 after subq -> no middle cells

.loop
    move.b        #12,(a2)               ; write TILE_LADDERC (middle segment)
    add.w         #WALL_PAPER_WIDTH,a2
    subq.w        #1,d0
    bne           .loop

.last
    move.b        #13,(a2)               ; write TILE_LADDERD (bottom segment)
    add.w         #WALL_PAPER_WIDTH,a2

    rts

.isone
    ; Single-cell ladder
    moveq         #15,d3                 ; default = TILE_LADDERF (free single)
    tst.w         d4
    beq           .topone
    moveq         #10,d3                 ; solid = TILE_LADDERA

.topone
    move.b        d3,(a2)                ; write single-cell tile
    moveq         #0,d0                  ; reset run length
    add.w         #WALL_PAPER_WIDTH,a2
    rts


;==============================================================================
; WallPaperWalls  -  Convert BLOCK_SOLID cells into wall tile variants
;
; Scans WallpaperWork row by row (WALL_PAPER_HEIGHT rows, WALL_PAPER_WIDTH cols).
; Finds runs of consecutive BLOCK_SOLID cells and assigns the correct wall
; tile types (single, left-cap, interior variants, right-cap, background).
;
; Non-solid cells are replaced with TILE_BACK (28 = background tile) in place.
;
; For each row:
;   Track the start of a solid run in a1.
;   Count run length in d0.
;   On first solid cell: mark the cell before as TILE_BACK; record run start.
;   On end of run (non-solid or end of row): call WallDespatch.
;
; After processing, WallpaperWork contains TILE_xxx values instead of BLOCK_xxx.
;==============================================================================

WallPaperWalls:
    lea           WallpaperWork(a5),a0
    moveq         #WALL_PAPER_HEIGHT-1,d7

.lineloop
    move.l        a0,a1                  ; a1 -> start of current row

    moveq         #WALL_PAPER_WIDTH-1,d6
    moveq         #0,d0                  ; d0 = current wall run length

.nexttile
    cmp.b         #BLOCK_SOLID,(a0)+     ; is this cell solid? (advance a0 past it)
    beq           .iswall

    ; Non-solid cell: dispatch any in-progress wall run
    bsr           WallDespatch
    bra           .next

.iswall
    ; First solid cell of a new run?
    tst.w         d0
    bne           .skipptr

    ; Start of run: write TILE_BACK into the cell BEFORE the run starts
    ; (because a0 was advanced, a0-1 is the current solid cell; a1 is being
    ;  maintained as the "run start" pointer and advanced here too).
    move.b        #28,(a1)+              ; TILE_BACK before run
    move.l        a0,a1                  ; a1 -> first solid cell (a0 is now past it)
    subq.l        #1,a1

.skipptr
    addq.w        #1,d0                  ; extend run length
    tst.w         d6
    bne           .next
    bsr           WallDespatch           ; end of row - dispatch remaining run

.next
    dbra          d6,.nexttile
    dbra          d7,.lineloop
    rts


;==============================================================================
; WallDespatch  -  Assign wall tile types to a completed horizontal run
;
; On entry:
;   d0 = number of solid cells in the run (0 = nothing to do)
;   a1 = pointer to the first cell of the run in WallpaperWork
;   AssetSet(a5) = current tile set index (0 = patterned walls; others = fully random)
;
; For tile set 0 (structured walls):
;   d0 = 0: write TILE_BACK (background) and return
;   d0 = 1: write TILE_WALLSINGLE
;   d0 = 2: write TILE_WALLLEFT + TILE_WALLRIGHT
;   d0 > 2: write TILE_WALLLEFT, random interior variants (6 choices), TILE_WALLRIGHT
;
; For tile sets 1-4 (fully random):
;   Every cell gets a fully random tile from 0-8 (all wall types).
;
; After dispatching, d0 is reset to 0 (ready for next run).
;==============================================================================

WallDespatch:
    tst.w         d0
    beq           .zero                  ; run length 0 = background cell

    tst.w         AssetSet(a5)           ; tile set 0 = structured; others = random
    bne           .fullrandom

    ; Structured wall (tile set 0)
    cmp.w         #1,d0
    beq           .isone                 ; single-cell wall

    cmp.w         #2,d0
    bne           .long                  ; 3+ cells

    ; Two-cell wall
    move.b        #TILE_WALLLEFT,(a1)+   ; left cap
    move.b        #TILE_WALLRIGHT,(a1)+  ; right cap
    moveq         #0,d0
    rts

.long
    ; Three-or-more-cell wall
    subq.w        #2,d0                  ; d0 = number of interior cells
    move.b        #TILE_WALLLEFT,(a1)+   ; left end-cap

.fill
    PUSH          d0
    RANDOMWORD                           ; generate random value in d0
    moveq         #0,d2
    move.w        d0,d2
    POP           d0
    divu          #6,d2                  ; d2 = remainder (0-5) + quotient in high word
    swap          d2                     ; bring remainder to low word
    add.w         #TILE_WALLA,d2         ; map to one of 6 interior tile variants

    move.b        d2,(a1)+               ; write random interior tile
    subq.w        #1,d0
    bne           .fill

    move.b        #TILE_WALLRIGHT,(a1)+  ; right end-cap
    rts

.isone
    move.b        #TILE_WALLSINGLE,(a1)+ ; isolated single-cell wall
    moveq         #0,d0
    rts

.zero
    move.b        #TILE_BACK,(a1)+       ; background / empty
    rts

.fullrandom
    ; Fully random tile for each cell (tile sets 1-4)
    PUSH          d0
    RANDOMWORD
    moveq         #0,d2
    move.w        d0,d2
    POP           d0
    divu          #9,d2                  ; choose from 9 wall tile variants (0-8)
    swap          d2

    move.b        d2,(a1)+               ; write random tile
    subq.w        #1,d0
    bne           .fullrandom
    rts


;==============================================================================
; WallPaperLoadBase  -  Load the border/template into GameMapCeiling and WallpaperWork
;
; Copies the static border template:
;   WallpaperBaseTop -> GameMapCeiling (the solid ceiling row, WALL_PAPER_WIDTH bytes)
;   WallpaperBase    -> WallpaperWork  (the 9-row frame with solid left/right borders)
;
; Both source arrays are defined in the data_fast section of main.asm.
; WallpaperBaseTop is all BLOCK_SOLID (5) - the full-width top border.
; WallpaperBase has BLOCK_SOLID on both ends and BLOCK_EMPTY in the interior.
;
; Also clears WallpaperLadders and WallpaperShadows to zero (no ladders/shadows).
; Fills WallpaperCheat (the hidden bottom dummy row) with TILE_BACK.
;==============================================================================

WallPaperLoadBase:
    ; Copy ceiling row template -> GameMapCeiling
    lea           WallpaperBaseTop,a0
    lea           GameMapCeiling(a5),a1
    move.w        #GAME_MAP_SIZE-1,d7

.game
    move.b        (a0)+,(a1)+
    dbra          d7,.game

    ; Copy base frame template -> WallpaperWork
    lea           WallpaperBase,a0
    lea           WallpaperWork(a5),a1
    move.w        #WALL_PAPER_SIZE-1,d7

.loop
    move.b        (a0)+,(a1)+
    dbra          d7,.loop

    ; Clear ladder and shadow overlay arrays
    lea           WallpaperLadders(a5),a0
    lea           WallpaperShadows(a5),a1
    move.w        #WALL_PAPER_SIZE-1,d7

.clr
    clr.b         (a0)+
    clr.b         (a1)+
    dbra          d7,.clr

    ; Fill the hidden bottom cheat row with TILE_BACK
    lea           WallpaperCheat(a5),a0
    moveq         #WALL_PAPER_WIDTH-1,d7

.cheat
    move.b        #TILE_BACK,(a0)+
    dbra          d7,.cheat
    rts


;==============================================================================
; DrawSprite  -  Blit a sprite tile from Sprites[] onto DisplayScreen with masking
;
; Similar to PasteTile but reads from Sprites (actor sprite sheet) rather than
; TileSet, and uses SpriteMask rather than TileMask.
;
; On entry:
;   d0 = pixel X position
;   d1 = pixel Y position
;   d2 = tile index in sprite sheet
;
; The blit uses minterm $fca (A&B | ~A&C): mask selects between sprite (B)
; and background (C), producing transparent blitting.
;
; Handles both aligned and 1-word-shifted (twowords) cases:
;   Aligned (shift = 0): source and dest modulos = 0 / TILE_BLT_MOD
;   Shifted (shift > 0): modulos are -2 wider (one extra word per row)
;==============================================================================

DrawSprite:
    PUSHM         d0-d2

    lea           Sprites,a0             ; sprite sheet base
    lea           SpriteMask,a2          ; sprite mask base
    lea           DisplayScreen,a1        ; destination buffer

    mulu          #TILE_SIZE,d2
    add.l         d2,a0                  ; advance to selected sprite tile
    add.l         d2,a2                  ; advance to corresponding mask

    ; Calculate destination address in DisplayScreen
    mulu          #SCREEN_STRIDE,d1      ; row offset (all planes)
    move.w        d0,d2
    asr.w         #3,d2                  ; byte column = X / 8
    add.w         d2,d1
    add.l         d1,a1                  ; a1 -> pixel row start in screen

    ; Calculate blitter shift amount (X mod 16)
    and.w         #$f,d0                 ; d0 = X AND 15  (0 = aligned, 1-15 = shifted)
    ror.w         #4,d0                  ; pack shift into bits 15:12 for BLTCON0
    move.w        d0,d1
    or.w          #$fca,d0               ; d0 = BLTCON0: shift + minterm A&B|~A&C
    cmp.w         #$8000,d1              ; shift = 0? (ror of 0 gives $8000? no, $0000)
    bcs           .twowords              ; shift != 0: need extra word (3 word wide blit)

    ; Aligned blit (2 words wide, no shift)
    WAITBLIT
    move.w        d0,BLTCON0(a6)
    move.w        d1,BLTCON1(a6)
    move.l        #$ffff0000,BLTAFWM(a6) ; first/last word mask
    move.l        a2,BLTAPT(a6)          ; A = mask
    move.l        a0,BLTBPT(a6)          ; B = sprite data
    move.l        a1,BLTCPT(a6)          ; C = destination (background)
    move.l        a1,BLTDPT(a6)          ; D = destination (output)
    move.w        #-2,BLTAMOD(a6)        ; A modulo: -2 (tight pack minus 2 for width)
    move.w        #-2,BLTBMOD(a6)
    move.w        #TILE_BLT_MOD-2,BLTCMOD(a6)
    move.w        #TILE_BLT_MOD-2,BLTDMOD(a6)
    move.w        #TILE_BLT_SIZE+1,BLTSIZE(a6)  ; +1 word for the shifted/aligned blit
    bra           .done

.twowords
    ; Shifted blit (3 words wide: sprite spans a word boundary)
    WAITBLIT
    move.w        d0,BLTCON0(a6)
    move.w        d1,BLTCON1(a6)
    move.l        #-1,BLTAFWM(a6)        ; all bits valid
    move.l        a2,BLTAPT(a6)
    move.l        a0,BLTBPT(a6)
    move.l        a1,BLTCPT(a6)
    move.l        a1,BLTDPT(a6)
    move.w        #0,BLTAMOD(a6)
    move.w        #0,BLTBMOD(a6)
    move.w        #TILE_BLT_MOD,BLTCMOD(a6)
    move.w        #TILE_BLT_MOD,BLTDMOD(a6)
    move.w        #TILE_BLT_SIZE,BLTSIZE(a6)

.done
    POPM          d0-d2
    rts


;==============================================================================
; GenSpriteMask  -  Generate blitter mask data for the sprite sheet
;
; For each row of each sprite in the sprite sheet (Sprites), OR together all
; 5 bitplane longwords to produce a combined "any pixel set" mask longword.
; This mask is replicated across all 5 planes of SpriteMask so that the
; blitter mask (A source) correctly covers any pixel that is set in ANY plane.
;
; Total iterations: SPRITESET_COUNT * TILE_HEIGHT = 144 * 24 = 3456 rows.
; Each row reads 5 longwords (one per plane) from Sprites and writes 5 longwords
; to SpriteMask.
;
; After this, SpriteMask is used as the A (mask) source in DrawSprite blits
; to correctly mask the transparent regions of sprite tiles.
;==============================================================================

GenSpriteMask:
    lea           Sprites,a0             ; source: sprite pixel data
    lea           SpriteMask,a1          ; destination: mask data
    move.w        #SPRITESET_COUNT*TILE_HEIGHT-1,d7  ; rows to process

.nexttile
    ; OR all 5 plane longwords together to get the combined mask
    move.l        (a0)+,d0
    or.l          (a0)+,d0
    or.l          (a0)+,d0
    or.l          (a0)+,d0
    or.l          (a0)+,d0               ; d0 = mask for this row (any pixel set = 1)

    ; Replicate the mask across all 5 planes of the mask buffer
    move.l        d0,(a1)+
    move.l        d0,(a1)+
    move.l        d0,(a1)+
    move.l        d0,(a1)+
    move.l        d0,(a1)+

    dbra          d7,.nexttile
    rts


;==============================================================================
; GenTileMask  -  Generate blitter mask data for the current tile set
;
; Identical algorithm to GenSpriteMask but operates on TileSet / TileMask.
; Called each time a new tile set is decompressed (in LevelInit via SetLevelAssets).
;
; Total iterations: TILESET_COUNT * TILE_HEIGHT = 29 * 24 = 696 rows.
;==============================================================================

GenTileMask:
    move.l        TilesetPtr(a5),a0      ; source: decompressed tile data
    lea           TileMask,a1            ; destination: tile mask
    move.w        #TILESET_COUNT*TILE_HEIGHT-1,d7

.nexttile
    move.l        (a0)+,d0
    or.l          (a0)+,d0
    or.l          (a0)+,d0
    or.l          (a0)+,d0
    or.l          (a0)+,d0

    move.l        d0,(a1)+
    move.l        d0,(a1)+
    move.l        d0,(a1)+
    move.l        d0,(a1)+
    move.l        d0,(a1)+

    dbra          d7,.nexttile
    rts


;------------------------------------------------------------------------------
; Blitter constants for tile, shadow and button blits.
;
; TILE_BLT_MOD  - destination modulo for a full-screen tile blit.
;                 = SCREEN_WIDTH_BYTE - 4
;                 After blitting 4 bytes (1 longword = 32 pixels = tile width in storage)
;                 Agnus must skip (SCREEN_WIDTH_BYTE - 4) bytes to reach the same column
;                 on the next row.  This value is written to BLTCMOD and BLTDMOD.
;
; TILE_BLT_SIZE - BLTSIZE register value for a tile blit.
;                 = (height_in_rows << 6) | words_per_row
;                 = (24*5 << 6) | 2  = 7680 | 2 = 7682
;                 BLTSIZE[15:6] = number of rows  (24 rows * 5 planes = 120)
;                 BLTSIZE[5:0]  = words per row   (2 words = 4 bytes = 32 pixels)
;
; SHADOW_BLT_MOD / SIZE - same calculation but for single-plane shadow blits.
; BUTTON_BLT_MOD / SIZE - for the 19-row button graphics.
;------------------------------------------------------------------------------

SHADOW_BLT_MOD      = SCREEN_STRIDE-4                  ; single-plane shadow modulo
SHADOW_BLT_SIZE     = ((24)<<6)+2                      ; 24 rows, 2 words wide

TILE_BLT_MOD        = SCREEN_WIDTH_BYTE-4              ; tile modulo (full screen)
TILE_BLT_SIZE       = ((24*SCREEN_DEPTH)<<6)+2         ; 120 rows (5 planes), 2 words


;==============================================================================
; DrawWalls  -  Blit all wall/background tiles from WallpaperWork into NonDisplayScreen
;
; Walks the WallpaperWork array (WALL_PAPER_WIDTH x WALL_PAPER_HEIGHT = 14x9)
; and calls DrawTile for each cell, passing the tile index and screen position.
;
; Pixel positions are computed as  X = col * TILE_WIDTH,  Y = row * TILE_HEIGHT.
; The outer loop iterates rows (Y += TILE_HEIGHT each iteration).
; The inner loop iterates columns (X += TILE_WIDTH each iteration).
;
; Note: DrawTile writes to NonDisplayScreen.  WallpaperWork was built by WallPaperWalls.
;==============================================================================

DrawWalls:
    lea           WallpaperWork(a5),a4   ; a4 -> tile type array
    moveq         #28,d2                 ; initial tile id (used for register clarity)

    moveq         #0,d1                  ; Y pixel position = 0 (top row)

.yloop
    move          #0,d0                  ; X pixel position = 0 (left column)

.xloop
    moveq         #0,d2
    move.b        (a4)+,d2               ; d2 = tile index for this cell
    bsr           DrawTile               ; blit tile to NonDisplayScreen at (d0, d1)
    add.w         #TILE_WIDTH,d0         ; advance X by one tile width (24)
    cmp.w         #SCREEN_WIDTH,d0       ; reached right edge?
    bcs           .xloop

    add.w         #TILE_HEIGHT,d1        ; advance Y by one tile height (24)
    cmp.w         #SCREEN_HEIGHT,d1      ; reached bottom edge?
    bcs           .yloop
    rts


;==============================================================================
; DrawLadders  -  Overlay ladder tiles onto NonDisplayScreen
;
; Walks WallpaperLadders and calls PasteTile (masked blit) for each non-zero
; entry.  Zero entries mean no ladder at that cell and are skipped.
;
; PasteTile uses the tile mask so ladder graphics appear with transparency
; (background shows through where the ladder tile has no pixels).
;==============================================================================

DrawLadders:
    lea           WallpaperLadders(a5),a4
    moveq         #0,d1                  ; Y = 0

.yloop
    move          #0,d0                  ; X = 0

.xloop
    moveq         #0,d2
    move.b        (a4)+,d2               ; d2 = ladder tile index (0 = none)
    beq           .skip                  ; skip empty cells

    lea           NonDisplayScreen,a1          ; destination: background save buffer
    bsr           PasteTile              ; masked blit with transparency

.skip
    add.w         #TILE_WIDTH,d0
    cmp.w         #SCREEN_WIDTH,d0
    bcs           .xloop

    add.w         #TILE_HEIGHT,d1
    cmp.w         #SCREEN_HEIGHT,d1
    bcs           .yloop
    rts


;==============================================================================
; DrawShadows  -  Overlay shadow graphics onto NonDisplayScreen
;
; Walks WallpaperShadows and calls ShadowTile for each non-zero entry.
; The shadow value is a 4-bit flag that ShadowTile maps to a shadow shape index.
;==============================================================================

DrawShadows:
    lea           WallpaperShadows(a5),a4
    moveq         #0,d1                  ; Y = 0

.yloop
    move          #0,d0                  ; X = 0

.xloop
    moveq         #0,d2
    move.b        (a4)+,d2               ; d2 = shadow flags (0 = none)
    beq           .skip

    bsr           ShadowTile             ; blit shadow graphic for this flag value

.skip
    add.w         #TILE_WIDTH,d0
    cmp.w         #SCREEN_WIDTH,d0
    bcs           .xloop

    add.w         #TILE_HEIGHT,d1
    cmp.w         #SCREEN_HEIGHT,d1
    bcs           .yloop
    rts


;==============================================================================
; ShadowTile  -  Blit a shadow graphic onto NonDisplayScreen (per-plane OR)
;
; Shadow graphics are single-bitplane images that darken specific pixels by
; setting them to colour 0 (background).  They are blitted with minterm $d0c
; (A | ~A&B = A&D | ~A&C, which is effectively "set pixels where A=1, keep B where A=0").
; Actually $d0c = OR with the existing plane content (NOT a transparency mask blit).
;
; The shadow is blitted once per bitplane using the same source graphic,
; advancing the destination address by SCREEN_WIDTH_BYTE between planes.
;
; On entry:
;   d0 = X pixel position
;   d1 = Y pixel position
;   d2 = shadow flag byte (4-bit, determines which shadow shape to use)
;
; The .shadowlist table maps the 4-bit flag to a shadow graphic index (0-5).
; A value of -1 means no shadow for that flag combination.
;
; Shadow graphic set:
;   0 = left edge shadow
;   1 = top edge shadow
;   2 = top-right corner shadow
;   3 = top-centre shadow
;   4 = top-left corner shadow
;   5 = diagonal shadow
; (exact shape definitions are in the shadow.bin asset)
;==============================================================================

ShadowTile:
    PUSHM         d0-d2

    ; Map shadow flags to a shadow graphic index via the lookup table
    lea           .shadowlist,a0
    add.w         d2,d2                  ; d2 * 2 (word table entries)
    move.w        (a0,d2.w),d2           ; d2 = shadow graphic index (-1 = none)
    bmi           .skip                  ; -1 -> no shadow here

    ; Calculate source address: Shadows + shadow_index * SHADOW_SIZE
    mulu          #SHADOW_SIZE,d2
    lea           Shadows,a0
    add.w         d2,a0                  ; a0 -> selected shadow graphic

    lea           NonDisplayScreen,a1          ; destination: background save buffer

    ; Calculate pixel offset in screen:
    mulu          #SCREEN_STRIDE,d1      ; row start offset (all planes)
    move.w        d0,d2
    asr.w         #3,d2                  ; byte column = X / 8
    add.w         d2,d1
    add.l         d1,a1                  ; a1 -> screen position

    ; Prepare BLTCON0: shift = X mod 16
    and.w         #$f,d0
    ror.w         #4,d0                  ; shift into bits 15:12
    move.w        d0,d1
    or.w          #$d0c,d0               ; BLTCON0: shift + minterm OR ($d0c)

    ; Blit shadow onto each bitplane separately (single-plane source, multi-plane dest)
    moveq         #SCREEN_DEPTH-1,d4     ; 5 planes

.plane
    WAITBLIT
    move.w        d0,BLTCON0(a6)         ; shift + minterm
    move.w        #0,BLTCON1(a6)         ; no shift on B channel
    move.l        #-1,BLTAFWM(a6)        ; all bits valid in A
    move.l        a0,BLTAPT(a6)          ; A = shadow graphic (single plane)
    move.l        a1,BLTBPT(a6)          ; B = current screen plane
    move.l        a1,BLTDPT(a6)          ; D = output (same as B)
    move.w        #0,BLTAMOD(a6)         ; shadow source: no modulo (tight rows)
    move.w        #SHADOW_BLT_MOD,BLTBMOD(a6)  ; screen modulo
    move.w        #SHADOW_BLT_MOD,BLTDMOD(a6)
    move.w        #SHADOW_BLT_SIZE,BLTSIZE(a6)

    add.w         #SCREEN_WIDTH_BYTE,a1  ; advance to next bitplane of same column

    dbra          d4,.plane

.skip
    POPM          d0-d2
    rts

; Shadow flag -> shadow graphic index table.
; Index = 4-bit shadow flag (0-15).  Value -1 = no shadow.
; Only certain flag combinations correspond to real shadow shapes.
.shadowlist
    dc.w          -1                     ;  0: no neighbours -> no shadow
    dc.w          -1                     ;  1
    dc.w           0                     ;  2
    dc.w          -1                     ;  3
    dc.w          -1                     ;  4
    dc.w           5                     ;  5
    dc.w          -1                     ;  6
    dc.w           1                     ;  7
    dc.w           2                     ;  8
    dc.w          -1                     ;  9
    dc.w           4                     ; 10
    dc.w          -1                     ; 11
    dc.w          -1                     ; 12
    dc.w           3                     ; 13
    dc.w          -1                     ; 14
    dc.w           4                     ; 15


;==============================================================================
; DrawTile  -  Blit a tile from TileSet into NonDisplayScreen (no mask, direct copy)
;
; Used by DrawWalls for background and wall tiles where every pixel should be
; opaque (the tile completely replaces the background).  Uses minterm $dfc
; (direct copy: D = A) rather than the masked $fca.
;
; On entry:
;   d0 = pixel X position (must be on a 24-pixel tile boundary, 0..312)
;   d1 = pixel Y position (must be on a 24-pixel tile boundary, 0..192)
;   d2 = tile index (0..TILESET_COUNT-1)
;   a5 = Variables base (for TilesetPtr)
;   a6 = $dff000
;
; Writes to NonDisplayScreen.
;==============================================================================

DrawTile:
    PUSHM         d0-d2

    ; Calculate source address in TileSet
    move.l        TilesetPtr(a5),a0
    lea           NonDisplayScreen,a1

    mulu          #TILE_SIZE,d2          ; byte offset = tile_index * TILE_SIZE
    add.w         d2,a0                  ; a0 -> selected tile's bitplane data

    ; Calculate destination address in NonDisplayScreen
    mulu          #SCREEN_STRIDE,d1      ; row offset = Y * SCREEN_STRIDE (all 5 planes)
    move.w        d0,d2
    asr.w         #3,d2                  ; byte column = X / 8
    add.w         d2,d1
    add.l         d1,a1                  ; a1 -> destination pixel in screen

    ; Shift calculation: since DrawTile is only called with tile-aligned X positions
    ; (multiples of 24, which are always aligned within 32-pixel storage),
    ; the shift is always 0.  BLTCON0 shift field = 0.
    and.w         #$f,d0                 ; X mod 16 (always 0 for tile-aligned calls)
    ror.w         #4,d0                  ; pack shift into bits 15:12 (= 0)
    or.w          #$dfc,d0               ; BLTCON0: minterm $dfc = D = A (direct copy)

    WAITBLIT
    move.w        d0,BLTCON0(a6)         ; shift + direct-copy minterm
    move.w        #0,BLTCON1(a6)         ; no second shift
    move.l        #-1,BLTAFWM(a6)        ; all source bits valid
    move.l        a0,BLTAPT(a6)          ; A = tile source
    move.l        a1,BLTBPT(a6)          ; B = screen (not used in minterm, but set)
    move.l        a1,BLTDPT(a6)          ; D = destination
    move.w        #0,BLTAMOD(a6)         ; source: tightly packed rows
    move.w        #TILE_BLT_MOD,BLTBMOD(a6)  ; screen modulo
    move.w        #TILE_BLT_MOD,BLTDMOD(a6)
    move.w        #TILE_BLT_SIZE,BLTSIZE(a6) ; 120 rows, 2 words wide

    POPM          d0-d2
    rts


;------------------------------------------------------------------------------
; Button and level counter blitter constants.
;
; Buttons are 19 rows tall (vs 24 for tiles), 4 bytes wide per plane row.
; Level counter is also 19 rows but 6 bytes wide (wider for the digit display).
;
; BUTTON_BLT_SIZE  = (19 rows * 5 planes << 6) | 2 words
; BUTTON2_BLT_SIZE = (19 rows * 5 planes << 6) | 3 words  (wider: 6 bytes)
;------------------------------------------------------------------------------

BUTTON_BLT_MOD      = SCREEN_WIDTH_BYTE-4          ; button modulo (4-byte row)
BUTTON_BLT_SIZE     = ((19*SCREEN_DEPTH)<<6)+2     ; 95 rows, 2 words

BUTTON2_BLT_MOD     = SCREEN_WIDTH_BYTE-6          ; level counter modulo (6-byte row)
BUTTON2_BLT_SIZE    = ((19*SCREEN_DEPTH)<<6)+3     ; 95 rows, 3 words

LEVEL_COUNT_STRIDE  = LEVEL_COUNT_WIDTH_BYTE*SCREEN_DEPTH  ; bytes between level counter rows
LEVEL_COUNT_START   = (LEVEL_COUNT_STRIDE*5)+3     ; byte offset to start of digit area within counter
LEVEL_COUNT_WIDTH_BYTE = 6                         ; bytes per row of the level counter graphic
LEVEL_FONT_WIDTH_BYTE  = 10                        ; bytes per row of the level font
LEVEL_FONT_STRIDE      = 10*SCREEN_DEPTH           ; bytes between level font rows (5 planes)


;==============================================================================
; DrawLevelCounter  -  Render the level number onto the level counter UI graphic
;
; Composites the current level number digits from LevelFont onto a copy of
; LevelCountRaw (the background counter graphic), then blits the result into
; NonDisplayScreen at the specified position.
;
; Steps:
;   1. Copy LevelCountRaw to LevelCountTemp (working buffer).
;   2. Extract decimal digits from (LevelId + 1) using TODECIMAL macro.
;   3. For each digit (3 digits, right-to-left), use LVLFNT macro to
;      AND-mask the target area and OR-in the font pixel for that digit.
;      This is done for 8 rows of each digit across 5 bitplanes.
;   4. Generate a combined mask in ButtonMaskTemp by OR-ing all 5 planes of
;      LevelCountTemp per row (mask = any pixel set in any plane).
;   5. Blit LevelCountTemp onto NonDisplayScreen using the mask (minterm $fca).
;
; On entry:
;   d0 = X pixel position
;   d1 = Y pixel position
;   a0 = pointer to LevelCountRaw (not used directly; overridden inside)
;   a5 = Variables base
;   a6 = $dff000
;==============================================================================

DrawLevelCounter:
    PUSHM         d0-d2

    ; Step 1: Copy LevelCountRaw to LevelCountTemp
    lea           LevelCountRaw,a0
    lea           LevelCountTemp,a2
    move.w        #(570/4)-1,d7          ; 570 bytes / 4 = 142 longwords

.copy
    move.l        (a0)+,(a2)+
    dbra          d7,.copy

    ; Step 2: Extract 3 decimal digits from level number (LevelId + 1, 1-based display)
    move.w        LevelId(a5),d2
    addq.w        #1,d2                  ; display as 1-based (level 0 shows as "1")
    TODECIMAL     d2,3,d3                ; d3 = 3-digit BCD in nibbles

    ; Step 3: Composite digits into LevelCountTemp
    ; Start at the rightmost digit position
    lea           LevelCountTemp,a0
    add.w         #LEVEL_COUNT_START,a0  ; a0 -> start of digit area in counter graphic

    moveq         #3-1,d6                ; 3 digits to render

.digit
    ; Extract current digit (4-bit nibble) from d3
    move.w        d3,d4
    lsr.w         #4,d3                  ; shift to expose next digit for next iteration
    and.w         #$f,d4                 ; d4 = current digit value (0-9)

    ; a2 -> correct column in LevelFont for this digit
    lea           LevelFont,a2
    add.w         d4,a2                  ; offset by digit value (one byte per column in font)

    ; Render 8 rows of this digit across all 5 bitplanes using LVLFNT macro
    moveq         #8-1,d7
    PUSH          a0                     ; save output pointer (moves each row)

.line
    ; Build the mask for this font row: OR all 5 planes of LevelFont together
    move.b        (a2),d5
    or.b          LEVEL_FONT_WIDTH_BYTE*1(a2),d5
    or.b          LEVEL_FONT_WIDTH_BYTE*2(a2),d5
    or.b          LEVEL_FONT_WIDTH_BYTE*3(a2),d5
    or.b          LEVEL_FONT_WIDTH_BYTE*4(a2),d5   ; d5 = combined pixel mask
    not.b         d5                     ; invert: 0 where digit pixels are (for AND-clear)

    ; For each plane: clear digit area in counter, OR in font pixel
    LVLFNT        0                      ; plane 0
    LVLFNT        1                      ; plane 1
    LVLFNT        2                      ; plane 2
    LVLFNT        3                      ; plane 3
    LVLFNT        4                      ; plane 4

    add.w         #LEVEL_COUNT_STRIDE,a0 ; advance output by one row (all planes)
    add.w         #LEVEL_FONT_STRIDE,a2  ; advance font by one row

    dbra          d7,.line

    POP           a0                     ; restore output pointer to row 0 of this digit

    subq.l        #1,a0                  ; move left one byte (next digit to the left)
    dbra          d6,.digit              ; render next digit

    ; Step 4: Generate mask in ButtonMaskTemp
    ; OR all 5 planes of each row of LevelCountTemp together to get the combined mask,
    ; then replicate it across all 5 planes of ButtonMaskTemp.
    lea           LevelCountTemp,a0
    move.l        a0,a2
    lea           ButtonMaskTemp,a3
    move.w        #19-1,d7               ; 19 rows

.nextline
    ; Read and OR all 5 plane contributions for this row (6 bytes = 3 words each)
    move.l        (a2)+,d5
    move.w        (a2)+,d6
    or.l          (a2)+,d5
    or.w          (a2)+,d6
    or.l          (a2)+,d5
    or.w          (a2)+,d6
    or.l          (a2)+,d5
    or.w          (a2)+,d6
    or.l          (a2)+,d5
    or.w          (a2)+,d6

    ; Write the mask for all 5 planes (6 bytes per plane row)
    move.l        d5,(a3)+
    move.w        d6,(a3)+
    move.l        d5,(a3)+
    move.w        d6,(a3)+
    move.l        d5,(a3)+
    move.w        d6,(a3)+
    move.l        d5,(a3)+
    move.w        d6,(a3)+
    move.l        d5,(a3)+
    move.w        d6,(a3)+

    dbra          d7,.nextline

    ; Step 5: Blit counter graphic onto NonDisplayScreen with mask
    lea           ButtonMaskTemp,a2      ; A source = mask
    lea           NonDisplayScreen,a1          ; C/D = destination

    lea           ButtonMaskTemp,a2      ; (re-set in case clobbered)

    ; Calculate destination address from d0, d1
    mulu          #SCREEN_STRIDE,d1
    move.w        d0,d2
    asr.w         #3,d2                  ; byte column
    add.w         d2,d1
    add.l         d1,a1

    ; Prepare shift and minterm
    and.w         #$f,d0
    ror.w         #4,d0
    move.w        d0,d1
    or.w          #$fca,d0               ; minterm $fca = A&B | ~A&C (masked copy)

    WAITBLIT
    move.w        d0,BLTCON0(a6)
    move.w        d1,BLTCON1(a6)
    move.l        #-1,BLTAFWM(a6)
    move.l        a2,BLTAPT(a6)          ; A = mask
    move.l        a0,BLTBPT(a6)          ; B = counter graphic (LevelCountTemp)
    move.l        a1,BLTCPT(a6)          ; C = screen background
    move.l        a1,BLTDPT(a6)          ; D = output
    move.w        #0,BLTAMOD(a6)
    move.w        #0,BLTBMOD(a6)
    move.w        #BUTTON2_BLT_MOD,BLTCMOD(a6)
    move.w        #BUTTON2_BLT_MOD,BLTDMOD(a6)
    move.w        #BUTTON2_BLT_SIZE,BLTSIZE(a6)

    POPM          d0-d2
    rts


;==============================================================================
; DrawButton  -  Blit a UI button graphic onto NonDisplayScreen with mask
;
; Generates a per-row mask from the button graphic (OR all 5 planes),
; then blits the graphic with that mask onto NonDisplayScreen at the given position.
;
; On entry:
;   d0 = X pixel position
;   d1 = Y pixel position
;   a0 = pointer to button graphic (ButtonNRaw, 5-plane, 19 rows, 4 bytes wide)
;
; The button graphic is 5 bitplanes * 19 rows * 4 bytes = 380 bytes.
; ButtonMaskTemp is filled with the per-row mask (OR of all 5 planes).
;==============================================================================

DrawButton:
    PUSHM         d0-d2

    ; Generate mask: OR all 5 plane contributions per row into ButtonMaskTemp
    move.l        a0,a2                  ; a2 -> button source data
    lea           ButtonMaskTemp,a3
    move.w        #19-1,d7               ; 19 rows

.nextline
    ; Read and OR all 5 plane longwords (4 bytes each) for this row
    move.l        (a2)+,d5
    or.l          (a2)+,d5
    or.l          (a2)+,d5
    or.l          (a2)+,d5
    or.l          (a2)+,d5               ; d5 = combined row mask

    ; Replicate mask across all 5 planes of ButtonMaskTemp
    move.l        d5,(a3)+
    move.l        d5,(a3)+
    move.l        d5,(a3)+
    move.l        d5,(a3)+
    move.l        d5,(a3)+

    dbra          d7,.nextline

    ; Set up pointers
    lea           ButtonMaskTemp,a2      ; a2 = mask source
    lea           NonDisplayScreen,a1          ; destination

    lea           ButtonMaskTemp,a2      ; re-set (belt-and-braces)

    ; Calculate destination pixel address
    mulu          #SCREEN_STRIDE,d1
    move.w        d0,d2
    asr.w         #3,d2
    add.w         d2,d1
    add.l         d1,a1

    ; Prepare shift and minterm for masked blit
    and.w         #$f,d0
    ror.w         #4,d0
    move.w        d0,d1
    or.w          #$fca,d0               ; minterm $fca = A&B | ~A&C

    WAITBLIT
    move.w        d0,BLTCON0(a6)
    move.w        d1,BLTCON1(a6)
    move.l        #-1,BLTAFWM(a6)
    move.l        a2,BLTAPT(a6)          ; A = mask
    move.l        a0,BLTBPT(a6)          ; B = button graphic
    move.l        a1,BLTCPT(a6)          ; C = screen background
    move.l        a1,BLTDPT(a6)          ; D = output
    move.w        #0,BLTAMOD(a6)
    move.w        #0,BLTBMOD(a6)
    move.w        #BUTTON_BLT_MOD,BLTCMOD(a6)
    move.w        #BUTTON_BLT_MOD,BLTDMOD(a6)
    move.w        #BUTTON_BLT_SIZE,BLTSIZE(a6)

    POPM          d0-d2
    rts


;==============================================================================
; DrawActor  -  Blit a moving actor tile onto DisplayScreen with shift-aware mask
;
; Used for actors that are mid-movement (XDec or YDec non-zero).  The actor's
; pixel position is computed from PrevX/Y + XDec/YDec (smooth animation position).
;
; Two blit variants based on the X sub-pixel shift:
;   shift >= 8 (fat blit): 3-word wide blit with $ffff0000 first-word mask
;   shift <  8 (thin blit): 2-word wide blit with all-ones mask
;
; The distinction ensures the blitter does not read/write beyond the intended
; area when the sprite straddles a word boundary awkwardly.
;
; On entry:
;   a3 = actor structure pointer (for PrevX, PrevY, XDec, YDec, SpriteOffset)
;   a5 = Variables base (for TilesetPtr)
;   a6 = $dff000
;==============================================================================

DrawActor:
    PUSHMOST

    ; Calculate pixel position from previous tile + sub-tile decimal offset
    move.w        Actor_PrevX(a3),d0
    mulu          #24,d0
    add.w         Actor_XDec(a3),d0      ; d0 = X pixels (tile position + animation offset)

    move.w        Actor_PrevY(a3),d1
    mulu          #24,d1
    add.w         Actor_YDec(a3),d1      ; d1 = Y pixels

    lea           DisplayScreen,a1        ; destination: static display buffer
    move.w        Actor_SpriteOffset(a3),d2  ; d2 = tile index

    ; Source pointers
    move.l        TilesetPtr(a5),a0
    lea           TileMask,a2

    mulu          #TILE_SIZE,d2
    add.w         d2,a0                  ; a0 -> tile graphic data
    add.w         d2,a2                  ; a2 -> tile mask data

    ; Destination address in DisplayScreen
    mulu          #SCREEN_STRIDE,d1
    move.w        d0,d2
    asr.w         #3,d2                  ; byte column
    add.w         d2,d1
    add.l         d1,a1

    ; Calculate shift: X mod 16
    and.w         #$f,d0

    cmp.w         #8,d0                  ; compare shift with 8
    bcs           .thin                  ; shift < 8: thin (2-word) blit

    ; --- Fat blit (shift >= 8): sprite overflows into 3 words ---
    ror.w         #4,d0                  ; pack shift into BLTCON0 shift field
    move.w        d0,d1
    or.w          #$fca,d0               ; minterm $fca = A&B | ~A&C

    WAITBLIT
    move.w        d0,BLTCON0(a6)
    move.w        d1,BLTCON1(a6)
    move.l        #$ffff0000,BLTAFWM(a6) ; mask: first word only, skip last (guard)
    move.l        a2,BLTAPT(a6)
    move.l        a0,BLTBPT(a6)
    move.l        a1,BLTCPT(a6)
    move.l        a1,BLTDPT(a6)
    move.w        #-2,BLTAMOD(a6)        ; source mod: -2 (3-word blit source width = 6)
    move.w        #-2,BLTBMOD(a6)
    move.w        #TILE_BLT_MOD-2,BLTCMOD(a6)
    move.w        #TILE_BLT_MOD-2,BLTDMOD(a6)
    move.w        #TILE_BLT_SIZE+1,BLTSIZE(a6) ; +1 word for the third word

    POPMOST
    rts

.thin
    ; --- Thin blit (shift < 8): sprite fits in 2 words ---
    ror.w         #4,d0
    move.w        d0,d1
    or.w          #$fca,d0

    WAITBLIT
    move.w        d0,BLTCON0(a6)
    move.w        d1,BLTCON1(a6)
    move.l        #$ffffffff,BLTAFWM(a6) ; all bits valid
    move.l        a2,BLTAPT(a6)
    move.l        a0,BLTBPT(a6)
    move.l        a1,BLTCPT(a6)
    move.l        a1,BLTDPT(a6)
    move.w        #0,BLTAMOD(a6)
    move.w        #0,BLTBMOD(a6)
    move.w        #TILE_BLT_MOD,BLTCMOD(a6)
    move.w        #TILE_BLT_MOD,BLTDMOD(a6)
    move.w        #TILE_BLT_SIZE,BLTSIZE(a6)

    POPMOST
    rts


;==============================================================================
; DrawInitialPlayers  -  Display both players at their starting positions
;
; Called from DrawMap after actors are drawn, to show both players at the
; start of a level.
;
; The active player (Status=1) is shown via hardware sprites (ShowSprite).
; The frozen player (Status=2) is shown as a static blitted sprite using
; the same DrawPlayerFrozen function called during player switching.
;==============================================================================

DrawInitialPlayers:
    ; Check Molly (PlayerPtrs+4)
    move.l      PlayerPtrs+4(a5),a4
    tst.w       Player_Status(a4)
    beq         .check_millie             ; skip if inactive (0)

    cmp.w       #1,Player_Status(a4)
    beq         .molly_active
    ; Molly is frozen (Status=2) - draw as static blit using DrawPlayerFrozen
    bsr         DrawPlayerFrozen
    bra         .check_millie

.molly_active
    moveq       #0,d0                      ; d0 = animation frame (idle)
    bsr         ShowSprite                 ; draw active player via hardware sprites

.check_millie
    ; Check Millie (PlayerPtrs+0)
    move.l      PlayerPtrs(a5),a4
    tst.w       Player_Status(a4)
    beq         .init_done                ; skip if inactive (0)

    cmp.w       #1,Player_Status(a4)
    beq         .millie_active
    ; Millie is frozen (Status=2) - draw as static blit using DrawPlayerFrozen
    bsr         DrawPlayerFrozen
    bra         .init_done

.millie_active
    moveq       #0,d0                      ; d0 = animation frame (idle)
    bsr         ShowSprite                 ; draw active player via hardware sprites

.init_done
    rts


;==============================================================================
; LevelIntroSetup  -  Initialise the level-start star animation
;
; Called from DrawMap immediately after DrawInitialPlayers.  Sets up the intro
; star state so ActionIntro can run each VBlank:
;
;   - Reads Molly's start tile from the Molly player struct (Player_X/Y).
;   - Determines the opposite corner:
;       Molly left  (X < 7)  → star starts from right edge (X = 13)
;       Molly right (X >= 7) → star starts from left  edge (X =  0)
;       Molly top   (Y < 5)  → star starts from bottom    (Y =  8)
;       Molly bottom(Y >= 5) → star starts from top       (Y =  0)
;   - Clears the trail particle pool (all Life = 0).
;   - Hides the hardware player sprites (SpritePtrs → NullSprite, copper patched).
;   - Draws the initial large star at the starting corner.
;   - Sets ActionStatus = ACTION_INTRO.
;
; On entry:  a5, a6 as usual.
;==============================================================================

LevelIntroSetup:
    PUSHALL

    ; --- Get Mille's tile position ---
    lea         Millie(a5),a4
    move.w      Player_X(a4),d0         ; d0 = Molly tile X
    move.w      Player_Y(a4),d1         ; d1 = Molly tile Y

    move.w      d0,IntroTargX(a5)
    move.w      d1,IntroTargY(a5)

    ; --- Compute starting corner (opposite of Millie's quadrant) ---
    ; Start X: right edge if Millie is left (X<7), left edge if Millie is right (X>=7)
    moveq       #0,d2                   ; default: left edge
    cmp.w       #7,d0
    bge         .startx_done            ; Millie on right half → start at left (0)
    move.w      #WALL_PAPER_WIDTH-1,d2  ; Millie on left  half → start at right (13)
.startx_done
    move.w      d2,IntroStarX(a5)

    ; Start Y: bottom if Millie is top (Y<5), top if Molly is bottom (Y>=5)
    moveq       #0,d3                   ; default: top edge
    cmp.w       #5,d1
    bge         .starty_done            ; Millie on bottom half → start at top (0)
    move.w      #WALL_PAPER_HEIGHT-1,d3 ; Millie on top    half → start at bottom (8)
.starty_done
    move.w      d3,IntroStarY(a5)

    ; --- Initialise timing / state ---
    move.w      #INTRO_STEP_TICKS,IntroTick(a5)  ; countdown; first step fires after this many frames
    clr.w       IntroDone(a5)
    clr.w       IntroWriteIdx(a5)

    ; --- Clear trail particle pool ---
    lea         IntroTrailLife(a5),a0
    moveq       #INTRO_TRAIL_MAX-1,d7
.clear_trail
    clr.w       (a0)+
    dbra        d7,.clear_trail

    ; --- Hide hardware player sprites: point all four SpritePtrs to NullSprite ---
    move.l      #NullSprite,d4          ; d4 = NullSprite address (preserved across loop)
    move.l      d4,SpritePtrs(a5)
    move.l      d4,SpritePtrs+4(a5)
    move.l      d4,SpritePtrs+8(a5)
    move.l      d4,SpritePtrs+12(a5)

    ; Patch the copper list sprite entries to NullSprite
    lea         cpSprites,a0
    lea         SpritePtrs(a5),a1
    moveq       #4-1,d7
.patch_copper
    move.l      (a1)+,d0
    move.w      d0,6(a0)                ; SPRxPTL
    swap        d0
    move.w      d0,2(a0)                ; SPRxPTH
    add.l       #8,a0                   ; next copper sprite entry (8 bytes per entry pair)
    dbra        d7,.patch_copper

    ; --- Draw initial large star at starting corner ---
    move.w      IntroStarX(a5),d0
    mulu        #24,d0                  ; pixel X
    move.w      IntroStarY(a5),d1
    mulu        #24,d1                  ; pixel Y
    move.w      #SPRITE_STAR_LARGE,d2
    bsr         DrawSprite

    ; --- Enter intro action state ---
    move.w      #ACTION_INTRO,ActionStatus(a5)

    POPALL
    rts


;==============================================================================
; PasteTile  -  Blit a tile from TileSet onto a screen buffer with masking
;
; The primary transparent tile blit routine.  Used for:
;   - DrawLadders (ladder tiles with transparency)
;   - DrawStaticActors (actor tiles pasted onto DisplayScreen)
;   - ActorDrawStatic (individual actor redraw)
;
; Uses minterm $fca (A&B | ~A&C):
;   A = TileMask  - selects which pixels to show from the tile
;   B = TileSet   - the tile graphic data
;   C = screen    - existing screen content (background preserved where A=0)
;   D = screen    - output
;
; On entry:
;   d0 = X pixel position
;   d1 = Y pixel position
;   d2 = tile index (0..TILESET_COUNT-1)
;   a1 = pointer to screen buffer (NonDisplayScreen or DisplayScreen)
;   a5 = Variables base (for TilesetPtr)
;   a6 = $dff000
;==============================================================================

PasteTile:
    PUSHM         d0-d2

    move.l        TilesetPtr(a5),a0      ; source: tile set
    lea           TileMask,a2            ; mask source

    mulu          #TILE_SIZE,d2
    add.w         d2,a0                  ; a0 -> selected tile graphic
    add.w         d2,a2                  ; a2 -> selected tile mask

    ; Destination address in screen buffer
    mulu          #SCREEN_STRIDE,d1
    move.w        d0,d2
    asr.w         #3,d2                  ; byte column = X / 8
    add.w         d2,d1
    add.l         d1,a1                  ; a1 -> destination pixel

    ; Shift: X mod 16
    and.w         #$f,d0
    ror.w         #4,d0                  ; pack into BLTCON0 shift field
    move.w        d0,d1
    or.w          #$fca,d0               ; minterm $fca = masked copy

    WAITBLIT
    move.w        d0,BLTCON0(a6)
    move.w        d1,BLTCON1(a6)
    move.l        #-1,BLTAFWM(a6)        ; all bits valid in A
    move.l        a2,BLTAPT(a6)          ; A = tile mask
    move.l        a0,BLTBPT(a6)          ; B = tile graphic
    move.l        a1,BLTCPT(a6)          ; C = current screen content
    move.l        a1,BLTDPT(a6)          ; D = output
    move.w        #0,BLTAMOD(a6)         ; source (tile) modulo: 0 (tight packing)
    move.w        #0,BLTBMOD(a6)
    move.w        #TILE_BLT_MOD,BLTCMOD(a6)  ; screen modulo
    move.w        #TILE_BLT_MOD,BLTDMOD(a6)
    move.w        #TILE_BLT_SIZE,BLTSIZE(a6)

    POPM          d0-d2
    rts


;==============================================================================
; WipeBlitBlack  -  Zero-fill one tile on DisplayScreen (black wipe step)
;
; Zero-fills the 24x24-pixel tile area at the given tile coordinates using
; the blitter.  Uses minterm $0A (~A & C): guard bits outside the 24-pixel
; tile boundary are preserved (D = C); pixels inside are cleared to 0 (black).
;
; A is constant $FFFF (USEA=0, BLTADAT=$FFFF), gated per-word by
; BLTAFWM/BLTALWM to restrict the clear to the 24-pixel tile width.
;
; On entry:
;   d0 = tile X (0..13)
;   d1 = tile Y (0..8)
;   a5 = Variables base
;   a6 = $dff000
;==============================================================================

WipeBlitBlack:
    PUSHALL

    lea         DisplayScreen,a1

    mulu        #24,d0                  ; pixel X
    mulu        #24,d1                  ; pixel Y

    mulu        #SCREEN_STRIDE,d1
    move.w      d0,d2
    asr.w       #3,d2                   ; byte column = X / 8
    add.w       d2,d1
    add.l       d1,a1                   ; a1 -> destination in DisplayScreen

    move.l      #$ffffff00,d1           ; mask: BLTAFWM=$FFFF, BLTALWM=$FF00 (shift=0)
    and.w       #$f,d0
    beq         .blit
    move.l      #$00ffffff,d1           ; mask: BLTAFWM=$00FF, BLTALWM=$FFFF (shift=8)

.blit
    WAITBLIT
    move.l      #$030a0000,BLTCON0(a6) ; USEC|USED, LF=$0A (~A&C), shift=0, BLTCON1=0
    move.l      d1,BLTAFWM(a6)         ; BLTAFWM + BLTALWM word masks
    move.w      #-1,BLTADAT(a6)        ; A = constant $FFFF (gated by BLTAFWM/BLTALWM)
    move.w      #0,BLTAMOD(a6)         ; A modulo = 0 (constant, no DMA advance)
    move.l      a1,BLTCPT(a6)          ; C = DisplayScreen (guard bits preserved)
    move.l      a1,BLTDPT(a6)          ; D = DisplayScreen (output)
    move.w      #TILE_BLT_MOD,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE,BLTSIZE(a6)

    POPALL
    rts


;==============================================================================
; WipeBlitWhite  -  One-fill one tile on DisplayScreen (white wipe step)
;
; One-fills the 24x24-pixel tile area at the given tile coordinates using
; the blitter.  Uses minterm $FA (A|C): guard bits outside the 24-pixel
; tile boundary are preserved (D = C); pixels inside are set to 1 (white).
;
; A is constant $FFFF (USEA=0, BLTADAT=$FFFF), gated per-word by
; BLTAFWM/BLTALWM to restrict the fill to the 24-pixel tile width.
;
; On entry:
;   d0 = tile X (0..13)
;   d1 = tile Y (0..8)
;   a5 = Variables base
;   a6 = $dff000
;==============================================================================

WipeBlitWhite:
    PUSHALL

    lea         DisplayScreen,a1

    mulu        #24,d0                  ; pixel X
    mulu        #24,d1                  ; pixel Y

    mulu        #SCREEN_STRIDE,d1
    move.w      d0,d2
    asr.w       #3,d2                   ; byte column = X / 8
    add.w       d2,d1
    add.l       d1,a1                   ; a1 -> destination in DisplayScreen

    move.l      #$ffffff00,d1           ; mask: BLTAFWM=$FFFF, BLTALWM=$FF00 (shift=0)
    and.w       #$f,d0
    beq         .blit
    move.l      #$00ffffff,d1           ; mask: BLTAFWM=$00FF, BLTALWM=$FFFF (shift=8)

.blit
    WAITBLIT
    move.l      #$03fa0000,BLTCON0(a6) ; USEC|USED, LF=$FA (A|C), shift=0, BLTCON1=0
    move.l      d1,BLTAFWM(a6)         ; BLTAFWM + BLTALWM word masks
    move.w      #-1,BLTADAT(a6)        ; A = constant $FFFF (gated by BLTAFWM/BLTALWM)
    move.w      #0,BLTAMOD(a6)         ; A modulo = 0 (constant, no DMA advance)
    move.l      a1,BLTCPT(a6)          ; C = DisplayScreen (guard bits preserved)
    move.l      a1,BLTDPT(a6)          ; D = DisplayScreen (output)
    move.w      #TILE_BLT_MOD,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE,BLTSIZE(a6)

    POPALL
    rts


;==============================================================================
; Level Wipe Transition  -  Screen wipe effect at end of each level
;
;
; LevelTransitionRun  - states 3/4/5/6 handler, called every VBlank from
;                       GameStatusRun.  Dispatches on GameStatus:
;                       LEVEL_INIT   : setup; first VBlank → LEVEL_WIPE.
;                       LEVEL_WIPE  : blits WIPE_SPEED tiles black per frame;
;                                     when done sets WipeHoldTick, → LEVEL_HOLD.
;                       LEVEL_HOLD  : counts down WipeHoldTick; calls
;                                     LevelRevealSetup when zero, → LEVEL_REVEAL.
;                       LEVEL_REVEAL: copies WIPE_SPEED tiles from NonDisplayScreen;
;                                     when done calls DrawStaticActors, → GameRun.
;
; LevelRevealSetup    - called from LevelTransitionRun when hold expires.
;                       Builds next level into NonDisplayScreen, reverses WipeTileX/Y,
;                       and advances to LEVEL_REVEAL (5).
;
; Fill routines   - each fills WipeTileX and WipeTileY with 126 tile coords
;                   (WALL_PAPER_SIZE = 14x9) in the desired visual order.
;
; WipeOppositeTable - byte lookup: given a pattern index, returns the index of
;                     its directional inverse for use by a future reveal effect.
;==============================================================================


;==============================================================================
; LevelSetup  -  Initialise and start the level transition
;
; Called from LevelTransitionRun for the LEVEL_INIT phase, immediately after LevelId is incremented.
;
; Actions:
;   1. Reset WipeTilesDone = 0.
;   2. Pick a random wipe pattern using RANDOMWORD and store in WipePattern.
;   3. Call the appropriate WipeFill routine to build WipeTileX/Y arrays.
;   4. Hide both hardware player sprites (set SpritePtrs to NullSprite).
;
; On entry: a5 = Variables base, a6 = CUSTOM.
;==============================================================================

LevelSetup:
    PUSHALL

    ; Initialise wipe counter (WipeHoldTick is set when wipe completes)
    clr.w       WipeTilesDone(a5)

    ; Pick random pattern (0..NUM_WIPE_PATTERNS-1)
    RANDOMWORD                          ; d0.w = pseudo-random value
    and.w       #NUM_WIPE_PATTERNS-1,d0 ; mask to pattern range (power of 2)
    move.w      d0,WipePattern(a5)

    ; Dispatch to the appropriate fill routine via absolute pointer table
    lsl.w       #2,d0                   ; d0 = pattern * 4 (longword table index)
    lea         .fill_ptrs(pc),a0
    move.l      (a0,d0.w),a0            ; a0 = fill routine address
    jsr         (a0)                    ; fill WipeTileX and WipeTileY arrays

    ; Hide hardware player sprites (point all four SpritePtrs to NullSprite)
    move.l      #NullSprite,d0
    move.l      d0,SpritePtrs(a5)
    move.l      d0,SpritePtrs+4(a5)
    move.l      d0,SpritePtrs+8(a5)
    move.l      d0,SpritePtrs+12(a5)
    lea         cpSprites,a0
    lea         SpritePtrs(a5),a1
    moveq       #4-1,d7
.patch_sprites
    move.l      (a1)+,d0
    move.w      d0,6(a0)                ; SPRxPTL
    swap        d0
    move.w      d0,2(a0)                ; SPRxPTH
    add.l       #8,a0                   ; next copper sprite entry
    dbra        d7,.patch_sprites

    POPALL
    rts

; Absolute address table - one longword per wipe pattern (8 entries)
.fill_ptrs
    dc.l        WipeFillTopBottom
    dc.l        WipeFillBottomTop
    dc.l        WipeFillLeftRight
    dc.l        WipeFillRightLeft
    dc.l        WipeFillDiagTLBR
    dc.l        WipeFillDiagBRTL
    dc.l        WipeFillCenterOut
    dc.l        WipeFillCenterIn


;==============================================================================
; LevelTransitionRun  -  Per-frame level transition handler
;
; Called every VBlank from GameStatusRun for states 3, 4, and 5.
; Dispatches to the appropriate phase based on GameStatus.
; No player input is processed during any transition state.
;
; LEVEL_INIT (3) - first VBlank after LevelSetup
;
; LEVEL_WIPE (4) - blit WIPE_SPEED tiles black per frame until all done,
;                  then set WipeHoldTick and advance to LEVEL_HOLD (4).
;
; LEVEL_HOLD (5) - count down WipeHoldTick each frame; when zero call
;                  LevelRevealSetup which builds the new level and advances
;                  to LEVEL_REVEAL (5).
;
; LEVEL_REVEAL (6) - copy WIPE_SPEED tiles per frame from NonDisplayScreen to
;                    DisplayScreen (reverse-wipe).  When done, call
;                    DrawStaticActors and return to GameRun (2).
;==============================================================================

LevelTransitionRun:
    move.w      GameStatus(a5),d5       ; d5 = current transition state (3/4/5)
    cmp.w       #LEVEL_WIPE,d5
    beq         .wipe_phase
    cmp.w       #LEVEL_HOLD,d5
    beq         .hold_phase
    cmp.w       #LEVEL_REVEAL,d5
    beq         .reveal_phase

    ; -----------------------------------------------------------------------
    ; LEVEL_INIT phase: setup for level transition effect
    ; -----------------------------------------------------------------------
    bsr         LevelSetup
    move.w      #LEVEL_WIPE,GameStatus(a5)
    rts

.wipe_phase
    ; -----------------------------------------------------------------------
    ; LEVEL_WIPE phase: blit WIPE_SPEED tiles black this frame
    ; -----------------------------------------------------------------------
    move.w      WipeTilesDone(a5),d7
    cmp.w       #WALL_PAPER_SIZE,d7
    bge         .wipe_done

    moveq       #WIPE_SPEED-1,d6
.wipe_loop
    cmp.w       #WALL_PAPER_SIZE,d7
    bge         .wipe_blit_done

    clr.l       d0
    lea         WipeTileX(a5),a0
    move.b      (a0,d7.w),d0            ; d0 = tile X (0..13)
    clr.l       d1
    lea         WipeTileY(a5),a0
    move.b      (a0,d7.w),d1            ; d1 = tile Y (0..8)

    bsr         WipeBlitBlack           ; zero-fill this tile (black)

    addq.w      #1,d7
    dbra        d6,.wipe_loop

.wipe_blit_done
    move.w      d7,WipeTilesDone(a5)
    rts

.wipe_done
    ; All tiles blitted black - start hold countdown, advance to LEVEL_HOLD
    move.w      #WIPE_HOLD_TICKS,WipeHoldTick(a5)
    move.w      #LEVEL_HOLD,GameStatus(a5)
    rts

    ; -----------------------------------------------------------------------
    ; LEVEL_HOLD phase: count down hold ticks, then trigger reveal setup
    ; -----------------------------------------------------------------------
.hold_phase
    move.w      WipeHoldTick(a5),d0
    beq         .hold_done
    subq.w      #1,d0
    move.w      d0,WipeHoldTick(a5)
    rts

.hold_done
    ; Hold complete - build next level and set up the reveal
    bsr         LevelRevealSetup        ; sets LEVEL_REVEAL and primes WipeTileX/Y
  ;  bsr LevelSetup
    move.w      #LEVEL_REVEAL,GameStatus(a5)
    rts

    ; -----------------------------------------------------------------------
    ; LEVEL_REVEAL phase: copy WIPE_SPEED tiles from NonDisplayScreen to DisplayScreen
    ; -----------------------------------------------------------------------
.reveal_phase
    move.w      WipeTilesDone(a5),d7
    cmp.w       #WALL_PAPER_SIZE,d7
    bge         .reveal_done

    moveq       #WIPE_SPEED-1,d6
.reveal_loop
    cmp.w       #WALL_PAPER_SIZE,d7
    bge         .reveal_blit_done

    clr.l       d0
    lea         WipeTileX(a5),a0
    move.b      (a0,d7.w),d0            ; d0 = tile X (0..13)
    clr.l       d1
    lea         WipeTileY(a5),a0
    move.b      (a0,d7.w),d1            ; d1 = tile Y (0..8)

    bsr         RestoreBackgroundTile        ; copy tile from NonDisplayScreen -> DisplayScreen

    addq.w      #1,d7
    dbra        d6,.reveal_loop

.reveal_blit_done
    move.w      d7,WipeTilesDone(a5)
    rts

.reveal_done
    ; All tiles revealed - restore actor tiles, initialize Level and resume gameplay
    bsr         DrawPlayersAndActors
    bsr         LevelIntroSetup

    move.w      #GAME_RUN,GameStatus(a5)       ; return to GameRun (state 2)
    rts


;==============================================================================
; WipeFillTopBottom  -  Fill wipe order: row by row, top to bottom
;==============================================================================

WipeFillTopBottom:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2                      ; write index (0..125)
    moveq       #0,d1                   ; y = 0
.row
    moveq       #0,d0                   ; x = 0
.col
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
    addq.w      #1,d0
    cmp.w       #WALL_PAPER_WIDTH,d0
    blt         .col
    addq.w      #1,d1
    cmp.w       #WALL_PAPER_HEIGHT,d1
    blt         .row
    rts


;==============================================================================
; WipeFillBottomTop  -  Fill wipe order: row by row, bottom to top
;==============================================================================

WipeFillBottomTop:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2
    moveq       #WALL_PAPER_HEIGHT-1,d1 ; y = 8, count down to 0
.row
    moveq       #0,d0
.col
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
    addq.w      #1,d0
    cmp.w       #WALL_PAPER_WIDTH,d0
    blt         .col
    subq.w      #1,d1
    bpl         .row                    ; loop while y >= 0
    rts


;==============================================================================
; WipeFillLeftRight  -  Fill wipe order: column by column, left to right
;==============================================================================

WipeFillLeftRight:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2
    moveq       #0,d0                   ; x = 0
.col
    moveq       #0,d1                   ; y = 0
.row
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
    addq.w      #1,d1
    cmp.w       #WALL_PAPER_HEIGHT,d1
    blt         .row
    addq.w      #1,d0
    cmp.w       #WALL_PAPER_WIDTH,d0
    blt         .col
    rts


;==============================================================================
; WipeFillRightLeft  -  Fill wipe order: column by column, right to left
;==============================================================================

WipeFillRightLeft:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2
    moveq       #WALL_PAPER_WIDTH-1,d0  ; x = 13, count down to 0
.col
    moveq       #0,d1
.row
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
    addq.w      #1,d1
    cmp.w       #WALL_PAPER_HEIGHT,d1
    blt         .row
    subq.w      #1,d0
    bpl         .col                    ; loop while x >= 0
    rts


;==============================================================================
; WipeFillDiagTLBR  -  Fill wipe order: diagonal stripes, top-left to bottom-right
;
; Iterates over diagonals where x+y = constant (d = 0..21).
; For each diagonal, emits all tiles (x,y) where x = d-y, 0<=x<=13, 0<=y<=8.
; 22 diagonals cover all 14x9 = 126 tiles exactly.
;==============================================================================

WipeFillDiagTLBR:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2                      ; write index
    moveq       #0,d3                   ; diagonal d = 0..21
.diag
    moveq       #0,d1                   ; y = 0
.scan
    move.w      d3,d0
    sub.w       d1,d0                   ; x = d - y
    blt         .next_y                 ; x < 0: y exceeds diagonal start
    cmp.w       #WALL_PAPER_WIDTH,d0    ; x >= 14: diagonal not yet reached
    bge         .next_y
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
.next_y
    addq.w      #1,d1
    cmp.w       #WALL_PAPER_HEIGHT,d1
    blt         .scan
    addq.w      #1,d3
    cmp.w       #WALL_PAPER_WIDTH+WALL_PAPER_HEIGHT-1,d3  ; while d < 22
    blt         .diag
    rts


;==============================================================================
; WipeFillDiagBRTL  -  Fill wipe order: diagonal stripes, bottom-right to top-left
;==============================================================================

WipeFillDiagBRTL:
    bsr         WipeFillDiagTLBR
    bsr         WipeReverseBuffer
    rts


;==============================================================================
; WipeFillCenterOut  -  Fill wipe order: outward from centre by Chebyshev distance
;
; Emits tiles sorted ascending by max(|x-WIPE_CENTER_X|, |y-WIPE_CENTER_Y|).
; Distance levels 0..7 (WIPE_MAX_DIST) cover the full 14x9 grid.
;==============================================================================

WipeFillCenterOut:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2                      ; write index
    moveq       #0,d5                   ; distance level = 0
.dist_loop
    moveq       #0,d1                   ; y = 0
.y_loop
    moveq       #0,d0                   ; x = 0
.x_loop
    ; Chebyshev distance = max(|x-CX|, |y-CY|)
    move.w      d0,d3
    sub.w       #WIPE_CENTER_X,d3
    bge         .x_abs
    neg.w       d3
.x_abs
    move.w      d1,d4
    sub.w       #WIPE_CENTER_Y,d4
    bge         .y_abs
    neg.w       d4
.y_abs
    cmp.w       d4,d3
    bge         .have_dist              ; d3 >= d4: d3 is the max
    move.w      d4,d3                   ; d4 > d3: use d4
.have_dist
    cmp.w       d5,d3
    bne         .skip_tile
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
.skip_tile
    addq.w      #1,d0
    cmp.w       #WALL_PAPER_WIDTH,d0
    blt         .x_loop
    addq.w      #1,d1
    cmp.w       #WALL_PAPER_HEIGHT,d1
    blt         .y_loop
    addq.w      #1,d5
    cmp.w       #WIPE_MAX_DIST+1,d5     ; while distance < 8
    blt         .dist_loop
    rts


;==============================================================================
; WipeFillCenterIn  -  Fill wipe order: inward from edges to centre
;==============================================================================

WipeFillCenterIn:
    bsr         WipeFillCenterOut
    bsr         WipeReverseBuffer
    rts


;==============================================================================
; WipeReverseBuffer  -  Reverse WipeTileX and WipeTileY arrays in place
;
; Two-pointer swap: lo starts at 0, hi starts at WALL_PAPER_SIZE-1.
; Both arrays are swapped in lockstep so they stay in sync.
;==============================================================================

WipeReverseBuffer:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d0                      ; lo index = 0
    move.w      #WALL_PAPER_SIZE-1,d1   ; hi index = 125
.rev_loop
    cmp.w       d1,d0
    bge         .rev_done

    ; reverse TileX coordinates
    move.b      (a0,d0.w),d2
    move.b      (a0,d1.w),(a0,d0.w)
    move.b      d2,(a0,d1.w)
    ; reverse TileY coordinates
    move.b      (a1,d0.w),d2
    move.b      (a1,d1.w),(a1,d0.w)
    move.b      d2,(a1,d1.w)

    addq.w      #1,d0
    subq.w      #1,d1
    bra         .rev_loop
.rev_done
    rts

;==============================================================================
; LevelRevealSetup  -  Build the new level and arm the reveal pass
;
; Called from LevelTransitionRun when the LEVEL_HOLD countdown reaches zero.
;
; Builds the new level's background into NonDisplayScreen only (CopySaveToStatic,
; DrawStaticActors, and CopyStaticToBuffers are skipped so DisplayScreen stays
; black from the completed wipe).  Then reverses WipeTileX/Y to give the
; directional opposite traversal order for the reveal, resets WipeTilesDone,
; and advances GameStatus to LEVEL_REVEAL.
;
; On entry: a5 = Variables base, a6 = CUSTOM.
;==============================================================================

LevelRevealSetup:
    PUSHALL

    ; draw the new map into the NonDisplayScreen
    bsr         DrawMap 

    ; Initialise tiles done back to 0
    clr.w       WipeTilesDone(a5)

    ; take the Wipe Pattern (used to clear the last level) to determine
    ; the Reveal pattern - ie the opposite effect
	moveq  #0,d0
	move.b WipePattern(a5),d0
	lea    WipeOppositeTable(pc),a0
	move.b (a0,d0.w),d0              ; d0 = opposite pattern index

    ; Dispatch to the appropriate fill routine via absolute pointer table
    lsl.w       #2,d0                   ; d0 = pattern * 4 (longword table index)
    lea         .fill_ptrs(pc),a0
    move.l      (a0,d0.w),a0            ; a0 = fill routine address
    jsr         (a0)                    ; fill WipeTileX and WipeTileY arrays

    POPALL
    rts

    

;==============================================================================
; WipeOppositeTable  -  Maps each wipe pattern to its directional inverse
;
; Index: pattern number (0..NUM_WIPE_PATTERNS-1)
; Value: index of the directional opposite
;
; Usage example:
;   moveq  #0,d0
;   move.b WipePattern(a5),d0
;   lea    WipeOppositeTable(pc),a0
;   move.b (a0,d0.w),d0              ; d0 = opposite pattern index
;==============================================================================

WipeOppositeTable:
    dc.b    WIPE_BOTTOM_TOP     ; opposite of WIPE_TOP_BOTTOM  (0)
    dc.b    WIPE_TOP_BOTTOM     ; opposite of WIPE_BOTTOM_TOP  (1)
    dc.b    WIPE_RIGHT_LEFT     ; opposite of WIPE_LEFT_RIGHT  (2)
    dc.b    WIPE_LEFT_RIGHT     ; opposite of WIPE_RIGHT_LEFT  (3)
    dc.b    WIPE_DIAG_BRTL      ; opposite of WIPE_DIAG_TLBR   (4)
    dc.b    WIPE_DIAG_TLBR      ; opposite of WIPE_DIAG_BRTL   (5)
    dc.b    WIPE_CENTER_IN      ; opposite of WIPE_CENTER_OUT  (6)
    dc.b    WIPE_CENTER_OUT     ; opposite of WIPE_CENTER_IN   (7)
    even                        ; ensure word-aligned for following code