# load_store.s
# Test load and store operations
# Expected result: x10 = 42

.section .text
.globl _start

_start:
    # Set up base address for data memory
    lui x5, 0x1          # x5 = 0x1000 (data memory base)

    # Test word store and load
    addi x6, x0, 42      # x6 = 42
    sw x6, 0(x5)         # store 42 at address 0x1000
    lw x10, 0(x5)        # load from 0x1000 into x10

    # Test halfword operations
    addi x7, x0, 100     # x7 = 100
    sh x7, 4(x5)         # store halfword at 0x1004
    lh x11, 4(x5)        # load halfword into x11

    # Test byte operations
    addi x8, x0, 255     # x8 = 255
    sb x8, 8(x5)         # store byte at 0x1008
    lb x12, 8(x5)        # load byte (sign-extended) into x12

    # Result should be in x10 = 42
    ebreak
