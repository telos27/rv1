# RV64I 64-bit SD/LD Test

.section .text
.globl _start

.option norvc

_start:
    li      t0, 0x2000              # Address

    # Build 64-bit value: 0x123456789ABCDEF0
    li      t1, 0x12345678
    slli    t1, t1, 32
    li      t2, 0x9ABCDEF0
    or      t1, t1, t2              # t1 = 0x123456789ABCDEF0

    sd      t1, 0(t0)               # Store doubleword
    ld      t2, 0(t0)               # Load doubleword

    # Move result for checking
    mv      a0, t2                  # Should be 0x123456789ABCDEF0
    nop
    nop
    ebreak
