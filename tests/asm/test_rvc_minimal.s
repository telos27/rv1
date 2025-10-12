# test_rvc_minimal.s - Minimal RVC test with only 4-byte aligned compressed instructions
# Expected result: x10 = 15

.section .text
.globl _start

_start:
    c.li    x10, 10         # x10 = 10 (at address 0x00)
    c.nop                   # nop (at address 0x02)
    c.li    x11, 5          # x11 = 5 (at address 0x04)
    c.nop                   # nop (at address 0x06)
    c.add   x10, x11        # x10 = 15 (at address 0x08)
    c.nop                   # nop (at address 0x0A)
    c.ebreak                # ebreak (at address 0x0C)
