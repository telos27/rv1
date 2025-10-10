# Minimal test for 1-NOP LUI bug
# Just test the specific failing case

.section .text
.globl _start

_start:
    # Establish a value in x1 first
    lui x1, 0xff010      # x1 = 0xff010000

    # Now test LUI x3 with 1 NOP after a dependent instruction
    addi x2, x1, -256    # x2 = x1 - 256 (uses x1)
    lui x3, 0xff010      # x3 = 0xff010000 (decoder extracts garbage rs1=x1!)
    nop                  # 1 NOP
    addi x4, x3, -256    # x4 = x3 - 256

    # End immediately
    ecall
