
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; gamestatus.asm  -  Top-Level Game State Machine
;==============================================================================
;
; The game runs as a simple state machine.  Every VBlank interrupt calls
; GameStatusRun, which dispatches to the handler for the current state.
;
; States (stored in GameStatus(a5) as a word index):
;
;   0 - TitleSetup  (defined in title.asm)
;       One-shot initialisation of the title screen.  Copies the title graphic
;       into ScreenStatic, sets up the title copper list, positions the four
;       star objects, then immediately advances GameStatus to TitleRun (1).
;
;   1 - TitleRun    (defined in title.asm)
;       Runs every frame while the title screen is displayed.
;       Animates the four star objects by blitting Star32 onto plane 4.
;       No user input is handled here yet (TODO: start-game trigger).
;
;   2 - GameRun     (defined below)
;       Main gameplay loop, called every VBlank.
;       Checks F1/F2 for level navigation (debug), reads player controls,
;       and calls PlayerLogic to advance the active player action state machine.
;
;   3 - LevelWipeRun  (defined in mapstuff.asm)
;       Per-frame handler for the end-of-level screen wipe.
;       Progressively blacks out tiles in the chosen wipe pattern, holds,
;       then loads the next level and advances to GAME_REVEAL (4).
;
;   4 - LevelRevealRun  (defined in mapstuff.asm)
;       Per-frame handler for the level-entry reveal.
;       Progressively restores tiles from ScreenSave in reverse-wipe order,
;       then draws actors and returns to GameRun (2).
;
; The JMPINDEX macro (macros.asm) converts the GameStatus word into a
; PC-relative jump through the word-offset table at .i.
;
;==============================================================================


;==============================================================================
; GameStatusRun  -  Dispatch to the current game state handler
;
; Called from VBlankTick once per frame (after confirming the VBlank flag).
; a5 must be loaded with the Variables base before calling.
; a6 must be $dff000 (CUSTOM chip base).
;
; No arguments.  Tail-calls the appropriate state handler via JMPINDEX.
;==============================================================================

GameStatusRun:
    move.w      GameStatus(a5),d0    ; load current state index (0..4)
    JMPINDEX    d0                   ; computed jump through offset table below

.i  ; jump-offset table - one signed word per state
    dc.w        TitleSetup-.i        ; state 0 -> TitleSetup    (in title.asm)
    dc.w        TitleRun-.i          ; state 1 -> TitleRun      (in title.asm)
    dc.w        GameRun-.i           ; state 2 -> GameRun       (below)
    dc.w        LevelWipeRun-.i      ; state 3 -> LevelWipeRun  (in mapstuff.asm)
    dc.w        LevelRevealRun-.i    ; state 4 -> LevelRevealRun (in mapstuff.asm)


;==============================================================================
; GameRun  -  Main gameplay frame handler (called every VBlank in state 2)
;
; Sequence each frame:
;   1. LevelTest      - check if LevelComplete flag is set or F1/F2 pressed;
;                       if LevelComplete, starts the wipe and returns early so
;                       PlayerLogic does NOT run (preventing a sprite re-enable
;                       in the same frame that LevelWipeSetup hid the sprites).
;   2. UpdateControls - sample keyboard, update ControlsHold / ControlsTrigger.
;   3. PlayerLogic    - run the active player's action state machine one step.
;                       The active player pointer is loaded from PlayerPtrs(a5)
;                       into a4 before calling.
;   4. ActionCloudActors - animate enemy death cloud puff animations.
;   5. AnimateEnemies - cycle ENEMYFALL/ENEMYFLOAT tile frames at 2fps.
;
; Note: DrawPlayers is currently commented out - sprite display is handled
; inside PlayerLogic / ActionPlayerFall via ShowSprite.
;==============================================================================

GameRun:
    bsr         LevelTest            ; advance level if complete or F1/F2 pressed
    cmp.w       #GAME_WIPE,GameStatus(a5) ; did LevelTest trigger a wipe?
    beq         .done                ; yes: skip player logic so ShowSprite can't
                                     ;      re-enable the sprites we just hid

    ;bsr        DrawPlayers          ; (disabled: sprite update inside PlayerLogic)

    bsr         UpdateControls       ; read keyboard, compute trigger/hold bytes

    move.l      PlayerPtrs(a5),a4   ; a4 -> active player structure (first entry)
    bsr         PlayerLogic          ; run player action state machine for this frame

    bsr         ActionCloudActors    ; animate any pending enemy death cloud animations
    bsr         AnimateEnemies       ; cycle ENEMYFALL/ENEMYFLOAT tile frames (2fps)

.done
    rts
