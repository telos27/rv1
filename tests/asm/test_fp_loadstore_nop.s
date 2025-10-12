# Test FP Load/Store with NOPs
# Add NOPs between FLW and FSW to avoid hazard

.section .data
.align 2
fp_input:
    .word 0x40400000    # 3.0
result:
    .word 0x00000000

.section .text
.globl _start

_start:
    la x10, fp_input
    la x11, result

    flw f0, 0(x10)      # Load 3.0
    nop
    nop
    nop
    fsw f0, 0(x11)      # Store 3.0

    lw x12, 0(x11)      # Load as integer
    li x13, 0x40400000
    beq x12, x13, success

    li x28, 0xBADC0DE
    j end

success:
    li x28, 0xDEADBEEF

end:
    ebreak
