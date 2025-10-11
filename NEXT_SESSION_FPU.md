# Next Session Guide - FPU Integration (Phase 8.3)

**Date**: 2025-10-10
**Session**: 18
**Goal**: Integrate all FP arithmetic units into top-level FPU module

---

## Current Status

### ✅ Completed (Session 17)
- All 10 FP arithmetic units implemented (~2,900 lines)
- IEEE 754-2008 compliant
- All rounding modes and exception flags supported
- Documentation complete (`PHASE8_PROGRESS.md`)

### 📁 Files Created (11 modules)
```
rtl/core/fp_register_file.v    (60 lines)   - 32 x FLEN registers
rtl/core/fp_adder.v             (380 lines)  - FADD/FSUB
rtl/core/fp_multiplier.v        (290 lines)  - FMUL
rtl/core/fp_divider.v           (350 lines)  - FDIV (SRT)
rtl/core/fp_sqrt.v              (270 lines)  - FSQRT
rtl/core/fp_fma.v               (410 lines)  - FMADD/FMSUB/FNMSUB/FNMADD
rtl/core/fp_sign.v              (45 lines)   - FSGNJ/FSGNJN/FSGNJX
rtl/core/fp_minmax.v            (100 lines)  - FMIN/FMAX
rtl/core/fp_compare.v           (115 lines)  - FEQ/FLT/FLE
rtl/core/fp_classify.v          (80 lines)   - FCLASS
rtl/core/fp_converter.v         (440 lines)  - INT↔FP conversions
```

---

## Next Session Tasks

### Stage 8.3: FPU Top-Level Integration

#### 1. Create `fpu.v` Module (~200 lines)

**Inputs:**
```verilog
module fpu #(
  parameter FLEN = 32,
  parameter XLEN = 32
) (
  input  wire              clk,
  input  wire              reset_n,

  // Control
  input  wire              start,
  input  wire [4:0]        operation,      // FP operation code
  input  wire [2:0]        rounding_mode,  // From fcsr.frm or instruction
  output wire              busy,
  output wire              done,

  // Operands (from FP register file)
  input  wire [FLEN-1:0]   operand_a,  // rs1
  input  wire [FLEN-1:0]   operand_b,  // rs2
  input  wire [FLEN-1:0]   operand_c,  // rs3 (for FMA)
  input  wire [XLEN-1:0]   int_operand, // For conversions

  // Results
  output wire [FLEN-1:0]   fp_result,
  output wire [XLEN-1:0]   int_result,   // For compare/classify/FP→INT

  // Exception flags (accumulated)
  output wire [4:0]        fflags        // {NV, DZ, OF, UF, NX}
);
```

**Operation Codes (suggestion):**
```verilog
localparam OP_FADD     = 5'd0;
localparam OP_FSUB     = 5'd1;
localparam OP_FMUL     = 5'd2;
localparam OP_FDIV     = 5'd3;
localparam OP_FSQRT    = 5'd4;
localparam OP_FMADD    = 5'd5;
localparam OP_FMSUB    = 5'd6;
localparam OP_FNMSUB   = 5'd7;
localparam OP_FNMADD   = 5'd8;
localparam OP_FSGNJ    = 5'd9;
localparam OP_FSGNJN   = 5'd10;
localparam OP_FSGNJX   = 5'd11;
localparam OP_FMIN     = 5'd12;
localparam OP_FMAX     = 5'd13;
localparam OP_FEQ      = 5'd14;
localparam OP_FLT      = 5'd15;
localparam OP_FLE      = 5'd16;
localparam OP_FCLASS   = 5'd17;
localparam OP_FCVT_*   = 5'd18-31; // Various conversions
```

**Implementation Steps:**

a) **Instantiate all 10 units:**
```verilog
fp_adder #(.FLEN(FLEN)) u_adder (...);
fp_multiplier #(.FLEN(FLEN)) u_multiplier (...);
fp_divider #(.FLEN(FLEN)) u_divider (...);
fp_sqrt #(.FLEN(FLEN)) u_sqrt (...);
fp_fma #(.FLEN(FLEN)) u_fma (...);
fp_sign #(.FLEN(FLEN)) u_sign (...);
fp_minmax #(.FLEN(FLEN)) u_minmax (...);
fp_compare #(.FLEN(FLEN)) u_compare (...);
fp_classify #(.FLEN(FLEN)) u_classify (...);
fp_converter #(.FLEN(FLEN), .XLEN(XLEN)) u_converter (...);
```

b) **Add operation decoder:**
- Decode `operation` input to select which unit to use
- Route operands to appropriate unit
- Set `start` signal for selected unit

c) **Add result multiplexer:**
- Select output from appropriate unit based on operation
- Route to either `fp_result` or `int_result`

d) **Add busy/done logic:**
- OR all busy signals from multi-cycle units
- Route done signal from active unit

e) **Add exception flag accumulation:**
- Collect flags from all units
- OR flags together (sticky behavior)
- Output as 5-bit `fflags`

#### 2. Testing Strategy

a) **Create simple testbench** (`tb/unit/tb_fpu.v`)
- Test each operation independently
- Verify result multiplexing works
- Check exception flag accumulation
- Test multi-cycle operation completion

b) **Test cases:**
- FADD: 1.0 + 2.0 = 3.0
- FMUL: 2.0 × 3.0 = 6.0
- FDIV: 6.0 / 2.0 = 3.0
- FSQRT: sqrt(4.0) = 2.0
- FMA: (2.0 × 3.0) + 1.0 = 7.0
- Compare: 1.0 < 2.0 = true
- Special values: NaN propagation, ±∞ handling

---

## After FPU Integration

### Stage 8.4: Pipeline Integration (Next priority)

**Files to modify:**
1. `rtl/core/idex_register.v` - Add FP ports
2. `rtl/core/exmem_register.v` - Add FP result path
3. `rtl/core/memwb_register.v` - Add FP writeback
4. `rtl/core/rv_core_pipelined.v` - Instantiate FPU and FP regfile

**Key additions:**
- FP register file instantiation
- FPU instantiation
- FP hazard detection (load-use, RAW)
- FP forwarding paths
- FPU busy → pipeline stall logic

---

## Design Decisions to Make

### 1. FPU Busy Behavior
**Option A**: Stall entire pipeline when FPU busy
- Simpler implementation
- May stall integer instructions unnecessarily

**Option B**: Separate FP scoreboard
- More complex
- Allows integer instructions to proceed
- Better performance

**Recommendation**: Start with Option A, upgrade to B later if needed.

### 2. FP Load/Store Path
**Question**: Where to handle FLW/FSW?
- **Option A**: Through FPU (add load/store ports)
- **Option B**: Direct path from memory to FP regfile
- **Recommendation**: Option B (simpler, consistent with integer loads)

### 3. Rounding Mode Source
- Instruction has 3-bit `rm` field
- If `rm == 3'b111` (DYN), use `fcsr.frm`
- Otherwise, use instruction `rm`
- **Implementation**: Add mux in control unit

---

## Key References

### Design Documents
- `docs/FD_EXTENSION_DESIGN.md` - Complete F/D specification
- `PHASE8_PROGRESS.md` - Current progress and statistics
- `PHASES.md` - Updated with Stage 8.2 completion

### Control Signals (Already Implemented)
See `rtl/core/control.v` for FP control signal generation:
- 19 FP ALU operations encoded
- Full decode for all 52 FP instructions
- Dynamic rounding mode detection

### Decoder (Already Implemented)
See `rtl/core/decoder.v` for FP instruction decoding:
- R4-type format support
- 7 FP opcodes detected
- FP-specific fields extracted (rs3, fp_rm, fp_fmt)

---

## Expected Session 18 Outcome

### Deliverables
1. ✅ `rtl/core/fpu.v` - Top-level FPU module (~200 lines)
2. ✅ `tb/unit/tb_fpu.v` - Basic FPU testbench
3. ✅ FPU compilation verification (no errors)
4. ✅ Basic smoke tests passing

### Metrics
- **Phase 8 Progress**: 60% → 70%
- **Total RTL lines**: ~3,300 → ~3,500
- **Ready for pipeline integration**: YES

---

## Build Commands

```bash
# Verify all FP modules compile
iverilog -g2012 rtl/core/fp_*.v -o /dev/null

# After FPU creation, test FPU module
iverilog -g2012 rtl/core/fp_*.v rtl/core/fpu.v tb/unit/tb_fpu.v -o sim/fpu_test
vvp sim/fpu_test

# View waveforms
gtkwave sim/fpu_test.vcd
```

---

## Notes

- All 10 units are **parameterized** for FLEN (32 or 64)
- All units handle **special values** (±0, ±∞, NaN, subnormals)
- Multi-cycle units have **state machines** (IDLE → COMPUTE → DONE)
- Combinational units are **1-cycle** (no state machine)
- Exception flags are **sticky** (OR accumulation)

---

**Session 17 Summary**: Implemented all 10 FP arithmetic units (~2,900 lines). Phase 8.2 complete (60%).

**Session 18 Goal**: Create FPU top-level integration module. Advance to 70%.
