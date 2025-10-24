# Test Edge Cases: Branch and Jump Offset Limits
# Tests maximum forward/backward offsets for branches and jumps
# RISC-V RV32I Edge Case Test

.section .text
.globl _start

_start:
    # Test base address for results
    lui x10, 0x01000       # x10 = 0x01000000 (test memory base)

    #===========================================
    # Test 1: Short Branch Offsets (BEQ, BNE, etc.)
    #===========================================
    # Branch forward (small offset)
    li x5, 42
    beq x5, x5, short_forward
    li x6, 999             # Should skip
    j test1_fail
short_forward:
    li x6, 100             # Should execute
    sw x6, 0(x10)          # Store success marker
    j test1_done
test1_fail:
    li x6, 0
    sw x6, 0(x10)
test1_done:

    # Branch backward (small offset)
    li x7, 0
    j skip_back1
back_target1:
    li x8, 200
    sw x8, 4(x10)          # Store success marker
    j test2_done
skip_back1:
    li x9, 10
    beq x9, x9, back_target1
    li x8, 0               # Fail marker
    sw x8, 4(x10)
test2_done:

    #===========================================
    # Test 2: Medium Branch Offsets
    #===========================================
    # Test forward branch with moderate offset
    li x11, 1
    beq x11, x11, medium_forward
    # Insert some NOPs to increase offset
    .rept 20
    nop
    .endr
medium_forward:
    li x12, 300
    sw x12, 8(x10)         # Store success marker

    #===========================================
    # Test 3: BLT, BGE, BLTU, BGEU offsets
    #===========================================
    # BLT forward
    li x5, 5
    li x6, 10
    blt x5, x6, blt_target
    li x7, 0               # Fail
    j blt_done
blt_target:
    li x7, 400             # Success
blt_done:
    sw x7, 12(x10)

    # BGE forward
    li x5, 10
    li x6, 5
    bge x5, x6, bge_target
    li x8, 0               # Fail
    j bge_done
bge_target:
    li x8, 500             # Success
bge_done:
    sw x8, 16(x10)

    # BLTU forward (unsigned comparison)
    li x5, -1              # 0xFFFFFFFF (large unsigned)
    li x6, 10
    bltu x6, x5, bltu_target
    li x9, 0               # Fail
    j bltu_done
bltu_target:
    li x9, 600             # Success
bltu_done:
    sw x9, 20(x10)

    # BGEU forward (unsigned comparison)
    li x5, -1              # 0xFFFFFFFF
    li x6, 10
    bgeu x5, x6, bgeu_target
    li x11, 0              # Fail
    j bgeu_done
bgeu_target:
    li x11, 700            # Success
bgeu_done:
    sw x11, 24(x10)

    #===========================================
    # Test 4: JAL Forward with Various Offsets
    #===========================================
    # Short JAL forward
    jal x15, jal_short_forward
    li x12, 0              # Should skip
    j jal_test1_fail
jal_short_forward:
    li x12, 800
    sw x12, 28(x10)        # Store success marker
    j jal_test1_done
jal_test1_fail:
    li x12, 0
    sw x12, 28(x10)
jal_test1_done:

    # Medium JAL forward (with NOPs)
    jal x15, jal_medium_forward
    .rept 30
    nop
    .endr
jal_medium_forward:
    li x13, 900
    sw x13, 32(x10)        # Store success marker

    #===========================================
    # Test 5: JAL Backward
    #===========================================
    j setup_jal_back
jal_back_target:
    li x14, 1000
    sw x14, 36(x10)        # Store success marker
    j jal_back_done
setup_jal_back:
    jal x15, jal_back_target
    li x14, 0              # Fail
    sw x14, 36(x10)
jal_back_done:

    #===========================================
    # Test 6: JALR with Various Offsets
    #===========================================
    # JALR with positive offset
    la x16, jalr_target1   # Load address
    jalr x15, 0(x16)       # Jump with 0 offset
    li x17, 0              # Should skip
    j jalr_test1_done
jalr_target1:
    li x17, 1100
    sw x17, 40(x10)        # Store success marker
jalr_test1_done:

    # JALR with maximum positive offset (+2047)
    # Note: We can't easily create +2047 offset in small test
    # So we'll test with moderate offsets
    la x18, jalr_base
    jalr x15, 100(x18)     # Jump to base + 100 bytes
    .rept 25               # Each NOP is 4 bytes, so 25 NOPs = 100 bytes
    nop
    .endr
jalr_base:
    li x19, 1200
    sw x19, 44(x10)        # Store success marker

    #===========================================
    # Test 7: Branch Not Taken Cases
    #===========================================
    # BEQ when not equal (branch not taken)
    li x5, 10
    li x6, 20
    beq x5, x6, should_not_branch1
    li x7, 1300            # Should execute
    j bnt1_done
should_not_branch1:
    li x7, 0               # Fail
bnt1_done:
    sw x7, 48(x10)

    # BNE when equal (branch not taken)
    li x5, 30
    li x6, 30
    bne x5, x6, should_not_branch2
    li x8, 1400            # Should execute
    j bnt2_done
should_not_branch2:
    li x8, 0               # Fail
bnt2_done:
    sw x8, 52(x10)

    # BLT when >= (branch not taken)
    li x5, 50
    li x6, 40
    blt x5, x6, should_not_branch3
    li x9, 1500            # Should execute
    j bnt3_done
should_not_branch3:
    li x9, 0               # Fail
bnt3_done:
    sw x9, 56(x10)

    #===========================================
    # Test 8: Zero Offset Branches (edge case)
    #===========================================
    # This would create an infinite loop if taken,
    # so we ensure the condition is false
    li x5, 10
    li x6, 20
    # If x5 == x6, would branch to itself (infinite loop)
    # Since x5 != x6, continues normally
    bne x5, x6, zero_offset_continue
zero_offset_continue:
    li x11, 1600
    sw x11, 60(x10)        # Store success marker

    #===========================================
    # Test 9: Chained Branches
    #===========================================
    # Multiple branches in sequence
    li x5, 1
    beq x5, x5, chain1
    j chain_fail
chain1:
    li x6, 2
    beq x6, x6, chain2
    j chain_fail
chain2:
    li x7, 3
    beq x7, x7, chain3
    j chain_fail
chain3:
    li x8, 1700            # Success - all branches taken
    j chain_done
chain_fail:
    li x8, 0               # Fail
chain_done:
    sw x8, 64(x10)

    #===========================================
    # Test 10: Long Jump Chain (maximum offset simulation)
    #===========================================
    # We can't easily test ±1MB JAL offset in a small test,
    # but we can test a chain of jumps that simulates long distance

    # Jump forward over large block
    j long_forward_end
    # Insert many NOPs to simulate large code section
    .rept 100
    nop
    .endr
long_forward_end:
    li x12, 1800
    sw x12, 68(x10)        # Store success marker

    #===========================================
    # Test 11: Mixed Branch and Jump Offsets
    #===========================================
    # Combine branch and jump in complex pattern
    li x5, 5
    blt x5, x0, mixed_fail # x5 > 0, so branch not taken
    jal x15, mixed_target  # Jump taken
    j mixed_fail
mixed_target:
    li x13, 1900           # Success
    j mixed_done
mixed_fail:
    li x13, 0              # Fail
mixed_done:
    sw x13, 72(x10)

    #===========================================
    # Test 12: Return Address Verification (JAL/JALR)
    #===========================================
    # Test that JAL stores correct return address
    auipc x14, 0           # Get current PC
    jal x15, ra_target
    # Return address should point here
    sub x16, x15, x14      # Calculate offset
    sw x16, 76(x10)        # Store offset (should be 4)
    j ra_done
ra_target:
    jalr x0, 0(x15)        # Return using stored address
ra_done:

    #===========================================
    # Verification Section
    #===========================================
    # Load back critical results for verification
    lw x5, 0(x10)          # Short forward branch
    lw x6, 4(x10)          # Short backward branch
    lw x7, 12(x10)         # BLT test
    lw x8, 28(x10)         # JAL short forward

    #===========================================
    # Test Complete - Set return value
    #===========================================
    li x10, 0              # Return 0 for success

    # Infinite loop to end simulation
    j .
