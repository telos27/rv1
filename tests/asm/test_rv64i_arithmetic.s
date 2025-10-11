# test_rv64i_arithmetic.s
# RV64I Arithmetic Test - 64-bit operations and sign extension
# Tests that XLEN-wide arithmetic works correctly
# Expected result: x10 = 0x600D (success code)

.section .text
.globl _start

_start:
    #==========================================================
    # Test 1: 64-bit addition with carry propagation
    #==========================================================
    # Create 64-bit values
    li x10, 0xFFFFFFFF      # x10 = 0xFFFFFFFF
    li x11, 1               # x11 = 1
    add x12, x10, x11       # Should be 0x100000000 (carry to bit 32)

    # Check result
    li x13, 0x100000000
    bne x12, x13, test_fail

    #==========================================================
    # Test 2: 64-bit subtraction with borrow
    #==========================================================
    li x14, 0x100000000     # x14 = 2^32
    li x15, 1               # x15 = 1
    sub x16, x14, x15       # Should be 0xFFFFFFFF

    li x17, 0xFFFFFFFF
    bne x16, x17, test_fail

    #==========================================================
    # Test 3: Sign extension of immediate values
    #==========================================================
    # ADDI sign-extends 12-bit immediate to XLEN
    addi x18, x0, -1        # Should be 0xFFFFFFFF_FFFFFFFF (all 1s)

    # Check all bits are 1
    li x19, -1
    bne x18, x19, test_fail

    #==========================================================
    # Test 4: Large 64-bit value construction
    #==========================================================
    # Build 0x0123456789ABCDEF
    li x20, 0x01234567      # Lower part
    slli x20, x20, 32       # Shift left: 0x0123456700000000

    li x21, 0x89ABCDEF      # Lower part (using li pseudo-instruction)

    # Need to mask x21 to 32 bits before OR
    slli x21, x21, 32       # Shift out upper bits
    srli x21, x21, 32       # Shift back (zero upper bits)

    or x20, x20, x21        # Combine

    # Verify by loading upper and lower parts
    srli x22, x20, 32       # Get upper 32 bits
    li x23, 0x01234567
    bne x22, x23, test_fail

    slli x24, x20, 32       # Clear upper bits
    srli x24, x24, 32       # Get lower 32 bits
    li x25, 0x89ABCDEF
    bne x24, x25, test_fail

    #==========================================================
    # Test 5: Logical operations on 64-bit values
    #==========================================================
    li x26, 0xAAAAAAAA
    slli x26, x26, 32
    li x27, 0xAAAAAAAA
    or x26, x26, x27        # x26 = 0xAAAAAAAA_AAAAAAAA

    li x27, 0x55555555
    slli x27, x27, 32
    li x28, 0x55555555
    or x27, x27, x28        # x27 = 0x55555555_55555555

    # XOR should give all 1s
    xor x29, x26, x27       # x29 = 0xFFFFFFFF_FFFFFFFF
    li x30, -1
    bne x29, x30, test_fail

    # AND should give all 0s
    and x29, x26, x27       # x29 = 0x00000000_00000000
    bnez x29, test_fail

    # OR should give all 1s
    or x29, x26, x27        # x29 = 0xFFFFFFFF_FFFFFFFF
    bne x29, x30, test_fail

    #==========================================================
    # Test 6: Shift operations on 64-bit values
    #==========================================================
    li x10, 1               # x10 = 1
    slli x10, x10, 63       # x10 = 0x8000000000000000 (MSB set)

    # Logical right shift should zero-extend
    srli x11, x10, 1        # x11 = 0x4000000000000000

    li x12, 0x40000000
    slli x12, x12, 32       # x12 = 0x4000000000000000
    bne x11, x12, test_fail

    # Arithmetic right shift should sign-extend
    srai x13, x10, 1        # x13 = 0xC000000000000000 (sign extended)

    li x14, 0xC0000000
    slli x14, x14, 32       # x14 = 0xC000000000000000
    bne x13, x14, test_fail

    #==========================================================
    # Test 7: Comparison operations with 64-bit values
    #==========================================================
    li x15, 0x80000000
    slli x15, x15, 32       # x15 = 0x8000000000000000 (large negative)

    li x16, 1               # x16 = 1 (small positive)

    # Signed comparison: negative < positive
    slt x17, x15, x16       # Should be 1 (true)
    li x18, 1
    bne x17, x18, test_fail

    # Unsigned comparison: large value > small value
    sltu x17, x15, x16      # Should be 0 (false)
    bnez x17, test_fail

    #==========================================================
    # Test 8: Branch on 64-bit comparisons
    #==========================================================
    li x19, 0xFFFFFFFF
    slli x19, x19, 32
    li x20, 0xFFFFFFFF
    or x19, x19, x20        # x19 = -1 (all bits set)

    li x20, 0               # x20 = 0

    # BLT: -1 < 0 (signed)
    blt x19, x20, branch1
    j test_fail

branch1:
    # BLTU: -1 > 0 (unsigned, since -1 is 0xFFFF...)
    bltu x20, x19, branch2
    j test_fail

branch2:
    # BEQ: compare equal 64-bit values
    li x21, 0x12345678
    slli x21, x21, 32
    li x22, 0xABCDEF00
    or x21, x21, x22        # x21 = 0x12345678_ABCDEF00

    li x22, 0x12345678
    slli x22, x22, 32
    li x23, 0xABCDEF00
    or x22, x22, x23        # x22 = 0x12345678_ABCDEF00

    beq x21, x22, branch3
    j test_fail

branch3:
    # BNE: compare different 64-bit values
    li x23, 0x12345678
    slli x23, x23, 32
    li x24, 0xABCDEF01      # Different in LSB
    or x23, x23, x24

    bne x21, x23, test_pass
    j test_fail

    #==========================================================
    # All tests passed!
    #==========================================================
test_pass:
    li x10, 0x600D          # Success code (GOOD)
    nop                     # Pipeline drain
    nop
    nop
    nop
    ebreak

test_fail:
    li x10, 0xBAD           # Failure code
    nop                     # Pipeline drain
    nop
    nop
    nop
    ebreak
