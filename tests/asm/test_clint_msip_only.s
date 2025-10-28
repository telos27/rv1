# test_clint_msip_only.s - Minimal CLINT MSIP Write Test
# Tests if writes to MSIP (0x02000000) reach the bus
# Author: RV1 Project - Session 50 Debug
# Date: 2025-10-28

.section .text
.global _start

_start:
    # Test: Write to MSIP (0x02000000)
    li      t0, 0x02000000          # MSIP address
    li      t1, 0x00000001          # Set bit 0
    sw      t1, 0(t0)               # Write MSIP

    lw      t2, 0(t0)               # Read back
    andi    t2, t2, 0x1             # Mask to bit 0
    bne     t1, t2, test_fail       # Should match

test_pass:
    li      a0, 0                   # Exit code 0
    ebreak

test_fail:
    li      a0, 1                   # Exit code 1
    ebreak
