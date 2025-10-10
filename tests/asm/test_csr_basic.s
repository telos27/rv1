# Test CSR instructions
# Simple test of CSR read/write operations

.section .text
.globl _start

_start:
    # Test 1: Write to mstatus and read back
    li   x1, 0x1800          # mstatus value (MPP=11, MIE=0)
    csrrw x2, mstatus, x1    # Write x1 to mstatus, read old to x2

    # Test 2: Read mstatus to verify write
    csrrs x3, mstatus, x0    # Read mstatus to x3 (no write, x0 = 0)

    # Test 3: Set bits in mstatus
    li   x4, 0x08            # MIE bit (bit 3)
    csrrs x5, mstatus, x4    # Set MIE bit, read old to x5

    # Test 4: Read mstatus again
    csrrs x6, mstatus, x0    # Read mstatus to x6

    # Test 5: Clear bits in mstatus
    li   x7, 0x08            # MIE bit
    csrrc x8, mstatus, x7    # Clear MIE bit, read old to x8

    # Test 6: Immediate form - CSRRWI
    csrrwi x9, mstatus, 5    # Write immediate 5 to mstatus

    # Test 7: Immediate form - CSRRSI
    csrrsi x10, mstatus, 10  # Set bits using immediate 10

    # Test 8: Immediate form - CSRRCI
    csrrci x11, mstatus, 2   # Clear bits using immediate 2

    # End test - infinite loop
_end:
    j _end
