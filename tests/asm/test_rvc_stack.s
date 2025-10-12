# test_rvc_stack.s - RVC Stack Operations Test
# Tests compressed stack-relative load/store instructions
# Expected result: x28 = 0xC0FFEE00 (success marker)

.section .text
.globl _start

_start:
    # Initialize stack pointer
    lui     x2, 0x10        # SP = 0x10000
    c.addi16sp -64          # SP = SP - 64 = 0x10000 - 64 = 0xFFC0

    # Save registers using C.SWSP (store word stack pointer)
    c.li    x10, 0x11       # x10 = 17
    c.li    x11, 0x22       # x11 = 34
    c.li    x12, 0x33       # x12 = 51

    c.swsp  x10, 0          # Store x10 at SP+0
    c.swsp  x11, 4          # Store x11 at SP+4
    c.swsp  x12, 8          # Store x12 at SP+8

    # Clear registers
    c.li    x10, 0
    c.li    x11, 0
    c.li    x12, 0

    # Load registers using C.LWSP (load word stack pointer)
    c.lwsp  x10, 0          # Load x10 from SP+0 (should be 0x11)
    c.lwsp  x11, 4          # Load x11 from SP+4 (should be 0x22)
    c.lwsp  x12, 8          # Load x12 from SP+8 (should be 0x33)

    # Verify values
    c.addi  x10, -0x11      # x10 = 0x11 - 0x11 = 0 (if correct)
    c.addi  x11, -0x22      # x11 = 0x22 - 0x22 = 0 (if correct)
    c.addi  x12, -0x33      # x12 = 0x33 - 0x33 = 0 (if correct)

    # Test C.ADDI4SPN (add immediate scaled by 4 to SP)
    c.addi4spn x13, 16      # x13 = SP + 16

    # Test compressed load/store with offset
    c.li    x14, 0x77       # x14 = 119
    c.sw    x14, 12(x2)     # Store at SP+12
    c.lw    x15, 12(x2)     # Load from SP+12 (should be 0x77)

    # Check if load worked
    c.sub   x15, x14        # x15 = x15 - x14 (should be 0)

    # Sum all results (should all be 0)
    c.add   x10, x11
    c.add   x10, x12
    c.add   x10, x15

    # If x10 == 0, test passed
    c.bnez  x10, fail

success:
    # Restore stack pointer
    c.addi16sp 64           # SP = SP + 64 = 0x10000

    # Store success marker
    lui     x28, 0xC0FFE    # Load upper immediate
    addi    x28, x28, 0xE00 # x28 = 0xC0FFEE00

    # Signal completion
    nop
    nop
    nop
    ebreak

fail:
    # Store failure marker
    lui     x28, 0xDEADD    # Load upper immediate
    addi    x28, x28, 0xEAD # x28 = 0xDEADDEAD

    nop
    nop
    nop
    ebreak
