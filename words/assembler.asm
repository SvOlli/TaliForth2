; Assembler for Tali Forth 2
; Scot W. Stevenson <scot.stevenson@gmail.com>
; Updated by Patrick Surry
; First version: 07. Nov 2014 (as tasm65c02)
; This version: 11. Aug 2024

; This is the built-in assembler for Tali Forth 2. Once the assembler wordlist
; is included with

;       assembler-wordlist >order

; the opcodes are available as normal Forth words. The format is Simpler
; Assembler Notation (SAN) which separates the opcode completely from the
; operand (see https://github.com/scotws/SAN). In this case, the operand is
; entered before the opcode in the postfix Forth notation (for example, "2000
; lda.#"). See the assembler documenation in the manual for more detail.

; The code here was originally used in A Typist's Assembler for the 65c02
; (tasm65c02), see https://github.com/scotws/tasm65c02 for the standalone
; version. Tasm65c02 is in the public domain.

; This code makes use of the opcode tables stored as part of the disassembler.

; ==========================================================
; MNEMONICS

; The assembler instructions are realized as individual Forth words with
; entries in the assembler wordlist (see header.asm).
; They are all implemented as `jsr asm_op_common` with the calling
; location chosen to pass the opcode as the LSB of the return address.

; The words are defined in headers.asm using the .nt_asm macro
; to select the right entrypoint from the asm_op_table.
; They are organized alphabetically by SAN mnemonic, not by opcode.
; Both SAN and traditional mnemonics are listed after the opcode.
; This list was generated by a Python script in the tools folder,
; see there for more detail.

assembler:              ; used to calculate size of assembler code

; ==========================================================
; ASSEMBLER HELPER FUNCTIONS

; This table repeats `jsr asm_op_common` 256 times, each 3 bytes long.
; Because 3 and 256 are relatively prime, for any opcode op
; there will be exactly one such entrypoint which generates a return
; address (at entrypoint+2) whose LSB matches op

asm_op_table:
.rept 256
        jsr asm_op_common
.endrept

; This macro calculates the relevant entrypoint from the table.
; Consider the entrypoint jsr  asm_op_table + 3*k for k=0..255
; It will generate a return address two bytes further on,
; so we want asm_op_table + 2 + 3k == op mod 256
; or equivalently 3k == op - 2 - #<asm_op_table mod 256
; Call the right hand side m = op - 2 - #<asm_op_table
; so we need k such that 3k = m.
; Since 85*3 = 255, we know that 3*(-85) == 1 mod 256.
; Or equivalently 3*171 == 1 mod 256.
; Multiply both sides by m to get 3*m*171 == m mod 256.
; So we can choose k = 171 m mod 256.  Phew.

xt_asm_op .sfunction op, ( asm_op_table + 3*(171 * (512 + op - 2 - <asm_op_table) % 256) )

asm_op_common:
        ; """Common routine for all opcodes. We arrive here with the opcode
        ; in the LSB of the caller's return address.
        ; We do not need to check for the correct values because we are
        ; coming from the assembler Dictionary and trust our external test
        ; suite.
        ; """
                pla     ; LSB contains op code
                ply     ; MSB is ignored

                cmp #$4c
                bne +

                ; special case so that direct jump (only) sets the NN flag
                jmp cmpl_jump_tos

+
                ; Compile opcode. Note cmpl_a does not use Y
                tay
                jsr cmpl_a
                tya
                jsr op_length           ; get opcode length in Y

                ; One byte means no operand, we're done. Use DEY as CPY #1
                dey
                beq _done

                ; We have an operand which must be TOS
                jsr underflow_1

                ; We compile the LSB of TOS as the operand we definitely have
                ; before we even test if this is a two- or three-byte
                ; instruction. Little endian CPU means we store this byte first
                lda 0,x
                jsr cmpl_a      ; does not use Y

                ; If this is a two-byte instruction, we're done. If we landed
                ; here, we've already decremented Y by one, so this is
                ; the equivalent to CPY #2
                dey
                beq _done_drop

                ; This must be a three-byte instruction, get the MSB.
                lda 1,x
                jsr cmpl_a      ; Fall through to _done_drop

_done_drop:
                inx
                inx             ; Fall through to _done
_done:
                rts             ; Returns to original caller


op_find_nt:
                ; given an opcode in A, find the corresponding assembler word
                ; nt_asm_xxx and return its NT in tmp1, or 0 if we have no match.
                ; We want the assembler word whose XT+2 has LSB equal to A
                ; i.e. LSB of XT is A-2
                sec
                sbc #2
                sta tmptos

                lda #<nt_asm_last       ; first candidate NT is the last in the linked list
                sta tmp1
                lda #>nt_asm_last
                sta tmp1+1

_loop:
                jsr nt_to_xt            ; return XT in Y,A
                cmp tmptos              ; check LSB of this word's XT
                beq _found

                jsr nt_to_nt            ; advance tmp1 to next NT

                lda tmp1
                cmp #<nt_asm_first
                bne _loop

                lda tmp1+1
                cmp #>nt_asm_first
                bne _loop

                stz tmp1
                stz tmp1+1
        _found:
                rts


op_length:
        ; given an opcode in A, return its length in Y (stomps A)
                pha
                and #$f
                tay
                lda _lengths,y  ; lookup the length
                bmi _special    ; $x0 and $x9 are special

                ply             ; discard the opcode
                tay             ; return the length
                rts

_lengths:       .byte $80,2,2,1,2,2,2,2, 1,$81,1,1,3,3,3,3

_special:
                ldy #1          ; guess length 1

                ror             ; test bit 0: C=0 means $x0, C=1 means $x9
                pla             ; recover the opcode
                bcs _x9

                ; for $x0 length is two except $20 (3), $40 (1), $60 (1)
                bit #%10011111  ; is opcode 0/20/40/60 ?
                bne _two
                asl             ; test bit 6 by shifting to sign bit
                bmi _one        ; bit 6 set means $40 or $60
                ; otherwise we have  A=$40 if op was $20 and $0 otherwise
                ; shift right twice to reuse bit 4 test
                lsr
                lsr
_x9:
                ; for $x9, bit 4 set means 3 bytes, clear means 2
                and #$10
                beq _two
_three:         iny
_two:           iny
_one:           rts


; ==========================================================
; PSEUDO-INSTRUCTIONS AND MACROS

xt_asm_push_a:
        ; """push-a puts the content of the 65c02 Accumulator on the Forth
        ; data stack as the TOS. This is a convenience routine that
        ; just copies the code for push_a_tos from disasm.asm
        ; """
                ldy #0
_loop:
                lda push_a_tos,y
                jsr cmpl_a      ; does not change Y
                iny
                cpy #z_push_a_tos - push_a_tos
                bne _loop
_done:
z_asm_push_a:
                rts


; ==========================================================
; DIRECTIVES

; The "<J" directive (back jump) is a dummy instruction (syntactic sugar) to
; make clear that the JMP or JSR instructions are using the address that had
; been placed on the stack by "-->" (the "arrow" directive).
xt_asm_back_jump:
z_asm_back_jump:
                rts

; The "<B" directive (back branch) takes an address that was placed on the Data
; Stack by the anonymous label directive "-->" (the "arrow") and the current
; address (via HERE) to calculate a backward branch offset. This is then stored
; by a following branch instruction.
xt_asm_back_branch:
                ; We arrive here with ( addr-l ) of the label on the stack and
                ; then subtract the current address
                jsr w_here             ; ( addr-l addr-h )
                jsr w_minus            ; ( offset )

                ; We subtract two more because of the branch instruction itself
                dea
                dea

z_asm_back_branch:
                rts
assembler_end:

; END
