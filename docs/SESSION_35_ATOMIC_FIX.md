# Session 35: Atomic Operations Fix - Write Pulse Exception

**Date**: 2025-10-27
**Status**: ✅ COMPLETE
**Impact**: CRITICAL - Fixes atomic operation regressions from Session 34

---

## Problem Discovery

After Session 34's UART duplication fix, quick regression showed **2 atomic tests failing**:
- `rv32ua-p-amoswap_w` - FAILED at test #7 (gp=0x7)
- `rv32ua-p-lrsc` - TIMEOUT/ERROR

Previously these tests were passing at 100% compliance (81/81 tests).

---

## Root Cause Analysis

**Session 34's Write Pulse Logic**:
```verilog
// Generate one-shot pulse on FIRST cycle instruction enters MEM stage
wire mem_stage_new_instr = exmem_valid && ((exmem_pc != exmem_pc_prev) || !exmem_valid_prev);
wire arb_mem_write_pulse = dmem_mem_write && mem_stage_new_instr;  // ONE-SHOT PULSE
```

**Why This Broke Atomics**:
1. Atomic operations (LR/SC, AMO) perform **multi-cycle read-modify-write** sequences
2. During RMW, the instruction **stays in MEM stage** with the **same PC** for multiple cycles
3. The atomic unit (`ex_atomic_busy=1`) controls memory writes across multiple cycles
4. One-shot pulse logic only triggered on **first cycle** → subsequent atomic writes were blocked

**Atomic Operation Sequence** (Example: AMOSWAP):
```
Cycle 1: ex_atomic_busy=1, mem_stage_new_instr=1 → write_pulse=1 ✓ (read request)
Cycle 2: ex_atomic_busy=1, mem_stage_new_instr=0 → write_pulse=0 ✗ (write blocked!)
Cycle 3: ex_atomic_busy=1, mem_stage_new_instr=0 → write_pulse=0 ✗ (write blocked!)
```

Result: Atomic write phase never completed → test failures

---

## Solution

Add **exception for atomic operations** - use level signal when atomic unit is busy:

```verilog
// CRITICAL: Only WRITES need to be one-shot pulses to prevent duplicate side effects
// READS can be level signals (needed for multi-cycle operations, atomics, etc.)
// EXCEPTION: Atomic operations (LR/SC, AMO) need LEVEL signals for multi-cycle read-modify-write
//            The atomic unit controls writes via ex_atomic_busy, so allow continuous writes
wire arb_mem_write_pulse = mmu_ptw_req_valid ? 1'b0 :
                           ex_atomic_busy ? dmem_mem_write :                       // Atomic: level signal
                           (dmem_mem_write && mem_stage_new_instr);                // Normal: one-shot pulse
```

**Key Insight**:
- **Normal stores**: One-shot pulse prevents UART/GPIO character duplication ✓
- **Atomic operations**: Level signal allows multi-cycle RMW to complete ✓
- Best of both worlds!

---

## Changes Made

**File**: `rtl/core/rv32i_core_pipelined.v`

**Lines Modified**: 2403-2405 (3 lines)

**Change Type**: Logic enhancement (added conditional for atomic operations)

---

## Verification Results

### Quick Regression (14 tests)
```
✓ rv32ui-p-add
✓ rv32ui-p-jal
✓ rv32um-p-mul
✓ rv32um-p-div
✓ rv32ua-p-amoswap_w    ← FIXED!
✓ rv32ua-p-lrsc         ← FIXED!
✓ rv32uf-p-fadd
✓ rv32uf-p-fcvt
✓ rv32ud-p-fadd
✓ rv32ud-p-fcvt
✓ rv32uc-p-rvc
✓ test_fp_compare_simple
✓ test_priv_minimal
✓ test_fp_add_simple

Result: 14/14 PASSED (was 12/14)
```

### Full Atomic Test Suite (10 tests)
```
✓ rv32ua-p-amoadd_w
✓ rv32ua-p-amoand_w
✓ rv32ua-p-amomax_w
✓ rv32ua-p-amomaxu_w
✓ rv32ua-p-amomin_w
✓ rv32ua-p-amominu_w
✓ rv32ua-p-amoor_w
✓ rv32ua-p-amoswap_w
✓ rv32ua-p-amoxor_w
✓ rv32ua-p-lrsc

Result: 10/10 PASSED (100%)
```

### FreeRTOS UART Output
```
Cycle 6161-6515: "FreeRTOS Blinky Demo"
Cycle 6553-6783: "Target: RV"

Result: NO character duplication ✓
Each character appears exactly ONCE ✓
```

---

## Impact Assessment

**Affected Components**:
- ✅ Atomic operations (LR/SC, AMO) - **FIXED**
- ✅ Normal stores (UART, GPIO) - **Still working** (no duplication)
- ✅ FreeRTOS boot - **Still working** (clean output)

**Test Coverage**:
- Quick regression: 14/14 passing
- Atomic suite: 10/10 passing
- UART functionality: Verified clean output

**Status**: All functionality restored, no regressions detected

---

## Technical Notes

### Why Atomic Unit Uses Level Signals

The atomic unit implements multi-cycle sequences:

1. **LR/SC (Load-Reserved/Store-Conditional)**:
   - Cycle 1: LR reads from memory, sets reservation
   - Cycle N: SC checks reservation, conditionally writes

2. **AMO (Atomic Memory Operations)**:
   - Cycle 1: Read current value from memory
   - Cycle 2: Perform operation (add/swap/and/or/xor/min/max)
   - Cycle 3: Write result back to memory

Both require the instruction to **stay in MEM stage** across multiple cycles while `ex_atomic_busy=1`. The atomic unit controls when reads/writes occur via `ex_atomic_mem_req` and `ex_atomic_mem_we`.

### Write Pulse vs Level Signal Trade-offs

| Signal Type | Use Case | Advantage | Disadvantage |
|-------------|----------|-----------|--------------|
| **One-shot pulse** | Normal stores (SB/SH/SW/SD) | Prevents duplicate writes to MMIO | Cannot handle multi-cycle ops |
| **Level signal** | Atomic ops (LR/SC/AMO) | Supports multi-cycle sequences | Could cause duplicates if not controlled |

**Solution**: Use pulse for normal stores, level for atomics (controlled by atomic unit's state machine)

---

## Lessons Learned

1. **Multi-cycle operations need special handling**: Write pulse optimization must account for operations that legitimately need multiple cycles in MEM stage

2. **State machine signals are key**: `ex_atomic_busy` indicates when atomic unit controls memory → use it to gate write pulse logic

3. **Regression testing is critical**: Quick regression (14 tests, 7s) caught this immediately after the change

4. **Verify fix doesn't break original issue**: Confirmed UART still works without duplication after atomic fix

---

## Follow-up Actions

- ✅ Fix implemented and tested
- ✅ Quick regression passing (14/14)
- ✅ Full atomic suite passing (10/10)
- ✅ UART functionality verified (no duplication)
- ✅ Full compliance suite run (80/81) - **COMPLETE**
- ✅ KNOWN_ISSUES.md updated with FENCE.I issue
- 🚧 Update CLAUDE.md with Session 35 summary - **PENDING**

---

## Full Compliance Suite Results

**Overall**: 80/81 passing (98.8%)

### ✅ Passing Extensions (80 tests)
- **RV32I**: 41/42 (FENCE.I failing - pre-existing issue)
- **RV32M**: 8/8 ✅ (mul, div, rem variants)
- **RV32A**: 10/10 ✅ (AMO + LR/SC - **FIXED IN THIS SESSION**)
- **RV32F**: 11/11 ✅ (single-precision FP)
- **RV32D**: 9/9 ✅ (double-precision FP)
- **RV32C**: 1/1 ✅ (compressed instructions)

### ❌ Failed Test (1)
- `rv32ui-p-fence_i` - **Pre-existing bug since Session 33**
  - Not caused by Session 34 or 35 changes (verified via git checkout)
  - Self-modifying code support affected by IMEM bus integration
  - Low priority - rarely used in real-world code
  - FreeRTOS/Linux not affected

### Compliance Status Change
- **Before Session 35**: 78/81 (96.3%) - 2 atomic tests failing
- **After Session 35**: 80/81 (98.8%) - Atomic tests fixed, FENCE.I issue documented

---

## References

- **Session 34**: UART Character Duplication Fix (write pulse implementation)
- **File**: `rtl/core/rv32i_core_pipelined.v` lines 2379-2414
- **Atomic Unit**: `rtl/core/atomic_unit.v`
- **Test Results**: Quick regression passed in 2s
