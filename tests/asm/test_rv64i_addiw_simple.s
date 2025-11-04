# Minimal RV64I ADDIW test
.section .text
.globl _start

_start:
    # Test ADDIW - simplest word operation
    li x1, 5
    addiw x2, x1, 10      # x2 = 15

    # Check result
    li x3, 15
    bne x2, x3, fail

pass:
    li a0, 1              # Success
    j done

fail:
    li a0, 0              # Failure

done:
    # Write result
    li t0, 0x23e8
    sw a0, 0(t0)
    ebreak
