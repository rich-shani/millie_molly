
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; macros.asm  -  Assembly Macros
;==============================================================================
;
; All macros used throughout the codebase are defined here.
; This file is INCLUDEd near the top of main.asm before any code is assembled.
;
; DEVPAC/ASM-ONE macro syntax:
;   MACRO name ... ENDM        - defines the macro body
;   \1, \2, ...                - positional arguments
;   .\@                        - unique local label suffix (expanded per invocation)
;
; Register convention (for context when reading macro bodies):
;   a5 = Variables base pointer   a6 = $dff000 (CUSTOM chip registers)
;   a4 = current player struct    a3 = current actor struct
;   d7 = general loop counter     sp = system stack pointer
;
;==============================================================================


;==============================================================================
; Stack save/restore macros
;
; The 68000 has no PUSH/POP instructions; these macros simulate them using
; MOVEM and pre-decrement / post-increment addressing.
;
; PUSH / POP      - save / restore a single register (as a longword)
; PUSHM / POPM    - save / restore a register list (MOVEM syntax: d0-d2/a0/a1)
; PUSHMOST        - save d0-a4 (all data regs and most address regs); used by
;                   subroutines that must preserve the caller's context but do
;                   not need to preserve a5/a6 (which are global constants).
; POPMOST         - matching restore for PUSHMOST
; PUSHALL         - save everything (d0-a6); used in interrupt handlers where
;                   ANY register could be in use by the interrupted code.
; POPALL          - matching restore for PUSHALL
;
; Stack grows downward: MOVEM Rn,-(sp) decrements sp THEN stores (pre-dec).
;                        MOVEM (sp)+,Rn loads THEN increments (post-inc).
;==============================================================================

PUSH               MACRO
                   move.l     \1,-(sp)
                   ENDM

POP                MACRO
                   move.l     (sp)+,\1
                   ENDM

PUSHM              MACRO
                   movem.l    \1,-(sp)
                   ENDM

POPM               MACRO
                   movem.l    (sp)+,\1
                   ENDM

PUSHMOST           MACRO
                   movem.l    d0-a4,-(sp)   ; save d0-d7, a0-a4 (11 regs = 44 bytes)
                   ENDM

POPMOST            MACRO
                   movem.l    (sp)+,d0-a4
                   ENDM

PUSHALL            MACRO
                   movem.l    d0-a6,-(sp)   ; save all 15 regs (d0-d7, a0-a6 = 60 bytes)
                   ENDM

POPALL             MACRO
                   movem.l    (sp)+,d0-a6
                   ENDM


;==============================================================================
; JMPINDEX  -  Indexed jump dispatch (computed GOTO / switch-case)
;
; Implements a jump table using PC-relative word offsets.  Used wherever the
; code branches on a small integer state value (action state, block type, etc.).
;
; Argument:  \1 = a DATA register containing the 0-based index (word).
;            The index register is destroyed (doubled in place).
;
; Usage pattern (example from PlayerLogic):
;
;   move.w  ActionStatus(a5),d0
;   JMPINDEX d0
; .i
;   dc.w    HandlerA-.i      ; index 0
;   dc.w    HandlerB-.i      ; index 1
;   dc.w    HandlerC-.i      ; index 2
;
; How it works:
;   1. Double the index (word size = 2 bytes per entry).
;   2. Read the signed word offset from the table (PC-relative).
;   3. Add that offset to the PC (which already points at the table base .i)
;      and jump there.
;
; The generated code sequence is:
;   ADD.W  d0,d0              ; index *= 2  (byte offset into word table)
;   MOVE.W .jmplist(pc,d0.w),d0   ; read signed 16-bit offset
;   JMP    .jmplist(pc,d0.w)      ; jump to handler
; .jmplist:
;   dc.w ...
;
; IMPORTANT: The label ".\@jmplist" is unique per invocation (.\@ = unique suffix)
;            so multiple JMPINDEX macros in the same source file do not clash.
;==============================================================================

JMPINDEX           MACRO
                   add.w      \1,\1                       ; index * 2 (word entries)
                   move.w     .\@jmplist(pc,\1.w),\1      ; load signed word offset
                   jmp        .\@jmplist(pc,\1.w)         ; jump through offset
.\@jmplist
                   ENDM


;==============================================================================
; RANDOMWORD  -  16-bit pseudo-random number generator
;
; Generates a new 16-bit pseudo-random value in the upper word of d0.
; Uses a simple multiply-add LFSR/LCG hybrid seeded from RandomSeed(a5).
;
; Algorithm:
;   seed = (seed_hi * $9D3D) + seed       (treating seed as two 16-bit halves)
;   result = upper 16 bits of new seed
;
; Destroys: d0 (result in upper word, lower word = 0 after SWAP/CLR)
; Preserves: d1 (saved/restored on stack)
; Requires:  a5 = Variables base pointer
;
; After the macro, d0 contains the 16-bit random value in its LOW word
; (due to the SWAP at the end).
;==============================================================================

RANDOMWORD         MACRO
                   move.l     d1,-(sp)           ; preserve d1
                   move.l     RandomSeed(a5),d0  ; load current 32-bit seed
                   move.l     d0,d1
                   swap.w     d0                 ; d0 = high word of seed
                   mulu.w     #$9D3D,d1          ; multiply low word by magic constant
                   add.l      d1,d0              ; add to produce new seed
                   move.l     d0,RandomSeed(a5)  ; store new seed
                   clr.w      d0                 ; clear low word
                   swap.w     d0                 ; d0.w = random value (was high word)
                   move.l     (sp)+,d1           ; restore d1
                   ENDM


;==============================================================================
; PLANE_TO_COPPER  -  Write a 32-bit address into a copper list bitplane entry
;
; The Copper stores 32-bit addresses split across two consecutive instruction
; pairs.  Each pair is  { MOVE #reg, hi_word } { MOVE #reg+4, lo_word }.
; In memory this looks like:
;   +0  reg_number (word)        <- written by Copper
;   +2  high 16 bits of address  <- this is what we write to +2(\2)
;   +4  reg_number+4 (word)
;   +6  low  16 bits of address  <- this is what we write to +6(\2)
;
; Arguments:
;   \1 = data register holding the 32-bit address (address is preserved via SWAP)
;   \2 = address register pointing to the copper list plane entry (e.g. cpPlanes)
;
; The SWAP / SWAP trick: SWAP gives us the two halves in sequence without
; needing a second register.  After the macro, \1 is unchanged (swapped twice).
;==============================================================================

PLANE_TO_COPPER    MACRO
                   move.w     \1,6(\2)    ; write low  16 bits to copper entry low  word
                   swap       \1          ; bring high 16 bits to lower word
                   move.w     \1,2(\2)    ; write high 16 bits to copper entry high word
                   swap       \1          ; restore \1 to original value
                   ENDM


;==============================================================================
; Blitter wait macros  (WAITBLIT / WAITBLITN)
;
; The Amiga blitter is an autonomous DMA device.  The CPU must not access
; blitter registers while a blit is in progress or data corruption will result.
;
; The standard wait sequence is:
;   1. Enable blitter priority (CPU yields to blitter when accessing Chip RAM).
;   2. Read DMACONR bit 14 (Blitter busy flag) - but the first read is
;      unreliable on some chipsets so we do a dummy read first (tst.b $02(a6)).
;   3. Spin until the busy flag is clear.
;   4. Disable blitter priority (restore normal CPU/blitter arbitration).
;
; BLITPRI_ENABLE  = $8400  : set bit 14 (BLTPRI) + bit 15 (SETCLR) in DMACON
; BLITPRI_DISABLE = $0400  : clear bit 14 (BLTPRI) (bit 15 = 0 means clear)
;
; The "twice to avoid A4000 hardware bug" pattern (INTREQ written twice) is
; analogous - some chip revisions require two writes to clear a flag reliably.
;
; WAITBLIT and WAITBLITN are functionally identical here; the two names allow
; a distinction between "wait before starting a new blit" (WAITBLIT) and
; "wait before using blitter output data" (WAITBLITN) if needed.
;==============================================================================

BLITPRI_ENABLE  = $8400    ; DMACON write value: SET blitter priority (CPU waits)
BLITPRI_DISABLE = $0400    ; DMACON write value: CLR blitter priority (normal)

WAITBLIT           MACRO
                   move.w     #BLITPRI_ENABLE,DMACON(a6)   ; give blitter bus priority
                   tst.b      $02(a6)                       ; dummy read  (chipset bug workaround)
.\@                btst       #6,$02(a6)                    ; test DMACONR bit 6 (blitter busy)
                   bne.b      .\@                           ; loop while busy
                   move.w     #BLITPRI_DISABLE,DMACON(a6)  ; restore normal arbitration
                   ENDM

WAITBLITN          MACRO
                   move.w     #BLITPRI_ENABLE,DMACON(a6)
                   tst.b      $02(a6)
.\@                btst       #6,$02(a6)
                   bne.b      .\@
                   move.w     #BLITPRI_DISABLE,DMACON(a6)
                   ENDM


;==============================================================================
; ROTATE_LONG  -  Rotate an array of longwords in-place (cyclic shift left)
;
; Performs an in-place cyclic rotation of \2 longwords starting at address
; register \1.  The first element is moved to the end and everything else
; shifts one position towards the front.
;
; Uses MOVEM for bulk register-based copy (much faster than a loop on 68000).
; Separate cases are generated for each supported count (2 through 7) at
; assembly time via IFEQs - these expand to inline code with no loop overhead.
;
; Argument:
;   \1 = address register pointing to the array base
;   \2 = number of longwords in the array (2..7, evaluated at assembly time)
;
; Note: \1 is modified during the operation and then restored.
; The IFEQs are mutually exclusive (only one will be true for a given \2).
;
; Example with \2=3 (array of 3 longs: [A, B, C]):
;   d7 = A  (save last element first, which is at offset (\2-1)*4)
;   MOVEM loads [A, B] from (\1)+  -> advances \1 by 8
;   Add 4 to \1 (skip one slot for insert)
;   MOVEM stores [A, B] at -(\1)   -> [_, A, B] with \1 back to original+8
;   Store d7 (=A) at -(\1)         -> [A, A, B]  <- wrong, let me re-read...
;
; Actually: saves the LAST element ((\2-1)*4(\1)), shifts remaining elements
; forward by one slot (toward higher addresses), then puts the saved element
; at the beginning.  Result: [last, first, second, ...] i.e. rotate-right.
;==============================================================================

ROTATE_LONG        MACRO

                   ifeq       \2-7
                   move.l     (\2-1)*4(\1),d7
                   movem.l    (\1)+,d0/d1/d2/d3/d4/d5
                   addq.l     #4,\1
                   movem.l    d0/d1/d2/d3/d4/d5,-(\1)
                   move.l     d7,-(\1)
                   endif

                   ifeq       \2-6
                   move.l     (\2-1)*4(\1),d7
                   movem.l    (\1)+,d0/d1/d2/d3/d4
                   addq.l     #4,\1
                   movem.l    d0/d1/d2/d3/d4,-(\1)
                   move.l     d7,-(\1)
                   endif

                   ifeq       \2-5
                   move.l     (\2-1)*4(\1),d7
                   movem.l    (\1)+,d0/d1/d2/d3
                   addq.l     #4,\1
                   movem.l    d0/d1/d2/d3,-(\1)
                   move.l     d7,-(\1)
                   endif

                   ifeq       \2-4
                   move.l     (\2-1)*4(\1),d7
                   movem.l    (\1)+,d0/d1/d2
                   addq.l     #4,\1
                   movem.l    d0/d1/d2,-(\1)
                   move.l     d7,-(\1)
                   endif

                   ifeq       \2-3
                   move.l     (\2-1)*4(\1),d7
                   movem.l    (\1)+,d0/d1
                   addq.l     #4,\1
                   movem.l    d0/d1,-(\1)
                   move.l     d7,-(\1)
                   endif

                   ifeq       \2-2
                   movem.l    (\1)+,d0/d1    ; load both longs, advance \1
                   exg        d0,d1          ; swap them
                   movem.l    d0/d1,-(\1)    ; store back (now rotated)
                   endif

                   ENDM


;==============================================================================
; KeyTest  -  Test a key and set a bit in d0
;
; Used exclusively inside ReadControls to build the control byte.
;
; Arguments:
;   \1 = keyboard scan-code (byte offset into Keys[] array; a0 = Keys base)
;   \2 = bit number to set in d0 if the key is pressed
;
; If Keys[\1] is non-zero (key held), bit \2 of d0 is set via BSET.
; d0 accumulates all pressed keys across multiple KeyTest expansions.
;
; The local label .\@notpressed gets a unique suffix per call to prevent
; multiple instances in the same routine from clashing.
;==============================================================================

KeyTest            MACRO
                   tst.b      (\1,a0)            ; is Keys[scan_code] non-zero?
                   beq.b      .\@notpressed       ; branch if key not pressed
                   bset       #\2,d0              ; set corresponding control bit
.\@notpressed
                   ENDM


;==============================================================================
; TODECIMAL  -  Convert a binary integer to packed BCD digits in a register
;
; Converts the value in \1 to \2+1 decimal digits stored packed (4 bits each)
; in the LOW word of \3.  Used by DrawLevelCounter to extract digit values
; for font rendering.
;
; Arguments:
;   \1 = source value register (DESTROYED - divided repeatedly)
;   \2 = number of digits - 1  (e.g. 3 for a 4-digit number, passed to MOVEQ)
;   \3 = destination register  (receives packed BCD result)
;
; Algorithm (per digit, repeated \2+1 times):
;   DIVU #10, \1   -> quotient in upper word, remainder (digit) in lower word
;   SWAP \1        -> bring remainder to lower word
;   OR.B \1, \3    -> OR the digit into the low byte of \3
;   CLR.W \1       -> zero the remainder word
;   SWAP \1        -> restore quotient for next iteration
;   ROR.W #4, \3   -> shift \3 right 4 bits (make room for next digit)
;
; After the loop, \3 contains the digits arranged with the most-significant
; digit in the highest nibble of the word.
;==============================================================================

TODECIMAL          MACRO
                   moveq      #\2,d7             ; loop counter = digit count - 1
                   moveq      #0,\3              ; clear destination
.\@loop            divu       #10,\1             ; \1.hi = remainder (next digit), \1.lo = quotient
                   swap       \1                 ; bring remainder to low word
                   or.b       \1,\3              ; OR digit into low byte of result
                   clr.w      \1                 ; clear remainder
                   swap       \1                 ; restore quotient
                   ror.w      #4,\3              ; shift result right one nibble
                   dbra       d7,.\@loop
                   ENDM


;==============================================================================
; DECIMAL2  -  Extract two decimal digits from a value
;
; Simpler two-digit variant: extracts the tens digit into the high byte of \2
; and the units digit into the low byte.
;
; Arguments:
;   \1 = source value (DESTROYED)
;   \2 = destination register (two digit values packed as { tens, units })
;==============================================================================

DECIMAL2           MACRO
                   moveq      #0,\2              ; clear destination
                   divu       #10,\1             ; divide by 10
                   swap       \1                 ; remainder = units digit
                   move.w     \1,\2              ; store units in low word of \2
                   swap       \2                 ; move units to high word
                   clr.w      \1                 ; clear remainder
                   swap       \1                 ; restore quotient (= tens digit)
                   divu       #10,\1             ; divide again
                   swap       \1                 ; remainder = tens digit
                   move.w     \1,\2              ; store tens in low word of \2
                   ENDM


;==============================================================================
; LVLFNT  -  Blit one row of a font digit onto the level counter graphic
;
; Used inside a loop in DrawLevelCounter to composite a decimal digit from
; LevelFont onto the LevelCountTemp working buffer.
;
; The level counter UI element shows the current level number.  Each digit is
; read from LevelFont (a 5-plane bitmap font, LEVEL_FONT_WIDTH_BYTE bytes wide)
; and OR-masked onto the corresponding position in LevelCountTemp.
;
; Arguments:
;   \1 = bitplane index (0..4)
;
; Register context assumed:
;   a0  = pointer to current row/plane of LevelCountTemp (destination)
;   a2  = pointer to current row of LevelFont (source digit)
;   d5  = pre-computed NOT of the font mask (all 5 planes OR-ed, then inverted)
;         used to clear the target area before OR-ing in the new digit pixel
;   d2  = scratch for the composite operation
;
; Each invocation handles one bitplane row:
;   1. Load the byte from LevelCountTemp plane \1 (offset = LEVEL_COUNT_WIDTH_BYTE*\1)
;   2. AND with d5 (the inverted mask) to clear bits where the digit will go
;   3. OR in the corresponding byte from LevelFont plane \1
;   4. Store back to LevelCountTemp
;==============================================================================

LVLFNT             MACRO
                   move.b     LEVEL_COUNT_WIDTH_BYTE*\1(a0),d2   ; load target byte
                   and.b      d5,d2                               ; clear digit area (mask)
                   or.b       LEVEL_FONT_WIDTH_BYTE*\1(a2),d2    ; OR in font pixel
                   move.b     d2,LEVEL_COUNT_WIDTH_BYTE*\1(a0)   ; write back
                   ENDM
