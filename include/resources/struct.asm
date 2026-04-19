
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; struct.asm  -  Data Structure Definitions
;==============================================================================
;
; Defines the field offsets for all record types used by the game, using the
; DEVPAC/ASM-ONE RS (Record Size) directives:
;
;   RSRESET        - reset the RS counter to 0
;   label: rs.w 1  - allocate 1 word (2 bytes), label = current offset, advance by 2
;   label: rs.b 1  - allocate 1 byte, label = current offset, advance by 1
;   label: rs.l 1  - allocate 1 longword (4 bytes)
;   label: rs.w 0  - allocate nothing; label captures the current total size
;
; Usage:  given a base address in register A4, field FOO is at FOO(a4).
; All word fields are naturally word-aligned.
;
;==============================================================================


;==============================================================================
; Player structure  (Player_Sizeof bytes)
;
; Holds the complete state of one player character (Millie or Molly).
; Two of these live in the Variables block:  Millie and Molly.
; a4 is the convention register for a pointer to the current player struct.
;
; Field descriptions:
;   Player_Status       - 0 = inactive, 1 = active/controlled, 2 = frozen
;   Player_X / Y        - current tile-grid position (0-based column / row)
;   Player_XDec / YDec  - sub-tile pixel offset used during ACTION_MOVE and
;                         ACTION_FALL to animate smooth movement between tiles
;                         (these are pixel deltas added to X*24 / Y*24)
;   Player_ActionCount  - countdown frames remaining in the current action
;                         (24 frames for a tile-to-tile move = 1 pixel/frame)
;   Player_PrevX / Y    - position at the start of the last move, used to
;                         clear the player's previous screen location
;   Player_NextX / Y    - destination tile for the current move or fall action
;   Player_SpriteOffset - base frame index in RealSprites for this character
;                         (Molly = 0, Millie = 48)
;   Player_AnimFrame    - current animation frame counter (0..7 walk, 0..3 idle)
;   Player_Facing       - direction the character faces:
;                         positive (e.g. +1) = right, negative (-1) = left
;   Player_OnLadder     - non-zero when the player is currently on a ladder
;   Player_LadderFreezeId - sprite frame used to draw the frozen/static image
;                         of this player when it is the inactive character
;   Player_DirectionX   - horizontal movement intent: -1, 0 or +1
;   Player_DirectionY   - vertical movement intent:   -1, 0 or +1
;   Player_Fallen       - non-zero while the player is in a fall animation
;   Player_ActionFrame  - sub-frame counter used by the fall easing calculation
;   Player_BlockId      - BLOCK_MILLIESTART or BLOCK_MOLLYSTART - the map cell
;                         value used to mark this player's presence in GameMap
;   Player_LadderId     - BLOCK_MILLIELADDER or BLOCK_MOLLYLADDER - the map
;                         cell value used while the player is on a ladder
;==============================================================================

                          RSRESET
Player_Status:            rs.w    1   ; 0=inactive, 1=active, 2=frozen (other player)
Player_X:                 rs.w    1   ; tile column (0..WALL_PAPER_WIDTH-1)
Player_Y:                 rs.w    1   ; tile row    (0..WALL_PAPER_HEIGHT-1)
Player_XDec:              rs.w    1   ; sub-tile horizontal pixel offset (+/-)
Player_YDec:              rs.w    1   ; sub-tile vertical   pixel offset (+/-)
Player_ActionCount:       rs.w    1   ; frames remaining in current move (24 per tile)
Player_PrevX:             rs.w    1   ; tile column at start of last move (for clear)
Player_PrevY:             rs.w    1   ; tile row    at start of last move (for clear)
Player_NextX:             rs.w    1   ; destination tile column for current action
Player_NextY:             rs.w    1   ; destination tile row    for current action
Player_SpriteOffset:      rs.w    1   ; base sprite frame index (Molly=0, Millie=48)
Player_AnimFrame:         rs.w    1   ; current animation frame (wraps per-action)
Player_Facing:            rs.w    1   ; +1 = facing right, -1 = facing left
Player_OnLadder:          rs.w    1   ; 0 = on ground,  non-zero = on ladder
Player_LadderFreezeId:    rs.w    1   ; sprite frame for frozen-on-ladder display
Player_DirectionX:        rs.w    1   ; intended X move: -1=left, 0=none, +1=right
Player_DirectionY:        rs.w    1   ; intended Y move: -1=up,   0=none, +1=down
Player_Fallen:            rs.w    1   ; non-zero while fall animation is active
Player_ActionFrame:       rs.w    1   ; easing sub-frame index for fall animation
Player_BlockId:           rs.b    1   ; BLOCK_MILLIESTART or BLOCK_MOLLYSTART
Player_LadderId:          rs.b    1   ; BLOCK_MILLIELADDER or BLOCK_MOLLYLADDER
Player_Sizeof:            rs.w    0   ; total structure size in bytes (for ds.b alloc)


;==============================================================================
; Actor structure  (Actor_Sizeof bytes)
;
; Holds the state of one game object / enemy instance.  The actor pool lives
; in the Variables block as  Actors: ds.b Actor_Sizeof*MAX_ACTORS.
; a3 is the convention register for a pointer to the current actor struct.
;
; The ActorList array holds longword pointers to active actor structures,
; kept sorted by Y position (DrawStaticActors uses this order).
;
; Field descriptions:
;   Actor_Status      - 0 = dead/free slot, 1 = alive
;   Actor_X / Y       - current tile position in the game grid
;   Actor_PrevX / Y   - position at the start of the last move (for clear)
;   Actor_XDec / YDec - sub-tile pixel offset during animated push/fall
;   Actor_DirectionX  - horizontal movement direction: -1, 0 or +1
;   Actor_DirectionY  - vertical movement direction:   -1, 0 or +1
;   Actor_HasMoved    - set to 1 when the actor changed tile this frame
;   Actor_HasFalled   - set to 1 while the actor is falling
;   Actor_Type        - BLOCK_xxx type (used during init, may be repurposed)
;   Actor_SpriteOffset - tile index in TileSet to draw this actor
;   Actor_CanFall     - 1 if this actor is subject to gravity (EnemyFall, Push)
;   Actor_Static      - 1 if this actor is drawn statically (not animated)
;   Actor_Delta       - longword easing accumulator for push animation
;   Actor_FallY       - target YDec pixel value at which the fall animation ends
;==============================================================================

                          RSRESET
Actor_Status:             rs.w    1   ; 0=dead, 1=alive
Actor_X:                  rs.w    1   ; tile column
Actor_Y:                  rs.w    1   ; tile row
Actor_PrevX:              rs.w    1   ; previous tile column (used by clear routines)
Actor_PrevY:              rs.w    1   ; previous tile row
Actor_XDec:               rs.w    1   ; sub-tile X pixel offset (push animation)
Actor_YDec:               rs.w    1   ; sub-tile Y pixel offset (fall animation)
Actor_DirectionX:         rs.w    1   ; horizontal direction: -1, 0 or +1
Actor_DirectionY:         rs.w    1   ; vertical direction:   -1, 0 or +1
Actor_HasMoved:           rs.w    1   ; flag: actor moved this frame
Actor_HasFalled:          rs.w    1   ; flag: actor is in a fall animation
Actor_Type:               rs.w    1   ; original BLOCK_xxx type from the map
Actor_SpriteOffset:       rs.w    1   ; tile index into TileSet for rendering
Actor_CanFall:            rs.w    1   ; 1 = subject to gravity
Actor_Static:             rs.w    1   ; 1 = drawn once into ScreenStatic (no update)
Actor_Delta:              rs.l    1   ; fixed-point easing accumulator (push anim)
Actor_FallY:              rs.w    1   ; pixel target for end of fall animation
Actor_ImpactTick:         rs.w    1   ; landing smoke tick: 0=idle, 1..IMPACT_TOTAL_TICKS=animating
Actor_Sizeof:             rs.w    0   ; total structure size in bytes


;==============================================================================
; Clean record  (Clean_Sizeof bytes)
;
; A small descriptor used when scheduling a screen area to be "cleaned"
; (restored from ScreenSave to ScreenStatic) after an actor has moved away.
; Currently used by the blitter clear routines.
;
;   Clean_ScreenOffset - byte offset from the start of the screen buffer
;                        to the top-left pixel of the tile to clear
;   Clean_BlitSize     - BLTSIZE register value for this blit operation
;   Clean_BlitMod      - blitter modulo for this operation
;==============================================================================

                          RSRESET
Clean_ScreenOffset:       rs.w    1   ; byte offset into screen buffer
Clean_BlitSize:           rs.w    1   ; BLTSIZE value for the clear blit
Clean_BlitMod:            rs.w    1   ; blitter modulo for the clear blit
Clean_Sizeof:             rs.w    0   ; total structure size in bytes
