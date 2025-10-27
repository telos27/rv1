# test_mmio_peripherals.s - Memory-Mapped Peripheral Access Test
# Tests that the SoC can access peripherals through the bus interconnect
# Author: RV1 Project
# Date: 2025-10-27

.section .text
.global _start

_start:
    # Test 1: Write to CLINT MSIP register (0x0200_0000)
    li      t0, 0x02000000      # CLINT base address
    li      t1, 0x00000001      # Set MSIP bit
    sw      t1, 0(t0)           # Write to msip[0]

    # Test 2: Read back MSIP register
    lw      t2, 0(t0)           # Read msip[0]
    li      t3, 0x00000001
    bne     t2, t3, test_fail   # Should be 1

    # Test 3: Clear MSIP register
    li      t1, 0x00000000
    sw      t1, 0(t0)
    lw      t2, 0(t0)
    li      t3, 0x00000000
    bne     t2, t3, test_fail   # Should be 0

    # Test 4: Write to CLINT MTIMECMP (0x0200_4000)
    li      t0, 0x02004000      # MTIMECMP address
    li      t1, 0x12345678      # Lower 32 bits
    sw      t1, 0(t0)
    li      t1, 0x9ABCDEF0      # Upper 32 bits
    sw      t1, 4(t0)

    # Test 5: Read back MTIMECMP
    lw      t2, 0(t0)
    li      t3, 0x12345678
    bne     t2, t3, test_fail
    lw      t2, 4(t0)
    li      t3, 0x9ABCDEF0
    bne     t2, t3, test_fail

    # Test 6: Write to UART THR (Transmit Holding Register) (0x1000_0000)
    li      t0, 0x10000000      # UART base address
    li      t1, 0x00000041      # ASCII 'A'
    sb      t1, 0(t0)           # Write to THR

    # Test 7: Read UART LSR (Line Status Register) (0x1000_0005)
    lb      t2, 5(t0)           # Read LSR
    # LSR should indicate transmitter empty (bit 5 = 1, bit 6 = 1)
    # We don't check exact value since UART might be busy

    # Test 8: Write to UART IER (Interrupt Enable Register) (0x1000_0001)
    li      t1, 0x00000003      # Enable RDA and THRE interrupts
    sb      t1, 1(t0)           # Write to IER
    lb      t2, 1(t0)           # Read back IER
    li      t3, 0x00000003
    bne     t2, t3, test_fail

    # Test 9: Access DMEM (0x8000_0000)
    li      t0, 0x80000000      # DMEM base address
    li      t1, 0xDEADBEEF
    sw      t1, 0(t0)           # Write to DMEM
    lw      t2, 0(t0)           # Read back
    bne     t2, t1, test_fail

    # Test 10: Access DMEM with different sizes
    li      t0, 0x80000100      # Different DMEM address
    li      t1, 0x12
    sb      t1, 0(t0)           # Byte write
    lb      t2, 0(t0)           # Byte read
    bne     t2, t1, test_fail

    li      t1, 0x3456
    sh      t1, 2(t0)           # Halfword write
    lh      t2, 2(t0)           # Halfword read
    bne     t2, t1, test_fail

test_pass:
    # All tests passed
    li      a0, 0               # Exit code 0
    ebreak                      # Signal test completion

test_fail:
    # Test failed
    li      a0, 1               # Exit code 1
    ebreak                      # Signal test failure
