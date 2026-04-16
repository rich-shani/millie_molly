
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; spritetools.asm  -  Hardware Sprite Display
;==============================================================================
;
; The player character is displayed using four Amiga hardware sprites
; arranged as two "attached" pairs (SPR0+SPR1 and SPR2+SPR3).
;
; Why four sprites for one character?
;   - Each hardware sprite is 16 pixels wide.
;   - The player is 24 pixels wide.
;   - Two 16-pixel sprites placed 16 pixels apart give a 32-pixel combined width,
;     of which the inner 24 pixels are the visible character.
;   - Attaching sprites in pairs (even+odd) gives each pair 4 colours instead
;     of the usual 3 (+transparent), doubling the colour depth.
;
; Sprite layout on screen:
;   SPR0 (16px wide) + SPR2 (16px wide) = left/right halves at Y=player_y
;   SPR1 (attached to SPR0) + SPR3 (attached to SPR2) = extra colour bits
;
; The sprite data structures are in RealSprites (realsprites.bin, Chip RAM).
; Each sprite frame occupies SPRITE_SIZE = 104 bytes:
;   4 bytes  header (SPRxPOS + SPRxCTL words, written by SpriteCoord)
;   96 bytes image data (TILE_HEIGHT=24 rows * 4 bytes per row)
;   4 bytes  terminator (two zero words)
;
; ShowSprite updates SpritePtrs(a5), which are then copied into the copper
; list sprite pointer entries (cpSprites) so Agnus fetches the right data
; each frame.
;
;==============================================================================


;==============================================================================
; ShowSprite  -  Display the player character using hardware sprites
;
; Calculates the pixel position from the player structure, selects the correct
; animation frame from RealSprites, writes the SPRxPOS/SPRxCTL header words
; via SpriteCoord, then patches the copper list sprite pointers.
;
; If the player is inactive (Player_Status = 0), all sprites are cleared
; by ClearSprites instead.
;
; On entry:
;   a4 = pointer to player structure (Millie or Molly)
;   a5 = Variables base pointer
;   a6 = $dff000 (CUSTOM chip base) - needed by ClearSprites
;
; Register usage:
;   d0 = sprite frame index (built from SpriteOffset + AnimFrame)
;   d1 = X pixel position
;   d2 = Y pixel position
;   d5 = SPRITE_SIZE (used as vertical extent for SpriteCoord)
;   a0 = pointer to current sprite structure in RealSprites
;==============================================================================

ShowSprite:
    tst.w     Player_Status(a4)          ; is this player active?
    bne       .go                        ; yes - proceed to display
    bsr       ClearSprites               ; no  - hide all sprites
    rts

.go
    ; Calculate pixel position from tile coordinates + sub-tile decimals
    moveq     #0,d1
    moveq     #0,d2
    move.w    Player_X(a4),d1            ; tile column
    move.w    Player_Y(a4),d2            ; tile row
    mulu      #24,d1                     ; pixel X = tile_col * 24
    mulu      #24,d2                     ; pixel Y = tile_row * 24

    add.w     Player_XDec(a4),d1         ; add sub-tile X offset (animation interpolation)
    add.w     Player_YDec(a4),d2         ; add sub-tile Y offset

    ; Select animation frame from sprite sheet
    ; d0 = SpriteOffset  (base for this character: Molly=0, Millie=48)
    ;     + AnimFrame offset for the current action
    add.w     Player_SpriteOffset(a4),d0

    ; Convert frame index to byte offset into RealSprites:
    ;   offset = frame_index * SPRITE_SIZE * 4
    ;   (* 4 because each "frame" in SPRITE_SIZE units is actually 4 sprites -
    ;    two pairs for the character width split)
    mulu      #SPRITE_SIZE*4,d0          ; d0 = byte offset to first sprite of this frame
    lea       RealSprites,a0             ; base of sprite data in Chip RAM
    add.l     d0,a0                      ; a0 -> SPR0 data for this frame

    ; --- SPR0 (left half, top colour bits) ---
    ; Position d5 = { $0080 | attach_bit, TILE_HEIGHT }
    ; The high word $0080 means: not attached (even sprite, no attach bit).
    move.w    #$80,d5
    swap      d5
    move.w    #TILE_HEIGHT,d5            ; d5.hi = $0080 (no attach), d5.lo = height

    move.l    a0,SpritePtrs(a5)          ; store SPR0 pointer for copper list update
    bsr       SpriteCoord                ; write SPRxPOS/SPRxCTL to sprite data header

    ; --- SPR1 (left half, bottom colour bits - attached to SPR0) ---
    add.w     #16,d1                     ; shift X right 16 pixels for right-half pair
    add.w     #SPRITE_SIZE,a0            ; advance to next sprite structure (SPR2 data)
    move.l    a0,SpritePtrs+8(a5)        ; SPR2 pointer (right half, top bits)

    move.w    #$80,d5
    swap      d5
    move.w    #TILE_HEIGHT,d5
    bsr       SpriteCoord                ; write SPR2 header

    ; --- SPR2 (right half, top colour bits) ---
    sub.w     #16,d1                     ; restore X to left-half position
    add.w     #SPRITE_SIZE,a0            ; advance to SPR1 data

    move.w    #$80,d5
    swap      d5
    move.w    #TILE_HEIGHT,d5

    move.l    a0,SpritePtrs+4(a5)        ; SPR1 pointer (left half, bottom/attach bits)
    bsr       SpriteCoord

    ; --- SPR3 (right half, bottom colour bits - attached to SPR2) ---
    add.w     #SPRITE_SIZE,a0            ; advance to SPR3 data
    add.w     #16,d1                     ; right-half X position again

    move.l    a0,SpritePtrs+12(a5)       ; SPR3 pointer

    move.w    #$80,d5
    swap      d5
    move.w    #TILE_HEIGHT,d5
    bsr       SpriteCoord                ; write SPR3 header

    ; --- Patch the copper list sprite pointer entries ---
    ; Copy the four sprite pointers from SpritePtrs(a5) into the cpSprites
    ; section of the copper list so Agnus knows where to fetch sprite data.
    ; Each copper entry is 4 bytes: { reg_word, data_word }.
    ; Pointer stored as:  high 16 bits at +2, low 16 bits at +6 of each entry pair.
    lea       cpSprites,a0              ; a0 -> first sprite copper entry (SPR0PTH)
    move.l    #NullSprite,d0             ; default pointer (not used here but d0 recycled)
    lea       SpritePtrs(a5),a1          ; a1 -> our four saved sprite pointers
    moveq     #4-1,d7                    ; loop: 4 sprites to patch

.loop
    move.l    (a1)+,d0                   ; d0 = sprite data pointer
    move.w    d0,6(a0)                   ; write low  16 bits to copper  (BPLxPTL offset)
    swap      d0
    move.w    d0,2(a0)                   ; write high 16 bits to copper  (BPLxPTH offset)
    swap      d0
    add.l     #8,a0                      ; advance to next copper sprite entry (8 bytes each)
    dbra      d7,.loop

    rts


;==============================================================================
; SpriteCoord  -  Write SPRxPOS and SPRxCTL words into a sprite structure header
;
; The Amiga hardware sprite position registers (SPRxPOS and SPRxCTL) are not
; written directly by the CPU - instead they are embedded in the sprite data
; structure as the first two words.  The Copper reads the sprite pointer
; (SPRxPTH/L) and Agnus copies these header words into the actual registers
; as it processes the sprite data each frame.
;
; Register format:
;   SPRxPOS (first word of sprite structure):
;     bits 15:8 = VSTART[7:0]  - vertical start (raster line, low 8 bits)
;     bits  7:1 = HSTART[8:1]  - horizontal start (colour-clock, bits 8:1)
;     bit   0   = VSTART[8]    - vertical start bit 8 (for > 255 lines)
;
;   SPRxCTL (second word of sprite structure):
;     bits 15:8 = VSTOP[7:0]   - vertical stop (raster line, low 8 bits)
;     bit   7   = attach bit   - 1 = attached to previous (even) sprite
;     bits  6:2 = reserved
;     bit   1   = VSTOP[8]     - vertical stop bit 8
;     bit   0   = VSTART[8]    - vertical start bit 8 (duplicate for SPRxCTL)
;
; On entry:
;   d1 = X pixel coordinate  (0-based from left edge of display)
;   d2 = Y pixel coordinate  (0-based from top  of display)
;   d5 = { attach_byte (high word), height_in_rows (low word) }
;        attach_byte: $80 = no attach, $c0 = attached (for odd sprites)
;        height_in_rows: TILE_HEIGHT (24) for this game
;   a0 = pointer to the 4-byte sprite structure header to fill
;
; Destroys: d3, d4  (d1/d2 preserved via PUSHM/POPM)
;
; The packing logic:
;   1. H_start = d1 + WINDOW_X_START - 1
;      The sprite X is relative to the display window start.
;      Bits 8:1 of H are packed into bits 7:1 of SPRxPOS.
;      Bit 0 of H (the LSB) goes to bit 0 of SPRxCTL.
;      LSR.L #1 / ROL.W #1 achieves this rotation.
;
;   2. V_start = d2 + WINDOW_Y_START
;      Packed into bits 15:8 of SPRxPOS.
;      LSL.L #8 / SWAP / LSL.W #2 places V in the correct bit position.
;
;   3. V_stop = V_start + height
;      Packed into bits 15:8 of SPRxCTL.
;      ROL.W #8 / LSL.B #1 places it correctly.
;
;   4. Attach bit from d5 high byte is OR-ed into the result.
;
; The final combined longword d4 is stored as the sprite header (SPRxPOS:SPRxCTL).
;==============================================================================

SpriteCoord:
    PUSHM     d1/d2                       ; preserve X and Y across this calculation

    ; Adjust X: add display window offset
    add.w     #WINDOW_X_START-1,d1        ; d1 = absolute horizontal position

    ; Adjust Y: add display window top
    moveq     #0,d4
    move.w    #WINDOW_Y_START,d4
    add.w     d4,d2                        ; d2 = absolute vertical position

    ; --- Build SPRxPOS word ---
    ; Horizontal: H[8:1] -> SPRxPOS[7:1], H[0] -> SPRxCTL[0]
    move.l    d1,d4
    swap      d4                           ; d4.lo = d1 now in high word (prep for shift)
    lsr.l     #1,d4                        ; shift right 1: H[8:1] now in d4.hi[7:1], H[0] in carry
    rol.w     #1,d4                        ; rotate low word: carry -> bit 0, H[8:1] -> bits[8:2]
                                           ; NOTE: d4.lo now has the H_START portion of SPRxPOS

    ; Vertical start: V[7:0] -> SPRxPOS[15:8]
    move.l    d2,d3
    lsl.l     #8,d3                        ; shift V left 8
    swap      d3                           ; bring to low word
    lsl.w     #2,d3                        ; shift left 2 more = 10 total -> bits[9:2] (PAL line range)
    or.l      d3,d4                        ; OR into result (V bits into upper area of d4.lo)

    ; --- Build SPRxCTL word ---
    ; Vertical stop: VSTOP = VSTART + height
    move.l    d2,d3
    add.w     d5,d3                        ; d3 = VSTOP = VSTART + TILE_HEIGHT
    rol.w     #8,d3                        ; VSTOP[7:0] -> bits[15:8] of d3.lo
    lsl.b     #1,d3                        ; shift left 1: VSTOP[7:0] -> SPRxCTL[15:8] (low bits intact)
    or.l      d3,d4                        ; OR VSTOP into result

    ; Attach bit
    swap      d5                           ; bring attach byte to low word
    or.b      d5,d4                        ; OR attach bit into SPRxCTL bit 7

    move.l    d4,(a0)                      ; write SPRxPOS (high word) : SPRxCTL (low word)

    POPM      d1/d2                        ; restore X and Y
    rts
