
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; actors.asm  -  Actor Initialisation, Management and Drawing
;==============================================================================
;
; An "actor" is any game object that occupies a tile cell and can move, be
; killed, or animate.  This includes:
;   - Enemy falling  (BLOCK_ENEMYFALL  = gravity-affected enemy)
;   - Enemy floating (BLOCK_ENEMYFLOAT = gravity-immune enemy)
;   - Pushable block (BLOCK_PUSH       = can be slid by the player)
;   - Dirt block     (BLOCK_DIRT       = player can walk through / destroy)
;   - Millie / Molly (player characters - special initialisation path)
;
; Actor data lives in the flat Actors[] array (Actor_Sizeof bytes per slot).
; The ActorList[] array holds pointers into Actors[], sorted by Y position
; (largest Y drawn last = appears on top).
;
; Register convention:
;   a3 = pointer to the current actor structure
;   a5 = Variables base pointer
;
;==============================================================================


;==============================================================================
; InitGameObjects  -  Scan the game map and create an actor for each object
;
; Called by LevelInit after the maps are built.  Iterates over every cell of
; GameMap (WALL_PAPER_WIDTH x WALL_PAPER_HEIGHT = 14 x 9 = 126 cells) and
; calls InitObject for non-empty, non-solid cells.
;
; After all actors are created, SortActors is called to order the ActorList
; by Y position so DrawStaticActors renders them back-to-front.
;
; Entry:  a5 = Variables base
; Exit:   ActorCount(a5) = number of initialised actors
;         ActorList(a5)  = sorted array of actor pointers
;==============================================================================

InitGameObjects:
    clr.w       ActorCount(a5)             ; reset actor count to zero

    ; Reset the actor pointer list write cursor to the start of ActorList
    lea         ActorList(a5),a0
    move.l      a0,ActorSlotPtr(a5)

    ; Zero the entire actor pool before use
    move.l      #Actor_Sizeof*MAX_ACTORS,d7
    bsr         TurboClear                 ; clear Actor_Sizeof * MAX_ACTORS bytes

    ; Walk the GameMap and initialise an actor for each cell
    lea         GameMap(a5),a0             ; a0 -> start of live game map
    moveq       #0,d1                      ; d1 = current X (column, 0-based)
    moveq       #0,d2                      ; d2 = current Y (row, 0-based)

.nextcell
    moveq       #0,d0
    move.b      (a0)+,d0                   ; d0 = block type at current cell
    move.w      d0,d3                      ; d3 = type again (InitObject uses both)
    bsr         InitObject                 ; create actor for this block type

    addq.w      #1,d1                      ; advance to next column
    cmp.w       #WALL_PAPER_WIDTH,d1       ; end of row?
    bne         .nextcell

    moveq       #0,d1                      ; reset column to 0
    addq.w      #1,d2                      ; advance to next row
    cmp.w       #WALL_PAPER_HEIGHT,d2      ; end of map?
    bne         .nextcell

    bsr         SortActors                 ; sort ActorList by Y for correct draw order
    rts


;==============================================================================
; InitObject  -  Dispatch to the correct initialisation routine for a block type
;
; Uses JMPINDEX to jump to the appropriate Init routine based on the block type.
; Most block types create an actor; solid walls and empty spaces are ignored.
;
; On entry:
;   d0 = block type (BLOCK_xxx constant, 0-based)
;   d1 = X tile position
;   d2 = Y tile position
;   d3 = block type (duplicate, some inits use d3 to store Actor_Type)
;
; The dispatch table entries:
;   BLOCK_EMPTY      (0) -> InitDummy   (nothing to do)
;   BLOCK_LADDER     (1) -> InitDummy   (ladders are purely graphical, not actors)
;   BLOCK_ENEMYFALL  (2) -> InitEnemyFall
;   BLOCK_PUSH       (3) -> InitPushBlock
;   BLOCK_DIRT       (4) -> InitDirt
;   BLOCK_SOLID      (5) -> InitDummy
;   BLOCK_ENEMYFLOAT (6) -> InitEnemyFloat
;   BLOCK_MILLIESTART(7) -> InitMillie
;   BLOCK_MOLLYSTART (8) -> InitMolly
;==============================================================================

InitObject:
    JMPINDEX    d0                         ; computed jump on block type

.i  ; offset table
    dc.w        InitDummy-.i               ; BLOCK_EMPTY       = 0
    dc.w        InitDummy-.i               ; BLOCK_LADDER      = 1
    dc.w        InitEnemyFall-.i           ; BLOCK_ENEMYFALL   = 2
    dc.w        InitPushBlock-.i           ; BLOCK_PUSH        = 3
    dc.w        InitDirt-.i                ; BLOCK_DIRT        = 4
    dc.w        InitDummy-.i               ; BLOCK_SOLID       = 5
    dc.w        InitEnemyFloat-.i          ; BLOCK_ENEMYFLOAT  = 6
    dc.w        InitMillie-.i              ; BLOCK_MILLIESTART = 7
    dc.w        InitMolly-.i               ; BLOCK_MOLLYSTART  = 8


;==============================================================================
; InitDummy  -  No-op initialiser for block types that need no actor
;==============================================================================

InitDummy:
    rts


;==============================================================================
; InitDirt  -  Create an actor for a dirt block
;
; Dirt blocks come in 4 graphical variants depending on whether the blocks
; immediately to the left and right are also dirt (for seamless joins):
;
;   Tile variant lookup table at .add:
;     index 0 (no neighbours)   -> TILE_DIRTA + 0  = TILE_DIRTA
;     index 1 (right neighbour) -> TILE_DIRTA + 1  = TILE_DIRTB
;     index 2 (left neighbour)  -> TILE_DIRTA + 3  = TILE_DIRTD  (NOTE: .add[2]=3)
;     index 3 (both neighbours) -> TILE_DIRTA + 2  = TILE_DIRTC  (NOTE: .add[3]=2)
;
; The adjacency check uses (a0) for the CURRENT cell (after GetActorSlot advances a0)
; and offsets from the original map pointer for neighbours.  Relies on a0 still
; pointing to the current cell in GameMap at call time.
;
; Actor_Static is set to 1 - dirt blocks are drawn once into ScreenStatic
; and never animated (no need to update them each frame).
;==============================================================================

InitDirt:
    bsr         GetActorSlot               ; allocate a slot; a3 -> new actor, a0 unchanged

    ; Determine which dirt variant tile to use based on neighbours
    moveq       #0,d0
    cmp.b       #BLOCK_DIRT,(a0)           ; is the cell AFTER current also dirt (right neighbour)?
    bne         .notright
    bset        #0,d0                      ; bit 0 set = right neighbour present
.notright
    cmp.b       #BLOCK_DIRT,-2(a0)         ; is the cell TWO before current also dirt (left neighbour)?
                                           ; (a0 was advanced past the current cell by GetActorSlot)
    bne         .notleft
    bset        #1,d0                      ; bit 1 set = left neighbour present
.notleft
    ; Look up tile variant: .add maps (right|left) flags to tile index offset
    move.b      .add(pc,d0.w),d0           ; d0 = tile offset (0, 1, 2 or 3)
    add.w       #TILE_DIRTA,d0             ; d0 = final tile index
    move.w      d0,Actor_SpriteOffset(a3)  ; store tile to draw
    move.w      #1,Actor_Static(a3)        ; dirt is static (drawn once, not animated)
    rts

.add
    dc.b        0,1,3,2     ; index = (leftBit<<1 | rightBit) -> tile offset within DIRTA..DIRTD


;==============================================================================
; InitEnemyFloat  -  Create a floating enemy actor (not affected by gravity)
;
; Floating enemies begin at frame TILE_ENEMYFLOATA and are animated elsewhere.
; Actor_CanFall is NOT set (default 0 from GetActorSlot clear).
;==============================================================================

InitEnemyFloat:
    bsr         GetActorSlot
    move.w      #TILE_ENEMYFLOATA,Actor_SpriteOffset(a3)   ; floating enemy sprite
    rts


;==============================================================================
; InitEnemyFall  -  Create a falling enemy actor (subject to gravity)
;
; Falling enemies use TILE_ENEMYFALLA as their base sprite and have
; Actor_CanFall = 1 so that ActorFallAll will process them.
;==============================================================================

InitEnemyFall:
    bsr         GetActorSlot
    move.w      #TILE_ENEMYFALLA,Actor_SpriteOffset(a3)    ; falling enemy sprite
    move.w      #1,Actor_CanFall(a3)       ; subject to gravity
    rts


;==============================================================================
; InitPushBlock  -  Create a pushable block actor
;
; Push blocks display as TILE_PUSH and are affected by gravity (they fall if
; unsupported after being pushed).  They are also static (drawn once per move).
;==============================================================================

InitPushBlock:
    bsr         GetActorSlot
    move.w      #TILE_PUSH,Actor_SpriteOffset(a3)          ; push block sprite
    move.w      #1,Actor_CanFall(a3)       ; push blocks fall under gravity
    move.w      #1,Actor_Static(a3)        ; static appearance (not animated)
    rts


;==============================================================================
; InitMillie  -  Initialise the Millie player character
;
; Sets Millie's sprite base offset to 48 (Millie's frames come after Molly's
; in the RealSprites data), configures her map block IDs, then calls InitPlayer.
;
; Player_SpriteOffset = 48 means all sprite frame lookups for Millie are
; offset by 48 frames relative to the start of RealSprites.
; Player_LadderFreezeId = 97 is the frame index used when Millie is frozen
; on a ladder (the idle-on-ladder graphic for Millie).
;==============================================================================

InitMillie:
    lea         Millie(a5),a4              ; a4 -> Millie player structure
    move.w      #48,Player_SpriteOffset(a4)        ; Millie's sprite base = frame 48
    move.w      #97,Player_LadderFreezeId(a4)      ; ladder freeze frame index
    move.b      #BLOCK_MILLIESTART,Player_BlockId(a4)    ; map cell type for Millie's presence
    move.b      #BLOCK_MILLIELADDER,Player_LadderId(a4)  ; map cell type when on ladder
    bsr         InitPlayer
    rts


;==============================================================================
; InitMolly  -  Initialise the Molly player character
;
; Sets Molly's sprite base offset to 0 (Molly's frames are first in RealSprites),
; configures her map block IDs, then calls InitPlayer.
;==============================================================================

InitMolly:
    lea         Molly(a5),a4               ; a4 -> Molly player structure
    move.w      #0,Player_SpriteOffset(a4)         ; Molly's sprite base = frame 0
    move.w      #96,Player_LadderFreezeId(a4)      ; ladder freeze frame index
    move.b      #BLOCK_MOLLYSTART,Player_BlockId(a4)    ; map cell type for Molly's presence
    move.b      #BLOCK_MOLLYLADDER,Player_LadderId(a4)  ; map cell type when on ladder
    bsr         InitPlayer
    rts


;==============================================================================
; InitPlayer  -  Common player initialisation (called by InitMillie / InitMolly)
;
; Increments the PlayerCount, sets the player's starting tile position from
; d1 (X) and d2 (Y), marks the player as active (Status=1), and sets the
; initial facing direction to right (+1).
;
; Sub-tile pixel offsets (XDec/YDec) are cleared to 0 (aligned on a tile).
;
; Note: PlayerPtrs are NOT set here - they are set by LevelInit before
; InitGameObjects runs (Millie -> PlayerPtrs+0, Molly -> PlayerPtrs+4).
; The order in which Millie and Molly appear in the map determines which
; one is "active" (first initialised player gets PlayerPtrs+0).
;
; On entry:
;   a4 = player structure pointer (set by InitMillie / InitMolly)
;   d1 = starting tile X
;   d2 = starting tile Y
;==============================================================================

InitPlayer:
    addq.w      #1,PlayerCount(a5)         ; count this player as initialised
    clr.w       Player_OnLadder(a4)        ; start on ground (not on ladder)
    move.w      d1,Player_X(a4)            ; set starting tile column
    move.w      d2,Player_Y(a4)            ; set starting tile row
    move.w      #1,Player_Status(a4)       ; status = 1 (active)
    move.w      #1,Player_DirectionX(a4)   ; initial facing: right
    clr.w       Player_XDec(a4)            ; no sub-tile X offset
    clr.w       Player_YDec(a4)            ; no sub-tile Y offset

    ; Commented-out code: would draw the "frozen" idle graphic for the second
    ; player when both are initialised.  Currently not used.
.noother
    rts


;==============================================================================
; GetActorSlot  -  Allocate a new actor structure from the pool
;
; Allocates the next free Actor slot, sets its initial position and type
; fields from d1 (X), d2 (Y), d3 (type), and adds it to the ActorList.
;
; The slot index is the current ActorCount value (before incrementing).
; Actor structures are stored sequentially: &Actors[0] + index * Actor_Sizeof.
;
; Also pushes the actor pointer into ActorList via ActorSlotPtr.
;
; On entry:
;   d1 = X tile position
;   d2 = Y tile position
;   d3 = block type (stored in Actor_Type)
;   a0 = current GameMap pointer (preserved and restored)
;
; On exit:
;   a3 = pointer to the newly allocated actor structure
;   ActorCount(a5) incremented by 1
;
; Crashes to FUCK if the actor pool is full (should never happen with
; MAX_ACTORS = MAP_SIZE = 88 slots for 88 map cells).
;==============================================================================

GetActorSlot:
    move.w      ActorCount(a5),d5          ; d5 = current count (= index of new slot)
    cmp.w       #MAX_ACTORS,d5             ; pool full?
    bcc         FUCK                       ; if count >= MAX_ACTORS, fatal error

    addq.w      #1,ActorCount(a5)          ; increment actor count

    ; Calculate address of new slot: &Actors + d5 * Actor_Sizeof
    lea         Actors(a5),a3
    mulu        #Actor_Sizeof,d5
    add.l       d5,a3                      ; a3 -> new actor structure

    ; Initialise core fields
    move.w      d1,Actor_X(a3)             ; tile column
    move.w      d2,Actor_Y(a3)             ; tile row
    move.w      d3,Actor_Type(a3)          ; block type
    move.w      #1,Actor_Status(a3)        ; status = alive
    clr.w       Actor_CanFall(a3)          ; default: not subject to gravity

    ; Add pointer to sorted actor list
    PUSH        a0                         ; preserve GameMap pointer
    move.l      ActorSlotPtr(a5),a0        ; a0 -> next free slot in ActorList
    move.l      a3,(a0)+                   ; store actor pointer and advance
    move.l      a0,ActorSlotPtr(a5)        ; update write cursor
    POP         a0                         ; restore GameMap pointer
    rts


;==============================================================================
; FUCK  -  Fatal error: actor pool overflow
;
; Should never be reached in normal play (MAX_ACTORS = MAP_SIZE = 88).
; Flashes the background colour register by alternating values - a classic
; Amiga "guru meditation" indicator for debugging.
;==============================================================================

FUCK:
    move.w      d0,$dff180                 ; write d0 to COLOR00 (flash background)
    subq.w      #1,d0                      ; count down through colours
    bra         FUCK                       ; loop forever (hang)


;==============================================================================
; DrawStaticActors  -  Blit all active actors into ScreenStatic
;
; Iterates through all live actors (via the flat Actors[] array) and calls
; PasteTile to blit each actor's sprite tile onto ScreenStatic at its current
; pixel position.
;
; "Static" actors (dirt, push blocks) are drawn here during level init and
; remain until explicitly cleared by ClearStaticBlock.
; Moving actors (enemies) are also blitted here when they arrive at a new tile.
;
; On entry:
;   a5 = Variables base
;   a6 = $dff000 (needed by PasteTile's WAITBLIT macro)
;==============================================================================

DrawStaticActors:
    move.w      ActorCount(a5),d7          ; d7 = number of actors
    bne         .go
    rts                                    ; no actors - nothing to draw

.go
    lea         Actors(a5),a3              ; a3 -> first actor structure
    subq.w      #1,d7                      ; adjust for DBRA

.loop
    tst.w       Actor_Status(a3)           ; is this actor alive?
    beq         .notactive                 ; no - skip it

    ; Calculate pixel position from tile coordinates
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    mulu        #24,d0                     ; pixel X = tile_col * 24
    mulu        #24,d1                     ; pixel Y = tile_row * 24

    moveq       #0,d2
    move.w      Actor_SpriteOffset(a3),d2  ; d2 = tile index in TileSet

    lea         ScreenStatic,a1            ; destination: the static screen buffer
    bsr         PasteTile                  ; blit tile to screen

.notactive
    add.w       #Actor_Sizeof,a3           ; advance to next actor structure
    dbra        d7,.loop
    rts


;==============================================================================
; ActorsSavePos  -  Save each actor's current position as its previous position
;
; Called at the start of each action frame (from ActionIdle).  Copies Actor_X
; to Actor_PrevX and Actor_Y to Actor_PrevY for all live actors, and clears
; Actor_HasMoved so that movement detection is fresh for this frame.
;
; Uses the sorted ActorList for iteration (consistent order with rendering).
;==============================================================================

ActorsSavePos:
    move.w      ActorCount(a5),d7
    bne         .go
    rts

.go
    subq.w      #1,d7
    lea         ActorList(a5),a2           ; a2 -> sorted pointer array

.loop
    move.l      (a2)+,a3                   ; a3 -> next actor struct (via sorted list)
    move.w      Actor_X(a3),Actor_PrevX(a3)    ; save X
    move.w      Actor_Y(a3),Actor_PrevY(a3)    ; save Y
    clr.w       Actor_HasMoved(a3)             ; clear moved flag
    dbra        d7,.loop
    rts


;==============================================================================
; ClearFrozenPlayer  -  Erase the frozen (inactive) player from ScreenStatic
;
; If the frozen player has fallen since the last frame (Player_Fallen set),
; clears the tile at its previous position.  Called from ActionIdle before
; drawing the updated position.
;==============================================================================

ClearFrozenPlayer:
    PUSH        a4                         ; preserve active player pointer

    move.l      PlayerPtrs+4(a5),a4        ; a4 -> frozen (second) player struct
    tst.w       Player_Fallen(a4)          ; did the frozen player fall?
    beq         .nofall

    move.w      Player_PrevX(a4),d0        ; previous tile X
    move.w      Player_PrevY(a4),d1        ; previous tile Y
    bsr         ClearStaticBlock           ; erase old tile from ScreenStatic

.nofall
    POP         a4                         ; restore active player pointer
    rts


;==============================================================================
; ClearMovedActors  -  Erase moved actors from their previous tile positions
;
; Any actor that has Actor_HasMoved set (was repositioned this frame) needs to
; be erased from its old screen position before being redrawn at the new one.
; This is done by blitting the corresponding tile from ScreenSave over the
; old position in ScreenStatic.
;==============================================================================

ClearMovedActors:
    move.w      ActorCount(a5),d7
    bne         .go
    rts

.go
    subq.w      #1,d7
    lea         Actors(a5),a3

.loop
    tst.w       Actor_Status(a3)           ; alive?
    beq         .next
    tst.w       Actor_HasMoved(a3)         ; did it move?
    beq         .next

    ; Clear the actor's PREVIOUS screen position
    move.w      Actor_PrevX(a3),d0         ; previous tile column
    move.w      Actor_PrevY(a3),d1         ; previous tile row
    bsr         ClearStaticBlock           ; restore background at old position

.next
    add.w       #Actor_Sizeof,a3
    dbra        d7,.loop
    rts


;==============================================================================
; CleanActors  -  Remove dead actors from the ActorList and update ActorCount
;
; After players kill actors (PlayerKillActor / PlayerKillDirt), their
; Actor_Status is set to 0.  This routine compacts the ActorList by removing
; those zero-status pointers and updating ActorCount to the new live count.
;
; Uses a two-pointer approach: reads from a0, writes to a1 (both start at
; the same ActorList base; a1 only advances for live actors).
;==============================================================================

CleanActors:
    move.w      ActorCount(a5),d7
    subq.w      #1,d7
    bmi         .exit                      ; no actors at all - nothing to do

    moveq       #0,d6                      ; d6 = new live actor count
    lea         ActorList(a5),a0           ; read pointer
    move.l      a0,a1                      ; write pointer (compacted list)

.loop
    move.l      (a0)+,a3                   ; a3 -> next actor
    tst.w       Actor_Status(a3)           ; alive?
    beq         .next                      ; dead - skip (don't copy to output)

    move.l      a3,(a1)+                   ; copy live actor pointer to compacted list
    addq.w      #1,d6                      ; increment live count

.next
    dbra        d7,.loop

    move.w      d6,ActorCount(a5)          ; update count to reflect removals

.exit
    rts


;==============================================================================
; SortActors  -  Bubble-sort ActorList by Y position (descending)
;
; Sorts the ActorList array so that actors with larger Y values (lower on
; screen) appear later in the list and are therefore drawn last (on top).
; This gives correct painter's-algorithm rendering for overlapping tiles.
;
; Uses a simple bubble sort.  d6 flags whether any swap occurred during the
; pass; if not, the list is already sorted and we exit.  For typical level
; sizes (< 20 actors) this is perfectly adequate.
;
; Comparator: Actor_Y(a1) < Actor_Y(a2) -> swap (push smaller-Y items earlier)
;==============================================================================

SortActors:
    moveq       #0,d6                      ; d6 = swap-occurred flag

    move.w      ActorCount(a5),d7
    subq.w      #2,d7                      ; compare N-1 adjacent pairs
    bmi         .exit                      ; fewer than 2 actors - already sorted

    lea         ActorList(a5),a0           ; a0 -> first pair

.next
    move.l      (a0),a1                    ; a1 -> actor at position i
    move.l      4(a0),a2                   ; a2 -> actor at position i+1

    move.w      Actor_Y(a1),d0             ; Y of actor at position i
    move.w      Actor_Y(a2),d1             ; Y of actor at position i+1

    cmp.w       d1,d0                      ; is Y[i] < Y[i+1]?
    bcc         .skip                      ; no (already in correct order) - skip swap

    ; Swap the two pointers: larger Y goes to higher index (drawn on top)
    move.l      a2,(a0)                    ; [i]   = a2 (larger Y)
    move.l      a1,4(a0)                   ; [i+1] = a1 (smaller Y)
    moveq       #1,d6                      ; mark that a swap occurred

.skip
    addq.w      #4,a0                      ; advance to next pointer pair
    dbra        d7,.next

    tst.w       d6                         ; did any swap occur this pass?
    bne         SortActors                 ; yes - run another pass until fully sorted

.exit
    rts
