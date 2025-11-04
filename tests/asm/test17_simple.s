.section .text
.globl _start

_start:
    # Test 17: fcvt.wu.s x, 1.1 with RTZ
    li x3, 17  # Test number in gp
    
    # Load 1.1 (0x3F8CCCCD) into f10
    li t0, 0x3F8CCCCD
    fmv.w.x f10, t0
    
    # Set rounding mode to RTZ (001)
    li t1, 1
    csrrs zero, frm, t1
    
    # Execute fcvt.wu.s
    fcvt.wu.s x10, f10  # a0 = result (should be 1)
    
    # Read flags
    csrrs x11, fflags, zero  # a1 = flags (should be 0x01)
    
    # Expected: a0=1, a1=0x01 (inexact)
    li x12, 1  # expected result
    li x13, 0x01  # expected flags
    
    # Compare result
    bne x10, x12, fail
    # Compare flags
    bne x11, x13, fail
    
    # Success - set gp to 0
    li x3, 0
    j done
    
fail:
    # gp already has test number (17)
    
done:
    li a7, 93  # exit syscall
    ecall

.section .data
