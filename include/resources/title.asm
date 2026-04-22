
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; title.asm  -  Title Screen Setup and Animation
;==============================================================================
;
; Handles game states 0 (TitleSetup) and 1 (TitleRun).
;
; The title screen uses a full-screen DisplayScreen buffer with the same 5-plane
; format as the game screen, but wider (TITLE_SCREEN_WIDTH = 336+32 pixels) to
; provide room for the horizontally-scrolling star animations.
;
; The title logo (title_i.raw) is a 3-plane, 208x88 pixel bitmap.  TitleSetup
; copies it into the centre of the first three bitplanes of DisplayScreen.
;
; Two parallax star layers are blitted each frame by TitleStarDraw:
;   Fast layer (plane 3): four stars at full speed (X+1/frame, Y+1 every 2 frames).
;   Slow layer (plane 4): four stars at half speed (X+1 every 2 frames, Y+1 every 4).
; BlitStar32 handles plane 3; BlitStar32Slow handles plane 4.
;
; TitleCycleColours writes 8 colour values from TitleCycleTable to COLOR00-COLOR07
; in the copper list every VBlank, using index (TickCounter & 7) for an 8-frame cycle.
;
; Coordinate system:
;   TITLE_SCREEN_WIDTH  = 368 pixels  (336 game width + 32 for star wrap)
;   TITLE_SCREEN_HEIGHT = SCREEN_HEIGHT + 32  (extra 32 rows for star wrap)
;
;==============================================================================

;------------------------------------------------------------------------------
; Title screen geometry constants
;------------------------------------------------------------------------------
TITLE_WIDTH             = 208           ; logo pixel width
TITLE_WIDTH_BYTE        = TITLE_WIDTH/8 ; logo bytes per row per plane (26)
TITLE_DEPTH             = 3             ; logo bitplane count (8 colours)
TITLE_HEIGHT            = 88            ; logo pixel height

TITLE_SCREEN_WIDTH      = 336+32        ; title screen pixel width (wider for star wrap)
TITLE_SCREEN_WIDTH_BYTE = TITLE_SCREEN_WIDTH/8  ; bytes per row per plane (46)
TITLE_SCREEN_DEPTH      = 5             ; title screen bitplane count (same as game)
TITLE_SCREEN_MOD        = TITLE_SCREEN_WIDTH_BYTE*(SCREEN_DEPTH-1)+4   ; BPL modulo
TITLE_SCREEN_STRIDE     = TITLE_SCREEN_DEPTH*TITLE_SCREEN_WIDTH_BYTE   ; bytes between rows
TITLE_SCREEN_HEIGHT     = SCREEN_HEIGHT+32  ; title screen total height (extra for stars)

; Horizontal byte offset to centre the 208-pixel logo in the 336-pixel screen:
;   (336/2 - 208/2) / 8 = (168 - 104) / 8 = 64/8 = 8 bytes
TITLE_LOGO_OFFSET       = ((336/2)-(TITLE_WIDTH/2))/8


;==============================================================================
; TitleSetup  -  Initialise the title screen (game state 0)
;
; One-shot initialisation called once when GameStatus transitions to 0.
; After setup, immediately advances GameStatus to 1 (TitleRun).
;
; Actions performed:
;   1. Call TitleCopperSetup to configure the title copper list with correct
;      bitplane pointers and palette.
;   2. Point the Copper at the title copper list (cpTitle) and restart it.
;   3. Set ScreenMemEnd to -1 (signals that the screen memory is valid).
;   4. Enable DMA (BASE_DMA).
;   5. Advance GameStatus to TitleRun (1).
;   6. Initialise the fast star positions in TitleStars (plane 3 layer):
;      - Star 0: X=0,        Y=0
;      - Star 1: X=3*32/2,   Y=3*32
;      - Star 2: X=3*32,     Y=6*32
;      - Star 3: X=3*32*3/2, Y=9*32
;      (each star spaced by 3*32/2 horizontally and 3*32 vertically)
;      Initialise the slow star positions in TitleSlowStars (plane 4 layer)
;      with a 24-pixel / 192-pixel offset for visual variety.
;   7. Copy the title logo from TitleRaw (in Chip RAM data section) into the
;      first three planes of DisplayScreen at the centred position.
;      The copy handles the fact that the logo planes are tightly packed while
;      the screen buffer has wider rows (TITLE_SCREEN_WIDTH_BYTE vs TITLE_WIDTH_BYTE).
;
;==============================================================================

TitleSetup:
    bsr         TitleCopperSetup       ; set up title copper list: planes, palette, sprites

    ; Switch Copper to the title list
    move.l      #cpTitle,COP1LC(a6)    ; load title copper list address into Copper 1
    move.w      #0,COPJMP1(a6)         ; strobe COPJMP1: Copper re-reads COP1LC and starts

    move.l      #-1,ScreenMemEnd       ; mark screen memory as initialised
    move.w      #BASE_DMA,DMACON(a6)   ; enable Copper + Blitter + Bitplane + Sprite DMA

    addq.w      #GAME_TITLE,GameStatus(a5)      ; advance to state 1 (TitleRun)

    ; Initialise fast star positions in TitleStars[] (plane 3 layer).
    ; Each star entry is two words: { X word, Y word }.
    ; Stars are spaced so they do not overlap initially.
    lea         TitleStars,a0          ; a0 -> TitleStars word-pair array
    moveq       #TITLE_STAR_COUNT-1,d7
    moveq       #0,d0                  ; starting X = 0
    moveq       #0,d1                  ; starting Y = 0

.starloop
    move.w      d0,(a0)+               ; store star X
    move.w      d1,(a0)+               ; store star Y
    add.w       #(3*32)/2,d0           ; X: +48 per star
    add.w       #3*32,d1               ; Y: +96 per star
    dbra        d7,.starloop

    ; Initialise slow star positions in TitleSlowStars[] (plane 4 layer).
    ; Offset by (24,192) from the fast layer for visual variety.
    lea         TitleSlowStars,a0
    moveq       #TITLE_STAR_COUNT-1,d7
    move.w      #24,d0                 ; start X offset from fast layer
    move.w      #192,d1                ; start Y offset

.slowstarloop
    move.w      d0,(a0)+
    move.w      d1,(a0)+
    add.w       #(3*32)/2,d0
    add.w       #3*32,d1
    dbra        d7,.slowstarloop

    ; Copy the title logo (TitleRaw) into DisplayScreen.
    ; TitleRaw is stored as 3 planes, each row TITLE_WIDTH_BYTE bytes wide.
    ; DisplayScreen has rows TITLE_SCREEN_WIDTH_BYTE bytes wide per plane.
    ; We must copy row by row, inserting padding bytes for the wider buffer.
    ;
    ; Outer loop: TITLE_HEIGHT rows
    ; Inner loop per row: TITLE_DEPTH planes, each TITLE_WIDTH_BYTE bytes
    ; After each plane's row: skip (TITLE_SCREEN_WIDTH_BYTE - TITLE_WIDTH_BYTE) bytes
    ; After all planes of a row: advance destination stride by TITLE_SCREEN_STRIDE

    lea         TitleRaw,a0            ; a0 -> source logo data (plane 0 row 0)
    lea         DisplayScreen+TITLE_LOGO_OFFSET,a1   ; a1 -> destination (centred)

    move.l      a1,a2                  ; a2 = base of row 0 (outer row pointer)

    move.w      #TITLE_HEIGHT-1,d7     ; 88 rows

.lineloop
    move.l      a2,a1                  ; reset inner pointer to start of this row

    moveq       #TITLE_DEPTH-1,d6      ; 3 planes per row

.depthloop
    move.w      #(TITLE_WIDTH_BYTE)-1,d5   ; TITLE_WIDTH_BYTE bytes per plane row

.byteloop
    move.b      (a0)+,(a1)+            ; copy one byte of logo data
    dbra        d5,.byteloop           ; repeat for this plane's row

    ; Skip padding to reach the start of the same row in the next plane
    lea         TITLE_SCREEN_WIDTH_BYTE-TITLE_WIDTH_BYTE(a1),a1

    dbra        d6,.depthloop          ; next plane

    ; Advance row pointer by one TITLE_SCREEN_STRIDE (all 5 planes)
    lea         TITLE_SCREEN_STRIDE(a2),a2

    dbra        d7,.lineloop           ; next row

    rts


;==============================================================================
; BlitStar32  -  Blit a 32x32 star graphic onto bitplane 4 of DisplayScreen
;
; The star graphic (Star32, star32.raw) is a single-plane 32x32 pixel image.
; It is blitted with OR (minterm $9f0) onto plane 4 of the title screen buffer.
; Plane 4 is the topmost bitplane and controls the star colour (colour index 16+).
;
; The blit can be either aligned (X divisible by 16) or shifted (uses the
; blitter's barrel shifter for non-aligned X positions).
;
; Two blit variants:
;   .blita - no shift (X mod 16 = 0): simple 2-word-wide blit, no mask adjustment
;   main   - shifted: 3-word-wide blit with first-word mask $ffff0000 to avoid
;             writing one word before the start of the destination
;
; On entry:
;   d0 = X pixel position of the star
;   d1 = Y pixel position of the star
;   a5 = Variables base
;   a6 = $dff000
;
; Preserves all registers (PUSHALL / POPALL).
;
; Screen layout for blit:
;   Destination = DisplayScreen + (plane 4 offset) + y*TITLE_SCREEN_STRIDE + x/8
;   Plane 4 offset = TITLE_SCREEN_WIDTH_BYTE * 3  (bytes for planes 0-3 per row + 1)
;                  (each plane adds TITLE_SCREEN_WIDTH_BYTE bytes before the next)
;
; Blit parameters:
;   STAR_BLIT_SIZE     = (32 rows << 6) | 2 words = size register for 32x32 one-plane
;   STAR_BLIT_DEST_MOD = TITLE_SCREEN_STRIDE - 4  (skip 4 planes worth + adjust for 2 words)
;==============================================================================

STAR_BLIT_SIZE      = (32<<6)|2        ; BLTSIZE: 32 rows, 2 words wide
STAR_BLIT_DEST_MOD  = TITLE_SCREEN_STRIDE-4    ; dest modulo: skip back to same plane next row

; Byte offset from row start to the plane used by each star layer (guard -4 included):
;   Plane 3 (BPL4, bit 3 of colour index → COLOR08): fast star layer
;   Plane 4 (BPL5, bit 4 of colour index → COLOR16): slow star layer
STAR_PLANE3_OFFSET  = TITLE_SCREEN_WIDTH_BYTE*3-4
STAR_PLANE4_OFFSET  = TITLE_SCREEN_WIDTH_BYTE*4-4

; Copper palette slot offsets for each star layer's colour register (data word at +2)
STAR_FAST_PAL_OFF   = 2+(8*4)         ; COLOR08 data word in cpTitlePal
STAR_SLOW_PAL_OFF   = 2+(16*4)        ; COLOR16 data word in cpTitlePal

; Colour values (RGB444) for each star layer
STAR_FAST_COLOR     = $fe8            ; fast layer: warm near-white (bright foreground stars)
STAR_SLOW_COLOR     = $46c            ; slow layer: dim cool blue   (distant background stars)

; Sine-wave wobble parameters for TitleStarDraw
; Phase spread: 4 stars placed SINE_ANGLES/4 = 512 entries apart → quarter-period spacing
;   (computed via  mulu #SINE_ANGLES/4,d3  — mulu used because 9-bit shift > 68000 max of 8)
; Fast layer: 8 table entries per frame → full cycle every 256 frames (~5s at 50Hz)
STAR_WAVE_FAST_SHIFT  = 3            ; TickCounter lsl for fast-layer wave speed (max 8, valid)
; Fast amplitude: ±8 pixels  — needs ÷4096: two-step  asr.w #8 ; asr.w #4
; Slow layer: 4 table entries per frame → full cycle every 512 frames (~10s at 50Hz)
STAR_WAVE_SLOW_SHIFT  = 2            ; TickCounter lsl for slow-layer wave speed
; Slow amplitude: ±4 pixels  — needs ÷8192: two-step  asr.w #8 ; asr.w #5

BlitStar32:
    PUSHALL

    ; Bounds check: skip if Y >= TITLE_SCREEN_HEIGHT (star is off the bottom)
    cmp.w       #TITLE_SCREEN_HEIGHT,d1
    bcc         .exit

    sub.w       #32,d1                 ; HACK: shift Y up 32 (stars wrapped around bottom)

    ; Bounds check: skip if X >= TITLE_SCREEN_WIDTH (star is off the right)
    cmp.w       #TITLE_SCREEN_WIDTH,d0
    bcc         .exit

    ; Calculate destination byte offset into DisplayScreen plane 3 (fast star layer):
    ;   d2 = (x / 8) + STAR_PLANE3_OFFSET
    move.w      d0,d2
    lsr.w       #3,d2                              ; d2 = X / 8 (byte column)
    add.l       #STAR_PLANE3_OFFSET,d2             ; add plane 3 start offset

    ; Add Y row offset:  d3 = Y * TITLE_SCREEN_STRIDE
    move.w      d1,d3
    muls        #TITLE_SCREEN_STRIDE,d3
    add.l       d3,d2                  ; d2 = final byte offset into screen

    add.l       #DisplayScreen,d2       ; d2 = absolute destination address

    ; Calculate shift amount: X mod 16 (4-bit shift for blitter BLTCON0 shift field)
    move.w      d0,d3
    and.w       #$f,d3                 ; d3 = X mod 16 (0 = aligned, 1-15 = shifted)
    beq         .blita                 ; if aligned, use simpler blit

    ; --- Shifted blit (X not on a 16-pixel boundary) ---
    ; Pack shift value into BLTCON0[15:12] (4-bit shift field)
    ror.w       #4,d3                  ; rotate shift to bits 15:12 of d3
    or.w        #$9f0,d3               ; d3 = BLTCON0: shift + use A only, copy minterm ($9f0)

    WAITBLIT
    move.w      d3,BLTCON0(a6)         ; BLTCON0: shift value + minterm (A source -> D dest)
    move.w      #0,BLTCON1(a6)         ; BLTCON1: no fill, no shift in B
    move.l      #Star32,BLTAPT(a6)     ; source: Star32 (single plane, 32x32)
    move.l      d2,BLTDPT(a6)          ; destination: plane 4 of title screen

    ; First-word mask: $ffff0000 prevents the blitter from writing anything in
    ; the 16 bits BEFORE the shift starts (the "guard" word to the left).
    move.l      #$ffff0000,BLTAFWM(a6) ; first word mask=none, last word mask=all

    move.w      #-2,BLTAMOD(a6)        ; source modulo: -2 (no extra skip, 2-word rows)
    move.w      #STAR_BLIT_DEST_MOD-2,BLTDMOD(a6)  ; dest modulo: skip other planes
    move.w      #STAR_BLIT_SIZE+1,BLTSIZE(a6)       ; size: 32 rows x 3 words (extra word for shift)
    WAITBLIT
    bra         .exit

.blita
    ; --- Aligned blit (X on a 16-pixel boundary) ---
    WAITBLIT
    move.w      #$9f0,BLTCON0(a6)      ; BLTCON0: no shift, copy minterm
    move.w      #0,BLTCON1(a6)
    move.l      #Star32,BLTAPT(a6)
    move.l      d2,BLTDPT(a6)
    move.l      #-1,BLTAFWM(a6)        ; all bits valid (no masking needed)
    move.w      #0,BLTAMOD(a6)         ; source modulo: 0 (tightly packed 2-word rows)
    move.w      #STAR_BLIT_DEST_MOD,BLTDMOD(a6)
    move.w      #STAR_BLIT_SIZE,BLTSIZE(a6)
    WAITBLIT

.exit
    POPALL
    rts


;==============================================================================
; BlitStar32Slow  -  Blit a 32x32 star onto plane 4 of DisplayScreen (slow layer)
;
; Identical to BlitStar32 but targets plane 4 (BPL5, bit 4 of colour index).
; Used for the parallax slow star layer whose colour (COLOR16 in background)
; differs from the fast layer (plane 3, COLOR08 in background).
;
; On entry / register use / masks: same as BlitStar32.
;==============================================================================

BlitStar32Slow:
    PUSHALL

    cmp.w       #TITLE_SCREEN_HEIGHT,d1
    bcc         .exits

    sub.w       #32,d1

    cmp.w       #TITLE_SCREEN_WIDTH,d0
    bcc         .exits

    move.w      d0,d2
    lsr.w       #3,d2
    add.l       #STAR_PLANE4_OFFSET,d2

    move.w      d1,d3
    muls        #TITLE_SCREEN_STRIDE,d3
    add.l       d3,d2

    add.l       #DisplayScreen,d2

    move.w      d0,d3
    and.w       #$f,d3
    beq         .blitas

    ror.w       #4,d3
    or.w        #$9f0,d3

    WAITBLIT
    move.w      d3,BLTCON0(a6)
    move.w      #0,BLTCON1(a6)
    move.l      #Star32,BLTAPT(a6)
    move.l      d2,BLTDPT(a6)
    move.l      #$ffff0000,BLTAFWM(a6)
    move.w      #-2,BLTAMOD(a6)
    move.w      #STAR_BLIT_DEST_MOD-2,BLTDMOD(a6)
    move.w      #STAR_BLIT_SIZE+1,BLTSIZE(a6)
    WAITBLIT
    bra         .exits

.blitas
    WAITBLIT
    move.w      #$9f0,BLTCON0(a6)
    move.w      #0,BLTCON1(a6)
    move.l      #Star32,BLTAPT(a6)
    move.l      d2,BLTDPT(a6)
    move.l      #-1,BLTAFWM(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #STAR_BLIT_DEST_MOD,BLTDMOD(a6)
    move.w      #STAR_BLIT_SIZE,BLTSIZE(a6)
    WAITBLIT

.exits
    POPALL
    rts


;==============================================================================
; TitleCopperSetup  -  Configure the title screen copper list
;
; Patches cpTitlePlanes with the addresses of DisplayScreen's five bitplanes
; (using TITLE_SCREEN_WIDTH_BYTE stride between planes), and copies the title
; palette from TitlePal (32 entries) into cpTitlePal.
;
; Also calls ClearSprites to point all 8 copper sprite entries at NullSprite
; (no hardware sprites used on the title screen).
;==============================================================================

TitleCopperSetup:
    bsr         ClearSprites           ; hide all hardware sprites

    ; Patch bitplane pointers in the title copper list.
    ; The five planes of DisplayScreen are interleaved with TITLE_SCREEN_WIDTH_BYTE
    ; bytes between them (wider than the game screen).
    move.l      #DisplayScreen,d0       ; d0 = base address of plane 0
    lea         cpTitlePlanes,a0       ; a0 -> first copper plane entry

    moveq       #SCREEN_DEPTH-1,d7     ; 5 planes

.ploop
    ; Write 32-bit plane address into copper entry pair:
    ; { BPLxPTH, hi_word } at +2(a0) and { BPLxPTL, lo_word } at +6(a0)
    move.w      d0,6(a0)               ; write low  word of address
    swap        d0
    move.w      d0,2(a0)               ; write high word of address
    swap        d0
    addq.l      #8,a0                  ; advance to next copper plane entry (8 bytes)
    add.l       #TITLE_SCREEN_WIDTH_BYTE,d0  ; next plane starts TITLE_SCREEN_WIDTH_BYTE bytes later
    dbra        d7,.ploop

    ; Copy title palette from TitlePal into the copper palette section.
    lea         TitlePal,a0
    lea         cpTitlePal,a1
    moveq       #32-1,d7               ; 32 colour entries

.cloop
    move.w      (a0)+,2(a1)            ; write colour value into copper MOVE data word
    addq.l      #4,a1                  ; advance to next copper COLOR entry
    dbra        d7,.cloop

    ; Fill COLOR08-COLOR15 with the fast star colour so stars on plane 3 remain visible
    ; over any logo pixels (planes 0-2 add bits 0-2, giving indices 8-15).
    lea         cpTitlePal+STAR_FAST_PAL_OFF,a0    ; a0 -> value word of COLOR08
    moveq       #8-1,d7
.fastpalloop
    move.w      #STAR_FAST_COLOR,(a0)
    addq.l      #4,a0
    dbra        d7,.fastpalloop

    ; Fill COLOR16-COLOR31 with the slow star colour (plane 4, indices 16-31).
    lea         cpTitlePal+STAR_SLOW_PAL_OFF,a0    ; a0 -> value word of COLOR16
    moveq       #16-1,d7
.slowpalloop
    move.w      #STAR_SLOW_COLOR,(a0)
    addq.l      #4,a0
    dbra        d7,.slowpalloop

    rts


;==============================================================================
; ClearTitleSprites  -  Point all title copper sprite entries at NullSprite
;
; Identical logic to ClearSprites but operates on cpTitleSprites rather than
; cpSprites.  Written separately to avoid dependency on which copper list
; is active when called.
;==============================================================================

ClearTitleSprites:
    lea         cpTitleSprites,a0
    move.l      #NullSprite,d0
    moveq       #8-1,d7

.loop
    move.w      d0,6(a0)               ; write low  word of NullSprite address
    swap        d0
    move.w      d0,2(a0)               ; write high word of NullSprite address
    swap        d0
    add.l       #8,a0                  ; next copper sprite entry
    dbra        d7,.loop
    rts


;==============================================================================
; TitleRun  -  Title screen per-frame handler (game state 1)
;
; Called every VBlank while the title screen is active.
; Checks for F7 to start the game, otherwise animates the four star objects.
;
; F7 pressed:
;   - Clears the key state to prevent repeat.
;   - Calls GameInit to set up the game copper list, sprite masks, DMA,
;     and draw the first level (START_LEVEL).
;   - Advances GameStatus to 2 (GameRun).
;   - Returns immediately (no star blit needed this frame).
;
; F7 not pressed:
;   - Falls through to TitleStarDraw as before.
;==============================================================================

TitleRun:
    ; Check for F7 key to start the game
    lea         Keys,a0                ; a0 -> keyboard state buffer
    tst.b       KEY_F7(a0)             ; is F7 held?
    beq         .nostart               ; no - continue title animation

    clr.b       KEY_F7(a0)             ; consume the keypress (prevent repeat)
    bsr         GameInit                ; set up game copper, sprites, DMA

    ; setup initial level (START_LEVEL)
    move.w      #START_LEVEL,LevelId(a5)
    ; set GameStatus to LEVEL_INIT to force level initization sequence
    move.w      #LEVEL_INIT,GameStatus(a5)

    rts                                ; return immediately - stars not needed this frame

.nostart
    bsr         TitleStarDraw          ; animate and blit both star layers
    rts


;==============================================================================
; TitleStarDraw  -  Animate and blit both parallax star layers
;
; Fast layer (TitleStars, plane 3):
;   X += 1/frame; Y += 1/2 frames.
;   Sine wobble applied to blit Y only (not stored): ±8 pixels, ~5s cycle.
;
; Slow layer (TitleSlowStars, plane 4):
;   X += 1/2 frames; Y += 1/4 frames.
;   Sine wobble: ±4 pixels, ~10s cycle.
;
; Both layers spread 4 stars a quarter-period apart in the sine wave so
; they form a continuous flowing curve across the screen.
; Wrap: X at 3*32 (96), Y at TITLE_STAR_COUNT*32*3 (384).
; Blit Y is transient (wobbled); stored Y drifts at the base scroll rate.
;==============================================================================

TitleStarDraw:
    ; Erase both star planes before redrawing to prevent trails.
    ; Two sequential D-only blits (minterm $00) zero-fill plane 3 then plane 4.
    ; BLTDMOD skips the other 4 planes per row to stay within the target plane.
    WAITBLIT
    move.w      #$0100,BLTCON0(a6)                                          ; D only, minterm $00
    move.w      #0,BLTCON1(a6)
    move.l      #DisplayScreen+TITLE_SCREEN_WIDTH_BYTE*3,BLTDPT(a6)        ; plane 3 start
    move.w      #TITLE_SCREEN_STRIDE-TITLE_SCREEN_WIDTH_BYTE,BLTDMOD(a6)   ; skip other planes
    move.w      #(TITLE_SCREEN_HEIGHT<<6)|(TITLE_SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)

    WAITBLIT
    move.l      #DisplayScreen+TITLE_SCREEN_WIDTH_BYTE*4,BLTDPT(a6)        ; plane 4 start
    move.w      #(TITLE_SCREEN_HEIGHT<<6)|(TITLE_SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)

    ; --- Fast star layer (plane 3, full speed + sine wobble) ---
    lea         TitleStars,a0
    moveq       #TITLE_STAR_COUNT-1,d7

.fastloop
    move.w      (a0),d0
    move.w      2(a0),d1

    ; Sine-wave Y offset: sample Sinus at (TickCounter*8 + star_index*512)
    ; Result ±8 pixels added to d1 for the blit (stored Y is not modified).
    move.w      TickCounter(a5),d2
    lsl.w       #STAR_WAVE_FAST_SHIFT,d2           ; phase = tick * 8
    move.w      #TITLE_STAR_COUNT-1,d3
    sub.w       d7,d3                              ; d3 = star index (0-3)
    mulu        #SINE_ANGLES/4,d3                  ; d3 = index * 512 (mulu: > 8-bit shift)
    add.w       d3,d2
    and.w       #SINE_ANGLES-1,d2                  ; wrap to table (mask $7FF)
    add.w       d2,d2                              ; byte index
    lea         Sinus,a1
    move.w      (a1,d2.w),d2                       ; ±$7fff
    asr.w       #8,d2                              ; ÷512 in two steps (68000 max shift = 8)
    asr.w       #1,d2                              ; → ±63 pixels
    add.w       d2,d1                              ; modulate blit Y

    bsr         BlitStar32
    add.w       #3*32,d0
    bsr         BlitStar32
    add.w       #3*32,d0
    bsr         BlitStar32
    add.w       #3*32,d0
    bsr         BlitStar32

    move.w      TickCounter(a5),d5
    addq.w      #1,(a0)                ; X += 1 every frame
    and.w       #1,d5
    beq         .fastskipy
    addq.w      #1,2(a0)               ; Y += 1 every other frame
.fastskipy

    cmp.w       #3*32,(a0)
    bcs         .fastnowrapx
    sub.w       #3*32,(a0)
.fastnowrapx

    cmp.w       #TITLE_STAR_COUNT*32*3,2(a0)
    bcs         .fastnowrapy
    sub.w       #TITLE_STAR_COUNT*32*3,2(a0)
.fastnowrapy

    addq.w      #4,a0
    dbra        d7,.fastloop

    ; --- Slow star layer (plane 4, half speed + gentler sine wobble) ---
    lea         TitleSlowStars,a0
    moveq       #TITLE_STAR_COUNT-1,d7

.slowloop
    move.w      (a0),d0
    move.w      2(a0),d1

    ; Sine-wave Y offset: same quarter-period phase spread, slower speed + smaller amplitude
    move.w      TickCounter(a5),d2
    lsl.w       #STAR_WAVE_SLOW_SHIFT,d2           ; phase = tick * 4
    move.w      #TITLE_STAR_COUNT-1,d3
    sub.w       d7,d3
    mulu        #SINE_ANGLES/4,d3                  ; d3 = index * 512
    add.w       d3,d2
    and.w       #SINE_ANGLES-1,d2
    add.w       d2,d2
    lea         Sinus,a1
    move.w      (a1,d2.w),d2                       ; ±$7fff
    asr.w       #8,d2                              ; ÷8192 in two steps
    asr.w       #5,d2                              ; → ±4 pixels
    add.w       d2,d1

    bsr         BlitStar32Slow
    add.w       #3*32,d0
    bsr         BlitStar32Slow
    add.w       #3*32,d0
    bsr         BlitStar32Slow
    add.w       #3*32,d0
    bsr         BlitStar32Slow

    move.w      TickCounter(a5),d5
    and.w       #1,d5                  ; X += 1 every 2 frames
    bne         .slowskipx
    addq.w      #1,(a0)
.slowskipx

    move.w      TickCounter(a5),d5
    and.w       #3,d5                  ; Y += 1 every 4 frames
    bne         .slowskipy
    addq.w      #1,2(a0)
.slowskipy

    cmp.w       #3*32,(a0)
    bcs         .slownowrapx
    sub.w       #3*32,(a0)
.slownowrapx

    cmp.w       #TITLE_STAR_COUNT*32*3,2(a0)
    bcs         .slownowrapy
    sub.w       #TITLE_STAR_COUNT*32*3,2(a0)
.slownowrapy

    addq.w      #4,a0
    dbra        d7,.slowloop

    rts


;==============================================================================
; TitleCycleColours  -  Slowly cycle the title logo palette (COLOR01-COLOR07)
;
; Called from TitleRun every VBlank.  Advances the cycle index every 8 frames
; (lsr.w #3 on TickCounter) so one full 8-step cycle takes ~1.28s at 50Hz —
; a slow, readable glow rather than a fast flash.
;
; COLOR00 (background) is intentionally NOT written; only the 7 logo colours
; (COLOR01-COLOR07) are updated.  The copper entry pointer starts at cpTitlePal+4
; and the table pointer at TitleCycleTable+2 to skip the placeholder word.
;
; Each cpTitlePal entry is 4 bytes: { reg_word (at 0), colour_word (at +2) }.
; Register usage: d0, d7, a0, a1 (all scratch).
;==============================================================================

TitleCycleColours:
    move.w      TickCounter(a5),d0
    lsr.w       #3,d0                  ; advance index every 8 frames (~1.3s per full cycle)
    and.w       #7,d0                  ; 8-frame cycle index
    lsl.w       #4,d0                  ; * 16 bytes (8 words per frame, power-of-2 stride)
    lea         TitleCycleTable+2,a0   ; +2: skip unused COLOR00 placeholder per frame
    add.w       d0,a0                  ; a0 -> COLOR01-COLOR07 values for this frame
    lea         cpTitlePal+4,a1        ; start at COLOR01 copper entry (skip COLOR00 background)
    moveq       #7-1,d7

.cloop
    move.w      (a0)+,2(a1)            ; write colour value to copper MOVE data word
    addq.l      #4,a1                  ; next copper COLOR entry (4 bytes: reg + data)
    dbra        d7,.cloop

    rts


;==============================================================================
; TitleCycleTable  -  8-frame × 8-word palette cycle for the title logo
;
; Indexed by ((TickCounter >> 3) & 7); full cycle ≈ 1.28s at 50Hz.
; Each row is 8 RGB444 words.  Entry 0 of each row is a placeholder ($000)
; and is never written to the copper — TitleCycleColours skips it (+2 offset)
; and always starts at COLOR01, leaving COLOR00 (background) unchanged.
; Colours in entries 1-7 (COLOR01-COLOR07) pulse through a blue wave,
; keeping the logo readable throughout the full cycle.
;==============================================================================

TitleCycleTable:
    ; entry[0] = unused placeholder; entries[1-7] = COLOR01-COLOR07
    dc.w    $000,$22c,$44e,$66f,$88f,$aaf,$ccf,$fff   ; frame 0 - brightest
    dc.w    $000,$22a,$22c,$44e,$66f,$88f,$aaf,$ccf   ; frame 1
    dc.w    $000,$228,$22a,$22c,$44e,$66f,$88f,$aaf   ; frame 2
    dc.w    $000,$226,$228,$22a,$22c,$44e,$66f,$88f   ; frame 3
    dc.w    $000,$224,$226,$228,$22a,$22c,$44e,$66f   ; frame 4 - dimmest
    dc.w    $000,$226,$228,$22a,$22c,$44e,$66f,$88f   ; frame 5
    dc.w    $000,$228,$22a,$22c,$44e,$66f,$88f,$aaf   ; frame 6
    dc.w    $000,$22a,$22c,$44e,$66f,$88f,$aaf,$ccf   ; frame 7
