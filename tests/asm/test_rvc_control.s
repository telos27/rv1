# test_rvc_control.s - RVC Control Flow Test
# Tests compressed jump and branch instructions
# Expected result: x28 = 0xFEEDFACE (success marker)

.section .text
.globl _start

_start:
    c.li    x10, 0          # Counter = 0
    c.li    x11, 5          # Target = 5

loop:
    c.addi  x10, 1          # Increment counter
    c.bnez  x10, check      # Branch if not equal to zero (always taken first time)
    c.li    x20, 0xFF       # Should not execute

check:
    c.beqz  x11, done       # Branch if x11 == 0 (not taken initially)
    c.addi  x11, -1         # Decrement target
    c.j     loop            # Jump back to loop

done:
    # Test C.JAL (jump and link)
    c.jal   func1           # Jump to func1, link to x1
    # Should return here
    c.addi  x10, 1          # x10 should now be 5 + 1 = 6

    # Test C.JR (jump register)
    la      x12, target1
    c.jr    x12             # Jump to target1
    c.li    x20, 0xFF       # Should not execute

target1:
    # Test C.JALR (jump and link register)
    la      x13, func2
    c.jalr  x13             # Jump to func2, link to x1
    # Should return here

    # All tests passed
    lui     x28, 0xFEEDF    # Load upper immediate
    addi    x28, x28, 0xACE # x28 = 0xFEEDFACE

    # Signal completion
    nop
    nop
    nop
    ebreak

func1:
    c.addi  x10, 0          # Do nothing, just test call/return
    c.jr    x1              # Return

func2:
    c.li    x14, 42         # x14 = 42
    c.jr    x1              # Return
