# Branch Instructions Test
# Tests: BEQ, BNE, BLT, BGE, BLTU, BGEU
# Expected final result: x10 = 0xB4A4C4ED (success marker)

.section .text
.globl _start

_start:
  # Initialize counter for passed tests
  addi  x10, x0, 0       # x10 = 0 (test pass counter)

  # Test 1: BEQ - branch if equal (should branch)
  addi  x1, x0, 42       # x1 = 42
  addi  x2, x0, 42       # x2 = 42
  beq   x1, x2, beq_pass # Should branch (equal)
  jal   x0, fail         # Should not reach here

beq_pass:
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 2: BEQ - should NOT branch when unequal
  addi  x3, x0, 10       # x3 = 10
  addi  x4, x0, 20       # x4 = 20
  beq   x3, x4, fail     # Should NOT branch (unequal)
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 3: BNE - branch if not equal (should branch)
  addi  x5, x0, 5        # x5 = 5
  addi  x6, x0, 10       # x6 = 10
  bne   x5, x6, bne_pass # Should branch (not equal)
  jal   x0, fail         # Should not reach here

bne_pass:
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 4: BNE - should NOT branch when equal
  addi  x7, x0, 99       # x7 = 99
  addi  x8, x0, 99       # x8 = 99
  bne   x7, x8, fail     # Should NOT branch (equal)
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 5: BLT - branch if less than (signed, should branch)
  addi  x9, x0, -10      # x9 = -10 (negative)
  addi  x11, x0, 5       # x11 = 5 (positive)
  blt   x9, x11, blt_pass # Should branch (-10 < 5)
  jal   x0, fail         # Should not reach here

blt_pass:
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 6: BLT - should NOT branch (greater than)
  addi  x12, x0, 100     # x12 = 100
  addi  x13, x0, 50      # x13 = 50
  blt   x12, x13, fail   # Should NOT branch (100 >= 50)
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 7: BLT - should NOT branch (equal)
  addi  x14, x0, 77      # x14 = 77
  addi  x15, x0, 77      # x15 = 77
  blt   x14, x15, fail   # Should NOT branch (equal)
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 8: BGE - branch if greater or equal (should branch - greater)
  addi  x16, x0, 100     # x16 = 100
  addi  x17, x0, 50      # x17 = 50
  bge   x16, x17, bge_pass1 # Should branch (100 >= 50)
  jal   x0, fail         # Should not reach here

bge_pass1:
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 9: BGE - branch if greater or equal (should branch - equal)
  addi  x18, x0, 33      # x18 = 33
  addi  x19, x0, 33      # x19 = 33
  bge   x18, x19, bge_pass2 # Should branch (33 >= 33)
  jal   x0, fail         # Should not reach here

bge_pass2:
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 10: BGE - should NOT branch (less than)
  addi  x20, x0, 10      # x20 = 10
  addi  x21, x0, 20      # x21 = 20
  bge   x20, x21, fail   # Should NOT branch (10 < 20)
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 11: BGE with negative numbers (signed)
  addi  x22, x0, -5      # x22 = -5
  addi  x23, x0, -10     # x23 = -10
  bge   x22, x23, bge_pass3 # Should branch (-5 >= -10)
  jal   x0, fail         # Should not reach here

bge_pass3:
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 12: BLTU - branch if less than unsigned
  # 0xFFFFFFFF (unsigned large) vs 0x00000001
  addi  x24, x0, 1       # x24 = 1
  addi  x25, x0, -1      # x25 = 0xFFFFFFFF
  bltu  x24, x25, bltu_pass # Should branch (1 < 0xFFFFFFFF unsigned)
  jal   x0, fail         # Should not reach here

bltu_pass:
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 13: BLTU - negative number treated as large unsigned
  addi  x26, x0, -1      # x26 = 0xFFFFFFFF
  addi  x27, x0, 1       # x27 = 1
  bltu  x26, x27, fail   # Should NOT branch (0xFFFFFFFF > 1 unsigned)
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 14: BGEU - branch if greater or equal unsigned (should branch)
  addi  x28, x0, -1      # x28 = 0xFFFFFFFF
  addi  x29, x0, 100     # x29 = 100
  bgeu  x28, x29, bgeu_pass # Should branch (0xFFFFFFFF >= 100 unsigned)
  jal   x0, fail         # Should not reach here

bgeu_pass:
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 15: BGEU - should NOT branch
  addi  x30, x0, 50      # x30 = 50
  addi  x31, x0, 100     # x31 = 100
  bgeu  x30, x31, fail   # Should NOT branch (50 < 100)
  addi  x10, x10, 1      # x10++ (test passed)

  # Test 16: BGEU - equal case (should branch)
  addi  x1, x0, 123      # x1 = 123
  addi  x2, x0, 123      # x2 = 123
  bgeu  x1, x2, bgeu_pass2 # Should branch (equal)
  jal   x0, fail         # Should not reach here

bgeu_pass2:
  addi  x10, x10, 1      # x10++ (test passed)

  # Verify all 16 tests passed
  addi  x3, x0, 16       # x3 = 16 (expected count)
  bne   x10, x3, fail

  # All tests passed - set success marker
  lui   x10, 0xB4A4C     # x10 = 0xB4A4C000
  addi  x10, x10, 0x4ED  # x10 = 0xB4A4C4ED (BRANCHED in leet)
  ebreak

fail:
  # Test failed - set x10 to 0xBADBEEF
  lui   x10, 0xBADBE     # x10 = 0xBADBE000
  addi  x10, x10, 0xEF   # x10 = 0xBADBEEF
  ebreak
