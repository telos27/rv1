# RV64I Word Operations Test
# Tests ADDIW, ADDW, SUBW, SLLIW, SRLIW, SRAIW, SLLW, SRLW, SRAW
# These operations work on lower 32 bits and sign-extend to 64 bits

.section .text
.globl _start

_start:
    # Test 1: ADDIW - Add immediate word (sign-extend result)
    # Load 0x00000001 into x1, then ADDIW with 0x7FF (2047)
    # Expected: x2 = 0x0000000000000800 (2048 sign-extended)
    li x1, 0x1
    addiw x2, x1, 0x7FF
    li x3, 0x800
    bne x2, x3, fail

    # Test 2: ADDIW with negative result (sign-extend negative)
    # 0x00000001 + (-2) = 0xFFFFFFFFFFFFFFFF (-1 sign-extended)
    li x1, 0x1
    addiw x2, x1, -2
    li x3, -1
    bne x2, x3, fail

    # Test 3: ADDW - Add word (sign-extend result)
    # 0x7FFFFFFF + 1 = 0xFFFFFFFF80000000 (-2147483648 sign-extended)
    li x1, 0x7FFFFFFF
    li x2, 0x1
    addw x3, x1, x2
    # Load expected value as negative to get sign extension
    li x4, -2147483648  # 0xFFFFFFFF80000000
    bne x3, x4, fail

    # Test 4: SUBW - Subtract word (sign-extend result)
    # 0x00000001 - 0x00000002 = 0xFFFFFFFFFFFFFFFF (-1 sign-extended)
    li x1, 0x1
    li x2, 0x2
    subw x3, x1, x2
    li x4, -1
    bne x3, x4, fail

    # Test 5: SLLIW - Shift left logical immediate word
    # 0x1 << 31 = 0xFFFFFFFF80000000 (bit 31 set, sign-extended)
    li x1, 0x1
    slliw x2, x1, 31
    li x3, -2147483648  # 0xFFFFFFFF80000000
    bne x2, x3, fail

    # Test 6: SRLIW - Shift right logical immediate word
    # 0xFFFFFFFF >> 1 = 0x000000007FFFFFFF (logical shift, zero-extended to 32, then sign-extended)
    li x1, -1
    srliw x2, x1, 1
    li x3, 0x7FFFFFFF
    bne x2, x3, fail

    # Test 7: SRAIW - Shift right arithmetic immediate word
    # 0xFFFFFFFF >>> 1 = 0xFFFFFFFFFFFFFFFF (arithmetic shift preserves sign)
    li x1, -1
    sraiw x2, x1, 1
    li x3, -1
    bne x2, x3, fail

    # Test 8: SLLW - Shift left logical word
    # 0x00000001 << 16 = 0x0000000000010000
    li x1, 0x1
    li x2, 16
    sllw x3, x1, x2
    li x4, 0x10000
    bne x3, x4, fail

    # Test 9: SRLW - Shift right logical word
    # 0x80000000 >> 16 = 0x0000000000008000 (logical shift)
    li x1, 0x80000000
    li x2, 16
    srlw x3, x1, x2
    li x4, 0x8000
    bne x3, x4, fail

    # Test 10: SRAW - Shift right arithmetic word
    # 0xFFFFFFFF80000000 >>> 16 = 0xFFFFFFFFFFFF8000 (arithmetic shift)
    li x1, -2147483648  # 0xFFFFFFFF80000000
    li x2, 16
    sraw x3, x1, x2
    li x4, -32768  # 0xFFFFFFFFFFFF8000 (sign-extended)
    bne x3, x4, fail

pass:
    li a0, 1        # Success
    j done

fail:
    li a0, 0        # Failure

done:
    # Write result to assertion address
    li t0, 0x23e8
    sw a0, 0(t0)

    # Exit simulation
    ebreak
