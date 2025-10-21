# Debugging fcvt_w Test #5 - Focused Plan

## Current Status
- Bug #13 fix implemented ✅
- Test #2 now sets flag_nx correctly (was 0, now 1) ✅
- Test still failing at #5
- Only ONE converter invocation seen in debug logs (test #2)

## Key Observation
From log: test completes in only 116 cycles with 80 instructions
- This is VERY fast - suggests tests aren't running normally
- Converter only called once (for test #2)
- Tests #3, #4, #5 not reaching converter

## Next Steps (ONE AT A TIME)

### Step 1: Understand why so few instructions
**Question**: Why only 80 instructions when there should be 5+ tests?

**Action**: Add PC tracking to see where execution goes

### Step 2: Check if tests #3-5 even execute
**Question**: Are tests #3, #4, #5 being skipped?

**Action**: Look for branch/jump instructions that might skip tests

### Step 3: Verify FFLAGS handling
**Question**: Is FFLAGS being read/cleared correctly between tests?

**Action**: Check if fsflags/frflags CSR operations work

## Hypothesis
The test is failing BEFORE it gets to converter operations. Likely:
- Test #2 passes now (with our fix)
- Test #3 or #4 fails on some OTHER check (not converter)
- This causes early exit to fail label
- Test #5 never executes

## Immediate Action
Remove debug flags, add instruction tracing to see execution flow

