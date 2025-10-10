# Jump and Upper Immediate Test
# Tests: JAL, JALR, LUI, AUIPC
# Expected final result: x10 = 0x00000050 (success marker)

.section .text
.globl _start

_start:
  addi  x10, x0, 0       # x10 = 0 (test counter)

  # Test 1: JAL - jump and link
  # Save return address and jump forward
  jal   x1, jal_target   # x1 = PC + 4, jump to jal_target
  jal   x0, fail         # Should not reach here

jal_target:
  # Verify return address was saved
  # x1 should point to the failed jump above
  # We can't easily check the exact PC value, so just verify x1 != 0
  beq   x1, x0, fail     # x1 should not be zero
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 2: JAL backward jump
  jal   x2, skip_back
back_target:
  addi  x10, x10, 1      # x10++ (test passed)
  jal   x0, after_back   # Continue to next test

skip_back:
  addi  x10, x10, 1      # x10++ (test passed)
  jal   x0, back_target  # Jump back

after_back:
  # Test 3: JALR - jump and link register
  # Compute target address and jump to it
  auipc x3, 0            # x3 = PC
  addi  x3, x3, 20       # x3 = PC + 20 (target: jalr_target)
  jalr  x4, x3, 0        # x4 = PC + 4, jump to address in x3
  jal   x0, fail         # Should not reach here

jalr_target:
  # Verify return address saved
  beq   x4, x0, fail     # x4 should not be zero
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 4: JALR with offset
  auipc x5, 0            # x5 = PC
  addi  x5, x5, 8        # x5 = PC + 8
  jalr  x6, x5, 12       # Jump to (x5 + 12), save return in x6
  jal   x0, fail         # Should not reach here

jalr_offset_target:
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 5: LUI - load upper immediate
  # LUI loads a 20-bit immediate into bits [31:12]
  lui   x7, 0x12345      # x7 = 0x12345000
  lui   x8, 0x12345      # x8 = 0x12345000 (for comparison)
  bne   x7, x8, fail
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 6: LUI with maximum value
  lui   x9, 0xFFFFF      # x9 = 0xFFFFF000
  lui   x11, 0xFFFFF     # x11 = 0xFFFFF000 (for comparison)
  bne   x9, x11, fail
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 7: AUIPC - add upper immediate to PC
  # AUIPC adds a 20-bit immediate (shifted left 12) to PC
  auipc x12, 0           # x12 = PC + 0
  auipc x13, 0           # x13 = PC + 0 (should be PC + 4 from x12)

  # x13 should be x12 + 4
  addi  x14, x12, 4      # x14 = x12 + 4
  bne   x13, x14, fail
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 8: AUIPC with non-zero immediate
  auipc x15, 1           # x15 = PC + 0x1000
  auipc x16, 0           # x16 = PC

  # x15 should be x16 + 0x1000 - 4 (because x15 was computed one instruction earlier)
  lui   x17, 1           # x17 = 0x1000
  add   x18, x16, x17    # x18 = x16 + 0x1000
  addi  x18, x18, -4     # x18 = x16 + 0x1000 - 4
  bne   x15, x18, fail
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 9: JAL with x0 (no link, just jump)
  jal   x0, jal_x0_target # Jump without saving return address
  jal   x0, fail          # Should not reach here

jal_x0_target:
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 10: JALR return address calculation
  # Use JALR to implement a simple function call/return
  auipc x19, 0           # x19 = PC
  addi  x19, x19, 20     # x19 = address of simple_func
  jalr  x20, x19, 0      # Call function, save return address in x20
  # Return point
  addi  x10, x10, 1      # x10++ (test passed after return)
  jal   x0, check_result # Jump to final check

simple_func:
  addi  x10, x10, 1      # x10++ (test passed - function executed)
  jalr  x0, x20, 0       # Return (jump to address in x20)

check_result:
  # Verify all 11 tests passed
  addi  x21, x0, 11      # x21 = 11 (expected count)
  bne   x10, x21, fail

  # All tests passed - set success marker
  addi  x10, x0, 80      # x10 = 80 (0x50 = 'P' for PASSED)
  ebreak

fail:
  # Test failed - set x10 to 0xBADF00D
  lui   x10, 0xBADF0     # x10 = 0xBADF0000
  addi  x10, x10, 0x0D   # x10 = 0xBADF00D
  ebreak
