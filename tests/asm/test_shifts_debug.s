# Test program to debug right shift operations
# Tests specific edge cases that might be failing

.globl _start
_start:
    # Test 1: SRL with value that has MSB set
    lui x5, 0x80000      # x5 = 0x80000000 (MSB set)
    srli x6, x5, 1       # x6 = 0x40000000 (logical shift, should zero-fill)

    # Test 2: SRA with value that has MSB set
    lui x7, 0x80000      # x7 = 0x80000000 (MSB set)
    srai x8, x7, 1       # x8 = 0xC0000000 (arithmetic shift, should sign-extend)

    # Test 3: SRL by 0
    addi x9, x0, 0x42    # x9 = 0x42
    srli x10, x9, 0      # x10 = 0x42 (shift by 0)

    # Test 4: SRL by 31
    lui x11, 0x80000     # x11 = 0x80000000
    srli x12, x11, 31    # x12 = 0x00000001

    # Test 5: SRA by 31
    lui x13, 0x80000     # x13 = 0x80000000
    srai x14, x13, 31    # x14 = 0xFFFFFFFF (all ones)

    # Test 6: SRL register-register
    addi x15, x0, 0xFF   # x15 = 0xFF
    slli x15, x15, 24    # x15 = 0xFF000000
    addi x16, x0, 8      # x16 = 8 (shift amount)
    srl x17, x15, x16    # x17 = 0x00FF0000

    # Test 7: SRA register-register with negative number
    addi x18, x0, -1     # x18 = 0xFFFFFFFF
    addi x19, x0, 4      # x19 = 4
    sra x20, x18, x19    # x20 = 0xFFFFFFFF (should stay all ones)

    # Store result in x10 for checking
    add x10, x6, x8      # x10 = x6 + x8

    # Exit
    ecall
