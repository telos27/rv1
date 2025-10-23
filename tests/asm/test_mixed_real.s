# test_mixed_real.s - Real mixed 16-bit and 32-bit instructions
# Tests that CPU correctly handles transitions between compressed and normal instructions
# Expected result: x10 = 100

.section .text
.globl _start

_start:
    # Start with compressed
    c.li    x10, 10         # x10 = 10 (2-byte)

    # Force 32-bit instruction (LUI cannot be compressed for high values)
    lui     x11, 0x12345    # x11 = 0x12345000 (4-byte, MUST be 32-bit)

    # Back to compressed
    c.addi  x10, 5          # x10 = 15 (2-byte)

    # Another 32-bit (SRAI with large shift cannot be compressed)
    srai    x12, x11, 20    # x12 = 0x12345000 >> 20 = 0x123 (4-byte)

    # Compressed
    c.li    x13, 30         # x13 = 30 (2-byte)

    # 32-bit ADD (forces 32-bit format)
    .option norvc           # Disable compression for next instruction
    add     x10, x10, x13   # x10 = 45 (4-byte, forced)
    .option rvc             # Re-enable compression

    # Compressed
    c.addi  x10, 31         # x10 = 76 (2-byte, max immediate is 31)
    c.addi  x10, 24         # x10 = 100 (2-byte)

    # Success marker
    li      x28, 0xBEEF     # Success marker
    ebreak
