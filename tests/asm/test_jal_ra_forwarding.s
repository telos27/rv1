# JAL/JALR Return Address Forwarding Test
# This test specifically targets potential register file forwarding bugs
# when JAL/JALR writes are immediately followed by reads of the link register.
#
# Tests:
# 1. JAL followed immediately by ra read
# 2. JALR followed immediately by ra read
# 3. Back-to-back JAL instructions to same register
# 4. JAL in pipeline with other register writes
# 5. Nested function calls (JAL overwrites previous ra)

.section .text
.globl _start

_start:
    # Initialize test counter
    li s0, 0

    #========================================
    # Test 1: JAL followed immediately by ra read
    #========================================
test1:
    li ra, 0xDEADBEEF          # Poison ra with known bad value
    auipc s1, 0                # s1 = current PC
    addi s1, s1, 8             # s1 = PC of next instruction (jal)
    jal ra, func1              # Should write ra = PC+4
    # Immediately use ra here (no delay)
    mv s2, ra                  # s2 = ra (test forwarding)

    # Verify ra was written (should not be 0xDEADBEEF)
    li t0, 0xDEADBEEF
    beq s2, t0, fail           # If still poisoned, forwarding failed

    # Verify ra points to this instruction (or nearby)
    addi s1, s1, 4             # s1 = expected ra (PC of jal + 4)
    bne s2, s1, fail           # ra should match expected value

    addi s0, s0, 1             # Test passed

    #========================================
    # Test 2: JALR followed immediately by ra read
    #========================================
test2:
    li ra, 0xBADC0FFE          # Poison ra again
    auipc t1, 0                # t1 = current PC
    addi t1, t1, 20            # t1 = address of func2
    auipc s1, 0                # s1 = current PC
    addi s1, s1, 8             # s1 = PC of next instruction (jalr)
    jalr ra, t1, 0             # Should write ra = PC+4, jump to func2
    # Immediately use ra here
    mv s2, ra                  # s2 = ra (test forwarding)

    # Verify ra was written
    li t0, 0xBADC0FFE
    beq s2, t0, fail           # If still poisoned, failed

    # Verify ra value
    addi s1, s1, 4             # s1 = expected ra
    bne s2, s1, fail

    addi s0, s0, 1             # Test passed

    #========================================
    # Test 3: Back-to-back JAL to same register
    #========================================
test3:
    auipc s1, 0                # s1 = current PC
    addi s1, s1, 8             # s1 = PC of first jal
    jal ra, func1              # First JAL, ra = PC1+4
    mv s2, ra                  # Save first ra

    auipc s1, 0                # s1 = current PC
    addi s1, s1, 8             # s1 = PC of second jal
    jal ra, func1              # Second JAL, ra = PC2+4 (overwrites!)
    mv s3, ra                  # Save second ra

    # Verify second JAL overwrote first
    beq s2, s3, fail           # They should be different

    # Verify second ra is correct
    addi s1, s1, 4             # s1 = expected second ra
    bne s3, s1, fail

    addi s0, s0, 1             # Test passed

    #========================================
    # Test 4: JAL with competing register writes
    #========================================
test4:
    li t1, 0x11111111          # Setup competing write
    auipc s1, 0
    addi s1, s1, 8
    jal ra, func1              # JAL writes ra
    addi t1, t1, 1             # Competing ALU operation in pipeline
    mv s2, ra                  # Read ra (should be from JAL, not t1)

    # Verify ra is NOT corrupted by t1 value
    li t0, 0x11111111
    beq s2, t0, fail           # ra should not be t1's value
    beq s2, zero, fail         # ra should not be zero

    addi s0, s0, 1             # Test passed

    #========================================
    # Test 5: Nested calls (ra overwrite)
    #========================================
test5:
    # Outer call
    auipc s1, 0
    addi s1, s1, 8
    jal ra, nested_outer       # Outer call
    mv s2, ra                  # Should have outer return address

    # Verify we got back the right ra
    addi s1, s1, 4
    bne s2, s1, fail

    addi s0, s0, 1             # Test passed

    #========================================
    # Test 6: JAL x0 doesn't corrupt ra
    #========================================
test6:
    li ra, 0xC0DEC0DE          # Set ra to known value
    jal x0, func1              # JAL x0 (no link)
    mv s2, ra                  # ra should be unchanged

    li t0, 0xC0DEC0DE
    bne s2, t0, fail           # ra should still be 0xC0DEC0DE

    addi s0, s0, 1             # Test passed

    #========================================
    # All tests passed
    #========================================
success:
    li a0, 6                   # Number of tests passed
    bne s0, a0, fail           # Verify counter matches

    li x28, 0xFEEDFACE         # Success marker
    ebreak

fail:
    li x28, 0xDEADDEAD         # Failure marker
    ebreak

#========================================
# Helper functions
#========================================

func1:
    # Simple function that just returns
    ret

func2:
    # Another simple function
    ret

nested_outer:
    # Save outer ra
    addi sp, sp, -8
    sw ra, 0(sp)

    # Inner call - will overwrite ra
    jal ra, nested_inner

    # Restore outer ra
    lw ra, 0(sp)
    addi sp, sp, 8
    ret

nested_inner:
    # Just return
    ret
