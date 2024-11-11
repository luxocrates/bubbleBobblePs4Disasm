;
; Annotated disassembly of Bubble Bobble's PS4 chip
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
;     cabinet switches
;   - informing the beasties of where the players are
;   - rotating which EXTEND bubbles the players are given
;   - effecting functionality for the clock special item
;   - generating interrupts on the main CPU
;   - ...and likely more (how does wind speed factor in, for example?)
;
; Suffice it to say, one does not _need_ a microcontroller to do any of the above.
; The PS4's real purpose is to move some vital functionality behind an opaque
; curtain. It also appears from the code below that Taito had intended for the
; PS4 to have additional functionality (killing the player if they touch a
; beastie, and maybe handling the credit count), but showstopper bugs forced
; those to be handled on the main CPU instead.
;
;
; The 6801U4 is a microcontroller variant of the 6800 microprocessor, with 4KiB
; of mask ROM and 192 bytes of RAM. If you're not familiar with 6800/6801
; assembly (I wasn't), be aware that:
;
; - Registers A and B can be used together as a 16-bit register, in which case 
;   they're called D.
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
; [$c1e](r)  - Phony credit counter
;              (Independently-tracked credit count; not used by main CPU)
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
;
; [$c26](rw) - Unknown (routine at $f3e3)
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
; [$c72](r)  - Unknown (routine at $f67f) (always reads 0 in my experience)
; [$c73](w)  - Unknown (routine at $f67f) (always writes 0 in my experience)
; [$c74](r)  - Unknown (routine at $f67f) (always reads 0 in my experience)
; [$c75](w)  - Unknown (routine at $f67f) (always writes 0 in my experience)
; [$c76](r)  - Wind speed
; [$c77](w)  - Seems to toggle rapidly between 0 and 1 in gameplay
; ------------------------------------------------------------------------------
; [$c78](rw) - Clock downcounter low byte
; [$c79](rw) - Clock downcounter high byte
; [$c7a](rw) - Clock is active (if not $00)
; [$c7b](w)  - Clock countdown complete, if PS4 writes $01
; ------------------------------------------------------------------------------
; [$c7c](rw) - Which EXTEND bubble the player would be offered if one appeared
;              right now
; [$c7d](w)  - I/O error reporting. PS4 writes $01 on error.
; [$c7e](rw) - Unknown (routine at $f3e3)
; [$c7f](r)  - Input for dead code at $f216-$f235. Maybe for debugging.
; [$c80](r)  - Unknown (routine at $f6f1)
; [$c81](w)  - Unknown (routine at $f6f1)
; [$c82](w)  - PS4 checksum high byte (game will report error if nonzero)
; [$c83](w)  - PS4 checksum low byte  (game will report error if nonzero)
; [$c85](w)  - PS4 ready reporting. Main CPU waits for PS4 to write $37 here.
;
; ------------------------------------------------------------------------------
;
; Whatever's going on with..          [$f88]-[$f8b] and [$c88], at $f903
;   ..mirrors what's happening with.. [$f8c]-[$f8f] and [$d88], at $f93d
;   ..which also mirrors..            [$f90]-[$f93] and [$e88], at $f977
;
; [$c88](w)  - Unknown (routine at $f903)
; [$d88](w)  - Unknown (routine at $f93d)
; [$e88](w)  - Unknown (routine at $f977)
;
; [$f88](r)  - Unknown (routine at $f903)
; [$f89](r)  - Unknown (routine at $f903)
; [$f8a](r)  - Unknown (routine at $f903)
; [$f8b](r)  - Unknown (routine at $f903)
;
; [$f8c](rw) - Unknown (routine at $f93d)
; [$f8d](r)  - Unknown (routine at $f93d)
; [$f8e](r)  - Unknown (routine at $f93d)
; [$f8f](r)  - Unknown (routine at $f93d)
;
; [$f90](rw) - Unknown (routine at $f977)
; [$f91](r)  - Unknown (routine at $f977)
; [$f92](r)  - Unknown (routine at $f977)
; [$f93](r)  - Unknown (routine at $f977)
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
; [$f98](r)  - Generate main CPU interrupts, if $47
; [$f99](w)  - Coin/credit related, but CPU doesn't seem affected if suppressed
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
; $0043:         Unknown (used at $f0b3)
; $004a, $004b:  Scratch (last shared RAM address read from or written to.)
; 0004c, $004d:  (Used only by dead code at $f216-$f235)
; $004e:         Cached controls/DIPs byte 0
; $004f:         Cached controls/DIPs byte 1 (but never retrieved)
; $0050:         Cached controls/DIPs byte 2 (but never retrieved)
; $0051:         Cached controls/DIPs byte 3 (but never retrieved)
; $0052:         Unknown, see $f2e7 et al
; $0053:         Parallel of $0052
; $0054:         Unknown (credits related?)
; $0055:         Current player Y position
; $0056:         Current player X position
; $0057:         Number of beastie currently being processed
; $0058, $0059:  Input structure pointer for current beastie
; $005a, $005b:  Output structure pointer for current beastie
; $005c:         Beastie Y overlap accumulator
; $005f:         Used in wind speed routine
;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Code!

; Cold start entrypoint
F000: 7E FE BB jmp  $FEBB
F003: 8E 00 FF lds  #$00FF                   ; Set stack pointer
F006: 0F       sei                           ; Disable interrupts
F007: 86 F0    lda  #$F0
F009: 97 00    sta  $00                      ; Set port 1 data direction register
F00B: 86 FF    lda  #$FF
F00D: 97 01    sta  $01                      ; Set port 2 data direction register
F00F: 97 04    sta  $04                      ; Set port 3 data direction register
F011: 97 05    sta  $05                      ; Set port 4 data direction register
F013: 86 BF    lda  #$BF                     ; Store $b3..
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
F04C: BD F0 92 jsr  $F092
F04F: BD F1 B0 jsr  $F1B0                    ; Call PROCESS_COIN_LOCKOUTS
F052: BD F2 A7 jsr  $F2A7
F055: BD F3 47 jsr  $F347
F058: BD F3 E3 jsr  $F3E3
F05B: BD F4 8F jsr  $F48F                    ; Call PROCESS_P1_BEASTIES
F05E: BD F5 85 jsr  $F585                    ; Call PROCESS_P2_BEASTIES
F061: BD F6 7F jsr  $F67F
F064: BD F6 CB jsr  $F6CB
F067: BD F6 F1 jsr  $F6F1
F06A: BD F8 99 jsr  $F899                    ; Call PROCESS_CLOCK_ITEM
F06D: BD F8 D5 jsr  $F8D5
F070: BD F8 F1 jsr  $F8F1                    ; Call BUMP_EXTEND
F073: BD F9 03 jsr  $F903
F076: BD F9 3D jsr  $F93D
F079: BD F9 77 jsr  $F977
F07C: BD F2 99 jsr  $F299                    ; Call LISTEN_FOR_RESET

F07F: CE 0F 96 ldx  #$0F96                   ; Read [$f96]
F082: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F085: C1 47    cmpb #$47                     ; If 71..
F087: 27 08    beq  $F091                    ;      ..skip the cycle burn
F089: CC 01 70 ldd  #$0170                   ; Burn cycles: iterate through $170 (368) empty loops
F08C: 83 00 01 subd #$0001
F08F: 26 FB    bne  $F08C
F091: 3B       rti                           ; Done. Return to IDLE.


;
; A routine called from the main interrupt handler, and pointed to by the
; vector at $fff4 (output compare interrupt vector)
;
; This part reads [$f98], and returns if it doesn't get the $47 magic number
; there that it expects. (See also $f1f8)
;

F092: CE 0F 98 ldx  #$0F98
F095: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F098: C1 47    cmpb #$47
F09A: 27 01    beq  $F09D
F09C: 39       rts  

; This seems to be configuring the I/O ports, then later goes on to do a whole
; lot of stuff with the phony credit counter
F09D: CE 00 40 ldx  #$0040                   ; X = $0040, for upcoming subroutine
F0A0: 96 02    lda  $02                      ; Read port 1 (cabinet)
F0A2: 48       asla                          ; Rotate until inputs TILT, SERVICE, COIN A, COIN B..
F0A3: 48       asla                          ; ..
F0A4: 48       asla                          ; ..are in bits 7-4..
F0A5: 48       asla                          ; ..and bits 3-0 are empty
F0A6: C6 03    ldb  #$03                     ; Set loop counter to 3

; Loop start
F0A8: 36       psha 
F0A9: 37       pshb 
F0AA: BD F1 6F jsr  $F16F
F0AD: 33       pulb 
F0AE: 32       pula 
F0AF: 48       asla 
F0B0: 5A       decb 
F0B1: 26 F5    bne  $F0A8

F0B3: B6 00 43 lda  $0043
F0B6: 81 00    cmpa #$00
F0B8: 26 39    bne  $F0F3
F0BA: F6 00 4E ldb  $004E                    
F0BD: 54       lsrb 
F0BE: 54       lsrb 
F0BF: 54       lsrb 

; I'm seeing this getting reached the moment a coin's inserted. I suspect we're
; looking up the coins/credits table...
;
F0C0: C4 06    andb #$06
F0C2: CE F1 87 ldx  #$F187                   ; data table pointer
F0C5: 3A       abx  
F0C6: A6 00    lda  $00,x
F0C8: 81 01    cmpa #$01
F0CA: 27 0D    beq  $F0D9
F0CC: 7C 00 48 inc  $0048
F0CF: A6 00    lda  $00,x
F0D1: B1 00 48 cmpa $0048
F0D4: 26 1D    bne  $F0F3
F0D6: 7F 00 48 clr  $0048
F0D9: A6 01    lda  $01,x
F0DB: 36       psha 
F0DC: CE 0C 1E ldx  #$0C1E
F0DF: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F0E2: 32       pula 
F0E3: 1B       aba  
F0E4: 16       tab  
F0E5: CE 0C 1E ldx  #$0C1E
F0E8: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F0EB: CE 0F 99 ldx  #$0F99
F0EE: C6 01    ldb  #$01
F0F0: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F0F3: B6 00 41 lda  $0041
F0F6: 81 00    cmpa #$00
F0F8: 26 3B    bne  $F135
F0FA: F6 00 4E ldb  $004E
F0FD: 54       lsrb                          ; Shift B right until it's..
F0FE: 54       lsrb                          ; ..
F0FF: 54       lsrb                          ; ..
F100: 54       lsrb                          ; ..
F101: 54       lsrb                          ; ..a 3-bit number
F102: C4 06    andb #$06                     ; Then zero-out the LSB
F104: CE F1 87 ldx  #$F187                   ; Data table pointer
F107: 3A       abx  
F108: A6 00    lda  $00,x
F10A: 81 01    cmpa #$01
F10C: 27 0D    beq  $F11B
F10E: 7C 00 49 inc  $0049
F111: A6 00    lda  $00,x
F113: B1 00 49 cmpa $0049
F116: 26 1D    bne  $F135
F118: 7F 00 49 clr  $0049
F11B: A6 01    lda  $01,x
F11D: 36       psha 
F11E: CE 0C 1E ldx  #$0C1E
F121: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F124: 32       pula 
F125: 1B       aba  
F126: 16       tab  
F127: CE 0C 1E ldx  #$0C1E
F12A: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F12D: CE 0F 99 ldx  #$0F99
F130: C6 01    ldb  #$01
F132: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F135: B6 00 45 lda  $0045
F138: 81 00    cmpa #$00
F13A: 26 1A    bne  $F156
F13C: CE 0C 1E ldx  #$0C1E
F13F: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F142: 86 08    lda  #$08
F144: 11       cba  
F145: 25 1A    bcs  $F161                    ; If carry, do ENABLE_COIN_LOCKOUTS and return
F147: 5C       incb 
F148: CE 0C 1E ldx  #$0C1E
F14B: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F14E: CE 0F 99 ldx  #$0F99
F151: C6 01    ldb  #$01
F153: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F156: CE 0C 1E ldx  #$0C1E
F159: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F15C: 86 08    lda  #$08
F15E: 11       cba  
F15F: 24 07    bcc  $F168                    ; If not carry, do DISABLE_COIN_LOCKOUTS and return
; Falls through...


;
; ENABLE_COIN_LOCKOUTS:
;
; Configures the coin mechs to not accept more coins
;

F161: 86 EF    lda  #$EF                     ; Create a mask for bit 4 ('OUT' for port 1)
F163: 94 02    anda $02                      ; AND port 1's current value
F165: 97 02    sta  $02                      ; Write it to port 1
F167: 39       rts  


;
; DISABLE_COIN_LOCKOUTS:
;
; Configures the coin mechs to accept more coins
;

F168: 86 10    lda  #$10                     ; Create a pattern for bit 4 ('OUT' for port 1)
F16A: 9A 02    ora  $02                      ; OR port 1's current value
F16C: 97 02    sta  $02                      ; Write it to port 1
F16E: 39       rts  

;
; Called during init, from $f0aa
;

F16F: B7 00 46 sta  $0046                    ; Store cabinet inputs in addr $0046
F172: E6 00    ldb  $00,x                    ; ($0040) -> B
F174: A7 00    sta  $00,x                    ; Store cabinet inputs in (X) (X = $0040)
F176: 4F       clra 
F177: 58       aslb 
F178: 25 01    bcs  $F17B
F17A: 4C       inca 
F17B: 78 00 46 asl  $0046
F17E: 24 02    bcc  $F182
F180: 4C       inca 
F181: 4C       inca 
F182: A7 01    sta  $01,x
F184: 08       inx  
F185: 08       inx  
F186: 39       rts  

;
; A table, accessed from $f0c2 and $f104. But in both cases, before the table
; is derefernced, the index is ANDed with 6, meaning every other byte is
; unreachable. Why?
;
; My guess is this relates to the x coins/y credits DIP switch settings
;
F187: 02       .byte $02
F188: 01       .byte $01
F189: 02       .byte $02
F18A: 03       .byte $03
F18B: 01       .byte $01
F18C: 02       .byte $02
F18D: 01       .byte $01
F18E: 01       .byte $01


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
; A routine called from the main interrupt handler. Receives signals from the
; main CPU to enable or disable the coin lockouts. The game engages the lockouts
; once the ninth credit has been inserted, disengaging it as soon as the game
; then starts.
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

; Put out the address with /SORAM low. Then set /SORAM high to kick off the request
;
F1C8: FF 00 4A stx  $004A                    ; Stash shared RAM address in $004a
F1CB: FC 00 4A ldd  $004A                    ; Maybe just to move X to A and B?
F1CE: 84 0F    anda #$0F                     ; Mask out upper nibble of address
F1D0: D7 07    stb  $07                      ; Put address low byte on port 4 (address bus lower)
F1D2: 97 03    sta  $03                      ; Put address high byte on port 2 (address bus upper)
F1D4: 8A 10    ora  #$10                     ; Set /SORAM output bit (tells IC12 PAL of a request)
F1D6: 97 03    sta  $03                      ; Add that to port 2
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
; The first routine called from the main interrupt handler. This generates an
; interrupt on the main CPU, but only if the magic number $47 has been written
; to [$f98].
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
;
; A routine called from the main interrupt handler and at startup
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
; test. The game code expects the value reported here to be $0000; it it isn't,
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

F288: 36       psha                          ; Save A (one byte of the checksum)
F289: CE 0C 83 ldx  #$0C83                   ; Store the other byte to [$c83]
F28C: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F28F: 33       pulb                          ; Retrieve stored A
F290: CE 0C 82 ldx  #$0C82                   ; Store it in [$c82]
F293: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F296: 39       rts  
;
; Given that there are exactly 2 bytes between CHECKSUM and the following
; routine, and that the checksum is a 2-byte value, and that nothing tries
; jumping to either of them, I think it's a safe bet that these are the checksum
; balancing bytes: the values needed to force the sum to be zero.
;
F297: 08 38    .byte $08,$38


;
; LISTEN_FOR_RESET:
; Begins a warm boot of the PS4 if [$f97] == $4a
;
; A routine called from the main interrupt handler
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
; A routine called from the main interrupt handler
;
; Does work depending on value of [$c6f].  I don't know what that's for: in
; practice, I've only ever seen it report zero.
;
; Mirrored in $f347, with different constants
;

F2A7: CE 0C 6F ldx  #$0C6F                   ; We'll be reading [$c70]
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
F2BD: CE 0F 95 ldx  #$0F95
F2C0: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F2C3: C1 42    cmpb #$42
F2C5: 26 0C    bne  $F2D3                    ; rts

; [$f95] was $42. Read [$c24]. If it doesn't match contents of addr $52, push the
; accumulator onto the stack and then try rts. Which would be sure to fail
; because the top of the stack just had the accumulator pushed to it. So this
; is pretty puzzling.

F2C7: CE 0C 24 ldx  #$0C24
F2CA: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F2CD: F1 00 52 cmpb $0052
F2D0: 27 01    beq  $F2D3
F2D2: 36       psha 
F2D3: 39       rts  

; Reached when [$c6f] == $01
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
F32F: C6 0A    ldb  #$0A
F331: F7 00 52 stb  $0052
F334: CE 0C 24 ldx  #$0C24
F337: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F33A: CE 0C 6F ldx  #$0C6F
F33D: C6 00    ldb  #$00
F33F: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F342: 39       rts  

; A small table, called from $f380 and $f2e0
F343: 01       .byte $01
F344: 00       .byte $00
F345: 04       .byte $04
F346: 02       .byte $02


;
; A routine called from the main interrupt handler
;
; Appears to parallel the routine at $f2a7, but for [$c70] instead of [$c6f]
;

F347: CE 0C 70 ldx  #$0C70                   ; Other routine used [$c6f]
F34A: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS

F34D: C1 01    cmpb #$01                     ; If $01..
F34F: 27 23    beq  $F374                    ;       ..jump to $f374
F351: C1 02    cmpb #$02                     ; If $02..
F353: 27 44    beq  $F399                    ;       ..jump to $f399
F355: C1 04    cmpb #$04                     ; If $04..
F357: 27 5D    beq  $F3B6                    ;       ..jump to $f3b6
F359: C1 08    cmpb #$08                     ; If $08..
F35B: 27 72    beq  $F3CF                    ;       ..jump to $f3cf

; [$c70] wasn't 1, 2, 4 or 8.
; If [$f95] != $42 (66), skip to return
F35D: CE 0F 95 ldx  #$0F95
F360: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F363: C1 42    cmpb #$42
F365: 26 0C    bne  $F373

; [$f95] was $42. Read [$c25]. If it doesn't match contents of addr $0053, push
; the accumulator onto the stack and then try rts. Which would be sure to fail
; because the top of the stack just had the accumulator pushed to it. So this
; is pretty puzzling.
;
F367: CE 0C 25 ldx  #$0C25
F36A: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F36D: F1 00 53 cmpb $0053
F370: 27 01    beq  $F373
F372: 36       psha 
F373: 39       rts  

; Handles [$c70] being 1
F374: CE 00 01 ldx  #$0001
F377: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F37A: 54       lsrb 
F37B: 54       lsrb 
F37C: 54       lsrb 
F37D: 54       lsrb 
F37E: C4 03    andb #$03
F380: CE F3 43 ldx  #$F343                   ; A small table
F383: 3A       abx  
F384: A6 00    lda  $00,x
F386: 16       tab  
F387: F7 00 53 stb  $0053
F38A: CE 0C 25 ldx  #$0C25
F38D: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F390: CE 0C 70 ldx  #$0C70
F393: C6 00    ldb  #$00
F395: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F398: 39       rts  

; Handles [$c70] being 2
F399: CE 0C 25 ldx  #$0C25
F39C: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F39F: C1 0A    cmpb #$0A
F3A1: 27 0A    beq  $F3AD
F3A3: 5C       incb 
F3A4: F7 00 53 stb  $0053
F3A7: CE 0C 25 ldx  #$0C25
F3AA: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F3AD: CE 0C 70 ldx  #$0C70
F3B0: C6 00    ldb  #$00
F3B2: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F3B5: 39       rts  

; Handles [$c70] being 4
F3B6: CE 0C 25 ldx  #$0C25
F3B9: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F3BC: 5A       decb 
F3BD: F7 00 53 stb  $0053
F3C0: CE 0C 25 ldx  #$0C25
F3C3: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F3C6: CE 0C 70 ldx  #$0C70
F3C9: C6 00    ldb  #$00
F3CB: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F3CE: 39       rts  

; Handles [$c70] being 8
F3CF: C6 0A    ldb  #$0A
F3D1: F7 00 53 stb  $0053
F3D4: CE 0C 25 ldx  #$0C25
F3D7: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F3DA: CE 0C 70 ldx  #$0C70
F3DD: C6 00    ldb  #$00
F3DF: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F3E2: 39       rts  


;
; A routine called from the main interrupt handler
;
; This one is dispatching multiple ways depending on the value of
; [$c7e], which in my playthrough only ever reported zero.
;

F3E3: CE 0C 7E ldx  #$0C7E
F3E6: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F3E9: C1 01    cmpb #$01
F3EB: 27 2F    beq  $F41C
F3ED: C1 02    cmpb #$02
F3EF: 27 3F    beq  $F430
F3F1: C1 04    cmpb #$04
F3F3: 27 54    beq  $F449
F3F5: C1 08    cmpb #$08
F3F7: 27 66    beq  $F45F
F3F9: C1 10    cmpb #$10
F3FB: 27 6E    beq  $F46B
F3FD: C1 20    cmpb #$20
F3FF: 27 76    beq  $F477
F401: C1 40    cmpb #$40
F403: 27 7E    beq  $F483

; Reached only if [$c7e] was $00, $80, or not a power of two
F405: CE 0F 95 ldx  #$0F95
F408: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F40B: C1 42    cmpb #$42
F40D: 26 0C    bne  $F41B
F40F: CE 0C 26 ldx  #$0C26
F412: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F415: F1 00 54 cmpb $0054
F418: 27 01    beq  $F41B                    ; This is odd.. 
F41A: 36       psha                          ; ..we're conditionally pushing to the stack. Won't that screw the rts?
F41B: 39       rts  

; Reached if [$c7e] was $01
F41C: CE 0C 26 ldx  #$0C26
F41F: C6 00    ldb  #$00
F421: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F424: 7F 00 54 clr  $0054
F427: CE 0C 7E ldx  #$0C7E
F42A: C6 00    ldb  #$00
F42C: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F42F: 39       rts  

; Reached if [$c7e] was $02
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

; Reached if [$c7e] was $04
F449: CE 0C 26 ldx  #$0C26
F44C: C6 31    ldb  #$31
F44E: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F451: C6 31    ldb  #$31

; Common ending for this handler and the few that follow
F453: F7 00 54 stb  $0054
F456: CE 0C 7E ldx  #$0C7E
F459: C6 00    ldb  #$00
F45B: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F45E: 39       rts  

; Reached if [$c7e] was $08
F45F: CE 0C 26 ldx  #$0C26
F462: C6 62    ldb  #$62
F464: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F467: C6 62    ldb  #$62
F469: 20 E8    bra  $F453

; Reached if [$c7e] was $10
F46B: CE 0C 26 ldx  #$0C26
F46E: C6 63    ldb  #$63
F470: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F473: C6 63    ldb  #$63
F475: 20 DC    bra  $F453

; Reached if [$c7e] was $20
F477: CE 0C 26 ldx  #$0C26
F47A: C6 64    ldb  #$64
F47C: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F47F: C6 64    ldb  #$64
F481: 20 D0    bra  $F453

; Reached if [$c7e] was $40
F483: CE 0C 26 ldx  #$0C26
F486: C6 65    ldb  #$65
F488: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F48B: C6 65    ldb  #$65
F48D: 20 C4    bra  $F453


;
; PROCESS_P1_BEASTIES:
;
; A routine called from the main interrupt handler
;
; This is for player 1. Note that the code in $f585 onwards does player 2,
; and is virtually identical.
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
F56E: C4 01    andb #$01                     ; Echoing what happened at $F4C6..
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
;
; A routine called from the main interrupt handler
;
; This is for player 2. Note that the code in $f48f onwards does player 1,
; and is virtually identical, the only differences being a few of the pointers
; and some extra increments so data can be stored after the P1 data.
;
; So below I'm only commenting on the differences.
;

F585: CE 0C 67 ldx  #$0C67                   ; Was [$c5f] for P1
F588: BD F1 BF jsr  $F1BF                    ; (see routine at $f48f)
F58B: C4 01    andb #$01                     ; (see routine at $f48f)
F58D: C1 01    cmpb #$01                     ; (see routine at $f48f)
F58F: 27 01    beq  $F592                    ; (see routine at $f48f)
F591: 39       rts                           ; (see routine at $f48f)
F592: 7F 00 57 clr  $0057                    ; (see routine at $f48f)
F595: CE 0C 68 ldx  #$0C68                   ; Was [$c60] for P1
F598: BD F1 BF jsr  $F1BF                    ; (see routine at $f48f)
F59B: F7 00 55 stb  $0055                    ; (see routine at $f48f)
F59E: CE 0C 69 ldx  #$0C69                   ; Was [$c61] for P1
F5A1: BD F1 BF jsr  $F1BF                    ; (see routine at $f48f)
F5A4: F7 00 56 stb  $0056                    ; (see routine at $f48f)
F5A7: CC 0C 01 ldd  #$0C01                   ; (see routine at $f48f)
F5AA: FD 00 58 std  $0058                    ; (see routine at $f48f)
F5AD: CC 0C 27 ldd  #$0C27                   ; (see routine at $f48f)
F5B0: FD 00 5A std  $005A                    ; (see routine at $f48f)
F5B3: 7F 00 5C clr  $005C                    ; (see routine at $f48f)
F5B6: FE 00 58 ldx  $0058                    ; (see routine at $f48f)
F5B9: BD F1 BF jsr  $F1BF                    ; (see routine at $f48f)
F5BC: C4 01    andb #$01                     ; (see routine at $f48f)
F5BE: C1 01    cmpb #$01                     ; (see routine at $f48f)
F5C0: 27 03    beq  $F5C5                    ; (see routine at $f48f)
F5C2: 7E F6 37 jmp  $F637                    ; (see routine at $f48f)
F5C5: FE 00 58 ldx  $0058                    ; (see routine at $f48f)
F5C8: 08       inx                           ; (see routine at $f48f)
F5C9: BD F1 BF jsr  $F1BF                    ; (see routine at $f48f)
F5CC: B6 00 55 lda  $0055                    ; (see routine at $f48f)
F5CF: 10       sba                           ; (see routine at $f48f)
F5D0: 27 0B    beq  $F5DD                    ; (see routine at $f48f)
F5D2: 24 05    bcc  $F5D9                    ; (see routine at $f48f)
F5D4: C6 01    ldb  #$01                     ; (see routine at $f48f)
F5D6: 40       nega                          ; (see routine at $f48f)
F5D7: 20 06    bra  $F5DF                    ; (see routine at $f48f)
F5D9: C6 00    ldb  #$00                     ; (see routine at $f48f)
F5DB: 20 02    bra  $F5DF                    ; (see routine at $f48f)
F5DD: C6 80    ldb  #$80                     ; (see routine at $f48f)
F5DF: FE 00 5A ldx  $005A                    ; (see routine at $f48f)
F5E2: 08       inx                           ; Not present for P1
F5E3: 36       psha                          ; (see routine at $f48f)
F5E4: BD F1 DB jsr  $F1DB                    ; (see routine at $f48f)
F5E7: FE 00 5A ldx  $005A                    ; (see routine at $f48f)
F5EA: 08       inx                           ; (see routine at $f48f)
F5EB: 08       inx                           ; (see routine at $f48f)
F5EC: 08       inx                           ; (see routine at $f48f)
F5ED: 08       inx                           ; (see routine at $f48f)
F5EE: 08       inx                           ; Not present for P1
F5EF: 32       pula                          ; (see routine at $f48f)
F5F0: 36       psha                          ; (see routine at $f48f)
F5F1: 16       tab                           ; (see routine at $f48f)
F5F2: BD F1 DB jsr  $F1DB                    ; (see routine at $f48f)
F5F5: 32       pula                          ; (see routine at $f48f)
F5F6: 81 08    cmpa #$08                     ; (see routine at $f48f)
F5F8: 24 03    bcc  $F5FD                    ; (see routine at $f48f)
F5FA: 7C 00 5C inc  $005C                    ; (see routine at $f48f)
F5FD: FE 00 58 ldx  $0058                    ; (see routine at $f48f)
F600: 08       inx                           ; (see routine at $f48f)
F601: 08       inx                           ; (see routine at $f48f)
F602: BD F1 BF jsr  $F1BF                    ; (see routine at $f48f)
F605: B6 00 56 lda  $0056                    ; (see routine at $f48f)
F608: 10       sba                           ; (see routine at $f48f)
F609: 27 0B    beq  $F616                    ; (see routine at $f48f)
F60B: 24 05    bcc  $F612                    ; (see routine at $f48f)
F60D: C6 01    ldb  #$01                     ; (see routine at $f48f)
F60F: 40       nega                          ; (see routine at $f48f)
F610: 20 06    bra  $F618                    ; (see routine at $f48f)
F612: C6 00    ldb  #$00                     ; (see routine at $f48f)
F614: 20 02    bra  $F618                    ; (see routine at $f48f)
F616: C6 80    ldb  #$80                     ; (see routine at $f48f)
F618: FE 00 5A ldx  $005A                    ; (see routine at $f48f)
F61B: 08       inx                           ; (see routine at $f48f)
F61C: 08       inx                           ; (see routine at $f48f)
F61D: 08       inx                           ; Not present for P1
F61E: 36       psha                          ; (see routine at $f48f)
F61F: BD F1 DB jsr  $F1DB                    ; (see routine at $f48f)
F622: FE 00 5A ldx  $005A                    ; (see routine at $f48f)
F625: 08       inx                           ; (see routine at $f48f)
F626: 08       inx                           ; (see routine at $f48f)
F627: 08       inx                           ; (see routine at $f48f)
F628: 08       inx                           ; (see routine at $f48f)
F629: 08       inx                           ; (see routine at $f48f)
F62A: 08       inx                           ; (see routine at $f48f)
F62B: 08       inx                           ; Not present for P1
F62C: 32       pula                          ; (see routine at $f48f)
F62D: 36       psha                          ; (see routine at $f48f)
F62E: 16       tab                           ; (see routine at $f48f)
F62F: BD F1 DB jsr  $F1DB                    ; (see routine at $f48f)
F632: 32       pula                          ; (see routine at $f48f)
F633: 81 08    cmpa #$08                     ; (see routine at $f48f)
F635: 25 26    bcs  $F65D                    ; (see routine at $f48f)
F637: FE 00 58 ldx  $0058                    ; (see routine at $f48f)
F63A: 08       inx                           ; (see routine at $f48f)
F63B: 08       inx                           ; (see routine at $f48f)
F63C: 08       inx                           ; (see routine at $f48f)
F63D: 08       inx                           ; (see routine at $f48f)
F63E: FF 00 58 stx  $0058                    ; (see routine at $f48f)
F641: FE 00 5A ldx  $005A                    ; (see routine at $f48f)
F644: 08       inx                           ; (see routine at $f48f)
F645: 08       inx                           ; (see routine at $f48f)
F646: 08       inx                           ; (see routine at $f48f)
F647: 08       inx                           ; (see routine at $f48f)
F648: 08       inx                           ; (see routine at $f48f)
F649: 08       inx                           ; (see routine at $f48f)
F64A: 08       inx                           ; Not present for P1
F64B: 08       inx                           ; Not present for P1
F64C: FF 00 5A stx  $005A                    ; (see routine at $f48f)
F64F: 7C 00 57 inc  $0057                    ; (see routine at $f48f)
F652: B6 00 57 lda  $0057                    ; (see routine at $f48f)
F655: 81 07    cmpa #$07                     ; (see routine at $f48f)
F657: 27 03    beq  $F65C                    ; (see routine at $f48f)
F659: 7E F5 B6 jmp  $F5B6                    ; (see routine at $f48f)
F65C: 39       rts                           ; (see routine at $f48f)
F65D: 7D 00 5C tst  $005C                    ; (see routine at $f48f)
F660: 27 FA    beq  $F65C                    ; (see routine at $f48f)
F662: CE 0C 67 ldx  #$0C67                   ; (see routine at $f48f)
F665: BD F1 BF jsr  $F1BF                    ; (see routine at $f48f)
F668: C4 01    andb #$01                     ; (see routine at $f48f)
F66A: C1 01    cmpb #$01                     ; (see routine at $f48f)
F66C: 26 EE    bne  $F65C                    ; (see routine at $f48f)
F66E: CE 0C 6A ldx  #$0C6A                   ; (see routine at $f48f)
F671: C6 01    ldb  #$01                     ; (see routine at $f48f)
F673: BD F1 DB jsr  $F1DB                    ; (see routine at $f48f)
F676: F6 00 57 ldb  $0057                    ; (see routine at $f48f)
F679: CE 0C 6B ldx  #$0C6B                   ; (see routine at $f48f)
F67C: 7E F1 DB jmp  $F1DB                    ; (see routine at $f48f)


;
; A routine called from the main interrupt handler
;

F67F: CE 0C 72 ldx  #$0C72
F682: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS

; This is a table lookup
F685: CE F7 17 ldx  #$F717
F688: 3A       abx  
F689: 3A       abx  
F68A: EE 00    ldx  $00,x
F68C: F6 00 5D ldb  $005D
F68F: 3A       abx  
F690: A6 00    lda  $00,x
F692: 81 FF    cmpa #$FF
F694: 26 05    bne  $F69B
F696: 7F 00 5D clr  $005D
F699: 20 E4    bra  $F67F
F69B: 7C 00 5D inc  $005D
F69E: 16       tab  
F69F: CE 0C 73 ldx  #$0C73
F6A2: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F6A5: CE 0C 74 ldx  #$0C74
F6A8: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F6AB: CE F7 17 ldx  #$F717
F6AE: 3A       abx  
F6AF: 3A       abx  
F6B0: EE 00    ldx  $00,x
F6B2: F6 00 5E ldb  $005E
F6B5: 3A       abx  
F6B6: A6 00    lda  $00,x
F6B8: 81 FF    cmpa #$FF
F6BA: 26 05    bne  $F6C1
F6BC: 7F 00 5E clr  $005E
F6BF: 20 E4    bra  $F6A5
F6C1: 7C 00 5E inc  $005E
F6C4: 16       tab  
F6C5: CE 0C 75 ldx  #$0C75
F6C8: 7E F1 DB jmp  $F1DB                    ; Call WRITE_RAM and return


;
; A routine called from the main interrupt handler
;
; I wonder if this is toggling [$c77] at a speed related to the wind speed
;

F6CB: CE 0C 76 ldx  #$0C76                   ; [$c76] is the wind speed value
F6CE: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F6D1: CE F7 17 ldx  #$F717                   ; Point X to table base
F6D4: 3A       abx                           ; X += B
F6D5: 3A       abx                           ; X += B
F6D6: EE 00    ldx  $00,x                    ; Load table value into X
F6D8: F6 00 5F ldb  $005F
F6DB: 3A       abx                           ; X += B
F6DC: A6 00    lda  $00,x                    ; Looks like the table was a table of tables!
F6DE: 81 FF    cmpa #$FF
F6E0: 26 05    bne  $F6E7
F6E2: 7F 00 5F clr  $005F
F6E5: 20 E4    bra  $F6CB                    ; Loop to start of this routine

F6E7: 7C 00 5F inc  $005F
F6EA: 16       tab  
F6EB: CE 0C 77 ldx  #$0C77
F6EE: 7E F1 DB jmp  $F1DB                    ; Call WRITE_RAM and return


;
; A routine called from the main interrupt handler
;

F6F1: CE 0C 80 ldx  #$0C80
F6F4: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F6F7: CE F7 17 ldx  #$F717
F6FA: 3A       abx  
F6FB: 3A       abx  
F6FC: EE 00    ldx  $00,x
F6FE: F6 00 60 ldb  $0060
F701: 3A       abx  
F702: A6 00    lda  $00,x
F704: 81 FF    cmpa #$FF
F706: 26 05    bne  $F70D
F708: 7F 00 60 clr  $0060
F70B: 20 E4    bra  $F6F1
F70D: 7C 00 60 inc  $0060
F710: 16       tab  
F711: CE 0C 81 ldx  #$0C81
F714: 7E F1 DB jmp  $F1DB                    ; Call WRITE_RAM and return


; A table for code at $f685

F717: F7 69    .word $F769
F719: F7 6B    .word $F76B
F71B: F7 76    .word $F776
F71D: F7 7C    .word $F77C
F71F: F7 87    .word $F787
F721: F7 8D    .word $F78D
F723: F7 90    .word $F790
F725: F7 96    .word $F796
F727: F7 A1    .word $F7A1
F729: F7 A7    .word $F7A7
F72B: F7 B2    .word $F7B2
F72D: F7 B4    .word $F7B4
F72F: F7 BF    .word $F7BF
F731: F7 C5    .word $F7C5
F733: F7 D0    .word $F7D0
F735: F7 D6    .word $F7D6
F737: F7 D9    .word $F7D9
F739: F7 DF    .word $F7DF
F73B: F7 EA    .word $F7EA
F73D: F7 F0    .word $F7F0
F73F: F7 FB    .word $F7FB
F741: F7 FD    .word $F7FD
F743: F8 08    .word $F808
F745: F8 0E    .word $F80E
F747: F8 19    .word $F819
F749: F8 1F    .word $F81F
F74B: F8 22    .word $F822
F74D: F8 28    .word $F828
F74F: F8 33    .word $F833
F751: F8 39    .word $F839
F753: F8 44    .word $F844
F755: F8 46    .word $F846
F757: F8 51    .word $F851
F759: F8 57    .word $F857 
F75C: F8 62    .word $F862
F75D: F8 68    .word $F868
F75F: F8 6B    .word $F86B
F761: F8 71    .word $F871
F763: F8 7C    .word $F87C
F765: F8 82    .word $F882
F767: F8 8D    .word $F88D

; I think there might now follow a whole sequence of tables with one-byte values, not .word's

F769: 00 FF    .word $00FF
F76B: 01 00    .word $0100
F76D: 00 00    .word $0000
F76F: 00 00    .word $0000
F771: 00 00    .word $0000
F773: 00 00    .word $0000
F775: FF 01    .word $FF01
F777: 00 00    .word $0000
F779: 00 00    .word $0000
F77B: FF 01    .word $FF01
F77D: 00 00    .word $0000
F77F: 01 00    .word $0100
F781: 00 01    .word $0001
F783: 00 00    .word $0000
F785: 00 FF    .word $00FF
F787: 01 00    .word $0100
F789: 01 00    .word $0100
F78B: 00 FF    .word $00FF
F78D: 01 00    .word $0100
F78F: FF 01    .word $FF01
F791: 00 01    .word $0001
F793: 00 01    .word $0001
F795: FF 01    .word $FF01
F797: 01 00    .word $0100
F799: 01 01    .word $0101
F79B: 00 01    .word $0001
F79D: 01 00    .word $0100
F79F: 01 FF    .word $01FF
F7A1: 01 01    .word $0101
F7A3: 01 01    .word $0101
F7A5: 00 FF    .word $00FF
F7A7: 01 01    .word $0101
F7A9: 01 01    .word $0101
F7AB: 01 01    .word $0101
F7AD: 01 01    .word $0101
F7AF: 01 00    .word $0100
F7B1: FF 01    .word $FF01
F7B3: FF 01    .word $FF01
F7B5: 01 01    .word $0101
F7B7: 01 01    .word $0101
F7B9: 01 01    .word $0101
F7BB: 01 01    .word $0101
F7BD: 02 FF    .word $02FF
F7BF: 01 01    .word $0101
F7C1: 01 01    .word $0101
F7C3: 02 FF    .word $02FF
F7C5: 02 01    .word $0201
F7C7: 01 01    .word $0101
F7C9: 02 01    .word $0201
F7CB: 01 01    .word $0101
F7CD: 02 01    .word $0201
F7CF: FF 01    .word $FF01
F7D1: 02 01    .word $0201
F7D3: 01 02    .word $0102
F7D5: FF 01    .word $FF01
F7D7: 02 FF    .word $02FF
F7D9: 02 01    .word $0201
F7DB: 02 01    .word $0201
F7DD: 02 FF    .word $02FF
F7DF: 02 02    .word $0202
F7E1: 02 02    .word $0202
F7E3: 01 02    .word $0102
F7E5: 02 02    .word $0202
F7E7: 01 01    .word $0101
F7E9: FF 01    .word $FF01
F7EB: 02 02    .word $0202
F7ED: 02 02    .word $0202
F7EF: FF 02    .word $FF02
F7F1: 02 02    .word $0202
F7F3: 02 02    .word $0202
F7F5: 02 02    .word $0202
F7F7: 02 02    .word $0202
F7F9: 01 FF    .word $01FF
F7FB: 02 FF    .word $02FF
F7FD: 03 02    .word $0302
F7FF: 02 02    .word $0202
F801: 02 02    .word $0202
F803: 02 02    .word $0202
F805: 02 02    .word $0202
F807: FF 02    .word $FF02
F809: 02 02    .word $0202
F80B: 02 03    .word $0203
F80D: FF 03    .word $FF03
F80F: 02 02    .word $0202
F811: 02 03    .word $0203
F813: 02 02    .word $0202
F815: 02 03    .word $0203
F817: 02 FF    .word $02FF
F819: 02 03    .word $0203
F81B: 02 02    .word $0202
F81D: 03 FF    .word $03FF
F81F: 02 03    .word $0203
F821: FF 03    .word $FF03
F823: 02 03    .word $0203
F825: 02 03    .word $0203
F827: FF 03    .word $FF03
F829: 03 03    .word $0303
F82B: 03 02    .word $0302
F82D: 03 03    .word $0303
F82F: 03 02    .word $0302
F831: 02 FF    .word $02FF
F833: 02 03    .word $0203
F835: 03 03    .word $0303
F837: 03 FF    .word $03FF
F839: 03 03    .word $0303
F83B: 03 03    .word $0303
F83D: 03 02    .word $0302
F83F: 03 03    .word $0303
F841: 03 03    .word $0303
F843: FF 03    .word $FF03
F845: FF 04    .word $FF04
F847: 03 03    .word $0303
F849: 03 03    .word $0303
F84B: 03 03    .word $0303
F84D: 03 03    .word $0303
F84F: 03 FF    .word $03FF
F851: 03 03    .word $0303
F853: 03 03    .word $0303
F855: 04 FF    .word $04FF
F857: 04 03    .word $0403
F859: 03 03    .word $0303
F85B: 04 03    .word $0403
F85D: 03 03    .word $0303
F85F: 04 03    .word $0403
F861: FF 03    .word $FF03
F863: 04 03    .word $0403
F865: 03 04    .word $0304
F867: FF 03    .word $FF03
F869: 04 FF    .word $04FF
F86B: 04 03    .word $0403
F86D: 04 03    .word $0403
F86F: 04 FF    .word $04FF
F871: 04 04    .word $0404
F873: 04 04    .word $0404
F875: 03 04    .word $0304
F877: 04 04    .word $0404
F879: 03 03    .word $0303
F87B: FF 03    .word $FF03
F87D: 04 04    .word $0404
F87F: 04 04    .word $0404
F881: FF 04    .word $FF04
F883: 04 04    .word $0404
F885: 04 04    .word $0404
F887: 03 04    .word $0304
F889: 04 04    .word $0404
F88B: 04 FF    .word $04FF
F88D: 04 FF    .word $04FF
F88F: FF FF    .word $FFFF
F891: FF FF    .word $FFFF
F893: FF FF    .word $FFFF
F895: FF FF    .word $FFFF
F897: FF FF    .word $FFFF


;
; PROCESS_CLOCK_ITEM:
;
; A routine called from the main interrupt handler
;
; There's a special item in the game which looks like a clock and pauses time
; for the beasties. This routine handles its countdown.
;

F899: CE 0C 7A ldx  #$0C7A
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
; A routine called from the main interrupt handler
;
; If I'm understanding this correctly, it's inserting 42 credits on some weird
; eventuality.
;
; But although [$c1e] seems to hold the remaining credits, the CPU doesn't seem
; to act on it. It has its own counter, which [$c1e] kinda mirrors, but changing
; [$c1e] seems to have no effect. So maybe they meant for the MCU to track
; credits, but then abandoned that work and had the CPU do it.
;
; I suspect this writing 42 to it might have been an act of sabotage, like to
; make the machine spontaneously award free credits if it suspects its integrity
; is compromised. It's certainly the kind of number that could be used in a
; prank...
;
; How would it work though? Perhaps if you had a real PS4, but the main CPU's
; ROM checksum doesn't check out or something? Hard to imagine.
;

F8D5: CE 0C 71 ldx  #$0C71                   ; Read [$c71]
F8D8: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F8DB: C1 0D    cmpb #$0D                     ; If $0d..
F8DD: 27 01    beq  $F8E0                    ;       ..skip the return
F8DF: 39       rts                           ; Return

F8E0: F6 00 54 ldb  $0054
F8E3: C1 0C    cmpb #$0C
F8E5: 27 01    beq  $F8E8
F8E7: 39       rts  

F8E8: CE 0C 1E ldx  #$0C1E                   ; I think this one's the phony credit counter
F8EB: C6 2A    ldb  #$2A                     ; ($2a is 42)
F8ED: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F8F0: 39       rts  


;
; BUMP_EXTEND:
; Reads [$c7c], increments it modulo 6, and writes it back
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
; A routine called from the main interrupt handler
;

; Return immediately if value of [$f88] isn't 1
F903: CE 0F 88 ldx  #$0F88
F906: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F909: C1 01    cmpb #$01
F90B: 27 01    beq  $F90E
F90D: 39       rts  
; In my playthrough, I never saw [$f88] be 1, so I don't know the circumstances
; around this
F90E: CE 0F 8A ldx  #$0F8A
F911: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F914: CE F9 B1 ldx  #$F9B1                   ; Table pointer -> X
F917: 3A       abx                           ; Add B to it..
F918: 3A       abx                           ; ..twice, since table entries are 16-bit
F919: EE 00    ldx  $00,x                    ; Table value -> X
F91B: 3C       pshx 
F91C: CE 0F 89 ldx  #$0F89
F91F: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F922: 38       pulx 
F923: 3A       abx  
F924: E6 00    ldb  $00,x
F926: 37       pshb 
F927: CE 0F 8B ldx  #$0F8B
F92A: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F92D: CE 0C 88 ldx  #$0C88
F930: 3A       abx  
F931: 33       pulb 
F932: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F935: C6 FF    ldb  #$FF
F937: CE 0F 88 ldx  #$0F88
F93A: 7E F1 DB jmp  $F1DB                    ; Call WRITE_RAM and return


;
; A routine called from the main interrupt handler
; Looks like a second copy of $f903, with different constants
;

F93D: CE 0F 8C ldx  #$0F8C
F940: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F943: C1 01    cmpb #$01
F945: 27 01    beq  $F948
F947: 39       rts  
F948: CE 0F 8E ldx  #$0F8E
F94B: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F94E: CE F9 B1 ldx  #$F9B1
F951: 3A       abx  
F952: 3A       abx  
F953: EE 00    ldx  $00,x
F955: 3C       pshx 
F956: CE 0F 8D ldx  #$0F8D
F959: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F95C: 38       pulx 
F95D: 3A       abx  
F95E: E6 00    ldb  $00,x
F960: 37       pshb 
F961: CE 0F 8F ldx  #$0F8F
F964: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F967: CE 0D 88 ldx  #$0D88
F96A: 3A       abx  
F96B: 33       pulb 
F96C: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F96F: C6 FF    ldb  #$FF
F971: CE 0F 8C ldx  #$0F8C
F974: 7E F1 DB jmp  $F1DB                    ; Call WRITE_RAM and return


;
; A routine called from the main interrupt handler
; Looks like a third copy of $f903, with different constants
;

F977: CE 0F 90 ldx  #$0F90
F97A: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F97D: C1 01    cmpb #$01
F97F: 27 01    beq  $F982
F981: 39       rts  
F982: CE 0F 92 ldx  #$0F92
F985: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F988: CE F9 B1 ldx  #$F9B1
F98B: 3A       abx  
F98C: 3A       abx  
F98D: EE 00    ldx  $00,x
F98F: 3C       pshx 
F990: CE 0F 91 ldx  #$0F91
F993: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F996: 38       pulx 
F997: 3A       abx  
F998: E6 00    ldb  $00,x
F99A: 37       pshb 
F99B: CE 0F 93 ldx  #$0F93
F99E: BD F1 BF jsr  $F1BF                    ; Call READ_RAM_OR_INPUTS
F9A1: CE 0E 88 ldx  #$0E88
F9A4: 3A       abx  
F9A5: 33       pulb 
F9A6: BD F1 DB jsr  $F1DB                    ; Call WRITE_RAM
F9A9: C6 FF    ldb  #$FF
F9AB: CE 0F 90 ldx  #$0F90
F9AE: 7E F1 DB jmp  $F1DB                    ; Call WRITE_RAM and return

; This is a table, accessed in $F914 and $F94E. It seems to point to other
; tables. I don't yet know why.
;
F9B1: F9 BB    .word $F9BB
F9B3: FA BB    .word $FABB
F9B5: FB BB    .word $FBBB
F9B7: FC BB    .word $FCBB
F9B9: FD BB    .word $FDBB

; Table pointed to from the table entry at $f9b1
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

; Table pointed to from the table entry at $f9b3
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

; Table pointed to from the table entry at $f9b5
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

; Table pointed to from the table entry at $f9b7
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

; Table pointed to from the table entry at $f9b9
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


; Bulk of the cold start routine, jumped to immediately from the actual start
; of the cold start handler ($f000)
;
FEBB: 8E 00 FF lds  #$00FF
FEBE: 0F       sei  
FEBF: 86 AF    lda  #$AF
FEC1: 97 0F    sta  $0F

; Initialize timers, serial port
FEC3: 7F 00 08 clr  $0008
FEC6: 7F 00 17 clr  $0017
FEC9: 7F 00 18 clr  $0018
FECC: 7F 00 11 clr  $0011
FECF: 7F 00 19 clr  $0019
FED2: CC 00 A0 ldd  #$00A0
FED5: DD 0B    std  $0B
FED7: CC 00 00 ldd  #$0000
FEDA: DD 1A    std  $1A
FEDC: CC 20 00 ldd  #$2000
FEDF: DD 1C    std  $1C
FEE1: 86 AA    lda  #$AA
FEE3: 16       tab  
FEE4: 91 02    cmpa $02
FEE6: 26 55    bne  $FF3D
FEE8: 91 07    cmpa $07
FEEA: 26 51    bne  $FF3D
FEEC: 96 03    lda  $03
FEEE: 84 1F    anda #$1F
FEF0: 81 0A    cmpa #$0A
FEF2: 26 49    bne  $FF3D
FEF4: 17       tba  
FEF5: 91 06    cmpa $06
FEF7: 26 44    bne  $FF3D
FEF9: 86 55    lda  #$55
FEFB: 16       tab  
FEFC: 91 02    cmpa $02
FEFE: 26 3D    bne  $FF3D
FF00: 91 07    cmpa $07
FF02: 26 39    bne  $FF3D
FF04: 96 03    lda  $03
FF06: 84 1F    anda #$1F
FF08: 81 15    cmpa #$15
FF0A: 26 31    bne  $FF3D
FF0C: 17       tba  
FF0D: 91 06    cmpa $06
FF0F: 26 2C    bne  $FF3D
FF11: 86 FF    lda  #$FF
FF13: 97 00    sta  $00
FF15: 97 01    sta  $01
FF17: 97 04    sta  $04
FF19: 97 05    sta  $05
FF1B: 86 BF    lda  #$BF
FF1D: 97 0F    sta  $0F
FF1F: 86 0F    lda  #$0F
FF21: 97 02    sta  $02
FF23: 97 03    sta  $03
FF25: 97 07    sta  $07
FF27: 97 06    sta  $06
FF29: 96 19    lda  $19
FF2B: 84 08    anda #$08
FF2D: 26 02    bne  $FF31
FF2F: 20 F8    bra  $FF29
FF31: 86 F0    lda  #$F0
FF33: 97 02    sta  $02
FF35: 97 03    sta  $03
FF37: 97 07    sta  $07
FF39: 97 06    sta  $06
FF3B: 20 03    bra  $FF40
FF3D: 7E F0 03 jmp  $F003
FF40: 86 00    lda  #$00
FF42: 16       tab  
FF43: CE 00 40 ldx  #$0040
FF46: 3A       abx  
FF47: C6 A5    ldb  #$A5
FF49: E7 00    stb  $00,x
FF4B: 08       inx  
FF4C: 8C 01 00 cmpx #$0100
FF4F: 27 16    beq  $FF67
FF51: C6 5A    ldb  #$5A
FF53: E7 00    stb  $00,x
FF55: 08       inx  
FF56: 8C 01 00 cmpx #$0100
FF59: 27 0C    beq  $FF67
FF5B: C6 00    ldb  #$00
FF5D: E7 00    stb  $00,x
FF5F: 08       inx  
FF60: 8C 01 00 cmpx #$0100
FF63: 27 02    beq  $FF67
FF65: 20 E0    bra  $FF47
FF67: 16       tab  
FF68: CE 00 40 ldx  #$0040
FF6B: 3A       abx  
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
FF90: D6 19    ldb  $19
FF92: 20 D8    bra  $FF6C
FF94: D6 19    ldb  $19
FF96: CE 00 00 ldx  #$0000
FF99: DF 1A    stx  $1A
FF9B: CE 20 00 ldx  #$2000
FF9E: DF 1C    stx  $1C
FFA0: 4C       inca 
FFA1: 81 03    cmpa #$03
FFA3: 26 9D    bne  $FF42
FFA5: 96 19    lda  $19
FFA7: 84 10    anda #$10
FFA9: 26 02    bne  $FFAD
FFAB: 20 F8    bra  $FFA5
FFAD: 86 AA    lda  #$AA
FFAF: 97 02    sta  $02
FFB1: 97 03    sta  $03
FFB3: 97 07    sta  $07
FFB5: 97 06    sta  $06
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
FFCB: 96 19    lda  $19
FFCD: 84 20    anda #$20
FFCF: 26 02    bne  $FFD3
FFD1: 20 F8    bra  $FFCB
FFD3: 86 55    lda  #$55
FFD5: 97 02    sta  $02
FFD7: 97 03    sta  $03
FFD9: 97 07    sta  $07
FFDB: 97 06    sta  $06
FFDD: 20 FE    bra  $FFDD                    ; loop forever


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
