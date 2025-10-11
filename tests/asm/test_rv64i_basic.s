# test_rv64i_basic.s
# RV64I Instruction Test - Basic LD/SD/LWU
# Tests the three new RV64I instructions: LD, SD, LWU
# Expected result: x10 = 0xDEADBEEF (success code)

.section .text
.globl _start

_start:
    # Setup test data area (use data memory address)
    lui x15, 0x1000         # x15 = 0x1000 (base address)

    #==========================================================
    # Test 1: SD (Store Doubleword) - Store 64-bit value
    #==========================================================
    # Store a 64-bit value to memory
    li x10, 0x12345678      # Lower 32 bits
    slli x10, x10, 32       # Shift to upper 32 bits
    li x11, 0xABCDEF00      # Lower 32 bits
    or x10, x10, x11        # x10 = 0x12345678_ABCDEF00

    sd x10, 0(x15)          # Store doubleword at [0x1000]

    #==========================================================
    # Test 2: LD (Load Doubleword) - Load 64-bit value
    #==========================================================
    # Load the 64-bit value back
    li x11, 0               # Clear x11
    ld x11, 0(x15)          # Load doubleword from [0x1000]

    # Verify: x11 should equal x10
    bne x10, x11, test_fail

    #==========================================================
    # Test 3: SD with offset
    #==========================================================
    li x12, 0xFEDCBA98      # Lower 32 bits
    slli x12, x12, 32       # Shift to upper 32 bits
    li x13, 0x76543210      # Lower 32 bits
    or x12, x12, x13        # x12 = 0xFEDCBA98_76543210

    sd x12, 8(x15)          # Store at [0x1008]

    #==========================================================
    # Test 4: LD with offset
    #==========================================================
    li x13, 0               # Clear x13
    ld x13, 8(x15)          # Load from [0x1008]

    # Verify: x13 should equal x12
    bne x12, x13, test_fail

    #==========================================================
    # Test 5: LWU (Load Word Unsigned) - Zero-extend 32-bit
    #==========================================================
    # First, store a 32-bit value with sign bit set
    li x14, 0xDEADBEEF      # Negative if sign-extended
    sw x14, 16(x15)         # Store word at [0x1010]

    # Load with LWU (should zero-extend)
    li x16, 0               # Clear x16
    lwu x16, 16(x15)        # Load word unsigned

    # x16 should be 0x00000000_DEADBEEF (zero-extended)
    # NOT 0xFFFFFFFF_DEADBEEF (sign-extended)

    # Check upper 32 bits are zero
    srli x17, x16, 32       # Shift right to get upper 32 bits
    bnez x17, test_fail     # Should be zero

    # Check lower 32 bits match
    li x18, 0xDEADBEEF
    slli x19, x16, 32       # Clear upper bits
    srli x19, x19, 32       # Shift back
    bne x19, x18, test_fail

    #==========================================================
    # Test 6: Compare LWU vs LW (sign extension difference)
    #==========================================================
    # LW should sign-extend the negative value
    lw x20, 16(x15)         # Load word signed

    # x20 should be 0xFFFFFFFF_DEADBEEF (sign-extended)
    # Check that upper bits are 1s (negative)
    srli x21, x20, 32       # Get upper 32 bits
    li x22, 0xFFFFFFFF
    bne x21, x22, test_fail # Upper bits should be all 1s

    # Verify LWU != LW for negative values
    beq x16, x20, test_fail # They should be different

    #==========================================================
    # Test 7: LD/SD alignment test (8-byte aligned)
    #==========================================================
    li x23, 0xCAFEBABE
    slli x23, x23, 32
    li x24, 0xDEADBEEF
    or x23, x23, x24        # x23 = 0xCAFEBABE_DEADBEEF

    sd x23, 24(x15)         # Store at [0x1018] (8-byte aligned)
    ld x24, 24(x15)         # Load back

    bne x23, x24, test_fail

    #==========================================================
    # Test 8: Multiple doubleword stores and loads
    #==========================================================
    li x25, 0x11111111
    slli x25, x25, 32
    li x26, 0x22222222
    or x25, x25, x26        # x25 = 0x11111111_22222222

    li x26, 0x33333333
    slli x26, x26, 32
    li x27, 0x44444444
    or x26, x26, x27        # x26 = 0x33333333_44444444

    li x27, 0x55555555
    slli x27, x27, 32
    li x28, 0x66666666
    or x27, x27, x28        # x27 = 0x55555555_66666666

    # Store three doublewords
    sd x25, 32(x15)         # [0x1020]
    sd x26, 40(x15)         # [0x1028]
    sd x27, 48(x15)         # [0x1030]

    # Load them back in reverse order
    ld x30, 48(x15)
    ld x29, 40(x15)
    ld x28, 32(x15)

    # Verify
    bne x25, x28, test_fail
    bne x26, x29, test_fail
    bne x27, x30, test_fail

    #==========================================================
    # All tests passed!
    #==========================================================
test_pass:
    # Load success code: 0x600D (GOOD)
    addi x10, x0, 0x600
    slli x10, x10, 4
    addi x10, x10, 0xD      # x10 = 0x600D
    nop                     # Pipeline drain
    nop
    nop
    nop
    ebreak

test_fail:
    addi x10, x0, -1        # Failure code (0xFFFFFFFFFFFFFFFF)
    nop                     # Pipeline drain
    nop
    nop
    nop
    ebreak
