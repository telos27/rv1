# test_rvc_basic.s - Basic RVC (Compressed) Instruction Test
# Tests fundamental compressed instructions
# Expected result: x28 = 0xDEADBEEF (success marker)

.section .text
.globl _start

_start:
    # Initialize registers
    c.li    x10, 0          # C.LI: Load immediate (x10 = 0)
    c.li    x11, 1          # C.LI: Load immediate (x11 = 1)
    c.li    x12, -1         # C.LI: Load immediate (x12 = -1)

    # Test C.ADDI (add immediate)
    c.addi  x10, 5          # x10 = 0 + 5 = 5
    c.addi  x11, 10         # x11 = 1 + 10 = 11
    c.addi  x12, 1          # x12 = -1 + 1 = 0

    # Test C.ADD (register-register add)
    c.add   x10, x11        # x10 = 5 + 11 = 16
    c.add   x10, x12        # x10 = 16 + 0 = 16

    # Test C.SUB (register-register subtract)
    c.sub   x10, x11        # x10 = 16 - 11 = 5

    # Test C.AND, C.OR, C.XOR
    c.li    x13, 0x0F       # x13 = 15
    c.li    x14, 0x33       # x14 = 51 (0x33)

    c.and   x13, x14        # x13 = 0x0F & 0x33 = 0x03
    c.or    x13, x14        # x13 = 0x03 | 0x33 = 0x33
    c.xor   x13, x14        # x13 = 0x33 ^ 0x33 = 0x00

    # Test shift instructions
    c.li    x15, 8          # x15 = 8
    c.slli  x15, 2          # x15 = 8 << 2 = 32
    c.srli  x15, 1          # x15 = 32 >> 1 = 16
    c.srai  x15, 2          # x15 = 16 >> 2 = 4 (arithmetic)

    # Test C.MV (move)
    c.mv    x20, x15        # x20 = x15 = 4

    # Test C.ANDI
    c.li    x21, 0x3F       # x21 = 63 (0x3F)
    c.andi  x21, 0x0F       # x21 = 0x3F & 0x0F = 0x0F = 15

    # Test C.LUI (load upper immediate)
    c.lui   x22, 0x12       # x22 = 0x12000

    # Store success marker
    lui     x28, 0xDEADB    # Load upper immediate
    addi    x28, x28, 0xEEF # x28 = 0xDEADBEEF

    # Signal completion
    nop
    nop
    nop
    ebreak
