# Test Integer Load (sanity check)

.section .data
.align 2
test_data:
    .word 0x40400000    # 3.0 in IEEE 754

.section .text
.globl _start

_start:
    la x10, test_data
    lw x12, 0(x10)      # Load as integer

    li x13, 0x40400000  # Expected
    beq x12, x13, success

    li x28, 0xBADC0DE
    j end

success:
    li x28, 0xDEADBEEF

end:
    ebreak
