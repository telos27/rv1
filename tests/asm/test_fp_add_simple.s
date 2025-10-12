# Simplest FP Add Test
# Tests: FLW, FADD.S, FSW only
# Strategy: Store FP results to memory, then load as integers to check

.section .data
.align 2
fp_input:
    .word 0x3F800000    # 1.0 in IEEE 754
    .word 0x40000000    # 2.0
result:
    .word 0x00000000    # Space for result

.section .text
.globl _start

_start:
    # Load base addresses
    la x10, fp_input
    la x11, result

    # Load FP values
    flw f0, 0(x10)      # f0 = 1.0
    flw f1, 4(x10)      # f1 = 2.0

    # FP Add: f2 = f0 + f1 = 1.0 + 2.0 = 3.0
    fadd.s f2, f0, f1

    # Store result to memory
    fsw f2, 0(x11)      # Store 3.0 to result

    # Load result as integer to verify
    lw x12, 0(x11)      # x12 should be 0x40400000 (3.0 in IEEE 754)

    # Check if result is correct
    li x13, 0x40400000  # Expected value for 3.0
    beq x12, x13, success

    # Failure path
    li x28, 0xBADC0DE
    j end

success:
    li x28, 0xDEADBEEF

end:
    ebreak

# Expected:
# x12 = 0x40400000 (3.0 in IEEE 754)
# x28 = 0xDEADBEEF if test passes
