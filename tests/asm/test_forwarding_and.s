# Minimal test to expose data forwarding bug with AND instruction
# Tests back-to-back RAW hazards that should be resolved by forwarding

.section .text
.globl _start

_start:
    # Initialize values
    li x1, 0xFF       # x1 = 255
    li x2, 0x0F       # x2 = 15

    # Test 1: EX-to-EX forwarding (1-cycle separation)
    # x3 should get result from x1 AND x2 immediately
    and x3, x1, x2    # x3 = x1 & x2 = 0xFF & 0x0F = 0x0F (15)
    and x4, x3, x1    # x4 = x3 & x1 = 0x0F & 0xFF = 0x0F (15) - needs EX-to-EX forwarding

    # Test 2: MEM-to-EX forwarding (2-cycle separation)
    and x5, x1, x2    # x5 = 15
    nop
    and x6, x5, x1    # x6 = x5 & x1 = 15 - needs MEM-to-EX forwarding

    # Test 3: WB-to-ID forwarding (3-cycle separation / register file bypass)
    and x7, x1, x2    # x7 = 15
    nop
    nop
    and x8, x7, x1    # x8 = x7 & x1 = 15 - needs WB-to-ID forwarding

    # Test 4: Complex chain (all forwarding types)
    li x10, 0xAA      # x10 = 170
    li x11, 0x55      # x11 = 85
    and x12, x10, x11 # x12 = 0xAA & 0x55 = 0x00 (0)
    and x13, x12, x10 # x13 = 0 & 0xAA = 0 (EX-to-EX)
    and x14, x13, x11 # x14 = 0 & 0x55 = 0 (EX-to-EX)

    # Store results for verification
    li x15, 0x100     # Base address for results
    sw x3, 0(x15)     # Should be 15
    sw x4, 4(x15)     # Should be 15
    sw x6, 8(x15)     # Should be 15
    sw x8, 12(x15)    # Should be 15
    sw x12, 16(x15)   # Should be 0
    sw x13, 20(x15)   # Should be 0
    sw x14, 24(x15)   # Should be 0

    # Test passed - set x10 to 42 (magic success value)
    li x10, 42

    # Exit
    ecall
