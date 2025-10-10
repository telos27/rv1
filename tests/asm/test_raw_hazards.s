# Test RAW (Read-After-Write) Hazard Handling
# This tests back-to-back dependent instructions
# Phase 1 (single-cycle): FAILS due to synchronous register file
# Phase 3 (pipelined with forwarding): Should PASS

.section .text
.globl _start

_start:
    # Test 1: Back-to-back ADD dependency (EX-to-EX forwarding)
    li x1, 10
    li x2, 20
    add x3, x1, x2      # x3 = 30
    add x4, x3, x1      # x4 = 40 (depends on x3 from previous instruction)

    # Test 2: R-type logical operations (AND, OR, XOR)
    li x5, 0xF0F0F0F0
    li x6, 0x0F0F0F0F
    and x7, x5, x6      # x7 = 0x00000000
    or  x8, x5, x6      # x8 = 0xFFFFFFFF
    xor x9, x5, x6      # x9 = 0xFFFFFFFF

    # Test 3: Chained dependencies
    li x10, 5
    add x11, x10, x10   # x11 = 10
    add x12, x11, x10   # x12 = 15 (depends on x11)
    add x13, x12, x11   # x13 = 25 (depends on x12)

    # Test 4: Right shifts (previously failing)
    li x14, 0x80000000
    srl x15, x14, x10   # x15 = 0x80000000 >> 5 = 0x04000000
    sra x16, x14, x10   # x16 = 0x80000000 >> 5 (arithmetic) = 0xFC000000

    # Test 5: Load-use hazard (should stall 1 cycle)
    li x17, 0x400
    sw x4, 0(x17)       # Store x4 (40) to memory
    lw x18, 0(x17)      # Load from memory
    add x19, x18, x1    # Use loaded value immediately (hazard!)

    # Expected results:
    # x4  = 40 (0x28)
    # x7  = 0x00000000
    # x8  = 0xFFFFFFFF
    # x9  = 0xFFFFFFFF
    # x13 = 25 (0x19)
    # x15 = 0x04000000
    # x16 = 0xFC000000
    # x19 = 50 (0x32)

    # Set return value to magic number if all tests pass
    li x10, 0xDEADBEEF

    # Exit
    ebreak
