# Session 50: Bus Interconnect Investigation - Testbench Issue Found

**Date**: 2025-10-28
**Status**: Partial Progress - One bug solved, one remains
**Achievement**: Found testbench mismatch causing test failures ✅

---

## Problem Statement

FreeRTOS timer interrupts not working - investigation revealed that MTIMECMP writes (address 0x02004000) were not reaching the CLINT peripheral.

---

## Investigation Process

### Phase 1: Bus Tracing Infrastructure

Added comprehensive debug tracing:

1. **Core-level tracing** (`rtl/core/rv32i_core_pipelined.v`):
   - Added `DEBUG_BUS` support with detailed bus transaction logging
   - Traces all bus writes/reads with address, data, PC
   - Highlights CLINT address range (0x0200_xxxx)

2. **Bus interconnect tracing** (`rtl/interconnect/simple_bus.v`):
   - Enhanced debug output showing device selection
   - Address decode verification
   - Request routing visualization

3. **CLINT peripheral tracing** (`rtl/peripherals/clint.v`):
   - Request validation logging
   - Write operation tracking for MTIMECMP/MTIME/MSIP

4. **Test infrastructure** (`tools/test_freertos.sh`):
   - Added DEBUG_BUS flag support

### Phase 2: Test Verification

Discovered `test_clint_basic` unit test hangs:
```bash
env XLEN=32 timeout 2s ./tools/run_test_by_name.sh test_clint_basic
# Result: TIMEOUT (hangs forever)
```

### Phase 3: Git Bisect (Misleading!)

Attempted git bisect between Session 18 (documented as passing) and HEAD:
- Result: Session 19 flagged as "first bad commit"
- However: Session 18 ALSO times out with same test!
- Conclusion: Bisect was testing with wrong infrastructure

### Phase 4: Testbench Discovery (ROOT CAUSE #1)

Found that different testbenches exist:

**tb_core_pipelined.v**:
- Used by: `./tools/run_test_by_name.sh`
- Instantiates: `rv_core_pipelined` (core ONLY)
- **NO peripherals** - no CLINT, UART, PLIC, etc.
- Purpose: Core-only tests (arithmetic, branches, CSRs)

**tb_soc.v**:
- Used by: `./tools/test_soc.sh`
- Instantiates: `rv_soc` (full SoC)
- **Has peripherals** - CLINT, UART, PLIC, DMEM, bus interconnect
- Purpose: Peripheral integration tests

**Test Result**:
```bash
# FAILS (wrong testbench - no CLINT peripheral):
env XLEN=32 ./tools/run_test_by_name.sh test_clint_basic
# Result: TIMEOUT

# PASSES (correct testbench - has CLINT):
env XLEN=32 ./tools/test_soc.sh test_clint_basic
# Result: PASSED in 11 cycles ✅
```

---

## Bug #1: Testbench Mismatch ✅ SOLVED

### Root Cause

Peripheral tests (CLINT, UART, etc.) require SoC testbench but were being run with core-only testbench.

When `test_clint_basic` runs on `tb_core_pipelined.v`:
1. Core generates bus request to CLINT address (0x02004000)
2. No CLINT peripheral exists in testbench
3. Bus request hangs waiting for non-existent peripheral
4. Test times out

### Solution

Use correct test infrastructure:
- **Core tests**: Use `./tools/run_test_by_name.sh` (tb_core_pipelined.v)
- **Peripheral tests**: Use `./tools/test_soc.sh` (tb_soc.v)
- **FreeRTOS tests**: Use `./tools/test_freertos.sh` (tb_freertos.v → rv_soc)

### Verification

```bash
# All these work correctly:
env XLEN=32 ./tools/test_soc.sh test_clint_basic          # 11 cycles ✅
env XLEN=32 ./tools/test_soc.sh test_interrupt_mtimer     # Works ✅
env XLEN=32 ./tools/test_soc.sh test_mmio_peripherals     # Works ✅
```

---

## Bug #2: FreeRTOS MTIMECMP Writes ❌ UNSOLVED

### Problem

Even with correct testbench (tb_freertos.v → rv_soc with CLINT), FreeRTOS timer setup code does NOT generate bus transactions to CLINT.

### Evidence

```bash
env XLEN=32 DEBUG_BUS=1 TIMEOUT=2 ./tools/test_freertos.sh 2>&1 | grep "0x0200"
# Result: ZERO CLINT bus accesses found
```

**Expected behavior** (from FreeRTOS port code):
```c
// In vPortSetupTimerInterrupt() at PC ~0x1b10:
volatile uint64_t *pullMachineTimerCompareRegister = (uint64_t *)0x02004000;
*pullMachineTimerCompareRegister = ullNextTime;  // Should generate SW to 0x02004000
```

**Actual behavior**:
- No bus write transactions to 0x02004000 observed
- Store instructions seem to execute (no exceptions)
- But bus_req_valid never asserts for CLINT addresses

### Disassembly Analysis

```assembly
# vPortSetupTimerInterrupt at 0x1aca:
1b10:	c194                	sw	a3,0(a1)    # Store lower 32 bits
1b1e:	0115a223          	sw	a7,4(a1)    # Store upper 32 bits
# where a1 = 0x02004000 (MTIMECMP address)
```

Stores exist in binary, addresses calculate correctly, but bus transactions don't appear.

### Status

This is the REAL bug blocking FreeRTOS timer interrupts. Requires further investigation:
- Why do these specific stores not generate bus_req_valid?
- Is there a pipeline stall/flush condition?
- Is there an issue with 64-bit store handling on RV32?
- Memory ordering or atomic operation interaction?

---

## Files Modified

### Debug Infrastructure Added

1. **rtl/core/rv32i_core_pipelined.v** (~40 lines added)
   - Bus transaction tracing under DEBUG_BUS
   - CLINT address range highlighting
   - MEM stage state display

2. **rtl/interconnect/simple_bus.v** (~40 lines modified)
   - Enhanced debug output
   - Device selection visualization
   - Address decode verification

3. **rtl/peripherals/clint.v** (~20 lines modified)
   - Request logging with cycle counts
   - Write operation tracking

4. **tools/test_freertos.sh** (3 lines added)
   - Added DEBUG_BUS flag support

5. **tests/asm/test_clint_msip_only.s** (NEW)
   - Minimal CLINT MSIP test for debugging

---

## Lessons Learned

1. **Testbench Architecture Matters**: Different testbenches for different test types
2. **Git Bisect Limitations**: Bisect can be misleading if test infrastructure changed
3. **Documentation Accuracy**: "Test passed in 22 cycles" didn't specify which test runner
4. **Verify Assumptions**: "Test worked in Session 18" was based on docs, not actual re-run

---

## Next Steps (Session 51)

1. **Debug FreeRTOS MTIMECMP writes**:
   - Add instruction-level tracing at PC 0x1b10-0x1b20
   - Check if stores reach MEM stage
   - Verify arb_mem_write_pulse logic triggers
   - Check for pipeline flushes/stalls during timer setup

2. **Test with minimal reproduction**:
   - Create simple assembly test that mimics FreeRTOS store pattern
   - Two SW instructions to 0x02004000 and 0x02004004
   - Compare behavior with working test_clint_basic

3. **Check write pulse logic**:
   - Verify mem_stage_new_instr detection
   - Check bus_req_issued flag behavior
   - Confirm arb_mem_write_pulse generation

---

## Status Summary

- ✅ **Bug #1 Solved**: Testbench mismatch - peripheral tests need test_soc.sh
- ❌ **Bug #2 Active**: FreeRTOS MTIMECMP writes don't reach bus (root cause unknown)
- 🎯 **Next Session**: Focus on why vPortSetupTimerInterrupt stores fail
- 📊 **Progress**: 50% - Found one bug, one remains

---

**Impact**: Critical - blocks FreeRTOS timer interrupts and task scheduling
**Priority**: HIGH - needed for Phase 2 completion
