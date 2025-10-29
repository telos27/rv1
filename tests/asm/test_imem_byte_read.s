# test_imem_byte_read.s - Test IMEM byte-level reads
# Tests that we can read individual bytes from IMEM data port
# This is critical for .rodata copying in FreeRTOS

.section .text
.globl _start

_start:
    # Test 1: Read word at 0x100 (should work - word-aligned)
    li t0, 0x100
    lw t1, 0(t0)
    li t2, 0xDEADBEEF
    bne t1, t2, fail

    # Test 2: Read byte at offset +0
    li t0, 0x100
    lbu t1, 0(t0)
    li t2, 0xEF          # Expecting low byte of 0xDEADBEEF
    bne t1, t2, fail

    # Test 3: Read byte at offset +1
    li t0, 0x100
    lbu t1, 1(t0)        # Read at 0x101
    li t2, 0xBE          # Expecting second byte
    bne t1, t2, fail

    # Test 4: Read byte at offset +2
    li t0, 0x100
    lbu t1, 2(t0)        # Read at 0x102
    li t2, 0xAD          # Expecting third byte
    bne t1, t2, fail

    # Test 5: Read byte at offset +3
    li t0, 0x100
    lbu t1, 3(t0)        # Read at 0x103
    li t2, 0xDE          # Expecting high byte
    bne t1, t2, fail

    # Test 6: Read halfword at offset +0
    li t0, 0x100
    lhu t1, 0(t0)
    li t2, 0xBEEF        # Low halfword
    bne t1, t2, fail

    # Test 7: Read halfword at offset +2
    li t0, 0x100
    lhu t1, 2(t0)
    li t2, 0xDEAD        # High halfword
    bne t1, t2, fail

pass:
    li a0, 0             # Exit code 0 (success)
    j done

fail:
    li a0, 1             # Exit code 1 (failure)

done:
    # Testbench will detect PC stuck here
    j done

.section .rodata
.align 4
test_data:
    .word 0xDEADBEEF
