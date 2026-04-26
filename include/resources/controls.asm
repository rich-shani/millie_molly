
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; controls.asm  -  Player Input Reading and Trigger Detection
;==============================================================================
;
; Reads the current keyboard state from the Keys[] buffer (populated by the
; CIA-A keyboard interrupt handler in keyboard.asm) and produces two control
; bytes stored in the Variables block:
;
;   ControlsHold    - bit set for EVERY frame the key is held down
;   ControlsTrigger - bit set ONLY on the first frame a key is pressed (edge)
;
; Control byte bit layout (same for both Hold and Trigger):
;   bit 4 = FIRE  (Space bar)   - switch active player
;   bit 3 = RIGHT (cursor right)
;   bit 2 = LEFT  (cursor left)
;   bit 1 = DOWN  (cursor down)
;   bit 0 = UP    (cursor up)
;
; Keyboard raw scan-codes mapped (these are the Amiga CIA scan-codes):
;   $4c = cursor UP
;   $4d = cursor DOWN
;   $4f = cursor LEFT
;   $4e = cursor RIGHT
;   $40 = Space bar (FIRE / switch player)
;
;==============================================================================


;==============================================================================
; UpdateControls  -  Read input and update Hold + Trigger bytes
;
; Must be called once per frame (from GameRun via VBlankTick).
;
; Calls ReadControls to get the raw current-frame state in d0, then calls
; StoreControls to perform edge-detection and update the two control bytes.
;
; No arguments.  Destroys d0.
;==============================================================================

UpdateControls:
    bsr        ReadControls           ; d0 = current frame raw control bits


;==============================================================================
; StoreControls  -  Compute edge-triggered (trigger) byte from hold state
;
; Entry points:
;   StoreControls1 - with a3 = ControlsHold (for external calls)
;   StoreControls  - direct entry (a3 already set by UpdateControls fall-through)
;
; On entry:
;   d0 = new raw control state (current frame)
;   a3 = pointer to ControlsHold byte
;
; Algorithm (edge detection):
;   prev_hold = ControlsHold    ; read previous frame's hold state
;   ControlsHold = d0           ; store new hold state
;   trigger = (prev_hold ^ d0) & d0
;            = bits that CHANGED between frames AND are now SET
;            = bits that transitioned 0->1 this frame (new presses only)
;   ControlsTrigger = trigger   ; stored at -1(a3), i.e. the byte before ControlsHold
;
; Note: ControlsTrigger is defined one byte before ControlsHold in the Variables
; layout (variables.asm), so -1(a3) addresses it correctly once a3 = &ControlsHold.
;==============================================================================

StoreControls1:
    lea        ControlsHold(a5),a3   ; a3 -> ControlsHold byte

StoreControls:
    move.b     (a3),d1               ; d1 = previous frame hold state
    move.b     d0,(a3)               ; update ControlsHold with current state
    eor.b      d1,d0                 ; d0 = bits that changed (XOR prev and new)
    and.b      (a3),d0               ; keep only bits that are now SET (new presses)
    move.b     d0,-1(a3)             ; store to ControlsTrigger (one byte before Hold)
    rts


;==============================================================================
; ReadControls  -  Sample joystick (priority) then keyboard, build control byte
;
; First reads the joystick (port 1) for input.  If joystick provides any input,
; returns that immediately.  Otherwise falls through to keyboard input.
;
; Out:
;   d0.b = control bits:
;     bit 0 = UP    (1 if cursor-up   is held)
;     bit 1 = DOWN  (1 if cursor-down is held)
;     bit 2 = LEFT  (1 if cursor-left is held)
;     bit 3 = RIGHT (1 if cursor-right is held)
;     bit 4 = FIRE  (1 if fire button is held)
;
; Joystick priority means if the joystick provides any input, keyboard is ignored.
; If no joystick input, keyboard is checked instead.
;==============================================================================

ReadControls:
    bsr        ReadJoystick          ; d0 = joystick control bits
    tst.b      d0                    ; any joystick input?
    bne        .done                 ; yes - use joystick, skip keyboard

    ; No joystick input - fall back to keyboard
    moveq      #0,d0                 ; clear result byte (all keys up)
    lea        Keys,a0               ; a0 = base of Keys[] scan-code buffer

    KeyTest    $4c,CONTROLB_UP       ; cursor UP    -> bit 0
    KeyTest    $4d,CONTROLB_DOWN     ; cursor DOWN  -> bit 1
    KeyTest    $4f,CONTROLB_LEFT     ; cursor LEFT  -> bit 2
    KeyTest    $4e,CONTROLB_RIGHT    ; cursor RIGHT -> bit 3
    KeyTest    $40,CONTROLB_FIRE     ; Space bar    -> bit 4

.done
    rts


;==============================================================================
; ReadJoystick  -  Read joystick port 1 and return control bits
;
; Reads the Amiga joystick hardware (port 1) and decodes it into the standard
; control byte format used by the rest of the game.
;
; Joystick bits decoded from JOY1DAT:
;   bit 0 = Y0 (up/down, inverted: 0=up, 1=down)
;   bit 1 = X0 (left/right, inverted: 0=left, 1=right)
;   bit 8 = Y1
;   bit 9 = X1
;
; Direction logic:
;   UP    = Y1=0 and Y0=1
;   DOWN  = Y1=1 and Y0=0
;   LEFT  = X1=0 and X0=1
;   RIGHT = X1=1 and X0=0
;   FIRE  = CIAAPRA bit 6 = 0 (fire button active-low)
;
; Out:
;   d0.b = control bits (same format as keyboard):
;     bit 0 = UP
;     bit 1 = DOWN
;     bit 2 = LEFT
;     bit 3 = RIGHT
;     bit 4 = FIRE (joystick button 1)
;
; Preserves all other registers.
;==============================================================================

ReadJoystick:
    movem.l    d1-d2/a0-a1,-(a7)    ; save working registers

    moveq      #0,d0                ; clear result byte

    ; Read joystick direction bits from JOY1DAT
    lea        $dff000,a0           ; custom chip base
    move.w     $00c(a0),d1          ; d1 = JOY1DAT

    ; Up: Y1=1 and Y0=0 (quad counter 10 = up)
    move.w     d1,d2
    btst       #8,d2
    beq.s      .notup
    btst       #0,d2
    bne.s      .notup
    bset       #CONTROLB_UP,d0
.notup

    ; Down: Y1=0 and Y0=1 (quad counter 01 = down)
    move.w     d1,d2
    btst       #8,d2
    bne.s      .notdown
    btst       #0,d2
    beq.s      .notdown
    bset       #CONTROLB_DOWN,d0
.notdown

    ; Left: X1=1 and X0=0 (quad counter 10 = left)
    move.w     d1,d2
    btst       #9,d2
    beq.s      .notleft
    btst       #1,d2
    bne.s      .notleft
    bset       #CONTROLB_LEFT,d0
.notleft

    ; Right: X1=0 and X0=1 (quad counter 01 = right)
    move.w     d1,d2
    btst       #9,d2
    bne.s      .notright
    btst       #1,d2
    beq.s      .notright
    bset       #CONTROLB_RIGHT,d0
.notright

    ; Fire button: CIAAPRA bit 6, active-low (0 = pressed).
    ; move.b only writes bits 0-7; bit 8 would still hold JOY1DAT's Y1 from
    ; the .notright check above, so the bit number must be 0-7.
    lea        $bfe001,a1           ; CIAA base
    move.b     (a1),d2              ; read CIAAPRA into bits 0-7
    btst       #6,d2                ; bit 6 = joystick 1 fire (0 = pressed)
    bne.s      .notfire
    bset       #CONTROLB_FIRE,d0
.notfire

    movem.l    (a7)+,d1-d2/a0-a1
    rts
