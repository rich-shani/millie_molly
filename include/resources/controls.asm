
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
; ReadControls  -  Sample keyboard and build control byte
;
; Reads the Keys[] array (set by KeyboardInterrupt) and packs the state of
; the five game control keys into the low 5 bits of d0.
;
; Out:
;   d0.b = control bits:
;     bit 0 = UP    (1 if cursor-up   is held)
;     bit 1 = DOWN  (1 if cursor-down is held)
;     bit 2 = LEFT  (1 if cursor-left is held)
;     bit 3 = RIGHT (1 if cursor-right is held)
;     bit 4 = FIRE  (1 if Space is held)
;
; Uses the KeyTest macro (defined in macros.asm) which checks Keys[scan_code]
; and sets the corresponding bit in d0 if non-zero.
; a0 must point to the Keys base - set here, assumed by KeyTest.
;==============================================================================

ReadControls:
    moveq      #0,d0                 ; clear result byte (all keys up)
    lea        Keys,a0               ; a0 = base of Keys[] scan-code buffer

    KeyTest    $4c,CONTROLB_UP       ; cursor UP    -> bit 0
    KeyTest    $4d,CONTROLB_DOWN     ; cursor DOWN  -> bit 1
    KeyTest    $4f,CONTROLB_LEFT     ; cursor LEFT  -> bit 2
    KeyTest    $4e,CONTROLB_RIGHT    ; cursor RIGHT -> bit 3
    KeyTest    $40,CONTROLB_FIRE     ; Space bar    -> bit 4

    rts
