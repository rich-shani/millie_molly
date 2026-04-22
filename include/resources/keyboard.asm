
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; keyboard.asm  -  CIA-A Keyboard Interrupt Handler
;==============================================================================
;
; The Amiga keyboard controller communicates with the computer via a serial
; protocol through CIA-A (Complex Interface Adapter at $BFE001).  Each key
; press or release generates an 8-bit scan-code sent serially on the SP (Serial
; Port) pin of CIA-A.
;
; Hardware flow:
;   1. Keyboard controller pulls SP line low (start bit).
;   2. 8 data bits are clocked in, MSB first, via the CIA-A SDR (Serial Data
;      Register, ciaSDR / CIASDR).
;   3. CIA-A sets the SP interrupt flag (CIAICRB_SP) in CIAICR.
;   4. This triggers a level-2 interrupt through CIA-A -> INT2 -> ports interrupt
;      ($68 = level 2 interrupt vector).  INTENA bit INTF_PORTS must be set.
;   5. The handler reads the scan-code, bit-inverts and rotates it to get the
;      standard Amiga key-code, stores it in the Keys[] buffer, then handshakes
;      by briefly setting CIA-A control register to output mode and back.
;
; The Keys[] buffer is 256 bytes (one byte per possible key-code).
; A non-zero byte means that key is currently pressed.
; The keyboard interrupt sets Keys[code] = $ff (key down) or $00 (key up)
; based on bit 7 of the received byte (0=make/press, 1=break/release).
;
; StoreKeyboard holds the previous $68 vector so it can be restored on exit.
;
;==============================================================================
    incdir  "include"
    include    "hardware/cia.i"     ; CIA register offsets and bit definitions


;==============================================================================
; KeyboardInit  -  Install the keyboard interrupt handler
;
; Sets up the CIA-A serial interrupt and installs KeyboardInterrupt at vector $68
; (the level-2 "ports" interrupt on the Amiga).
;
; Before installing, it:
;   - Saves the current $68 vector in StoreKeyboard
;   - Clears any pending CIA-A interrupt by reading CIAICR
;   - Sets CIA-A to serial INPUT mode (CIACRAF_SPMODE = 0 in CIACRA)
;   - Clears any pending PORTS interrupt in INTREQ
;   - Enables the PORTS interrupt in INTENA
;
; Note: Uses absolute zero-page addressing (sub.l a0,a0 ; use 0-based vector table).
; On a standard Amiga with no MMU, the vector table is at physical address $0.
; The TODO comment indicates that a real implementation should read the vector
; base register (VBR, 68010+) via the Exec system_variables structure.
;
; Preserves all registers.
;==============================================================================

KeyboardInit:
    movem.l    d0-a6,-(a7)            ; save all regs (called from Init, must be clean)

    ; TODO: Use VBR / Exec sys_vectorbase for 68010+ compatibility
    sub.l      a0,a0                  ; a0 = address 0 (vector base on 68000)

    move.l     $68(a0),StoreKeyboard  ; save current level-2 vector for later restore

    ; Enable CIA-A serial-port interrupt so we get a signal on each key event.
    ; CIAICRF_SETCLR = bit 7 = 1 (set mode).  CIAICRF_SP = bit 3 (serial port).
    ; Writing this to CIAICR enables the SP interrupt source.
    move.b     #CIAICRF_SETCLR|CIAICRF_SP,(ciaicr+$bfe001)

    tst.b      (ciaicr+$bfe001)       ; dummy read to acknowledge/clear any pending interrupt

    ; Set CIA-A serial port to INPUT mode (receive keyboard data).
    ; CIACRAF_SPMODE = bit 6 of CIACRA.  Clear it for input.
    and.b      #~(CIACRAF_SPMODE),(ciacra+$bfe001)

    ; Clear any stale PORTS interrupt request in the custom chip.
    move.w     #INTF_PORTS,(intreq+$dff000)

    ; Install our handler and enable the PORTS interrupt channel.
    move.l     #KeyboardInterrupt,$68(a0)
    move.w     #INTF_SETCLR|INTF_INTEN|INTF_PORTS,(intena+$dff000)

    movem.l    (a7)+,d0-a6
    rts


;==============================================================================
; KeyboardRemove  -  Uninstall the keyboard interrupt handler
;
; Restores the previously saved level-2 interrupt vector and leaves the
; CIA-A serial interrupt enabled (the restored handler will deal with it).
;
; Preserves all registers.
;==============================================================================

KeyboardRemove:
    movem.l    d0-a6,-(a7)

    ; TODO: Use VBR / Exec sys_vectorbase for 68010+ compatibility
    sub.l      a0,a0                  ; a0 = vector base (address 0)

    ; Re-enable PORTS interrupt (just in case it was masked)
    move.w     #INTF_SETCLR|INTF_PORTS,(intena+$dff000)

    ; Restore the original vector
    move.l     StoreKeyboard,$68(a0)

    movem.l    (a7)+,d0-a6
    rts


;==============================================================================
; KeyboardInterrupt  -  Level-2 CIA-A keyboard interrupt service routine
;
; Fires on every key press or release.  Reads the raw scan-code from CIA-A,
; converts it to the standard Amiga key-code format, and stores it in Keys[].
;
; The raw byte received from the keyboard controller is:
;   bits 7:1 = scan-code (7 bits, MSB first)
;   bit  0   = make/break  (0 = key pressed, 1 = key released)
; The entire byte is transmitted with all bits inverted (active-low protocol).
;
; Conversion:
;   1. Read SDR (serial data register) - gives inverted bits, LSB first.
;   2. NOT d0  - un-invert all bits.
;   3. ROR.B #1  - rotate right 1 to move the make/break bit into bit 7,
;                  and shift the 7-bit scan-code into bits 6:0.
;   4. SPL d1  - d1 = $ff if result was positive (bit 7 = 0 = key down),
;                d1 = $00 if result was negative  (bit 7 = 1 = key up).
;   5. AND #$7f  - mask off the make/break bit to get clean 7-bit code.
;   6. Keys[code] = d1  (non-zero for pressed, zero for released).
;
; After reading, the handler must perform a hardware handshake to tell the
; keyboard controller it can send the next code.  This is done by briefly
; setting the CIA-A serial port to OUTPUT mode (3 raster-line delay) then
; back to INPUT mode.
;
; Finally, the PORTS interrupt is cleared in INTREQ and the chain patch
; location is NOPped (KeyboardPatchPtr can be modified to chain to another
; handler if needed).
;
; Preserves: d0-d1, a0-a2  (saved on stack).
;==============================================================================

KeyboardInterrupt:
    movem.l    d0-d1/a0-a2,-(a7)     ; save working registers

    ; --- Check that this is really a CIA-A SP interrupt, not another level-2 source ---
    lea        $dff000,a0             ; custom chip base
    move.w     intreqr(a0),d0         ; read interrupt request flags
    btst       #INTB_PORTS,d0         ; is the PORTS bit set?
    beq        .end                   ; no - not our interrupt, exit cleanly

    lea        $bfe001,a1             ; CIA-A base (note: CIA-A = $BFE001, registers at +n)
    btst       #CIAICRB_SP,ciaicr(a1) ; is the serial port interrupt pending?
    beq        .end                   ; no - spurious, exit

    ; --- Read and decode the scan-code ---
    move.b     ciasdr(a1),d0          ; read raw serial data byte from CIA-A SDR

    ; Tell CIA-A to handshake: switch to output mode momentarily
    or.b       #CIACRAF_SPMODE,ciacra(a1)  ; set SP to output (handshake signal to keyboard)

    not.b      d0                     ; invert all bits (protocol is active-low)
    ror.b      #1,d0                  ; rotate: make/break -> bit 7, scan-code -> bits 6:0

    spl        d1                     ; d1 = $ff if key DOWN (bit 7 was 0), $00 if key UP
    and.w      #$7f,d0                ; mask to 7-bit scan-code (clears break bit)

    lea        Keys,a2                ; base of the 256-byte key state buffer
    move.b     d1,(a2,d0.w)           ; Keys[scan_code] = $ff (pressed) or $00 (released)

    ; --- Hardware handshake: wait ~3 raster lines then release ---
    ; The keyboard controller needs to see the SP line held low for at least
    ; 75 microseconds before it will accept the next key-code.
    ; We spin for 3 raster-line changes (each line = ~64 us at PAL timing).
    moveq      #3-1,d1                ; loop 3 times
.wait1
    move.b     vhposr(a0),d0          ; read current raster position (V/H low byte)
.wait2
    cmp.b      vhposr(a0),d0          ; wait until raster position changes (one line passed)
    beq        .wait2
    dbf        d1,.wait1

    ; Release handshake: set CIA-A back to input mode
    and.b      #~(CIACRAF_SPMODE),ciacra(a1)  ; clear SPMODE -> serial input again

.end
    ; Clear the PORTS interrupt request flag in the custom chip
    move.w     #INTF_PORTS,intreq(a0)
    tst.w      intreqr(a0)            ; dummy read to ensure write has propagated (bus timing)

    ; KeyboardPatchPtr: three NOPs that can be overwritten at runtime to chain
    ; this interrupt handler to another level-2 handler if required.
KeyboardPatchPtr:
    nop
    nop
    nop

    movem.l    (a7)+,d0-d1/a0-a2
    rte                                ; return from interrupt


;==============================================================================
; StoreKeyboard  -  Storage for the previous level-2 interrupt vector
;
; Initialised to 0.  Written by KeyboardInit, read back by KeyboardRemove.
;==============================================================================

StoreKeyboard:
    dc.l       0
