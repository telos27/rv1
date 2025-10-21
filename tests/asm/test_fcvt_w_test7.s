# Test fcvt.w.s 1.1 specifically (test #7 from compliance suite)
# Expected: result=1, flags=0x01 (NX)

.section .text
.globl _start

_start:
  # Load 1.1 into f1
  lui  t0, 0x3f8cd      # Upper 20 bits of 0x3f8ccccd (1.1 in FP32)
  addi t0, t0, -819     # Add lower 12 bits: 0xccd = -819 signed
  fmv.w.x f1, t0        # Move to FP register

  # Convert to integer
  fcvt.w.s a0, f1, rtz  # Convert with RTZ rounding

  # Read FFLAGS
  frflags a1

  # Store results for inspection
  # a0 should = 1
  # a1 should = 0x01 (NX flag)

  # End test
  li t0, 1
  beq a0, t0, check_flags
  j fail

check_flags:
  li t0, 0x01
  beq a1, t0, pass
  j fail

pass:
  # Write success indicator
  li a0, 42
  j done

fail:
  # Write failure indicator
  li a0, 99

done:
  # Infinite loop
  j done
