
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; uigfx.asm  -  UI Button Graphics (Chip RAM)
;==============================================================================
;
; Four raw interleaved bitplane images for the player-switch button UI element.
; These are blitted onto the screen by DrawButton (mapstuff.asm) to display the
; active player indicator above the game map.
;
; ui_0.bin - ui_3.bin are four animation / state variants of the button graphic
; (e.g. Millie active, Molly active, pressed, idle).  Each is the same size
; as a fixed rectangular UI element stored in 5-plane interleaved format.
;
; These labels reside in the data_chip section (Chip RAM) because they are
; used as blitter source data, and the blitter can only DMA from Chip RAM.
; They are placed here (included from main.asm inside data_chip) so that they
; assemble into the correct section.
;
; ButtonMaskTemp and LevelCountTemp (bss_c) are the working Chip RAM buffers
; that receive the composited button / level-counter graphics each frame before
; they are blitted to DisplayScreen.
;==============================================================================

Button0Raw:
    incbin    "assets/ui_0.bin"   ; button state 0 (e.g. Molly  active)
Button1Raw:
    incbin    "assets/ui_1.bin"   ; button state 1 (e.g. Millie active)
Button2Raw:
    incbin    "assets/ui_2.bin"   ; button state 2
Button3Raw:
    incbin    "assets/ui_3.bin"   ; button state 3

