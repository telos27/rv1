# Test AUIPC followed by LW using same register
# This tests data hazard detection when LW uses AUIPC result as base

.section .text
.globl _start

_start:
    # Initialize
    li gp, 0                    # Test counter

    # Test 1: AUIPC followed immediately by LW using same register
    li gp, 1
    auipc a4, 0x2               # a4 = PC + 0x2000
    lw a4, -0x1d4(a4)           # Load from a4 + offset
                                # Should use forwarded AUIPC result

    # If we got here without hanging, test passes
    li gp, 0

    # Exit
    li a0, 0
    li a7, 93                   # exit syscall
    ecall

.section .data
.align 12
test_data:
    .word 0x12345678
