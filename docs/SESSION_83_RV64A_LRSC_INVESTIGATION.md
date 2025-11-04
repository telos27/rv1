# Session 83: RV64A LR/SC Test Investigation (2025-11-04)

## Goal
Debug the single failing RV64A test: `rv64ua-p-lrsc` (LR/SC reservation tracking)

## Status
🔍 **Investigation In Progress** - Root cause analysis underway

## Test Failure
- **Test**: rv64ua-p-lrsc
- **Result**: Test #3 fails (gp=3 at termination)
- **Expected**: Test #3 should pass (load from `foo` returns 0)
- **Actual**: Test #3 reads non-zero value from `foo`

## Investigation Summary

### Test Structure (riscv-tests/isa/rv64ua/lrsc.S)
```asm
# Test #2 (line 29-33): SC without reservation should fail
TEST_CASE( 2, a4, 1,
  la a0, foo;           # Load address of foo (0x80002008)
  li a5, 0xdeadbeef;    # Value to write
  sc.w a4, a5, (a0);    # SC without prior LR → should return 1 (fail)
)

# Test #3 (line 36-38): Verify failed SC didn't write to memory
TEST_CASE( 3, a4, 0,
  lw a4, foo;           # Load from foo → should still be 0
)
```

### Findings

#### ✅ SC Hardware is Correct
1. **Created minimal test** (`test_sc_no_reservation.s`):
   - SC without LR correctly returns 1 (failure)
   - Memory is NOT written
   - Test **PASSES** ✅

2. **Debug trace confirms**:
   ```
   [ATOMIC] SC @ 0x80002008 FAILED (wdata=0xdeadbeef)
   [RESERVATION] SC at 0x80002008, reserved=0, match=0 -> FAIL
   [CORE] Atomic in EXMEM: is_atomic=1, mem_wr=0, result=0x01
   ```
   - SC correctly returns 1
   - `mem_wr=0` confirms NO memory write
   - Reservation station correctly reports failure

#### 🔍 Mysterious Test Flow
The debug trace shows unexpected execution order:
1. Test #2 executes: Failed SC at 0x800001cc ✅
2. **Execution jumps directly to 0x800001fc** (LR/SC loop)
3. Loop writes 0x1, 0x2, 0x3... to `foo`
4. Test #3 never seems to execute normally
5. Test terminates with gp=3 (test #3 failed)

**Question**: Why does execution jump from test #2 to the loop, bypassing test #3?

#### Memory State Timeline
```
Initial:     foo = 0x00000000 (data section initialization)
Test #2:     SC fails, returns 1, NO write ✅
???:         foo remains 0 (expected)
Loop start:  LR @ 0x80002008 → reads 0x00000000 ✅
Loop:        SC writes 0x1, 0x2, 0x3, ... (loop executing)
Test #3:     Should read 0, but test fails
```

### Test Disassembly
```asm
800001cc:  sc.w   a4, a5, (a0)      # Test #2: Failed SC
800001d0:  li     t2, 1              # Expected return value
800001d4:  bne    a4, t2, fail      # Branch if a4 != 1
800001d8:  li     gp, 3              # Test #3 marker
800001dc:  auipc  a4, 0x2
800001e0:  lw     a4, -468(a4)      # Load from foo (0x80002008)
800001e4:  li     t2, 0              # Expected value = 0
800001e8:  bne    a4, t2, fail      # Branch if a4 != 0
...
800001fc:  lr.w   a4, (a0)          # Loop start
```

### Hypotheses to Investigate (Next Session)

1. **Branch Mispredict/Flush Issue**:
   - Does the branch at 0x800001d4 execute correctly?
   - Is there a pipeline flush bug causing wrong-path execution?

2. **Memory Read Timing**:
   - Does the LW at 0x800001e0 execute BEFORE or AFTER the loop?
   - Could there be a memory ordering issue?

3. **Forwarding Bug**:
   - Could the SC result (1) be incorrectly forwarded to the LW instruction?
   - Check data hazard detection around atomic instructions

4. **Test Flow Anomaly**:
   - Add PC trace to see exact instruction execution order
   - Verify test #3 marker (gp=3) is set before the failing LW

### Debug Infrastructure Created
- ✅ Minimal SC test: `tests/asm/test_sc_no_reservation.s` (PASSES)
- ✅ Debug flags: `DEBUG_ATOMIC`, `DEBUG_RESERVATION`
- ✅ Memory write tracking
- 🔲 Need: Full PC trace to see execution flow

## Next Steps (Session 84)

1. **Add PC execution trace** to see exact instruction order:
   - When does test #3 LW (0x800001e0) execute?
   - When does loop LR (0x800001fc) execute?
   - What executes between test #2 and test #3?

2. **Check branch execution**:
   - Does branch at 0x800001d4 take or fall through?
   - Is x14 (a4) correctly 1 when branch executes?

3. **Memory read debugging**:
   - What value does LW at 0x800001e0 actually read?
   - When does this read occur relative to loop writes?

4. **Check for pipeline bugs**:
   - Pipeline flush correctness
   - Data forwarding around atomic instructions
   - Memory ordering

## Files Created
- `tests/asm/test_sc_no_reservation.s` - Minimal SC test (PASSES)

## Key Insight
**The SC instruction hardware is working correctly!** The bug is in the test execution flow or memory state management, not in the LR/SC implementation itself.

## Impact
- RV64A is 95% complete (18/19 tests passing)
- RV64IMA is 98% complete (84/86 tests passing)
- Only this one LR/SC test blocking Phase 3 completion
