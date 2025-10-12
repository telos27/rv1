# Test: Minimal CSR Test
# Just test if mscratch CSR works

.section .text
.globl _start

_start:
    # Test: Write and read mscratch
    li      t0, 0x12345678
    csrw    mscratch, t0
    csrr    t1, mscratch

    # Check if read value matches written value
    beq     t0, t1, pass

fail:
    li      t1, 0xDEADDEAD       # Failure marker
    mv      x28, t1
    ebreak

pass:
    li      t1, 0xDEADBEEF       # Success marker
    mv      x28, t1
    ebreak

.align 4
