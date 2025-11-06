.option norvc
.section .text
.globl _start

_start:
    # Test 1: Write to 0x80003000 and read back
    li t0, 0x80003000
    li t1, 0x11111111
    sw t1, 0(t0)
    lw t2, 0(t0)
    
    # Test 2: Write to 0x80003004 and read back
    li t1, 0x22222222
    sw t1, 4(t0)
    lw t3, 4(t0)
    
    # Test 3: Read from 0x80000000 (should be first instruction)
    li t0, 0x80000000
    lw t4, 0(t0)
    
    # Test 4: Read from 0x80003000 again
    li t0, 0x80003000
    lw t5, 0(t0)
    
    # Success
    li x28, 0xDEADBEEF
    ebreak
