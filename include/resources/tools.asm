
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; tools.asm  -  Low-Level Utility Routines
;==============================================================================


;==============================================================================
; TurboClear  -  Fast memory clear using MOVEM
;
; Clears a block of memory to zero as quickly as possible on the 68000 by
; using MOVEM to write 13 registers (52 bytes) per loop iteration.  This is
; significantly faster than a simple CLR.B / DBRA loop because MOVEM amortises
; the instruction fetch overhead across many stores.
;
; The technique works by pre-loading a0-a6 and d0-d6 with zero, then using
; MOVEM.L Rn,-(a0) (pre-decrement store) to write them all in one instruction.
; We clear the buffer backwards (from the end) so that a0 ends up pointing
; at the start - convenient for the caller.
;
; Arguments:
;   a0 = pointer to the START of the block to clear
;   d7 = number of BYTES to clear
;
; Destroys:  a0-a6, d0-d7  (all registers used)
; Note:  This routine is called with PUSHALL / POPALL in the callers that need
;        register preservation.  When called from Restart, all regs are scratch.
;
; Algorithm:
;   1. Advance a0 to point just PAST the end of the buffer:  a0 += d7
;   2. Divide d7 by 52 to get the number of full MOVEM blocks.
;      DIVU #52,d7  -> d7.lo = quotient (blocks), d7.hi = remainder (bytes)
;   3. If quotient > 0, clear it via the pre-decrement MOVEM loop.
;   4. The remainder (0..51 bytes) is extracted from d7.hi (SWAP) and cleared
;      one byte at a time with CLR.B / DBRA.
;
; Why 52 bytes per iteration?
;   MOVEM.L a1-a6/d0-d6,-(a0) stores 13 longwords = 52 bytes in one instruction.
;   a1,a2,a3,a4,a5,a6 = 6 address registers (all zeroed)
;   d0,d1,d2,d3,d4,d5,d6 = 7 data registers (all zeroed)
;   = 13 registers * 4 bytes = 52 bytes per MOVEM
;   (d7 cannot be included as it is the loop counter)
;   (a0 cannot be included as it is the destination pointer)
;==============================================================================

TurboClear:
    PUSHALL                        ; save all registers (a0-a6, d0-d7)

    add.l      d7,a0              ; advance a0 to one byte PAST the end of buffer

    divu       #52,d7             ; d7.lo = number of 52-byte blocks, d7.hi = remainder
    subq.w     #1,d7              ; adjust for DBRA  (DBRA loops until -1, not 0)
    bmi        .remain            ; skip main loop if fewer than 52 bytes total

    ; Zero all the registers we will store (d7 already the loop counter)
    sub.l      a1,a1              ; a1 = 0
    sub.l      a2,a2              ; a2 = 0
    sub.l      a3,a3              ; a3 = 0
    sub.l      a4,a4              ; a4 = 0
    sub.l      a5,a5              ; a5 = 0
    sub.l      a6,a6              ; a6 = 0
    moveq      #0,d0              ; d0 = 0
    moveq      #0,d1              ; d1 = 0
    moveq      #0,d2              ; d2 = 0
    moveq      #0,d3              ; d3 = 0
    moveq      #0,d4              ; d4 = 0
    moveq      #0,d5              ; d5 = 0
    moveq      #0,d6              ; d6 = 0

.loop1
    movem.l    a1-a6/d0-d6,-(a0) ; store 13 zero longs (52 bytes) pre-decrement
    dbra       d7,.loop1          ; repeat for each full block

.remain
    ; Handle the remainder bytes (0..51) stored in the HIGH word of d7.
    ; After DIVU, d7 = { remainder[15:0], quotient[15:0] }.
    ; CLR.W d7 zeroes the quotient word, leaving remainder in the high word.
    ; SWAP d7 puts the remainder in the low word for DBRA.
    clr.w      d7                 ; zero the quotient word (low word after DIVU)
    swap       d7                 ; bring remainder to low word
    subq.w     #1,d7              ; adjust for DBRA
    bcs        .done              ; no remainder bytes, we are finished

.loop2
    clr.b      -(a0)              ; clear one byte (pre-decrement from end of buffer)
    dbra       d7,.loop2          ; repeat for each remainder byte

.done
    POPALL                        ; restore all registers
    rts
