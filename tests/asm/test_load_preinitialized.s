# Test loading from pre-initialized memory
# This mimics the official compliance tests which have data sections

.section .text
.globl _start

_start:
    # Load from data section address
    lui  x10, 0x2           # x10 = 0x2000
    lw   x11, 0(x10)        # x11 = mem[0x2000] (should be 0x12345678)

    # Check expected value
    lui  x12, 0x12345       # x12 = 0x12345000
    addi x12, x12, 0x678    # x12 = 0x12345678

    bne  x11, x12, fail

success:
    li   x28, 0xDEADBEEF
    ebreak

fail:
    li   x28, 0xDEADDEAD
    ebreak

.section .data
.org 0x1000
testdata:
    .word 0x12345678
    .word 0xAABBCCDD
    .word 0x0F0F0F0F
