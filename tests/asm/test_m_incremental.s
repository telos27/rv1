# Incremental M extension test - test each instruction individually
# Exit code in a0 indicates which test failed (0x600D = all pass)

.section .text
.globl _start

_start:
    #=========================================================================
    # Test 1: MUL
    #=========================================================================
    li a0, 100
    li a1, 200
    mul a2, a0, a1          # a2 = 100 * 200 = 20000 (0x4E20)

    # Check result
    li t0, 20000
    li a0, 0x0001           # Test 1 failed
    bne a2, t0, fail

    #=========================================================================
    # Test 2: MULH (signed high)
    #=========================================================================
    li a3, -10
    li a4, -20
    mulh a5, a3, a4         # High bits of (-10) * (-20) = 200, high should be 0

    li t1, 0
    li a0, 0x0002           # Test 2 failed
    bne a5, t1, fail

    #=========================================================================
    # Test 3: MULHU (unsigned high)
    #=========================================================================
    li a0, 0xFFFFFFFF       # Max unsigned 32-bit
    li a1, 2
    mulhu a2, a0, a1        # High bits of (0xFFFFFFFF * 2)

    li t2, 1                # Should be 1
    li a0, 0x0003           # Test 3 failed
    bne a2, t2, fail

    #=========================================================================
    # Test 4: DIV (signed)
    #=========================================================================
    li a3, 100
    li a4, 5
    div a5, a3, a4          # 100 / 5 = 20

    li t3, 20
    li a0, 0x0004           # Test 4 failed
    bne a5, t3, fail

    #=========================================================================
    # Test 5: DIVU (unsigned)
    #=========================================================================
    li a0, 100
    li a1, 3
    divu a2, a0, a1         # 100 / 3 = 33

    li t4, 33
    li a0, 0x0005           # Test 5 failed
    bne a2, t4, fail

    #=========================================================================
    # Test 6: REM (signed remainder)
    #=========================================================================
    li a3, 100
    li a4, 7
    rem a5, a3, a4          # 100 % 7 = 2

    li t5, 2
    li a0, 0x0006           # Test 6 failed
    bne a5, t5, fail

    #=========================================================================
    # Test 7: REMU (unsigned remainder)
    #=========================================================================
    li a0, 100
    li a1, 7
    remu a2, a0, a1         # 100 % 7 = 2

    li t0, 2
    li a0, 0x0007           # Test 7 failed
    bne a2, t0, fail

    #=========================================================================
    # Test 8: Division by zero
    #=========================================================================
    li a3, 100
    li a4, 0
    div a5, a3, a4          # Should give -1 per RISC-V spec

    li t1, -1
    li a0, 0x0008           # Test 8 failed
    bne a5, t1, fail

    #=========================================================================
    # All tests passed!
    #=========================================================================
pass:
    li a0, 0x600D           # GOOD
    nop
    nop
    nop
    nop
    ebreak

fail:
    # a0 already contains the test number that failed
    nop
    nop
    nop
    nop
    ebreak
