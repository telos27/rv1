# ==============================================================================
# Test: Multiple Sequential Syscalls
# ==============================================================================
#
# This test verifies that multiple syscalls can be executed in sequence
# and that each syscall operates independently without interference.
#
# Test Sequence:
# 1. Enter U-mode
# 2. Execute 10 different syscalls in sequence
# 3. Verify each syscall returns correct result
# 4. Verify state is preserved correctly between syscalls
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE
    TEST_STAGE 1

    ###########################################################################
    # Setup trap handlers
    ###########################################################################

    SET_MTVEC_DIRECT m_trap_handler
    SET_STVEC_DIRECT s_trap_handler

    # Delegate U-mode ECALL to S-mode
    DELEGATE_EXCEPTION CAUSE_ECALL_U

    TEST_STAGE 2

    ###########################################################################
    # Enter U-mode
    ###########################################################################

    ENTER_UMODE_M u_mode_entry

u_mode_entry:
    TEST_STAGE 3

    ###########################################################################
    # Test: 10 sequential syscalls
    ###########################################################################

    # Syscall 1: Add (5 + 10 = 15)
    li      a7, 1
    li      a0, 5
    li      a1, 10
    ecall
    li      t0, 15
    bne     a0, t0, test_fail

    TEST_STAGE 4

    # Syscall 2: Multiply (3 * 7 = 21)
    li      a7, 2
    li      a0, 3
    li      a1, 7
    ecall
    li      t0, 21
    bne     a0, t0, test_fail

    TEST_STAGE 5

    # Syscall 3: Subtract (100 - 25 = 75)
    li      a7, 3
    li      a0, 100
    li      a1, 25
    ecall
    li      t0, 75
    bne     a0, t0, test_fail

    TEST_STAGE 6

    # Syscall 4: AND (0xFF & 0x0F = 0x0F)
    li      a7, 4
    li      a0, 0xFF
    li      a1, 0x0F
    ecall
    li      t0, 0x0F
    bne     a0, t0, test_fail

    TEST_STAGE 7

    # Syscall 5: OR (0xF0 | 0x0F = 0xFF)
    li      a7, 5
    li      a0, 0xF0
    li      a1, 0x0F
    ecall
    li      t0, 0xFF
    bne     a0, t0, test_fail

    TEST_STAGE 8

    # Syscall 6: XOR (0xAA ^ 0x55 = 0xFF)
    li      a7, 6
    li      a0, 0xAA
    li      a1, 0x55
    ecall
    li      t0, 0xFF
    bne     a0, t0, test_fail

    TEST_STAGE 9

    # Syscall 7: Shift left (5 << 2 = 20)
    li      a7, 7
    li      a0, 5
    li      a1, 2
    ecall
    li      t0, 20
    bne     a0, t0, test_fail

    TEST_STAGE 10

    # Syscall 8: Shift right logical (32 >> 2 = 8)
    li      a7, 8
    li      a0, 32
    li      a1, 2
    ecall
    li      t0, 8
    bne     a0, t0, test_fail

    TEST_STAGE 11

    # Syscall 9: Max (compare 42 and 17, return 42)
    li      a7, 9
    li      a0, 42
    li      a1, 17
    ecall
    li      t0, 42
    bne     a0, t0, test_fail

    TEST_STAGE 12

    # Syscall 10: Min (compare 99 and 123, return 99)
    li      a7, 10
    li      a0, 99
    li      a1, 123
    ecall
    li      t0, 99
    bne     a0, t0, test_fail

    # All syscalls succeeded\!
    j       test_pass

###############################################################################
# S-mode trap handler - Handles syscalls
###############################################################################

s_trap_handler:
    # Check if this is ECALL from U-mode
    csrr    t0, scause
    li      t1, CAUSE_ECALL_U
    bne     t0, t1, trap_fail

    # Dispatch based on syscall number in a7
    li      t0, 1
    beq     a7, t0, syscall_add
    li      t0, 2
    beq     a7, t0, syscall_mul
    li      t0, 3
    beq     a7, t0, syscall_sub
    li      t0, 4
    beq     a7, t0, syscall_and
    li      t0, 5
    beq     a7, t0, syscall_or
    li      t0, 6
    beq     a7, t0, syscall_xor
    li      t0, 7
    beq     a7, t0, syscall_sll
    li      t0, 8
    beq     a7, t0, syscall_srl
    li      t0, 9
    beq     a7, t0, syscall_max
    li      t0, 10
    beq     a7, t0, syscall_min

    # Unknown syscall
    j       trap_fail

syscall_add:
    add     a0, a0, a1
    j       syscall_return

syscall_mul:
    mul     a0, a0, a1
    j       syscall_return

syscall_sub:
    sub     a0, a0, a1
    j       syscall_return

syscall_and:
    and     a0, a0, a1
    j       syscall_return

syscall_or:
    or      a0, a0, a1
    j       syscall_return

syscall_xor:
    xor     a0, a0, a1
    j       syscall_return

syscall_sll:
    sll     a0, a0, a1
    j       syscall_return

syscall_srl:
    srl     a0, a0, a1
    j       syscall_return

syscall_max:
    # Return max(a0, a1)
    bge     a0, a1, syscall_return  # If a0 >= a1, return a0
    mv      a0, a1                  # Else return a1
    j       syscall_return

syscall_min:
    # Return min(a0, a1)
    ble     a0, a1, syscall_return  # If a0 <= a1, return a0
    mv      a0, a1                  # Else return a1
    j       syscall_return

syscall_return:
    # Advance SEPC past ECALL
    csrr    t0, sepc
    addi    t0, t0, 4
    csrw    sepc, t0
    sret

trap_fail:
    TEST_STAGE 0xF0
    j       test_fail

###############################################################################
# M-mode trap handler
###############################################################################

m_trap_handler:
    csrr    s0, mcause
    csrr    s1, mtval
    TEST_STAGE 0xFF
    j       test_fail

###############################################################################
# Test result handlers
###############################################################################

test_pass:
    li gp, 1
    j end_test

test_fail:
    li gp, 0
    j end_test

end_test:
    li t0, 0x80002100
    sw gp, 0(t0)
1:  j 1b
