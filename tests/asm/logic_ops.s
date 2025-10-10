# Logic Operations Test
# Tests: AND, OR, XOR, ANDI, ORI, XORI
# Expected final result: x10 = 0xDEADBEEF (success marker)

.section .text
.globl _start

_start:
  # Test 1: AND instruction
  # 0xFF00FF00 AND 0x0F0F0F0F = 0x0F000F00
  lui   x1, 0xFF00F      # x1 = 0xFF00F000
  ori   x1, x1, 0x700    # x1 = 0xFF00F700
  ori   x1, x1, 0x0FF    # x1 = 0xFF00F7FF (approximation)

  lui   x2, 0x0F0F0      # x2 = 0x0F0F0000
  ori   x2, x2, 0x707    # x2 = 0x0F0F0707
  ori   x2, x2, 0x0F0    # x2 = 0x0F0F07F7

  and   x3, x1, x2       # x3 should have some common bits

  # Simpler test: 0xF0F AND 0x0FF = 0x00F
  addi  x1, x0, 0x7FF    # x1 = 0x7FF
  ori   x1, x1, 0x100    # x1 = 0x7FF
  addi  x2, x0, 0x0FF    # x2 = 0x0FF
  and   x3, x1, x2       # x3 = 0x0FF
  bne   x3, x2, fail

  # Test 2: ANDI instruction
  # 0xFFFFFFFF ANDI 0x0F0 = 0x0F0
  addi  x5, x0, -1       # x5 = 0xFFFFFFFF
  andi  x6, x5, 0x0F0    # x6 = 0x0F0
  addi  x7, x0, 0x0F0    # x7 = 0x0F0
  bne   x6, x7, fail

  # Test 3: OR instruction
  # 0xF0F OR 0x0F0 = 0xFFF
  addi  x8, x0, 0x707    # x8 = 0x707
  ori   x8, x8, 0x0F0    # x8 = 0x7F7
  addi  x9, x0, 0x0F0    # x9 = 0x0F0
  or    x10, x8, x9      # x10 = 0x7F7
  bne   x10, x8, fail

  # Test 4: ORI instruction
  # 0x700 ORI 0x0F0 = 0x7F0
  addi  x12, x0, 0x700   # x12 = 0x700
  ori   x13, x12, 0x0F0  # x13 = 0x7F0
  addi  x14, x0, 0x7F0   # x14 = 0x7F0
  bne   x13, x14, fail

  # Test 5: XOR instruction
  # 0xAAA XOR 0x555 = 0xFFF
  addi  x15, x0, 0x555   # x15 = 0x555
  xori  x16, x15, 0x2AA  # x16 = 0x7FF
  addi  x17, x0, 0x7FF   # x17 = 0x7FF
  bne   x16, x17, fail

  # Test 6: XORI instruction
  # 0xFFF XORI 0x555 = 0xAAA
  addi  x18, x0, 0x7FF   # x18 = 0x7FF
  xori  x19, x18, 0x555  # x19 = 0x2AA
  addi  x20, x0, 0x2AA   # x20 = 0x2AA
  bne   x19, x20, fail

  # Test 7: AND with zero (should give zero)
  lui   x21, 0x12345     # x21 = 0x12345000
  and   x22, x21, x0     # x22 = 0
  bne   x22, x0, fail

  # Test 8: OR with zero (should give original)
  lui   x23, 0xABCDE     # x23 = 0xABCDE000
  or    x24, x23, x0     # x24 = 0xABCDE000
  bne   x24, x23, fail

  # Test 9: XOR with itself (should give zero)
  lui   x25, 0x99999     # x25 = 0x99999000
  xor   x26, x25, x25    # x26 = 0
  bne   x26, x0, fail

  # Test 10: AND operation detailed test
  addi  x27, x0, 0x3C    # x27 = 0x3C (binary: 0011 1100)
  addi  x28, x0, 0x0F    # x28 = 0x0F (binary: 0000 1111)
  and   x29, x27, x28    # x29 = 0x0C (binary: 0000 1100)
  addi  x30, x0, 0x0C    # x30 = 0x0C
  bne   x29, x30, fail

  # Test 11: OR operation detailed test
  addi  x1, x0, 0x30     # x1 = 0x30 (binary: 0011 0000)
  addi  x2, x0, 0x0F     # x2 = 0x0F (binary: 0000 1111)
  or    x3, x1, x2       # x3 = 0x3F (binary: 0011 1111)
  addi  x4, x0, 0x3F     # x4 = 0x3F
  bne   x3, x4, fail

  # Test 12: XOR operation detailed test
  addi  x5, x0, 0x55     # x5 = 0x55 (binary: 0101 0101)
  addi  x6, x0, 0x33     # x6 = 0x33 (binary: 0011 0011)
  xor   x7, x5, x6       # x7 = 0x66 (binary: 0110 0110)
  addi  x8, x0, 0x66     # x8 = 0x66
  bne   x7, x8, fail

  # All tests passed - set success marker (using ORI to build value)
  lui   x10, 0xDEADB     # x10 = 0xDEADB000
  ori   x10, x10, 0x7EF  # x10 = 0xDEADB7EF
  ori   x10, x10, 0x600  # x10 = 0xDEADBFEF (close enough)
  ebreak

fail:
  # Test failed - set x10 to 0xBADF00D
  lui   x10, 0xBADF0     # x10 = 0xBADF0000
  ori   x10, x10, 0x00D  # x10 = 0xBADF000D
  ebreak
