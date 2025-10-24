# Session Summary: MRET/SRET Privilege Violation Bug Fix (WIP)

**Date**: 2025-10-23
**Status**: 🔧 IN PROGRESS
**Achievement**: RTL logic implemented, verification pending

---

## 🎯 Objective

Fix the privilege violation bug discovered in Phase 1 testing where MRET and SRET instructions don't trap when executed in insufficient privilege modes.

---

## 🐛 Bug Analysis

### Root Cause
The MRET and SRET instructions were correctly decoded but never checked for privilege violations. The exception_unit had no logic to detect when these instructions execute in insufficient privilege modes.

### Expected Behavior
- **MRET**: Only allowed in M-mode → should trap with illegal instruction in S-mode or U-mode
- **SRET**: Only allowed in M-mode or S-mode → should trap with illegal instruction in U-mode

### Actual Behavior (Before Fix)
- MRET/SRET executed successfully in any privilege mode
- No illegal instruction exception was raised
- Security issue: U-mode code could potentially manipulate privilege state

---

## 🔧 Implementation

### Files Modified (3)

#### 1. `rtl/core/exception_unit.v`
**Changes**:
- Added `id_mret` and `id_sret` input ports
- Added privilege checking logic:
  ```verilog
  wire id_mret_violation = id_valid && id_mret && (current_priv != 2'b11);
  wire id_sret_violation = id_valid && id_sret && (current_priv == 2'b00);
  wire id_illegal_combined = id_illegal || id_mret_violation || id_sret_violation;
  ```
- Updated exception priority encoder to use `id_illegal_combined`
- Updated comments to reflect xRET privilege checking

**Lines Changed**: ~15 lines added/modified

#### 2. `rtl/core/rv32i_core_pipelined.v`
**Changes**:
- Connected `id_mret` and `id_sret` signals to exception_unit:
  ```verilog
  .id_mret(idex_is_mret && idex_valid),
  .id_sret(idex_is_sret && idex_valid),
  ```
- Prevented illegal xRET propagation to MEM stage:
  ```verilog
  .is_mret_in(idex_is_mret && !(exception && (exception_code == 5'd2))),
  .is_sret_in(idex_is_sret && !(exception && (exception_code == 5'd2))),
  ```
- Updated mret_flush/sret_flush to not trigger on exceptions:
  ```verilog
  assign mret_flush = exmem_is_mret && exmem_valid && !exception;
  assign sret_flush = exmem_is_sret && exmem_valid && !exception;
  ```

**Lines Changed**: ~10 lines modified

#### 3. `tests/asm/test_mret_trap_simple.s` (NEW)
**Purpose**: Test that MRET traps when executed in U-mode

**Test Flow**:
1. Enter U-mode via MRET
2. Attempt MRET from U-mode
3. Should trap with mcause=2 (illegal instruction)
4. Success if trap occurs

**Status**: ⚠️ Test created but times out - needs debugging

---

## ✅ Verification Results

### Regression Tests
```
make test-quick: 14/14 PASSED ✅
```
- No regressions introduced
- All existing functionality preserved

### Phase 1 Tests
```
test_umode_entry_from_mmode:  PASSED ✅
test_umode_entry_from_smode:  PASSED ✅
test_umode_ecall:              PASSED ✅
test_umode_csr_violation:      PASSED ✅
test_umode_illegal_instr:      PASSED ✅
```
- All Phase 1 tests still passing
- Legitimate MRET/SRET usage works correctly

### New Privilege Tests
```
test_mret_trap_simple:  TIMEOUT ⚠️
test_xret_privilege_trap:  TIMEOUT ⚠️
```
- Tests timeout instead of passing
- Indicates issue with test or privilege state tracking

---

## 🔍 Current Issue

### Symptom
Test `test_mret_trap_simple` times out with:
- 49,999 cycles executed
- 12,512 instructions (too many for simple test)
- 12,496 flushes (25% - indicates looping)
- x28 (t3) = 0x00000000 (neither PASS nor FAIL marker set)

### Possible Causes
1. **Privilege mode not set correctly**: `current_priv` may not be 2'b00 (U-mode) when expected
2. **Exception not triggering**: MRET violation check may not be activating
3. **Test flow issue**: Trap handler may not be reached or executed correctly
4. **Signal timing**: Exception signals may have timing/propagation issues

### Debug Approach for Next Session
1. Add waveform analysis to check `current_priv` signal
2. Verify `id_mret_violation` signal goes high
3. Check `exception` and `exception_code` signals
4. Trace execution through trap handler
5. Simplify test to minimal case

---

## 📊 Technical Details

### Privilege Checking Logic
```verilog
// MRET: Only allowed in M-mode (priv == 2'b11)
wire id_mret_violation = id_valid && id_mret && (current_priv != 2'b11);

// SRET: Only allowed in M-mode or S-mode (priv >= 2'b01)
wire id_sret_violation = id_valid && id_sret && (current_priv == 2'b00);
```

### Exception Priority
1. Instruction address misaligned (IF)
2. EBREAK (ID)
3. ECALL (ID)
4. **Illegal instruction (ID) - includes MRET/SRET violations** ← NEW
5. Load/Store page fault (MEM)
6. Load address misaligned (MEM)
7. Store address misaligned (MEM)

### xRET Flush Control
```verilog
// Only flush on xRET if no exception
assign mret_flush = exmem_is_mret && exmem_valid && !exception;
assign sret_flush = exmem_is_sret && exmem_valid && !exception;

// Prevent illegal xRET from propagating to MEM stage
.is_mret_in(idex_is_mret && !(exception && (exception_code == 5'd2)))
.is_sret_in(idex_is_sret && !(exception && (exception_code == 5'd2)))
```

---

## 📝 Test Infrastructure Created

### Test Files
- `tests/asm/test_mret_trap_simple.s` - Simple MRET U-mode trap test
- `tests/asm/test_xret_privilege_trap.s` - Comprehensive xRET trap test (3 test cases)

### Test Coverage Planned
1. ✅ SRET in U-mode → illegal instruction
2. ✅ MRET in U-mode → illegal instruction
3. ✅ MRET in S-mode → illegal instruction

---

## 🎯 Next Session Tasks

### High Priority
1. **Debug test timeout issue**
   - Use waveform viewer (gtkwave) to trace signals
   - Check privilege mode transitions
   - Verify exception triggering

2. **Fix and verify tests**
   - Get `test_mret_trap_simple` passing
   - Run comprehensive `test_xret_privilege_trap`

3. **Complete verification**
   - Run full compliance suite
   - Verify no regressions in official tests

### Medium Priority
4. **Update Phase 1 tests**
   - Remove workarounds for MRET/SRET bug
   - Add direct MRET/SRET privilege tests

5. **Documentation**
   - Update bug status in all docs
   - Add technical notes on fix

---

## 💡 Lessons Learned

### What Went Well
1. ✅ Root cause identified quickly through systematic analysis
2. ✅ Fix implementation was straightforward and clean
3. ✅ No regressions - all existing tests still pass
4. ✅ Good separation of concerns (exception_unit handles privilege checking)

### Challenges
1. ⚠️ Test verification taking longer than expected
2. ⚠️ Privilege mode state tracking harder to debug
3. ⚠️ Pipeline timing interactions complex

### Key Insights
- Privilege checking must happen early (EX stage) to prevent propagation
- xRET instructions need special handling - they modify PC but can also trap
- Exception priority is critical - traps must block xRET execution
- Test infrastructure needs better debugging support (signal traces, etc.)

---

## 📈 Progress Metrics

### Code Changes
- Files Modified: 2 RTL files
- Files Created: 2 test files
- Lines Added: ~30 (RTL)
- Lines Added: ~160 (tests)

### Testing
- Regression Tests: 14/14 passing ✅
- Phase 1 Tests: 5/5 passing ✅
- New Privilege Tests: 0/2 passing ⚠️

### Time Spent
- Bug Analysis: ~30 min
- Implementation: ~45 min
- Testing/Debug: ~45 min
- **Total**: ~2 hours

---

## 🔗 References

- **RISC-V Privileged Spec**: Section 3.3.2 (Privilege Modes)
- **Bug Discovery**: `SESSION_PHASE1_SUMMARY.md` - Bug #1
- **Original Issue**: Documented in Phase 1 test `test_umode_illegal_instr.s` line 15-16

---

## 🚀 Commands for Next Session

### Quick Start
```bash
# Check current status
make test-quick

# Run Phase 1 tests
for test in test_umode_*; do
  env XLEN=32 ./tools/test_pipelined.sh $test
done

# Debug MRET trap test
env XLEN=32 ./tools/test_pipelined.sh test_mret_trap_simple

# View waveform for debugging
gtkwave sim/waves/core_pipelined.vcd

# Check git status
git status
```

### Debugging Checklist
- [ ] Verify `current_priv` is 2'b00 when in U-mode
- [ ] Check `id_mret_violation` signal activates
- [ ] Verify `exception` signal goes high
- [ ] Confirm `exception_code` = 5'd2
- [ ] Trace trap handler execution
- [ ] Check mepc/mcause CSRs

---

**Status**: Ready for next session debugging 🔧
