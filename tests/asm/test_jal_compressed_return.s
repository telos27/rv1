# Test JAL followed by compressed instruction at return address
# This tests the specific pattern causing FreeRTOS to hang:
# - JAL to function (4-byte instruction)
# - Compressed instruction (2-byte) at return address
#
# Pattern from FreeRTOS:
#   4c6: jal ra, 2000 <memset>  # 4-byte JAL
#   4ca: c.lw a5, 48(s1)         # 2-byte C.LW (return address)

.section .text
.globl _start

_start:
    # Initialize test values
    li sp, 0x80001000       # Set up stack
    li s1, 0x80000800       # Set s1 for c.lw test
    li a5, 0xDEADBEEF
    sw a5, 48(s1)           # Store test value

    # Test: JAL followed by compressed instruction
    # The JAL is 4 bytes, so return address should be PC+4
    jal ra, test_function   # Call function
    c.lw a5, 48(s1)         # <-- Return address (2-byte compressed)
    c.addi a5, 1            # Should execute this after return

    # Check if we got here correctly
    li a0, 0
    li a1, 0xA5A5          # Check value
    bne a5, a1, test_fail

    # SUCCESS
    li a0, 0
    j test_pass

test_function:
    # Simple function that just returns
    li t0, 0x12345678
    ret

test_pass:
    li a0, 0
    li a1, 42
    j exit

test_fail:
    li a0, 1
    li a1, 0
    j exit

exit:
    # Write result to test address
    li t0, 0x80002000
    sw a0, 0(t0)

    # End simulation
    ebreak
