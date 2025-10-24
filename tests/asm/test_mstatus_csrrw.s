# Test: MSTATUS CSR Read/Write Test
# Test if mstatus CSR works

.section .text
.globl _start

_start:
    # Test: Write and read mstatus
    li      t0, 0x00001888          # MPP=11, MPIE=1, MIE=1
    csrw    mstatus, t0
    csrr    t1, mstatus

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
