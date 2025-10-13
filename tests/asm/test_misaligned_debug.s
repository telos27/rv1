# Test misaligned halfword store + byte load (test 92 reproduction)
.section .text
.globl _start

_start:
    # Load data section address into s0
    la s0, data_section

    # Test 92 reproduction:
    # Store halfword 0x9b9a at s0+1 (misaligned)
    li t1, 0x9b9a
    sh t1, 1(s0)

    # Load signed byte from s0+2
    lb t3, 2(s0)

    # Expected result: 0xffffff9b
    li t2, 0xffffff9b

    # Check if t3 == t2
    bne t2, t3, fail

pass:
    li a0, 0
    li a7, 93        # exit syscall
    ecall

fail:
    li a0, 1
    li a7, 93
    ecall

.section .data
.align 3
data_section:
    .word 0x03020100
    .word 0x07060504
    .word 0x0b0a0908
    .word 0x0f0e0d0c
