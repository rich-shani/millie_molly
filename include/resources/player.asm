
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; player.asm  -  Player Logic, Movement, Animation and Actor Interaction
;==============================================================================
;
; This file implements the player action state machine and all gameplay logic:
;
;   PlayerLogic        - top-level dispatcher for ActionStatus
;   ActionIdle         - idle state: poll input, trigger moves
;   ActionMove         - smooth tile-to-tile movement (24 pixel steps)
;   ActionFall         - player falling with quadratic easing
;   ActionPlayerPush   - push-block animation (sinusoidal easing)
;   ActionFallActors   - animate actors that are falling simultaneously
;   PlayerCheckControls- dispatch to active/frozen/inactive sub-handlers
;   PlayerIdle         - process player input in idle state
;   PlayerShowIdleAnim - animate the player sprite when standing still
;   PlayerShowWalkAnim - animate the player sprite while moving
;   PlayerTryMove      - test the next cell and choose the correct action
;   PlayerDoMove       - commit a standard move (set ActionStatus = MOVE)
;   PlayerMoveActor    - find and push a block in the direction of movement
;   PlayerKillActor    - find and remove an enemy at the target cell
;   PlayerKillDirt     - remove a dirt block at the target cell
;   PlayerKillEnemy    - kill an enemy actor and clean actor list
;   PlayerMoveLogic    - update GameMap after a move completes
;   PlayerFallLogic    - check if the active player should now fall
;   PlayerFallLogicFrozen - check if the frozen player should fall
;   PlayerSwitch       - swap active and frozen player characters
;   DrawPlayerFrozen   - draw the frozen player in its idle/static pose
;   CheckLevelDone     - scan GameMap for remaining enemies
;   ActorFall          - find floor and initiate fall for one actor
;   ActorFallAll       - trigger falls for all eligible actors
;   ActorDrawStatic    - draw one actor at its current tile position
;   ClearPlayer        - erase the active player from DisplayScreen
;   RestoreBackgroundTile   - erase a tile-aligned block from DisplayScreen
;   ClearActor         - erase a (possibly shifted) actor from DisplayScreen
;   PlayerGetNextBlock - return the block type at the cell ahead of the player
;
; Register convention:
;   a4 = current (active) player structure
;   a3 = current actor structure
;   a5 = Variables base
;   a6 = $dff000 (CUSTOM chip base)
;
;==============================================================================


;==============================================================================
; PlayerLogic  -  Top-level player action dispatcher
;
; Called every VBlank from GameRun.  Reads ActionStatus and jumps to the
; appropriate handler for the current game action.
;
; ActionStatus values (from const.asm):
;   0 = ACTION_IDLE        -> ActionIdle
;   1 = ACTION_MOVE        -> ActionMove
;   2 = ACTION_FALL        -> ActionFall
;   3 = ACTION_PLAYERPUSH  -> ActionPlayerPush
;   4 = ACTION_INTRO       -> ActionIntro  (level intro star animation)
;   5 = ACTION_SWITCH      -> ActionIntro  (player switch star animation; same body)
;
; Only one action runs at a time.  Each action handler is responsible for
; resetting ActionStatus to ACTION_IDLE when it completes.
;==============================================================================

PlayerLogic:
    move.w      ActionStatus(a5),d0     ; load current action state
    JMPINDEX    d0                      ; dispatch through jump table

.i  ; jump offset table
    dc.w        ActionIdle-.i           ; state 0: idle
    dc.w        ActionMove-.i           ; state 1: moving
    dc.w        ActionFall-.i           ; state 2: falling
    dc.w        ActionPlayerPush-.i     ; state 3: push animation
    dc.w        ActionIntro-.i          ; state 4: level intro star animation
    dc.w        ActionIntro-.i          ; state 5: player switch star animation (same body)


;==============================================================================
; ActionFall  -  Player and actor fall animation handler (ACTION_FALL state)
;
; Each frame while in the fall state:
;   1. ActionPlayerFall - advance the player's fall animation one step.
;   2. ActionFallActors - advance all falling actors one step.
;   3. Check if both are complete (d6 = 0 from ActionFallActors AND
;      Player_Fallen = 0 from ActionPlayerFall).
;      If complete: transition back to ACTION_IDLE.
;
; d6 is used as the "fall still in progress" flag: non-zero = still falling.
;==============================================================================

ActionFall:
    bsr         ActionPlayerFall        ; advance player fall one frame; clears Player_Fallen when done
    bsr         ActionFallActors        ; advance actor falls; d6 = number still falling
    add.w       Player_Fallen(a4),d6   ; add player's own fall flag
    bne         .notyet                 ; d6 != 0 -> at least one fall still active
    move.w      #ACTION_IDLE,ActionStatus(a5)   ; all falls complete -> back to idle
    bsr         TakeSnapshot           ; game fully settled after the fall chain

.notyet
    rts


;==============================================================================
; ActionFallActors  -  Animate all actors that are currently in a fall
;
; Iterates the FallenActors list (populated by ActorFallAll) and for each
; actor with Actor_HasFalled set:
;   1. RestoreBackgroundTile x2 - restore the two tiles the sprite spans
;   2. Increment Actor_YDec (accelerating: YDec/2 + 1 per frame)
;   3. DrawActor        - redraw at new sub-pixel position
;   4. When Actor_YDec reaches Actor_FallY: clear fall fields, set
;      Actor_ImpactTick = 1 to start the landing smoke animation, then
;      fall through into the impact section below.
;
; For each actor with Actor_ImpactTick > 0 (smoke animation in progress):
;   1. RestoreBackgroundTile + ActorDrawStatic - restore tile and redraw actor
;   2. DrawSprite - overlay the current smoke frame (SPRITE_SMOKE_A..D)
;   3. Increment Actor_ImpactTick; when it exceeds IMPACT_TOTAL_TICKS,
;      restore tile, redraw actor cleanly, clear Actor_ImpactTick.
;
; a2 (FallenActors list pointer) is preserved across all draw calls that
; corrupt it (PasteTile and DrawSprite both set a2 to their mask pointer).
;
; Out: d6 = number of actors still active (falling OR impact animating)
;==============================================================================

ActionFallActors:
    moveq       #0,d6                   ; d6 = running count of still-falling actors

    move.w      FallenActorsCount(a5),d7
    subq.w      #1,d7
    bmi         .exit                   ; no fallen actors

    lea         FallenActors(a5),a2     ; a2 -> array of pointers to falling actors

.loop
    move.l      (a2)+,a3                ; a3 -> actor struct

    tst.w       Actor_HasFalled(a3)     ; is this actor still falling?
    beq         .check_impact           ; no fall - check for pending impact animation

    addq.w      #1,d6                   ; count: one more actor still active

    ; ROOT CAUSE: ClearActor erases a 24-row window at PrevY*24+YDec, then
    ; DrawActor immediately redraws PrevY*24+(YDec+delta).  When delta is
    ; small (1,2,4... on early frames) 20-23 of the 24 cleared rows are
    ; repainted in the same frame, so every tile in the fall path appears
    ; unchanged for many frames — a persistent ghost.
    ;
    ; FIX: the sprite is 24 pixels tall and can span at most two tiles.
    ; Restore both tiles from NonDisplayScreen before every draw.  This gives
    ; a clean slate regardless of velocity, eliminating ghosts in the original
    ; tile and in every intermediate tile throughout the entire fall.
    moveq       #0,d0
    move.w      Actor_YDec(a3),d0
    divu        #24,d0                   ; d0.w = floor(YDec/24) = whole tiles fallen
    move.w      Actor_PrevX(a3),d1      ; save tile X (preserved by RestoreBackgroundTile)
    move.w      Actor_PrevY(a3),d2      ; save base tile Y
    add.w       d0,d2                    ; d2 = tile Y of sprite top
    move.w      d1,d0                    ; d0 = tile X
    move.w      d2,d1                    ; d1 = tile Y (top)
    bsr         RestoreBackgroundTile    ; wipe tile containing sprite top
    addq.w      #1,d1                    ; tile immediately below = sprite bottom
    move.w      Actor_PrevX(a3),d0
    bsr         RestoreBackgroundTile    ; wipe tile containing sprite bottom

    ; Accelerating fall: velocity = YDec/2 + 1 (grows as fall distance increases)
    move.w      Actor_YDec(a3),d0
    lsr.w       #1,d0                   ; d0 = current distance / 2
    addq.w      #1,d0                   ; minimum 1 pixel/frame
    add.w       d0,Actor_YDec(a3)       ; advance fall position

    ; Clamp to target before drawing: prevents the sprite bleeding into the tile
    ; below the landing row when a large velocity step overshoots Actor_FallY.
    move.w      Actor_YDec(a3),d0
    cmp.w       Actor_FallY(a3),d0
    blo         .draw
    move.w      Actor_FallY(a3),Actor_YDec(a3)

.draw
    bsr         DrawActor               ; redraw at new (clamped) sub-pixel position

    ; Has the fall reached its target?
    move.w      Actor_YDec(a3),d0
    cmp.w       Actor_FallY(a3),d0     ; compare with target distance
    blo         .next                   ; still falling (unsigned less-than)

    ; Fall complete: clean up and start impact smoke animation
    clr.w       Actor_YDec(a3)         ; reset sub-tile offset
    clr.w       Actor_HasFalled(a3)    ; mark fall as done
    move.w      #1,Actor_ImpactTick(a3) ; start smoke effect (falls through below)

.check_impact
    tst.w       Actor_ImpactTick(a3)   ; impact animation pending?
    beq         .next                   ; no - nothing to do

    addq.w      #1,d6                   ; impact in progress: keep ACTION_FALL alive

    ; Compute current smoke animation frame index (0..IMPACT_FRAMES-1)
    moveq       #0,d0
    move.w      Actor_ImpactTick(a3),d0
    subq.w      #1,d0                   ; 0-based tick (0..IMPACT_TOTAL_TICKS-1)
    divu        #IMPACT_FRAME_TICKS,d0  ; d0.w = frame index (0,1,2,3)

    ; Check if all smoke frames have played
    cmp.w       #IMPACT_FRAMES,d0
    bcc         .impact_done            ; frame >= 4: animation complete

    ; --- Draw smoke frame ---
    ; Preserve a2: PasteTile (via ActorDrawStatic) and DrawSprite both set a2
    ; to their mask pointer, corrupting the FallenActors list position.
    PUSH        a2

    ; 1. Restore background from NonDisplayScreen (clears previous smoke frame)
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile

    ; 2. Redraw actor with transparency (NonDisplayScreen now clean underneath)
    bsr         ActorDrawStatic

    ; 3. Compute smoke sprite index: SPRITE_SMOKE_A + frame_index
    moveq       #0,d2
    move.w      Actor_ImpactTick(a3),d2
    subq.w      #1,d2
    divu        #IMPACT_FRAME_TICKS,d2  ; d2.w = frame index
    add.w       #SPRITE_SMOKE_A,d2      ; d2 = sprite sheet index

    ; 4. Pixel position of actor's landed tile
    move.w      Actor_X(a3),d0
    mulu        #24,d0                  ; pixel X
    move.w      Actor_Y(a3),d1
    mulu        #24,d1                  ; pixel Y

    ; 5. Blit smoke frame over actor (transparent overlay using SpriteMask)
    bsr         DrawSprite

    POP         a2                      ; restore FallenActors list pointer

    addq.w      #1,Actor_ImpactTick(a3) ; advance to next tick
    bra         .next

.impact_done
    ; All smoke frames shown: restore clean state (actor visible, no smoke)
    PUSH        a2
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile        ; clear last smoke frame
    bsr         ActorDrawStatic         ; redraw actor cleanly
    POP         a2
    clr.w       Actor_ImpactTick(a3)    ; mark animation complete

.next
    dbra        d7,.loop

.exit
    tst.w       d6                      ; return d6 (0 = all falls and impacts done)
    rts


;==============================================================================
; ActionPlayerPush  -  Animate a block being pushed (ACTION_PLAYERPUSH state)
;
; Called once per frame while a block is being pushed.  Uses a quadratic easing
; curve (Quadratic table, assets/quadratic.bin) to produce a smooth
; acceleration/deceleration motion for the pushed block.
;
; PUSH_STEPS  = 12 animation frames for a full push (24 pixel travel)
; PUSH_DELTA  = angular increment per frame in the Quadratic table index space
;              = (SINE_ANGLES << 16) / 2 / PUSH_STEPS
;              (maps PUSH_STEPS frames to a half-period of the quadratic curve)
;
; Per frame:
;   1. ClearActor   - erase the block from its current drawn position
;   2. Advance Actor_Delta by PUSH_DELTA (fixed-point angle accumulator)
;   3. Read Actor_Delta low word, add SINE_270 offset (start at the trough),
;      mask to SINE_RANGE-1, read Quadratic[index].
;   4. Scale the quadratic value: pixel_offset = quad * 12 / SINE_RANGE + 12
;      (gives 0..24 pixel range over the half-period, centred at 12)
;   5. Apply direction: if DirectionX is negative, negate offset.
;   6. Store as Actor_XDec.
;   7. DrawActor    - redraw at new position.
;   8. When ActionCounter reaches PUSH_STEPS (12), finalise the push:
;      clear XDec, update PrevX = X, call ActorFallAll.
;      If any actors are now falling, set ActionStatus = ACTION_FALL,
;      otherwise return to ACTION_IDLE.
;==============================================================================

PUSH_STEPS  = 12
PUSH_DELTA  = (SINE_ANGLES<<16)/2/PUSH_STEPS

ActionPlayerPush:
    move.l      PushedActor(a5),a3     ; a3 -> the block being pushed

    ; First, restore the background tile from NonDisplayScreen for the entire animation area
    move.w      Actor_PrevX(a3),d0      ; tile X coordinate
    move.w      Actor_PrevY(a3),d1      ; tile Y coordinate
    bsr         RestoreBackgroundTile        ; blit background from NonDisplayScreen to DisplayScreen

    bsr         ClearActor             ; erase block from current drawn position

    ; Advance the fixed-point angle accumulator
    lea         Quadratic,a0
    sub.l       #PUSH_DELTA,Actor_Delta(a3)  ; decrement angle (half-period, trough to peak)

    ; Sample the quadratic easing curve at the current angle
    moveq       #0,d0
    move.w      Actor_Delta(a3),d0    ; current angle (low word of fixed-point delta)
    add.w       #SINE_270,d0          ; start at the 270-degree (trough) point
    and.w       #SINE_RANGE-1,d0      ; wrap to table bounds
    add.w       d0,d0                 ; word index (table entries are words)
    move.w      (a0,d0.w),d0          ; d0 = quadratic value (-SINE_RANGE..+SINE_RANGE)

    ; Scale: map quadratic value to 0..24 pixel range
    muls        #12,d0                ; scale by 12 (half of 24-pixel tile width)
    divs        #SINE_RANGE,d0        ; normalise to -12..+12
    add.w       #12,d0                ; shift to 0..24 range

    ; Apply direction sign
    move.w      Actor_DirectionX(a3),d4
    tst.w       Actor_DirectionX(a3)
    bpl         .positive
    neg.w       d0                    ; negative direction: negate offset

.positive
    move.w      d0,Actor_XDec(a3)    ; store computed sub-pixel X offset

    bsr         DrawActor             ; redraw block at new sub-pixel position

    ; Advance frame counter; check for push completion
    addq.w      #1,ActionCounter(a3)
    cmp.w       #PUSH_STEPS,ActionCounter(a3)
    bne         .exit                 ; not done yet

    ; Push animation complete
    clr.w       Actor_XDec(a3)       ; clear sub-pixel offset (snap to final position)
    move.w      Actor_X(a3),Actor_PrevX(a3)   ; update previous position record

    ; Check if the pushed block (or any other actor) should now fall
    bsr         ActorFallAll          ; d5 = number of actors now falling
    move.w      #ACTION_IDLE,d0
    tst.w       d5
    beq         .nofall
    move.w      #ACTION_FALL,d0       ; actors fell -> enter fall state

.nofall
    move.w      d0,ActionStatus(a5)
    ; If settling to IDLE (no fall), snapshot now; fall case deferred to ActionFall
    tst.w       d0
    bne         .exit
    bsr         TakeSnapshot

.exit
    rts


;==============================================================================
; ActionPlayerFall  -  Advance the active player's fall animation one frame
;
; Called from ActionFall each VBlank while Player_Fallen is set.
;
; The fall distance (in pixels) is (Player_NextY - Player_Y) * 24.
; Player_ActionFrame acts as a velocity counter: it increments by 1 each frame
; and is added to Player_YDec, giving constant acceleration (quadratic distance
; growth).  The fall ends when Player_YDec reaches the total fall distance.
;
; On completion:
;   - Player_Fallen is cleared
;   - Player_YDec is cleared (player snaps to final position)
;   - Player_Y is set to Player_NextY
;
; While falling, the walk/fall animation cycles through PLAYER_SPRITE_FALL_OFFSET
; frames at 3-frame intervals.
;==============================================================================

ActionPlayerFall:
    tst.w       Player_Fallen(a4)      ; is the player currently in a fall?
    beq         .exit

    ; Calculate total fall distance in pixels
    move.w      Player_Y(a4),d0
    move.w      Player_NextY(a4),d1
    mulu        #24,d0
    mulu        #24,d1
    sub.w       d0,d1                  ; d1 = total fall distance in pixels

    ; Accelerating fall: ActionFrame is the velocity (pixels/frame).
    ; Increment velocity first, then accumulate into YDec (position).
    addq.w      #1,Player_ActionFrame(a4)  ; velocity += 1 pixel/frame each frame
    move.w      Player_ActionFrame(a4),d2
    add.w       d2,Player_YDec(a4)         ; position += velocity
    move.w      Player_YDec(a4),d2         ; d2 = current pixel offset

    ; Clamp to total fall distance (handle overshoot from large velocity step)
    cmp.w       d1,d2
    blo         .inrange
    move.w      d1,d2                      ; clamp at maximum
    move.w      d1,Player_YDec(a4)

.inrange
    ; Check if we have reached the end of the fall
    cmp.w       d1,d2
    bne         .show                  ; not yet at the destination

    ; Fall complete: snap to final position
    clr.w       Player_Fallen(a4)
    clr.w       Player_YDec(a4)
    move.w      Player_NextY(a4),Player_Y(a4)  ; commit final tile position

.show
    ; Animate fall sprite: cycle frames at 1/3 speed
    move.w      TickCounter(a5),d0
    divu        #3,d0                  ; one animation step every 3 frames
    swap        d0                     ; remainder -> d0 low word
    tst         d0
    bne         .noadd                 ; only advance animation on remainder == 0

    addq.w      #1,Player_AnimFrame(a4)
    and.w       #3,Player_AnimFrame(a4) ; cycle 0..3

.noadd
    move.w      Player_AnimFrame(a4),d0
    add.w       #PLAYER_SPRITE_FALL_OFFSET,d0  ; select fall animation frame
    bsr         ShowSprite

.exit
    rts


;==============================================================================
; ActionIntro  -  Star animation handler (ACTION_INTRO and ACTION_SWITCH states)
;
; Called every VBlank while ActionStatus = ACTION_INTRO or ACTION_SWITCH.
; StarAnimContext selects which completion behaviour fires when the hold expires:
;   0 (ACTION_INTRO)  - level start: show the player sprite, enter ACTION_IDLE.
;   1 (ACTION_SWITCH) - player swap: swap PlayerPtrs, clear the frozen graphic,
;                       show the new active player sprite, enter ACTION_IDLE.
;
; A large blue star steps one tile per INTRO_STEP_TICKS frames on a straight
; diagonal path from StarOriginX/Y toward StarTargetX/Y.  Each step:
;   - Stores one trail pool entry (tile X/Y) for background restoration.
;   - Blits 2-4 small white star sprites at random pixel offsets within the
;     tile area.  Offset range: ±8 pixels in both X and Y from the tile origin.
;     DrawSprite restores d0-d2 via POPM so consecutive calls reuse the same
;     pixel base; only the offsets differ.
;
; Trail particle life is INTRO_TRAIL_LIFE frames; RestoreBackgroundTile at the tile
; position restores the background when the particle expires.
;
; Registers in the step section:
;   d3 = base pixel X (StarOriginX*24), saved across DrawSprite calls
;   d4 = base pixel Y (StarOriginY*24), saved across DrawSprite calls
;   d5 = random word from RANDOMWORD
;==============================================================================

ActionIntro:
    ; --- 1. Age trail particles (runs every frame: during travel and hold) ---
    ;
    ; For each live slot: clear tile, decrement life, redraw if still alive.
    ; Small stars fade out on their natural schedule regardless of hold state.
    ; d6 = byte offset (index*2); d3 = tileX; d4 = tileY; d5 = life; d7 = counter
    ; RestoreBackgroundTile uses PUSHALL/POPALL (all regs preserved).
    ; DrawSprite clobbers a0-a2 only (d0-d7, a3-a6 preserved via PUSHM/POPM).

    moveq       #INTRO_TRAIL_MAX-1,d7
.age_loop
    move.w      d7,d6
    lsl.w       #1,d6                   ; d6 = byte offset

    lea         IntroTrailLife(a5),a0
    lea         IntroTrailX(a5),a1
    lea         IntroTrailY(a5),a2

    move.w      (a0,d6.w),d5            ; d5 = life
    beq         .age_next               ; dead: skip

    move.w      (a1,d6.w),d3            ; d3 = tileX
    move.w      (a2,d6.w),d4            ; d4 = tileY

    move.w      d3,d0
    move.w      d4,d1
    bsr         RestoreBackgroundTile        ; restore tile from NonDisplayScreen
    bsr         RedrawActorAtTile            ; redraw any actor at this tile (d0/d1 preserved)

    subq.w      #1,d5                   ; decrement life
    move.w      d5,(a0,d6.w)
    beq         .age_next               ; just expired: no redraw

    ; Redraw at tile-aligned pixel coords
    move.w      d3,d0
    mulu        #24,d0                  ; d0 = pixel X
    move.w      d4,d1
    mulu        #24,d1                  ; d1 = pixel Y
    move.w      #SPRITE_STAR_SMALL,d2
    bsr         DrawSprite              ; clobbers a0-a2; preserves d0-d7, a3-a6

.age_next
    dbra        d7,.age_loop

    ; --- 2. Hold or travel? ---
    move.w      IntroDone(a5),d0
    bne         .holding

    ; --- TRAVELLING: check step time ---
    subq.w      #1,IntroTick(a5)
    bne         .no_step

    ; --- STEP ---
    move.w      #INTRO_STEP_TICKS,IntroTick(a5)

    ; a. Erase large star from current tile
    move.w      StarOriginX(a5),d0
    move.w      StarOriginY(a5),d1
    bsr         RestoreBackgroundTile
    bsr         RedrawActorAtTile            ; redraw any actor at this tile (d0/d1 preserved)

    ; b. Write one trail pool entry at current tile position
    move.w      IntroWriteIdx(a5),d3    ; d3 = slot index
    move.w      d3,d4
    lsl.w       #1,d4                   ; d4 = byte offset
    lea         IntroTrailX(a5),a0
    lea         IntroTrailY(a5),a1
    lea         IntroTrailLife(a5),a2
    move.w      StarOriginX(a5),d0
    move.w      d0,(a0,d4.w)            ; TrailX[d3] = StarX
    move.w      StarOriginY(a5),d1
    move.w      d1,(a1,d4.w)            ; TrailY[d3] = StarY
    move.w      #INTRO_TRAIL_LIFE,(a2,d4.w)
    ; Advance circular write index
    addq.w      #1,d3
    cmp.w       #INTRO_TRAIL_MAX,d3
    blt         .idx_ok
    moveq       #0,d3
.idx_ok
    move.w      d3,IntroWriteIdx(a5)

    ; c. Blit 2-4 small stars at random pixel offsets within this tile
    ;    Compute base pixel coords and save in d3/d4; DrawSprite restores d0-d2
    ;    so we add fresh offsets each call.
    mulu        #24,d0                  ; d0 = StarX * 24  (tile pixel X)
    mulu        #24,d1                  ; d1 = StarY * 24  (tile pixel Y)
    move.w      d0,d3                   ; d3 = base pixel X (preserved across DrawSprite)
    move.w      d1,d4                   ; d4 = base pixel Y

    ; Get random word; bits 0-15 supply 3 × (4-bit X offset + 4-bit Y offset)
    RANDOMWORD                          ; d0 = random word; d1 preserved via stack
    move.w      d0,d5                   ; d5 = random word

    ; Star 1: exact tile origin
    move.w      d3,d0
    move.w      d4,d1
    move.w      #SPRITE_STAR_SMALL,d2
    bsr         DrawSprite

    ; Star 2: random offset from bits 7:0  (4-bit X: -8..+7, 4-bit Y: -8..+7)
    move.w      d5,d0
    and.w       #$F,d0                  ; bits 3:0 → 0..15
    subq.w      #8,d0                   ; → -8..+7
    add.w       d3,d0                   ; pixel X with offset
    move.w      d5,d1
    lsr.w       #4,d1
    and.w       #$F,d1                  ; bits 7:4 → 0..15
    subq.w      #8,d1                   ; → -8..+7
    add.w       d4,d1                   ; pixel Y with offset
    move.w      #SPRITE_STAR_SMALL,d2
    bsr         DrawSprite

    ; Star 3: random offset from bits 15:8
    move.w      d5,d0
    lsr.w       #8,d0
    and.w       #$F,d0
    subq.w      #8,d0
    add.w       d3,d0
    move.w      d5,d1
    lsr.w       #7,d1
    and.w       #$F,d1
    subq.w      #8,d1
    add.w       d4,d1
    move.w      #SPRITE_STAR_SMALL,d2
    bsr         DrawSprite

    ; Star 4: only if bits 5:4 of random word are non-zero (75% chance)
    move.w      d5,d0
    and.w       #$30,d0                 ; bits 5:4
    beq         .skip_star4             ; 25% chance: skip

    RANDOMWORD                          ; fresh random bits for this star's offset
    move.w      d0,d5
    move.w      d5,d0
    and.w       #$F,d0
    subq.w      #8,d0
    add.w       d3,d0
    move.w      d5,d1
    lsr.w       #4,d1
    and.w       #$F,d1
    subq.w      #8,d1
    add.w       d4,d1
    move.w      #SPRITE_STAR_SMALL,d2
    bsr         DrawSprite

.skip_star4
    ; d. Move star one tile toward target
    move.w      StarOriginX(a5),d0
    move.w      StarTargetX(a5),d1
    cmp.w       d0,d1
    beq         .star_x_done
    bgt         .star_x_right
    subq.w      #1,d0
    bra         .star_x_done
.star_x_right
    addq.w      #1,d0
.star_x_done
    move.w      d0,StarOriginX(a5)

    move.w      StarOriginY(a5),d0
    move.w      StarTargetY(a5),d1
    cmp.w       d0,d1
    beq         .star_y_done
    bgt         .star_y_down
    subq.w      #1,d0
    bra         .star_y_done
.star_y_down
    addq.w      #1,d0
.star_y_done
    move.w      d0,StarOriginY(a5)

    ; e. Check if arrived at target
    move.w      StarOriginX(a5),d0
    cmp.w       StarTargetX(a5),d0
    bne         .draw_star
    move.w      StarOriginY(a5),d0
    cmp.w       StarTargetY(a5),d0
    bne         .draw_star

    ; ARRIVED: start hold countdown; duration depends on animation context
    tst.w       StarAnimContext(a5)
    bne         .switch_hold
    move.w      #INTRO_HOLD_TICKS,IntroDone(a5)
    bra         .draw_star
.switch_hold
    move.w      #SWITCH_HOLD_TICKS,IntroDone(a5)

.draw_star
    ; f. Draw large star at new/current position
    move.w      StarOriginX(a5),d0
    mulu        #24,d0
    move.w      StarOriginY(a5),d1
    mulu        #24,d1
    move.w      #SPRITE_STAR_LARGE,d2
    bsr         DrawSprite

.no_step
    rts

    ; --- HOLDING: large star stays at target; small trail stars age out normally ---
.holding
    ; Redraw large star each frame (trail aging above may have cleared its tile)
    move.w      StarOriginX(a5),d0
    mulu        #24,d0
    move.w      StarOriginY(a5),d1
    mulu        #24,d1
    move.w      #SPRITE_STAR_LARGE,d2
    bsr         DrawSprite

    subq.w      #1,IntroDone(a5)
    bne         .no_step                ; still holding: done for this frame

    ; Hold expired: erase large star and trail, then finish
    move.w      StarOriginX(a5),d0
    move.w      StarOriginY(a5),d1
    bsr         RestoreBackgroundTile        ; erase large star from DisplayScreen
    bsr         IntroClearAllTrail           ; clear any surviving trail particles
    bsr         DrawStaticActors             ; restore any actor tiles the trail cleared
    tst.w       StarAnimContext(a5)
    bne         .switch_done
    ; Level intro: draw frozen player if one is present in this level
    move.l      PlayerPtrs+4(a5),a4
    tst.w       Player_Status(a4)           ; status 0 = not placed in this level
    beq         .anim_complete
    bsr         DrawPlayerFrozen
    bra         .anim_complete
.switch_done
    ; Player switch: perform pointer swap now that star has arrived
    move.l      PlayerPtrs+4(a5),a4         ; a4 -> previously frozen player
    move.l      PlayerPtrs(a5),PlayerPtrs+4(a5)
    move.l      a4,PlayerPtrs(a5)
    move.w      #1,Player_Status(a4)        ; new active player
    bsr         ClearPlayer                  ; erase frozen graphic from screen
    ; Redraw the now-frozen player (trail cleanup may have erased their sprite)
    move.l      PlayerPtrs+4(a5),a4
    bsr         DrawPlayerFrozen
.anim_complete
    move.l      PlayerPtrs(a5),a4
    moveq       #0,d0
    bsr         ShowSprite
    move.w      #ACTION_IDLE,ActionStatus(a5)
    rts


;==============================================================================
; IntroClearAllTrail  -  RestoreBackgroundTile all active trail particles
;
; Called at intro completion to erase every still-visible trail star from
; DisplayScreen and mark each particle dead (Life = 0).
;==============================================================================

IntroClearAllTrail:
    lea         IntroTrailLife(a5),a0
    lea         IntroTrailX(a5),a1
    lea         IntroTrailY(a5),a2
    moveq       #INTRO_TRAIL_MAX-1,d7

.loop
    move.w      d7,d6
    lsl.w       #1,d6                   ; d6 = byte offset
    move.w      (a0,d6.w),d0            ; life
    beq         .next                   ; already dead
    move.w      (a1,d6.w),d0            ; tile X
    move.w      (a2,d6.w),d1            ; tile Y
    bsr         RestoreBackgroundTile        ; PUSHALL/POPALL: preserves all registers
    clr.w       (a0,d6.w)               ; mark dead

.next
    dbra        d7,.loop
    rts


;==============================================================================
; StarAnimBegin  -  Common initialisation for the star animation
;
; Called after the caller has set StarOriginX/Y, StarTargetX/Y, and
; StarAnimContext.  Resets IntroTick, IntroDone, IntroWriteIdx, clears the
; trail pool, and blits the large star at the origin position.
;
; Clobbers: none (PUSHALL/POPALL).
;==============================================================================

StarAnimBegin:
    PUSHALL
    move.w      #INTRO_STEP_TICKS,IntroTick(a5)
    clr.w       IntroDone(a5)
    clr.w       IntroWriteIdx(a5)
    lea         IntroTrailLife(a5),a0
    moveq       #INTRO_TRAIL_MAX-1,d7
.clear_trail
    clr.w       (a0)+
    dbra        d7,.clear_trail
    move.w      StarOriginX(a5),d0
    mulu        #24,d0
    move.w      StarOriginY(a5),d1
    mulu        #24,d1
    move.w      #SPRITE_STAR_LARGE,d2
    bsr         DrawSprite
    POPALL
    rts


;==============================================================================
; RedrawActorAtTile  -  Redraw any live actor at the given tile position
;
; Called after RestoreBackgroundTile during the star animation so that actors
; whose tiles are restored by trail cleanup or the large-star erase do not
; disappear from the screen mid-animation.
;
; Entry: d0 = tile X, d1 = tile Y
; Clobbers: none (PUSHALL/POPALL).
;==============================================================================

RedrawActorAtTile:
    PUSHALL
    move.w      ActorCount(a5),d7
    beq         .exit
    subq.w      #1,d7
    lea         Actors(a5),a3
.scan
    tst.w       Actor_Status(a3)
    beq         .next
    cmp.w       Actor_X(a3),d0
    bne         .next
    cmp.w       Actor_Y(a3),d1
    bne         .next
    bsr         ActorDrawStatic             ; redraws actor tile onto DisplayScreen
    bra         .exit
.next
    add.w       #Actor_Sizeof,a3
    dbra        d7,.scan
.exit
    POPALL
    rts


;==============================================================================
; ActionCloudActors  -  Animate all active cloud death animations
;
; Called every frame from GameRun, independent of the main action state.
; Iterates CloudActors[0..CloudActorsCount-1]; actors with CloudTick=0 are
; skipped (already done).
;
; Cloud frames are blitted to DisplayScreen via DrawSprite.  The player
; hardware sprite (SPR0-3) sits in front of the bitplane, so the cloud
; always appears behind the player - this is an accepted visual limitation.
;
; For each actor with Actor_CloudTick > 0:
;   1. Compute frame index = (Actor_CloudTick - 1) / CLOUD_FRAME_TICKS
;   2. If frame >= CLOUD_FRAMES: RestoreBackgroundTile, clear Actor_CloudTick.
;   3. Otherwise: RestoreBackgroundTile, DrawSprite(cloud frame), increment tick.
;
; Registers: a2=CloudActors pointer, a3=actor struct, d7=loop counter
; a2 is PUSH/POPed around DrawSprite (DrawSprite clobbers a2).
;==============================================================================

ActionCloudActors:
    move.w      CloudActorsCount(a5),d7
    subq.w      #1,d7
    bmi         .exit                   ; no cloud actors registered

    lea         CloudActors(a5),a2      ; a2 -> cloud actor pointer array

.loop
    move.l      (a2)+,a3                ; a3 -> actor struct

    tst.w       Actor_CloudTick(a3)     ; animation active?
    beq         .next                   ; tick=0: already done, skip

    ; Compute frame index: (tick - 1) / CLOUD_FRAME_TICKS
    moveq       #0,d0
    move.w      Actor_CloudTick(a3),d0
    subq.w      #1,d0                   ; 0-based tick (0..CLOUD_TOTAL_TICKS-1)
    divu        #CLOUD_FRAME_TICKS,d0   ; d0.w = frame index (0..CLOUD_FRAMES-1+)

    cmp.w       #CLOUD_FRAMES,d0
    bcc         .cloud_done             ; frame >= CLOUD_FRAMES: all frames shown

    ; --- Draw cloud frame via blitter ---
    PUSH        a2                      ; DrawSprite clobbers a2

    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile   ; erase previous cloud frame

    move.w      Actor_CloudTick(a3),d2
    subq.w      #1,d2
    divu        #CLOUD_FRAME_TICKS,d2   ; d2.w = frame index
    add.w       #SPRITE_CLOUD_A,d2      ; absolute sprite sheet index

    move.w      Actor_X(a3),d0
    mulu        #24,d0                  ; pixel X
    move.w      Actor_Y(a3),d1
    mulu        #24,d1                  ; pixel Y
    bsr         DrawSprite

    POP         a2

    addq.w      #1,Actor_CloudTick(a3)
    bra         .next

.cloud_done
    PUSH        a2
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile   ; erase final cloud frame
    POP         a2
    clr.w       Actor_CloudTick(a3)

.next
    dbra        d7,.loop

.exit
    rts


;==============================================================================
; ActionMove  -  Smooth tile-to-tile movement animation (ACTION_MOVE state)
;
; Each frame:
;   1. Advance Player_XDec by DirectionX and Player_YDec by DirectionY.
;      (DirectionX/Y is -1, 0, or +1, giving 1 pixel per frame of movement)
;   2. Show the walk animation sprite.
;   3. Decrement Player_ActionCount.  Movement takes 24 frames (1 frame per pixel).
;   4. When ActionCount reaches 0, the move is complete:
;      - Clear ActionStatus to IDLE
;      - Clear XDec/YDec (snap to exact tile position)
;      - Call PlayerMoveLogic to update GameMap (move the player in the map)
;      - Call PlayerFallLogic to check if the player should now fall
;      - Call ActorFallAll to check if any actors should now fall
;      - If actors fell, set ActionStatus to ACTION_FALL
;==============================================================================

ActionMove:
    ; Advance sub-pixel position by the movement direction (1 pixel per frame)
    move.w      Player_XDec(a4),d0
    add.w       Player_DirectionX(a4),d0
    move.w      d0,Player_XDec(a4)

    move.w      Player_YDec(a4),d0
    add.w       Player_DirectionY(a4),d0
    move.w      d0,Player_YDec(a4)

    bsr         PlayerShowWalkAnim     ; update sprite for walking animation

    subq.w      #1,Player_ActionCount(a4)  ; one frame closer to destination
    bne         .exit                   ; still moving

    ; --- Move complete (ActionCount hit 0) ---
    clr.w       ActionStatus(a5)       ; return to IDLE
    clr.w       Player_XDec(a4)        ; snap to tile boundary
    clr.w       Player_YDec(a4)

    bsr         PlayerMoveLogic        ; update GameMap: clear old cell, fill new cell
    bsr         PlayerFallLogic        ; check if the player itself should now fall

    bsr         ActorFallAll           ; check if any actors should now fall; d5 = count
    tst.w       d5
    beq         .nofall

    move.w      #ACTION_FALL,ActionStatus(a5)  ; one or more actors fell -> enter fall state

.nofall
    ; If ActionStatus is still IDLE (no player fall, no actor fall), the game has
    ; settled - snapshot now.  If ACTION_FALL is pending, defer to ActionFall.
    tst.w       ActionStatus(a5)
    bne         .exit
    bsr         TakeSnapshot

.exit
    rts


;==============================================================================
; ActionIdle  -  Idle state: poll input and trigger player actions
;
; Called every VBlank when ActionStatus = ACTION_IDLE.
; Sequence:
;   1. Check FIRE button (trigger) to switch the active player.
;   2. Clear PlayerMoved (fresh movement detection for this frame).
;   3. ActorsSavePos - snapshot current actor positions as "previous".
;   4. PlayerCheckControls - read input and (possibly) start a new action.
;   5. If ActionStatus is still IDLE after controls (no action started),
;      check if all enemies have been destroyed (CheckLevelDone).
;      If done, set LevelComplete.
;==============================================================================

ActionIdle:
    ; F9 = undo last move (one-shot: clears the key so it requires a fresh press)
    lea         Keys,a0
    tst.b       KEY_F9(a0)
    beq         .nof9
    clr.b       KEY_F9(a0)
    cmp.w       #2,SnapshotCount(a5)    ; at least one move in the undo stack?
    blt         .f9_done                ; nothing to undo: clear key, skip both
    bsr         UndoMove
    bsr         VHS_StartEffect
.f9_done
    rts

.nof9
    btst        #CONTROLB_FIRE,ControlsTrigger(a5)  ; FIRE button just pressed?
    bne         PlayerSwitch                         ; yes -> switch active player

    clr.w       PlayerMoved(a5)        ; clear "did player move this frame" flag
    bsr         ActorsSavePos          ; save all actor positions for delta detection

    bsr         PlayerCheckControls    ; process directional input; may set ActionStatus
    tst.w       ActionStatus(a5)
    bne         .exit                  ; a new action was started - we are done

    ; Still idle: check if level is complete
    bsr         CheckLevelDone         ; d3 = number of remaining enemies (0 = level done)
    tst.w       d3
    bne         .notdone
    move.w      #1,LevelComplete(a5)  ; no enemies left -> level complete

.notdone
.exit
    rts


;==============================================================================
; PlayerSwitch  -  Begin the player-switch star animation (ACTION_SWITCH)
;
; Launches the blue star animation from the active player's tile toward the
; frozen player's tile.  Both players' frozen graphics are drawn only once the
; animation completes (in ActionIntro's StarAnimContext=1 completion path).
; The actual pointer swap also happens there.
;
; If the other player's Status is 0 (inactive = not yet placed in the level),
; the switch is blocked.
;==============================================================================

PlayerSwitch:
    move.l      PlayerPtrs+4(a5),a0        ; a0 -> frozen player struct
    tst.w       Player_Status(a0)          ; is the frozen player even active?
    beq         .noswitch                  ; no - only one player placed, can't switch

    move.w      #2,Player_Status(a4)       ; mark current player as frozen

    ; Set origin = active player tile; target = frozen player tile
    ; a0 still valid: nothing between the load above and here clobbers it
    move.w      Player_X(a4),d0
    move.w      d0,StarOriginX(a5)
    move.w      Player_Y(a4),d1
    move.w      d1,StarOriginY(a5)
    move.w      Player_X(a0),d0
    move.w      d0,StarTargetX(a5)
    move.w      Player_Y(a0),d1
    move.w      d1,StarTargetY(a5)

    move.w      #1,StarAnimContext(a5)     ; switch mode (not level intro)
    bsr         StarAnimBegin              ; reset trail pool, draw initial star
    move.w      #ACTION_SWITCH,ActionStatus(a5)

.noswitch
    rts


;==============================================================================
; DrawPlayerFrozen  -  Draw the inactive player in its static frozen pose
;
; Blits the "frozen" sprite for the current player (a4) into DisplayScreen.
; The frozen sprite is:
;   - If on a ladder: Player_LadderFreezeId frame (specific ladder-idle graphic)
;   - If facing right: Player_SpriteOffset + 46 (right-facing static frame)
;   - If facing left:  Player_SpriteOffset + 47 (left-facing static frame)
;
; Uses DrawSprite (in mapstuff.asm) which blits from the Sprites sheet (not RealSprites).
; Note: DrawSprite targets DisplayScreen; ClearPlayer must be called to remove it later.
;==============================================================================

DrawPlayerFrozen:
    ; Calculate pixel position from tile coordinates
    move.w      Player_X(a4),d0
    move.w      Player_Y(a4),d1
    mulu        #24,d0
    mulu        #24,d1

    ; Select the frozen sprite frame
    moveq       #0,d2
    move.w      Player_LadderFreezeId(a4),d2   ; default: ladder freeze frame

    tst.w       Player_OnLadder(a4)     ; is the player on a ladder?
    bne         .isright                ; yes - use ladder freeze frame as-is

    ; Not on ladder: use standing still frame based on facing direction
    move.w      Player_SpriteOffset(a4),d2
    add.w       #46,d2                  ; base frozen frame (right-facing)
    tst.w       Player_Facing(a4)
    bpl         .isright                ; positive facing = right, no change

    addq.w      #1,d2                   ; +1 for left-facing frozen frame

.isright
    bsr         DrawSprite              ; blit frozen sprite into DisplayScreen
    rts


;==============================================================================
; CheckLevelDone  -  Scan GameMap for remaining enemies
;
; Walks the entire GameMap (WALL_PAPER_SIZE cells) looking for any cell that
; contains BLOCK_ENEMYFALL or BLOCK_ENEMYFLOAT.  If found, sets d3 = 1.
; If none are found, d3 = 0 (level complete).
;
; Out:  d3 = 0 if no enemies remain (level done), 1 if enemies still present
;==============================================================================

CheckLevelDone:
    lea         GameMap(a5),a0
    moveq       #WALL_PAPER_SIZE-1,d7
    moveq       #0,d3                   ; assume no enemies (done = true)

.loop
    move.b      (a0)+,d0               ; load next map cell
    cmp.b       #BLOCK_ENEMYFALL,d0
    beq         .notdone               ; found a falling enemy -> not done
    cmp.b       #BLOCK_ENEMYFLOAT,d0
    bne         .next                  ; not an enemy -> continue

.notdone
    moveq       #1,d3                  ; enemy found -> level not complete
    rts

.next
    dbra        d7,.loop
    rts                                ; d3 = 0: no enemies remain


;==============================================================================
; PlayerMoveLogic  -  Update GameMap after the active player completes a move
;
; Called when ACTION_MOVE completes (ActionCount hits 0).
; Only runs if PlayerMoved is non-zero (set by PlayerDoMove).
;
; Updates GameMap:
;   - New cell (NextX, NextY): if it was a plain BLOCK_LADDER, set it to
;     Player_LadderId (occupying a ladder cell).  Otherwise set to Player_BlockId.
;   - Old cell (X, Y): if it was a player's ladder ID, restore to BLOCK_LADDER.
;     Otherwise set to BLOCK_EMPTY.
;   - Update Player_X/Y to Player_NextX/Y.
;==============================================================================

PlayerMoveLogic:
    tst.w       PlayerMoved(a5)
    beq         .nomove                ; PlayerMoved = 0 -> no update needed

    lea         GameMap(a5),a0

    ; Calculate map offsets for current and next positions
    move.w      Player_Y(a4),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Player_X(a4),d0        ; d0 = current cell offset

    move.w      Player_NextY(a4),d1
    mulu        #WALL_PAPER_WIDTH,d1
    add.w       Player_NextX(a4),d1    ; d1 = next cell offset

    move.b      (a0,d0.w),d2           ; d2 = current cell type
    move.b      (a0,d1.w),d3           ; d3 = next cell type

    ; Write player's block ID into the next cell.
    ; If the next cell is a plain BLOCK_LADDER, use the ladder variant ID instead.
    move.b      Player_BlockId(a4),d4
    cmp.b       #BLOCK_LADDER,d3
    bne         .notladdernext
    move.b      Player_LadderId(a4),d4  ; use ladder-specific ID (MILLIELADDER/MOLLYLADDER)

.notladdernext
    move.b      d4,(a0,d1.w)           ; write player presence into next cell

    ; Clear the current cell.
    ; If it was a ladder ID, restore it to plain BLOCK_LADDER.
    move.b      #BLOCK_EMPTY,d4
    cmp.b       Player_LadderId(a4),d2
    bne         .notladderlast
    move.b      #BLOCK_LADDER,d4       ; restore the ladder

.notladderlast
    move.b      d4,(a0,d0.w)           ; write to old cell

    ; Commit tile-grid position
    move.w      Player_NextX(a4),Player_X(a4)
    move.w      Player_NextY(a4),Player_Y(a4)

.nomove
    rts


;==============================================================================
; PlayerFallLogicFrozen  -  Check if the frozen player should fall
;
; Checks the frozen (inactive) player.  If the cell it occupies is not its
; own ladder ID (i.e. not on a ladder) AND the cell below is empty, the frozen
; player starts a fall animation.
;
; Updates the frozen player's Y in GameMap (removes from old cell, adds to
; landing cell) and sets Player_Fallen = 1.
;
; This is called when the active player takes an action that might cause the
; frozen player to lose its footing (e.g. a block below the frozen player
; was pushed or destroyed).
;==============================================================================

PlayerFallLogicFrozen:
    PUSH        a4

    move.l      PlayerPtrs+4(a5),a4   ; a4 -> frozen player struct
    cmp.w       #2,Player_Status(a4)  ; is it actually frozen (status = 2)?
    bne         .exit                 ; no - not applicable

    ; Save current position as "previous" for the clear routine
    move.w      Player_X(a4),Player_PrevX(a4)
    move.w      Player_Y(a4),Player_PrevY(a4)

    lea         GameMap(a5),a0

    ; Calculate map offset for frozen player's current position
    move.w      Player_Y(a4),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Player_X(a4),d0
    move.w      d0,d1

    ; Check if frozen player is on a ladder (if so, cannot fall)
    move.b      Player_LadderId(a4),d2
    cmp.b       (a0,d1.w),d2
    beq         .exit                 ; on a ladder - safe

    ; Find how far down before hitting a floor
    moveq       #0,d3                 ; fall counter

.findfloor
    tst.b       WALL_PAPER_WIDTH(a0,d1.w)   ; is the cell below non-empty?
    bne         .found
    addq.w      #1,d3                 ; one more row to fall
    add.w       #WALL_PAPER_WIDTH,d1
    bra         .findfloor

.found
    tst.w       d3
    beq         .exit                 ; floor directly below - no fall

    ; Commit the fall: update Player_Y and GameMap
    add.w       d3,Player_Y(a4)       ; advance tile row by fall count
    clr.b       (a0,d0.w)             ; clear old map cell
    move.b      Player_BlockId(a4),(a0,d1.w) ; set new map cell (landing position)
    move.w      #1,Player_Fallen(a4)  ; signal that the frozen player fell

.exit
    POP         a4                    ; restore active player pointer
    rts


;==============================================================================
; PlayerFallLogic  -  Check if the active player should now fall
;
; Called after PlayerMoveLogic (when a move is complete).
; If the player did not move this frame, no fall check is needed.
;
; Checks the cell directly below the player's NEW position.  If empty and
; the player is not on a ladder, initiates a fall.
;
; Fall setup:
;   - Scan downward from current cell until a non-empty cell is found.
;   - Set Player_NextY to the tile just above that cell.
;   - Update GameMap: clear current cell, mark landing cell.
;   - Set Player_Fallen = 1, ActionStatus = ACTION_FALL.
;   - Reset animation frame counters.
;==============================================================================

PlayerFallLogic:
    tst.w       PlayerMoved(a5)
    beq         .exit                 ; no move this frame -> no fall check

    lea         GameMap(a5),a0

    ; Calculate map offset for current position (post-move)
    move.w      Player_Y(a4),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Player_X(a4),d0
    move.w      d0,d1

    ; Is the player currently on a ladder (their cell = LadderId)?  If so, no fall.
    move.b      Player_LadderId(a4),d2
    cmp.b       (a0,d1.w),d2
    beq         .exit

    ; Scan downward for the floor
    moveq       #0,d3                 ; fall distance in tiles

.findfloor
    tst.b       WALL_PAPER_WIDTH(a0,d1.w)  ; cell below non-empty?
    bne         .found
    addq.w      #1,d3
    add.w       #WALL_PAPER_WIDTH,d1
    bra         .findfloor

.found
    tst.w       d3
    beq         .exit                 ; floor directly below - no fall

    ; Set up fall parameters
    add.w       Player_Y(a4),d3       ; d3 = landing row (current Y + fall tiles)
    move.w      d3,Player_NextY(a4)   ; store landing tile Y
    move.w      Player_X(a4),Player_NextX(a4)  ; X unchanged during a vertical fall

    ; Update GameMap: clear current cell, mark landing cell
    clr.b       (a0,d0.w)
    move.b      Player_BlockId(a4),(a0,d1.w)

    ; Activate fall animation
    move.w      #1,Player_Fallen(a4)          ; player is now falling
    move.w      #ACTION_FALL,ActionStatus(a5) ; switch to fall state
    clr.w       Player_AnimFrame(a4)          ; reset animation frame
    clr.w       Player_ActionFrame(a4)        ; reset easing frame counter

.exit
    rts


;==============================================================================
; PlayerCheckControls  -  Dispatch to idle/frozen/inactive control handler
;
; PlayerPtrs[0] is the active player (status=1).
; PlayerPtrs[1] is the frozen player (status=2) or inactive (status=0).
;
; Uses JMPINDEX on Player_Status:
;   0 -> PlayerInactive  (character not yet placed)
;   1 -> PlayerIdle      (active, processes input)
;   2 -> PlayerFrozen    (frozen, ignores input)
;==============================================================================

PlayerCheckControls:
    move.w      Player_Status(a4),d0  ; 0=inactive, 1=active, 2=frozen
    JMPINDEX    d0

.i
    dc.w        PlayerInactive-.i
    dc.w        PlayerIdle-.i
    dc.w        PlayerFrozen-.i


;==============================================================================
; PlayerFrozen  -  Frozen player does nothing
;==============================================================================

PlayerFrozen:
    rts


;==============================================================================
; PlayerInactive  -  Inactive player (not yet placed in level) does nothing
;==============================================================================

PlayerInactive:
    rts


;==============================================================================
; PlayerIdle  -  Process player input when idle and active
;
; Reads ControlsTrigger to detect newly-pressed direction keys.
; Priority order: RIGHT, LEFT, DOWN, UP.
; Only one direction is acted upon per frame (first match wins).
;
; Special UP handling: UP only triggers a move if the player is currently
; on a ladder cell (Player_LadderId check).  You cannot walk upward through air.
;
; If a direction is found, calls PlayerTryMove to determine what action to take.
; Also calls PlayerShowIdleAnim to animate the sprite while standing still.
;==============================================================================

PlayerIdle:
    bsr         PlayerShowIdleAnim    ; update idle animation frame

    move.b      ControlsHold(a5),d0  ; d0 = newly-pressed keys this frame

    ; Clear both directions so left/right branches don't inherit a stale DirectionY
    ; from the previous frame (e.g. a ladder climb that has since ended).
    clr.w       Player_DirectionX(a4)
    clr.w       Player_DirectionY(a4)

    ; Check each direction; set DirectionX/Y and branch to .move if pressed
    move.w      #1,Player_DirectionX(a4)    ; assume right
    btst        #CONTROLB_RIGHT,d0
    bne         .move                       ; right pressed -> move right

    move.w      #-1,Player_DirectionX(a4)   ; assume left
    btst        #CONTROLB_LEFT,d0
    bne         .move                       ; left pressed -> move left

    clr.w       Player_DirectionX(a4)       ; no horizontal movement

    move.w      #1,Player_DirectionY(a4)    ; assume down
    btst        #CONTROLB_DOWN,d0
    bne         .move                       ; down pressed -> move down

    move.w      #-1,Player_DirectionY(a4)   ; assume up
    btst        #CONTROLB_UP,d0
    beq         .nomove                     ; up not pressed

    ; Up pressed: only allowed if currently on a ladder
    move.w      Player_Y(a4),d1
    mulu        #WALL_PAPER_WIDTH,d1
    add.w       Player_X(a4),d1            ; d1 = map offset of current cell

    lea         GameMap(a5),a0
    move.b      (a0,d1.w),d1               ; d1 = cell type at current position
    cmp.b       Player_LadderId(a4),d1
    beq         .move                      ; on ladder -> allow upward movement

.nomove
    clr.w       Player_DirectionY(a4)      ; cancel direction
    rts

.move
    ; A direction was chosen: update facing based on X direction
    move.w      Player_DirectionX(a4),Player_Facing(a4)
    bsr         PlayerTryMove              ; try to move in the chosen direction

.exit
    rts


;==============================================================================
; PlayerShowIdleAnim  -  Animate the player sprite while standing still
;
; Called from PlayerIdle once per frame.  Advances the animation frame every
; 5 VBlanks (TickCounter mod 5 = 0) for a slower idle cycle.
;
; Selects the appropriate animation frame based on:
;   - If on a ladder: PLAYER_SPRITE_LADDER_IDLE (single frame, no cycling)
;   - If off ladder, facing right: walk cycle frame + PLAYER_SPRITE_WALK_OFFSET
;   - If off ladder, facing left: walk cycle frame + PLAYER_SPRITE_LEFT_OFFSET
;
; Also updates Player_OnLadder based on the player's current map cell.
;==============================================================================

PlayerShowIdleAnim:
    ; Only advance animation every 5 frames
    move.w      TickCounter(a5),d0
    divu        #5,d0
    swap        d0                    ; remainder -> d0 low word
    tst.w       d0
    beq         .anim                 ; remainder = 0 -> advance
    rts                               ; skip this frame

.anim
    ; Check if on a ladder
    move.w      Player_Y(a4),d1
    mulu        #WALL_PAPER_WIDTH,d1
    add.w       Player_X(a4),d1       ; map offset

    moveq       #PLAYER_SPRITE_LADDER_IDLE,d0   ; default: ladder idle frame

    moveq       #0,d2
    lea         GameMap(a5),a0
    move.b      (a0,d1.w),d1          ; d1 = cell type at current position
    cmp.b       Player_LadderId(a4),d1
    bne         .noladder1
    moveq       #1,d2                 ; d2 = 1 means on ladder

.noladder1
    move.w      d2,Player_OnLadder(a4)  ; update on-ladder status

    bne         .isright              ; on ladder: use PLAYER_SPRITE_LADDER_IDLE

    ; Not on ladder: cycle walk animation frames 0..3
    move.w      Player_AnimFrame(a4),d0
    addq.w      #1,d0
    and.w       #3,d0
    move.w      d0,Player_AnimFrame(a4)

    ; Check if we came off a ladder (Player_OnLadder was just set to 0)
    tst.w       Player_OnLadder(a4)
    beq         .noladder

    ; Was on ladder: use ladder frame offset
    add.w       #PLAYER_SPRITE_LADDER_OFFSET,d0
    bra         .isright

.noladder
    ; Off ladder: apply left/right facing offset
    tst.w       Player_Facing(a4)
    bpl         .isright              ; positive facing = right, no extra offset
    add.w       #PLAYER_SPRITE_LEFT_OFFSET,d0  ; left-facing frames

.isright
    bsr         ShowSprite            ; display the selected animation frame
    rts


;==============================================================================
; PlayerShowWalkAnim  -  Animate the player sprite while moving
;
; Called from ActionMove every frame.  Advances the animation cycle every
; other frame (TickCounter AND 1) for walk animation.
;
; Walk animation uses 8 frames (0..7) for off-ladder, 4 frames (0..3) for
; on-ladder climbing.
;
; Frame selection:
;   On ladder:   AnimFrame (0..3) + PLAYER_SPRITE_LADDER_OFFSET
;   Off ladder, right: AnimFrame (0..7) + PLAYER_SPRITE_WALK_OFFSET
;   Off ladder, left:  (AnimFrame + PLAYER_SPRITE_LEFT_OFFSET) + PLAYER_SPRITE_WALK_OFFSET
;==============================================================================

PlayerShowWalkAnim:
    ; if Player_DirectionY is non-zero, we are definitely on a ladder (vertical movement only)
    tst.w       Player_DirectionY(a4)
    bne         .ontladder

    ; Update Player_OnLadder based on current cell type, since we can only be on a ladder if moving vertically onto it.
      move.w      Player_Y(a4),d1
      mulu        #WALL_PAPER_WIDTH,d1
      add.w       Player_X(a4),d1        ; d1 = current cell offset
      lea         GameMap(a5),a0
      move.b      (a0,d1.w),d2           ; d2 = current cell type
      moveq       #0,d3                  ; d3 = on ladder flag (default: walking)

      cmp.b       Player_LadderId(a4),d2 ; on a ladder cell?
      bne         .notlad

      ; On a ladder cell - check if we've reached the bottom and are stepping off
      move.b      WALL_PAPER_WIDTH(a0,d1.w),d4  ; d4 = cell type directly below
      cmp.b       #BLOCK_LADDER,d4 ; is cell below also a ladder?
      beq         .ontladder             ; yes - still climbing

      ; Switch to walking if we're moving horizontally away from the ladder (DirectionX non-zero).
      ; *and* there's no ladder left/right that we could climb onto

      tst.w       Player_DirectionX(a4)     ; moving left or right?
      beq         .ontladder                ; no - not moving horizontally, so still on the ladder

      ; check tile to the left/right of the Player
        add.w       Player_DirectionX(a4),d1        ; d1 = current cell offset
        move.b      (a0,d1.w),d2  ; d2 = cell type to the right
        cmp.b       #BLOCK_LADDER,d2
        bne         .notlad          

.ontladder
      moveq       #1,d3                  ; use climbing sprite

.notlad
      move.w      d3,Player_OnLadder(a4)

      ; Only advance animation every other frame
      move.w      TickCounter(a5),d0
      and.w       #1,d0
      bne         .show                 ; odd frame: show but don't advance

      ; Advance walk animation (even frames only)
      move.w      Player_AnimFrame(a4),d0
      addq.w      #1,d0

      ; Cycle limit depends on whether on ladder (0-3) or walking (0-7)
      tst.w       Player_OnLadder(a4)
      beq         .walkframes
      and.w       #3,d0                 ; ladder: cycle 0..3
      bra         .saveframe

.walkframes
      and.w       #7,d0                 ; walk: cycle 0..7
.saveframe
      move.w      d0,Player_AnimFrame(a4)

.show
      move.w      Player_AnimFrame(a4),d0

      ; Determine if on ladder or walking
      tst.w       Player_OnLadder(a4)
      beq         .walking

      ; On ladder: use ladder offset (doesn't change based on facing)
      add.w       #PLAYER_SPRITE_LADDER_OFFSET,d0
      bsr         ShowSprite
      rts

.walking
      ; Off ladder: use walk offset + facing adjustment
      move.w      #PLAYER_SPRITE_WALK_OFFSET,d1

      tst.w       Player_Facing(a4)
      bpl         .rightface
      add.w       #PLAYER_SPRITE_LEFT_OFFSET,d0  ; left-facing: offset the frame index

.rightface
      add.w       d1,d0                 ; add walk offset
      bsr         ShowSprite
      rts

;==============================================================================
; PlayerTryMove  -  Determine what action the player can take
;
; Based on Player_DirectionX/Y and the block type in the next cell,
; dispatches to the appropriate response routine.
;
; Calls PlayerGetNextBlock to read the block type at (X+DirX, Y+DirY).
; Then JMPINDEX on that block type to choose the action.
;
; Block type -> action dispatch:
;   BLOCK_EMPTY       -> PlayerDoMove   (walk into empty space)
;   BLOCK_LADDER      -> PlayerDoMove   (walk onto/off ladder)
;   BLOCK_ENEMYFALL   -> PlayerKillEnemy (kill the enemy)
;   BLOCK_PUSH        -> PlayerPushBlock (check if the block can be pushed)
;   BLOCK_DIRT        -> PlayerKillDirt  (walk through dirt, destroying it)
;   BLOCK_SOLID       -> PlayerNotMove   (blocked by wall)
;   BLOCK_ENEMYFLOAT  -> PlayerKillEnemy (kill the floating enemy)
;   BLOCK_MILLIESTART -> PlayerNotMove   (can't walk into the other player's cell)
;   BLOCK_MOLLYSTART  -> PlayerNotMove
;   BLOCK_MILLIELADDER-> PlayerMoveLadder (move along while on ladder)
;   BLOCK_MOLLYLADDER -> PlayerMoveLadder
;==============================================================================

PlayerTryMove:
    move.w      Player_DirectionX(a4),d1
    bsr         PlayerGetNextBlock    ; d2 = block type of next cell, a0 = GameMap, d0 = offset

    JMPINDEX    d2                    ; jump based on next cell's block type

.i
    dc.w        PlayerDoMove-.i       ; BLOCK_EMPTY       = 0
    dc.w        PlayerDoMove-.i       ; BLOCK_LADDER      = 1
    dc.w        PlayerKillEnemy-.i    ; BLOCK_ENEMYFALL   = 2
    dc.w        PlayerPushBlock-.i    ; BLOCK_PUSH        = 3
    dc.w        PlayerKillDirt-.i     ; BLOCK_DIRT        = 4
    dc.w        PlayerNotMove-.i      ; BLOCK_SOLID       = 5
    dc.w        PlayerKillEnemy-.i    ; BLOCK_ENEMYFLOAT  = 6
    dc.w        PlayerNotMove-.i      ; BLOCK_MILLIESTART = 7
    dc.w        PlayerNotMove-.i      ; BLOCK_MOLLYSTART  = 8
    dc.w        PlayerMoveLadder-.i   ; BLOCK_MILLIELADDER= 9
    dc.w        PlayerMoveLadder-.i   ; BLOCK_MOLLYLADDER = 10
    rts


;==============================================================================
; PlayerPushBlock  -  Attempt to push a block
;
; Only allowed for horizontal movement (DirectionX = +/-1, DirectionY = 0).
; Checks if the cell BEYOND the push block (two cells ahead) is empty.
; If so, calls PlayerMoveActor to initiate the push animation.
; If not (something blocks), the push fails silently.
;
; On entry:
;   a0 = GameMap base pointer (from PlayerGetNextBlock)
;   d0 = map offset of the PUSH block's cell
;==============================================================================

PlayerPushBlock:
    add.w       Player_DirectionX(a4),d0  ; advance to cell BEYOND the push block
    tst.b       (a0,d0.w)                 ; is the cell beyond empty?
    beq         PlayerMoveActor           ; yes -> initiate push
    rts                                   ; no  -> blocked, cannot push


;==============================================================================
; PlayerNotMove  -  Blocked move (wall or other player's cell)
; Does nothing; the player simply cannot enter that cell.
;==============================================================================

PlayerNotMove:
    rts


;==============================================================================
; PlayerMoveLadder  -  Move into a cell containing the other player's ladder marker
;
; If the next cell is BLOCK_MILLIELADDER or BLOCK_MOLLYLADDER (the other player
; is on this ladder cell), the current player can still "share" the cell by
; executing a standard move.  This is a design decision: players can be on the
; same ladder segment simultaneously.
;==============================================================================

PlayerMoveLadder:
    bsr         PlayerDoMove
    rts


;==============================================================================
; PlayerKillDirt  -  Walk into and destroy a dirt block
;
; Dirt can only be destroyed by horizontal movement (not by descending into it).
; If DirectionY is non-zero (moving vertically), the kill is blocked.
; Otherwise: move normally AND kill the actor occupying that cell.
;==============================================================================

PlayerKillDirt:
    tst.w       Player_DirectionY(a4)  ; vertical movement?
    bne         .nokill                ; yes - can't destroy dirt by moving down into it
    bsr         PlayerDoMove           ; standard move into the cell
    bsr         PlayerKillActor        ; remove the dirt actor and clear its screen tile
.nokill
    rts


;==============================================================================
; PlayerKillEnemy  -  Walk into and destroy an enemy
;
; Enemies can only be killed by horizontal movement (same rule as dirt).
; Killing also triggers CleanActors (compact the actor list) and SortActors
; (re-sort by Y for correct draw order).
;==============================================================================

PlayerKillEnemy:
    tst.w       Player_DirectionY(a4)  ; vertical movement?
    bne         .nokill                ; yes - can't kill enemies from above/below
    bsr         PlayerDoMove
    bsr         PlayerKillActor
    bsr         CleanActors            ; compact actor list (remove dead slots)
    bsr         SortActors             ; re-sort by Y for correct rendering order
.nokill
    rts


;==============================================================================
; PlayerDoMove  -  Commit a tile-to-tile move
;
; Sets up all state for a standard 24-step movement animation:
;   - PlayerMoved = 1 (signals PlayerMoveLogic to update GameMap)
;   - Player_NextX/Y = target tile
;   - ActionStatus = ACTION_MOVE
;   - Player_ActionCount = 24 (one frame per pixel)
;   - Clear XDec/YDec (start sub-pixel at 0)
;==============================================================================

PlayerDoMove:
    move.w      #1,PlayerMoved(a5)    ; flag that the player is moving this frame

    ; Calculate destination tile
    move.w      Player_DirectionX(a4),d0
    add.w       Player_X(a4),d0       ; d0 = target X tile
    move.w      Player_DirectionY(a4),d1
    add.w       Player_Y(a4),d1       ; d1 = target Y tile

    move.w      d0,Player_NextX(a4)   ; store target X
    move.w      d1,Player_NextY(a4)   ; store target Y

    move.w      #ACTION_MOVE,ActionStatus(a5)  ; switch to MOVE state
    move.w      #24,Player_ActionCount(a4)     ; 24 frames = 1 pixel/frame for 24px tile

    clr.w       Player_XDec(a4)       ; start sub-pixel offsets at 0
    clr.w       Player_YDec(a4)
    rts


;==============================================================================
; PlayerMoveActor  -  Initiate a block-push animation
;
; Searches ActorList for the actor at (Player_X + DirectionX, Player_Y).
; When found:
;   - Advances the actor's X by DirectionX (moves it one tile)
;   - Updates GameMap: clears the old cell, writes the actor's type to the new cell
;   - Sets Actor_Delta = 0 (easing accumulator reset)
;   - Sets ActionStatus = ACTION_PLAYERPUSH
;   - Stores the actor pointer in PushedActor for ActionPlayerPush to use
;   - Clears actor animation state (XDec, YDec, DirectionY, ActionCounter)
;
; Also initiates PlayerDoMove so the player walks into the block's old cell.
;==============================================================================

PlayerMoveActor:
    move.w      ActorCount(a5),d7
    beq         .exit                 ; no actors - nothing to push
    subq.w      #1,d7

    ; Calculate the position of the block to push (one tile ahead)
    move.w      Player_X(a4),d0
    move.w      Player_Y(a4),d1
    add.w       Player_DirectionX(a4),d0  ; d0 = X of the block

    lea         ActorList(a5),a2       ; a2 -> sorted actor pointer list

.loop
    move.l      (a2)+,a3              ; a3 -> next actor
    tst.w       Actor_Status(a3)      ; alive?
    beq         .next
    cmp.w       Actor_X(a3),d0        ; X matches?
    bne         .next
    cmp.w       Actor_Y(a3),d1        ; Y matches?
    bne         .next

    ; Found the block: advance its tile X position
    move.w      Player_DirectionX(a4),d2
    add.w       d2,Actor_X(a3)        ; actor X += direction
    move.w      #1,Actor_HasMoved(a3)  ; mark the actor as having moved (for ActionPlayerPush)

    ; Update GameMap: clear old cell, set new cell
    mulu        #WALL_PAPER_WIDTH,d1
    add.w       d1,d0                 ; d0 = map offset of old cell
    add.w       d0,d2                 ; d2 = map offset of new cell
    lea         GameMap(a5),a0
    move.b      (a0,d0.w),(a0,d2.w)   ; copy block type to new cell
    clr.b       (a0,d0.w)             ; clear old cell

    ; Initialise push animation
    clr.l       Actor_Delta(a3)       ; reset easing accumulator
    move.w      #ACTION_PLAYERPUSH,ActionStatus(a5)  ; enter push state
    move.l      a3,PushedActor(a5)   ; remember which actor is being pushed

    clr.w       Actor_XDec(a3)
    clr.w       Actor_YDec(a3)
    move.w      Player_DirectionX(a4),Actor_DirectionX(a3)  ; set push direction
    clr.w       Actor_DirectionY(a3)
    clr.w       ActionCounter(a3)    ; reset push frame counter

    bra         .exit                 ; found the block - done

.next
    add.w       #Actor_Sizeof,a3      ; advance to next actor
    dbra        d7,.loop

.exit
    rts


;==============================================================================
; ActorFallAll  -  Check all eligible actors for falls and initiate them
;
; Iterates all live actors with Actor_CanFall = 1.
; For each such actor, calls ActorFall to check if it should fall.
; If ActorFall sets Actor_HasFalled (d3 != 0 on return), the actor is added
; to the FallenActors list for ActionFallActors to process each frame.
;
; Out:
;   d5 = total number of actors that will now fall (0 = no falls)
;   FallenActorsCount(a5) = d5
;==============================================================================

ActorFallAll:
    moveq       #0,d5                 ; d5 = total actors now falling

    move.w      ActorCount(a5),d7
    bne         .go
    rts

.go
    lea         ActorList(a5),a0       ; a0 -> sorted actor pointer array
    lea         FallenActors(a5),a2    ; a2 -> fallen actor pointer array (write cursor)
    subq.w      #1,d7

.loop
    move.l      (a0)+,a3              ; a3 -> next actor
    tst.w       Actor_Status(a3)      ; alive?
    beq         .nofall
    tst.w       Actor_CanFall(a3)     ; subject to gravity?
    beq         .nofall

    PUSH        a0                    ; preserve list read pointer (ActorFall uses a0)
    bsr         ActorFall             ; check/initiate fall; d3 = 0 if no fall, non-zero if falling
    POP         a0

    tst.w       d3
    beq         .nofall               ; actor did not fall

    add.w       #1,d5                 ; increment falling count
    move.l      a3,(a2)+              ; add actor to FallenActors list

.nofall
    dbra        d7,.loop

    move.w      d5,FallenActorsCount(a5)  ; store count for ActionFallActors
    rts


;==============================================================================
; ActorDrawStatic  -  Draw an actor at its current tile position
;
; Blits the actor's sprite tile into DisplayScreen at its tile-aligned position.
; Used to redraw an actor after it has landed at a new position.
;==============================================================================

ActorDrawStatic:
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    mulu        #24,d0
    mulu        #24,d1
    moveq       #0,d2
    move.w      Actor_SpriteOffset(a3),d2
    lea         DisplayScreen,a1
    bsr         PasteTile
    rts


;==============================================================================
; ActorFall  -  Check if an actor should fall and set it up if so
;
; Scans the cells below the actor's current position in GameMap until a
; non-empty cell is found.  The count of empty cells is the fall distance.
;
; If the actor is directly supported (cell below non-empty), no fall occurs
; and d3 = 0 on return.
;
; If the actor should fall:
;   - Actor_Y is advanced by the fall tile count
;   - Actor_FallY is set to (fall_tiles * 24) pixels (target for YDec)
;   - Actor_HasFalled = 1
;   - GameMap is updated: old cell cleared, new cell gets the actor type
;   - d3 = non-zero
;
; On entry:  a3 = actor struct pointer
; Destroys:  a0, d0, d1, d3
;==============================================================================

ActorFall:
    lea         GameMap(a5),a0

    ; Calculate map offset for actor's current position
    move.w      Actor_Y(a3),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Actor_X(a3),d0
    move.w      d0,d1                 ; d1 = current map offset

    moveq       #0,d3                 ; fall distance (tiles)

.findfloor
    tst.b       WALL_PAPER_WIDTH(a0,d1.w)   ; is the cell below non-empty?
    bne         .found
    addq.w      #1,d3                 ; fall one more row
    add.w       #WALL_PAPER_WIDTH,d1  ; advance map offset one row
    bra         .findfloor

.found
    tst.w       d3
    beq         .exit                 ; no fall (floor is directly below)

    ; Commit the fall
    add.w       d3,Actor_Y(a3)        ; advance actor Y by fall distance
    mulu        #24,d3                ; convert tiles to pixels (for YDec animation target)
    move.w      d3,Actor_FallY(a3)   ; set pixel target for fall animation
    move.w      #1,Actor_HasFalled(a3)    ; mark as falling
    move.b      (a0,d0.w),(a0,d1.w)  ; copy actor type from old to new map cell
    clr.b       (a0,d0.w)            ; clear old map cell

.exit
    rts


;==============================================================================
; PlayerKillActor  -  Find and kill an actor at the player's next position
;
; Searches ActorList for a live actor at (Player_NextX, Player_NextY).
; When found: sets Actor_Status = 0 (dead), clears the GameMap cell,
; and calls RestoreBackgroundTile to erase it from DisplayScreen.
;
; Also erases it from DisplayScreen by calling RestoreBackgroundTile.
;
; Note: CleanActors must be called separately to compact the ActorList.
;==============================================================================

PlayerKillActor:
    move.w      ActorCount(a5),d7
    beq         .exit                 ; no actors
    subq.w      #1,d7

    ; Target position = where the player is moving to
    move.w      Player_NextX(a4),d0
    move.w      Player_NextY(a4),d1

    lea         ActorList(a5),a2

.loop
    move.l      (a2)+,a3
    tst.w       Actor_Status(a3)
    beq         .next
    cmp.w       Actor_X(a3),d0        ; X matches?
    bne         .next
    cmp.w       Actor_Y(a3),d1        ; Y matches?
    bne         .next

    ; Found the actor to kill - register cloud animation for enemy types only
    move.w      Actor_Type(a3),d2
    cmp.w       #BLOCK_ENEMYFALL,d2
    beq         .setup_cloud
    cmp.w       #BLOCK_ENEMYFLOAT,d2
    bne         .skip_cloud             ; not an enemy: skip cloud setup

.setup_cloud
    ; Add to CloudActors list (bounds-checked; max MAP_SIZE entries)
    move.w      CloudActorsCount(a5),d2
    cmp.w       #MAP_SIZE,d2
    bge         .skip_cloud             ; safety: pool full, skip cloud setup
    lea         CloudActors(a5),a0
    lsl.w       #2,d2                   ; byte offset = index * 4 (pointer size)
    move.l      a3,(a0,d2.w)            ; CloudActors[count] = a3
    addq.w      #1,CloudActorsCount(a5)

    move.w      #1,Actor_CloudTick(a3)  ; start cloud animation on tick 1

.skip_cloud
    clr.w       Actor_Status(a3)        ; mark as dead

    ; Clear the actor's cell in GameMap
    mulu        #WALL_PAPER_WIDTH,d1
    add.w       d1,d0
    lea         GameMap(a5),a0
    clr.b       (a0,d0.w)

    ; Erase from screen
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile        ; erase tile from DisplayScreen
    bra         .exit

.next
    dbra        d7,.loop

.exit
    rts


;==============================================================================
; ClearPlayer  -  Erase the active player from DisplayScreen
;
; Restores the 24x24 pixel area at the player's current tile position from
; NonDisplayScreen into DisplayScreen.  Used when switching from active to frozen.
;
; The blit uses minterm $7ca combined with a constant mask to select which
; words to write.  The mask depends on whether the player's X is on the left
; or right word boundary:
;   X AND $f = 0 (left-aligned): mask = $ffffff00 (write first 3 bytes of each word)
;   X AND $f != 0 (shifted):     mask = $00ffffff (write last 3 bytes)
;
; The blitter writes a constant $ffff (all ones) from BLTADAT, gated by the
; mask in BLTAFWM, combined with the source from NonDisplayScreen (B) and
; current DisplayScreen (C).
; Minterm $7ca = (~A&B&C) | (A&B) | (~A&~B&C) simplifies to: where mask=1 use B, else C.
; Effectively: copy NonDisplayScreen (B) to DisplayScreen (D) in the masked region.
;==============================================================================

ClearPlayer:
    PUSHALL
    lea         NonDisplayScreen,a0          ; source: clean background
    lea         DisplayScreen,a1        ; destination: current display buffer

    ; Calculate player pixel position
    move.w      Player_X(a4),d0
    move.w      Player_Y(a4),d1
    mulu        #24,d0
    mulu        #24,d1

    ; Calculate byte offset in screen buffers
    mulu        #SCREEN_STRIDE,d1
    move.w      d0,d2
    asr.w       #3,d2                  ; byte column
    add.w       d2,d1
    add.l       d1,a0                  ; a0 -> source position
    add.l       d1,a1                  ; a1 -> destination position

    ; Choose mask based on X alignment
    move.l      #$ffffff00,d1          ; default: left-aligned mask
    and.w       #$f,d0                 ; X mod 16
    beq         .left
    move.l      #$00ffffff,d1          ; shifted: right-aligned mask

.left
    WAITBLIT
    move.l      #$7ca<<16,BLTCON0(a6)  ; BLTCON0: minterm $7ca, no shift
    move.l      d1,BLTAFWM(a6)         ; first+last word mask
    move.w      #-1,BLTADAT(a6)        ; A data register = $ffff (constant ones)
    move.l      a0,BLTBPT(a6)          ; B = NonDisplayScreen (clean background)
    move.l      a1,BLTCPT(a6)          ; C = DisplayScreen (current display)
    move.l      a1,BLTDPT(a6)          ; D = DisplayScreen (output)
    move.w      #0,BLTAMOD(a6)         ; A is constant (no DMA, just BLTADAT)
    move.w      #TILE_BLT_MOD,BLTBMOD(a6)
    move.w      #TILE_BLT_MOD,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE,BLTSIZE(a6)
    POPALL
    rts


;==============================================================================
; RestoreBackgroundTile  -  Erase a tile-aligned block from DisplayScreen
;
; Identical logic to ClearPlayer but takes its coordinates from d0 (X tile)
; and d1 (Y tile) in tile units (not pixels - multiplied by 24 inside).
;
; Used by:
;   ClearMovedActors  - erase actors from their previous tile position
;   PlayerKillActor   - erase a killed actor
;   ClearFrozenPlayer - erase the frozen player after it falls
;
; On entry:
;   d0 = tile X  (multiplied by 24 to get pixels inside)
;   d1 = tile Y
;   a5, a6 as usual
;==============================================================================

RestoreBackgroundTile:
    PUSHALL
    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1

    mulu        #24,d0                 ; pixel X
    mulu        #24,d1                 ; pixel Y

    mulu        #SCREEN_STRIDE,d1
    move.w      d0,d2
    asr.w       #3,d2
    add.w       d2,d1
    add.l       d1,a0
    add.l       d1,a1

    move.l      #$ffffff00,d1
    and.w       #$f,d0
    beq         .left
    move.l      #$00ffffff,d1

.left
    WAITBLIT
    move.l      #$7ca<<16,BLTCON0(a6)
    move.l      d1,BLTAFWM(a6)
    move.w      #-1,BLTADAT(a6)
    move.l      a0,BLTBPT(a6)
    move.l      a1,BLTCPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #TILE_BLT_MOD,BLTBMOD(a6)
    move.w      #TILE_BLT_MOD,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE,BLTSIZE(a6)
    POPALL
    rts


;==============================================================================
; ClearActor  -  Erase a (potentially sub-pixel-shifted) actor from DisplayScreen
;
; Unlike RestoreBackgroundTile which uses tile coordinates, ClearActor uses the
; actor's PrevX/PrevY tile position PLUS XDec/YDec sub-tile offsets to compute
; the exact pixel position.  This correctly erases an actor that is mid-animation.
;
; The mask applied to the blit depends on the X pixel offset modulo 16:
;   If offset >= 9: use the 3-word (fat) blit with first-word mask from ClearMasks
;   If offset <  9: use the 2-word (thin) blit with same mask but different modulos
;
; ClearMasks[d1*4] provides the pre-computed mask longword for each of the
; 16 possible sub-pixel X offsets.  The mask is used in BLTAFWM.
;
; After clearing, DrawActor redraws the actor at its new (advanced) position.
;
; On entry:
;   a3 = actor structure pointer
;   a5, a6 as usual
;==============================================================================

ClearActor:
    PUSHMOST

    ; Compute pixel position from previous tile + sub-pixel offsets
    move.w      Actor_PrevX(a3),d0
    mulu        #24,d0
    add.w       Actor_XDec(a3),d0     ; pixel X = PrevX*24 + XDec

    move.w      Actor_PrevY(a3),d1
    mulu        #24,d1
    add.w       Actor_YDec(a3),d1     ; pixel Y = PrevY*24 + YDec

    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1

    mulu        #SCREEN_STRIDE,d1
    move.w      d0,d2
    asr.w       #3,d2
    add.w       d2,d1
    add.l       d1,a0
    add.l       d1,a1

    ; Look up the pre-computed mask for this X sub-pixel offset
    lea         ClearMasks(a5),a2
    and.w       #$f,d0                 ; d0 = X mod 16 (0..15)
    move.w      d0,d1
    add.w       d1,d1                  ; d1 = d0 * 2
    add.w       d1,d1                  ; d1 = d0 * 4 (longword index)
    move.l      (a2,d1.w),d1          ; d1 = mask longword for this shift

    cmp.w       #9,d0                  ; shift >= 9 -> fat (3-word) blit
    bcs         .left                  ; shift < 9  -> thin (2-word) blit

    ; Fat blit (shift >= 9): 3 words wide, adjusted modulos
    WAITBLIT
    move.l      #$7ca<<16,BLTCON0(a6)
    move.l      d1,BLTAFWM(a6)
    move.w      #-1,BLTADAT(a6)
    move.l      a0,BLTBPT(a6)
    move.l      a1,BLTCPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #TILE_BLT_MOD-2,BLTBMOD(a6) ; -2: 3 words per row vs 2
    move.w      #TILE_BLT_MOD-2,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD-2,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE+1,BLTSIZE(a6) ; +1 word for the extra column

    POPMOST
    rts

.left
    ; Thin blit (shift < 9): 2 words wide
    WAITBLIT
    move.l      #$7ca<<16,BLTCON0(a6)
    move.l      d1,BLTAFWM(a6)
    move.w      #-1,BLTADAT(a6)
    move.l      a0,BLTBPT(a6)
    move.l      a1,BLTCPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #TILE_BLT_MOD,BLTBMOD(a6)
    move.w      #TILE_BLT_MOD,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE,BLTSIZE(a6)

    POPMOST
    rts


;==============================================================================
; PlayerGetNextBlock  -  Return the block type at the cell the player will enter
;
; Calculates the map offset of (Player_X + DirectionX, Player_Y + DirectionY)
; and reads the block type from GameMap.
;
; On entry:
;   a4 = player struct pointer
;   a5 = Variables base
;
; On exit:
;   d0 = map offset (byte offset into GameMap)
;   d2 = block type at the next cell  (BLOCK_xxx)
;   a0 = GameMap base pointer  (callers use this for further checks)
;
; Note: DirectionX and DirectionY reflect the player's intended move direction.
;       One of them should be 0 and the other +/-1 for a valid move.
;==============================================================================

PlayerGetNextBlock:
    ; Calculate target row contribution: (Y + DirY) * WALL_PAPER_WIDTH
    move.w      Player_Y(a4),d0
    add.w       Player_DirectionY(a4),d0    ; target row
    mulu        #WALL_PAPER_WIDTH,d0

    ; Add target column: (X + DirX)
    add.w       Player_X(a4),d0            ; + current column
    add.w       Player_DirectionX(a4),d0   ; + column direction

    lea         GameMap(a5),a0
    moveq       #0,d2
    move.b      (a0,d0.w),d2              ; read block type at target cell
    rts
