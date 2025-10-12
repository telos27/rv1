# Floating-Point CSR Test
# Tests: FCSR, FRM, FFLAGS register operations
# Tests the critical fix for CSR integration with dynamic rounding modes

.section .text
.globl _start

_start:
    # Test 1: Read initial FCSR value
    # FCSR = 0x003, FFLAGS = 0x001, FRM = 0x002
    csrr x10, 0x003     # Read fcsr
    csrr x11, 0x001     # Read fflags (should be 0)
    csrr x12, 0x002     # Read frm (should be 0 = RNE)

    # Test 2: Write to FRM - Set rounding mode
    # Rounding modes:
    # 000 = RNE (Round to Nearest, ties to Even) - default
    # 001 = RTZ (Round towards Zero)
    # 010 = RDN (Round Down, towards -Inf)
    # 011 = RUP (Round Up, towards +Inf)
    # 100 = RMM (Round to Nearest, ties to Max Magnitude)

    # Set rounding mode to RTZ (Round towards Zero)
    li x13, 0x001       # RTZ = 001
    csrw 0x002, x13     # Write to frm

    # Read back to verify
    csrr x14, 0x002     # Should be 0x001
    csrr x15, 0x003     # fcsr should have frm in bits [7:5]

    # Test 3: Test that rounding mode affects operations
    la x20, fp_data
    flw f0, 0(x20)      # f0 = 1.1 (approx 0x3F8CCCCD)
    flw f1, 4(x20)      # f1 = 1.9 (approx 0x3FF33333)

    # Convert to integer with RTZ (should truncate)
    fcvt.w.s x16, f0    # 1.1 -> 1 (truncate towards zero)
    fcvt.w.s x17, f1    # 1.9 -> 1 (truncate towards zero)

    # Test 4: Change to RDN (Round Down) mode
    li x18, 0x002       # RDN = 010
    csrw 0x002, x18     # Write to frm

    # Convert with RDN (should round down/towards -infinity)
    fcvt.w.s x19, f0    # 1.1 -> 1 (floor)
    fcvt.w.s x21, f1    # 1.9 -> 1 (floor)

    # Test 5: Test FFLAGS accumulation
    # Clear fflags first
    li x22, 0
    csrw 0x001, x22

    # Generate division by zero exception
    la x23, fp_zero
    flw f2, 0(x23)      # f2 = 0.0
    flw f3, 4(x23)      # f3 = 1.0

    # f4 = 1.0 / 0.0 = +Infinity, sets DZ flag (bit 3)
    fdiv.s f4, f3, f2

    # Read fflags - should have DZ (0x08) set
    csrr x24, 0x001     # fflags should be 0x08

    # Generate overflow exception
    # Load very large numbers
    la x25, fp_large
    flw f5, 0(x25)      # f5 = large value (near max float)
    flw f6, 4(x25)      # f6 = large value

    # Multiply to cause overflow -> sets OF flag (bit 2)
    fmul.s f7, f5, f6

    # Read fflags - should have DZ | OF (0x0C)
    csrr x26, 0x001     # fflags should be 0x0C

    # Test 6: Test FCSR read/write combining frm and fflags
    # fcsr[7:5] = frm, fcsr[4:0] = fflags
    # Current: frm=010, fflags=0x0C
    # Expected fcsr = (010 << 5) | 0x0C = 0x4C

    csrr x27, 0x003     # Read full fcsr

    # Write new fcsr value
    li x28, 0x60        # frm=011 (RUP), fflags=00000
    csrw 0x003, x28

    # Verify frm and fflags changed
    csrr x29, 0x002     # frm should be 3 (RUP)
    csrr x30, 0x001     # fflags should be 0

    # Success marker
    li x31, 0xFEEDF00D

end:
    j end

.section .data
.align 2
fp_data:
    .word 0x3F8CCCCD    # 1.1 (approximate)
    .word 0x3FF33333    # 1.9 (approximate)

fp_zero:
    .word 0x00000000    # 0.0
    .word 0x3F800000    # 1.0

fp_large:
    .word 0x7F000000    # Very large value (~1.7e38)
    .word 0x7F000000    # Very large value

# Expected Results:
# x10 = initial fcsr (likely 0x000)
# x11 = initial fflags (0x00)
# x12 = initial frm (0x00 = RNE)
# x14 = 0x001 (RTZ mode set)
# x16 = 1 (1.1 truncated to 1)
# x17 = 1 (1.9 truncated to 1)
# x19 = 1 (1.1 floored to 1)
# x21 = 1 (1.9 floored to 1)
# x24 = 0x08 (DZ flag set after 1.0/0.0)
# x26 = 0x0C (DZ | OF flags set)
# x27 = 0x4C (fcsr with frm=010, fflags=0x0C)
# x29 = 3 (RUP mode)
# x30 = 0 (fflags cleared)
# x31 = 0xFEEDF00D (success)
