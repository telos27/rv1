# Minimal M extension debug test
# Purpose: Isolate the post-MUL instruction execution issue
# Expected behavior: All instructions after MUL should execute correctly
# Author: Debug session 2025-10-10

.section .text
.globl _start

_start:
    # Test 1: MUL followed by immediate NOPs
    li a0, 5                # a0 = 5
    li a1, 10               # a1 = 10
    mul a2, a0, a1          # a2 = 5 × 10 = 50 (0x32)

    # These NOPs should execute - test if pipeline resumes
    nop                     # Should execute
    nop                     # Should execute
    nop                     # Should execute
    nop                     # Should execute

    # Test 2: Simple load after NOPs
    li a3, 0x111            # a3 = 0x111 (test if this executes)
    li a4, 0x222            # a4 = 0x222 (test if this executes)

    # Test 3: Another MUL to see if second M instruction works
    li a5, 3                # a5 = 3
    li a6, 7                # a6 = 7
    mul a7, a5, a6          # a7 = 3 × 7 = 21 (0x15)

    # More NOPs
    nop
    nop
    nop
    nop

    # Test 4: Verify results with markers
    li t0, 50               # Expected a2 value
    li t1, 0x111            # Expected a3 value
    li t2, 0x222            # Expected a4 value
    li t3, 21               # Expected a7 value

    # Success marker
    li a0, 0x600D           # GOOD indicator

    # Pipeline drain
    nop
    nop
    nop
    nop
    ebreak

# Expected final register state:
# a0 = 0x0000600D (GOOD)
# a1 = 0x0000000A (10)
# a2 = 0x00000032 (50 - first MUL)
# a3 = 0x00000111 (should be set after first MUL)
# a4 = 0x00000222 (should be set after first MUL)
# a5 = 0x00000003 (3)
# a6 = 0x00000007 (7)
# a7 = 0x00000015 (21 - second MUL)
# t0 = 0x00000032 (50)
# t1 = 0x00000111
# t2 = 0x00000222
# t3 = 0x00000015 (21)
