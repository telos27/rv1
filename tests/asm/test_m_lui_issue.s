# Test to isolate LUI immediately after MUL issue
# Purpose: Check if LUI right after MUL executes correctly
# Author: Debug session 2025-10-10

.section .text
.globl _start

_start:
    # Test 1: MUL followed immediately by LUI (like test_m_basic)
    li a0, 100              # a0 = 100
    li a1, 200              # a1 = 200
    mul a2, a0, a1          # a2 = 100 × 200 = 20000 (0x4E20)
    lui t0, 0x5             # t0 = 0x5000 (CRITICAL: does this execute?)
    addi t0, t0, -480       # t0 = 0x5000 - 480 = 0x4E20 (20000)

    # Verify: a2 should equal t0
    bne a2, t0, fail

    # Test 2: MUL followed by NOP then LUI
    li a3, 50               # a3 = 50
    li a4, 10               # a4 = 10
    mul a5, a3, a4          # a5 = 50 × 10 = 500 (0x1F4)
    nop                     # Add one NOP
    lui t1, 0x0             # t1 = 0
    addi t1, t1, 500        # t1 = 500

    # Verify: a5 should equal t1
    bne a5, t1, fail

success:
    li a0, 0x600D           # GOOD
    nop
    nop
    nop
    nop
    ebreak

fail:
    li a0, 0xBAD            # BAD
    nop
    nop
    nop
    nop
    ebreak

# Expected results if all works:
# a0 = 0x600D (GOOD)
# a2 = 0x4E20 (20000)
# t0 = 0x4E20 (20000)
# a5 = 0x01F4 (500)
# t1 = 0x01F4 (500)
