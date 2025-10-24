# ==============================================================================
# RISC-V Privilege Mode Test Macro Library
# ==============================================================================
#
# This file provides a comprehensive set of macros for testing privilege mode
# functionality in RISC-V processors. It simplifies writing tests for:
# - Privilege mode transitions (M ↔ S ↔ U)
# - Trap handling and delegation
# - CSR access and verification
# - Exception and interrupt testing
#
# Usage: .include "tests/asm/include/priv_test_macros.s"
#
# ==============================================================================

# ==============================================================================
# PRIVILEGE MODE CONSTANTS
# ==============================================================================

# Privilege mode encodings (for MPP, SPP, current_priv)
.equ PRIV_U,        0x0     # User mode
.equ PRIV_S,        0x1     # Supervisor mode
.equ PRIV_M,        0x3     # Machine mode

# mstatus bit positions
.equ MSTATUS_SIE,   (1 << 1)    # Supervisor Interrupt Enable
.equ MSTATUS_MIE,   (1 << 3)    # Machine Interrupt Enable
.equ MSTATUS_SPIE,  (1 << 5)    # Supervisor Previous Interrupt Enable
.equ MSTATUS_MPIE,  (1 << 7)    # Machine Previous Interrupt Enable
.equ MSTATUS_SPP,   (1 << 8)    # Supervisor Previous Privilege
.equ MSTATUS_MPP_MASK,   0x1800 # Machine Previous Privilege mask (bits 12:11)
.equ MSTATUS_MPP_SHIFT,  11     # MPP field shift
.equ MSTATUS_SUM,   (1 << 18)   # Supervisor User Memory access
.equ MSTATUS_MXR,   (1 << 19)   # Make eXecutable Readable

# Exception/Interrupt cause codes
.equ CAUSE_MISALIGNED_FETCH,    0
.equ CAUSE_FETCH_ACCESS,        1
.equ CAUSE_ILLEGAL_INSTR,       2
.equ CAUSE_BREAKPOINT,          3
.equ CAUSE_MISALIGNED_LOAD,     4
.equ CAUSE_LOAD_ACCESS,         5
.equ CAUSE_MISALIGNED_STORE,    6
.equ CAUSE_STORE_ACCESS,        7
.equ CAUSE_ECALL_U,             8
.equ CAUSE_ECALL_S,             9
.equ CAUSE_ECALL_M,             11
.equ CAUSE_FETCH_PAGE_FAULT,    12
.equ CAUSE_LOAD_PAGE_FAULT,     13
.equ CAUSE_STORE_PAGE_FAULT,    15

# Interrupt cause codes (with interrupt bit set, bit 31 for RV32, bit 63 for RV64)
.equ CAUSE_INT_SSI,     0x8000000001  # Supervisor software interrupt
.equ CAUSE_INT_MSI,     0x8000000003  # Machine software interrupt
.equ CAUSE_INT_STI,     0x8000000005  # Supervisor timer interrupt
.equ CAUSE_INT_MTI,     0x8000000007  # Machine timer interrupt
.equ CAUSE_INT_SEI,     0x8000000009  # Supervisor external interrupt
.equ CAUSE_INT_MEI,     0x800000000B  # Machine external interrupt

# Test result markers
.equ TEST_PASS_MARKER,  0xDEADBEEF
.equ TEST_FAIL_MARKER,  0xDEADDEAD

# ==============================================================================
# TRAP VECTOR SETUP MACROS
# ==============================================================================

# Set M-mode trap vector (Direct mode)
# Usage: SET_MTVEC_DIRECT label
.macro SET_MTVEC_DIRECT handler
    la      t0, \handler
    csrw    mtvec, t0
.endm

# Set S-mode trap vector (Direct mode)
# Usage: SET_STVEC_DIRECT label
.macro SET_STVEC_DIRECT handler
    la      t0, \handler
    csrw    stvec, t0
.endm

# Set M-mode trap vector (Vectored mode)
# Usage: SET_MTVEC_VECTORED label
.macro SET_MTVEC_VECTORED handler
    la      t0, \handler
    ori     t0, t0, 1       # Set mode = 1 (Vectored)
    csrw    mtvec, t0
.endm

# Set S-mode trap vector (Vectored mode)
# Usage: SET_STVEC_VECTORED label
.macro SET_STVEC_VECTORED handler
    la      t0, \handler
    ori     t0, t0, 1       # Set mode = 1 (Vectored)
    csrw    stvec, t0
.endm

# ==============================================================================
# PRIVILEGE MODE TRANSITION MACROS
# ==============================================================================

# Enter U-mode from M-mode via MRET
# Usage: ENTER_UMODE_M target_label
.macro ENTER_UMODE_M target
    la      t0, \target
    csrw    mepc, t0

    # Set MPP = 00 (U-mode)
    li      t1, ~MSTATUS_MPP_MASK
    csrr    t2, mstatus
    and     t2, t2, t1          # Clear MPP bits
    csrw    mstatus, t2         # MPP = 00 (U-mode)

    mret                        # Return to U-mode
.endm

# Enter S-mode from M-mode via MRET
# Usage: ENTER_SMODE_M target_label
.macro ENTER_SMODE_M target
    la      t0, \target
    csrw    mepc, t0

    # Set MPP = 01 (S-mode)
    li      t1, ~MSTATUS_MPP_MASK
    csrr    t2, mstatus
    and     t2, t2, t1          # Clear MPP bits
    li      t1, (PRIV_S << MSTATUS_MPP_SHIFT)
    or      t2, t2, t1          # Set MPP = 01 (S-mode)
    csrw    mstatus, t2

    mret                        # Return to S-mode
.endm

# Enter U-mode from S-mode via SRET
# Usage: ENTER_UMODE_S target_label
.macro ENTER_UMODE_S target
    la      t0, \target
    csrw    sepc, t0

    # Set SPP = 0 (U-mode)
    li      t1, ~MSTATUS_SPP
    csrr    t2, mstatus
    and     t2, t2, t1          # Clear SPP bit
    csrw    mstatus, t2         # SPP = 0 (U-mode)

    sret                        # Return to U-mode
.endm

# Return to S-mode via SRET (SPP already set)
# Usage: RETURN_SMODE target_label
.macro RETURN_SMODE target
    la      t0, \target
    csrw    sepc, t0
    sret
.endm

# Return to M-mode via MRET (MPP already set)
# Usage: RETURN_MMODE target_label
.macro RETURN_MMODE target
    la      t0, \target
    csrw    mepc, t0
    mret
.endm

# ==============================================================================
# MSTATUS MANIPULATION MACROS
# ==============================================================================

# Set MPP field to specified privilege level
# Usage: SET_MPP PRIV_S (or PRIV_U, PRIV_M)
.macro SET_MPP priv_level
    li      t0, ~MSTATUS_MPP_MASK
    csrr    t1, mstatus
    and     t1, t1, t0              # Clear MPP
    li      t0, (\priv_level << MSTATUS_MPP_SHIFT)
    or      t1, t1, t0              # Set new MPP
    csrw    mstatus, t1
.endm

# Set SPP bit to specified privilege level
# Usage: SET_SPP PRIV_U (or PRIV_S)
.macro SET_SPP priv_level
.if \priv_level == PRIV_U
    li      t0, ~MSTATUS_SPP
    csrr    t1, mstatus
    and     t1, t1, t0              # Clear SPP (U-mode)
    csrw    mstatus, t1
.else
    li      t0, MSTATUS_SPP
    csrr    t1, mstatus
    or      t1, t1, t0              # Set SPP (S-mode)
    csrw    mstatus, t1
.endif
.endm

# Enable machine interrupts (set MIE)
# Usage: ENABLE_MIE
.macro ENABLE_MIE
    li      t0, MSTATUS_MIE
    csrrs   zero, mstatus, t0
.endm

# Disable machine interrupts (clear MIE)
# Usage: DISABLE_MIE
.macro DISABLE_MIE
    li      t0, MSTATUS_MIE
    csrrc   zero, mstatus, t0
.endm

# Enable supervisor interrupts (set SIE)
# Usage: ENABLE_SIE
.macro ENABLE_SIE
    li      t0, MSTATUS_SIE
    csrrs   zero, mstatus, t0
.endm

# Disable supervisor interrupts (clear SIE)
# Usage: DISABLE_SIE
.macro DISABLE_SIE
    li      t0, MSTATUS_SIE
    csrrc   zero, mstatus, t0
.endm

# Enable machine previous interrupt enable (set MPIE)
# Usage: ENABLE_MPIE
.macro ENABLE_MPIE
    li      t0, MSTATUS_MPIE
    csrrs   zero, mstatus, t0
.endm

# Disable machine previous interrupt enable (clear MPIE)
# Usage: DISABLE_MPIE
.macro DISABLE_MPIE
    li      t0, MSTATUS_MPIE
    csrrc   zero, mstatus, t0
.endm

# Enable supervisor previous interrupt enable (set SPIE)
# Usage: ENABLE_SPIE
.macro ENABLE_SPIE
    li      t0, MSTATUS_SPIE
    csrrs   zero, mstatus, t0
.endm

# Disable supervisor previous interrupt enable (clear SPIE)
# Usage: DISABLE_SPIE
.macro DISABLE_SPIE
    li      t0, MSTATUS_SPIE
    csrrc   zero, mstatus, t0
.endm

# Set SUM bit (Supervisor User Memory access)
# Usage: ENABLE_SUM
.macro ENABLE_SUM
    li      t0, MSTATUS_SUM
    csrrs   zero, mstatus, t0
.endm

# Clear SUM bit
# Usage: DISABLE_SUM
.macro DISABLE_SUM
    li      t0, MSTATUS_SUM
    csrrc   zero, mstatus, t0
.endm

# ==============================================================================
# TRAP DELEGATION MACROS
# ==============================================================================

# Delegate specific exception to S-mode
# Usage: DELEGATE_EXCEPTION CAUSE_ILLEGAL_INSTR
.macro DELEGATE_EXCEPTION cause_code
    li      t0, (1 << \cause_code)
    csrrs   zero, medeleg, t0
.endm

# Remove exception delegation
# Usage: UNDELEGATE_EXCEPTION CAUSE_ILLEGAL_INSTR
.macro UNDELEGATE_EXCEPTION cause_code
    li      t0, (1 << \cause_code)
    csrrc   zero, medeleg, t0
.endm

# Delegate all synchronous exceptions to S-mode
# Usage: DELEGATE_ALL_EXCEPTIONS
.macro DELEGATE_ALL_EXCEPTIONS
    li      t0, 0xFFFF          # All exception causes
    csrw    medeleg, t0
.endm

# Clear all exception delegations
# Usage: CLEAR_EXCEPTION_DELEGATION
.macro CLEAR_EXCEPTION_DELEGATION
    csrw    medeleg, zero
.endm

# Delegate specific interrupt to S-mode
# Usage: DELEGATE_INTERRUPT 1 (for supervisor software interrupt bit)
.macro DELEGATE_INTERRUPT int_bit
    li      t0, (1 << \int_bit)
    csrrs   zero, mideleg, t0
.endm

# Remove interrupt delegation
# Usage: UNDELEGATE_INTERRUPT 1
.macro UNDELEGATE_INTERRUPT int_bit
    li      t0, (1 << \int_bit)
    csrrc   zero, mideleg, t0
.endm

# ==============================================================================
# CSR VERIFICATION MACROS
# ==============================================================================

# Read CSR and compare with expected value, jump to fail_label if mismatch
# Usage: EXPECT_CSR mstatus, 0x1800, test_fail
.macro EXPECT_CSR csr_name, expected_value, fail_label
    csrr    t0, \csr_name
    li      t1, \expected_value
    bne     t0, t1, \fail_label
.endm

# Read CSR and verify specific bits are set
# Usage: EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail
.macro EXPECT_BITS_SET csr_name, bit_mask, fail_label
    csrr    t0, \csr_name
    li      t1, \bit_mask
    and     t2, t0, t1
    bne     t2, t1, \fail_label
.endm

# Read CSR and verify specific bits are clear
# Usage: EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail
.macro EXPECT_BITS_CLEAR csr_name, bit_mask, fail_label
    csrr    t0, \csr_name
    li      t1, \bit_mask
    and     t2, t0, t1
    bnez    t2, \fail_label
.endm

# Extract and verify MPP field
# Usage: EXPECT_MPP PRIV_S, test_fail
.macro EXPECT_MPP expected_priv, fail_label
    csrr    t0, mstatus
    li      t1, MSTATUS_MPP_MASK
    and     t0, t0, t1
    srli    t0, t0, MSTATUS_MPP_SHIFT
    li      t1, \expected_priv
    bne     t0, t1, \fail_label
.endm

# Verify SPP bit
# Usage: EXPECT_SPP PRIV_U, test_fail
.macro EXPECT_SPP expected_priv, fail_label
    csrr    t0, mstatus
    li      t1, MSTATUS_SPP
    and     t0, t0, t1
.if \expected_priv == PRIV_U
    bnez    t0, \fail_label         # SPP should be 0 for U-mode
.else
    beqz    t0, \fail_label         # SPP should be 1 for S-mode
.endif
.endm

# ==============================================================================
# TRAP EXPECTATION MACROS
# ==============================================================================

# Setup to expect a trap with specific cause
# Saves expected cause to a global variable for trap handler to check
# Usage: EXPECT_TRAP_CAUSE CAUSE_ILLEGAL_INSTR
.macro EXPECT_TRAP_CAUSE cause_code
    li      t0, \cause_code
    la      t1, expected_cause
    sw      t0, 0(t1)
.endm

# Macro to verify trap cause matches expected (use in trap handler)
# Usage: VERIFY_TRAP_CAUSE mcause, test_fail
.macro VERIFY_TRAP_CAUSE cause_csr, fail_label
    csrr    t0, \cause_csr
    la      t1, expected_cause
    lw      t2, 0(t1)
    bne     t0, t2, \fail_label
.endm

# ==============================================================================
# TEST RESULT MACROS
# ==============================================================================

# Mark test as passed and exit
# Usage: TEST_PASS
.macro TEST_PASS
    li      t0, TEST_PASS_MARKER
    mv      x28, t0             # Save marker to x28 for testbench
    ebreak                      # Signal test completion
.endm

# Mark test as failed and exit
# Usage: TEST_FAIL
.macro TEST_FAIL
    li      t0, TEST_FAIL_MARKER
    mv      x28, t0             # Save marker to x28 for testbench
    ebreak                      # Signal test completion
.endm

# Mark test as failed with error code
# Usage: TEST_FAIL_CODE 5 (error code in a0)
.macro TEST_FAIL_CODE error_code
    li      a0, \error_code
    li      t0, TEST_FAIL_MARKER
    mv      x28, t0
    ebreak
.endm

# Mark test stage (for debugging multi-stage tests)
# Usage: TEST_STAGE 3 (saves stage number to x29)
.macro TEST_STAGE stage_num
    li      x29, \stage_num
.endm

# ==============================================================================
# INTERRUPT SETUP MACROS
# ==============================================================================

# Enable specific interrupt in MIE
# Usage: ENABLE_M_INTERRUPT 7 (bit position, e.g., 7 for MTI)
.macro ENABLE_M_INTERRUPT bit_pos
    li      t0, (1 << \bit_pos)
    csrrs   zero, mie, t0
.endm

# Disable specific interrupt in MIE
# Usage: DISABLE_M_INTERRUPT 7
.macro DISABLE_M_INTERRUPT bit_pos
    li      t0, (1 << \bit_pos)
    csrrc   zero, mie, t0
.endm

# Enable specific interrupt in SIE
# Usage: ENABLE_S_INTERRUPT 5 (bit position, e.g., 5 for STI)
.macro ENABLE_S_INTERRUPT bit_pos
    li      t0, (1 << \bit_pos)
    csrrs   zero, sie, t0
.endm

# Disable specific interrupt in SIE
# Usage: DISABLE_S_INTERRUPT 5
.macro DISABLE_S_INTERRUPT bit_pos
    li      t0, (1 << \bit_pos)
    csrrc   zero, sie, t0
.endm

# Set interrupt pending bit in MIP
# Usage: SET_M_INTERRUPT_PENDING 7 (for MTI)
.macro SET_M_INTERRUPT_PENDING bit_pos
    li      t0, (1 << \bit_pos)
    csrrs   zero, mip, t0
.endm

# Clear interrupt pending bit in MIP
# Usage: CLEAR_M_INTERRUPT_PENDING 7
.macro CLEAR_M_INTERRUPT_PENDING bit_pos
    li      t0, (1 << \bit_pos)
    csrrc   zero, mip, t0
.endm

# ==============================================================================
# DEBUGGING MACROS
# ==============================================================================

# Save register to a known memory location for debugging
# Usage: SAVE_REG x10, debug_save_area
.macro SAVE_REG reg, mem_label
    la      t6, \mem_label
    sw      \reg, 0(t6)
.endm

# Save all important CSRs for debugging
# Usage: SAVE_ALL_CSRS csr_save_area
.macro SAVE_ALL_CSRS mem_label
    la      t6, \mem_label
    csrr    t5, mstatus
    sw      t5, 0(t6)
    csrr    t5, mepc
    sw      t5, 4(t6)
    csrr    t5, mcause
    sw      t5, 8(t6)
    csrr    t5, mtval
    sw      t5, 12(t6)
.endm

# Print register value (if simulator supports it)
# Usage: DEBUG_PRINT_REG x10
.macro DEBUG_PRINT_REG reg
    # This is a placeholder - actual implementation depends on simulator
    # Most simulators support special addresses for debug output
    nop
.endm

# ==============================================================================
# COMMON TEST PATTERNS
# ==============================================================================

# Standard test preamble - setup both trap vectors
# Usage: TEST_PREAMBLE
.macro TEST_PREAMBLE
    # Set M-mode trap vector
    la      t0, m_trap_handler
    csrw    mtvec, t0

    # Set S-mode trap vector
    la      t0, s_trap_handler
    csrw    stvec, t0

    # Clear delegations
    csrw    medeleg, zero
    csrw    mideleg, zero
.endm

# Standard test epilogue - mark success
# Usage: TEST_EPILOGUE (same as TEST_PASS)
.macro TEST_EPILOGUE
    TEST_PASS
.endm

# ==============================================================================
# DATA SECTION HELPER
# ==============================================================================

# Define data area for trap testing
# Usage: TRAP_TEST_DATA_AREA (place at end of test file)
.macro TRAP_TEST_DATA_AREA
.section .data
.align 4
expected_cause:
    .word   0
trap_count:
    .word   0
debug_save_area:
    .skip   64          # 16 words for debugging
csr_save_area:
    .skip   64          # 16 words for CSR saves
.endm

# ==============================================================================
# END OF MACRO LIBRARY
# ==============================================================================
