;==============================================================================
; vhs_rewind.asm  -  VHS Cassette Rewind Screen Effect
; Amiga 68000 Assembly / OCS-ECS Chipset
;
; Triggered on F9 (UndoMove): desaturates the palette, applies per-frame
; colour-channel noise, per-scanline BPLCON1 horizontal jitter, and a
; periodic one-frame vertical roll blip via bitplane pointer offset.
;
; PUBLIC API
;   VHS_Init         - call once in GameInit (after copper list is live)
;   VHS_StartEffect  - trigger the effect (ActionIdle, after bsr UndoMove)
;   VHS_StopEffect   - cancel early if needed
;   VHS_DoFrame      - call every VBlank; d0=1 active, d0=0 just finished
;   VHS_StateActive  - byte flag: non-zero while effect is running
;
; All routines preserve a5 (Variables) and a6 (CUSTOM).
; VHS_DoFrame returns result in d0; all other registers preserved by all routines.
;
; TUNING: adjust the EQUs below to change effect intensity without touching code.
;==============================================================================

VHS_EFFECT_DURATION EQU  30          ; frames at full effect (~0.6 s at 50 Hz PAL)
VHS_LFSR_POLY       EQU  $80000057   ; Galois LFSR polynomial (maximal-length 32-bit)
VHS_NOISE_BITS      EQU  $0111       ; XOR mask: bits 0,4,8 = B/G/R channel LSBs

; --- Scanline jitter (BPLCON1 copper slots in cpVHSDistort) ---
; Screen splits into three regions; one copper WAIT+BPLCON1 slot per region.
; Slots always carry valid scanlines so no slot blocks subsequent ones.
; VHS_HSHIFT_MASK is ANDed with the LFSR byte; set bits choose which colour-clock
; steps are possible.  $05 (bits 0,2) yields steps {0,1,4,5} → BPLCON1 $00/$11/$44/$55
; = 0/2/8/10 lo-res pixels.  Use $03 for subtle 0-6 px, $07 for 0-14 px maximum.
VHS_SLOT0_BASE      EQU  $2c         ; region 0 start: display top      (line  44)
VHS_SLOT1_BASE      EQU  $74         ; region 1 start: middle third      (line 116)
VHS_SLOT2_BASE      EQU  $bc         ; region 2 start: bottom third      (line 188)
VHS_SLOT_RAND       EQU  $3f         ; random line spread within region  (0-63 lines)
VHS_HSHIFT_MASK     EQU  $05         ; AND mask: bits 0,2 → steps {0,1,4,5} = 0/2/8/10 px

; --- Vertical roll blip (bitplane pointer offset) ---
; Every VHS_ROLL_INTERVAL frames the display jumps up by VHS_ROLL_LINES rows
; for exactly one frame then snaps back - classic VHS tracking roll.
; Increase VHS_ROLL_LINES for a larger jump, decrease VHS_ROLL_INTERVAL for
; more frequent rolls.
VHS_ROLL_INTERVAL   EQU  10          ; frames between roll events (~0.2 s at 50 Hz PAL)
VHS_ROLL_LINES      EQU  8           ; rows to offset during the blip (8 rows = 1680 bytes)
VHS_ROLL_BYTES      EQU  VHS_ROLL_LINES*SCREEN_STRIDE  ; byte delta for BPLxPT offset

;==============================================================================
; Fast RAM BSS  (CPU-only; zeroed by OS at load)
;==============================================================================

    section  mem_fast,bss

VHS_StateActive:    ds.b  1   ; non-zero while effect runs (exported symbol)
                    ds.b  1   ; alignment pad
VHS_FrameCount:     ds.w  1   ; frames elapsed since VHS_StartEffect
VHS_SavedPal:       ds.w  32  ; original colour values captured from cpPal
VHS_DesPal:         ds.w  32  ; desaturated + darkened palette
VHS_RollTimer:      ds.w  1   ; countdown to next vertical roll event
VHS_RollActive:     ds.b  1   ; non-zero = roll applied this frame; restore next frame
                    ds.b  1   ; alignment pad

;==============================================================================
; Fast RAM DATA  (LFSR seed must be non-zero, so cannot live in BSS)
;==============================================================================

    section  data_fast,data

VHS_LFSR:           dc.l  $DEADBEEF

;==============================================================================
; Code
;==============================================================================

    section  main,code

;------------------------------------------------------------------------------
; VHS_Init
; Call once in GameInit after the copper list is live.
; No-op for Phase 1: LFSR is pre-seeded in the data section.
;------------------------------------------------------------------------------

VHS_Init:
    rts

;------------------------------------------------------------------------------
; VHS_StartEffect
; Snapshot cpPal colour values, compute the desaturated VHS palette, apply
; it immediately to cpPal, and start the frame counter.
;
; If already active (F9 pressed a second time mid-effect), only resets the
; frame counter so the effect continues from the correct desaturated base
; rather than re-snapshotting a palette that is already desaturated.
;
; Preserves all registers.
;------------------------------------------------------------------------------

VHS_StartEffect:
    movem.l  d0-d3/d7/a0-a1,-(sp)

    tst.b    VHS_StateActive
    bne      .activate             ; already running: skip snapshot, just reset timer

    ;--- Snapshot: cpPal colour values -> VHS_SavedPal -----------------------
    ; cpPal copper entry layout: dc.w COLORxx, colour_value  (4 bytes each)
    ; The colour value word sits at byte offset +2 within each 4-byte pair.
    lea      cpPal+2,a0            ; a0 -> first colour value word
    lea      VHS_SavedPal,a1
    moveq    #32-1,d7
.snap:
    move.w   (a0),(a1)+
    addq.l   #4,a0                 ; next copper pair
    dbra     d7,.snap

    ;--- Desaturate: VHS_SavedPal -> VHS_DesPal ------------------------------
    ; Per OCS colour $0RGB (4 bits/channel, range 0-15):
    ;   grey  = (R+G+B)*85 >> 8   (integer approximation of /3, error <= 1)
    ;   new_c = (c + grey) >> 1   (lerp 50% toward grey = half-saturation)
    ;   new_c = new_c - new_c>>2  (darken to 75% brightness)
    lea      VHS_SavedPal,a0
    lea      VHS_DesPal,a1
    moveq    #32-1,d7
.desat:
    move.w   (a0)+,d0              ; d0 = source colour $0RGB

    ; extract channels into d0=B, d1=R, d2=G
    move.w   d0,d1
    lsr.w    #8,d1
    and.w    #$F,d1                ; d1 = R (0..15)
    move.w   d0,d2
    lsr.w    #4,d2
    and.w    #$F,d2                ; d2 = G (0..15)
    and.w    #$F,d0                ; d0 = B (0..15)

    ; grey = (R+G+B)*85 >> 8
    move.w   d1,d3
    add.w    d2,d3
    add.w    d0,d3                 ; d3 = R+G+B (0..45)
    mulu.w   #85,d3
    lsr.l    #8,d3
    and.w    #$F,d3                ; d3 = grey (0..14)

    ; desaturate 50%: new = (ch + grey) >> 1
    add.w    d3,d1
    lsr.w    #1,d1                 ; new R
    add.w    d3,d2
    lsr.w    #1,d2                 ; new G
    add.w    d3,d0
    lsr.w    #1,d0                 ; new B

    ; darken to 75%: new = new - new>>2
    move.w   d1,d3
    lsr.w    #2,d3
    sub.w    d3,d1
    move.w   d2,d3
    lsr.w    #2,d3
    sub.w    d3,d2
    move.w   d0,d3
    lsr.w    #2,d3
    sub.w    d3,d0

    ; pack $0RGB: (R<<8) | (G<<4) | B
    lsl.w    #4,d2
    or.w     d2,d0                 ; d0 = (G<<4)|B
    lsl.w    #8,d1
    or.w     d1,d0                 ; d0 = (R<<8)|(G<<4)|B
    move.w   d0,(a1)+
    dbra     d7,.desat

    ;--- Apply desaturated palette to cpPal immediately ----------------------
    lea      VHS_DesPal,a0
    lea      cpPal+2,a1
    moveq    #32-1,d7
.apply0:
    move.w   (a0)+,(a1)
    addq.l   #4,a1
    dbra     d7,.apply0

.activate:
    move.b   #1,VHS_StateActive
    clr.w    VHS_FrameCount
    clr.b    VHS_RollActive
    move.w   #VHS_ROLL_INTERVAL,VHS_RollTimer
    bsr      VHS_ClearDistort

    movem.l  (sp)+,d0-d3/d7/a0-a1
    rts

;------------------------------------------------------------------------------
; VHS_StopEffect
; Restore the original palette from VHS_SavedPal to cpPal and deactivate.
; Preserves all registers.
;------------------------------------------------------------------------------

VHS_StopEffect:
    movem.l  d7/a0-a1,-(sp)

    lea      VHS_SavedPal,a0
    lea      cpPal+2,a1
    moveq    #32-1,d7
.restore:
    move.w   (a0)+,(a1)
    addq.l   #4,a1
    dbra     d7,.restore

    tst.b    VHS_RollActive         ; if roll was applied, restore plane pointers
    beq.b    .no_rp
    bsr      VHS_RestorePlanes
    clr.b    VHS_RollActive
.no_rp:
    bsr      VHS_ClearDistort       ; neutralise all BPLCON1 distortion slots

    clr.b    VHS_StateActive

    movem.l  (sp)+,d7/a0-a1
    rts

;------------------------------------------------------------------------------
; VHS_DoFrame
; Call once per VBlank while VHS_StateActive is non-zero.
; Writes VHS_DesPal + LFSR-driven per-channel noise to all 32 cpPal entries.
;
; OUT:  d0 = 1  effect still running
;       d0 = 0  effect just finished (palette already restored to normal)
; All other registers preserved.
;------------------------------------------------------------------------------

VHS_DoFrame:
    movem.l  d1-d2/d7/a0-a1,-(sp)

    ; Increment and check frame counter
    addq.w   #1,VHS_FrameCount
    cmp.w    #VHS_EFFECT_DURATION,VHS_FrameCount
    blt      .run

    ; Effect expired: restore palette and signal done
    movem.l  (sp)+,d1-d2/d7/a0-a1
    bsr      VHS_StopEffect
    moveq    #0,d0
    rts

.run:
    ; Write VHS_DesPal + LFSR channel-noise to all 32 cpPal value words.
    ; LFSR is advanced once per entry; bits 0/4/8 of the low word flip
    ; the LSB of the B/G/R channels (OCS $0RGB format) for ±1 colour noise.
    move.l   VHS_LFSR,d2
    lea      VHS_DesPal,a0
    lea      cpPal+2,a1            ; a1 -> first colour value word in copper list
    moveq    #32-1,d7

.noise:
    lsr.l    #1,d2                 ; Galois LFSR step
    bcc      .no_xor
    eor.l    #VHS_LFSR_POLY,d2
.no_xor:
    move.w   (a0)+,d1              ; load desaturated colour
    move.w   d2,d0                 ; scratch: low word of LFSR
    and.w    #VHS_NOISE_BITS,d0    ; isolate bits 0, 4, 8
    eor.w    d0,d1                 ; flip B/G/R LSBs at random
    move.w   d1,(a1)               ; write noisy colour to copper list
    addq.l   #4,a1                 ; advance to next colour value word
    dbra     d7,.noise

    move.l   d2,VHS_LFSR           ; persist updated LFSR state

    bsr      VHS_DoDistort          ; per-frame BPLCON1 scanline jitter
    bsr      VHS_DoRoll             ; per-interval one-frame bitplane roll blip

    movem.l  (sp)+,d1-d2/d7/a0-a1
    moveq    #1,d0
    rts

;------------------------------------------------------------------------------
; VHS_ClearDistort
; Resets all three cpVHSDistort copper slots to their base scanlines with
; BPLCON1=$0000 (no horizontal shift).  Valid WAITs are kept so that no slot
; ever stalls at off-screen line $ff and thereby blocks the subsequent slots.
; Preserves all registers.
;------------------------------------------------------------------------------

VHS_ClearDistort:
    move.l   a0,-(sp)
    lea      cpVHSDistort,a0
    move.w   #(VHS_SLOT0_BASE<<8)|$07,(a0)   ; slot 0: WAIT at region base
    clr.w    6(a0)                             ; slot 0: BPLCON1 = 0
    move.w   #(VHS_SLOT1_BASE<<8)|$07,8(a0)  ; slot 1: WAIT at region base
    clr.w    14(a0)                            ; slot 1: BPLCON1 = 0
    move.w   #(VHS_SLOT2_BASE<<8)|$07,16(a0) ; slot 2: WAIT at region base
    clr.w    22(a0)                            ; slot 2: BPLCON1 = 0
    move.l   (sp)+,a0
    rts

;------------------------------------------------------------------------------
; VHS_DoDistort
; Each frame: picks a pseudo-random scanline within each of the three screen
; regions and a colour-clock shift magnitude, then writes a copper WAIT word
; and BPLCON1 data word into the corresponding cpVHSDistort slot.
;
; BPLCON1 format: bits 7-4 = even-plane delay, bits 3-0 = odd-plane delay.
; Both nibbles are set equal so all bitplanes shift by the same amount.
; With VHS_HSHIFT_MASK=$05 the possible BPLCON1 values are:
;   $00 = 0 colour clocks =  0 lo-res pixels  (slot inactive)
;   $11 = 1 colour clock  =  2 lo-res pixels
;   $44 = 4 colour clocks =  8 lo-res pixels
;   $55 = 5 colour clocks = 10 lo-res pixels
;
; When the LFSR yields shift=0 a WAIT is still written with BPLCON1=$0000 so
; no slot blocks the subsequent ones by stalling at an off-screen line.
;
; Advances VHS_LFSR by 6 steps (2 per slot).  Preserves all registers.
;------------------------------------------------------------------------------

VHS_DoDistort:
    movem.l  d0-d3/a0,-(sp)
    move.l   VHS_LFSR,d2
    lea      cpVHSDistort,a0

    ;--- Slot 0: top region (base line VHS_SLOT0_BASE) ---
    lsr.l    #1,d2
    bcc.b    .nd0a
    eor.l    #VHS_LFSR_POLY,d2
.nd0a:
    moveq    #0,d0
    move.b   d2,d0
    and.b    #VHS_SLOT_RAND,d0
    add.b    #VHS_SLOT0_BASE,d0     ; d0.b = scanline in region 0
    lsl.w    #8,d0
    or.w     #$07,d0                ; d0 = copper WAIT word 1
    move.w   d0,(a0)               ; patch slot 0 WAIT (always a valid line)

    lsr.l    #1,d2
    bcc.b    .nd0b
    eor.l    #VHS_LFSR_POLY,d2
.nd0b:
    moveq    #0,d3
    move.b   d2,d3
    and.b    #VHS_HSHIFT_MASK,d3   ; d3 = shift magnitude 0-3
    beq.b    .w0                    ; 0 → write $0000 directly
    move.w   d3,d1
    lsl.w    #4,d1
    or.w     d1,d3                  ; d3 = BPLCON1 ($11 / $22 / $33)
.w0:
    move.w   d3,6(a0)              ; patch slot 0 BPLCON1 data word
    addq.l   #8,a0

    ;--- Slot 1: middle region (base line VHS_SLOT1_BASE) ---
    lsr.l    #1,d2
    bcc.b    .nd1a
    eor.l    #VHS_LFSR_POLY,d2
.nd1a:
    moveq    #0,d0
    move.b   d2,d0
    and.b    #VHS_SLOT_RAND,d0
    add.b    #VHS_SLOT1_BASE,d0
    lsl.w    #8,d0
    or.w     #$07,d0
    move.w   d0,(a0)

    lsr.l    #1,d2
    bcc.b    .nd1b
    eor.l    #VHS_LFSR_POLY,d2
.nd1b:
    moveq    #0,d3
    move.b   d2,d3
    and.b    #VHS_HSHIFT_MASK,d3
    beq.b    .w1
    move.w   d3,d1
    lsl.w    #4,d1
    or.w     d1,d3
.w1:
    move.w   d3,6(a0)
    addq.l   #8,a0

    ;--- Slot 2: bottom region (base line VHS_SLOT2_BASE) ---
    lsr.l    #1,d2
    bcc.b    .nd2a
    eor.l    #VHS_LFSR_POLY,d2
.nd2a:
    moveq    #0,d0
    move.b   d2,d0
    and.b    #VHS_SLOT_RAND,d0
    add.b    #VHS_SLOT2_BASE,d0
    lsl.w    #8,d0
    or.w     #$07,d0
    move.w   d0,(a0)

    lsr.l    #1,d2
    bcc.b    .nd2b
    eor.l    #VHS_LFSR_POLY,d2
.nd2b:
    moveq    #0,d3
    move.b   d2,d3
    and.b    #VHS_HSHIFT_MASK,d3
    beq.b    .w2
    move.w   d3,d1
    lsl.w    #4,d1
    or.w     d1,d3
.w2:
    move.w   d3,6(a0)

    move.l   d2,VHS_LFSR
    movem.l  (sp)+,d0-d3/a0
    rts

;------------------------------------------------------------------------------
; VHS_DoRoll
; Manages the one-frame vertical roll blip.  Every VHS_ROLL_INTERVAL frames
; all five BPLxPTH/L pairs in cpPlanes are offset by +VHS_ROLL_BYTES, causing
; the display to jump up by VHS_ROLL_LINES rows (the bottom rows show data
; past the screen buffer for an authentic corrupted-field look).  The following
; frame the pointers are restored to the normal DisplayScreen base.
; Preserves all registers.
;------------------------------------------------------------------------------

VHS_DoRoll:
    movem.l  d0/d7/a0,-(sp)

    tst.b    VHS_RollActive
    beq.b    .rcheck

    ; Roll was active last frame: restore plane pointers now
    clr.b    VHS_RollActive
    bsr      VHS_RestorePlanes
    bra.b    .rd

.rcheck:
    subq.w   #1,VHS_RollTimer
    bne.b    .rd

    ; Timer expired: apply a one-frame roll offset to all five bitplane pointers
    move.w   #VHS_ROLL_INTERVAL,VHS_RollTimer
    move.b   #1,VHS_RollActive
    move.l   #DisplayScreen,d0
    add.l    #VHS_ROLL_BYTES,d0    ; base + roll delta
    lea      cpPlanes,a0
    moveq    #SCREEN_DEPTH-1,d7
.rloop:
    PLANE_TO_COPPER  d0,a0        ; write rolled high+low address words
    add.l    #SCREEN_WIDTH_BYTE,d0
    addq.l   #8,a0
    dbra     d7,.rloop

.rd:
    movem.l  (sp)+,d0/d7/a0
    rts

;------------------------------------------------------------------------------
; VHS_RestorePlanes
; Writes the canonical DisplayScreen-based addresses back into cpPlanes,
; undoing any roll offset.  Called by VHS_DoRoll and VHS_StopEffect.
; Preserves all registers.
;------------------------------------------------------------------------------

VHS_RestorePlanes:
    movem.l  d0/d7/a0,-(sp)
    move.l   #DisplayScreen,d0
    lea      cpPlanes,a0
    moveq    #SCREEN_DEPTH-1,d7
.rp:
    PLANE_TO_COPPER  d0,a0
    add.l    #SCREEN_WIDTH_BYTE,d0
    addq.l   #8,a0
    dbra     d7,.rp
    movem.l  (sp)+,d0/d7/a0
    rts
