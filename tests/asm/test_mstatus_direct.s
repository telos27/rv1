# Direct test - write and read mstatus
.section .text
.globl _start

_start:
    # Load trap vector addresses
    la t0, m_trap_handler
    csrw mtvec, t0

    # Test 1: Write to mscratch (known working CSR)
    li t0, 0x12345678
    csrw mscratch, t0
    csrr a0, mscratch           # a0 should = 0x12345678

    # Test 2: Write to mstatus with CSRRW
    li t1, 0x00001888           # MIE|MPIE|MPP=11 (bits 3,7,11-12)
    csrw mstatus, t1

    # Test 3: Read mstatus back
    csrr a1, mstatus            # a1 should = 0x1888, but reads 0x0000!

    # Store results for debug
    mv t3, a1                   # t3 = mstatus value for debug output

    # Check if mstatus read worked
    li t4, 0x00001888
    bne a1, t4, fail

pass:
    li a7, 0xDEADBEEF
    ebreak

fail:
    li a7, 0xDEADDEAD
    ebreak

m_trap_handler:
    li t3, 0xBADBAD00
    ebreak

.align 4
