# test_rvc_simple.s - Simple RVC Integration Test
# Tests that compressed instructions work in the pipeline
# Expected result: x10 = 42

.section .text
.globl _start

_start:
    # Use compressed instructions
    c.li    x10, 0          # x10 = 0
    c.addi  x10, 10         # x10 = 10
    c.li    x11, 5          # x11 = 5
    c.add   x10, x11        # x10 = 15

    # Mix with normal instructions
    addi    x10, x10, 12    # x10 = 27 (32-bit instruction)

    # More compressed
    c.li    x12, 15         # x12 = 15
    c.add   x10, x12        # x10 = 42

    # Success - x10 should be 42
    ebreak
