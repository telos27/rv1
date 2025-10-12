# Test FP Load/Store Only
# Tests: FLW, FSW only (no arithmetic)

.section .data
.align 2
fp_input:
    .word 0x40400000    # 3.0 in IEEE 754
result:
    .word 0x00000000    # Space for result

.section .text
.globl _start

_start:
    # Load base addresses
    la x10, fp_input
    la x11, result

    # Load FP value
    flw f0, 0(x10)      # f0 = 3.0

    # Store FP value
    fsw f0, 0(x11)      # Store 3.0 to result

    # Load result as integer to verify
    lw x12, 0(x11)      # x12 should be 0x40400000

    # Check if result is correct
    li x13, 0x40400000  # Expected value
    beq x12, x13, success

    # Failure
    li x28, 0xBADC0DE
    ebreak

success:
    li x28, 0xDEADBEEF

end:
    ebreak

# Expected:
# x12 = 0x40400000
# x28 = 0xDEADBEEF if test passes
