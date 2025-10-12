# test_rvc_mixed.s - Mixed Compressed and Non-Compressed Instructions Test
# Tests interleaving of 16-bit and 32-bit instructions
# Expected result: x28 = 0x0000BEEF (success marker)

.section .text
.globl _start

_start:
    # Mix compressed and non-compressed instructions
    c.li    x10, 10         # Compressed: x10 = 10
    addi    x10, x10, 5     # Non-compressed: x10 = 15
    c.addi  x10, 5          # Compressed: x10 = 20
    addi    x10, x10, -10   # Non-compressed: x10 = 10

    # Test alignment: compressed followed by compressed
    c.li    x11, 1
    c.addi  x11, 2          # x11 = 3

    # Test alignment: non-compressed followed by compressed
    addi    x12, x0, 5      # x12 = 5
    c.add   x12, x11        # x12 = 5 + 3 = 8

    # Test alignment: compressed followed by non-compressed
    c.li    x13, 7
    add     x13, x13, x12   # x13 = 7 + 8 = 15

    # Complex mixing
    c.mv    x14, x10        # x14 = 10
    slli    x14, x14, 1     # x14 = 20
    c.addi  x14, -5         # x14 = 15
    sub     x14, x14, x11   # x14 = 15 - 3 = 12
    c.add   x14, x12        # x14 = 12 + 8 = 20

    # Test with branches (mixed alignment)
    c.li    x15, 0
    c.addi  x15, 1          # x15 = 1
    beq     x15, x11, skip1 # Not taken (1 != 3)
    c.addi  x15, 1          # x15 = 2

skip1:
    c.bnez  x15, skip2      # Taken (x15 != 0)
    addi    x15, x15, 100   # Should not execute

skip2:
    # Test jump alignment
    c.j     target1         # Compressed jump
    c.li    x20, 0xFF       # Should not execute

target1:
    jal     x1, func1       # Non-compressed jump and link
    # Returns here
    c.addi  x16, 0          # x16 gets return value

    # Verify all calculations
    # x10 should be 10
    c.addi  x10, -10        # x10 = 0
    # x11 should be 3
    addi    x11, x11, -3    # x11 = 0
    # x12 should be 8
    c.addi  x12, -8         # x12 = 0
    # x13 should be 15
    addi    x13, x13, -15   # x13 = 0
    # x14 should be 20
    c.addi  x14, -20        # x14 = 0
    # x15 should be 2
    c.addi  x15, -2         # x15 = 0
    # x16 should be 99
    addi    x16, x16, -99   # x16 = 0

    # Sum all (should be 0 if all correct)
    add     x10, x10, x11
    c.add   x10, x12
    add     x10, x10, x13
    c.add   x10, x14
    add     x10, x10, x15
    c.add   x10, x16

    # Check result
    c.bnez  x10, fail

success:
    lui     x28, 0x0        # Load upper immediate
    addi    x28, x28, 0xBEF # x28 = 0x0000BEEF

    nop
    nop
    nop
    ebreak

fail:
    lui     x28, 0x0BAD     # Load upper immediate
    addi    x28, x28, 0xC0D # x28 = 0x0BADC0DE

    nop
    nop
    nop
    ebreak

func1:
    c.li    x16, 99         # Return value = 99
    c.jr    x1              # Compressed return
