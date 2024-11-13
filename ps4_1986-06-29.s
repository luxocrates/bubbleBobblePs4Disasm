;
; Annotated disassembly of Bubble Bobble's PS4 chip
;
; The latest version of this document can be found at:
;     https://github.com/luxocrates/bubbleBobblePs4Disasm
;
; The PS4 (labeled JPH1011P, but referred to throughout official sources as PS4)
; is a 6801U4 microcontroller which serves as a security device for Bubble Bobble,
; without which the game is unplayable.
;
; This document is a disassembly of its mask ROM, with an attempt at interpreting
; its routines. The binary file it's based on was named `a78-01.17`, with md5sum
; `7408cf481379cc8ce08177a17e83071e`.
;
; TL;DR: PS4 roles include:
;   - interfacing with player controls, DIP switches, the coin mechanisms and
;     cabinet switches, and relaying their values to the main CPU
;   - informing the beasties of where the players are
;   - rotating which EXTEND bubbles the players are given
;   - effecting functionality for the clock special item
;   - generating interrupts on the main CPU
;
; Suffice it to say, one does not _need_ a microcontroller to do any of the
; above. The PS4's real purpose is to move some vital functionality behind an
; opaque curtain. However, it seems obvious from the code that Taito had
; intended for more functionality to be on the PS4 than just the above.
; Specifically, we see routines and data hookups for:
;
;   - performing collision detection between players and level beasties
;     (not Skel Monsta/Baron von Blubba)
;   - controlling the speed of the wind simulation
;   - owning the credits count
;
; ...where the calculations are performed on the PS4, but their results ignored
; by the main CPU. In the case of the beastie collision detection, there's a
; clear showstopper bug preventing its use. For the others, less so. There are
; additional functions whose mechanics seem arbitrary enough to be unguessable,
; and which don't seem to get triggered by in-game actions, so we may never
; know what the intention was.
; 
;
;
; The 6801U4 is a microcontroller variant of the 6800 microprocessor, with 4KiB
; of mask ROM and 192 bytes of RAM. If you're not familiar with 6800/6801
; assembly (I wasn't), be aware that:
;
; - Registers A and B can be used together as a 16-bit pair, called D.
; - Like 68k, immediate addressing is denoted with '#', and absolute addressing
;   has no denotation at all. It's very easy to see an instruction like
;   `ora $47` and think it's ORing with a constant, when in fact the argument is
;   being read from memory.
; - The 6801U4 has extra opcodes that you won't find on the regular 6800.
;
;
; I/O port map
; =============
;
; Port 1: bit 0:    TILT input
;         bit 1:    SERVICE input
;         bit 2:    COIN A input
;         bit 3:    COIN B input
;         bit 4:    OUT output
;         bit 5:    1/2 WAY output
;         bit 6:    Raise main CPU interrupt
;         bit 7:    Goes to IC12 PAL as P-CPU bus access type (0 = write, 1 = read)
; Port 2: bits 0-4: P-CPU address bus, bits 8-11
;         bit 5:    Signals to IC12 PAL that PS4 is requesting shared RAM access
; Port 3: bits 0-7: P-CPU data bus, bits 0-7
; Port 4: bits 0-7: P-CPU address bus, bits 0-7
;
;
; P-CPU bus memory layout
; =======================
;
; The P-CPU data/address buses connect the PS4 to shared RAM at IC16, and to some
; I/O inputs. As a convention in this document, P-CPU addresses will be denoted
; as, eg. [$c00]. The mapping is:
;
;   P-CPU addr      Main CPU addr   Device
;   -----------------------------------------------------
;   [$000]-[$003]   (unmapped*)     Inputs (DIPs, player controls)
;   [$c00]-[$fff]   $fc00 - $ffff   Shared RAM $000-$3ff (IC16, a 2016-100)
;
;   (* TODO - check this)
;
; For the memory layout below, r/w/rw are from the perspective of the PS4
;
; -- Input ports ---------------------------------------------------------------
;
; [$000](r)  - Player controls/DIPs 0
; [$001](r)  - Player controls/DIPs 1
; [$002](r)  - Player controls/DIPs 2
; [$003](r)  - Player controls/DIPs 3
;
; -- Beastie input structure ---------------------------------------------------
;
; [$c01](r)  - Beastie 1 life stage
;                $00 = gone
;                $01 = roaming (angry doesn't get its own value)
;                $08 = showing as a bonus item or points value only
;                $40 = popped
;                $80 = bubbled
; [$c02](r)  - Beastie 1 Y position
; [$c03](r)  - Beastie 1 X position
; [$c04](r)  - Beastie 1 bonus item has been collected ($00 or $01) (not read by PS4)
;
; [$c05]-[$c08] - Beastie 2 equivalents of [$c01]-[$c04]
; [$c09]-[$c0c] - Beastie 3 equivalents of [$c01]-[$c04]
; [$c0d]-[$c10] - Beastie 4 equivalents of [$c01]-[$c04]
; [$c11]-[$c14] - Beastie 5 equivalents of [$c01]-[$c04]
; [$c15]-[$c18] - Beastie 6 equivalents of [$c01]-[$c04]
; [$c19]-[$c1c] - Beastie 7 equivalents of [$c01]-[$c04]
;
; ------------------------------------------------------------------------------
;
; [$c1e](rw) - Phony credits count
;
; It seems likely that this value was intended to be the authoritative credits
; count, but got deprecated, with vestiges of it remaining.
;
; The main CPU tracks the credits count itself, using only the relay of port 1
; at [$c1f] to increment it. After incrementing, however, it does update the
; the shared value at [$c1e], but it's not clear why: this seems to be the
; only time the CPU updates the value -- it doesn't decrement it on game start.
; Separately, the main CPU communicates to the PS4 using [$f94] whether the
; coin lockouts should be enabled or not.
;
; -- Relayed input ports -------------------------------------------------------
;
; [$c1f](w)  - Relay of Port 1 (see I/O port map)
; [$c20](w)  - Relay of [$000]
; [$c21](w)  - Relay of [$001]
; [$c22](w)  - Relay of [$002]
; [$c23](w)  - Relay of [$003]
;
; ------------------------------------------------------------------------------
;
; [$c24](rw) - Unknown (routine at $f2a7), parallel of [$c25]
; [$c25](rw) - Unknown (routine at $f347), parallel of [$c24]
; [$c26](rw) - Seems unused (an output for [$c7e] processor)
;
; -- Beastie output structure --------------------------------------------------
;
; [$c27](w)  - Vertical qualitative comparison for player 1 wrt. beastie 1
;                $00 = player is above
;                $01 = is below
;                $80 = is vertically centered with
; [$c28](w)  - (as above, but for player 2)
; [$c29](w)  - Horizontal qualitative comparison for player 1 wrt. beastie 1
;                $00 = player is right of
;                $01 = is left of
;                $80 = is horizontally centered with
; [$c2a](w)  - (as above, but for player 2)
; [$c2b](w)  - absolute vertical distance between beastie 1 and player 1
; [$c2c](w)  - (as above, but for player 2)
; [$c2d](w)  - absolute horizontal distance between beastie 1 and player 1
; [$c2e](w)  - (as above, but for player 2)
;
; [$c2f]-[$c36] - Beastie 2 equivalents of [$c27]-[$c2e]
; [$c37]-[$c3e] - Beastie 3 equivalents of [$c27]-[$c2e]
; [$c3f]-[$346] - Beastie 4 equivalents of [$c27]-[$c2e]
; [$c47]-[$34e] - Beastie 5 equivalents of [$c27]-[$c2e]
; [$c4f]-[$c56] - Beastie 6 equivalents of [$c27]-[$c2e]
; [$c57]-[$c5e] - Beastie 7 equivalents of [$c27]-[$c2e]
;
; -- Player structure ----------------------------------------------------------
;
; [$c5f](r)  - Player 1 phony liveness (bit 0)
;              Most likely intended as a way for the CPU to tell the PS4 that
;              player 1 is alive, but effectively unused. Gets set to $01 at
;              start of gameplay, and the PS4 won't do processing for beasties
;              unless it is $01, but nothing ever seems to reset it to zero.
; [$c60](r)  - Player 1 Y position
; [$c61](r)  - Player 1 X position
; [$c62](w)  - Player 1 phony kill switch
;              Most likely intended as a way for the PS4 to tell the CPU to kill
;              off player 1, but collision detection code was botched, so the
;              CPU seems to disregard this value. Likely, this is why [$c5f]
;              isn't really used.
; [$c63](w) -  Index of beastie that the bugged collision detector thinks
;              collided with the player
;
; [$c67]-[$c6b] - Player 2 equivalents of [$c5f]-[$c63]
;
; ------------------------------------------------------------------------------
;
; [$c6f](rw) - Unknown (routine at $f2a7) (always reports 0 in my experience)
; [$c70](rw) - Parallel to [$c6f] (routine at $f347)
; [$c71](r)  - Unknown (routine at $f8d5) (credits prank?)
;
; -- Creepers (see PROCESS_CREEPER_C76) ----------------------------------------
;
; [$c72](r)  - Seems unused (feeds creeper for [$c73])
; [$c73](w)  - Seems unused (fed from creeper for [$c72])
; [$c74](r)  - Seems unused (feeds creeper for [$c75])
; [$c75](w)  - Seems unused (fed from creeper for [$c74])
; [$c76](r)  - Wind speed   (feeds creeper for [$c77])
; [$c77](w)  - Seems unused (fed from creeper for [$c76])
;
; -- Clock ---------------------------------------------------------------------
;
; [$c78](rw) - Clock downcounter low byte
; [$c79](rw) - Clock downcounter high byte
; [$c7a](rw) - Clock is active (if not $00)
; [$c7b](w)  - Clock countdown complete, if PS4 writes $01
;
; ------------------------------------------------------------------------------
; [$c7c](rw) - Which EXTEND bubble the player would be offered if one appeared
;              right now
; [$c7d](w)  - I/O error reporting. PS4 writes $01 on error.
; [$c7e](rw) - Seems unused (causes writes to itself, [$c26] and $0054)
; [$c7f](r)  - Seems unused (input for dead code at $f216-$f235)
; [$c80](r)  - Unknown (routine at $f6f1)
; [$c81](w)  - Unknown (routine at $f6f1)
; [$c82](w)  - PS4 checksum high byte (game will report error if nonzero)
; [$c83](w)  - PS4 checksum low byte  (game will report error if nonzero)
; [$c85](w)  - PS4 ready reporting. Main CPU waits for PS4 to write $37 here.
;
; -- Translators (see PROCESS_TRANSLATOR_F88) ----------------------------------
;
; Theoretically, translators could target any other variables in the range
; [$c88]-[$f87], but in practice are unused.
;
; [$f88](rw) - status            for translator at $f903
; [$f89](r)  - index ptr         for translator at $f903
; [$f8a](r)  - table ptr         for translator at $f903
; [$f8b](r)  - output offset ptr for translator at $f903
;
; [$f8c](rw) - status            for translator at $f93d
; [$f8d](r)  - index ptr         for translator at $f93d
; [$f8e](r)  - table ptr         for translator at $f93d
; [$f8f](r)  - output offset ptr for translator at $f93d
;
; [$f90](rw) - status            for translator at $f977
; [$f91](r)  - index ptr         for translator at $f977
; [$f92](r)  - table ptr         for translator at $f977
; [$f93](r)  - output offset ptr for translator at $f977
;
; ------------------------------------------------------------------------------
;
; [$f94](r)  - Should coin lockouts accept more coins?
;                $01 - stop accepting
;                $ff - start accepting
;                otherwise, do not change
; [$f95](r)  - Unknown (routines at $f2a7, $f347, $f3e3)
; [$f96](r)  - Delay after interrupt handler, if $47
; [$f97](r)  - Reboot PS4, if $4a
; [$f98](r)  - Main CPU is ready, if $47
; [$f99](w)  - Phony credit event: PS4 writes $01 here on credit bump, but main
;              CPU doesn't read it
;
;
; Memory map
; ==========
;
; 6801U4 Internal memory-mapped registers
; ---------------------------------------
; For more information on the 6801U4, see Motorola's manual:
; DL139, "Microprocessor, Microcontroller, and Peripheral Data", Volume 1
;
; (From Table 4 on page 3-147)
;
; $0000: Port 1 data direction register
; $0001: Port 2 data direction register
; $0002: Port 1 data register
; $0003: Port 2 data register
;
; $0004: Port 3 data direction register
; $0005: Port 4 data direction register
; $0006: Port 3 data register
; $0007: Port 4 data register
;
; $0008: Timer control and status register
; $0009: Counter (high byte)
; $000a: Counter (low byte)
; $000b: Output compare register (high byte)
;
; $000c: Output compare register (low byte)
; $000d: Input capture register (high byte)
; $000e: Input capture register (low byte)
; $000f: Port 3 control and status register
;
; $0010: Rate and mode control register
; $0011: Transmit/receive control and status register
; $0012: Receive data register
; $0013: Transmit data register
;
; $0014: RAM control register
; $0015: Counter alternate address (high byte)
; $0016: Counter alternate address (low byte)
; $0017: Timer control register 1
;
; $0018: Timer control register 2
; $0019: Timer status register
; $001a: Output compare register 2 (high byte)
; $001b: Output compare register 2 (low byte)
;
; $001c: Output compare register 3 (high byte)
; $001d: Output compare register 3 (low byte)
; $001e: Input capture register 2 (high byte)
; $001f: Input capture register 2 (low byte)
;
; 
; RAM
; ---
; $0040:         Last frame's port 1 data, shifted left 4 bits
; $0041:         How COIN B has changed since last frame
; $0042:         Last frame's port 1 data, shifted left 5 bits
; $0043:         How COIN A has changed since last frame
; $0044:         Last frame's port 1 data, shifted left 6 bits
; $0045:         How SERVICE has changed since last frame
; $0046:         Temporary storage for TRACK_MSB_CHANGE
; $0048:         Phony unactioned coins count
;                (An unactioned coin is where the game pricing would be, say,
;                2-coins-1-credit: after receiving the first coin, this is the
;                counter we bump). But the whole credits count is phony: the
;                main CPU doesn't use any of it.
; $004a, $004b:  Scratch (last shared RAM address read from or written to.)
; 0004c, $004d:  (Used only by dead code at $f216-$f235)
; $004e:         Cached controls/DIPs byte 0
; $004f:         Cached controls/DIPs byte 1 (but never retrieved)
; $0050:         Cached controls/DIPs byte 2 (but never retrieved)
; $0051:         Cached controls/DIPs byte 3 (but never retrieved)
; $0052:         Unknown, see $f2e7 et al
; $0053:         Parallel of $0052
; $0054:         Unknown (credits related?)
; $0055:         Cached player Y position
; $0056:         Cached player X position
; $0057:         Number of beastie currently being processed
; $0058, $0059:  Input structure pointer for current beastie
; $005a, $005b:  Output structure pointer for current beastie
; $005c:         Beastie Y overlap accumulator
; $005d:         Sequence index for the [$c72]->[$c73] creeper
; $005e:         Sequence index for the [$c74]->[$c75] creeper
; $005f:         Sequence index for the [$c76]->[$c77] creeper
; $0060:         Sequence index for the [$c80]->[$c81] creeper
;
;
; Handy reference for MAME debugging
; ==================================
;
; To set [$c10] to $3f:                      fill fc10,1,3f
;
; To trap the main CPU writing to [$c7e]:    wpset fc7e,1,w
; To trap the main CPU reading from [$c26]:  wpset fc26,1,r
;
; To trap the PS4 writing to $0054:          wpset 0054:mcu,1,w
; To trap the PS4 executing $f070:           bpset f070:mcu
; To trap* the PS4 reading from [$c7c]:      bpset f1bf:mcu,x==c7c
; To trap* the PS4 reading $05 from [$c7c]:  bpset f1da:mcu,x==c7c && b==05
; To trap* the PS4 writing to [$f99]:        bpset f1db:mcu,x==f99
; To trap* the PS4 writing $7c to [$f99]:    bpset f1db:mcu,x==f99 && b==7c
;
; *: the PS4 doesn't directly wire to shared RAM, so we can't trap accesses
; using basic debugger functionality. As a workaround, we can put a breakpoint
; on the two functions that interface with it, and set a condition on the target
; address. This will leave the PS4's PC at the interfacing code, and the
; instruction that initiated it on the top of the stack. Use the `out` debugger
; command to advance execution back to the routine that initiated it.
;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Code!

; Cold start entrypoint
F000: 7E FE BB jmp  $FEBB                    ; Jump to CONFIGURE_MCU
F003: 8E 00 FF lds  #$00FF                   ; Set stack pointer (already done)
F006: 0F       sei                           ; Disable interrupts (already done)
F007: 86 F0    lda  #$F0
F009: 97 00    sta  $00                      ; Set port 1 data direction register
F00B: 86 FF    lda  #$FF
F00D: 97 01    sta  $01                      ; Set port 2 data direction register
F00F: 97 04    sta  $04                      ; Set port 3 data direction register
F011: 97 05    sta  $05                      ; Set port 4 data direction register
F013: 86 BF    lda  #$BF                     ; Store $bf..
F015: 97 0F    sta  $0F                      ; ..into port 3 control and status register
F017: 7F 00 08 clr  $0008                    ; Clear timer control and status register
F01A: 7F 00 17 clr  $0017                    ; Clear timer control register 1
F01D: 7F 00 18 clr  $0018                    ; Clear timer control register 2
F020: 7F 00 11 clr  $0011                    ; Clear transmit/receive control and status register

; Initialize RAM (all 192 bytes of it!)
F023: CE 00 40 ldx  #$0040                   ; Point X to RAM base (device registers come before)
F026: C6 C0    ldb  #$C0                     ; Loop counter: 192
F028: 6F 00    clr  $00,x                    ; Empty byte
F02A: 08       inx                           ; Increment pointer
F02B: 5A       decb                          ; Decrement loop counter
F02C: 26 FA    bne  $F028                    ; Loop

; Final port configuration and self-test
F02E: BD F2 36 jsr  $F236                    ; Call RELAY_PORTS
F031: BD F1 8F jsr  $F18F                    ; Call SET_OUT_AND_12WAY
F034: BD F1 96 jsr  $F196                    ; Call TEST_FOR_STUCK_COINS
F037: BD F2 7A jsr  $F27A                    ; Call CHECKSUM
F03A: C6 37    ldb  #$37                     ; Store magic number..
F03C: CE 0C 85 ldx  #$0C85                   ; ..into [$c85] to report that PS4 has booted
F03F: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F042: 0E       cli                           ; Enable interrupts

;
; IDLE:
;
; All of the PS4's post-setup functionality takes place in an interrupt handler.
; This is where it spins when the handler's done.
;
F043: 20 FE    bra  $F043                    ; Branch-to-self
F045: 01       nop  


;
; IRQ_HANDLER:
;
; The entrypoint for per-frame processing of basically everything the PS4 does
;

F046: BD F1 F8 jsr  $F1F8                    ; Call INTERRUPT_MAIN_CPU
F049: BD F2 36 jsr  $F236                    ; Call RELAY_PORTS
F04C: BD F0 92 jsr  $F092                    ; Call PROCESS_PHONY_CREDITS
F04F: BD F1 B0 jsr  $F1B0                    ; Call PROCESS_COIN_LOCKOUTS
F052: BD F2 A7 jsr  $F2A7                    ; Call PROCESS_C6F
F055: BD F3 47 jsr  $F347                    ; Call PROCESS_C70
F058: BD F3 E3 jsr  $F3E3                    ; Call PROCESS_C7E
F05B: BD F4 8F jsr  $F48F                    ; Call PROCESS_P1_BEASTIES
F05E: BD F5 85 jsr  $F585                    ; Call PROCESS_P2_BEASTIES
F061: BD F6 7F jsr  $F67F                    ; Call PROCESS_CREEPER_C72_C74
F064: BD F6 CB jsr  $F6CB                    ; Call PROCESS_CREEPER_C76
F067: BD F6 F1 jsr  $F6F1                    ; Call PROCESS_CREEPER_C80
F06A: BD F8 99 jsr  $F899                    ; Call PROCESS_CLOCK_ITEM
F06D: BD F8 D5 jsr  $F8D5                    ; Call PROCESS_CREDITS_MISCHIEF
F070: BD F8 F1 jsr  $F8F1                    ; Call PROCESS_EXTEND_ROTATION
F073: BD F9 03 jsr  $F903                    ; Call PROCESS_TRANSLATOR_F88
F076: BD F9 3D jsr  $F93D                    ; Call PROCESS_TRANSLATOR_F8C
F079: BD F9 77 jsr  $F977                    ; Call PROCESS_TRANSLATOR_F90
F07C: BD F2 99 jsr  $F299                    ; Call PROCESS_RESET_REQUEST

F07F: CE 0F 96 ldx  #$0F96                   ; Read [$f96]
F082: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F085: C1 47    cmpb #$47                     ; If $47..
F087: 27 08    beq  $F091                    ;      ..skip the cycle burn
F089: CC 01 70 ldd  #$0170                   ; Burn cycles: iterate through $170 (368) empty loops
F08C: 83 00 01 subd #$0001                   ; Decrement loop counter
F08F: 26 FB    bne  $F08C                    ; Loop
F091: 3B       rti                           ; Done: return to IDLE


;
; PROCESS_PHONY_CREDITS:
; (Called from IRQ_HANDLER, and the output compare interrupt vector, $fff4)
;
; This routine tries to track the credits count, but the main CPU ignores all of
; its output
;

; Check that the main CPU is ready for us (see also $f1f8)
;
F092: CE 0F 98 ldx  #$0F98                   ; [$f98] = is main CPU ready for us?
F095: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F098: C1 47    cmpb #$47                     ; Look for magic number
F09A: 27 01    beq  $F09D                    ; Process if found
F09C: 39       rts                           ; Return otherwise

; Isolate the credit-related inputs from port 1
;
F09D: CE 00 40 ldx  #$0040                   ; X = $0040, for upcoming subroutine
F0A0: 96 02    lda  $02                      ; Read port 1 (cabinet)
F0A2: 48       asla                          ; Rotate until inputs COIN B, ..
F0A3: 48       asla                          ; ..COIN A, SERVICE, TILT..
F0A4: 48       asla                          ; ..are in bits 7-4..
F0A5: 48       asla                          ; ..and bits 3-0 are empty
F0A6: C6 03    ldb  #$03                     ; Set loop counter to 3

; Iterate through the three bits that have COIN B, COIN A and SERVICE inputs.
; This will end up with locations $0041, $0043 and $0045 containing a byte which
; represents how the respective bit has changed since last frame.
;
F0A8: 36       psha                          ; Preserve regs..
F0A9: 37       pshb                          ; ..
F0AA: BD F1 6F jsr  $F16F                    ; Call TRACK_MSB_CHANGE
F0AD: 33       pulb                          ; Retrieve regs..
F0AE: 32       pula                          ; ..
F0AF: 48       asla                          ; Shift the next MSB into place
F0B0: 5A       decb                          ; Decrement remaining count
F0B1: 26 F5    bne  $F0A8                    ; Loop to next most significant bit

;
; COIN A handler
;

F0B3: B6 00 43 lda  $0043                    ; Fetch COIN A change code
F0B6: 81 00    cmpa #$00                     ; Falling edge?
F0B8: 26 39    bne  $F0F3                    ; If not, skip to COIN B handler

; COIN A has a new coin. Consult the coins/credits table.
;
F0BA: F6 00 4E ldb  $004E                    ; Retrieve cached DIPs
F0BD: 54       lsrb                          ; Shift right until..
F0BE: 54       lsrb                          ; A-5 and A-6.. (check this)
F0BF: 54       lsrb                          ; ..are in bits 1 and 2
F0C0: C4 06    andb #$06                     ; Mask out all other bits

; B is now a table offset. Table entries are two bytes each, which is why we
; shifted the switch bits to start at bit 1, not bit 0.
;
F0C2: CE F1 87 ldx  #$F187                   ; Point X to PHONY_COINS_PER_CREDIT_TABLE
F0C5: 3A       abx                           ; Add the offset
F0C6: A6 00    lda  $00,x                    ; Load the coins value from the table
F0C8: 81 01    cmpa #$01                     ; A one-coin entry?
F0CA: 27 0D    beq  $F0D9                    ; If so, skip to $f0d9

; (Multiple) coins, (some number of) credits
;
F0CC: 7C 00 48 inc  $0048                    ; Bump the phony unactioned coins count
F0CF: A6 00    lda  $00,x                    ; Refetch the coins value table entry (unnecessary)
F0D1: B1 00 48 cmpa $0048                    ; Have we received enough coins?
F0D4: 26 1D    bne  $F0F3                    ; If not, skip to part 2
F0D6: 7F 00 48 clr  $0048                    ; If so, reset the phony count

; We've received enough coins to grant credits
;
F0D9: A6 01    lda  $01,x                    ; Load the credits value from the table
F0DB: 36       psha                          ; Stash it
F0DC: CE 0C 1E ldx  #$0C1E                   ; Read phony credits count
F0DF: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F0E2: 32       pula                          ; Retrieve stashed credits value
F0E3: 1B       aba                           ; Add to the phony credits count
F0E4: 16       tab                           ; Move it to B, so we can..
F0E5: CE 0C 1E ldx  #$0C1E                   ; ..commit the count to shared RAM
F0E8: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM

; Trigger the credit-inserted event on the phony credit event channel
;
F0EB: CE 0F 99 ldx  #$0F99                   ; Into [$f99]..
F0EE: C6 01    ldb  #$01                     ; ..write $01 (a credit bump happened)
F0F0: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM

;
; COIN B handler
; (Mirrors the COIN A handler)
;

F0F3: B6 00 41 lda  $0041                    ; Fetch COIN B change code
F0F6: 81 00    cmpa #$00                     ; (See routine at $f0b3)
F0F8: 26 3B    bne  $F135                    ; Skips to SERVICE trigger handler
F0FA: F6 00 4E ldb  $004E                    ; (See routine at $f0b3)
F0FD: 54       lsrb                          ; (See routine at $f0b3)
F0FE: 54       lsrb                          ; (See routine at $f0b3)
F0FF: 54       lsrb                          ; (See routine at $f0b3)
F100: 54       lsrb                          ; Two more than for COIN A
F101: 54       lsrb                          ; Two more than for COIN A
F102: C4 06    andb #$06                     ; (See routine at $f0b3)
F104: CE F1 87 ldx  #$F187                   ; (See routine at $f0b3)
F107: 3A       abx                           ; (See routine at $f0b3)
F108: A6 00    lda  $00,x                    ; (See routine at $f0b3)
F10A: 81 01    cmpa #$01                     ; (See routine at $f0b3)
F10C: 27 0D    beq  $F11B                    ; (See routine at $f0b3)
F10E: 7C 00 49 inc  $0049                    ; (See routine at $f0b3)
F111: A6 00    lda  $00,x                    ; (See routine at $f0b3)
F113: B1 00 49 cmpa $0049                    ; (See routine at $f0b3)
F116: 26 1D    bne  $F135                    ; Skips to SERVICE trigger handler
F118: 7F 00 49 clr  $0049                    ; (See routine at $f0b3)
F11B: A6 01    lda  $01,x                    ; (See routine at $f0b3)
F11D: 36       psha                          ; (See routine at $f0b3)
F11E: CE 0C 1E ldx  #$0C1E                   ; (See routine at $f0b3)
F121: BD F1 BF jsr  $F1BF                    ; (See routine at $f0b3)
F124: 32       pula                          ; (See routine at $f0b3)
F125: 1B       aba                           ; (See routine at $f0b3)
F126: 16       tab                           ; (See routine at $f0b3)
F127: CE 0C 1E ldx  #$0C1E                   ; (See routine at $f0b3)
F12A: BD F1 DB jsr  $F1DB                    ; (See routine at $f0b3)
F12D: CE 0F 99 ldx  #$0F99                   ; (See routine at $f0b3)
F130: C6 01    ldb  #$01                     ; (See routine at $f0b3)
F132: BD F1 DB jsr  $F1DB                    ; (See routine at $f0b3)

;
; SERVICE handler
;

F135: B6 00 45 lda  $0045                    ; Fetch SERVICE change code
F138: 81 00    cmpa #$00                     ; Falling edge?
F13A: 26 1A    bne  $F156                    ; If not, skip to lockouts handler

F13C: CE 0C 1E ldx  #$0C1E                   ; Load phony credits count
F13F: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F142: 86 08    lda  #$08                     ; Compare 8..
F144: 11       cba                           ; ..to the phony credits count
F145: 25 1A    bcs  $F161                    ; If count >= 9, do ENABLE_COIN_LOCKOUTS and return

F147: 5C       incb                          ; Increment the phony credits count
F148: CE 0C 1E ldx  #$0C1E                   ; We'll commit it back to [$c1e]
F14B: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM

F14E: CE 0F 99 ldx  #$0F99                   ; Now commit to the phony credit event channel..
F151: C6 01    ldb  #$01                     ; ..the value $01 (a credit bump happened)
F153: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM

;
; Lockouts handler
;

F156: CE 0C 1E ldx  #$0C1E                   ; Load phony credits count
F159: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F15C: 86 08    lda  #$08                     ; Compared to 8..
F15E: 11       cba                           ; ..is it larger?
F15F: 24 07    bcc  $F168                    ; If not, do DISABLE_COIN_LOCKOUTS and return
; Falls through...


;
; ENABLE_COIN_LOCKOUTS:
; (Called from both PROCESS_PHONY_CREDITS and PROCESS_COIN_LOCKOUTS, which
; overrides the PS4-calculated value with one from the main CPU)
;
; Configures the coin mechs to not accept more coins
;

F161: 86 EF    lda  #$EF                     ; Create a mask for bit 4 ('OUT' for port 1)
F163: 94 02    anda $02                      ; AND port 1's current value
F165: 97 02    sta  $02                      ; Write it to port 1
F167: 39       rts  


;
; DISABLE_COIN_LOCKOUTS:
; (Called from both PROCESS_PHONY_CREDITS and PROCESS_COIN_LOCKOUTS, which
; overrides the PS4-calculated value with one from the main CPU)
;
; Configures the coin mechs to accept more coins
;

F168: 86 10    lda  #$10                     ; Create a pattern for bit 4 ('OUT' for port 1)
F16A: 9A 02    ora  $02                      ; OR port 1's current value
F16C: 97 02    sta  $02                      ; Write it to port 1
F16E: 39       rts  


;
; TRACK_MSB_CHANGE:
; (A subroutine for PROCESS_PHONY_CREDITS)
;
; On entry, X   = a RAM address
;           A   = a byte where we only care about the MSB
;           (X) = last frame's value of A
;
; On exit,  (X)   = this frame's value of A            (for incoming val. of X)
;           (X+1) = How MSB of A has changed           (for incoming val. of X)
;                   $00 = 1 last frame, 0 this frame
;                   $01 = 0 last frame, 0 this frame
;                   $02 = 1 last frame, 1 this frame
;                   $03 = 0 last frame, 1 this frame
;           X     = 2 + incoming val. of X
;

F16F: B7 00 46 sta  $0046                    ; Stash incoming byte in $0046
F172: E6 00    ldb  $00,x                    ; Load last frame's byte into B
F174: A7 00    sta  $00,x                    ; Store this frame's byte into X
F176: 4F       clra                          ; Stage a change code of $00

; Set change code bit 0 based on last frame's MSB
F177: 58       aslb                          ; Rotate prev frame's byte left
F178: 25 01    bcs  $F17B                    ; If its bit 7 was set, skip
F17A: 4C       inca                          ; Effectively, sets bit 0

; Set change code bit 1 based on this frame's MSB
F17B: 78 00 46 asl  $0046                    ; Shift this frame's byte left
F17E: 24 02    bcc  $F182                    ; If its bit 7 was unset, skip
F180: 4C       inca                          ; Effectively, sets..
F181: 4C       inca                          ; .. bit 1

F182: A7 01    sta  $01,x                    ; Store MSB change code
F184: 08       inx                           ; Advance X..
F185: 08       inx                           ; ..by 2
F186: 39       rts  


;
; PHONY_COINS_PER_CREDIT_TABLE:
;
; I can't quite explain the ordering here: it doesn't seem to match the DIPs.
; Although this isn't the _real_ table: the main CPU completely ignores the
; credits-counting work that the PS4 is doing. Maybe they changed it the
; assignments?
;

F187: 02 01    .byte $02,$01                 ; 2 coins 1 credit
F189: 02 03    .byte $02,$03                 ; 2 coins 3 credits
F18B: 01 02    .byte $01,$02                 ; 1 coin  2 credits
F18D: 01 01    .byte $01,$01                 ; 1 coin  1 credit


;
; SET_OUT_AND_12WAY:
;
; Called from init. Configures the OUT and 1/2 WAY outputs to coin mechs.
; 

F18F: 86 20    lda  #$20                     ; $20 = OUT and 1/2 WAY bits
F191: 9A 02    ora  $02                      ; Read port 1, OR it with the #$20
F193: 97 02    sta  $02                      ; Write to port 1 (set those outputs)
F195: 39       rts  


;
; TEST_FOR_STUCK_COINS:
;

F196: 8D D0    bsr  $F168                    ; Call DISABLE_COIN_LOCKOUTS
F198: CC 01 F4 ldd  #$01F4                   ; Delay: perform 500..
F19B: 83 00 01 subd #$0001
F19E: 26 FB    bne  $F19B                    ; ..empty loops
F1A0: 96 02    lda  $02                      ; Read port 1 (cabinet) data
F1A2: 84 0C    anda #$0C                     ; Isolate bits 2 and 3 (COIN A, COIN B)
F1A4: 26 01    bne  $F1A7                    ; If nonzero, a coin is in: report failure
F1A6: 39       rts  
;
; Either or both of the coin mechs were reporting that a coin was in at the time
; of boot. Write a $01 to [$c7d]. Game will now report "I/O ERROR" and boot loop
; until the coin mechs no longer report there's a coin in.
;
F1A7: CE 0C 7D ldx  #$0C7D                   ; [$c7d] is I/O error reporting channel
F1AA: C6 01    ldb  #$01                     ; Magic number
F1AC: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F1AF: 39       rts  


;
; PROCESS_COIN_LOCKOUTS:
;
; A routine called from IRQ_HANDLER. Receives signals from the main CPU to
; enable or disable the coin lockouts. The game engages the lockouts once the
; ninth credit has been inserted, disengaging it as soon as the game then
; starts.
;

F1B0: CE 0F 94 ldx  #$0F94                   ; [$f94] is coin lockout instruction
F1B3: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F1B6: C1 01    cmpb #$01                     ; If $01..
F1B8: 27 A7    beq  $F161                    ;       ..do ENABLE_COIN_LOCKOUTS and return
F1BA: C1 FF    cmpb #$FF                     ; If $ff..
F1BC: 27 AA    beq  $F168                    ;       ..do DISABLE_COIN_LOCKOUTS and return
F1BE: 39       rts  


;
; READ_RAM_OR_INPUTS:
; Reads a byte from address X of the shared RAM interface into reg B
;
; This is the sole function through which all shared RAM reads flow.
; Note similarities to WRITE_RAM.
;

; Set port 1 bit 7 high. This signals to the IC12 PAL that we'll be doing a read.
F1BF: 96 02    lda  $02
F1C1: 8A 80    ora  #$80
F1C3: 97 02    sta  $02

; Set port 3 (data bus) data direction register to be reading from it
F1C5: 7F 00 04 clr  $0004

; Put out the address with /SORAM low. Then set /SORAM high to kick off the request.
;
F1C8: FF 00 4A stx  $004A                    ; Stash shared RAM address in $004a..
F1CB: FC 00 4A ldd  $004A                    ; ..maybe just to move X to A and B?
F1CE: 84 0F    anda #$0F                     ; Mask out upper nibble of address
F1D0: D7 07    stb  $07                      ; Put address low byte on port 4 (address bus lower)
F1D2: 97 03    sta  $03                      ; Put address high byte on port 2 (address bus upper)
F1D4: 8A 10    ora  #$10                     ; Set /SORAM output bit (tells IC12 PAL of a request)
F1D6: 97 03    sta  $03                      ; Add that to port 2

; I'm guessing they've done some configuration of the ports to hold off read
; attempts on port 3 data until the SC1 input is confident that the request has
; been fulfilled, but I don't know where.
;
F1D8: D6 06    ldb  $06                      ; Read port 3 (data bus) data
F1DA: 39       rts  


;
; WRITE_RAM:
; Writes a byte (in reg B) to shared RAM (at address X)
;
; This is the sole function through which all shared RAM writes flow.
; Note similarities to READ_RAM_OR_INPUTS.
;

; Clear port 1 bit 7. This signals to the IC12 PAL that we'll be doing a write.
F1DB: 96 02    lda  $02
F1DD: 84 7F    anda #$7F
F1DF: 97 02    sta  $02

; Set port 3 (data bus) data direction register to be writing to it
F1E1: 86 FF    lda  #$FF
F1E3: 97 04    sta  $04

F1E5: D7 06    stb  $06                      ; Put byte to write on the data bus
F1E7: FF 00 4A stx  $004A                    ; Stash shared RAM address in $004a..
F1EA: FC 00 4A ldd  $004A                    ; ..maybe just to move X to A and B?
F1ED: 84 0F    anda #$0F                     ; Mask out upper nibble of address
F1EF: D7 07    stb  $07                      ; Put address low byte on port 4 (address bus lower)
F1F1: 97 03    sta  $03                      ; Put address high byte on port 2 (address bus upper)
F1F3: 8A 10    ora  #$10                     ; Set /SORAM output bit (tells IC12 PAL of a request)
F1F5: 97 03    sta  $03                      ; Add that to port 2
F1F7: 39       rts  


;
; INTERRUPT_MAIN_CPU:
;
; The first routine called from IRQ_HANDLER. This generates an interrupt on the
; main CPU, but only if the magic number $47 has been written to [$f98].
;
; Without this routine, the main game would be frozen.
;
; (See also $f092)
;

F1F8: CE 0F 98 ldx  #$0F98                   ; Read [$f98]
F1FB: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F1FE: C1 47    cmpb #$47                     ; Is it the magic number?
F200: 27 01    beq  $F203                    ; Proceed with the interrupt
F202: 39       rts                           ; Otherwise, we're done
;
; Port 1 bit 6 clocks a flip-flop (IC30) which feeds the main CPU's INT line.
; We'll set it low, then high, then low again, to guarantee a full clock pulse.
;
F203: 96 02    lda  $02                      ; Read port 1 data
F205: 84 BF    anda #$BF                     ; Clear bit 6 (main CPU interrupt controller clock)
F207: 97 02    sta  $02                      ; Write it back..
F209: 96 02    lda  $02                      ; ..but immediately re-read it
F20B: 8A 40    ora  #$40                     ; Raise bit 6
F20D: 97 02    sta  $02                      ; Write it back..
F20F: 96 02    lda  $02                      ; ..but immediately re-read it
F211: 84 BF    anda #$BF                     ; Clear bit 6 again
F213: 97 02    sta  $02                      ; Write it back
F215: 39       rts  


;
; This looks like unreachable code. My guess is it was a top-level subroutine,
; which they first stubbed out by making its first instruction an rts; then they
; removed the links to it. Given that it's doing stuff with the status register,
; possibly something vestigial from debugging?
;
F216: 39       rts  
F217: CE 0C 7F ldx  #$0C7F
F21A: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F21D: F1 00 4C cmpb $004C
F220: 07       tpa  
F221: F7 00 4C stb  $004C
F224: 06       tap  
F225: 26 0B    bne  $F232
F227: 7C 00 4D inc  $004D
F22A: B6 00 4D lda  $004D
F22D: 81 0A    cmpa #$0A
F22F: 25 04    bcs  $F235                    ; Return early
F231: 36       psha 
F232: 7F 00 4D clr  $004D
F235: 39       rts  


;
; RELAY_PORTS:
; (Called from IRQ_HANDLER and at startup)
;
; Copies the cabinet interface (I/O pins on port 1) and player controls/DIP
; switches (memory-mapped via the P-CPU bus) to shared RAM locations where the
; main CPU can read them.
;

F236: D6 02    ldb  $02                      ; Read PS4 port 1 data
F238: CE 0C 1F ldx  #$0C1F                   ; Relay it to [$c1f]
F23B: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM

F23E: CE 00 00 ldx  #$0000                   ; Read player controls/DIPs 0
F241: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F244: F7 00 4E stb  $004E                    ; Cache it in $004e
F247: CE 0C 20 ldx  #$0C20                   ; Relay it to [$c20]
F24A: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM

F24D: CE 00 01 ldx  #$0001                   ; Read player controls/DIPs 1
F250: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F253: F7 00 4F stb  $004F                    ; Cache it in $004f
F256: CE 0C 21 ldx  #$0C21                   ; Relay it to [$c21]
F259: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM

F25C: CE 00 02 ldx  #$0002                   ; Read player controls/DIPs 2
F25F: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F262: F7 00 50 stb  $0050                    ; Cache it in $0050
F265: CE 0C 22 ldx  #$0C22                   ; Relay it to [$c22]
F268: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM

F26B: CE 00 03 ldx  #$0003                   ; Read player controls/DIPs 3
F26E: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F271: F7 00 51 stb  $0051                    ; Cache it in $0051
F274: CE 0C 23 ldx  #$0C23                   ; Relay it to [$c23]
F277: 7E F1 DB jmp  $F1DB                    ; Call WRITE_RAM and return


;
; CHECKSUM:
;
; Calculates a 16-bit checksum of code ROM, for the main CPU to use in a self-
; test. The game code expects the value reported here to be $0000; if it isn't,
; it'll display 'PS4 SUM ERROR' and do a boot loop.
;

F27A: CE F0 00 ldx  #$F000                   ; Point X to start of ROM
F27D: 4F       clra                          ; Make D = 0..
F27E: 5F       clrb                          ; ..by zeroing its constituent bytes

F27F: E3 00    addd $00,x                    ; Add (X), (X+1) to D (16-bit)
F281: 08       inx                           ; Advance D..
F282: 08       inx                           ; ..twice (we're doing 16-bit words)
F283: 8C 00 00 cmpx #$0000                   ; Looped through all of ROM?
F286: 26 F7    bne  $F27F                    ; If not, iterate

F288: 36       psha                          ; Stash A (one byte of the checksum)
F289: CE 0C 83 ldx  #$0C83                   ; Store the other byte to [$c83]
F28C: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F28F: 33       pulb                          ; Retrieve stashed A
F290: CE 0C 82 ldx  #$0C82                   ; Store it in [$c82]
F293: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F296: 39       rts  
;
; Given that the checksum is a 2-byte value, and that there are exactly 2 bytes
; between CHECKSUM and the following routine, neither of which get jumped to, I
; think it's a safe bet that these are the checksum balancing bytes: the values
; needed to force the sum to be zero.
;
F297: 08 38    .byte $08,$38


;
; PROCESS_RESET_REQUEST:
; (Called from IRQ_HANDLER)
;
; Begins a warm boot of the PS4 if [$f97] == $4a
;
; It's not obvious why this would be needed: the PS4's reset line is memory-mapped
; to the main CPU.
;

F299: CE 0F 97 ldx  #$0F97                   ; Read [$f97]
F29C: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F29F: C1 4A    cmpb #$4A                     ; Is $4a?
F2A1: 26 03    bne  $F2A6                    ; If not, return
F2A3: 7E F0 00 jmp  $F000                    ; Cold boot
F2A6: 39       rts


;
; PROCESS_C6F:
; (Called from IRQ_HANDLER)
;
; Does work depending on value of [$c6f], which in a playthrough of the game was
; never written to by the CPU outside of the RAM self-test.
;
; Mirrored in $f347, with different constants
;

F2A7: CE 0C 6F ldx  #$0C6F                   ; We'll be reading [$c6f]
F2AA: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F2AD: C1 01    cmpb #$01                     ; If $01..
F2AF: 27 23    beq  $F2D4                    ;       ..jump to $f2d4
F2B1: C1 02    cmpb #$02                     ; If $02..
F2B3: 27 44    beq  $F2F9                    ;       ..jump to $f2f9
F2B5: C1 04    cmpb #$04                     ; If $04..
F2B7: 27 5D    beq  $F316                    ;       ..jump to $f316
F2B9: C1 08    cmpb #$08                     ; If $08..
F2BB: 27 72    beq  $F32F                    ;       ..jump to $f32f

; [$c6f] wasn't 1, 2, 4 or 8.
; If [$f95] != $42 (66), skip to return
;
F2BD: CE 0F 95 ldx  #$0F95
F2C0: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F2C3: C1 42    cmpb #$42
F2C5: 26 0C    bne  $F2D3                    ; rts

; [$f95] was $42. Read [$c24]. If it doesn't match contents of addr $52, push the
; accumulator onto the stack and then try rts. Which would be sure to fail
; because the top of the stack just had the accumulator pushed to it. So this
; is pretty puzzling.
;
F2C7: CE 0C 24 ldx  #$0C24
F2CA: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F2CD: F1 00 52 cmpb $0052
F2D0: 27 01    beq  $F2D3
F2D2: 36       psha 
F2D3: 39       rts  

; Reached when [$c6f] == $01
;
F2D4: CE 00 01 ldx  #$0001
F2D7: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F2DA: 54       lsrb 
F2DB: 54       lsrb 
F2DC: 54       lsrb 
F2DD: 54       lsrb 
F2DE: C4 03    andb #$03
F2E0: CE F3 43 ldx  #$F343                   ; A small table
F2E3: 3A       abx  
F2E4: A6 00    lda  $00,x
F2E6: 16       tab  
F2E7: F7 00 52 stb  $0052
F2EA: CE 0C 24 ldx  #$0C24
F2ED: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F2F0: CE 0C 6F ldx  #$0C6F
F2F3: C6 00    ldb  #$00
F2F5: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F2F8: 39       rts  

; Reached when [$c6f] == $02
;
F2F9: CE 0C 24 ldx  #$0C24
F2FC: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F2FF: C1 0A    cmpb #$0A
F301: 27 0A    beq  $F30D
F303: 5C       incb 
F304: F7 00 52 stb  $0052
F307: CE 0C 24 ldx  #$0C24
F30A: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F30D: CE 0C 6F ldx  #$0C6F
F310: C6 00    ldb  #$00
F312: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F315: 39       rts  

; Reached when [$c6f] == $04
;
F316: CE 0C 24 ldx  #$0C24
F319: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F31C: 5A       decb 
F31D: F7 00 52 stb  $0052
F320: CE 0C 24 ldx  #$0C24
F323: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F326: CE 0C 6F ldx  #$0C6F
F329: C6 00    ldb  #$00
F32B: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F32E: 39       rts  

; Reached when [$c6f] == $08
;
F32F: C6 0A    ldb  #$0A
F331: F7 00 52 stb  $0052
F334: CE 0C 24 ldx  #$0C24
F337: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F33A: CE 0C 6F ldx  #$0C6F
F33D: C6 00    ldb  #$00
F33F: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F342: 39       rts  

; A small table, called from $f380 and $f2e0
;
F343: 01       .byte $01
F344: 00       .byte $00
F345: 04       .byte $04
F346: 02       .byte $02


;
; PROCESS_C70:
; (Called from IRQ_HANDLER)
;
; Appears to parallel the routine at $f2a7, but for [$c70] instead of [$c6f]
; The CPU wasn't seen activating this one during a playthrough either.
;

F347: CE 0C 70 ldx  #$0C70                   ; Other routine used [$c6f]
F34A: BD F1 BF jsr  $F1BF                    ; (See routine at $f2a7)
F34D: C1 01    cmpb #$01                     ; (See routine at $f2a7)
F34F: 27 23    beq  $F374                    ; (See routine at $f2a7)
F351: C1 02    cmpb #$02                     ; (See routine at $f2a7)
F353: 27 44    beq  $F399                    ; (See routine at $f2a7)
F355: C1 04    cmpb #$04                     ; (See routine at $f2a7)
F357: 27 5D    beq  $F3B6                    ; (See routine at $f2a7)
F359: C1 08    cmpb #$08                     ; (See routine at $f2a7)
F35B: 27 72    beq  $F3CF                    ; (See routine at $f2a7)
F35D: CE 0F 95 ldx  #$0F95                   ; (See routine at $f2a7)
F360: BD F1 BF jsr  $F1BF                    ; (See routine at $f2a7)
F363: C1 42    cmpb #$42                     ; (See routine at $f2a7)
F365: 26 0C    bne  $F373                    ; (See routine at $f2a7)
F367: CE 0C 25 ldx  #$0C25                   ; Other routine used [$c24]
F36A: BD F1 BF jsr  $F1BF                    ; (See routine at $f2a7)
F36D: F1 00 53 cmpb $0053                    ; Other routine used $0052
F370: 27 01    beq  $F373                    ; (See routine at $f2a7)
F372: 36       psha                          ; (See routine at $f2a7)
F373: 39       rts                           ; (See routine at $f2a7)
F374: CE 00 01 ldx  #$0001                   ; (See routine at $f2a7)
F377: BD F1 BF jsr  $F1BF                    ; (See routine at $f2a7)
F37A: 54       lsrb                          ; (See routine at $f2a7)
F37B: 54       lsrb                          ; (See routine at $f2a7)
F37C: 54       lsrb                          ; (See routine at $f2a7)
F37D: 54       lsrb                          ; (See routine at $f2a7)
F37E: C4 03    andb #$03                     ; (See routine at $f2a7)
F380: CE F3 43 ldx  #$F343                   ; (See routine at $f2a7)
F383: 3A       abx                           ; (See routine at $f2a7)
F384: A6 00    lda  $00,x                    ; (See routine at $f2a7)
F386: 16       tab                           ; (See routine at $f2a7)
F387: F7 00 53 stb  $0053                    ; Other routine used $0052
F38A: CE 0C 25 ldx  #$0C25                   ; Other routine used [$c24]
F38D: BD F1 DB jsr  $F1DB                    ; (See routine at $f2a7)
F390: CE 0C 70 ldx  #$0C70                   ; Other routine used [$c6f]
F393: C6 00    ldb  #$00                     ; (See routine at $f2a7)
F395: BD F1 DB jsr  $F1DB                    ; (See routine at $f2a7)
F398: 39       rts                           ; (See routine at $f2a7)
F399: CE 0C 25 ldx  #$0C25                   ; Other routine used [$c24]
F39C: BD F1 BF jsr  $F1BF                    ; (See routine at $f2a7)
F39F: C1 0A    cmpb #$0A                     ; (See routine at $f2a7)
F3A1: 27 0A    beq  $F3AD                    ; (See routine at $f2a7)
F3A3: 5C       incb                          ; (See routine at $f2a7)
F3A4: F7 00 53 stb  $0053                    ; Other routine used $0052
F3A7: CE 0C 25 ldx  #$0C25                   ; Other routine used [$c24]
F3AA: BD F1 DB jsr  $F1DB                    ; (See routine at $f2a7)
F3AD: CE 0C 70 ldx  #$0C70                   ; Other routine used [$c6f]
F3B0: C6 00    ldb  #$00                     ; (See routine at $f2a7)
F3B2: BD F1 DB jsr  $F1DB                    ; (See routine at $f2a7)
F3B5: 39       rts                           ; (See routine at $f2a7)
F3B6: CE 0C 25 ldx  #$0C25                   ; Other routine used [$c24]
F3B9: BD F1 BF jsr  $F1BF                    ; (See routine at $f2a7)
F3BC: 5A       decb                          ; (See routine at $f2a7)
F3BD: F7 00 53 stb  $0053                    ; Other routine used $0052
F3C0: CE 0C 25 ldx  #$0C25                   ; Other routine used [$c24]
F3C3: BD F1 DB jsr  $F1DB                    ; (See routine at $f2a7)
F3C6: CE 0C 70 ldx  #$0C70                   ; Other routine used [$c6f]
F3C9: C6 00    ldb  #$00                     ; (See routine at $f2a7)
F3CB: BD F1 DB jsr  $F1DB                    ; (See routine at $f2a7)
F3CE: 39       rts                           ; (See routine at $f2a7)
F3CF: C6 0A    ldb  #$0A                     ; (See routine at $f2a7)
F3D1: F7 00 53 stb  $0053                    ; Other routine used $0052
F3D4: CE 0C 25 ldx  #$0C25                   ; Other routine used [$c24]
F3D7: BD F1 DB jsr  $F1DB                    ; (See routine at $f2a7)
F3DA: CE 0C 70 ldx  #$0C70                   ; Other routine used [$c6f]
F3DD: C6 00    ldb  #$00                     ; (See routine at $f2a7)
F3DF: BD F1 DB jsr  $F1DB                    ; (See routine at $f2a7)
F3E2: 39       rts                           ; (See routine at $f2a7)


;
; PROCESS_C7E:
; (Called from IRQ_HANDLER)
;
; Sets [$c26] and $0054 based on value of [$c7e]. Don't know what this was
; intended for, as, in my experience, the main CPU never attempts a write to
; [$c7e], nor a read from [$c26] (outside of bootup RAM test).
;
; $0054 also seems to be used in PROCESS_CREDITS_MISCHIEF.
;
;
; Current [$c7e] value | New [$c26] and $0054 value | New [$c7e] value
; ---------------------|----------------------------|-----------------
;                  $01 |                        $00 |              $00
;                  $02 |   incremented [$c26] value |              $00
;                  $04 |                        $31 |              $00
;                  $08 |                        $62 |              $00
;                  $10 |                        $63 |              $00
;                  $20 |                        $64 |              $00
;                  $40 |                        $65 |              $00
;                other |                  unchanged |        unchanged
;
; In the 'other' case, will crash if [$f95] is $42 and [$c26] doesn't match
; contents of $0054
;

F3E3: CE 0C 7E ldx  #$0C7E
F3E6: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F3E9: C1 01    cmpb #$01                     ; If $01..
F3EB: 27 2F    beq  $F41C                    ;       ..go to $f41c
F3ED: C1 02    cmpb #$02                     ; If $02..
F3EF: 27 3F    beq  $F430                    ;       ..go to $f430
F3F1: C1 04    cmpb #$04                     ; If $04..
F3F3: 27 54    beq  $F449                    ;       ..go to $f449
F3F5: C1 08    cmpb #$08                     ; If $08..
F3F7: 27 66    beq  $F45F                    ;       ..go to $f45f
F3F9: C1 10    cmpb #$10                     ; If $10..
F3FB: 27 6E    beq  $F46B                    ;       ..go to $f46b
F3FD: C1 20    cmpb #$20                     ; If $20..
F3FF: 27 76    beq  $F477                    ;       ..go to $f477
F401: C1 40    cmpb #$40                     ; If $40..
F403: 27 7E    beq  $F483                    ;       ..go to $f483

; Reached only if [$c7e] was $00, $80, or not a power of two:
;
; If [$f95] isn't $42, do no more
; otherwise, read [$c26]. If it doesn't match $0054, trash the stack (why?!)
;
F405: CE 0F 95 ldx  #$0F95
F408: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F40B: C1 42    cmpb #$42
F40D: 26 0C    bne  $F41B
F40F: CE 0C 26 ldx  #$0C26
F412: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F415: F1 00 54 cmpb $0054
F418: 27 01    beq  $F41B 
F41A: 36       psha                          ; Puts a stray byte on the stack before an rts. Will crash.
F41B: 39       rts  

; [$c7e] was $01: clear what's at [$c26], $0054 and [$c7e]
F41C: CE 0C 26 ldx  #$0C26
F41F: C6 00    ldb  #$00
F421: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F424: 7F 00 54 clr  $0054
F427: CE 0C 7E ldx  #$0C7E
F42A: C6 00    ldb  #$00
F42C: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F42F: 39       rts  

; [$c7e] was $02: increment what's at [$c26], caching new value at $0054; clear [$c7e]
F430: CE 0C 26 ldx  #$0C26
F433: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F436: 5C       incb 
F437: F7 00 54 stb  $0054
F43A: CE 0C 26 ldx  #$0C26
F43D: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F440: CE 0C 7E ldx  #$0C7E
F443: C6 00    ldb  #$00
F445: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F448: 39       rts  

; [$c7e] was $04: write $31 to [$c26] and $0054, and $00 to [$c7e]
F449: CE 0C 26 ldx  #$0C26
F44C: C6 31    ldb  #$31
F44E: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F451: C6 31    ldb  #$31
; Falls through...

; Common ending for this handler and the few that follow
F453: F7 00 54 stb  $0054                    ; Cache the value we just wrote to shared RAM
F456: CE 0C 7E ldx  #$0C7E                   ; To [$c7e], write..
F459: C6 00    ldb  #$00                     ; ..zero
F45B: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F45E: 39       rts                           ; Done

; [$c7e] was $08: write $62 to [$c26] and $0054, and $00 to [$c7e]
F45F: CE 0C 26 ldx  #$0C26
F462: C6 62    ldb  #$62
F464: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F467: C6 62    ldb  #$62
F469: 20 E8    bra  $F453                    ; Common ending

; [$c7e] was $10: write $63 to [$c26] and $0054, and $00 to [$c7e]
F46B: CE 0C 26 ldx  #$0C26
F46E: C6 63    ldb  #$63
F470: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F473: C6 63    ldb  #$63
F475: 20 DC    bra  $F453                    ; Common ending

; [$c7e] was $20: write $64 to [$c26] and $0054, and $00 to [$c7e]
F477: CE 0C 26 ldx  #$0C26
F47A: C6 64    ldb  #$64
F47C: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F47F: C6 64    ldb  #$64
F481: 20 D0    bra  $F453                    ; Common ending

; [$c7e] was $40: write $65 to [$c26] and $0054, and $00 to [$c7e]
F483: CE 0C 26 ldx  #$0C26
F486: C6 65    ldb  #$65
F488: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F48B: C6 65    ldb  #$65
F48D: 20 C4    bra  $F453                    ; Common ending


;
; PROCESS_P1_BEASTIES:
; (Called from IRQ_HANDLER)
;
; This is for player 1. Note that the code in $f585 onwards does player 2, and
; is virtually identical.
;

F48F: CE 0C 5F ldx  #$0C5F                   ; [$c5f] = player 1 liveness
F492: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS

; Check phony liveness value of player 1 before starting (see note in memory map)
F495: C4 01    andb #$01
F497: C1 01    cmpb #$01
F499: 27 01    beq  $F49C                    ; Only start if [$c5f] has bit 0 set
F49B: 39       rts  

F49C: 7F 00 57 clr  $0057                    ; Reset count of beasties processed
F49F: CE 0C 60 ldx  #$0C60                   ; Point X to the player's Y position
F4A2: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F4A5: F7 00 55 stb  $0055                    ; Store Y position in $0055
F4A8: CE 0C 61 ldx  #$0C61                   ; Point X to the player's X position
F4AB: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F4AE: F7 00 56 stb  $0056                    ; Store X position in $0056
F4B1: CC 0C 01 ldd  #$0C01                   ; Store pointer to first beastie input structure..
F4B4: FD 00 58 std  $0058                    ; ..in $0058
F4B7: CC 0C 27 ldd  #$0C27                   ; Store pointer to first beastie output structure..
F4BA: FD 00 5A std  $005A                    ; ..in $005a
F4BD: 7F 00 5C clr  $005C                    ; Reset count of Y overlaps

; Loop start for beastie iteration
F4C0: FE 00 58 ldx  $0058                    ; Load current beastie's life stage
F4C3: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F4C6: C4 01    andb #$01                     ; Is bit 1 set? (ie. is it alive?)
F4C8: C1 01    cmpb #$01
F4CA: 27 03    beq  $F4CF                    ; If so, let's process it
F4CC: 7E F5 3D jmp  $F53D                    ; If not, go to end of loop to iterate to next beastie

; Beastie is alive
F4CF: FE 00 58 ldx  $0058                    ; Load beastie input structure base into X
F4D2: 08       inx                           ; Increment, so X now points to its coordinates

; Compare the Y positions of the player and the beastie. Into the first byte of
; the output structure we'll write a qualitative who's-above-whom code, and into
; the fifth we'll write the quantitative difference.
;
F4D3: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS, fetching the Y coordinate into B
F4D6: B6 00 55 lda  $0055                    ; Load player Y pos into A
F4D9: 10       sba                           ; Subtract beastie Y from player Y, into A
F4DA: 27 0B    beq  $F4E7                    ; If they match, branch to $f4e7
F4DC: 24 05    bcc  $F4E3                    ; If player had higher (greater) Y pos, go to $f4e3

; Player is below beastie
F4DE: C6 01    ldb  #$01                     ; Output code will be $01
F4E0: 40       nega                          ; Flip the sign: get the absolute Y delta
F4E1: 20 06    bra  $F4E9                    ; Commit it and move on

; Player is above beastie
F4E3: C6 00    ldb  #$00                     ; Output code will be $00
F4E5: 20 02    bra  $F4E9                    ; Commit it and move on

; Player has the same Y pos as beastie
F4E7: C6 80    ldb  #$80                     ; Output code will be $80

; Write output code to byte 0 of beastie output structure
F4E9: FE 00 5A ldx  $005A                    ; Point X to beastie output structure base
F4EC: 36       psha                          ; Stash absolute Y delta on the stack
F4ED: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM

; Store the absolute Y delta into the fifth byte of the output structure
F4F0: FE 00 5A ldx  $005A
F4F3: 08       inx  
F4F4: 08       inx  
F4F5: 08       inx  
F4F6: 08       inx  
F4F7: 32       pula 
F4F8: 36       psha 
F4F9: 16       tab  
F4FA: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM

F4FD: 32       pula                          ; Retrieve stashed absolute Y delta
F4FE: 81 08    cmpa #$08
F500: 24 03    bcc  $F505

; A Y collision has happened.
;
; Raise a flag for the X collision detector to consider.
;
F502: 7C 00 5C inc  $005C                    ; Bump the Y overlap count

; Now look at horizontal
F505: FE 00 58 ldx  $0058                    ; Point X to beastie input structure..
F508: 08       inx                           ; ..
F509: 08       inx                           ; ..+2, which is their X coordinate
F50A: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS, putting the X pos in B
F50D: B6 00 56 lda  $0056                    ; Retrieve the player's X pos into A
F510: 10       sba                           ; Subtract beastie X from player X, into A
F511: 27 0B    beq  $F51E                    ; If they match, branch to $f51e
F513: 24 05    bcc  $F51A                    ; If player had rightmost (greater) X pos, go to $f51a

; Player is left of beastie
F515: C6 01    ldb  #$01                     ; Output code will be $01
F517: 40       nega                          ; Flip the sign: get the absolute X delta
F518: 20 06    bra  $F520                    ; Commit it and move on

; Player is right of beastie
F51A: C6 00    ldb  #$00                     ; Output code will be $00
F51C: 20 02    bra  $F520                    ; Commit it and move on

; Player has the same X pos as beastie
F51E: C6 80    ldb  #$80                     ; Output code will be $80

; Write output code to the thid byte of beastie output structure
F520: FE 00 5A ldx  $005A                    ; Point X to beastie output structure base..
F523: 08       inx                           ; ..and add..
F524: 08       inx                           ; ..two
F525: 36       psha                          ; Stash absolute X delta on the stack
F526: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM

; Store the absolute X delta into the seventh byte of the output structure
F529: FE 00 5A ldx  $005A
F52C: 08       inx  
F52D: 08       inx  
F52E: 08       inx  
F52F: 08       inx  
F530: 08       inx  
F531: 08       inx  
F532: 32       pula 
F533: 36       psha 
F534: 16       tab  
F535: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM

F538: 32       pula                          ; Retrieve stashed absolute X delta
F539: 81 08    cmpa #$08
F53B: 25 26    bcs  $F563

; Loop post-amble
F53D: FE 00 58 ldx  $0058                    ; Point X to beastie input structure base
F540: 08       inx                           ; Increment it by 4..
F541: 08       inx                           ; ..
F542: 08       inx                           ; ..
F543: 08       inx                           ; ..to point it to next beastie's input structure base
F544: FF 00 58 stx  $0058                    ; Store that as the new current one

F547: FE 00 5A ldx  $005A                    ; Point X to beastie output structure base
F54A: 08       inx                           ; Increment it by 8..
F54B: 08       inx                           ; ..
F54C: 08       inx                           ; ..
F54D: 08       inx                           ; ..
F54E: 08       inx                           ; ..
F54F: 08       inx                           ; ..
F550: 08       inx                           ; ..
F551: 08       inx                           ; ..to point it to next beastie's output structure base
F552: FF 00 5A stx  $005A                    ; Store that as the new current one

F555: 7C 00 57 inc  $0057                    ; Increment count of beasties we've processed..
F558: B6 00 57 lda  $0057                    ; ..and pull it into A
F55B: 81 07    cmpa #$07                     ; Have we processed all seven?
F55D: 27 03    beq  $F562                    ; If so, skip to return
F55F: 7E F4 C0 jmp  $F4C0                    ; If not, loop
F562: 39       rts                           ; All done

; An X collision has happened.
;
; The code from here on out has a showstopper bug. What the developer probably
; intended was to kill off the player if both axes of a beastie are +/-8 from
; the player's corresponding axis. What's _actually_ happening is that we iterate
; through the beasties, and...
;
;  - each time there's a Y collision, we increment $005c
;  - each time there's an X collision, then:
;     - if there's been a Y collision, then try kill off the player, and exit
;     - if there hasn't, just exit
;
; This means that:
; 
;  - a player could be killed if they overlap in X with one beastie, and in Y
;    with another (depending on order)
;  - none of the beasties that follow the one with the X overlap will have their
;    beastie output data updated
;
; I'll speculate that the code that runs the axis-tests for a single beastie used
; to get jsr'd to, with a zero $005c each time. But that's no longer the case,
; and the post-X-overlap code thinks it's just returning from a single beastie
; processor but it's accidentally rts'ing from the whole lot.
;
; I'll further speculate that they only realized this problem after the mask ROMs
; for the PS4s were in production, and worked around it in main CPU code by:
;
;  - deprecating the [$c5f]/[$c67] variables that otherwise look like they're
;    trying to track whether players 1 and 2, respectively, are alive
;  - deprecating the [$c62]/[$c6a] variables that look like they're trying to
;    trigger player death
;  - as for the output data for some beasties not getting updated after an
;    X-overlap: they just accepted the consequences. It will affect gameplay,
;    but... well, as a player, did you ever notice?
;
F563: 7D 00 5C tst  $005C                    ; Was a Y collision previously reported?
F566: 27 FA    beq  $F562                    ; If not, early-out

; The code thinks that a player and a beastie overlap in both X and Y and wants
; to kill the player off. It'll first re-load their liveness, I guess to not
; try kill off a player when they're already dead (would there be any harm?)
;
F568: CE 0C 5F ldx  #$0C5F                   ; Re-load player phony liveness
F56B: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F56E: C4 01    andb #$01                     ; Echoing what happened at $f4c6..
F570: C1 01    cmpb #$01                     ; ..
F572: 26 EE    bne  $F562                    ; Early-out if player seems dead (never happens)

; Issue a request for the main CPU to kill off the player (which it will ignore)
; 
F574: CE 0C 62 ldx  #$0C62                   ; Store in [$c62]..
F577: C6 01    ldb  #$01                     ; ..a flag to presumably request death
F579: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F57C: F6 00 57 ldb  $0057                    ; Load beastie loop counter into B..
F57F: CE 0C 63 ldx  #$0C63                   ; ..to report which beastie cause the collision
F582: 7E F1 DB jmp  $F1DB                    ; Call WRITE_RAM and return


;
; PROCESS_P2_BEASTIES:
; (Called from IRQ_HANDLER)
;
; This is for player 2. Note that the code in $f48f onwards does player 1,
; and is virtually identical, the only differences being a few of the pointers
; and some extra increments so data can be stored after the P1 data.
;
; So below I'm only commenting on the differences.
;

F585: CE 0C 67 ldx  #$0C67                   ; Was [$c5f] for P1
F588: BD F1 BF jsr  $F1BF                    ; (See routine at $f48f)
F58B: C4 01    andb #$01                     ; (See routine at $f48f)
F58D: C1 01    cmpb #$01                     ; (See routine at $f48f)
F58F: 27 01    beq  $F592                    ; (See routine at $f48f)
F591: 39       rts                           ; (See routine at $f48f)
F592: 7F 00 57 clr  $0057                    ; (See routine at $f48f)
F595: CE 0C 68 ldx  #$0C68                   ; Was [$c60] for P1
F598: BD F1 BF jsr  $F1BF                    ; (See routine at $f48f)
F59B: F7 00 55 stb  $0055                    ; (See routine at $f48f)
F59E: CE 0C 69 ldx  #$0C69                   ; Was [$c61] for P1
F5A1: BD F1 BF jsr  $F1BF                    ; (See routine at $f48f)
F5A4: F7 00 56 stb  $0056                    ; (See routine at $f48f)
F5A7: CC 0C 01 ldd  #$0C01                   ; (See routine at $f48f)
F5AA: FD 00 58 std  $0058                    ; (See routine at $f48f)
F5AD: CC 0C 27 ldd  #$0C27                   ; (See routine at $f48f)
F5B0: FD 00 5A std  $005A                    ; (See routine at $f48f)
F5B3: 7F 00 5C clr  $005C                    ; (See routine at $f48f)
F5B6: FE 00 58 ldx  $0058                    ; (See routine at $f48f)
F5B9: BD F1 BF jsr  $F1BF                    ; (See routine at $f48f)
F5BC: C4 01    andb #$01                     ; (See routine at $f48f)
F5BE: C1 01    cmpb #$01                     ; (See routine at $f48f)
F5C0: 27 03    beq  $F5C5                    ; (See routine at $f48f)
F5C2: 7E F6 37 jmp  $F637                    ; (See routine at $f48f)
F5C5: FE 00 58 ldx  $0058                    ; (See routine at $f48f)
F5C8: 08       inx                           ; (See routine at $f48f)
F5C9: BD F1 BF jsr  $F1BF                    ; (See routine at $f48f)
F5CC: B6 00 55 lda  $0055                    ; (See routine at $f48f)
F5CF: 10       sba                           ; (See routine at $f48f)
F5D0: 27 0B    beq  $F5DD                    ; (See routine at $f48f)
F5D2: 24 05    bcc  $F5D9                    ; (See routine at $f48f)
F5D4: C6 01    ldb  #$01                     ; (See routine at $f48f)
F5D6: 40       nega                          ; (See routine at $f48f)
F5D7: 20 06    bra  $F5DF                    ; (See routine at $f48f)
F5D9: C6 00    ldb  #$00                     ; (See routine at $f48f)
F5DB: 20 02    bra  $F5DF                    ; (See routine at $f48f)
F5DD: C6 80    ldb  #$80                     ; (See routine at $f48f)
F5DF: FE 00 5A ldx  $005A                    ; (See routine at $f48f)
F5E2: 08       inx                           ; Not present for P1
F5E3: 36       psha                          ; (See routine at $f48f)
F5E4: BD F1 DB jsr  $F1DB                    ; (See routine at $f48f)
F5E7: FE 00 5A ldx  $005A                    ; (See routine at $f48f)
F5EA: 08       inx                           ; (See routine at $f48f)
F5EB: 08       inx                           ; (See routine at $f48f)
F5EC: 08       inx                           ; (See routine at $f48f)
F5ED: 08       inx                           ; (See routine at $f48f)
F5EE: 08       inx                           ; Not present for P1
F5EF: 32       pula                          ; (See routine at $f48f)
F5F0: 36       psha                          ; (See routine at $f48f)
F5F1: 16       tab                           ; (See routine at $f48f)
F5F2: BD F1 DB jsr  $F1DB                    ; (See routine at $f48f)
F5F5: 32       pula                          ; (See routine at $f48f)
F5F6: 81 08    cmpa #$08                     ; (See routine at $f48f)
F5F8: 24 03    bcc  $F5FD                    ; (See routine at $f48f)
F5FA: 7C 00 5C inc  $005C                    ; (See routine at $f48f)
F5FD: FE 00 58 ldx  $0058                    ; (See routine at $f48f)
F600: 08       inx                           ; (See routine at $f48f)
F601: 08       inx                           ; (See routine at $f48f)
F602: BD F1 BF jsr  $F1BF                    ; (See routine at $f48f)
F605: B6 00 56 lda  $0056                    ; (See routine at $f48f)
F608: 10       sba                           ; (See routine at $f48f)
F609: 27 0B    beq  $F616                    ; (See routine at $f48f)
F60B: 24 05    bcc  $F612                    ; (See routine at $f48f)
F60D: C6 01    ldb  #$01                     ; (See routine at $f48f)
F60F: 40       nega                          ; (See routine at $f48f)
F610: 20 06    bra  $F618                    ; (See routine at $f48f)
F612: C6 00    ldb  #$00                     ; (See routine at $f48f)
F614: 20 02    bra  $F618                    ; (See routine at $f48f)
F616: C6 80    ldb  #$80                     ; (See routine at $f48f)
F618: FE 00 5A ldx  $005A                    ; (See routine at $f48f)
F61B: 08       inx                           ; (See routine at $f48f)
F61C: 08       inx                           ; (See routine at $f48f)
F61D: 08       inx                           ; Not present for P1
F61E: 36       psha                          ; (See routine at $f48f)
F61F: BD F1 DB jsr  $F1DB                    ; (See routine at $f48f)
F622: FE 00 5A ldx  $005A                    ; (See routine at $f48f)
F625: 08       inx                           ; (See routine at $f48f)
F626: 08       inx                           ; (See routine at $f48f)
F627: 08       inx                           ; (See routine at $f48f)
F628: 08       inx                           ; (See routine at $f48f)
F629: 08       inx                           ; (See routine at $f48f)
F62A: 08       inx                           ; (See routine at $f48f)
F62B: 08       inx                           ; Not present for P1
F62C: 32       pula                          ; (See routine at $f48f)
F62D: 36       psha                          ; (See routine at $f48f)
F62E: 16       tab                           ; (See routine at $f48f)
F62F: BD F1 DB jsr  $F1DB                    ; (See routine at $f48f)
F632: 32       pula                          ; (See routine at $f48f)
F633: 81 08    cmpa #$08                     ; (See routine at $f48f)
F635: 25 26    bcs  $F65D                    ; (See routine at $f48f)
F637: FE 00 58 ldx  $0058                    ; (See routine at $f48f)
F63A: 08       inx                           ; (See routine at $f48f)
F63B: 08       inx                           ; (See routine at $f48f)
F63C: 08       inx                           ; (See routine at $f48f)
F63D: 08       inx                           ; (See routine at $f48f)
F63E: FF 00 58 stx  $0058                    ; (See routine at $f48f)
F641: FE 00 5A ldx  $005A                    ; (See routine at $f48f)
F644: 08       inx                           ; (See routine at $f48f)
F645: 08       inx                           ; (See routine at $f48f)
F646: 08       inx                           ; (See routine at $f48f)
F647: 08       inx                           ; (See routine at $f48f)
F648: 08       inx                           ; (See routine at $f48f)
F649: 08       inx                           ; (See routine at $f48f)
F64A: 08       inx                           ; Not present for P1
F64B: 08       inx                           ; Not present for P1
F64C: FF 00 5A stx  $005A                    ; (See routine at $f48f)
F64F: 7C 00 57 inc  $0057                    ; (See routine at $f48f)
F652: B6 00 57 lda  $0057                    ; (See routine at $f48f)
F655: 81 07    cmpa #$07                     ; (See routine at $f48f)
F657: 27 03    beq  $F65C                    ; (See routine at $f48f)
F659: 7E F5 B6 jmp  $F5B6                    ; (See routine at $f48f)
F65C: 39       rts                           ; (See routine at $f48f)
F65D: 7D 00 5C tst  $005C                    ; (See routine at $f48f)
F660: 27 FA    beq  $F65C                    ; (See routine at $f48f)
F662: CE 0C 67 ldx  #$0C67                   ; (See routine at $f48f)
F665: BD F1 BF jsr  $F1BF                    ; (See routine at $f48f)
F668: C4 01    andb #$01                     ; (See routine at $f48f)
F66A: C1 01    cmpb #$01                     ; (See routine at $f48f)
F66C: 26 EE    bne  $F65C                    ; (See routine at $f48f)
F66E: CE 0C 6A ldx  #$0C6A                   ; (See routine at $f48f)
F671: C6 01    ldb  #$01                     ; (See routine at $f48f)
F673: BD F1 DB jsr  $F1DB                    ; (See routine at $f48f)
F676: F6 00 57 ldb  $0057                    ; (See routine at $f48f)
F679: CE 0C 6B ldx  #$0C6B                   ; (See routine at $f48f)
F67C: 7E F1 DB jmp  $F1DB                    ; (See routine at $f48f)


;
; PROCESS_CREEPER_C72_C74:
; (Called from IRQ_HANDLER)
;
; Two creepers (see PROCESS_CREEPER_C76) chained together. The first uses:
;   - table source [$c72]
;   - output value [$c73]
;   - sequence index at $005d
;

F67F: CE 0C 72 ldx  #$0C72                   ; (See routine at $f6cb)
F682: BD F1 BF jsr  $F1BF                    ; (See routine at $f6cb)
F685: CE F7 17 ldx  #$F717                   ; (See routine at $f6cb)
F688: 3A       abx                           ; (See routine at $f6cb)
F689: 3A       abx                           ; (See routine at $f6cb)
F68A: EE 00    ldx  $00,x                    ; (See routine at $f6cb)
F68C: F6 00 5D ldb  $005D                    ; (See routine at $f6cb)
F68F: 3A       abx                           ; (See routine at $f6cb)
F690: A6 00    lda  $00,x                    ; (See routine at $f6cb)
F692: 81 FF    cmpa #$FF                     ; (See routine at $f6cb)
F694: 26 05    bne  $F69B                    ; (See routine at $f6cb)
F696: 7F 00 5D clr  $005D                    ; (See routine at $f6cb)
F699: 20 E4    bra  $F67F                    ; (See routine at $f6cb)
F69B: 7C 00 5D inc  $005D                    ; (See routine at $f6cb)
F69E: 16       tab                           ; (See routine at $f6cb)
F69F: CE 0C 73 ldx  #$0C73                   ; (See routine at $f6cb)
F6A2: BD F1 DB jsr  $F1DB                    ; jsr instead of jmp, to fall through
;
; This second creeper uses:
;   - table source [$c74]
;   - output value [$c75]
;   - sequence index at $005e
;
F6A5: CE 0C 74 ldx  #$0C74                   ; (See routine at $f6cb)
F6A8: BD F1 BF jsr  $F1BF                    ; (See routine at $f6cb)
F6AB: CE F7 17 ldx  #$F717                   ; (See routine at $f6cb)
F6AE: 3A       abx                           ; (See routine at $f6cb)
F6AF: 3A       abx                           ; (See routine at $f6cb)
F6B0: EE 00    ldx  $00,x                    ; (See routine at $f6cb)
F6B2: F6 00 5E ldb  $005E                    ; (See routine at $f6cb)
F6B5: 3A       abx                           ; (See routine at $f6cb)
F6B6: A6 00    lda  $00,x                    ; (See routine at $f6cb)
F6B8: 81 FF    cmpa #$FF                     ; (See routine at $f6cb)
F6BA: 26 05    bne  $F6C1                    ; (See routine at $f6cb)
F6BC: 7F 00 5E clr  $005E                    ; (See routine at $f6cb)
F6BF: 20 E4    bra  $F6A5                    ; (See routine at $f6cb)
F6C1: 7C 00 5E inc  $005E                    ; (See routine at $f6cb)
F6C4: 16       tab                           ; (See routine at $f6cb)
F6C5: CE 0C 75 ldx  #$0C75                   ; (See routine at $f6cb)
F6C8: 7E F1 DB jmp  $F1DB                    ; (See routine at $f6cb)


;
; PROCESS_CREEPER_C76:
; (Called from IRQ_HANDLER)
;
; A creeper using:
;   - table source [$c76]
;   - output value [$c77]
;   - sequence index at $005f
;
; 'Creepers' are routines that emit a sequence of integers contrived to average
; out at a very specific fraction. The values would be used to determine how many
; times, in any given frame, to perform some unit of work, such that a steady
; non-integer rate of work can be achieved on average.
;
; There are four creepers simulated by the PS4, all of which seem redundant (the
; main CPU hasn't been seen trying to read their results). This one, however, is
; at least fed something by the CPU: the current level's wind speed. You'd think
; the output would then be used to determine how many iterations of the bubble-
; drifting simulation to run for that frame. But no. The main CPU doesn't even
; try read it.
;

F6CB: CE 0C 76 ldx  #$0C76                   ; Fetch table source from [$c76]
F6CE: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F6D1: CE F7 17 ldx  #$F717                   ; Point X to CREEPER_TABLES
F6D4: 3A       abx                           ; Table entries are 16-bit..
F6D5: 3A       abx                           ; ..so add the index twice
F6D6: EE 00    ldx  $00,x                    ; Load the 16-bit table entry into X

; We now have a creeper table base pointer in X
F6D8: F6 00 5F ldb  $005F                    ; Retrieve current sequence index
F6DB: 3A       abx                           ; Add it to table base
F6DC: A6 00    lda  $00,x                    ; Fetch sequence value into A 
F6DE: 81 FF    cmpa #$FF                     ; Was table entry $ff? (the sentinel)
F6E0: 26 05    bne  $F6E7                    ; If not, continue
F6E2: 7F 00 5F clr  $005F                    ; If so, reset sequence index to 0..
F6E5: 20 E4    bra  $F6CB                    ; ..and re-run from the start

F6E7: 7C 00 5F inc  $005F                    ; Increment sequence index
F6EA: 16       tab                           ; Transfer sequence value to B..
F6EB: CE 0C 77 ldx  #$0C77                   ; ..to output at [$c77]
F6EE: 7E F1 DB jmp  $F1DB                    ; Call WRITE_RAM and return


;
; PROCESS_CREEPER_C80:
; (Called from IRQ_HANDLER)
;
; A creeper (see PROCESS_CREEPER_C76) using:
;   - table source [$c80]
;   - output value [$c81]
;   - sequence index at $0060
;

F6F1: CE 0C 80 ldx  #$0C80                   ; (See routine at $f6cb)
F6F4: BD F1 BF jsr  $F1BF                    ; (See routine at $f6cb)
F6F7: CE F7 17 ldx  #$F717                   ; (See routine at $f6cb)
F6FA: 3A       abx                           ; (See routine at $f6cb)
F6FB: 3A       abx                           ; (See routine at $f6cb)
F6FC: EE 00    ldx  $00,x                    ; (See routine at $f6cb)
F6FE: F6 00 60 ldb  $0060                    ; (See routine at $f6cb)
F701: 3A       abx                           ; (See routine at $f6cb)
F702: A6 00    lda  $00,x                    ; (See routine at $f6cb)
F704: 81 FF    cmpa #$FF                     ; (See routine at $f6cb)
F706: 26 05    bne  $F70D                    ; (See routine at $f6cb)
F708: 7F 00 60 clr  $0060                    ; (See routine at $f6cb)
F70B: 20 E4    bra  $F6F1                    ; (See routine at $f6cb)
F70D: 7C 00 60 inc  $0060                    ; (See routine at $f6cb)
F710: 16       tab                           ; (See routine at $f6cb)
F711: CE 0C 81 ldx  #$0C81                   ; (See routine at $f6cb)
F714: 7E F1 DB jmp  $F1DB                    ; (See routine at $f6cb)


;
; CREEPER_TABLES:
;
; The data below is useful for work that needs to be performed, on average,
; a non-integer number of times per frame.
;
; Each entry in the table points to a sequence which has a specific average
; value, in increments of one-tenth.
;
; For example, entry 12 is CREEPER_TABLE_1_2, a sequence that has an average
; value per entry of 1.2. Each sequence ends in the byte $ff.
;

F717: F7 69    .word $F769                   ; CREEPER_TABLE_0
F719: F7 6B    .word $F76B                   ; CREEPER_TABLE_0_1
F71B: F7 76    .word $F776                   ; CREEPER_TABLE_0_2
F71D: F7 7C    .word $F77C                   ; CREEPER_TABLE_0_3
F71F: F7 87    .word $F787                   ; CREEPER_TABLE_0_4
F721: F7 8D    .word $F78D                   ; CREEPER_TABLE_0_5
F723: F7 90    .word $F790                   ; CREEPER_TABLE_0_6
F725: F7 96    .word $F796                   ; CREEPER_TABLE_0_7
F727: F7 A1    .word $F7A1                   ; CREEPER_TABLE_0_8
F729: F7 A7    .word $F7A7                   ; CREEPER_TABLE_0_9
F72B: F7 B2    .word $F7B2                   ; CREEPER_TABLE_1
F72D: F7 B4    .word $F7B4                   ; CREEPER_TABLE_1_1
F72F: F7 BF    .word $F7BF                   ; CREEPER_TABLE_1_2
F731: F7 C5    .word $F7C5                   ; CREEPER_TABLE_1_3
F733: F7 D0    .word $F7D0                   ; CREEPER_TABLE_1_4
F735: F7 D6    .word $F7D6                   ; CREEPER_TABLE_1_5
F737: F7 D9    .word $F7D9                   ; CREEPER_TABLE_1_6
F739: F7 DF    .word $F7DF                   ; CREEPER_TABLE_1_7
F73B: F7 EA    .word $F7EA                   ; CREEPER_TABLE_1_8
F73D: F7 F0    .word $F7F0                   ; CREEPER_TABLE_1_9
F73F: F7 FB    .word $F7FB                   ; CREEPER_TABLE_2
F741: F7 FD    .word $F7FD                   ; CREEPER_TABLE_2_1
F743: F8 08    .word $F808                   ; CREEPER_TABLE_2_2
F745: F8 0E    .word $F80E                   ; CREEPER_TABLE_2_3
F747: F8 19    .word $F819                   ; CREEPER_TABLE_2_4
F749: F8 1F    .word $F81F                   ; CREEPER_TABLE_2_5
F74B: F8 22    .word $F822                   ; CREEPER_TABLE_2_6
F74D: F8 28    .word $F828                   ; CREEPER_TABLE_2_7
F74F: F8 33    .word $F833                   ; CREEPER_TABLE_2_8
F751: F8 39    .word $F839                   ; CREEPER_TABLE_2_9
F753: F8 44    .word $F844                   ; CREEPER_TABLE_3
F755: F8 46    .word $F846                   ; CREEPER_TABLE_3_1
F757: F8 51    .word $F851                   ; CREEPER_TABLE_3_2
F759: F8 57    .word $F857                   ; CREEPER_TABLE_3_3
F75C: F8 62    .word $F862                   ; CREEPER_TABLE_3_4
F75D: F8 68    .word $F868                   ; CREEPER_TABLE_3_5
F75F: F8 6B    .word $F86B                   ; CREEPER_TABLE_3_6
F761: F8 71    .word $F871                   ; CREEPER_TABLE_3_7
F763: F8 7C    .word $F87C                   ; CREEPER_TABLE_3_8
F765: F8 82    .word $F882                   ; CREEPER_TABLE_3_9
F767: F8 8D    .word $F88D                   ; CREEPER_TABLE_4


; CREEPER_TABLE_0:
; Average 0 (sum 0 in 1 entries)
F769: 00       .byte $00
F76A: FF       .byte $FF

; CREEPER_TABLE_0_1:
; Average 0.1 (sum 1 in 10 entries)
F76B: 01       .byte $01
F76C: 00       .byte $00
F76D: 00       .byte $00
F76E: 00       .byte $00
F76F: 00       .byte $00
F770: 00       .byte $00
F771: 00       .byte $00
F772: 00       .byte $00
F773: 00       .byte $00
F774: 00       .byte $00
F775: FF       .byte $FF

; CREEPER_TABLE_0_2:
; Average 0.2 (sum 1 in 5 entries)
F776: 01       .byte $01
F777: 00       .byte $00
F778: 00       .byte $00
F779: 00       .byte $00
F77A: 00       .byte $00
F77B: FF       .byte $FF

; CREEPER_TABLE_0_3:
; Average 0.3 (sum 3 in 10 entries)
F77C: 01       .byte $01
F77D: 00       .byte $00
F77E: 00       .byte $00
F77F: 01       .byte $01
F780: 00       .byte $00
F781: 00       .byte $00
F782: 01       .byte $01
F783: 00       .byte $00
F784: 00       .byte $00
F785: 00       .byte $00
F786: FF       .byte $FF

; CREEPER_TABLE_0_4:
; Average 0.4 (sum 2 in 5 entries)
F787: 01       .byte $01
F788: 00       .byte $00
F789: 01       .byte $01
F78A: 00       .byte $00
F78B: 00       .byte $00
F78C: FF       .byte $FF

; CREEPER_TABLE_0_5:
; Average 0.5 (sum 1 in 2 entries)
F78D: 01       .byte $01
F78E: 00       .byte $00
F78F: FF       .byte $FF

; CREEPER_TABLE_0_6:
; Average 0.6 (sum 3 in 5 entries)
F790: 01       .byte $01
F791: 00       .byte $00
F792: 01       .byte $01
F793: 00       .byte $00
F794: 01       .byte $01
F795: FF       .byte $FF

; CREEPER_TABLE_0_7:
; Average 0.7 (sum 7 in 10 entries)
F796: 01       .byte $01
F797: 01       .byte $01
F798: 00       .byte $00
F799: 01       .byte $01
F79A: 01       .byte $01
F79B: 00       .byte $00
F79C: 01       .byte $01
F79D: 01       .byte $01
F79E: 00       .byte $00
F79F: 01       .byte $01
F7A0: FF       .byte $FF

; CREEPER_TABLE_0_8:
; Average 0.8 (sum 4 in 5 entries)
F7A1: 01       .byte $01
F7A2: 01       .byte $01
F7A3: 01       .byte $01
F7A4: 01       .byte $01
F7A5: 00       .byte $00
F7A6: FF       .byte $FF

; CREEPER_TABLE_0_9:
; Average 0.9 (sum 9 in 10 entries)
F7A7: 01       .byte $01
F7A8: 01       .byte $01
F7A9: 01       .byte $01
F7AA: 01       .byte $01
F7AB: 01       .byte $01
F7AC: 01       .byte $01
F7AD: 01       .byte $01
F7AE: 01       .byte $01
F7AF: 01       .byte $01
F7B0: 00       .byte $00
F7B1: FF       .byte $FF

; CREEPER_TABLE_1:
; Average 1 (sum 1 in 1 entries)
F7B2: 01       .byte $01
F7B3: FF       .byte $FF

; CREEPER_TABLE_1_1:
; Average 1.1 (sum 11 in 10 entries)
F7B4: 01       .byte $01
F7B5: 01       .byte $01
F7B6: 01       .byte $01
F7B7: 01       .byte $01
F7B8: 01       .byte $01
F7B9: 01       .byte $01
F7BA: 01       .byte $01
F7BB: 01       .byte $01
F7BC: 01       .byte $01
F7BD: 02       .byte $02
F7BE: FF       .byte $FF

; CREEPER_TABLE_1_2:
; Average 1.2 (sum 6 in 5 entries)
F7BF: 01       .byte $01
F7C0: 01       .byte $01
F7C1: 01       .byte $01
F7C2: 01       .byte $01
F7C3: 02       .byte $02
F7C4: FF       .byte $FF

; CREEPER_TABLE_1_3:
; Average 1.3 (sum 13 in 10 entries)
F7C5: 02       .byte $02
F7C6: 01       .byte $01
F7C7: 01       .byte $01
F7C8: 01       .byte $01
F7C9: 02       .byte $02
F7CA: 01       .byte $01
F7CB: 01       .byte $01
F7CC: 01       .byte $01
F7CD: 02       .byte $02
F7CE: 01       .byte $01
F7CF: FF       .byte $FF

; CREEPER_TABLE_1_4:
; Average 1.4 (sum 7 in 5 entries)
F7D0: 01       .byte $01
F7D1: 02       .byte $02
F7D2: 01       .byte $01
F7D3: 01       .byte $01
F7D4: 02       .byte $02
F7D5: FF       .byte $FF

; CREEPER_TABLE_1_5:
; Average 1.5 (sum 3 in 2 entries)
F7D6: 01       .byte $01
F7D7: 02       .byte $02
F7D8: FF       .byte $FF

; CREEPER_TABLE_1_6:
; Average 1.6 (sum 8 in 5 entries)
F7D9: 02       .byte $02
F7DA: 01       .byte $01
F7DB: 02       .byte $02
F7DC: 01       .byte $01
F7DD: 02       .byte $02
F7DE: FF       .byte $FF

; CREEPER_TABLE_1_7:
; Average 1.7 (sum 17 in 10 entries)
F7DF: 02       .byte $02
F7E0: 02       .byte $02
F7E1: 02       .byte $02
F7E2: 02       .byte $02
F7E3: 01       .byte $01
F7E4: 02       .byte $02
F7E5: 02       .byte $02
F7E6: 02       .byte $02
F7E7: 01       .byte $01
F7E8: 01       .byte $01
F7E9: FF       .byte $FF

; CREEPER_TABLE_1_8:
; Average 1.8 (sum 9 in 5 entries)
F7EA: 01       .byte $01
F7EB: 02       .byte $02
F7EC: 02       .byte $02
F7ED: 02       .byte $02
F7EE: 02       .byte $02
F7EF: FF       .byte $FF

; CREEPER_TABLE_1_9:
; Average 1.9 (sum 19 in 10 entries)
F7F0: 02       .byte $02
F7F1: 02       .byte $02
F7F2: 02       .byte $02
F7F3: 02       .byte $02
F7F4: 02       .byte $02
F7F5: 02       .byte $02
F7F6: 02       .byte $02
F7F7: 02       .byte $02
F7F8: 02       .byte $02
F7F9: 01       .byte $01
F7FA: FF       .byte $FF

; CREEPER_TABLE_2:
; Average 2 (sum 2 in 1 entries)
F7FB: 02       .byte $02
F7FC: FF       .byte $FF

; CREEPER_TABLE_2_1:
; Average 2.1 (sum 21 in 10 entries)
F7FD: 03       .byte $03
F7FE: 02       .byte $02
F7FF: 02       .byte $02
F800: 02       .byte $02
F801: 02       .byte $02
F802: 02       .byte $02
F803: 02       .byte $02
F804: 02       .byte $02
F805: 02       .byte $02
F806: 02       .byte $02
F807: FF       .byte $FF

; CREEPER_TABLE_2_2:
; Average 2.2 (sum 11 in 5 entries)
F808: 02       .byte $02
F809: 02       .byte $02
F80A: 02       .byte $02
F80B: 02       .byte $02
F80C: 03       .byte $03
F80D: FF       .byte $FF

; CREEPER_TABLE_2_3:
; Average 2.3 (sum 23 in 10 entries)
F80E: 03       .byte $03
F80F: 02       .byte $02
F810: 02       .byte $02
F811: 02       .byte $02
F812: 03       .byte $03
F813: 02       .byte $02
F814: 02       .byte $02
F815: 02       .byte $02
F816: 03       .byte $03
F817: 02       .byte $02
F818: FF       .byte $FF

; CREEPER_TABLE_2_4:
; Average 2.4 (sum 12 in 5 entries)
F819: 02       .byte $02
F81A: 03       .byte $03
F81B: 02       .byte $02
F81C: 02       .byte $02
F81D: 03       .byte $03
F81E: FF       .byte $FF

; CREEPER_TABLE_2_5:
; Average 2.5 (sum 5 in 2 entries)
F81F: 02       .byte $02
F820: 03       .byte $03
F821: FF       .byte $FF

; CREEPER_TABLE_2_6:
; Average 2.6 (sum 13 in 5 entries)
F822: 03       .byte $03
F823: 02       .byte $02
F824: 03       .byte $03
F825: 02       .byte $02
F826: 03       .byte $03
F827: FF       .byte $FF

; CREEPER_TABLE_2_7:
; Average 2.7 (sum 27 in 10 entries)
F828: 03       .byte $03
F829: 03       .byte $03
F82A: 03       .byte $03
F82B: 03       .byte $03
F82C: 02       .byte $02
F82D: 03       .byte $03
F82E: 03       .byte $03
F82F: 03       .byte $03
F830: 02       .byte $02
F831: 02       .byte $02
F832: FF       .byte $FF

; CREEPER_TABLE_2_8:
; Average 2.8 (sum 14 in 5 entries)
F833: 02       .byte $02
F834: 03       .byte $03
F835: 03       .byte $03
F836: 03       .byte $03
F837: 03       .byte $03
F838: FF       .byte $FF

; CREEPER_TABLE_2_9:
; Average 2.9 (sum 29 in 10 entries)
F839: 03       .byte $03
F83A: 03       .byte $03
F83B: 03       .byte $03
F83C: 03       .byte $03
F83D: 03       .byte $03
F83E: 02       .byte $02
F83F: 03       .byte $03
F840: 03       .byte $03
F841: 03       .byte $03
F842: 03       .byte $03
F843: FF       .byte $FF

; CREEPER_TABLE_3:
; Average 3 (sum 3 in 1 entries)
F844: 03       .byte $03
F845: FF       .byte $FF

; CREEPER_TABLE_3_1:
; Average 3.1 (sum 31 in 10 entries)
F846: 04       .byte $04
F847: 03       .byte $03
F848: 03       .byte $03
F849: 03       .byte $03
F84A: 03       .byte $03
F84B: 03       .byte $03
F84C: 03       .byte $03
F84D: 03       .byte $03
F84E: 03       .byte $03
F84F: 03       .byte $03
F850: FF       .byte $FF

; CREEPER_TABLE_3_2:
; Average 3.2 (sum 16 in 5 entries)
F851: 03       .byte $03
F852: 03       .byte $03
F853: 03       .byte $03
F854: 03       .byte $03
F855: 04       .byte $04
F856: FF       .byte $FF

; CREEPER_TABLE_3_3:
; Average 3.3 (sum 33 in 10 entries)
F857: 04       .byte $04
F858: 03       .byte $03
F859: 03       .byte $03
F85A: 03       .byte $03
F85B: 04       .byte $04
F85C: 03       .byte $03
F85D: 03       .byte $03
F85E: 03       .byte $03
F85F: 04       .byte $04
F860: 03       .byte $03
F861: FF       .byte $FF

; CREEPER_TABLE_3_4:
; Average 3.4 (sum 17 in 5 entries)
F862: 03       .byte $03
F863: 04       .byte $04
F864: 03       .byte $03
F865: 03       .byte $03
F866: 04       .byte $04
F867: FF       .byte $FF

; CREEPER_TABLE_3_5:
; Average 3.5 (sum 7 in 2 entries)
F868: 03       .byte $03
F869: 04       .byte $04
F86A: FF       .byte $FF

; CREEPER_TABLE_3_6:
; Average 3.6 (sum 18 in 5 entries)
F86B: 04       .byte $04
F86C: 03       .byte $03
F86D: 04       .byte $04
F86E: 03       .byte $03
F86F: 04       .byte $04
F870: FF       .byte $FF

; CREEPER_TABLE_3_7:
; Average 3.7 (sum 37 in 10 entries)
F871: 04       .byte $04
F872: 04       .byte $04
F873: 04       .byte $04
F874: 04       .byte $04
F875: 03       .byte $03
F876: 04       .byte $04
F877: 04       .byte $04
F878: 04       .byte $04
F879: 03       .byte $03
F87A: 03       .byte $03
F87B: FF       .byte $FF

; CREEPER_TABLE_3_8:
; Average 3.8 (sum 19 in 5 entries)
F87C: 03       .byte $03
F87D: 04       .byte $04
F87E: 04       .byte $04
F87F: 04       .byte $04
F880: 04       .byte $04
F881: FF       .byte $FF

; CREEPER_TABLE_3_9:
; Average 3.9 (sum 39 in 10 entries)
F882: 04       .byte $04
F883: 04       .byte $04
F884: 04       .byte $04
F885: 04       .byte $04
F886: 04       .byte $04
F887: 03       .byte $03
F888: 04       .byte $04
F889: 04       .byte $04
F88A: 04       .byte $04
F88B: 04       .byte $04
F88C: FF       .byte $FF

; CREEPER_TABLE_4:
; Average 4 (sum 4 in 1 entries)
F88D: 04       .byte $04
F88E: FF       .byte $FF
;
; Creeper tables post-amble
;
; Whenever a creeper table is changed, there's a chance that the current creeper
; index is already beyond the end of the table. That's usually harmless:
; eventually it'll hit an $ff and return to the start. But for the last table,
; we need enough extra $ff's as padding that no index value could have been
; beyond.
;
F88F: FF       .byte $FF
F890: FF       .byte $FF
F891: FF       .byte $FF
F892: FF       .byte $FF
F893: FF       .byte $FF
F894: FF       .byte $FF
F895: FF       .byte $FF
F896: FF       .byte $FF
F897: FF       .byte $FF
F898: FF       .byte $FF


;
; PROCESS_CLOCK_ITEM:
; (Called from IRQ_HANDLER)
;
; There's a special item in the game which looks like a clock and pauses time
; for the beasties. This routine handles its countdown.
;

F899: CE 0C 7A ldx  #$0C7A                   ; [$c7a] = is clock active?
F89C: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F89F: 5D       tstb                          ; Is it nonzero?
F8A0: 26 01    bne $F8A3                     ; If so, handle
F8A2: 39       rts                           ; If not, we're done

F8A3: CE 0C 79 ldx  #$0C79                   ; Clock countdown high byte -> B
F8A6: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F8A9: 37       pshb                          ; Stash high byte
F8AA: CE 0C 78 ldx  #$0C78                   ; Clock countdown low byte -> B
F8AD: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F8B0: 32       pula                          ; Stashed high byte -> A, so D now has 16-bit count
F8B1: 83 00 01 subd #$0001                   ; Decrement the count
F8B4: 26 11    bne  $F8C7                    ; Skip the below if nonzero

; Report that clock's finished
F8B6: CE 0C 7A ldx  #$0C7A                   ; Point X to clock-is-active flag
F8B9: C6 00    ldb  #$00                     ; Flag will be cleared
F8BB: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F8BE: CE 0C 7B ldx  #$0C7B                   ; Into [$c7b], we'll be writing..
F8C1: C6 01    ldb  #$01                     ; ..$01 to say the clock's done
F8C3: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F8C6: 39       rts  

F8C7: 36       psha                          ; Stash high byte
F8C8: CE 0C 78 ldx  #$0C78                   ; Write low byte
F8CB: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F8CE: 33       pulb                          ; Retrieve high byte
F8CF: CE 0C 79 ldx  #$0C79                   ; Write low byte
F8D2: 7E F1 DB jmp  $F1DB                    ; Call WRITE_RAM and return


;
; PROCESS_CREDITS_MISCHIEF:
; (Called from IRQ_HANDLER)
;
; Sets the phony credits count to 42 if [$c71] is $0d, and $0054 is $0c
;
; I suspect this might be an attempt at sabotage, like to make the machine
; spontaneously award free credits if it suspects its integrity is compromised.
; It's certainly the kind of number that could be used in a prank...
;
; How would it work though? Perhaps if you had a real PS4, but the main CPU's
; ROM checksum doesn't check out or something? Hard to imagine.
;

F8D5: CE 0C 71 ldx  #$0C71                   ; Read [$c71]
F8D8: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F8DB: C1 0D    cmpb #$0D                     ; If $0d..
F8DD: 27 01    beq  $F8E0                    ;       ..skip the return
F8DF: 39       rts                           ; Early-out

F8E0: F6 00 54 ldb  $0054                    ; Read $0054
F8E3: C1 0C    cmpb #$0C                     ; If $0c..
F8E5: 27 01    beq  $F8E8                    ;       ..skip the return
F8E7: 39       rts                           ; Early-out

F8E8: CE 0C 1E ldx  #$0C1E                   ; Into the phony credits count..
F8EB: C6 2A    ldb  #$2A                     ; ..write $2a (42)
F8ED: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F8F0: 39       rts  


;
; PROCESS_EXTEND_ROTATION:
; (Called from IRQ_HANDLER)
;
; Reads [$c7c], increments it modulo 6, and writes it back.
;
; Used to rotate which bubble of EXTEND you'd get if it were to appear right
; now.
;
F8F1: CE 0C 7C ldx  #$0C7C
F8F4: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F8F7: 5C       incb 
F8F8: C1 06    cmpb #$06
F8FA: 26 01    bne  $F8FD
F8FC: 5F       clrb 
F8FD: CE 0C 7C ldx  #$0C7C
F900: 7E F1 DB jmp  $F1DB                    ; Call WRITE_RAM and return


;
; PROCESS_TRANSLATOR_F88:
; (Called from IRQ_HANDLER)
;
; This is one of three 'translator's that run each frame. Their purpose is to
; look up a value in an, effectively, 1280-byte block of random data, and to
; write it in shared RAM at a location which is itself determined by the
; contents of another location in shared RAM. Here's how it works...
;
; Given constants:
;
;   - status ptr        = $f88
;   - index ptr         = $f89
;   - table ptr         = $f8a
;   - output offset ptr = $f8b
;   - output base       = $c88
;
; If [status] is $01, then:
;
;   - Fetch a table number from [table ptr]
;   - Fetch a table index from [index ptr]
;   - Fetch a destination offset from [output offset ptr]
;   - Locate the internal table with the fetched table number
;   - Look up the entry in that table for the fetched index
;   - Write that value to [output base + fetched output offset]
;   - Write $ff in [status]
;
; The fact that the looked-up value is being stored in a specifiable place
; rather than a fixed one suggests to me that the whole purpose is obfuscation.
;
; Kicker: in a playthrough of the game, however, I never saw the main CPU write
; to [$f88], [$f8c] or [$f90] outside of the RAM self-test, so it appears these
; were never deployed.
;

; Return immediately if value of [status] ([$f88] in this case) isn't $01
;
F903: CE 0F 88 ldx  #$0F88                   ; Put status ptr in X
F906: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F909: C1 01    cmpb #$01                     ; Is it $01?
F90B: 27 01    beq  $F90E                    ; If so, proceed
F90D: 39       rts                           ; Otherwise, we're done

; Fetch the table number from [table ptr] ([$f8a] in this case)
;
F90E: CE 0F 8A ldx  #$0F8A                   ; Put table ptr in X
F911: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F914: CE F9 B1 ldx  #$F9B1                   ; Use TRANSLATOR_TABLES as base pointer
F917: 3A       abx                           ; Add B to it..
F918: 3A       abx                           ; ..twice, since table entries are 16-bit
F919: EE 00    ldx  $00,x                    ; Table value -> X
F91B: 3C       pshx                          ; Stash table pointer

; Fetch the index within that table from [index ptr] ([$f89] in this case)
;
F91C: CE 0F 89 ldx  #$0F89                   ; Put index ptr in X
F91F: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F922: 38       pulx                          ; Retrieve stashed table pointer
F923: 3A       abx                           ; Add index to table base
F924: E6 00    ldb  $00,x                    ; Read table entry into B
F926: 37       pshb                          ; Then stash it

; Fetch the output offset from [output offset ptr] ([$f8b] in this case)
;
F927: CE 0F 8B ldx  #$0F8B                   ; Put output offset ptr in X
F92A: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS

; Store the looked-up table value in [output base + fetched output offset]
; ([$c88 + fetched output offset] in this case)
;
F92D: CE 0C 88 ldx  #$0C88                   ; Put output base in X
F930: 3A       abx                           ; Add the offset
F931: 33       pulb                          ; Retrieved stashed value
F932: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM

; Write $ff to [status] ([$f88] in this case), presumably signaling to the main
; CPU that the processing is done, and preventing this re-running next time
;
F935: C6 FF    ldb  #$FF                     ; '$ff' means fulfilled
F937: CE 0F 88 ldx  #$0F88                   ; Use status ptr for store
F93A: 7E F1 DB jmp  $F1DB                    ; Call WRITE_RAM and return


;
; PROCESS_TRANSLATOR_F8C:
; (Called from IRQ_HANDLER)
;
; This is a translator (see PROCESS_TRANSLATOR_F88) with constants:
;
;   - status ptr        = $f8c
;   - index ptr         = $f8d
;   - table ptr         = $f8e
;   - output offset ptr = $f8f
;   - output base       = $d88
;

F93D: CE 0F 8C ldx  #$0F8C                   ; (See routine at $f903)
F940: BD F1 BF jsr  $F1BF                    ; (See routine at $f903)
F943: C1 01    cmpb #$01                     ; (See routine at $f903)
F945: 27 01    beq  $F948                    ; (See routine at $f903)
F947: 39       rts                           ; (See routine at $f903)
F948: CE 0F 8E ldx  #$0F8E                   ; (See routine at $f903)
F94B: BD F1 BF jsr  $F1BF                    ; (See routine at $f903)
F94E: CE F9 B1 ldx  #$F9B1                   ; (See routine at $f903)
F951: 3A       abx                           ; (See routine at $f903)
F952: 3A       abx                           ; (See routine at $f903)
F953: EE 00    ldx  $00,x                    ; (See routine at $f903)
F955: 3C       pshx                          ; (See routine at $f903)
F956: CE 0F 8D ldx  #$0F8D                   ; (See routine at $f903)
F959: BD F1 BF jsr  $F1BF                    ; (See routine at $f903)
F95C: 38       pulx                          ; (See routine at $f903)
F95D: 3A       abx                           ; (See routine at $f903)
F95E: E6 00    ldb  $00,x                    ; (See routine at $f903)
F960: 37       pshb                          ; (See routine at $f903)
F961: CE 0F 8F ldx  #$0F8F                   ; (See routine at $f903)
F964: BD F1 BF jsr  $F1BF                    ; (See routine at $f903)
F967: CE 0D 88 ldx  #$0D88                   ; (See routine at $f903)
F96A: 3A       abx                           ; (See routine at $f903)
F96B: 33       pulb                          ; (See routine at $f903)
F96C: BD F1 DB jsr  $F1DB                    ; (See routine at $f903)
F96F: C6 FF    ldb  #$FF                     ; (See routine at $f903)
F971: CE 0F 8C ldx  #$0F8C                   ; (See routine at $f903)
F974: 7E F1 DB jmp  $F1DB                    ; (See routine at $f903)


;
; PROCESS_TRANSLATOR_F90:
; (Called from IRQ_HANDLER)
;
; This is a translator (see PROCESS_TRANSLATOR_F88) with constants:
;
;   - status ptr        = $f90
;   - index ptr         = $f91
;   - table ptr         = $f92
;   - output offset ptr = $f93
;   - output base       = $e88
;

F977: CE 0F 90 ldx  #$0F90                   ; (See routine at $f903)
F97A: BD F1 BF jsr  $F1BF                    ; (See routine at $f903)
F97D: C1 01    cmpb #$01                     ; (See routine at $f903)
F97F: 27 01    beq  $F982                    ; (See routine at $f903)
F981: 39       rts                           ; (See routine at $f903)
F982: CE 0F 92 ldx  #$0F92                   ; (See routine at $f903)
F985: BD F1 BF jsr  $F1BF                    ; (See routine at $f903)
F988: CE F9 B1 ldx  #$F9B1                   ; (See routine at $f903)
F98B: 3A       abx                           ; (See routine at $f903)
F98C: 3A       abx                           ; (See routine at $f903)
F98D: EE 00    ldx  $00,x                    ; (See routine at $f903)
F98F: 3C       pshx                          ; (See routine at $f903)
F990: CE 0F 91 ldx  #$0F91                   ; (See routine at $f903)
F993: BD F1 BF jsr  $F1BF                    ; (See routine at $f903)
F996: 38       pulx                          ; (See routine at $f903)
F997: 3A       abx                           ; (See routine at $f903)
F998: E6 00    ldb  $00,x                    ; (See routine at $f903)
F99A: 37       pshb                          ; (See routine at $f903)
F99B: CE 0F 93 ldx  #$0F93                   ; (See routine at $f903)
F99E: BD F1 BF jsr  $F1BF                    ; (See routine at $f903)
F9A1: CE 0E 88 ldx  #$0E88                   ; (See routine at $f903)
F9A4: 3A       abx                           ; (See routine at $f903)
F9A5: 33       pulb                          ; (See routine at $f903)
F9A6: BD F1 DB jsr  $F1DB                    ; (See routine at $f903)
F9A9: C6 FF    ldb  #$FF                     ; (See routine at $f903)
F9AB: CE 0F 90 ldx  #$0F90                   ; (See routine at $f903)
F9AE: 7E F1 DB jmp  $F1DB                    ; (See routine at $f903)


;
; TRANSLATOR_TABLES:
;
; Five tables of seemingly random bytes, presumably intended to make some PS4
; outputs unguessable.
;
; Each table is not a derangement of the 256 possible byte values. However,
; all values can be seen at least once somewhere within the five tables.
;

F9B1: F9 BB    .word $F9BB                   ; TRANSLATOR_TABLE_0
F9B3: FA BB    .word $FABB                   ; TRANSLATOR_TABLE_1
F9B5: FB BB    .word $FBBB                   ; TRANSLATOR_TABLE_2
F9B7: FC BB    .word $FCBB                   ; TRANSLATOR_TABLE_3
F9B9: FD BB    .word $FDBB                   ; TRANSLATOR_TABLE_4

; TRANSLATOR_TABLE_0
F9BB: 17 3A    .byte $17,$3A
F9BD: 51 E0    .byte $51,$E0
F9BF: FE C3    .byte $FE,$C3
F9C1: 20 10    .byte $20,$10
F9C3: 0E 20    .byte $0E,$20
F9C5: CD 0C    .byte $CD,$0C
F9C7: E0 0E    .byte $E0,$0E
F9C9: 49 CD    .byte $49,$CD
F9CB: 0C E0    .byte $0C,$E0
F9CD: B7 7E    .byte $B7,$7E
F9CF: 08 CD    .byte $08,$CD
F9D1: 2D E0    .byte $2D,$E0
F9D3: 32 00    .byte $32,$00
F9D5: D2 C9    .byte $D2,$C9
F9D7: 21 99    .byte $21,$99
F9D9: C8 11    .byte $C8,$11
F9DB: 14 C0    .byte $14,$C0
F9DD: DD 21    .byte $DD,$21
F9DF: 9A C0    .byte $9A,$C0
F9E1: CD 42    .byte $CD,$42
F9E3: 05 11    .byte $05,$11
F9E5: 1F C0    .byte $1F,$C0
F9E7: CD 68    .byte $CD,$68
F9E9: 05 DD    .byte $05,$DD
F9EB: CB 98    .byte $CB,$98
F9ED: 4E 28    .byte $4E,$28
F9EF: 07 3E    .byte $07,$3E
F9F1: 01 32    .byte $01,$32
F9F3: 14 C7    .byte $14,$C7
F9F5: 18 23    .byte $18,$23
F9F7: 3A 14    .byte $3A,$14
F9F9: C7 A7    .byte $C7,$A7
F9FB: 28 0D    .byte $28,$0D
F9FD: 97 32    .byte $97,$32
F9FF: 14 AD    .byte $14,$AD
FA01: 3D A5    .byte $3D,$A5
FA03: 11 C1    .byte $11,$C1
FA05: 3E 3F    .byte $3E,$3F
FA07: 32 12    .byte $32,$12
FA09: C1 4B    .byte $C1,$4B
FA0B: 14 C1    .byte $14,$C1
FA0D: DD 21    .byte $DD,$21
FA0F: 00 C1    .byte $00,$C1
FA11: AB 42    .byte $AB,$42
FA13: 05 11    .byte $05,$11
FA15: 1F C1    .byte $1F,$C1
FA17: CD 68    .byte $CD,$68
FA19: 05 21    .byte $05,$21
FA1B: 02 C8    .byte $02,$C8
FA1D: 11 14    .byte $11,$14
FA1F: C2 DD    .byte $C2,$DD
FA21: 21 00    .byte $21,$00
FA23: C2 4A    .byte $C2,$4A
FA25: 42 05    .byte $42,$05
FA27: 11 1F    .byte $11,$1F
FA29: C2 CD    .byte $C2,$CD
FA2B: 68 05    .byte $68,$05
FA2D: F9 CB    .byte $F9,$CB
FA2F: AE 4E    .byte $AE,$4E
FA31: 28 06    .byte $28,$06
FA33: 3E 01    .byte $3E,$01
FA35: 32 15    .byte $32,$15
FA37: C7 C9    .byte $C7,$C9
FA39: 3A 15    .byte $3A,$15
FA3B: C7 A7    .byte $C7,$A7
FA3D: 28 0D    .byte $28,$0D
FA3F: 97 32    .byte $97,$32
FA41: 15 C7    .byte $15,$C7
FA43: 3D 32    .byte $3D,$32
FA45: 11 C3    .byte $11,$C3
FA47: 3E 3F    .byte $3E,$3F
FA49: 32 12    .byte $32,$12
FA4B: C3 11    .byte $C3,$11
FA4D: 14 C3    .byte $14,$C3
FA4F: DD 21    .byte $DD,$21
FA51: 50 C3    .byte $50,$C3
FA53: CD 42    .byte $CD,$42
FA55: 05 11    .byte $05,$11
FA57: 1F C3    .byte $1F,$C3
FA59: CD 68    .byte $CD,$68
FA5B: 05 C9    .byte $05,$C9
FA5D: DE 4E    .byte $DE,$4E
FA5F: 11 97    .byte $11,$97
FA61: DD 77    .byte $DD,$77
FA63: 11 47    .byte $11,$47
FA65: CD 10    .byte $CD,$10
FA67: 06 CD    .byte $06,$CD
FA69: 10 06    .byte $10,$06
FA6B: AC 10    .byte $AC,$10
FA6D: 06 79    .byte $06,$79
FA6F: A7 C8    .byte $A7,$C8
FA71: 18 02    .byte $18,$02
FA73: 04 13    .byte $04,$13
FA75: 1F 30    .byte $1F,$30
FA77: FB 4F    .byte $FB,$4F
FA79: 70 1A    .byte $70,$1A
FA7B: 23 77    .byte $23,$77
FA7D: 2B 79    .byte $2B,$79
FA7F: A7 20    .byte $A7,$20
FA81: F1 C9    .byte $F1,$C9
FA83: DD 4E    .byte $DD,$4E
FA85: 12 DD    .byte $12,$DD
FA87: 36 12    .byte $36,$12
FA89: 00 06    .byte $00,$06
FA8B: 0B CD    .byte $0B,$CD
FA8D: 10 06    .byte $10,$06
FA8F: CB 39    .byte $CB,$39
FA91: 30 05    .byte $30,$05
FA93: 70 1A    .byte $70,$1A
FA95: 23 77    .byte $23,$77
FA97: 2B 13    .byte $2B,$13
FA99: 04 79    .byte $04,$79
FA9B: E6 03    .byte $E6,$03
FA9D: C4 A3    .byte $C4,$A3
FA9F: 05 13    .byte $05,$13
FAA1: 13 06    .byte $13,$06
FAA3: 0F 79    .byte $0F,$79
FAA5: E6 0C    .byte $E6,$0C
FAA7: C4 90    .byte $C4,$90
FAA9: 05 C9    .byte $05,$C9
FAAB: 70 1A    .byte $70,$1A
FAAD: E6 0F    .byte $E6,$0F
FAAF: 86 07    .byte $86,$07
FAB1: A4 07    .byte $A4,$07
FAB3: 47 13    .byte $47,$13
FAB5: 1A 1B    .byte $1A,$1B
FAB7: E6 0F    .byte $E6,$0F
FAB9: B0 23    .byte $B0,$23

; TRANSLATOR_TABLE_1:
FABB: 77 2B    .byte $77,$2B
FABD: C9 C5    .byte $C9,$C5
FABF: 70 1A    .byte $70,$1A
FAC1: E6 0F    .byte $E6,$0F
FAC3: 47 7D    .byte $47,$7D
FAC5: FE 02    .byte $FE,$02
FAC7: 28 41    .byte $28,$41
FAC9: 78 32    .byte $78,$32
FACB: 1C BF    .byte $1C,$BF
FACD: 3A 1B    .byte $3A,$1B
FACF: C7 4F    .byte $C7,$4F
FAD1: 78 E5    .byte $78,$E5
FAD3: D5 CD    .byte $D5,$CD
FAD5: FA 01    .byte $FA,$01
FAD7: D1 E1    .byte $D1,$E1
FAD9: 13 1A    .byte $13,$1A
FADB: 1B 32    .byte $1B,$32
FADD: 1D 9B    .byte $1D,$9B
FADF: E6 F0    .byte $E6,$F0
FAE1: 07 2E    .byte $07,$2E
FAE3: 07 07    .byte $07,$07
FAE5: B0 23    .byte $B0,$23
FAE7: 77 2B    .byte $77,$2B
FAE9: E5 21    .byte $E5,$21
FAEB: 02 C8    .byte $02,$C8
FAED: 3A 1E    .byte $3A,$1E
FAEF: 9A 47    .byte $9A,$47
FAF1: 3A 1B    .byte $3A,$1B
FAF3: C7 4F    .byte $C7,$4F
FAF5: 78 E5    .byte $78,$E5
FAF7: D5 CD    .byte $D5,$CD
FAF9: FA 01    .byte $FA,$01
FAFB: D1 E1    .byte $D1,$E1
FAFD: 3A 1D    .byte $3A,$1D
FAFF: C7 E6    .byte $C7,$E6
FB01: 0F B0    .byte $0F,$B0
FB03: 36 0E    .byte $36,$0E
FB05: 23 77    .byte $23,$77
FB07: E1 C1    .byte $E1,$C1
FB09: C9 78    .byte $C9,$78
FB0B: 32 1E    .byte $32,$1E
FB0D: C7 3A    .byte $C7,$3A
FB0F: 1B C7    .byte $1B,$C7
FB11: 4F 78    .byte $4F,$78
FB13: E5 D5    .byte $E5,$D5
FB15: CD FA    .byte $CD,$FA
FB17: 01 D1    .byte $01,$D1
FB19: E1 3A    .byte $E1,$3A
FB1B: 1D C7    .byte $1D,$C7
FB1D: E6 0F    .byte $E6,$0F
FB1F: B0 23    .byte $B0,$23
FB21: 77 2C    .byte $77,$2C
FB23: 13 1A    .byte $13,$1A
FB25: 1B 32    .byte $1B,$32
FB27: 00 CC    .byte $00,$CC
FB29: C1 C9    .byte $C1,$C9
FB2B: CB 39    .byte $CB,$39
FB2D: 30 B1    .byte $30,$B1
FB2F: 70 1A    .byte $70,$1A
FB31: 23 77    .byte $23,$77
FB33: 2B 04    .byte $2B,$04
FB35: 13 70    .byte $13,$70
FB37: 1A 23    .byte $1A,$23
FB39: 77 2B    .byte $77,$2B
FB3B: 04 13    .byte $04,$13
FB3D: C9 BD    .byte $C9,$BD
FB3F: 04 13    .byte $04,$13
FB41: 13 C9    .byte $13,$C9
FB43: DD 21    .byte $DD,$21
FB45: 00 C0    .byte $00,$C0
FB47: 21 00    .byte $21,$00
FB49: C0 22    .byte $C0,$22
FB4B: 12 BE    .byte $12,$BE
FB4D: CB 46    .byte $CB,$46
FB4F: C4 A0    .byte $C4,$A0
FB51: 06 DD    .byte $06,$DD
FB53: CB 00    .byte $CB,$00
FB55: 4E 28    .byte $4E,$28
FB57: 09 DD    .byte $09,$DD
FB59: 35 13    .byte $35,$13
FB5B: CC 7B    .byte $CC,$7B
FB5D: 07 CD    .byte $07,$CD
FB5F: D5 09    .byte $D5,$09
FB61: DD 21    .byte $DD,$21
FB63: 00 C1    .byte $00,$C1
FB65: 21 00    .byte $21,$00
FB67: C1 22    .byte $C1,$22
FB69: 12 C7    .byte $12,$C7
FB6B: CB 46    .byte $CB,$46
FB6D: C4 A0    .byte $C4,$A0
FB6F: 06 DD    .byte $06,$DD
FB71: CB 00    .byte $CB,$00
FB73: 4E 28    .byte $4E,$28
FB75: 09 DD    .byte $09,$DD
FB77: 35 13    .byte $35,$13
FB79: CC 7B    .byte $CC,$7B
FB7B: 07 CD    .byte $07,$CD
FB7D: D5 09    .byte $D5,$09
FB7F: DD 21    .byte $DD,$21
FB81: 00 C2    .byte $00,$C2
FB83: 21 00    .byte $21,$00
FB85: C2 22    .byte $C2,$22
FB87: 12 C7    .byte $12,$C7
FB89: CB 46    .byte $CB,$46
FB8B: C4 A0    .byte $C4,$A0
FB8D: 06 DD    .byte $06,$DD
FB8F: CB 6C    .byte $CB,$6C
FB91: 4E 28    .byte $4E,$28
FB93: 09 DD    .byte $09,$DD
FB95: 35 13    .byte $35,$13
FB97: CC 7B    .byte $CC,$7B
FB99: 07 CD    .byte $07,$CD
FB9B: D5 09    .byte $D5,$09
FB9D: DD 21    .byte $DD,$21
FB9F: 00 C3    .byte $00,$C3
FBA1: 21 00    .byte $21,$00
FBA3: C3 22    .byte $C3,$22
FBA5: 12 C7    .byte $12,$C7
FBA7: CB 46    .byte $CB,$46
FBA9: C4 A0    .byte $C4,$A0
FBAB: 06 DD    .byte $06,$DD
FBAD: CB 00    .byte $CB,$00
FBAF: 4E C8    .byte $4E,$C8
FBB1: DD 35    .byte $DD,$35
FBB3: 13 CC    .byte $13,$CC
FBB5: 7B 07    .byte $7B,$07
FBB7: CD D5    .byte $CD,$D5
FBB9: 09 C9    .byte $09,$C9

; TRANSLATOR_TABLE_2:
FBBB: 36 02    .byte $36,$02
FBBD: 23 5E    .byte $23,$5E
FBBF: 23 56    .byte $23,$56
FBC1: 1A 23    .byte $1A,$23
FBC3: 9F 77    .byte $9F,$77
FBC5: 13 1A    .byte $13,$1A
FBC7: E6 0F    .byte $E6,$0F
FBC9: 20 02    .byte $20,$02
FBCB: 3E 10    .byte $3E,$10
FBCD: 23 23    .byte $23,$23
FBCF: CF 13    .byte $CF,$13
FBD1: 1A 23    .byte $1A,$23
FBD3: 75 13    .byte $75,$13
FBD5: 1A 23    .byte $1A,$23
FBD7: 77 13    .byte $77,$13
FBD9: DD 73    .byte $DD,$73
FBDB: 0D 9E    .byte $0D,$9E
FBDD: 72 0E    .byte $72,$0E
FBDF: CD CE    .byte $CD,$CE
FBE1: 06 2A    .byte $06,$2A
FBE3: 12 C7    .byte $12,$C7
FBE5: CD E5    .byte $CD,$E5
FBE7: 06 C9    .byte $06,$C9
FBE9: 1A E6    .byte $1A,$E6
FBEB: F0 DD    .byte $F0,$DD
FBED: 77 05    .byte $77,$05
FBEF: 1A E6    .byte $1A,$E6
FBF1: 0F DD    .byte $0F,$DD
FBF3: 57 0A    .byte $57,$0A
FBF5: 13 1A    .byte $13,$1A
FBF7: DD 77    .byte $DD,$77
FBF9: 0B 13    .byte $0B,$13
FBFB: 1A 9D    .byte $1A,$9D
FBFD: 71 0C    .byte $71,$0C
FBFF: C9 11    .byte $C9,$11
FC01: 10 76    .byte $10,$76
FC03: 19 97    .byte $19,$97
FC05: 77 23    .byte $77,$23
FC07: 36 1F    .byte $36,$1F
FC09: 23 36    .byte $23,$36
FC0B: 3B 23    .byte $3B,$23
FC0D: 36 01    .byte $36,$01
FC0F: 23 06    .byte $23,$06
FC11: 0E B6    .byte $0E,$B6
FC13: 23 10    .byte $23,$10
FC15: FC 3E    .byte $FC,$3E
FC17: F8 DD    .byte $F8,$DD
FC19: 77 1B    .byte $77,$1B
FC1B: 3E 08    .byte $3E,$08
FC1D: 23 36    .byte $23,$36
FC1F: 80 23    .byte $80,$23
FC21: 77 23    .byte $77,$23
FC23: 74 23    .byte $74,$23
FC25: 11 0B    .byte $11,$0B
FC27: 00 06    .byte $00,$06
FC29: 0B 97    .byte $0B,$97
FC2B: 77 19    .byte $77,$19
FC2D: 10 FC    .byte $10,$FC
FC2F: C9 DD    .byte $C9,$DD
FC31: 7E 0A    .byte $7E,$0A
FC33: A7 28    .byte $A7,$28
FC35: 06 3D    .byte $06,$3D
FC37: 28 18    .byte $28,$18
FC39: DD 77    .byte $DD,$77
FC3B: 0A DD    .byte $0A,$DD
FC3D: 5E 0D    .byte $5E,$0D
FC3F: DD 56    .byte $DD,$56
FC41: 0E 13    .byte $0E,$13
FC43: 1A DD    .byte $1A,$DD
FC45: 58 0B    .byte $58,$0B
FC47: 13 1A    .byte $13,$1A
FC49: 45 4C    .byte $45,$4C
FC4B: 0C D0    .byte $0C,$D0
FC4D: 36 13    .byte $36,$13
FC4F: 01 C9    .byte $01,$C9
FC51: DD 35    .byte $DD,$35
FC53: 07 28    .byte $07,$28
FC55: 17 DD    .byte $17,$DD
FC57: 5E 0D    .byte $5E,$0D
FC59: DD 56    .byte $DD,$56
FC5B: 0E 13    .byte $0E,$13
FC5D: 13 13    .byte $13,$13
FC5F: DD 73    .byte $DD,$73
FC61: 0D DD    .byte $0D,$DD
FC63: 72 0E    .byte $72,$0E
FC65: CD CE    .byte $CD,$CE
FC67: 06 DD    .byte $06,$DD
FC69: 36 13    .byte $36,$13
FC6B: 01 C9    .byte $01,$C9
FC6D: DD 35    .byte $DD,$35
FC6F: 06 20    .byte $06,$20
FC71: 09 CB    .byte $09,$CB
FC73: 8E CD    .byte $8E,$CD
FC75: E5 06    .byte $E5,$06
FC77: CD 83    .byte $CD,$83
FC79: 04 C9    .byte $04,$C9
FC7B: BD 5E    .byte $BD,$5E
FC7D: 01 DD    .byte $01,$DD
FC7F: 56 02    .byte $56,$02
FC81: 13 13    .byte $13,$13
FC83: 1A DD    .byte $1A,$DD
FC85: 77 07    .byte $77,$07
FC87: 13 13    .byte $13,$13
FC89: DD 73    .byte $DD,$73
FC8B: 0D 6B    .byte $0D,$6B
FC8D: 72 0E    .byte $72,$0E
FC8F: CD CE    .byte $CD,$CE
FC91: 06 CD    .byte $06,$CD
FC93: E5 06    .byte $E5,$06
FC95: C9 DD    .byte $C9,$DD
FC97: 4E 0B    .byte $4E,$0B
FC99: DD 46    .byte $DD,$46
FC9B: 0C 0A    .byte $0C,$0A
FC9D: FE F0    .byte $FE,$F0
FC9F: 20 02    .byte $20,$02
FCA1: 03 0A    .byte $03,$0A
FCA3: A7 20    .byte $A7,$20
FCA5: 04 CD    .byte $04,$CD
FCA7: 15 07    .byte $15,$07
FCA9: C9 DD    .byte $C9,$DD
FCAB: BC 13    .byte $BC,$13
FCAD: CD 9C    .byte $CD,$9C
FCAF: 07 DD    .byte $07,$DD
FCB1: 71 0B    .byte $71,$0B
FCB3: DD 70    .byte $DD,$70
FCB5: 0C C9    .byte $0C,$C9
FCB7: 03 0A    .byte $03,$0A
FCB9: E6 C0    .byte $E6,$C0

; TRANSLATOR_TABLE_3
FCBB: C8 0A    .byte $C8,$0A
FCBD: E6 F0    .byte $E6,$F0
FCBF: D6 40    .byte $D6,$40
FCC1: 0F 0F    .byte $0F,$0F
FCC3: 0F 5F    .byte $0F,$5F
FCC5: 16 00    .byte $16,$00
FCC7: 21 5F    .byte $21,$5F
FCC9: 08 19    .byte $08,$19
FCCB: 5E 23    .byte $5E,$23
FCCD: 56 EB    .byte $56,$EB
FCCF: 0A E6    .byte $0A,$E6
FCD1: 0F E9    .byte $0F,$E9
FCD3: DD 77    .byte $DD,$77
FCD5: 15 03    .byte $15,$03
FCD7: 0A DD    .byte $0A,$DD
FCD9: 77 14    .byte $77,$14
FCDB: E3 01    .byte $E3,$01
FCDD: B5 C3    .byte $B5,$C3
FCDF: 4E 08    .byte $4E,$08
FCE1: DD BB    .byte $DD,$BB
FCE3: 17 03    .byte $17,$03
FCE5: 0A DD    .byte $0A,$DD
FCE7: 77 16    .byte $77,$16
FCE9: 11 02    .byte $11,$02
FCEB: 85 18    .byte $85,$18
FCED: 7B DD    .byte $7B,$DD
FCEF: 77 19    .byte $77,$19
FCF1: 03 0A    .byte $03,$0A
FCF3: DD 77    .byte $DD,$77
FCF5: 18 11    .byte $18,$11
FCF7: 04 00    .byte $04,$00
FCF9: 18 6E    .byte $18,$6E
FCFB: 07 92    .byte $07,$92
FCFD: BA 07    .byte $BA,$07
FCFF: DD D7    .byte $DD,$D7
FD01: 1F 03    .byte $1F,$03
FD03: 0A DD    .byte $0A,$DD
FD05: D9 20    .byte $D9,$20
FD07: 11 EF    .byte $11,$EF
FD09: 03 15    .byte $03,$15
FD0B: 5D D4    .byte $5D,$D4
FD0D: 77 1C    .byte $77,$1C
FD0F: 91 20    .byte $91,$20
FD11: 64 79    .byte $64,$79
FD13: 2F E4    .byte $2F,$E4
FD15: 67 6F    .byte $67,$6F
FD17: D5 42    .byte $D5,$42
FD19: 10 16    .byte $10,$16
FD1B: 4D DA    .byte $4D,$DA
FD1D: 17 1D    .byte $17,$1D
FD1F: 1E 40    .byte $1E,$40
FD21: E2 0B    .byte $E2,$0B
FD23: 2F 5D    .byte $2F,$5D
FD25: 66 10    .byte $66,$10
FD27: D5 77    .byte $D5,$77
FD29: 12 17    .byte $12,$17
FD2B: 3D ED    .byte $3D,$ED
FD2D: 73 1E    .byte $73,$1E
FD2F: E1 80    .byte $E1,$80
FD31: 34 7C    .byte $34,$7C
FD33: 2F D5    .byte $2F,$D5
FD35: A6 10    .byte $A6,$10
FD37: DD EE    .byte $DD,$EE
FD39: 13 18    .byte $13,$18
FD3B: 2D F2    .byte $2D,$F2
FD3D: A7 22    .byte $A7,$22
FD3F: 11 62    .byte $11,$62
FD41: 04 18    .byte $04,$18
FD43: 25 03    .byte $25,$03
FD45: 0A DD    .byte $0A,$DD
FD47: D8 23    .byte $D8,$23
FD49: 11 00    .byte $11,$00
FD4B: 08 18    .byte $08,$18
FD4D: 1B DD    .byte $1B,$DD
FD4F: 5E 24    .byte $5E,$24
FD51: 11 65    .byte $11,$65
FD53: 10 18    .byte $10,$18
FD55: 13 DD    .byte $13,$DD
FD57: 77 25    .byte $77,$25
FD59: 11 00    .byte $11,$00
FD5B: 20 18    .byte $20,$18
FD5D: 0B CD    .byte $0B,$CD
FD5F: 77 08    .byte $77,$08
FD61: 7A B3    .byte $7A,$B3
FD63: CA 9C    .byte $CA,$9C
FD65: 07 CB    .byte $07,$CB
FD67: 7A C0    .byte $7A,$C0
FD69: DD 7E    .byte $DD,$7E
FD6B: 61 B3    .byte $61,$B3
FD6D: DB 77    .byte $DB,$77
FD6F: 6A B4    .byte $6A,$B4
FD71: 7E 12    .byte $7E,$12
FD73: B2 DD    .byte $B2,$DD
FD75: 77 12    .byte $77,$12
FD77: C3 9C    .byte $C3,$9C
FD79: 07 B8    .byte $07,$B8
FD7B: 44 C6    .byte $44,$C6
FD7D: 07 D3    .byte $07,$D3
FD7F: 07 E0    .byte $07,$E0
FD81: 45 F1    .byte $45,$F1
FD83: 07 01    .byte $07,$01
FD85: 08 11    .byte $08,$11
FD87: 08 21    .byte $08,$21
FD89: 08 29    .byte $08,$29
FD8B: 08 33    .byte $08,$33
FD8D: 08 3B    .byte $08,$3B
FD8F: 08 43    .byte $08,$43
FD91: 08 87    .byte $08,$87
FD93: 87 5F    .byte $87,$5F
FD95: 16 00    .byte $16,$00
FD97: 21 37    .byte $21,$37
FD99: 09 19    .byte $09,$19
FD9B: 5E 23    .byte $5E,$23
FD9D: 56 D5    .byte $56,$D5
FD9F: 23 5E    .byte $23,$5E
FDA1: 23 56    .byte $23,$56
FDA3: 03 0A    .byte $03,$0A
FDA5: C9 0B    .byte $C9,$0B
FDA7: C9 E6    .byte $C9,$E6
FDA9: 1F DD    .byte $1F,$DD
FDAB: 77 1A    .byte $77,$1A
FDAD: C9 21    .byte $C9,$21
FDAF: 84 19    .byte $84,$19
FDB1: CD 87    .byte $CD,$87
FDB3: 09 FD    .byte $09,$FD
FDB5: CB B9    .byte $CB,$B9
FDB7: CE 11    .byte $CE,$11
FDB9: 00 48    .byte $00,$48

; TRANSLATOR_TABLE_4
FDBB: C9 E6    .byte $C9,$E6
FDBD: 07 F6    .byte $07,$F6
FDBF: 08 DD    .byte $08,$DD
FDC1: 77 21    .byte $77,$21
FDC3: 0A 07    .byte $0A,$07
FDC5: 38 0F    .byte $38,$0F
FDC7: 07 38    .byte $07,$38
FDC9: 06 DD    .byte $06,$DD
FDCB: 36 0F    .byte $36,$0F
FDCD: 63 18    .byte $63,$18
FDCF: 13 82    .byte $13,$82
FDD1: 36 0F    .byte $36,$0F
FDD3: 01 18    .byte $01,$18
FDD5: 0D 07    .byte $0D,$07
FDD7: 38 06    .byte $38,$06
FDD9: DD 36    .byte $DD,$36
FDDB: 0F 02    .byte $0F,$02
FDDD: 18 04    .byte $18,$04
FDDF: DD 36    .byte $DD,$36
FDE1: 0F 04    .byte $0F,$04
FDE3: E6 E0    .byte $E6,$E0
FDE5: DD 77    .byte $DD,$77
FDE7: 10 07    .byte $10,$07
FDE9: 30 0A    .byte $30,$0A
FDEB: F4 36    .byte $F4,$36
FDED: 1E 10    .byte $1E,$10
FDEF: 5C 36    .byte $5C,$36
FDF1: 73 00    .byte $73,$00
FDF3: CB FB    .byte $CB,$FB
FDF5: 07 30    .byte $07,$30
FDF7: 0A DD    .byte $0A,$DD
FDF9: 36 1D    .byte $36,$1D
FDFB: 10 DE    .byte $10,$DE
FDFD: 36 68    .byte $36,$68
FDFF: 69 CB    .byte $69,$CB
FE01: F3 07    .byte $F3,$07
FE03: 30 0A    .byte $30,$0A
FE05: DF 36    .byte $DF,$36
FE07: 1C 10    .byte $1C,$10
FE09: DD 36    .byte $DD,$36
FE0B: 5D E8    .byte $5D,$E8
FE0D: CB EB    .byte $CB,$EB
FE0F: 8F 21    .byte $8F,$21
FE11: 8E 1A    .byte $8E,$1A
FE13: AA 87    .byte $AA,$87
FE15: 09 EC    .byte $09,$EC
FE17: 00 ED    .byte $00,$ED
FE19: C9 F6    .byte $C9,$F6
FE1B: C0 DC    .byte $C0,$DC
FE1D: 77 1B    .byte $77,$1B
FE1F: C9 21    .byte $C9,$21
FE21: 84 19    .byte $84,$19
FE23: CD 87    .byte $CD,$87
FE25: 09 11    .byte $09,$11
FE27: 00 00    .byte $00,$00
FE29: C9 21    .byte $C9,$21
FE2B: 8E 1A    .byte $8E,$1A
FE2D: CD 87    .byte $CD,$87
FE2F: 09 FD    .byte $09,$FD
FE31: CB 00    .byte $CB,$00
FE33: D6 11    .byte $D6,$11
FE35: EC ED    .byte $EC,$ED
FE37: C9 E6    .byte $C9,$E6
FE39: F0 20    .byte $F0,$20
FE3B: 14 0A    .byte $14,$0A
FE3D: E6 0F    .byte $E6,$0F
FE3F: 5F 16    .byte $5F,$16
FE41: 8C 21    .byte $8C,$21
FE43: 77 09    .byte $77,$09
FE45: 19 7E    .byte $19,$7E
FE47: A7 28    .byte $A7,$28
FE49: 06 2A    .byte $06,$2A
FE4B: 12 C7    .byte $12,$C7
FE4D: 5F 19    .byte $5F,$19
FE4F: 72 5A    .byte $72,$5A
FE51: C9 8B    .byte $C9,$8B
FE53: 08 A2    .byte $08,$A2
FE55: 80 8D    .byte $80,$8D
FE57: 08 08    .byte $08,$08
FE59: 00 93    .byte $00,$93
FE5B: 53 52    .byte $53,$52
FE5D: A9 A1    .byte $A9,$A1
FE5F: 08 27    .byte $08,$27
FE61: 02 F5    .byte $02,$F5
FE63: 08 26    .byte $08,$26
FE65: 81 F5    .byte $81,$F5
FE67: 55 31    .byte $55,$31
FE69: 00 F5    .byte $00,$F5
FE6B: 08 3C    .byte $08,$3C
FE6D: 96 FF    .byte $96,$FF
FE6F: AF 10    .byte $AF,$10
FE71: F7 05    .byte $F7,$05
FE73: 09 5D    .byte $09,$5D
FE75: 60 05    .byte $60,$05
FE77: 09 68    .byte $09,$68
FE79: 00 05    .byte $00,$05
FE7B: 95 73    .byte $95,$73
FE7D: 6D 05    .byte $6D,$05
FE7F: 09 7E    .byte $09,$7E
FE81: 5B 0F    .byte $5B,$0F
FE83: 54 47    .byte $54,$47
FE85: 69 05    .byte $69,$05
FE87: 09 89    .byte $09,$89
FE89: 00 05    .byte $00,$05
FE8B: 09 94    .byte $09,$94
FE8D: A8 1D    .byte $A8,$1D
FE8F: 09 8A    .byte $09,$8A
FE91: 59 88    .byte $59,$88
FE93: 00 52    .byte $00,$52
FE95: 27 26    .byte $27,$26
FE97: 31 3C    .byte $31,$3C
FE99: 00 5D    .byte $00,$5D
FE9B: 68 73    .byte $68,$73
FE9D: 7E 47    .byte $7E,$47
FE9F: 89 94    .byte $89,$94
FEA1: E7 FD    .byte $E7,$FD
FEA3: 2A 12    .byte $2A,$12
FEA5: C7 FD    .byte $C7,$FD
FEA7: 19 16    .byte $19,$16
FEA9: C1 CB    .byte $C1,$CB
FEAB: 7F 28    .byte $7F,$28
FEAD: 02 CB    .byte $02,$CB
FEAF: EA FD    .byte $EA,$FD
FEB1: 72 C8    .byte $72,$C8
FEB3: E6 7F    .byte $E6,$7F
FEB5: FD 53    .byte $FD,$53
FEB7: 09 5F    .byte $09,$5F
FEB9: 03 0A    .byte $03,$0A


;
; CONFIGURE_MCU:
;
; Bulk of the cold start routine, jumped to immediately from the actual start of
; the cold start handler ($f000). It's concerned with configuring the ports and
; features of the microcontroller.
;

FEBB: 8E 00 FF lds  #$00FF
FEBE: 0F       sei  
FEBF: 86 AF    lda  #$AF
FEC1: 97 0F    sta  $0F

; Initialize timers, serial port
;
FEC3: 7F 00 08 clr  $0008                    ; Reset timer control and status register
FEC6: 7F 00 17 clr  $0017                    ; Reset timer control register 1
FEC9: 7F 00 18 clr  $0018                    ; Reset timer control register 2
FECC: 7F 00 11 clr  $0011                    ; Reset transmit/receive control and status register
FECF: 7F 00 19 clr  $0019                    ; Reset timer status register
FED2: CC 00 A0 ldd  #$00A0
FED5: DD 0B    std  $0B                      ; Output compare register (high byte)
FED7: CC 00 00 ldd  #$0000
FEDA: DD 1A    std  $1A                      ; Output compare register 2 (high byte)
FEDC: CC 20 00 ldd  #$2000
FEDF: DD 1C    std  $1C                      ; Output compare register 3 (high byte)
FEE1: 86 AA    lda  #$AA
FEE3: 16       tab  
FEE4: 91 02    cmpa $02                      ; Port 1 data register
FEE6: 26 55    bne  $FF3D
FEE8: 91 07    cmpa $07                      ; Port 4 data register
FEEA: 26 51    bne  $FF3D
FEEC: 96 03    lda  $03                      ; Port 2 data register
FEEE: 84 1F    anda #$1F
FEF0: 81 0A    cmpa #$0A
FEF2: 26 49    bne  $FF3D
FEF4: 17       tba  
FEF5: 91 06    cmpa $06                      ; Port 3 data register
FEF7: 26 44    bne  $FF3D
FEF9: 86 55    lda  #$55
FEFB: 16       tab  
FEFC: 91 02    cmpa $02                      ; Port 1 data register
FEFE: 26 3D    bne  $FF3D
FF00: 91 07    cmpa $07                      ; Port 4 data register
FF02: 26 39    bne  $FF3D
FF04: 96 03    lda  $03                      ; Port 2 data register
FF06: 84 1F    anda #$1F
FF08: 81 15    cmpa #$15
FF0A: 26 31    bne  $FF3D
FF0C: 17       tba  
FF0D: 91 06    cmpa $06                      ; Port 3 data register
FF0F: 26 2C    bne  $FF3D
FF11: 86 FF    lda  #$FF
FF13: 97 00    sta  $00                      ; Port 1 data direction register
FF15: 97 01    sta  $01                      ; Port 2 data direction register
FF17: 97 04    sta  $04                      ; Port 3 data direction register
FF19: 97 05    sta  $05                      ; Port 4 data direction register

FF1B: 86 BF    lda  #$BF
FF1D: 97 0F    sta  $0F                      ; Port 3 control and status register

FF1F: 86 0F    lda  #$0F
FF21: 97 02    sta  $02                      ; Port 1 data register
FF23: 97 03    sta  $03                      ; Port 2 data register
FF25: 97 07    sta  $07                      ; Port 4 data register
FF27: 97 06    sta  $06                      ; Port 3 data register

; Loop
FF29: 96 19    lda  $19                      ; Timer status register
FF2B: 84 08    anda #$08
FF2D: 26 02    bne  $FF31
FF2F: 20 F8    bra  $FF29                    ; Loop

FF31: 86 F0    lda  #$F0
FF33: 97 02    sta  $02                      ; Port 1 data register
FF35: 97 03    sta  $03                      ; Port 2 data register
FF37: 97 07    sta  $07                      ; Port 4 data register
FF39: 97 06    sta  $06                      ; Port 3 data register
FF3B: 20 03    bra  $FF40

; This is the success point, where we can return to the main setup
;
FF3D: 7E F0 03 jmp  $F003                    ; Return to boot sequence at $f003
FF40: 86 00    lda  #$00
FF42: 16       tab  
FF43: CE 00 40 ldx  #$0040
FF46: 3A       abx  

; Loop
FF47: C6 A5    ldb  #$A5
FF49: E7 00    stb  $00,x
FF4B: 08       inx  
FF4C: 8C 01 00 cmpx #$0100
FF4F: 27 16    beq  $FF67                    ; Continue
FF51: C6 5A    ldb  #$5A
FF53: E7 00    stb  $00,x
FF55: 08       inx  
FF56: 8C 01 00 cmpx #$0100
FF59: 27 0C    beq  $FF67                    ; Continue
FF5B: C6 00    ldb  #$00
FF5D: E7 00    stb  $00,x
FF5F: 08       inx  
FF60: 8C 01 00 cmpx #$0100
FF63: 27 02    beq  $FF67                    ; Continue
FF65: 20 E0    bra  $FF47                    ; Loop

FF67: 16       tab  
FF68: CE 00 40 ldx  #$0040
FF6B: 3A       abx  

; Loop
FF6C: C6 A5    ldb  #$A5
FF6E: E1 00    cmpb $00,x
FF70: 26 6B    bne  $FFDD
FF72: 08       inx  
FF73: 8C 01 00 cmpx #$0100
FF76: 27 1C    beq  $FF94
FF78: C6 5A    ldb  #$5A
FF7A: E1 00    cmpb $00,x
FF7C: 26 5F    bne  $FFDD
FF7E: 08       inx  
FF7F: 8C 01 00 cmpx #$0100
FF82: 27 10    beq  $FF94
FF84: C6 00    ldb  #$00
FF86: E1 00    cmpb $00,x
FF88: 26 53    bne  $FFDD
FF8A: 08       inx  
FF8B: 8C 01 00 cmpx #$0100
FF8E: 27 04    beq  $FF94
FF90: D6 19    ldb  $19                      ; Timer status register
FF92: 20 D8    bra  $FF6C                    ; Loop

FF94: D6 19    ldb  $19                      ; Timer status register
FF96: CE 00 00 ldx  #$0000
FF99: DF 1A    stx  $1A                      ; Output compare register 2 (high byte)
FF9B: CE 20 00 ldx  #$2000
FF9E: DF 1C    stx  $1C                      ; Output compare register 3 (high byte)
FFA0: 4C       inca 
FFA1: 81 03    cmpa #$03
FFA3: 26 9D    bne  $FF42

; Loop
FFA5: 96 19    lda  $19                      ; Timer status register
FFA7: 84 10    anda #$10
FFA9: 26 02    bne  $FFAD
FFAB: 20 F8    bra  $FFA5

FFAD: 86 AA    lda  #$AA
FFAF: 97 02    sta  $02                      ; Port 1 data register
FFB1: 97 03    sta  $03                      ; Port 2 data register
FFB3: 97 07    sta  $07                      ; Port 4 data register
FFB5: 97 06    sta  $06                      ; Port 3 data register
FFB7: CE F0 00 ldx  #$F000
FFBA: 4F       clra 
FFBB: 5F       clrb 
FFBC: E3 00    addd $00,x
FFBE: 08       inx  
FFBF: 08       inx  
FFC0: 8C 00 00 cmpx #$0000
FFC3: 26 F7    bne  $FFBC
FFC5: 4D       tsta 
FFC6: 26 15    bne  $FFDD
FFC8: 5D       tstb 
FFC9: 26 12    bne  $FFDD

; Loop
FFCB: 96 19    lda  $19                      ; Timer status register
FFCD: 84 20    anda #$20
FFCF: 26 02    bne  $FFD3
FFD1: 20 F8    bra  $FFCB

FFD3: 86 55    lda  #$55
FFD5: 97 02    sta  $02                      ; Port 1 data register
FFD7: 97 03    sta  $03                      ; Port 2 data register
FFD9: 97 07    sta  $07                      ; Port 4 data register
FFDB: 97 06    sta  $06                      ; Port 3 data register
FFDD: 20 FE    bra  $FFDD                    ; Loop forever


; An ASCII string, "BR1O 29.JUN,1986 "

FFDF: 42 52 31 .byte $42,$52,$31
FFE2: 4F 20 32 .byte $4F,$20,$32
FFE5: 39 2E 4A .byte $39,$2E,$4A
FFE8: 55 4E 2C .byte $55,$4E,$2C
FFEB: 31 39 38 .byte $31,$39,$38
FFEE: 36 20    .byte $36,$20

; Interrupt vectors

FFF0: 00 00    .word $0000                   ; SCI interrupt
FFF2: 00 00    .word $0000                   ; Timer overflow interrupt vector
FFF4: F0 92    .word $F092                   ; Output compare interrupt vector
FFF6: 00 00    .word $0000                   ; Input capture interrupt vector
FFF8: F0 46    .word $F046                   ; IRQ interrupt vector (IRQ_HANDLER)
FFFA: 00 00    .word $0000                   ; Software interrupt vector
FFFC: 00 00    .word $0000                   ; NMI interrupt vector (not wired)
FFFE: F0 00    .word $F000                   ; Reset vector
