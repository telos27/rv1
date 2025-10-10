# Simple RAW hazard test
# Tests back-to-back ADD dependency

.section .text
.globl _start

_start:
    # Simple back-to-back dependency
    li x1, 10           # x1 = 10
    li x2, 20           # x2 = 20
    add x3, x1, x2      # x3 = 30
    add x4, x3, x1      # x4 = 40 (x3 is forwarded from EX/MEM stage)

    # Store result for verification
    li x10, 0x28        # Expected value: 40 (0x28)

    ebreak
