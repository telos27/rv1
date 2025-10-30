# JALR test without compressed instructions
# Force no compressed instructions to isolate JALR bug

.option norvc  # Disable compressed instructions

.section .text
.globl _start

_start:
    # Test basic JALR - jump forward
    auipc x1, 0            # x1 = PC
    addi x1, x1, 20        # x1 = PC + 20 (target)
    jalr x2, x1, 0         # Jump to x1, save return address in x2

    # Should NOT reach here
    li x28, 0xDEADDEAD
    ebreak

target:
    # We should land here
    li x28, 0xFEEDFACE
    ebreak
