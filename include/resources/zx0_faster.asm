
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; zx0_faster.asm  -  ZX0 Decompressor for 68000
;==============================================================================
;
;  unzx0_68000.s
;
;  Adapted by platon42: modified to NOT preserve registers and to avoid
;  longword operations for block lengths > 64KB (unsupported).
;  get_elias inlined for speed.  Additional micro-optimisations applied.
;
;  Original algorithm: ZX0 (c) 2021 Einar Saukas
;    https://github.com/einar-saukas/ZX0
;
;  Decompressor: Copyright (C) 2021 Emmanuel Marty
;                Copyright (C) 2023 Emmanuel Marty, Chris Hodges
;
;  Licence: zlib (use freely, credit appreciated, do not misrepresent origin)
;
;------------------------------------------------------------------------------
; ZX0 is a lossless byte-stream compressor that produces an optimal compressed
; format for decompression on simple CPUs.  The compressed stream interleaves:
;   - Literal runs    (raw bytes copied directly from the stream)
;   - Backreferences  (copy a sequence from already-decompressed output)
;   - Repeated matches (reuse the last match offset)
;
; Lengths and offsets are encoded using Elias gamma coding:
;   Elias gamma: a sequence of (N-1) zero bits followed by 1, followed by
;   (N-1) data bits.  This encodes positive integers efficiently with a
;   bias toward small values.
;
; The bit queue:
;   Compressed stream bits are consumed MSB-first from a byte queue held in d1.
;   When d1 is exhausted (ADD.B d1,d1 produces carry=0 and d1=0), a new byte
;   is loaded from (a0)+ and shifted in.  The sentinel value $80 in d1.hi
;   means one bit remains (the 1 from the sentinel itself).
;   Initialised to -128 ($80 in the byte = $ffffff80 as .l, but used as .b):
;   moveq.l #-128,d1  sets d1 = $ffffff80; the first ADD.B d1,d1 shifts out
;   the sentinel and immediately triggers a reload.
;
; Register usage:
;   a0 = read pointer  (compressed input)
;   a1 = write pointer (decompressed output)
;   a2 = scratch for backreference source address
;   d0 = Elias gamma accumulator / length / high-byte of offset
;   d1 = bit queue byte (signed, tested with ADD.B to shift bits into carry)
;   d2 = current match offset (negative value used for backreference)
;
; On entry:
;   a0 = start of compressed data  (Fast RAM or Chip RAM)
;   a1 = start of decompression buffer  (must be in Chip RAM for game use)
;
; On exit:
;   a0 = byte after the last compressed byte read
;   a1 = byte after the last decompressed byte written
;
; Trashes: d0-d2, a2
;==============================================================================

zx0_decompress:
        moveq.l #-128,d1        ; init bit queue: $80 sentinel means "fetch immediately"
                                ; first ADD.B d1,d1 will overflow -> load first byte
        moveq.l #-1,d2          ; init repeat-offset to -1 (1 byte back, i.e. last written)
        bra.s   .literals       ; jump into the literal-copy path (first block is always literals)


;------------------------------------------------------------------------------
; Short-path: copy exactly 2 bytes from the current backreference offset.
; Entered from .get_offset when the length bit embedded in the offset byte is 1.
; d2 = negative match offset (calculated in .get_offset below).
;------------------------------------------------------------------------------
.do_copy_offs2
        move.b  (a1,d2.l),(a1)+        ; copy byte 0 from (dest + offset)
        move.b  (a1,d2.l),(a1)+        ; copy byte 1

        add.b   d1,d1                   ; read next control bit (literal or match?)
        bcs.s   .get_offset             ; 1 -> read a new match offset
        ; fall through to .literals (0 -> copy more literals)


;==============================================================================
; LITERALS BLOCK
; Read an Elias-gamma encoded count, then copy that many raw bytes from input.
;==============================================================================
.literals
        ; Decode the literal count using Elias gamma.
        ; The value starts at 1; each "0" control bit doubles-and-shifts a data bit in.
        moveq.l #1,d0                   ; initialise count accumulator to 1
.elias_loop1
        add.b   d1,d1                   ; shift bit queue; MSB into carry
        bne.s   .got_bit1               ; queue not empty (result non-zero) -> got a bit
        move.b  (a0)+,d1                ; queue empty: load 8 new bits
        addx.b  d1,d1                   ; shift queue AND shift in carry (the 1 sentinel)
.got_bit1
        bcs.s   .got_elias1             ; control bit = 1 -> Elias gamma complete
        add.b   d1,d1                   ; read next data bit (shift queue)
        addx.w  d0,d0                   ; shift data bit into count accumulator
        bra.s   .elias_loop1            ; loop for more Elias bits

.got_elias1
        ; d0 = literal count.  Adjust for DBRA which loops until -1.
        subq.w  #1,d0
.copy_lits
        move.b  (a0)+,(a1)+             ; copy one literal byte from input to output
        dbra    d0,.copy_lits           ; loop for all literal bytes

        ; After literals: read control bit to decide next action.
        add.b   d1,d1                   ; read control bit
        bcs.s   .get_offset             ; 1 -> read a new match offset
        ; 0 -> fall through to .rep_match (reuse last offset)


;==============================================================================
; REPEATED MATCH (REP-MATCH)
; Reuse the last match offset (d2) without reading a new one.
; Read the match length via Elias gamma, then copy.
;==============================================================================
.rep_match
        moveq.l #1,d0                   ; init length accumulator
.elias_loop2
        add.b   d1,d1                   ; shift bit queue
        bne.s   .got_bit2               ; queue not empty
        move.b  (a0)+,d1                ; reload queue
        addx.b  d1,d1
.got_bit2
        bcs.s   .got_elias2             ; control bit = 1 -> done
        add.b   d1,d1                   ; read data bit
        addx.w  d0,d0                   ; accumulate
        bra.s   .elias_loop2

.got_elias2
        subq.w  #1,d0                   ; adjust for DBRA
.do_copy_offs
        move.l  a1,a2                   ; a2 = dest + negative_offset = source address
        add.l   d2,a2                   ; (d2 is negative, so this subtracts)
.copy_match
        move.b  (a2)+,(a1)+             ; copy matched byte from history to output
        dbra    d0,.copy_match          ; loop for match length bytes

        add.b   d1,d1                   ; read next control bit (literal or match?)
        bcc.s   .literals               ; 0 -> go copy more literals
        ; 1 -> fall through to .get_offset (read a new offset)


;==============================================================================
; NEW MATCH OFFSET
; Read the high byte of the match offset via Elias gamma (biased encoding),
; then read the low byte from the stream (which also embeds 1 bit of length).
;==============================================================================
.get_offset
        moveq.l #-2,d0                  ; init offset high byte accumulator to $fe
                                        ; (the encoding is biased: 0 -> EOD, 1 -> offset=1, etc.)

        ; Read the Elias-gamma-encoded high byte of the offset.
.elias_loop3
        add.b   d1,d1                   ; shift bit queue
        bne.s   .got_bit3               ; queue not empty
        move.b  (a0)+,d1                ; reload queue
        addx.b  d1,d1
.got_bit3
        bcs.s   .got_elias3             ; control bit = 1 -> done
        add.b   d1,d1                   ; read data bit
        addx.w  d0,d0                   ; accumulate
        bra.s   .elias_loop3

.got_elias3
        addq.b  #1,d0                   ; un-bias: $fe+1=$ff=-1, $fc+1=$fd, etc.
        beq.s   .done                   ; d0 = 0 after +1 means EOD marker ($ff -> $00) -> done

        ; Transfer the negative high byte via the stack (classic 68000 trick to
        ; set the high byte of a word without corrupting the low byte):
        move.b  d0,-(sp)                ; push high byte of negative offset
        move.w  (sp)+,d2                ; pop as word: d2 = { high_byte, garbage_low }
                                        ; (low byte is whatever was on stack - overwritten next)

        move.b  (a0)+,d2                ; read low byte of offset (plus 1 embedded length bit)
        asr.l   #1,d2                   ; arithmetic right shift: length bit -> carry, offset >>1
                                        ; d2 is now the final signed negative offset

        bcs.s   .do_copy_offs2          ; length bit was 1 -> match length = 2 (short path)

        ; Length bit was 0 -> read the actual match length via Elias gamma.
        moveq.l #1,d0                   ; init length accumulator
        add.b   d1,d1                   ; read first data bit of Elias gamma length
        addx.w  d0,d0                   ; shift into accumulator

.elias_loop4
        add.b   d1,d1                   ; shift bit queue
        bne.s   .got_bit4               ; queue not empty
        move.b  (a0)+,d1                ; reload queue
        addx.b  d1,d1
.got_bit4
        bcs.s   .do_copy_offs           ; control bit = 1 -> length complete, go copy
        add.b   d1,d1                   ; read data bit
        addx.w  d0,d0                   ; accumulate length
        bra.s   .elias_loop4            ; loop

.done
        rts                             ; decompression complete; a0 and a1 point past output
