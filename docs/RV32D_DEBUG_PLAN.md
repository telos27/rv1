# RV32D Systematic Debugging Plan
## Session 2025-10-23 (Session 17)

## Current Status
- **RV32F**: 11/11 tests passing (100%) ✅
- **RV32D**: 0/9 tests passing (0%) ❌
- **All RV32D tests fail at test #5** (consistent failure point)
- **Infrastructure**: MISA fixed, test runner configured

## Systematic Debug Strategy

### Phase 1: Isolate the Problem (Divide & Conquer)

#### Step 1.1: Test FLD (64-bit FP Load) in Isolation
**Goal**: Verify FLD can load 64-bit values into FP registers correctly

**Method**:
```assembly
# Minimal FLD test
.data
test_data: .dword 0x3FF0000000000000  # 1.0 in double-precision

.text
  la   x10, test_data
  fld  f10, 0(x10)      # Load double into f10
  fmv.x.d x11, f10       # Move to integer register to inspect
  # Check if x11 == 0x3FF0000000000000
```

**Expected Failure Modes**:
- FLD not decoded correctly → Wrong instruction executed
- FLD loads wrong size → Only 32 bits loaded
- FLD loads garbage → Data path broken

#### Step 1.2: Test FCLASS.D (Simplest D Instruction)
**Goal**: Verify FPU can process double-precision instructions

**Method**:
```assembly
# Test FCLASS.D with known input
.data
pos_inf: .dword 0x7FF0000000000000  # +Infinity

.text
  la   x10, pos_inf
  fld  f10, 0(x10)
  fclass.d x11, f10     # Should return 0x080 (positive infinity)
  # Check if x11 == 0x080
```

**Expected Results**:
- FCLASS.D correct → FPU double-precision classify working
- FCLASS.D wrong → FPU format handling broken

#### Step 1.3: Test FADD.D (Double-Precision Arithmetic)
**Goal**: Verify FPU arithmetic operations work for double-precision

**Method**:
```assembly
# Test FADD.D: 1.0 + 1.0 = 2.0
.data
one: .dword 0x3FF0000000000000      # 1.0
two: .dword 0x4000000000000000      # 2.0

.text
  la   x10, one
  fld  f10, 0(x10)
  fld  f11, 0(x10)
  fadd.d f12, f10, f11  # 1.0 + 1.0 = 2.0
  fmv.x.d x11, f12
  # Check if x11 == 0x4000000000000000
```

### Phase 2: Narrow Down to Specific Module

#### Test Matrix
| Test | FLD | FPU fmt | Module | Expected Outcome |
|------|-----|---------|--------|------------------|
| 1.1  | Yes | N/A     | data_memory, pipeline | Identifies load issues |
| 1.2  | Yes | Yes     | fp_classify | Identifies FPU input issues |
| 1.3  | Yes | Yes     | fp_adder | Identifies arithmetic issues |

#### Decision Tree
```
FLD Test Fails?
├─ YES → Problem in load/store path
│         Check: data_memory.v, pipeline registers, FP register file
│
└─ NO → FLD works
        │
        FCLASS.D Test Fails?
        ├─ YES → Problem in FPU format handling
        │         Check: fpu.v operand extraction, fp_classify.v format bit
        │
        └─ NO → FCLASS.D works
                │
                FADD.D Test Fails?
                ├─ YES → Problem in FPU arithmetic
                │         Check: fp_adder.v UNPACK/PACK stages
                │
                └─ NO → All basic ops work, issue is complex interaction

```

### Phase 3: Targeted Inspection (Based on Phase 2 Results)

#### If FLD Fails → Inspect Load Path
1. **data_memory.v**: Verify funct3=011 (FLD) case returns 64 bits
2. **Pipeline registers**: Check MEM→WB carries 64-bit data
3. **fp_register_file.v**: Verify write port width = FLEN (should be 64)
4. **Forwarding**: Check FP load forwarding handles 64-bit values

**Code Locations to Check**:
```
rtl/memory/data_memory.v:124-129      (FLD case)
rtl/core/memwb_register.v:??          (fp_mem_data width)
rtl/core/fp_register_file.v:35-42     (register write)
rtl/core/forwarding_unit.v:??         (FP forwarding)
```

#### If FCLASS.D Fails → Inspect Format Handling
1. **fpu.v**: Verify format bit extraction (funct7[0])
2. **fp_classify.v**: Check if format bit used correctly
3. **Operand extraction**: Verify exponent/mantissa extraction for double

**Code Locations to Check**:
```
rtl/core/fpu.v:68-70                  (format bit extraction)
rtl/core/fpu.v:85-111                 (operand extraction - CRITICAL)
rtl/core/fp_classify.v:??             (format-specific logic)
```

#### If FADD.D Fails → Inspect Arithmetic Modules
1. **fp_adder.v**: UNPACK stage format-aware extraction
2. **fp_adder.v**: PACK stage format-aware result assembly
3. **Common bug pattern**: Single-precision assumptions hardcoded

**Code Locations to Check**:
```
rtl/core/fp_adder.v:UNPACK            (operand extraction)
rtl/core/fp_adder.v:PACK              (result assembly)
rtl/core/fp_adder.v:GRS bits          (guard/round/sticky)
```

### Phase 4: Hypothesis Testing

#### Hypothesis 1: FLD Only Loads 32 Bits
**Test**: Create FLD test with distinctive bit pattern
```assembly
.data
test: .dword 0xDEADBEEFCAFEBABE

.text
  la x10, test
  fld f10, 0(x10)
  fmv.x.d x11, f10
  # Expect x11 = 0xDEADBEEFCAFEBABE
  # If x11 = 0xXXXXXXXXCAFEBABE or 0xXXXXXXXXDEADBEEF → only 32 bits loaded
```

#### Hypothesis 2: FPU Format Bit Ignored
**Test**: Compare FCLASS.S vs FCLASS.D on same bit pattern
```assembly
# Load 0x7FC00000 (single-precision NaN)
li   x10, 0x7FC00000
fmv.w.x f10, x10
fclass.s x11, f10    # Should return 0x100 (quiet NaN)

# Load 0x7FF8000000000000 (double-precision NaN)
la   x10, dnan
fld  f11, 0(x10)
fclass.d x12, f11    # Should return 0x100 (quiet NaN)
```

#### Hypothesis 3: Pipeline Width Mismatch (RV32 Issue)
**Test**: Check if RV32 with FLEN=64 has register width issues
```
XLEN=32 but FLEN=64 → Some pipeline registers may be 32-bit only
Check: IDEX, EXMEM, MEMWB for FP data paths
```

### Phase 5: Execution Plan

1. **Run official test first** to confirm failure mode hasn't changed
   ```bash
   env XLEN=32 timeout 5s ./tools/run_official_tests.sh rv32ud-p-fclass
   ```

2. **Create minimal test** (Step 1.1: FLD test)
   ```bash
   # Create tests/asm/test_fld_minimal.s
   # Assemble and run
   ```

3. **Add debug instrumentation** to testbench
   ```verilog
   // In tb/tb_core_pipelined.v
   always @(posedge clk) begin
     if (memwb_fp_reg_write) begin
       $display("[DEBUG] FP Write: f%0d = 0x%016x", memwb_rd, memwb_fp_wb_data);
     end
   end
   ```

4. **Iterate based on results**
   - If FLD test passes → Move to FCLASS.D test
   - If FLD test fails → Inspect data_memory.v, pipeline, FP regfile

## Key Debugging Questions

1. **Does FLD load 64 bits or 32 bits?**
   - Check: Memory read, pipeline carry, FP register write

2. **Does the FPU receive the format bit correctly?**
   - Check: funct7[0] extraction in fpu.v:68-70

3. **Are FPU modules format-aware?**
   - Check: Each FPU module (11 total) for format bit usage

4. **Is there an RV32+FLEN=64 interaction bug?**
   - Check: Pipeline register widths, alignment issues

## Success Criteria

- **Minimal**: At least 1 RV32D test passing (demonstrates path works)
- **Good**: 5+ RV32D tests passing (demonstrates most ops work)
- **Excellent**: 9/9 RV32D tests passing (100% compliance)

## Tools Available

1. **Waveform**: `gtkwave sim/waves/core_pipelined.vcd`
2. **Objdump**: `riscv64-unknown-elf-objdump -d test.elf`
3. **Custom tests**: `tests/asm/` directory
4. **Debug flags**: `DEBUG_FPU=1`, `DEBUG_MEM_FCVT=1`

## Expected Time
- Phase 1-2 (Isolation): 30-60 minutes
- Phase 3 (Inspection): 30-60 minutes
- Phase 4-5 (Fix): Varies by complexity (1-4 hours)

---

**Philosophy**: "Measure twice, cut once" - Spend time understanding the problem before attempting fixes.
