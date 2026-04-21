
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; title.asm  -  Title Screen Setup and Animation
;==============================================================================
;
; Handles game states 0 (TitleSetup) and 1 (TitleRun).
;
; The title screen uses a full-screen DisplayScreen buffer with the same 5-plane
; format as the game screen, but wider (TITLE_SCREEN_WIDTH = 336+32 pixels) to
; provide room for the horizontally-scrolling star animation on plane 4.
;
; The title logo (title_i.raw) is a 3-plane, 208x88 pixel bitmap.  TitleSetup
; copies it into the centre of the first three bitplanes of DisplayScreen.
;
; Four 32x32 star sprites (Star32, from star32.raw) are blitted onto bitplane 4
; of DisplayScreen each frame by BlitStar32.  They scroll right and down slowly,
; wrapping around when they reach the edge.
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
;   6. Initialise the four star positions in TitleStars:
;      - Star 0: X=0,        Y=0
;      - Star 1: X=3*32/2,   Y=3*32
;      - Star 2: X=3*32,     Y=6*32
;      - Star 3: X=3*32*3/2, Y=9*32
;      (each star spaced by 3*32/2 horizontally and 3*32 vertically)
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

    ; Initialise four star X/Y positions in TitleStars[] array.
    ; Each star entry is two words: { X word, Y word }.
    ; They are spaced apart so they do not overlap initially.
    lea         TitleStars,a0          ; a0 -> TitleStars word-pair array
    moveq       #TITLE_STAR_COUNT-1,d7 ; 4 stars, loop count-1 for DBRA
    moveq       #0,d0                  ; starting X = 0
    moveq       #0,d1                  ; starting Y = 0

.starloop
    move.w      d0,(a0)+               ; store star X
    move.w      d1,(a0)+               ; store star Y
    add.w       #(3*32)/2,d0           ; next star X: shift right by half a star-cell (48)
    add.w       #3*32,d1               ; next star Y: shift down by one star-cell (96)
    dbra        d7,.starloop

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

BlitStar32:
    PUSHALL

    ; Bounds check: skip if Y >= TITLE_SCREEN_HEIGHT (star is off the bottom)
    cmp.w       #TITLE_SCREEN_HEIGHT,d1
    bcc         .exit

    sub.w       #32,d1                 ; HACK: shift Y up 32 (stars wrapped around bottom)

    ; Bounds check: skip if X >= TITLE_SCREEN_WIDTH (star is off the right)
    cmp.w       #TITLE_SCREEN_WIDTH,d0
    bcc         .exit

    ; Calculate destination byte offset into DisplayScreen plane 4:
    ;   d2 = (x / 8) + TITLE_SCREEN_WIDTH_BYTE*3 - 4
    ;        (the -4 accounts for the 2-word blit width: blitter starts 4 bytes earlier)
    move.w      d0,d2
    lsr.w       #3,d2                              ; d2 = X / 8 (byte column)
    add.l       #(TITLE_SCREEN_WIDTH_BYTE*3)-4,d2  ; add plane 4 start offset

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
    ; TitlePal is 32 words for the logo (3-plane) plus extra entries for star colours
    ; on the upper 16 colour registers.
    lea         TitlePal,a0
    lea         cpTitlePal,a1
    moveq       #32-1,d7               ; 32 colour entries

.cloop
    move.w      (a0)+,2(a1)            ; write colour value into copper MOVE data word
    addq.l      #4,a1                  ; advance to next copper COLOR entry
    dbra        d7,.cloop

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
; Checks for F3 to start the game, otherwise animates the four star objects.
;
; F3 pressed:
;   - Clears the key state to prevent repeat.
;   - Calls GameInit to set up the game copper list, sprite masks, DMA,
;     and draw the first level (START_LEVEL).
;   - Advances GameStatus to 2 (GameRun).
;   - Returns immediately (no star blit needed this frame).
;
; F3 not pressed:
;   - Falls through to TitleStarDraw as before.
;==============================================================================

TitleRun:
    ; Check for F3 key to start the game
    lea         Keys,a0                ; a0 -> keyboard state buffer
    tst.b       KEY_F3(a0)             ; is F3 held?
    beq         .nostart               ; no - continue title animation

    clr.b       KEY_F3(a0)             ; consume the keypress (prevent repeat)
    bsr         GameInit                ; set up game copper, sprites, DMA

    ; setup initial level (START_LEVEL)
    move.w      #START_LEVEL,LevelId(a5)
    ; set GameStatus to LEVEL_INIT to force level initization sequence
    move.w      #LEVEL_INIT,GameStatus(a5)

    rts                                ; return immediately - stars not needed this frame

.nostart
    bsr         TitleStarDraw          ; animate and blit the four stars
    rts


;==============================================================================
; TitleStarDraw  -  Animate and blit all four stars
;
; Iterates through the four star records in TitleStars[].
; Each record is { word X, word Y }.
;
; Per star each frame:
;   1. Blit the star at 4 equally-spaced horizontal positions across the screen:
;      X, X+(3*32), X+(6*32), X+(9*32)  - four copies of the 32x32 graphic.
;   2. Move the star right by 1 pixel per frame: X += 1.
;   3. Every other frame (TickCounter AND 1 = 0): move down by 1 pixel: Y += 1.
;   4. Wrap X when it reaches 3*32 (96): X -= 3*32.
;   5. Wrap Y when it reaches TITLE_STAR_COUNT*32*3: Y -= TITLE_STAR_COUNT*32*3.
;
; The four horizontal copies fill the 3*32*4 = 384 pixel-wide star band that
; scrolls across the 368-pixel screen.  The wrap logic ensures seamless repeat.
;
; BlitStar32 handles the actual blit (with shift/mask as needed).
;==============================================================================

TitleStarDraw:
    lea         TitleStars,a0          ; a0 -> first star record
    moveq       #TITLE_STAR_COUNT-1,d7 ; 4 stars

.starloop
    move.w      (a0),d0                ; d0 = star X
    move.w      2(a0),d1               ; d1 = star Y

    ; Blit 4 copies of the star horizontally, each 3*32 pixels apart
    bsr         BlitStar32             ; copy 1 at (X, Y)
    add.w       #3*32,d0               ; shift X right one star-period
    bsr         BlitStar32             ; copy 2
    add.w       #3*32,d0
    bsr         BlitStar32             ; copy 3
    add.w       #3*32,d0
    bsr         BlitStar32             ; copy 4

    ; Update star position for next frame
    move.w      TickCounter(a5),d5
    addq.w      #1,(a0)                ; X += 1 every frame
    and.w       #1,d5                  ; test TickCounter bit 0
    beq         .skipy
    addq.w      #1,2(a0)               ; Y += 1 every other frame (slower vertical scroll)
.skipy

    ; Wrap X
    cmp.w       #3*32,(a0)             ; X >= 96?
    bcs         .nowrapx
    sub.w       #3*32,(a0)             ; X -= 96
.nowrapx

    ; Wrap Y
    cmp.w       #TITLE_STAR_COUNT*32*3,2(a0)   ; Y >= 384?
    bcs         .nowrapy
    sub.w       #TITLE_STAR_COUNT*32*3,2(a0)   ; Y -= 384
.nowrapy

    addq.w      #4,a0                  ; advance to next star record (2 words = 4 bytes)
    dbra        d7,.starloop

    rts


;------------------------------------------------------------------------------
; Leftover per-star X/Y variables (no longer used; star state is now stored
; directly in TitleStars[] in the Variables block).
;------------------------------------------------------------------------------
StarX:
    dc.w        0

StarY:
    dc.w        0
