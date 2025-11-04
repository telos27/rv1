# RV64I Load/Store Test
# Tests: LD, LWU, SD

.section .text
.globl _start

.option norvc  # Disable compressed instructions

_start:
    # Initialize test data in memory
    li      t0, 0x2000              # Data memory address (will be masked to 0x80002000)

    # Test 1: SD (Store Doubleword) and LD (Load Doubleword)
    li      t1, 0x12345678
    slli    t1, t1, 32
    li      t2, 0x9ABCDEF0
    or      t1, t1, t2              # t1 = 0x123456789ABCDEF0
    sd      t1, 0(t0)               # Store doubleword
    ld      t2, 0(t0)               # Load doubleword
    bne     t1, t2, test_fail       # Check if loaded value matches

    # Test 2: LWU (Load Word Unsigned) - upper 32 bits should be zero
    li      t1, 0xFEDCBA98
    sw      t1, 8(t0)               # Store word
    lwu     t2, 8(t0)               # Load word unsigned (lower 32 bits, zero-extend)
    srli    t3, t2, 32              # Check upper 32 bits
    bnez    t3, test_fail           # Upper bits should be zero
    li      t3, 0xFEDCBA98
    bne     t2, t3, test_fail       # Check value

    # Test 3: LW (Load Word) - should sign-extend
    li      t1, 0x8ABCDEF0          # Negative 32-bit value (bit 31 = 1)
    sw      t1, 16(t0)              # Store word
    lw      t2, 16(t0)              # Load word (sign-extend)
    srli    t3, t2, 32              # Check upper 32 bits
    li      t4, 0xFFFFFFFF
    srli    t4, t4, 32              # t4 = 0xFFFFFFFF (upper 32 bits)
    bne     t3, t4, test_fail       # Upper bits should be all 1s

    # Test 4: Multiple doubleword loads/stores
    li      t1, 0x11111111
    slli    t1, t1, 32
    li      t2, 0x11111111
    or      t1, t1, t2
    sd      t1, 24(t0)

    ld      t4, 24(t0)
    bne     t1, t4, test_fail

test_pass:
    li      a0, 1                   # Success
    nop
    nop
    j       done

test_fail:
    li      a0, 0                   # Failure
    nop
    nop

done:
    ebreak
