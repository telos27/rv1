# Test Edge Cases: Immediate Value Limits
# Tests LUI, ADDI, load/store offsets, and shift amount boundaries
# RISC-V RV32I Edge Case Test

.section .text
.globl _start

_start:
    # Test base address for results
    lui x10, 0x01000       # x10 = 0x01000000 (test memory base)

    #===========================================
    # Test 1: LUI immediate limits (20-bit)
    #===========================================
    # Maximum positive LUI value (0xFFFFF << 12)
    lui x5, 0xFFFFF        # x5 = 0xFFFFF000
    sw x5, 0(x10)          # Store result

    # Minimum LUI value (0x00000 << 12)
    lui x6, 0x00000        # x6 = 0x00000000
    sw x6, 4(x10)          # Store result

    # Middle values
    lui x7, 0x80000        # x7 = 0x80000000
    sw x7, 8(x10)          # Store result

    lui x8, 0x7FFFF        # x8 = 0x7FFFF000
    sw x8, 12(x10)         # Store result

    #===========================================
    # Test 2: ADDI immediate limits (12-bit signed)
    #===========================================
    # Maximum positive ADDI immediate (+2047)
    li x5, 0
    addi x5, x5, 2047      # x5 = 2047 (0x7FF)
    sw x5, 16(x10)         # Store result

    # Minimum negative ADDI immediate (-2048)
    li x6, 0
    addi x6, x6, -2048     # x6 = -2048 (0xFFFFF800)
    sw x6, 20(x10)         # Store result

    # Adding max positive to register
    lui x7, 0x7FFFF        # x7 = 0x7FFFF000
    addi x7, x7, 0x7FF     # x7 = 0x7FFFFFFF (INT_MAX)
    sw x7, 24(x10)         # Store result

    # Adding max negative to register
    lui x8, 0x80000        # x8 = 0x80000000
    addi x8, x8, -2048     # x8 = 0x7FFFF800
    sw x8, 28(x10)         # Store result

    #===========================================
    # Test 3: SLTI/SLTIU immediate limits
    #===========================================
    # SLTI with max positive immediate (2047)
    li x5, 2048
    slti x6, x5, 2047      # x6 = 0 (2048 not < 2047)
    sw x6, 32(x10)         # Store result

    li x5, 2046
    slti x6, x5, 2047      # x6 = 1 (2046 < 2047)
    sw x6, 36(x10)         # Store result

    # SLTI with min negative immediate (-2048)
    li x5, -2049
    slti x6, x5, -2048     # x6 = 1 (-2049 < -2048)
    sw x6, 40(x10)         # Store result

    # SLTIU with max immediate (treats as unsigned)
    li x5, -1              # x5 = 0xFFFFFFFF
    sltiu x6, x5, 2047     # x6 = 0 (0xFFFFFFFF not < 2047)
    sw x6, 44(x10)         # Store result

    #===========================================
    # Test 4: ANDI/ORI/XORI immediate limits (12-bit signed)
    #===========================================
    # ORI with all bits set (-1 in 12-bit signed = 0xFFF)
    li x5, 0
    ori x5, x5, -1         # x5 = 0xFFFFFFFF (sign extended then OR'd)
    sw x5, 48(x10)         # Store result

    # ANDI with positive max (2047)
    li x6, -1              # x6 = 0xFFFFFFFF
    andi x6, x6, 2047      # x6 = 0x000007FF
    sw x6, 52(x10)         # Store result

    # XORI with negative immediate
    lui x7, 0x12345
    addi x7, x7, 0x678     # x7 = 0x12345678
    xori x7, x7, -1        # x7 = ~0x12345678 = 0xEDCBA987 (invert all bits)
    sw x7, 56(x10)         # Store result

    #===========================================
    # Test 5: Load/Store offset limits (12-bit signed)
    #===========================================
    # Store with maximum positive offset (+2047)
    lui x11, 0x01001       # x11 = 0x01001000 (new base)
    li x5, 0xDEADBEEF
    sw x5, 2047(x11)       # Store at 0x010017FF

    # Load with maximum positive offset
    lw x6, 2047(x11)       # Load from 0x010017FF
    sw x6, 60(x10)         # Store loaded value

    # Store with minimum negative offset (-2048)
    lui x11, 0x01002       # x11 = 0x01002000
    li x5, 0xCAFEBABE
    sw x5, -2048(x11)      # Store at 0x01001800

    # Load with minimum negative offset
    lw x6, -2048(x11)      # Load from 0x01001800
    sw x6, 64(x10)         # Store loaded value

    # Load/store with zero offset
    li x5, 0x12345678
    sw x5, 0(x10)          # Store at base
    lw x6, 0(x10)          # Load from base
    sw x6, 68(x10)         # Store loaded value

    #===========================================
    # Test 6: Shift immediate limits (5-bit for RV32)
    #===========================================
    # Left shift by 0 (minimum)
    li x5, 0x12345678
    slli x6, x5, 0         # x6 = 0x12345678 (no shift)
    sw x6, 72(x10)         # Store result

    # Left shift by 31 (maximum for RV32)
    li x5, 1
    slli x6, x5, 31        # x6 = 0x80000000
    sw x6, 76(x10)         # Store result

    # Right logical shift by 31
    lui x5, 0x80000        # x5 = 0x80000000
    srli x6, x5, 31        # x6 = 0x00000001
    sw x6, 80(x10)         # Store result

    # Right arithmetic shift by 31 (sign extension)
    lui x5, 0x80000        # x5 = 0x80000000 (INT_MIN, negative)
    srai x6, x5, 31        # x6 = 0xFFFFFFFF (all bits set)
    sw x6, 84(x10)         # Store result

    # Shift positive value by 31 arithmetic
    lui x5, 0x7FFFF
    addi x5, x5, 0x7FF     # x5 = 0x7FFFFFFF (INT_MAX)
    srai x6, x5, 31        # x6 = 0x00000000 (sign bit was 0)
    sw x6, 88(x10)         # Store result

    # Multiple shifts to verify each bit position
    li x5, 1
    slli x6, x5, 15        # x6 = 0x00008000
    sw x6, 92(x10)         # Store result

    slli x7, x5, 16        # x7 = 0x00010000
    sw x7, 96(x10)         # Store result

    #===========================================
    # Test 7: Branch offset limits (13-bit signed, multiple of 2)
    #===========================================
    # Note: Can't easily test maximum offsets in small test
    # These are simple forward/backward branches

    # Short forward branch
    li x5, 10
    beq x5, x5, forward_target
    li x6, 999             # Should skip this
forward_target:
    li x6, 42
    sw x6, 100(x10)        # Store result (should be 42)

    # Short backward branch
    li x7, 0
    j skip_back
back_target:
    li x8, 100
    sw x8, 104(x10)        # Store result (should be 100)
    j after_back
skip_back:
    li x9, 5
    beq x9, x9, back_target
after_back:

    #===========================================
    # Test 8: JAL/JALR offset limits
    #===========================================
    # JAL has 21-bit signed immediate (multiple of 2)
    # Maximum range: ±1 MiB

    # Simple JAL forward
    jal x15, jal_target
    li x5, 999             # Should skip

jal_target:
    li x5, 77
    sw x5, 108(x10)        # Store result (should be 77)

    # JALR with 12-bit signed immediate
    # Maximum offset: ±2048
    lui x11, 0x01000
    addi x11, x11, 0       # x11 = base address
    la x12, jalr_target    # Load address of jalr_target
    jalr x15, 0(x12)       # Jump to jalr_target
    li x6, 888             # Should skip

jalr_target:
    li x6, 88
    sw x6, 112(x10)        # Store result (should be 88)

    #===========================================
    # Test 9: AUIPC with immediate limits
    #===========================================
    # AUIPC adds upper immediate to PC
    auipc x5, 0            # x5 = current PC
    sw x5, 116(x10)        # Store PC value

    auipc x6, 0xFFFFF      # x6 = PC + 0xFFFFF000
    sw x6, 120(x10)        # Store result

    auipc x7, 0x7FFFF      # x7 = PC + 0x7FFFF000
    sw x7, 124(x10)        # Store result

    #===========================================
    # Verification Section
    #===========================================
    # Load back critical results for verification
    lw x5, 0(x10)          # LUI max value
    lw x6, 16(x10)         # ADDI max positive
    lw x7, 20(x10)         # ADDI max negative
    lw x8, 76(x10)         # SLLI by 31

    #===========================================
    # Test Complete - Set return value
    #===========================================
    li x10, 0              # Return 0 for success

    # Infinite loop to end simulation
    j .
