# Critical Bugs - Quick Reference

**Purpose**: Quick reference for the most important bugs fixed during development
**For**: Understanding major technical challenges overcome

---

## Top 5 Critical Bugs

### 1. Bug #54: FMA Double-Precision GRS Bits ⭐⭐⭐
**The Final Boss - Achieved 100% Compliance**

- **Impact**: Blocked 100% RV32D compliance (4/9 tests failing)
- **Root Cause**: GRS bits extracted at wrong positions for 64-bit FMA
- **Fix**: Corrected extraction to bits [105:103] for double precision
- **Why Critical**: Last bug preventing 100% compliance across all extensions
- **Detailed Doc**: `archive/` (see BUG_FIXES_SUMMARY.md)

### 2. Bug #48: FCVT.W Address Calculation ⭐⭐⭐
**Memory Corruption via FP Conversion**

- **Impact**: Segmentation faults, memory corruption in real programs
- **Symptom**: Using float→int conversion result for load/store gave wrong addresses
- **Root Cause**: FCVT result not forwarded through pipeline
- **Fix**: Added FPU→INT forwarding path
- **Why Critical**: Made FP programs unreliable, real-world blocker

### 3. Bug #43: FD Mixed Precision ⭐⭐⭐
**Single/Double Precision Coexistence**

- **Impact**: Mixing F and D extension ops gave wrong results
- **Symptom**: Single-precision values corrupted when used in double-precision
- **Root Cause**: NaN-boxing not implemented (F extension requirement)
- **Fix**: Upper 32 bits set to 0xFFFFFFFF for SP values
- **Why Critical**: Fundamental to F/D extension interoperability

### 4. Bug #42: C.JAL PC+2 Issue ⭐⭐
**Compressed Instruction Return Address**

- **Impact**: Function calls/returns broken with RVC enabled
- **Symptom**: Return addresses off by 2 bytes
- **Root Cause**: C.JAL treated like JAL (4-byte) instead of compressed (2-byte)
- **Fix**: Use PC+2 for compressed jump-and-link
- **Why Critical**: Made RVC extension unusable

### 5. Bug #40: FSQRT Precision ⭐⭐
**Square Root Accuracy**

- **Impact**: Failed rv32uf-p-fsqrt compliance test
- **Symptom**: SQRT results off by 1-2 ULP
- **Root Cause**: Radix-4 algorithm insufficient precision
- **Fix**: Full-precision Radix-4 with proper remainder handling
- **Why Critical**: IEEE 754 compliance requirement (0.5 ULP max error)

---

## By Impact Category

### Compliance Blockers
1. **Bug #54** - FMA GRS bits (blocked RV32D 100%)
2. **Bug #40** - FSQRT precision (blocked RV32F compliance)
3. **Bug #24** - FCVT negative handling (blocked FCVT tests)

### Correctness Issues
1. **Bug #48** - FCVT address calculation (memory corruption)
2. **Bug #43** - F/D mixed precision (wrong results)
3. **Bug #22** - FP forwarding (pipeline hazards)

### Architectural Bugs
1. **Bug #42** - C.JAL PC+2 (RVC broken)
2. **Bug #6** - CSR-FPU hazard (race condition)
3. **Bug #38** - FMUL operand latching (non-deterministic)

---

## Bug Discovery Timeline

### Early Development (Phase 1-10)
- **Bug #6**: CSR-FPU hazard (supervisor mode integration)
- **Load-Store**: Misalignment handling

### FPU Integration (Phase 11-15)
- **Bugs #7-14**: FPU arithmetic (normalization, flags, special cases)
- **Bug #22**: FP-to-INT forwarding

### RVC Implementation (Phase 16)
- **Bugs #23, #29-31**: RVC decoding
- **Bug #42**: C.JAL PC increment

### FPU Refinement (Sessions 18-22)
- **Bugs #24-26**: FCVT conversion edge cases
- **Bugs #34-40**: SQRT implementation
- **Bug #38**: FMUL operand latching
- **Bug #43**: F/D mixed precision
- **Bug #44**: FMA alignment
- **Bug #48**: FCVT forwarding

### Final Push (Session 23)
- **Bugs #50-54**: Last RV32D issues
- **Bug #54**: FMA GRS bits (final bug!)

---

## Technical Insights

### Hardest to Debug
1. **Bug #54** (FMA GRS) - 3+ debugging sessions, subtle bit positioning
2. **Bug #40** (FSQRT) - Required algorithm change, precision analysis
3. **Bug #43** (F/D) - Spec interpretation (NaN-boxing)

### Most Impactful Fixes
1. **Bug #48** (FCVT address) - Enabled real-world FP programs
2. **Bug #22** (FP forwarding) - Major performance improvement
3. **Bug #42** (C.JAL) - Made RVC usable

### Quick Wins
1. **Bug #23** (RVC detection) - One-line fix
2. **Bug #39** (SQRT counter) - Initialization fix
3. **Bug #14** (FFLAGS) - Wire connection

---

## Prevention Checklist

When adding new instructions/features:

- [ ] Test special cases first (NaN, Inf, zero, denormals)
- [ ] Verify bit positions in spec (off-by-one errors common)
- [ ] Add forwarding paths for new data sources
- [ ] Check PC increment (2 vs 4 bytes for RVC)
- [ ] Implement proper rounding (GRS bits)
- [ ] Update stall/busy logic for multicycle ops
- [ ] Test mixed precision (if FPU)
- [ ] Run compliance tests early and often

---

## Quick Reference Table

| Bug # | Component | Impact | Sessions | Status |
|-------|-----------|--------|----------|--------|
| #54 | FMA GRS | 100% blocker | 3+ | ✅ FIXED |
| #48 | FCVT addr | Memory corruption | 2 | ✅ FIXED |
| #43 | F/D mixed | Wrong results | 2 | ✅ FIXED |
| #42 | C.JAL PC+2 | RVC broken | 1 | ✅ FIXED |
| #40 | FSQRT | Compliance | 3 | ✅ FIXED |
| #38 | FMUL latch | Non-deterministic | 1 | ✅ FIXED |
| #24 | FCVT neg | Conversion fail | 2 | ✅ FIXED |
| #22 | FP forward | Pipeline hazard | 1 | ✅ FIXED |
| #6 | CSR hazard | Race condition | 1 | ✅ FIXED |

---

## See Also

- **BUG_FIXES_SUMMARY.md** - Complete bug documentation (this directory)
- **KNOWN_ISSUES.md** - Current status (root directory)
- **docs/archive/** - Detailed bug fix documentation
- **PHASES.md** - Development history with bug context

---

**All Critical Bugs**: ✅ FIXED
**Status**: 100% Compliance (81/81 tests)
**Last Updated**: 2025-10-23
