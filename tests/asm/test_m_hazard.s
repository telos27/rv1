# Test M Extension Data Hazard
# Minimal test to reproduce the division bug

.section .text
.globl _start

_start:
    # Initialize registers to known bad values
    li a1, 100
    li a2, 200

    # Now set them to the values we actually want
    li a1, 1        # a1 = 1
    li a2, 0        # a2 = 0
    divu a4, a1, a2  # a4 = 1 / 0 = 0xFFFFFFFF

    # Check result
    li a5, -1       # a5 = 0xFFFFFFFF
    beq a4, a5, pass

fail:
    li a0, 1
    j end

pass:
    li a0, 0

end:
    # Write result to address 0x1000 for testbench
    li t0, 0x1000
    sw a0, 0(t0)

    # Infinite loop
    j end
