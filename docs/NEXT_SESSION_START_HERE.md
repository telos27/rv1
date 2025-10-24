# 🚀 Next Session: Privilege Mode Testing Implementation

**Session Goal**: Implement Phase 1 - U-Mode Fundamentals (6 tests)
**Priority**: 🔴 CRITICAL
**Estimated Time**: 2-3 hours
**Status**: Ready to Begin

---

## Quick Start Guide

### 1. Environment Check (5 minutes)
```bash
cd /home/lei/rv1

# Verify test infrastructure works
make test-quick

# Expected output:
# ✓ All quick regression tests PASSED!
# Safe to proceed with development.

# Check macro library exists
ls tests/asm/include/priv_test_macros.s
cat tests/asm/include/README.md | head -20
```

### 2. Review Key Documents (10 minutes)
**Must Read Before Starting**:
1. `docs/PRIVILEGE_TEST_IMPLEMENTATION_PLAN.md` - Section "Phase 1"
2. `tests/asm/include/README.md` - Macro quick reference
3. `docs/PRIVILEGE_TEST_CHECKLIST.md` - Track your progress

**Quick Reference**:
- Macro library: `tests/asm/include/priv_test_macros.s`
- Demo test: `tests/asm/test_priv_macros_demo.s`
- Template: See implementation plan Phase 1.1

### 3. Implementation Order

**Implement these 6 tests in order**:

#### Test 1.1: `test_umode_entry_from_mmode.s` (30 min)
**Purpose**: Verify M→U transition via MRET
**Key Points**:
- Use `ENTER_UMODE_M target` macro
- Verify CSR access traps in U-mode
- Check cause = CAUSE_ILLEGAL_INSTR

**Template Location**: Plan document, Phase 1, Test 1.1

---

#### Test 1.2: `test_umode_entry_from_smode.s` (30 min)
**Purpose**: Verify S→U transition via SRET
**Key Points**:
- First `ENTER_SMODE_M`, then `ENTER_UMODE_S`
- Verify privileged instructions trap
- Test with and without delegation

**Template Location**: Plan document, Phase 1, Test 1.2

---

#### Test 1.3: `test_umode_ecall.s` (30 min)
**Purpose**: ECALL from U-mode (cause code 8)
**Key Points**:
- Test without delegation → M-mode
- Test with delegation → S-mode
- Verify cause = CAUSE_ECALL_U

**Template Location**: Plan document, Phase 1, Test 1.3

---

#### Test 1.4: `test_umode_csr_violation.s` (20 min)
**Purpose**: All CSR accesses trap from U-mode
**Key Points**:
- Try M-mode CSRs: mstatus, mepc, mscratch
- Try S-mode CSRs: sstatus, sepc, sscratch
- Each should trap with CAUSE_ILLEGAL_INSTR

**Template Location**: Plan document, Phase 1, Test 1.4

---

#### Test 1.5: `test_umode_illegal_instr.s` (20 min)
**Purpose**: Privileged instructions trap in U-mode
**Key Points**:
- Test MRET (M-mode only)
- Test SRET (S-mode and above)
- Test WFI (may trap based on TW bit)
- All should cause CAUSE_ILLEGAL_INSTR

**Template Location**: Plan document, Phase 1, Test 1.5

---

#### Test 1.6: `test_umode_memory_sum.s` (20 min)
**Purpose**: SUM bit controls S-mode access to U-mode pages
**Key Points**:
- SUM=0: S-mode can't access U-mode pages
- SUM=1: S-mode can access U-mode pages
- U-mode always accesses own pages
- **NOTE**: May SKIP if MMU not fully implemented

**Template Location**: Plan document, Phase 1, Test 1.6

---

### 4. Build & Test Workflow

**For each test**:
```bash
# 1. Create test file
vim tests/asm/test_umode_entry_from_mmode.s

# 2. Use standard template (from plan document)
# Include macro library at top:
.include "tests/asm/include/priv_test_macros.s"

# 3. Build test
tools/assemble.sh tests/asm/test_umode_entry_from_mmode.s

# 4. Check disassembly (verify addresses start at 0x0)
riscv64-unknown-elf-objdump -d tests/vectors/test_umode_entry_from_mmode.elf | head -40

# 5. Run test
tools/run_test.sh test_umode_entry_from_mmode

# 6. Check result
# Expected: ✓ Test PASSED

# 7. Update checklist
vim docs/PRIVILEGE_TEST_CHECKLIST.md
# Mark test as complete [x]
```

**After all 6 tests complete**:
```bash
# Validate phase
make test-custom-all | grep umode
# Expected: 5-6 tests passing (1 may SKIP)

# Verify no regressions
make test-quick
# Expected: ✓ All quick regression tests PASSED!

# Update catalog
make catalog

# Check catalog
cat docs/TEST_CATALOG.md | grep -A2 "umode"
```

---

## 📝 Standard Test Template

Save this as starting point for each test:

```assembly
# ==============================================================================
# Test: [Test Name]
# ==============================================================================
#
# Purpose: [What this test verifies]
#
# Test Flow:
#   1. [Step 1]
#   2. [Step 2]
#   ...
#
# Expected Result: [What should happen]
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    ###########################################################################
    # SETUP
    ###########################################################################
    TEST_PREAMBLE           # Setup trap handlers, clear delegations

    ###########################################################################
    # TEST BODY
    ###########################################################################
    # [Your test code here]

    TEST_PASS

# =============================================================================
# TRAP HANDLERS
# =============================================================================
m_trap_handler:
    # [M-mode trap handling]
    TEST_FAIL

s_trap_handler:
    # [S-mode trap handling]
    TEST_FAIL

test_fail:
    TEST_FAIL

# =============================================================================
# DATA SECTION
# =============================================================================
TRAP_TEST_DATA_AREA

.align 4
```

---

## 🎯 Session Success Criteria

By end of session, you should have:
- [ ] 6 test files created
- [ ] All 6 tests compile without errors
- [ ] 5-6 tests passing (1 may SKIP if MMU incomplete)
- [ ] `make test-quick` still passes (no regressions)
- [ ] Checklist updated with progress
- [ ] Tests committed to git

---

## 🔧 Common Macros You'll Use

**Privilege Transitions**:
```assembly
ENTER_UMODE_M target       # Enter U-mode from M-mode
ENTER_SMODE_M target       # Enter S-mode from M-mode
ENTER_UMODE_S target       # Enter U-mode from S-mode
```

**Trap Setup**:
```assembly
TEST_PREAMBLE              # Setup both M and S trap handlers
SET_MTVEC_DIRECT handler   # Set M-mode trap vector
SET_STVEC_DIRECT handler   # Set S-mode trap vector
```

**CSR Verification**:
```assembly
EXPECT_CSR mcause, CAUSE_ILLEGAL_INSTR, test_fail
EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail
```

**Delegation**:
```assembly
DELEGATE_EXCEPTION CAUSE_ILLEGAL_INSTR
CLEAR_EXCEPTION_DELEGATION
```

**Test Results**:
```assembly
TEST_PASS                  # Mark success and exit
TEST_FAIL                  # Mark failure and exit
TEST_STAGE 3               # Mark stage (for debugging)
```

**Constants**:
```assembly
PRIV_U                     # 0x0 - User mode
PRIV_S                     # 0x1 - Supervisor mode
PRIV_M                     # 0x3 - Machine mode

CAUSE_ILLEGAL_INSTR        # 2
CAUSE_BREAKPOINT           # 3
CAUSE_ECALL_U              # 8
CAUSE_ECALL_S              # 9
CAUSE_ECALL_M              # 11
```

---

## 🐛 Debugging Tips

**If test times out**:
```bash
# Check what instruction PC is stuck on
# Look at final PC in output
riscv64-unknown-elf-objdump -d tests/vectors/[test].elf | grep [PC_value]
```

**If test fails with wrong cause**:
- Check RTL exception priority
- Verify instruction actually triggers expected exception
- Check delegation isn't interfering

**If privilege transitions don't work**:
- Verify MPP/SPP bits set correctly before xRET
- Check disassembly for correct macro expansion
- Verify RTL privilege mode update logic

**Add debug markers**:
```assembly
TEST_STAGE 1               # Sets x29 = 1
TEST_STAGE 2               # Sets x29 = 2
# If test fails, x29 shows how far it got
```

---

## 📊 Track Your Progress

**Time Estimate**:
- Setup & review: 15 min
- Test 1.1-1.3: 90 min (30 min each)
- Test 1.4-1.6: 60 min (20 min each)
- Debugging: 30 min (buffer)
- Validation: 15 min
- **Total**: ~3 hours

**Update checklist as you go**:
```bash
vim docs/PRIVILEGE_TEST_CHECKLIST.md
# Fill in:
# - Date/time
# - Tests completed
# - Issues found
# - Session notes
```

---

## 📚 Key Documentation

1. **Implementation Plan** (PRIMARY REFERENCE)
   - `docs/PRIVILEGE_TEST_IMPLEMENTATION_PLAN.md`
   - Section: "Phase 1: U-Mode Fundamentals"
   - Has complete code examples for each test

2. **Macro Reference** (KEEP OPEN)
   - `tests/asm/include/README.md`
   - Quick lookup for macro syntax

3. **Checklist** (TRACK PROGRESS)
   - `docs/PRIVILEGE_TEST_CHECKLIST.md`
   - Mark off tests as you complete them

4. **Demo Test** (EXAMPLE)
   - `tests/asm/test_priv_macros_demo.s`
   - Shows working example of macros

---

## ✅ Pre-Session Checklist

Before you start coding:
- [ ] Read Phase 1 section of implementation plan
- [ ] Review macro library README
- [ ] Run `make test-quick` (ensure baseline works)
- [ ] Have implementation plan open for reference
- [ ] Have checklist open for tracking

---

## 🎓 Learning Resources

**RISC-V Privileged Spec Sections**:
- Section 3.1.6: Privilege Modes
- Section 3.1.9: mstatus register
- Section 3.2: Trap Handling
- Section 4: Supervisor Mode

**Online**: https://riscv.org/technical/specifications/

---

## 🎯 Post-Session Tasks

After completing Phase 1:
- [ ] Run full validation
- [ ] Commit all tests
- [ ] Update checklist with results
- [ ] Document any RTL bugs found
- [ ] Plan Phase 2 for next session

---

## 💡 Tips for Success

1. **Start Simple**: Test 1.1 is the easiest, build confidence
2. **Use Macros**: Don't write manual bit manipulation, use macros!
3. **Copy Templates**: Start from implementation plan examples
4. **Test Incrementally**: Build and test each one before moving on
5. **Debug Early**: If one fails, fix before continuing
6. **Track Progress**: Update checklist as you go
7. **Ask Questions**: If stuck, review plan document or demo test

---

**Ready to begin! Start with Test 1.1: `test_umode_entry_from_mmode.s`**

**Good luck! 🚀**

---

**Document Version**: 1.0
**Created**: 2025-10-23
**For Session**: Phase 1 Implementation
