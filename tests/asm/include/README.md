# RISC-V Privilege Mode Test Macro Library

This directory contains reusable assembly macros for writing privilege mode tests.

## Files

- **`priv_test_macros.s`** - Comprehensive privilege testing macro library

## Usage

Include the macro library at the top of your test file:

```assembly
.include "tests/asm/include/priv_test_macros.s"
```

## Quick Reference

### Privilege Transitions

```assembly
ENTER_UMODE_M target_label      # M→U via MRET
ENTER_SMODE_M target_label      # M→S via MRET
ENTER_UMODE_S target_label      # S→U via SRET
RETURN_SMODE target_label       # Return to S-mode via SRET
RETURN_MMODE target_label       # Return to M-mode via MRET
```

### Trap Vector Setup

```assembly
SET_MTVEC_DIRECT handler        # Set M-mode trap handler (direct mode)
SET_STVEC_DIRECT handler        # Set S-mode trap handler (direct mode)
```

### MSTATUS Manipulation

```assembly
SET_MPP PRIV_S                  # Set MPP field (PRIV_U, PRIV_S, PRIV_M)
SET_SPP PRIV_U                  # Set SPP field (PRIV_U or PRIV_S)
ENABLE_MIE                      # Enable machine interrupts
DISABLE_MIE                     # Disable machine interrupts
ENABLE_SIE                      # Enable supervisor interrupts
DISABLE_SIE                     # Disable supervisor interrupts
ENABLE_SUM                      # Enable supervisor user memory access
DISABLE_SUM                     # Disable supervisor user memory access
```

### Trap Delegation

```assembly
DELEGATE_EXCEPTION CAUSE_ILLEGAL_INSTR      # Delegate specific exception
UNDELEGATE_EXCEPTION CAUSE_ILLEGAL_INSTR    # Remove delegation
DELEGATE_ALL_EXCEPTIONS                      # Delegate all exceptions
CLEAR_EXCEPTION_DELEGATION                   # Clear all delegations
DELEGATE_INTERRUPT 1                         # Delegate interrupt bit
```

### CSR Verification

```assembly
EXPECT_CSR mstatus, 0x1800, fail_label      # Verify CSR value
EXPECT_BITS_SET mstatus, MSTATUS_MIE, fail_label    # Verify bits set
EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, fail_label  # Verify bits clear
EXPECT_MPP PRIV_S, fail_label                # Verify MPP field
EXPECT_SPP PRIV_U, fail_label                # Verify SPP field
```

### Test Results

```assembly
TEST_PASS                       # Mark test passed and exit
TEST_FAIL                       # Mark test failed and exit
TEST_FAIL_CODE 5                # Mark test failed with error code
TEST_STAGE 3                    # Mark test stage (for debugging)
```

### Common Patterns

```assembly
TEST_PREAMBLE                   # Standard test setup (trap vectors, clear delegation)
TEST_EPILOGUE                   # Standard test success (same as TEST_PASS)
TRAP_TEST_DATA_AREA             # Define data section for trap testing
```

## Constants

### Privilege Levels
- `PRIV_U` (0x0) - User mode
- `PRIV_S` (0x1) - Supervisor mode
- `PRIV_M` (0x3) - Machine mode

### Exception Causes
- `CAUSE_MISALIGNED_FETCH` (0)
- `CAUSE_FETCH_ACCESS` (1)
- `CAUSE_ILLEGAL_INSTR` (2)
- `CAUSE_BREAKPOINT` (3)
- `CAUSE_MISALIGNED_LOAD` (4)
- `CAUSE_LOAD_ACCESS` (5)
- `CAUSE_MISALIGNED_STORE` (6)
- `CAUSE_STORE_ACCESS` (7)
- `CAUSE_ECALL_U` (8)
- `CAUSE_ECALL_S` (9)
- `CAUSE_ECALL_M` (11)
- `CAUSE_FETCH_PAGE_FAULT` (12)
- `CAUSE_LOAD_PAGE_FAULT` (13)
- `CAUSE_STORE_PAGE_FAULT` (15)

### MSTATUS Bits
- `MSTATUS_SIE` - Supervisor Interrupt Enable
- `MSTATUS_MIE` - Machine Interrupt Enable
- `MSTATUS_SPIE` - Supervisor Previous Interrupt Enable
- `MSTATUS_MPIE` - Machine Previous Interrupt Enable
- `MSTATUS_SPP` - Supervisor Previous Privilege
- `MSTATUS_MPP_MASK` - Machine Previous Privilege mask
- `MSTATUS_SUM` - Supervisor User Memory access
- `MSTATUS_MXR` - Make eXecutable Readable

### Test Markers
- `TEST_PASS_MARKER` (0xDEADBEEF) - Success indicator
- `TEST_FAIL_MARKER` (0xDEADDEAD) - Failure indicator

## Example Test

See `tests/asm/test_priv_macros_demo.s` for a complete example.

```assembly
.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    TEST_PREAMBLE               # Setup trap handlers

    # Test M→S transition
    ENTER_SMODE_M s_mode_code

s_mode_code:
    # Verify we're in S-mode by checking SPP can be accessed
    li      t0, 0x12345678
    csrw    sscratch, t0
    csrr    t1, sscratch
    bne     t0, t1, test_fail

    TEST_PASS

test_fail:
    TEST_FAIL

m_trap_handler:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

TRAP_TEST_DATA_AREA
```

## Benefits

✅ **Readability** - Clear intent vs manual bit manipulation
✅ **Consistency** - Same patterns across all tests
✅ **Maintainability** - Update macros instead of every test
✅ **Error Reduction** - Correct bit masks and shifts
✅ **Documentation** - Self-documenting test code

## Before (without macros)

```assembly
# Set MPP = 01 (S-mode) - manual bit manipulation
csrr    t0, mstatus
li      t1, 0xFFFFE7FF        # Mask to clear MPP[12:11]
and     t0, t0, t1
li      t1, 0x00000800        # MPP = 01
or      t0, t0, t1
csrw    mstatus, t0
la      t0, s_mode_entry
csrw    mepc, t0
mret
```

## After (with macros)

```assembly
# Enter S-mode - clear and simple
ENTER_SMODE_M s_mode_entry
```

## Notes

- Macros use temporary registers `t0`, `t1`, `t2`, `t5`, `t6`
- Some macros use `x29` for stage tracking
- Test results use `x28` for pass/fail markers
- All trap-related macros assume standard trap handler labels exist
