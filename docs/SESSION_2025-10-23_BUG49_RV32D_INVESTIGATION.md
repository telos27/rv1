# Session 2025-10-23: Bug #49 - RV32D Investigation

## Summary
Investigated RV32D (double-precision floating-point) compliance test failures. Fixed MISA register to advertise all implemented extensions, but RV32D tests still failing. Identified likely issue in FLD instruction or double-precision FPU operations.

## Session Goals
- Run RV32D compliance tests
- Identify and fix failures
- Achieve RV32D compliance similar to RV32F (100%)

## Progress

### Initial State
- **RV32F**: 11/11 tests passing (100%) ✅
- **RV32D**: Not yet tested
- **RV32I/M/A/C**: All passing

### Issue #1: Missing Test Configuration
**Problem**: Test runner script (`tools/run_official_tests.sh`) didn't have a case for rv32ud tests.

**Analysis**:
- Script recognized rv32ud extension but didn't set config flag
- Tests ran without proper CONFIG_RV32IMAFD define

**Fix**:
```bash
# Added to run_official_tests.sh:
elif [[ "$test_name" == rv32ud* ]] || [[ "$test_name" == rv64ud* ]]; then
  # D extension test - needs M+A+F (D is enabled via FLEN=64 default)
  if [[ "$test_name" == rv32* ]]; then
    config_flag="-DCONFIG_RV32IMAF"
  else
    config_flag="-DCONFIG_RV64GC"
  fi
```

**Note**: D extension is enabled via `FLEN=64` default in `rtl/config/rv_config.vh:20`, not a separate CONFIG flag.

### Issue #2: MISA Register Missing Extensions ⚠️ **CRITICAL BUG**
**Problem**: MISA CSR only advertised I extension, missing M, A, F, D.

**Discovery**:
```verilog
// BEFORE (rtl/core/csr_file.v:136):
wire [31:0] misa = {2'b01, 4'b0, 26'b00000000000000000100000000};
//                                    ^^^^^^^^^^^^^^^^^^^^^^^^
//                                    Only bit 8 (I) set = 0x100
```

**Impact**:
- Compliance tests likely check MISA to verify extension support
- Missing extension bits could cause tests to skip or fail early

**Fix**:
```verilog
// AFTER:
wire [31:0] misa = {2'b01, 4'b0, 26'b00000000000001000100101001};
//                                    ^^^^^^^^^^^^^^^^^^^^^^^^
//                                    I(8), M(12), A(0), F(5), D(3) = 0x1129
```

**Extension Bits**:
| Bit | Extension | Description |
|-----|-----------|-------------|
| 0   | A         | Atomic operations |
| 3   | D         | Double-precision FP |
| 5   | F         | Single-precision FP |
| 8   | I         | Base integer ISA |
| 12  | M         | Multiply/Divide |

### Test Results After Fixes

**RV32F** (verification):
```
Total:  11
Passed: 11
Failed: 0
Pass rate: 100% ✅
```

**RV32D** (current state):
```
Total:  9
Passed: 0
Failed: 9
Pass rate: 0% ❌
```

**Failed tests**:
- rv32ud-p-fadd
- rv32ud-p-fclass
- rv32ud-p-fcmp
- rv32ud-p-fcvt (TIMEOUT)
- rv32ud-p-fcvt_w
- rv32ud-p-fdiv
- rv32ud-p-fmadd
- rv32ud-p-fmin
- rv32ud-p-ldst

## Detailed Failure Analysis

### Symptom Pattern
All tests fail at **test #5** with:
```
Failed at test number: 5
Final PC: 0x8000000c
Cycles: 106 (varies by test)
x3 (gp) = 0x00000005
```

### Key Observations

1. **Consistent Failure Point**: All tests fail at test #5, suggesting a common issue

2. **Execution Reaches Test Code**: Tests execute 77-86 instructions before failing
   - Not an immediate failure
   - Test framework setup completes successfully

3. **Test Framework Check**: Initial instructions check for environment:
   ```
   @0x0000: JAL x0, 80       # Jump to register init
   @0x0004: CSRRS x30, mcause, x0
   @0x0008: ADDI x31, x0, 8
   @0x000c: BEQ x30, x31, 48  # Check if mcause == 8
   ```

4. **FLD Instructions Present**: Tests contain FLD (funct3=011) instructions starting at 0x01a4
   ```
   @0x01a4: FLD f10, 0(x10)  [0x00053507]
   @0x01c0: FLD f10, 0(x10)  [0x00053507]
   ...
   ```

5. **Single vs Double Precision Comparison**:
   - RV32F fclass: 100% passing
   - RV32D fclass: Failing at test #5
   - Both use same FPU, differ only in:
     - Load instruction: FLW (funct3=010) vs FLD (funct3=011)
     - Format bit: funct7[0]=0 (single) vs funct7[0]=1 (double)

### Hypothesis: FLD or Double-Precision FPU Issue

**Most Likely Root Causes** (in order of probability):

1. **FLD (64-bit FP load) not working correctly**
   - Data memory supports 64-bit loads (funct3=011) ✅ (verified in code)
   - Pipeline may not be passing 64-bit data correctly
   - Possible width mismatch in pipeline registers

2. **Double-precision FPU operations producing incorrect results**
   - Format bit (funct7[0]) controls single/double precision
   - FPU modules may have bugs specific to double-precision
   - NaN-boxing or special case handling differences

3. **FP register file initialization**
   - 64-bit FP registers may not be initialized correctly
   - Test data may not be loading into FP registers

## Architecture Verification

### Data Memory (64-bit support)
✅ **Verified**: `rtl/memory/data_memory.v` correctly implements 64-bit loads/stores
```verilog
module data_memory #(
  parameter FLEN = `FLEN,     // 64 by default
  ...
) (
  input  wire [63:0] write_data,  // 64-bit write data
  output reg  [63:0] read_data,   // 64-bit read data
  ...
);

// FLD (funct3=011) case:
3'b011: begin
  read_data = dword_data;  // Full 64-bit read
end
```

### FP Register File (64-bit support)
✅ **Verified**: `rtl/core/fp_register_file.v` parameterized with FLEN
```verilog
module fp_register_file #(
  parameter FLEN = 32  // Set to 64 for D extension
) (
  output wire [FLEN-1:0] rs1_data,
  output wire [FLEN-1:0] rs2_data,
  output wire [FLEN-1:0] rs3_data,
  ...
);
```

### FPU (format bit support)
✅ **Verified**: `rtl/core/fpu.v` extracts format bit
```verilog
// Extract format from funct7[1:0]: 00=single, 01=double
wire fmt = funct7[0];  // Bit 0 distinguishes single (0) from double (1)
```

All FPU sub-modules receive `fmt` signal and should handle both formats.

### Configuration
✅ **Verified**: FLEN defaults to 64
```verilog
// rtl/config/rv_config.vh:20
`ifndef FLEN
  `define FLEN 64  // Default to 64 to support both F and D extensions
`endif
```

## Next Steps for Bug #49 Resolution

### Immediate Actions (Priority 1)
1. **Create minimal FLD test**
   - Write assembly: Load 64-bit constant, verify in register
   - Isolate FLD from FPU operations
   - Check if data is correctly loaded into FP registers

2. **Add FP register file debugging**
   - Modify testbench to dump FP registers (f0-f31)
   - Compare FLW vs FLD results
   - Verify 64-bit values are stored correctly

3. **Test double-precision FCLASS in isolation**
   - Load known 64-bit FP value via FLD
   - Execute FCLASS.D
   - Compare result with expected classification

### Investigation Tools (Priority 2)
4. **Waveform analysis**
   - Open `sim/waves/core_pipelined.vcd`
   - Examine FLD instruction execution
   - Check data path: Memory → Pipeline → FP RegFile

5. **Add targeted debug output**
   - Enable DEBUG_FPU for double-precision operations
   - Add prints for FLD instruction decode
   - Monitor 64-bit data flow through pipeline

### Systematic Testing (Priority 3)
6. **Compare RV32F vs RV32D test binaries**
   - Disassemble both fclass tests
   - Identify structural differences
   - Check if D tests have different initialization

7. **Test individual D extension instructions**
   - FADD.D, FSUB.D, FMUL.D
   - FCVT.D.W, FCVT.W.D
   - Isolate which operations work and which don't

## Code Changes This Session

### Modified Files
1. **rtl/core/csr_file.v** (lines 131-141)
   - MISA register: 0x100 → 0x1129
   - Added M, A, F, D extension bits

2. **tools/run_official_tests.sh** (lines 125-131)
   - Added rv32ud/rv64ud test configuration case

### Git Commit
```
commit 614ecc4
Bug #49: MISA Register - Fixed extension advertisement for M/A/F/D
```

## Lessons Learned

1. **MISA is critical infrastructure**: Many test suites check MISA to verify ISA support
2. **Test configuration matters**: Missing config flags can cause silent failures
3. **RV32D requires FLEN=64**: Unlike RV64D which naturally has 64-bit registers
4. **FPU format bit**: Single mechanism (funct7[0]) controls single/double precision

## References

- RISC-V Privileged Spec v1.12, Section 3.1.1 (MISA Register)
- RISC-V ISA Spec v2.2, Chapter 11 (D Extension)
- Project: PHASES.md (current status), ARCHITECTURE.md (FPU design)

---

**Session Status**: MISA bug fixed, RV32D infrastructure in place, ready for detailed debugging.

**Next Session Goal**: Debug and fix RV32D test failures to achieve 100% compliance.
