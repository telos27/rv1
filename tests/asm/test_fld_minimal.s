# Minimal FLD Test
# Test if FLD correctly loads 64-bit double-precision values

.section .text
.globl _start

_start:
    # Load address of test data
    la x10, test_data_neg_inf

    # FLD: Load double-precision negative infinity
    fld f10, 0(x10)

    # FCLASS.D: Classify the value
    fclass.d x11, f10

    # x11 should be 0x001 (negative infinity)
    # Store result for inspection
    la x12, result
    sw x11, 0(x12)

    # End test
    li x17, 93  # exit syscall
    ecall

.section .data
.align 3
test_data_neg_inf:
    .dword 0xfff0000000000000  # Negative infinity

result:
    .word 0
