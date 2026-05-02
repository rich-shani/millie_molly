
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; copperlists.asm  -  Copper List Data
;==============================================================================
;
; The Copper (co-processor) is a programmable list processor built into the
; Agnus chip.  It runs in sync with the video beam, executing a sequence of
; instructions from a list in Chip RAM.  The CPU programs the Copper by writing
; the list address to COP1LC and strobing COPJMP1.
;
; Copper instruction format (two words):
;   MOVE instruction:  { register_address, data_value }
;     - register_address bit 0 = 0 identifies it as a MOVE
;     - Writes data_value to the named custom chip register
;
;   WAIT instruction:  { vp<<8 | hp, ve<<8 | he | $0001 }
;     - bit 0 = 1 identifies it as WAIT (or SKIP)
;     - Copper stalls until the beam reaches or passes (vp, hp)
;
;   COPPER_HALT (dc.l $fffffffe) - special WAIT that is never satisfied,
;     stopping the Copper at the end of the list.
;
; This file defines two copper lists:
;   cpTest  - game screen (5-plane, 32-colour, full screen)
;   cpTitle - title screen (5-plane, 32-colour, wider format for star effect)
;
; Both lists are in the data_chip section (Chip RAM) because the Copper
; can only DMA-fetch from Chip RAM.
;
; Labelled sub-sections allow GameCopperInit / TitleCopperSetup to patch in
; the correct bitplane pointers and palette values at runtime:
;   cpPlanes / cpTitlePlanes    - bitplane pointer MOVE pairs (BPL1PTH/L etc.)
;   cpSprites / cpTitleSprites  - sprite pointer MOVE pairs   (SPR0PTH/L etc.)
;   cpPal / cpTitlePal          - palette MOVE pairs          (COLOR00..COLOR31)
;
;==============================================================================


;==============================================================================
; cpTest  -  Game screen copper list
;
; Sets up the display for the main gameplay screen:
;   - Slow fetch mode ($01fc = FMODE register, value $0000 = OCS compatible)
;   - Display window (DIWSTRT / DIWSTOP) = game screen boundaries
;   - Bitplane DMA fetch window (DDFSTRT / DDFSTOP)
;   - BPLCON0 = $5200  : 5 bitplanes (bits 14:12 = 101), colour enable (bit 9)
;   - BPLCON1 = $0000  : no horizontal scroll
;   - BPLCON2 = $0024  : sprites 0-3 above playfield, sprite priority
;   - BPL1MOD / BPL2MOD = SCREEN_MOD  : interleave modulo for 5-plane layout
;   - 5 pairs of BPLxPTH/L for bitplane addresses (patched at runtime)
;   - 8 pairs of SPRxPTH/L for sprite addresses   (patched at runtime)
;   - 32 COLOR register writes                    (patched at runtime)
;   - Two COPPER_HALT longwords to stop the Copper
;
; BPLCON0 = $5200 breakdown:
;   bits 14:12 = 101 -> 5 bitplanes (BPU field)
;   bit  9     = 1   -> colour enable
;   bits 8:0   = 000 -> lo-res, non-interlaced, no EHB/HAM
;
; BPLCON2 = $0024:
;   bits 5:3 = 100 -> sprites 0-3 win over odd playfield where they overlap
;   bits 2:0 = 100 -> sprites 0-3 win over even playfield
;
;==============================================================================

cpTest:
    dc.w    $01fc,$0000             ; FMODE: OCS-compatible slow fetch mode (must be first)

    dc.w    DIWSTRT,WINDOW_START    ; display window top-left  ($2c81 for PAL standard)
    dc.w    DIWSTOP,WINDOW_STOP     ; display window bottom-right
    dc.w    DDFSTRT,FETCH_START     ; bitplane DMA fetch start  ($30)
    dc.w    DDFSTOP,FETCH_STOP      ; bitplane DMA fetch stop   ($d0)

    dc.w    BPLCON0,$5200           ; 5 bitplanes, colour enable, lo-res
    dc.w    BPLCON1,$0000           ; no horizontal bitplane scroll
    dc.w    BPLCON2,$0024           ; sprite/playfield priority control
    dc.w    BPL1MOD,SCREEN_MOD     ; odd-plane modulo  (skip 4 planes between rows)
    dc.w    BPL2MOD,SCREEN_MOD     ; even-plane modulo (same value for non-interlaced)

; cpPlanes  - patched by GameCopperInit to point at DisplayScreen bitplanes.
; Each plane occupies SCREEN_WIDTH_BYTE bytes per row.  The five planes are
; stored consecutively: plane0 row0, plane1 row0 ... plane4 row0, plane0 row1 ...
; (interleaved layout as required by the SCREEN_MOD modulo scheme).
cpPlanes:
    dc.w    BPL1PTH,0               ; bitplane 1 address high word (patched)
    dc.w    BPL1PTL,0               ; bitplane 1 address low  word (patched)
    dc.w    BPL2PTH,0               ; bitplane 2 address high word (patched)
    dc.w    BPL2PTL,0               ; bitplane 2 address low  word (patched)
    dc.w    BPL3PTH,0               ; bitplane 3 address high word (patched)
    dc.w    BPL3PTL,0               ; bitplane 3 address low  word (patched)
    dc.w    BPL4PTH,0               ; bitplane 4 address high word (patched)
    dc.w    BPL4PTL,0               ; bitplane 4 address low  word (patched)
    dc.w    BPL5PTH,0               ; bitplane 5 address high word (patched)
    dc.w    BPL5PTL,0               ; bitplane 5 address low  word (patched)

; cpSprites  - patched each frame by ShowSprite / ClearSprites.
; On the OCS/ECS Amiga there are 8 hardware sprite channels (SPR0..SPR7).
;   SPR0-3  player character (two attached pairs, 24px wide, 16 colours)
;   SPR4-7  unused (NullSprite)
cpSprites:
    dc.w    SPR0PTH,0               ; sprite 0 data pointer high (patched)
    dc.w    SPR0PTL,0               ; sprite 0 data pointer low  (patched)
    dc.w    SPR1PTH,0               ; sprite 1 data pointer high (patched)
    dc.w    SPR1PTL,0               ; sprite 1 data pointer low  (patched)
    dc.w    SPR2PTH,0               ; sprite 2 data pointer high (patched)
    dc.w    SPR2PTL,0               ; sprite 2 data pointer low  (patched)
    dc.w    SPR3PTH,0               ; sprite 3 data pointer high (patched)
    dc.w    SPR3PTL,0               ; sprite 3 data pointer low  (patched)
    dc.w    SPR4PTH,0               ; sprite 4 data pointer high (patched -> NullSprite)
    dc.w    SPR4PTL,0               ; sprite 4 data pointer low  (patched -> NullSprite)
    dc.w    SPR5PTH,0               ; sprite 5 data pointer high (patched -> NullSprite)
    dc.w    SPR5PTL,0               ; sprite 5 data pointer low  (patched -> NullSprite)
    dc.w    SPR6PTH,0               ; sprite 6 data pointer high (patched -> NullSprite)
    dc.w    SPR6PTL,0               ; sprite 6 data pointer low  (patched -> NullSprite)
    dc.w    SPR7PTH,0               ; sprite 7 data pointer high (patched -> NullSprite)
    dc.w    SPR7PTL,0               ; sprite 7 data pointer low  (patched -> NullSprite)

; cpPal  - 32 palette entries, patched by SetLevelAssets / GameCopperInit.
; COLOR00 (index 0) is the background colour, also used for transparent sprite pixels.
; Colors 0-15  = tile/background palette (from tiles_N.pal)
; Colors 16-31 = sprite / actor palette  (from sprites.pal)
; Initial value $00f (blue) is a placeholder visible only before the real palette is loaded.
cpPal:
    dc.w    COLOR00,$00f            ; colour  0: background (placeholder blue)
    dc.w    COLOR01,0               ; colour  1 (patched)
    dc.w    COLOR02,0               ; colour  2 (patched)
    dc.w    COLOR03,0               ; colour  3 (patched)
    dc.w    COLOR04,0               ; colour  4 (patched)
    dc.w    COLOR05,0               ; colour  5 (patched)
    dc.w    COLOR06,0               ; colour  6 (patched)
    dc.w    COLOR07,0               ; colour  7 (patched)
    dc.w    COLOR08,0               ; colour  8 (patched)
    dc.w    COLOR09,0               ; colour  9 (patched)
    dc.w    COLOR10,0               ; colour 10 (patched)
    dc.w    COLOR11,0               ; colour 11 (patched)
    dc.w    COLOR12,0               ; colour 12 (patched)
    dc.w    COLOR13,0               ; colour 13 (patched)
    dc.w    COLOR14,0               ; colour 14 (patched)
    dc.w    COLOR15,0               ; colour 15 (patched)
    dc.w    COLOR16,0               ; colour 16 - sprite palette start (patched)
    dc.w    COLOR17,0               ; colour 17 (patched)
    dc.w    COLOR18,0               ; colour 18 (patched)
    dc.w    COLOR19,0               ; colour 19 (patched)
    dc.w    COLOR20,0               ; colour 20 (patched)
    dc.w    COLOR21,0               ; colour 21 (patched)
    dc.w    COLOR22,0               ; colour 22 (patched)
    dc.w    COLOR23,0               ; colour 23 (patched)
    dc.w    COLOR24,0               ; colour 24 (patched)
    dc.w    COLOR25,0               ; colour 25 (patched)
    dc.w    COLOR26,0               ; colour 26 (patched)
    dc.w    COLOR27,0               ; colour 27 (patched)
    dc.w    COLOR28,0               ; colour 28 (patched)
    dc.w    COLOR29,0               ; colour 29 (patched)
    dc.w    COLOR30,0               ; colour 30 (patched)
    dc.w    COLOR31,0               ; colour 31 (patched)

; cpVHSDistort - VHS tracking-error scanline distortion (patched by vhs_rewind.asm)
;
; Three WAIT+BPLCON1 pairs cover the top, middle, and bottom thirds of the screen.
; Each slot fires at a pseudo-random line within its region and sets BPLCON1 to a
; colour-clock shift value ($11/$22/$33 = 2/4/6 lo-res pixels).  The shift persists
; to the start of the next slot (or end-of-frame); the BPLCON1=$0000 MOVE at the
; top of cpTest resets the register cleanly at the beginning of every new frame.
;
; Slots always carry valid scanline WAITs (never $ff07) so no slot blocks the next.
; When the shift value is 0, the WAIT fires but BPLCON1 stays $0000 (no visible change).
; VHS_ClearDistort writes base-line WAITs + $0000 to all three slots when inactive.
cpVHSDistort:
    dc.w    $2c07,$fffe             ; slot 0: WAIT at display-top line (patched each frame)
    dc.w    BPLCON1,$0000           ; slot 0: horizontal shift value (0 = inactive)
    dc.w    $7407,$fffe             ; slot 1: WAIT at middle-third base line (patched)
    dc.w    BPLCON1,$0000           ; slot 1: horizontal shift value
    dc.w    $bc07,$fffe             ; slot 2: WAIT at bottom-third base line (patched)
    dc.w    BPLCON1,$0000           ; slot 2: horizontal shift value

    dc.l    COPPER_HALT             ; end-of-list marker 1 ($fffffffe)
    dc.l    COPPER_HALT             ; end-of-list marker 2 (belt-and-braces)


;==============================================================================
; cpTitle  -  Title screen copper list
;
; Identical structure to cpTest but uses a wider screen geometry to accommodate
; the title screen which is larger than the game screen (extra pixels for the
; scrolling star effect on plane 4).
;
; Title screen is TITLE_SCREEN_WIDTH x TITLE_SCREEN_HEIGHT pixels.
; BPL1MOD / BPL2MOD = TITLE_SCREEN_MOD (wider than game screen).
;
; The star graphics are blitted onto bitplane 4 of DisplayScreen by BlitStar32.
; The title logo is copied to bitplanes 0-2 of DisplayScreen by TitleSetup.
; Bitplane 3 is unused (background = colour 0 = black).
;==============================================================================

cpTitle:
    dc.w    $01fc,$0000             ; FMODE: OCS-compatible slow fetch mode

    dc.w    DIWSTRT,WINDOW_START    ; same display window as game screen
    dc.w    DIWSTOP,WINDOW_STOP
    dc.w    DDFSTRT,FETCH_START
    dc.w    DDFSTOP,FETCH_STOP

    dc.w    BPLCON0,$5200           ; 5 bitplanes, colour enable, lo-res
    dc.w    BPLCON1,$0000           ; no horizontal scroll
    dc.w    BPLCON2,$0024           ; sprite/playfield priority
    dc.w    BPL1MOD,TITLE_SCREEN_MOD   ; wider modulo for title screen format
    dc.w    BPL2MOD,TITLE_SCREEN_MOD

; cpTitlePlanes  - patched by TitleCopperSetup.
; Bitplane pointers stride by TITLE_SCREEN_WIDTH_BYTE instead of SCREEN_WIDTH_BYTE.
cpTitlePlanes:
    dc.w    BPL1PTH,0               ; title bitplane 1 high (patched)
    dc.w    BPL1PTL,0               ; title bitplane 1 low  (patched)
    dc.w    BPL2PTH,0               ; title bitplane 2 high (patched)
    dc.w    BPL2PTL,0               ; title bitplane 2 low  (patched)
    dc.w    BPL3PTH,0               ; title bitplane 3 high (patched)
    dc.w    BPL3PTL,0               ; title bitplane 3 low  (patched)
    dc.w    BPL4PTH,0               ; title bitplane 4 high (patched)
    dc.w    BPL4PTL,0               ; title bitplane 4 low  (patched)
    dc.w    BPL5PTH,0               ; title bitplane 5 high (patched)
    dc.w    BPL5PTL,0               ; title bitplane 5 low  (patched)

; cpTitleSprites  - all 8 sprites pointed at NullSprite on the title screen.
; (No hardware sprites used on title; the star animation uses the blitter.)
cpTitleSprites:
    dc.w    SPR0PTH,0               ; sprite 0 high (-> NullSprite)
    dc.w    SPR0PTL,0               ; sprite 0 low
    dc.w    SPR1PTH,0               ; sprite 1 high (-> NullSprite)
    dc.w    SPR1PTL,0               ; sprite 1 low
    dc.w    SPR2PTH,0               ; sprite 2 high (-> NullSprite)
    dc.w    SPR2PTL,0               ; sprite 2 low
    dc.w    SPR3PTH,0               ; sprite 3 high (-> NullSprite)
    dc.w    SPR3PTL,0               ; sprite 3 low
    dc.w    SPR4PTH,0               ; sprite 4 high (-> NullSprite)
    dc.w    SPR4PTL,0               ; sprite 4 low
    dc.w    SPR5PTH,0               ; sprite 5 high (-> NullSprite)
    dc.w    SPR5PTL,0               ; sprite 5 low
    dc.w    SPR6PTH,0               ; sprite 6 high (-> NullSprite)
    dc.w    SPR6PTL,0               ; sprite 6 low
    dc.w    SPR7PTH,0               ; sprite 7 high (-> NullSprite)
    dc.w    SPR7PTL,0               ; sprite 7 low

; cpTitlePal  - title screen palette, patched by TitleCopperSetup from TitlePal.
; The title raw graphic uses 3 bitplanes -> 8 colours (entries 0-7).
; Entries 8-31 are unused but set to 0 (black) for cleanliness.
cpTitlePal:
    dc.w    COLOR00,$000            ; colour  0: background (black)
    dc.w    COLOR01,0               ; colour  1 (patched from TitlePal)
    dc.w    COLOR02,0               ; colour  2 (patched)
    dc.w    COLOR03,0               ; colour  3 (patched)
    dc.w    COLOR04,0               ; colour  4 (patched)
    dc.w    COLOR05,0               ; colour  5 (patched)
    dc.w    COLOR06,0               ; colour  6 (patched)
    dc.w    COLOR07,0               ; colour  7 (patched - last used by logo)
    dc.w    COLOR08,0               ; colour  8 (unused)
    dc.w    COLOR09,0               ; colour  9 (unused)
    dc.w    COLOR10,0               ; colour 10 (unused)
    dc.w    COLOR11,0               ; colour 11 (unused)
    dc.w    COLOR12,0               ; colour 12 (unused)
    dc.w    COLOR13,0               ; colour 13 (unused)
    dc.w    COLOR14,0               ; colour 14 (unused)
    dc.w    COLOR15,0               ; colour 15 (unused)
    dc.w    COLOR16,0               ; colour 16 (star colour, set via TitlePal extra entries)
    dc.w    COLOR17,0               ; colour 17
    dc.w    COLOR18,0               ; colour 18
    dc.w    COLOR19,0               ; colour 19
    dc.w    COLOR20,0               ; colour 20
    dc.w    COLOR21,0               ; colour 21
    dc.w    COLOR22,0               ; colour 22
    dc.w    COLOR23,0               ; colour 23
    dc.w    COLOR24,0               ; colour 24
    dc.w    COLOR25,0               ; colour 25
    dc.w    COLOR26,0               ; colour 26
    dc.w    COLOR27,0               ; colour 27
    dc.w    COLOR28,0               ; colour 28
    dc.w    COLOR29,0               ; colour 29
    dc.w    COLOR30,0               ; colour 30
    dc.w    COLOR31,0               ; colour 31

; Ensure COLOR00 is black (override palette value)
    dc.w    COLOR00,$000            ; black background (immediate, no WAIT)

; Black background before bars start
  ;  dc.w    $2c07,$fffe             ; scanline $2c (display start)
  ;  dc.w    COLOR00,$000            ; black background

; cpTitleBar  -  9-scanline rotating copper bar for the middle of title screen
;
; Initial WAIT Y bytes ($80-$88) are patched each frame by MoveTitleBar.
; Color words at offsets +6, +14, +22, ... are rotated in-place by RotateTitleBar
; so that the bar appears to pulse/animate its colour field.
cpTitleBar:
    dc.w    $8007,$fffe             ; wait line $80 (patched each frame, middle of screen)
    dc.w    COLOR00,$f0b            ; bar colour 1 (red-orange)
    dc.w    $8107,$fffe             ; wait line $81 (patched)
    dc.w    COLOR00,$ff0            ; bar colour 2 (bright yellow)
    dc.w    $8207,$fffe
    dc.w    COLOR00,$fd0            ; bar colour 3 (orange-yellow)
    dc.w    $8307,$fffe
    dc.w    COLOR00,$39f            ; bar colour 4 (center, purple)
    dc.w    $8407,$fffe
    dc.w    COLOR00,$ff0            ; bar colour 5 (bright yellow)
    dc.w    $8507,$fffe
    dc.w    COLOR00,$39f            ; bar colour 6 (purple)
    dc.w    $8607,$fffe
    dc.w    COLOR00,$fd0            ; bar colour 7 (orange-yellow)
    dc.w    $8707,$fffe
    dc.w    COLOR00,$ff0            ; bar colour 8 (bright yellow)
    dc.w    $8807,$fffe
    dc.w    COLOR00,$f0b            ; bar colour 9 (red-orange)
    dc.w    $8907,$fffe             ; restore entry (patched to bar_Y + 9)
    dc.w    COLOR00,$000            ; restore background after bar

; cpTitleBar2  -  9-scanline rotating copper bar for middle of title screen
;
; Mirrors cpTitleBar at the same screen position. Initial WAIT Y bytes ($80-$88) are
; patched each frame by MoveTitleBar2 in the opposite direction (inverted sine wave).
; Colors rotate with the same pattern as cpTitleBar.
cpTitleBar2:
    dc.w    $8007,$fffe             ; wait line $80 (patched each frame, inverted, middle)
    dc.w    COLOR00,$f0b            ; bar colour 1 (red-orange)
    dc.w    $8107,$fffe             ; wait line $81 (patched)
    dc.w    COLOR00,$ff0            ; bar colour 2 (bright yellow)
    dc.w    $8207,$fffe
    dc.w    COLOR00,$fd0            ; bar colour 3 (orange-yellow)
    dc.w    $8307,$fffe
    dc.w    COLOR00,$39f            ; bar colour 4 (center, purple)
    dc.w    $8407,$fffe
    dc.w    COLOR00,$ff0            ; bar colour 5 (bright yellow)
    dc.w    $8507,$fffe
    dc.w    COLOR00,$39f            ; bar colour 6 (purple)
    dc.w    $8607,$fffe
    dc.w    COLOR00,$fd0            ; bar colour 7 (orange-yellow)
    dc.w    $8707,$fffe
    dc.w    COLOR00,$ff0            ; bar colour 8 (bright yellow)
    dc.w    $8807,$fffe
    dc.w    COLOR00,$f0b            ; bar colour 9 (red-orange)
    dc.w    $8907,$fffe             ; restore entry (patched to bar_Y + 9)
    dc.w    COLOR00,$000            ; restore background after bar

    dc.l    COPPER_HALT             ; end-of-list marker 1 ($fffffffe)
    dc.l    COPPER_HALT             ; end-of-list marker 2 (belt-and-braces)
