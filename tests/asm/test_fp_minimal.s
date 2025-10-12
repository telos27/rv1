# Minimal FP Test - Just test FLW and FSW
# This will help us debug if basic FP instructions work

.section .data
.align 2
fp_value:
    .word 0x3F800000    # 1.0

result:
    .word 0x00000000

.section .text
.globl _start

_start:
    # Load address
    la x10, fp_value
    la x11, result

    # Test 1: Simple FP load
    flw f0, 0(x10)      # Load 1.0 into f0

    # Test 2: Simple FP store
    fsw f0, 0(x11)      # Store it back

    # Test 3: Move FP to integer
    fmv.x.w x12, f0     # x12 should be 0x3F800000

    # Set success flag
    li x28, 0xFEEDFACE

    # End
end:
    ebreak
    ebreak
