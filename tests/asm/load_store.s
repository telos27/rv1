# load_store.s
# Test load and store operations
# Expected results: x10 = 42, x11 = 100, x12 = -1 (0xFFFFFFFF)

.section .text
.globl _start

_start:
    # Set up base address for data memory
    # Using 0x400 (1024) which is in the middle of 4KB data memory (0x000-0xFFF)
    addi x5, x0, 0x400   # x5 = 0x400 (data memory base)

    # Test word store and load
    addi x6, x0, 42      # x6 = 42
    sw x6, 0(x5)         # store 42 at address 0x400
    lw x10, 0(x5)        # load from 0x400 into x10

    # Test halfword operations
    addi x7, x0, 100     # x7 = 100
    sh x7, 4(x5)         # store halfword at 0x404
    lh x11, 4(x5)        # load halfword into x11

    # Test byte operations
    addi x8, x0, 255     # x8 = 255
    sb x8, 8(x5)         # store byte at 0x408
    lb x12, 8(x5)        # load byte (sign-extended) into x12

    # Result should be in x10 = 42
    ebreak
