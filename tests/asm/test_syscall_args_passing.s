# ==============================================================================
# Test: Syscall Argument Passing (U-mode to S-mode)
# ==============================================================================
#
# This test verifies that syscall arguments are correctly passed from U-mode
# to S-mode and that return values are passed back correctly.
#
# Test Sequence:
# 1. Enter U-mode
# 2. Prepare arguments in a0-a7 (standard RISC-V calling convention)
# 3. Execute ECALL to enter S-mode
# 4. S-mode handler reads arguments from a0-a7
# 5. S-mode performs computation and writes result to a0
# 6. S-mode executes SRET to return to U-mode
# 7. U-mode verifies result in a0
# 8. Test multiple syscalls with different arguments
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
    # Setup M-mode trap handler (for unexpected traps)
    ###########################################################################

    SET_MTVEC_DIRECT m_trap_handler

    TEST_STAGE 2

    ###########################################################################
    # Setup S-mode trap handler (for ECALL from U-mode)
    ###########################################################################

    SET_STVEC_DIRECT s_trap_handler

    # Delegate U-mode ECALL to S-mode
    DELEGATE_EXCEPTION CAUSE_ECALL_U

    TEST_STAGE 3

    ###########################################################################
    # Enter U-mode
    ###########################################################################

    ENTER_UMODE_M u_mode_entry

u_mode_entry:
    TEST_STAGE 4

    ###########################################################################
    # Test 1: Simple syscall with 2 arguments (add)
    ###########################################################################

    li      a7, 1                   # Syscall number 1 = add
    li      a0, 10                  # arg0 = 10
    li      a1, 20                  # arg1 = 20
    ecall                           # Call S-mode handler

    # Handler should return a0 = 10 + 20 = 30
    li      t0, 30
    bne     a0, t0, test_fail

    TEST_STAGE 5

    ###########################################################################
    # Test 2: Syscall with 4 arguments (sum)
    ###########################################################################

    li      a7, 2                   # Syscall number 2 = sum of 4 values
    li      a0, 5                   # arg0 = 5
    li      a1, 10                  # arg1 = 10
    li      a2, 15                  # arg2 = 15
    li      a3, 20                  # arg3 = 20
    ecall                           # Call S-mode handler

    # Handler should return a0 = 5 + 10 + 15 + 20 = 50
    li      t0, 50
    bne     a0, t0, test_fail

    TEST_STAGE 6

    ###########################################################################
    # Test 3: Syscall with all 8 argument registers
    ###########################################################################

    li      a7, 3                   # Syscall number 3 = XOR all args
    li      a0, 0xAAAA
    li      a1, 0x5555
    li      a2, 0xF0F0
    li      a3, 0x0F0F
    li      a4, 0xFF00
    li      a5, 0x00FF
    li      a6, 0xDEAD
    ecall                           # a7 is syscall number, not XORed

    # Handler should return a0 = 0xAAAA ^ 0x5555 ^ 0xF0F0 ^ 0x0F0F ^ 0xFF00 ^ 0x00FF ^ 0xDEAD
    # = 0xFFFF ^ 0x0F0F ^ 0x0000 ^ 0xFF00 ^ 0x00FF ^ 0xDEAD = 0x2152
    li      t0, 0x2152
    bne     a0, t0, test_fail

    TEST_STAGE 7

    ###########################################################################
    # Test passed!
    ###########################################################################

    j       test_pass

###############################################################################
# S-mode trap handler - Handles syscalls from U-mode
###############################################################################

s_trap_handler:
    # Check if this is ECALL from U-mode
    csrr    t0, scause
    li      t1, CAUSE_ECALL_U
    bne     t0, t1, trap_fail

    # Save a7 to s2 for debugging
    mv      s2, a7

    # Dispatch based on syscall number in a7
    li      t0, 1
    beq     a7, t0, syscall_add

    li      t0, 2
    beq     a7, t0, syscall_sum4

    li      t0, 3
    beq     a7, t0, syscall_xor_all

    # Unknown syscall - save a7 to s2 for debug
    j       trap_fail

syscall_add:
    # Syscall 1: Add two numbers (a0 + a1)
    add     a0, a0, a1              # Result in a0
    j       syscall_return

syscall_sum4:
    # Syscall 2: Sum four numbers (a0 + a1 + a2 + a3)
    add     a0, a0, a1
    add     a0, a0, a2
    add     a0, a0, a3              # Result in a0
    j       syscall_return

syscall_xor_all:
    # Syscall 3: XOR all argument registers (except a7)
    xor     a0, a0, a1
    xor     a0, a0, a2
    xor     a0, a0, a3
    xor     a0, a0, a4
    xor     a0, a0, a5
    xor     a0, a0, a6              # Result in a0
    j       syscall_return

syscall_return:
    # Advance SEPC past the ECALL instruction (4 bytes)
    csrr    t0, sepc
    addi    t0, t0, 4
    csrw    sepc, t0

    # Return to U-mode
    sret

trap_fail:
    TEST_STAGE 0xF0
    j       test_fail

###############################################################################
# M-mode trap handler (for unexpected traps)
###############################################################################

m_trap_handler:
    # Save mcause for debugging
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
