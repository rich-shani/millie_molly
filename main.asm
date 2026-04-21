
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; main.asm  -  Program Entry Point and Core Framework
;==============================================================================
;
; This is the top-level assembly file.  It:
;   1. Includes all headers (register/bit definitions, macros, variables, consts).
;   2. Defines the code section containing the program entry point (Main),
;      the VBlank interrupt handler (VBlankTick), and several utility routines
;      used across the game.
;   3. INCLUDEs all subsystem source files (keyboard, map, actors, player, etc.)
;      so the entire game assembles as a single translation unit.
;   4. Defines the data and BSS sections that lay out the game's static data,
;      compressed assets, Chip RAM buffers, and variable storage.
;
; Global register conventions (held constant after Init):
;   a5 = Variables base pointer  (Fast RAM BSS block)
;   a6 = $dff000  CUSTOM chip base
;   a4 = current Player structure pointer (set each frame from PlayerPtrs)
;   a3 = current Actor  structure pointer (set by actor routines)
;
;==============================================================================

    INCDIR     "include"
    INCDIR     "include/resources"

    INCLUDE    "hw.i"
    INCLUDE    "funcdef.i"

    include    "macros.asm"
    include    "variables.asm"

    include    "intbits.i"
    include    "dmabits.i"
    include    "const.asm"
    include    "struct.asm"

;==============================================================================
; Code section
;==============================================================================

    section    main,code


;==============================================================================
; Main  -  Program entry point
;
; Installs a minimal TRAP #0 handler at exception vector $80 so that any
; accidental TRAP #0 instruction loops on itself rather than crashing into
; random memory.  Then falls through immediately to Restart.
;
; On real hardware the OS (Workbench / CLI) transfers control here after the
; binary is loaded.  In an emulator / bare-metal environment the reset vector
; points here directly.
;==============================================================================

Main:
    lea        .trap(pc),a0
    move.l     a0,$80          ; install looping TRAP #0 handler at vector $80
    trap       #0              ; immediately trigger it - jumps to .trap below
.trap                          ; falls through: TRAP #0 now points here, so future
                               ; TRAP #0 calls will also land here (harmless loop)


;==============================================================================
; Restart  -  Hardware initialisation and main loop
;
; Resets the Amiga custom chip environment to a known blank state, then calls
; Init to set up game data structures and installs the VBlank interrupt.
; After that the CPU spins in an infinite loop - all game logic runs inside
; the VBlank handler (VBlankTick).
;
; Sequence:
;   1. Load a6 = CUSTOM ($dff000), a5 = Variables base.
;   2. Disable all DMA, audio DMA key, interrupts, and clear all pending
;      interrupt requests (write $7fff to DMACON/ADKCON/INTENA/INTREQ).
;   3. Call Init  - initialise keyboard, game state, copper, etc.
;   4. Call StartVBlank  - install VBlankTick at $6c and enable VERTB interrupt.
;   5. Spin forever (.forever loop) - game runs entirely from interrupts.
;==============================================================================

Restart:
    ;lea        AllChip,a0
    ;move.l     #AllChipEnd-AllChip,d7
    ;bsr        TurboClear

    ;lea        AllFast,a0
    ;move.l     #AllFastEnd-AllFast,d7
    ;bsr        TurboClear

    lea        CUSTOM,a6
    lea        Variables,a5
    move.w     #$7fff,DMACON(a6)
    move.w     #$7fff,ADKCON(a6)
    move.w     #$7fff,INTENA(a6)
    move.w     #$7fff,INTREQ(a6)

    bsr        Init

    bsr        StartVBlank
.forever
    bra        .forever

;==============================================================================
; LevelTest  -  Check for level completion or debug level navigation
;
; Called every frame from GameRun (gamestatus.asm).
;
; If LevelComplete is non-zero (all enemies destroyed), advances to the next
; level automatically.  Otherwise checks the F1 / F2 keys for manual level
; navigation (debug feature):
;   F1 = previous level (decrement LevelId, min 0)
;   F2 = next level     (increment LevelId, max 99)
;
; After any change, calls DrawMap to load and render the new level.
;
; Preserves all registers (all working registers saved/restored by DrawMap's
; own PUSHALL / POPALL).
;==============================================================================

LevelTest:
    tst.w      LevelComplete(a5)
    beq        .nope

    addq.w     #1,LevelId(a5)
    ; change GameStatus to LEVEL_INIT so that GameRun skips PlayerLogic and ShowSprite
    move.w      #LEVEL_INIT,GameStatus(a5)
    rts                             ; return; GameStatusRun dispatches LevelWipeRun next frame

.nope
    lea        Keys,a0
    tst.b      KEY_F1(a0)
    beq        .nof1
    clr.b      KEY_F1(a0)
    tst.w      LevelId(a5)
    beq        .nof1
    subq.w     #1,LevelId(a5)
    bra        .changelevel
.nof1
    tst.b      KEY_F2(a0)
    beq        .nof2
    clr.b      KEY_F2(a0)
    cmp.w      #99,LevelId(a5)
    beq        .nof2
    addq.w     #1,LevelId(a5)
.changelevel
   ; set GameStatus to LEVEL_INIT to force level initization sequence
    move.w      #LEVEL_INIT,GameStatus(a5)
 ;   bsr         DrawMap
;    bsr         DrawPlayersAndActors
 ;   bsr         LevelIntroSetup
.nof2
    rts

;==============================================================================
; DrawPlayers  -  Display both player characters (currently partially disabled)
;
; Iterates over the two player structures (Millie and Molly) and calls
; DrawPlayer for each to blit the correct sprite frame onto the screen.
;
; Millie's ShowSprite call is currently commented out (sprite is updated inside
; PlayerLogic / ActionPlayerFall instead).  Molly's DrawPlayer call is active.
;
; On entry: a5 = Variables base, a6 = CUSTOM base.
;==============================================================================

DrawPlayers:
    lea        Millie(a5),a4
    ;bsr        DrawPlayer
    bsr        ShowSprite
    lea        Molly(a5),a4
    bsr        DrawPlayer
    rts

;==============================================================================
; DrawPlayer  -  Blit one player's sprite to the screen
;
; Converts the player's tile-grid position to pixel coordinates, selects the
; current animation frame, and calls DrawSprite to blit it onto the screen.
; Does nothing if Player_Status == 0 (player is inactive / not yet in play).
;
; On entry:
;   a4 = pointer to Player structure (Millie or Molly)
;   a5 = Variables base
;   a6 = CUSTOM base
;
; Pixel position:  (Player_X * 24, Player_Y * 24)
; Frame index:     Player_SpriteOffset  (base for this character + animation frame)
;==============================================================================

DrawPlayer:
    tst.w      Player_Status(a4)
    beq        .exit
    moveq      #0,d0
    moveq      #0,d1
    move.w     Player_X(a4),d0
    move.w     Player_Y(a4),d1
    mulu       #24,d0
    mulu       #24,d1
    moveq      #0,d2
    add.w      Player_SpriteOffset(a4),d2
    bsr        DrawSprite
.exit
    rts
    
;==============================================================================
; Init  -  Minimal game initialisation
;
; Initialises the game-state variable and installs the keyboard handler.
; Additional copper / sprite / level setup is currently commented out; those
; operations are now driven by the GameStatus state machine (TitleSetup ->
; GameInit path) rather than being done unconditionally at startup.
;
; Called from Restart before the VBlank interrupt is enabled.
; a5 and a6 must already be loaded.
;==============================================================================

Init:

    move.w     #GAME_INIT,GameStatus(a5)
    bsr        KeyboardInit

 ;   bsr        GameCopperInit
;    bsr        GenSpriteMask
 ;   move.l     #cpTest,COP1LC(a6)
 ;   move.w     #0,COPJMP1(a6)
;
 ;   move.l     #-1,ScreenMemEnd
;    move.w     #BASE_DMA,DMACON(a6)
;
 ;   move.w     #START_LEVEL,LevelId(a5)
;
    rts



;==============================================================================
; GameInit  -  Full game screen initialisation (called from TitleSetup or
;                  directly when entering gameplay state)
;
; Sets up the game copper list, generates the hardware sprite mask data,
; installs the game copper list into Agnus, enables DMA, sets the starting
; level, and draws the first map.
;
; Sequence:
;   1. GameCopperInit  - build cpPlanes / cpPal copper entries for DisplayScreen
;   2. GenSpriteMask   - build SpriteMask from the Sprites tile data
;   3. Install cpTest copper list and start Copper (COPJMP1)
;   4. Set ScreenMemEnd sentinel to -1 (marks uninitialised double-buffer state)
;   5. Enable DMA (BASE_DMA)
;   6. Set LevelId = START_LEVEL and call DrawMap to render the opening level
;==============================================================================

GameInit:
    bsr        GameCopperInit
    bsr        GenSpriteMask
    move.l     #cpTest,COP1LC(a6)
    move.w     #0,COPJMP1(a6)

    move.l     #-1,ScreenMemEnd
    move.w     #BASE_DMA,DMACON(a6)
    rts


 ;   move.w     #START_LEVEL,LevelId(a5)

    ; change GameStatus to LEVEL_INIT
 ;   move.w      #LEVEL_INIT,GameStatus(a5)

;    bsr         DrawMap
 ;   bsr         DrawPlayersAndActors
  ;  bsr         LevelIntroSetup

  ;  rts

;==============================================================================
; CreateClearMasks  -  Pre-compute the 16 blitter first-word masks for ClearActor
;
; The blitter's BLTAFWM (first word mask) must vary with the sub-tile pixel
; offset of an actor so that only the correct bits are cleared when erasing
; a 24-pixel-wide tile from a 16-bit-aligned screen buffer.
;
; This routine builds the 16 possible masks (one per pixel offset 0..15) and
; stores them in ClearMasks(a5) as a table of 16 longwords.
;
; Algorithm:
;   Start mask = $ffffff00  (24 bits set, covering a 24-wide tile in 32 bits)
;   Each iteration: shift right 1 bit (LSR.L), and if the carry caused the MSB
;   to drop out (BCC), set bit 31 to $8000 (LSB of the WORD above).
;   This produces masks offset by 0..15 bit positions.
;
; Called once at game startup (from Init / GameInit).
;==============================================================================

CreateClearMasks:
    moveq      #16-1,d7
    lea        ClearMasks(a5),a0
    move.l     #$ffffff00,d0
.loop
    move.l     d0,(a0)+
    lsr.l      #1,d0
    bcc        .under
    move.w     #$8000,d0
.under
    dbra       d7,.loop
    rts    


;==============================================================================
; StartVBlank  -  Install VBlankTick and enable the vertical-blank interrupt
;
; Writes the address of VBlankTick into the level-3 autovector ($6c) and then
; enables both the master interrupt enable (INTF_INTEN) and the vertical-blank
; interrupt (INTF_VERTB) plus the Copper interrupt (INTF_COPER) in INTENA.
;
; After this call the CPU idles in the .forever loop and all game logic
; executes under interrupt.
;==============================================================================

StartVBlank:
    move.l     #VBlankTick,$6c
    move.w     #INTF_SETCLR|INTF_VERTB|INTF_COPER,INTENA(a6)
    rts


;==============================================================================
; VBlankTick  -  Level-3 vertical-blank interrupt service routine
;
; Fires once per video frame (~50 Hz PAL) via the level-3 autovector at $6c.
; Handles both the vertical-blank (INTF_VERTB) flag and the Copper interrupt
; (INTF_COPER); only acts on VERTB.
;
; Sequence:
;   1. Save all registers (PUSHALL).
;   2. Reload a6 = CUSTOM and a5 = Variables (may have been anything when
;      the interrupt arrived).
;   3. Read INTREQR to find which interrupt fired; check INTF_VERTB bit.
;   4. If not VERTB, exit cleanly (spurious interrupt from Copper etc.).
;   5. Acknowledge VERTB by writing the bit to INTREQ (twice - A4000 bug
;      workaround: some chipset revisions require two writes to clear reliably).
;   6. Increment TickCounter (frame counter, used by animation timers).
;   7. Call GameStatusRun to dispatch one frame of the current game state.
;   8. Restore all registers (POPALL) and return from exception (RTE).
;==============================================================================

VBlankTick:
    PUSHALL
    lea        CUSTOM,a6
    lea        Variables,a5

    move.w     INTREQR(a6),d0
    move.w     d0,d1
    and.w      #INTF_VERTB,d1
    beq        .exit

    move.w     d1,INTREQ(a6)
    move.w     d1,INTREQ(a6)                                              ; twice to avoid a4k hw bug

    addq.w     #1,TickCounter(a5)

    bsr        GameStatusRun

.exit
    POPALL
    rte



;==============================================================================
; GameCopperInit  -  Patch the game copper list with screen and palette data
;
; Called from GameInit before the copper list is activated.  Fills in the
; runtime-variable fields of cpTest that the assembler left as zeros:
;
;   cpPlanes  - writes the physical addresses of DisplayScreen's five bitplanes
;               into the BPL1PTH/L .. BPL5PTH/L copper MOVE pairs.
;               DisplayScreen is a single-buffered display (both ScreenPtrs
;               entries currently point to Screen1, and the copper is pointed
;               at DisplayScreen - only one buffer is active in this build).
;
;   cpPal     - copies the 32 halfword colour values from TilesPal0 (the
;               default tile palette) into the COLOR00..COLOR31 copper entries.
;
; Also calls ClearSprites to zero all 8 sprite copper entries (SPR0..SPR7
; pointed at NullSprite).
;
; Uses PLANE_TO_COPPER macro to split each 32-bit address into the two 16-bit
; copper words at +2 and +6 of each BPLxPTH/L pair.
;==============================================================================

GameCopperInit:
    move.l     #Screen1,ScreenPtrs(a5)
    move.l     #Screen2,ScreenPtrs+4(a5)

    bsr        ClearSprites

    move.l     #DisplayScreen,d0
    lea        cpPlanes,a0
    moveq      #SCREEN_DEPTH-1,d7
.ploop
    move.w     d0,6(a0)
    swap       d0
    move.w     d0,2(a0)
    swap       d0
    addq.l     #8,a0
    add.l      #SCREEN_WIDTH_BYTE,d0
    dbra       d7,.ploop

    lea        TilesPal0,a0
    lea        cpPal,a1
    moveq      #SCREEN_COLORS-1,d7
.cloop
    move.w     (a0)+,2(a1)    
    addq.l     #4,a1
    dbra       d7,.cloop

    rts

;==============================================================================
; ClearSprites  -  Point all 8 hardware sprite channels at NullSprite
;
; Writes the address of NullSprite (two zero longwords = a terminated, empty
; sprite structure) into all eight SPRxPTH/L copper list entries in cpSprites.
; This hides all hardware sprites from the display.
;
; Called by GameCopperInit at startup and whenever no sprite should be shown.
;
; NullSprite is a dc.l 0,0 in bss_c (Chip RAM) - Agnus needs to fetch it,
; so it must be in Chip RAM.  The terminator pattern (two zero words) tells
; Agnus to stop fetching sprite data immediately on the first line.
;==============================================================================

ClearSprites:
    lea        cpSprites,a0
    move.l     #NullSprite,d0
    moveq      #8-1,d7
.loop
    move.w     d0,6(a0)
    swap       d0
    move.w     d0,2(a0)
    swap       d0
    add.l      #8,a0
    dbra       d7,.loop
    rts



;==============================================================================
; Subsystem includes
;
; All game subsystems are assembled as a single translation unit by INCLUDEing
; them here.  They share the same section (main,code) and can call each other
; directly without any linking step.
;==============================================================================

    include    "keyboard.asm"
    include    "tools.asm"
    include    "mapstuff.asm"
    include    "actors.asm"
    include    "zx0_faster.asm"
    include    "spritetools.asm"
    include    "player.asm"
    include    "controls.asm"
    include    "title.asm"
    include    "gamestatus.asm"

;==============================================================================
; Fast RAM data section  (data_fast)
;
; Read-only tables and compressed asset pointers that do not need to be in
; Chip RAM.  Fast RAM is significantly faster to access than Chip RAM on
; expanded Amigas, so lookup tables, level data, and palette data live here.
;
; Contents:
;   Quartic / Quadratic / Sinus  - pre-computed easing / sine tables (binary)
;   assets.asm                   - tile asset tables and ZX0-compressed tile data
;   SpritePal                    - hardware sprite palette (sprites.pal)
;   TilesPal0..4                 - per-chapter tile palettes (tiles_N.pal)
;   LevelData                    - all 100 levels packed as raw 88-byte maps
;   WallpaperBaseTop/Base        - default wallpaper border tile templates
;   LevelCountRaw                - level counter UI source graphic (ui_4.bin)
;==============================================================================

    section    data_fast,data


;------------------------------------------------------------------------------
; Easing / animation tables  (pre-computed, accessed by index each frame)
;
; Quartic  - quartic ease-in curve (x^4), used for push-block acceleration
; Quadratic- quadratic ease curve, used for fall animation
; Sinus    - full-period sine table (SINE_ANGLES entries of signed 16-bit words)
;            SinusEnd marks the end so SINE_ANGLES can be derived at assemble time
;------------------------------------------------------------------------------

Quartic:    
    incbin     "assets/quartic.bin"
Quadratic:    
    incbin     "assets/quadratic.bin"
Sinus:    
    incbin     "assets/sin.bin"
SinusEnd:


    include    "assets.asm"

SpritePal:
    incbin     "assets/sprites.pal"

TilesPal0:
    incbin     "assets/Tiles/tiles_0.pal"
TilesPal1:
    incbin     "assets/Tiles/tiles_1.pal"
TilesPal2:
    incbin     "assets/Tiles/tiles_2.pal"
TilesPal3:
    incbin     "assets/Tiles/tiles_3.pal"
TilesPal4:
    incbin     "assets/Tiles/tiles_4.pal"

LevelData:
    incbin     "assets/Levels/levels.bin"
WallpaperBaseTop:
    dc.b       $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
WallpaperBase:
    REPT       WALL_PAPER_HEIGHT-1
    dc.b       $05,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$05,$05
    ENDR
    dc.b       $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
    
LevelCountRaw:
    incbin     "assets/ui_4.bin"
LevelCountRawEnd:

;==============================================================================
; Chip RAM data section  (data_chip)
;
; All data that must be in Chip RAM because it is accessed by the DMA hardware
; (Copper, Blitter, Agnus sprite DMA, audio DMA):
;
;   copperlists.asm  - cpTest and cpTitle copper list programs
;   RealSprites      - hardware sprite frame data (4 sprites * N frames)
;   Sprites          - actor / tile sprite source bitmaps (blitter source)
;   Shadows          - shadow mask bitmaps (single-plane, blitted under actors)
;   LevelFont        - 5-plane digit font for the level counter UI
;   TitleRaw         - raw interleaved bitplane data for the title screen logo
;   TitlePal         - title screen palette (with extra star colour entries)
;   uigfx.asm        - Button0Raw..Button3Raw UI button graphics
;   Star32           - 32x32 star graphic blitted by BlitStar32 on the title screen
;==============================================================================

    section    data_chip,data_c

    include    "copperlists.asm"

RealSprites:
    incbin     "assets/realsprites.bin"

Sprites:
    incbin     "assets/sprites.bin"
Shadows:
    incbin     "assets/shadows.bin"

LevelFont:
    incbin     "assets/levelfont.bin"

TitleRaw: 
    incbin     "assets/title_i.raw"

TitlePal:
    incbin     "assets/title.pal"
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff
    dc.w       $f00,$0f0,$00f,$fff

    include    "uigfx.asm"

Star32:
    incbin     "assets/star32.raw"


;==============================================================================
; Fast RAM BSS section  (mem_fast)
;
; Uninitialised working memory allocated in Fast RAM (cleared by TurboClear
; before gameplay begins).  Fast RAM gives the CPU faster access than Chip RAM
; for the data it accesses every frame.
;
;   Variables  - the global Variables block (layout defined in variables.asm),
;                permanently addressed via a5 throughout the game.
;   Keys       - 256-byte keyboard state buffer (KeyboardInterrupt writes here).
;                Followed by 200 bytes of padding to safely handle any out-of-
;                range scan-codes without corrupting adjacent data.
;==============================================================================

    section    mem_fast,bss

AllFast:

Variables:
    ds.b       Variables_sizeof


Keys:
    ds.b       256
    ds.b       200
	
AllFastEnd:



;==============================================================================
; Chip RAM BSS section  (mem_chip)
;
; Uninitialised working buffers that must be in Chip RAM because they are read
; or written by the Blitter, Copper, or sprite DMA every frame.
;
;   NullSprite      - two zero longwords (terminated empty sprite structure).
;                     All unused sprite channels are pointed here so Agnus
;                     fetches nothing and outputs transparent pixels.
;
;   ButtonMaskTemp  - working buffer for the composited player-switch button UI
;                     (570 bytes = button graphic height * interleaved stride).
;   LevelCountTemp  - working buffer for the composited level counter graphic.
;
;   TileSet         - TILESET_SIZE bytes: decompressed tile bitplane data.
;                     Filled by SetLevelAssets via zx0_decompress each level load.
;   TileMask        - TILESET_SIZE bytes: blitter mask derived from TileSet by
;                     GenTileMask.  Used as BLTBDAT source to avoid bleed when
;                     blitting transparent tiles.
;   SpriteMask      - SPRITESET_SIZE bytes: blitter mask for actor sprites,
;                     generated by GenSpriteMask from Sprites data.
;
;   Screen1/2       - double-buffer bitplane storage (SCREEN_SIZE each).
;                     Currently only Screen1 is used (single-buffer mode).
;   DisplayScreen    - the composited game frame.  DrawWalls, DrawPlayersAndActors, and
;                     BlitStar32 all write here; this is what the copper displays.
;   NonDisplayScreen      - a clean copy of the background (walls + ladders + shadows
;                     only, no actors).  ClearActor restores DisplayScreen by
;                     copying from NonDisplayScreen.
;
;   ScreenMemEnd    - 200-byte guard region after the last screen buffer.
;                     Initialised to -1 as a sentinel; any overrun that writes
;                     here is detectable in a debugger.
;==============================================================================

    section    mem_chip,bss_c
AllChip:

NullSprite:    
    ds.l       0,0

ButtonMaskTemp:
    ds.b       570
LevelCountTemp:
    ds.b       570


TileSet:
    ds.b       TILESET_SIZE
TileMask:
    ds.b       TILESET_SIZE
SpriteMask:
    ds.b       SPRITESET_SIZE

Screen1:
    ds.b       SCREEN_SIZE
Screen2:
    ds.b       SCREEN_SIZE

DisplayScreen:
    ds.b       SCREEN_SIZE

NonDisplayScreen:
    ds.b       SCREEN_SIZE

ScreenMemEnd:
    ds.b       200

AllChipEnd:
