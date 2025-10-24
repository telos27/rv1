# Session 21 Plan: RV32D Final Push - Target 88%+

**Status**: 📋 PLANNED
**Current**: RV32D 77% (7/9 tests)
**Target**: RV32D 88%+ (8/9 tests minimum)

---

## Current Status

### Passing Tests (7/9)
✅ rv32ud-p-fadd
✅ rv32ud-p-fclass
✅ rv32ud-p-fcmp
✅ rv32ud-p-fcvt
✅ rv32ud-p-fcvt_w
✅ rv32ud-p-fmin
✅ rv32ud-p-ldst

### Failing Tests (2/9)
❌ rv32ud-p-fdiv - Floating-point division
❌ rv32ud-p-fmadd - Fused multiply-add

---

## Session Goals

**Primary**: Fix at least ONE of the remaining two tests (88% compliance)
**Stretch**: Fix BOTH tests (100% RV32D compliance!)

---

## Investigation Plan

### Phase 1: Analyze rv32ud-p-fdiv

#### Step 1: Run with Debug
```bash
env DEBUG_FPU=1 XLEN=32 timeout 30s \
  vvp sim/official-compliance/rv32ud-p-fdiv.vvp > fdiv_debug.log 2>&1
```

#### Step 2: Identify Failure Point
- Look for which test number fails (gp register value)
- Check if it's early failure (basic cases) or late (edge cases)

#### Step 3: Analyze Division Algorithm
Review `rtl/core/fp_divider.v`:
- Check for precision issues in iteration count
- Verify special case handling:
  - Division by zero
  - NaN propagation
  - Infinity cases
  - Signed zeros
- Check rounding mode implementation

#### Step 4: Common Division Bugs
- **Insufficient iterations**: Need 24 iterations for single, 53 for double
- **Incorrect normalization**: Result must be normalized correctly
- **Rounding errors**: GRS bits (guard, round, sticky) computation
- **Subnormal handling**: Denormalized inputs/outputs
- **Exception flags**: NV (invalid), DZ (divide by zero), OF, UF, NX

### Phase 2: Analyze rv32ud-p-fmadd

#### Step 1: Run with Debug
```bash
env DEBUG_FPU=1 XLEN=32 timeout 30s \
  vvp sim/official-compliance/rv32ud-p-fmadd.vvp > fmadd_debug.log 2>&1
```

#### Step 2: Identify Failure Point
- Which test case fails?
- Is it FMADD, FMSUB, FNMADD, or FNMSUB?

#### Step 3: Analyze FMA Algorithm
Review `rtl/core/fp_fma.v`:
- Verify multiply step precision
- Check addition alignment (exponent difference handling)
- Verify single rounding (critical for FMA correctness!)
- Check sign handling for different operations:
  - FMADD:  (a × b) + c
  - FMSUB:  (a × b) - c
  - FNMADD: -(a × b) + c
  - FNMSUB: -(a × b) - c

#### Step 4: Common FMA Bugs
- **Double rounding**: Must round ONCE at the end, not after multiply
- **Catastrophic cancellation**: (a × b) ≈ c with opposite signs
- **Precision loss**: Need extra guard bits for intermediate result
- **Incorrect exponent**: Alignment and normalization issues

---

## Prioritization Strategy

### Start with rv32ud-p-fdiv
**Rationale**:
1. Division is simpler than FMA (single operation vs compound)
2. More likely to be a quick fix
3. Gets us to 88% faster

### If fdiv is complex, switch to fmadd
**Indicators to switch**:
- Division algorithm looks fundamentally correct
- Bug appears to be deep in the iteration logic
- Quick inspection of FMA shows obvious issue

---

## Expected Bug Types

### Division (fdiv)
**Most Likely**:
1. Off-by-one in iteration count
2. Incorrect sticky bit computation
3. Special case mishandling

**Less Likely**:
4. Fundamental algorithm error
5. Timing/state machine bug

### FMA (fmadd)
**Most Likely**:
1. Double rounding issue
2. Sign bit error in negated variants
3. Alignment error when |exp_a - exp_b| is large

**Less Likely**:
4. Multiply stage error (would break FMUL which passes)
5. Fundamental algorithm error

---

## Debug Tools Available

### Existing Debug Flags
- `DEBUG_FPU`: Shows FPU operation start/done
- `DEBUG_FPU_CONVERTER`: Shows conversion details
- `DEBUG_FPU_DIVIDER`: (if exists) Shows division iterations
- `DEBUG_FCVT_TRACE`: FCVT-specific trace

### May Need to Add
- `DEBUG_DIV_ITER`: Division iteration-by-iteration trace
- `DEBUG_FMA_STAGES`: FMA multiply/add/round stages

---

## Success Criteria

### Minimum Success (88%)
- ✅ Fix rv32ud-p-fdiv OR rv32ud-p-fmadd
- 📝 Document the bug and fix
- 🔒 Verify no regressions in other tests

### Full Success (100%)
- ✅ Fix BOTH rv32ud-p-fdiv AND rv32ud-p-fmadd
- 📝 Complete RV32D compliance documentation
- 🎉 Celebrate 100% RV32D!

---

## Contingency Plans

### If both bugs are complex
**Option 1**: Focus on partial fix
- Get one test closer to passing (more tests passing within it)
- Document progress and remaining issues

**Option 2**: Deep dive on one
- Fully understand and fix one test
- Leave other for next session

### If bugs are in shared code
- Check fp_classifier, fp_normalizer, fp_rounder
- May fix both tests with single fix!

---

## Commands for Quick Start

```bash
# Test current status
env XLEN=32 timeout 60s ./tools/run_official_tests.sh d

# Debug fdiv
env DEBUG_FPU=1 XLEN=32 timeout 30s \
  vvp sim/official-compliance/rv32ud-p-fdiv.vvp 2>&1 | tee fdiv_debug.log

# Debug fmadd
env DEBUG_FPU=1 XLEN=32 timeout 30s \
  vvp sim/official-compliance/rv32ud-p-fmadd.vvp 2>&1 | tee fmadd_debug.log

# Check test failure point
tail -50 fdiv_debug.log | grep -E "gp=|GP_WRITE|FAILED"
tail -50 fmadd_debug.log | grep -E "gp=|GP_WRITE|FAILED"

# Disassemble test to understand what's being tested
riscv64-unknown-elf-objdump -d tests/official-compliance/rv32ud-p-fdiv.elf | less
riscv64-unknown-elf-objdump -d tests/official-compliance/rv32ud-p-fmadd.elf | less
```

---

## Timeline Estimate

### Quick Win Scenario (2-4 hours)
- Simple bug in special case handling
- One-line fix
- Achieve 88%

### Standard Scenario (4-8 hours)
- Algorithm bug requiring careful analysis
- Multi-line fix with verification
- Achieve 88%, document second bug

### Complex Scenario (8+ hours)
- Deep algorithm issue requiring rewrite
- May need additional session
- Thorough testing and verification

---

## References

### RISC-V ISA Spec
- Chapter 11: "D" Standard Extension for Double-Precision Floating-Point
- Section 11.3: Double-Precision Floating-Point Computational Instructions

### IEEE 754-2008
- Section 5: Operations (for FMA requirements)
- Section 7: Default exception handling

### Project Files
- `rtl/core/fp_divider.v` - Division implementation
- `rtl/core/fp_fma.v` - Fused multiply-add implementation
- `rtl/core/fpu.v` - FPU top-level orchestration
- `rtl/core/fp_rounder.v` - Rounding logic (shared)
- `rtl/core/fp_normalizer.v` - Normalization (shared)

---

## Next Session Start

1. Run both tests with debug
2. Check failure points
3. Start with simpler bug
4. Fix, verify, document
5. If time permits, tackle second test
6. Push all changes

**Goal**: Leave with 88%+ RV32D compliance! 🎯
