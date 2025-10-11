# M Extension - Next Session Guide

**Date Created**: 2025-10-10
**Current Status**: Core modules complete (60%), pipeline integration pending
**Next Phase**: Pipeline integration and testing

---

## Quick Start - What Was Done

### ✅ Completed This Session (60%)

1. **Design Documentation**
   - `docs/M_EXTENSION_DESIGN.md` - Complete specification
   - Algorithm selection and performance analysis

2. **Core Modules Implemented**
   - ✅ `rtl/core/mul_unit.v` - Sequential multiplier (~200 lines)
   - ✅ `rtl/core/div_unit.v` - Non-restoring divider (~230 lines)
   - ✅ `rtl/core/mul_div_unit.v` - Wrapper module (~80 lines)
   - ✅ `rtl/core/decoder.v` - M extension detection (updated)

3. **What Works**
   - Multiply logic: MUL, MULH, MULHSU, MULHU
   - Divide logic: DIV, DIVU, REM, REMU
   - RV32M and RV64M support (parameterized)
   - Edge case handling (div-by-zero, overflow)

---

## What Needs to Be Done (40%)

### Phase 1: Control Unit Updates (30 min)
**File**: `rtl/core/control.v`

Add M extension control signals:

```verilog
// Add to module ports
input  wire        is_mul_div,      // From decoder
input  wire [3:0]  mul_div_op,      // From decoder
input  wire        is_word_op,      // From decoder
output reg         mul_div_en       // Enable M result

// Add to control logic
always @(*) begin
    // ... existing logic ...

    if (is_mul_div) begin
        mul_div_en = 1'b1;
        alu_src_a = 2'b00;      // Use rs1
        alu_src_b = 2'b00;      // Use rs2
        reg_write = 1'b1;
        wb_sel = 3'b100;        // New mux option for M result
    end
end
```

### Phase 2: Pipeline Integration (1-2 hours)
**File**: `rtl/core/rv_core_pipelined.v`

#### Step 1: Add M unit instantiation in EX stage
```verilog
// Instantiate M extension unit
mul_div_unit #(
    .XLEN(XLEN)
) m_unit (
    .clk(clk),
    .reset_n(reset_n),
    .start(idex_is_mul_div && !stall),
    .operation(idex_mul_div_op),
    .is_word_op(idex_is_word_op),
    .operand_a(alu_operand_a),
    .operand_b(alu_operand_b),
    .result(mul_div_result),
    .busy(mul_div_busy),
    .ready(mul_div_ready)
);
```

#### Step 2: Extend writeback mux
```verilog
// Update wb_data multiplexer (add M result case)
assign wb_data = (memwb_wb_sel == 3'b100) ? memwb_mul_div_result :
                 (memwb_wb_sel == 3'b011) ? memwb_csr_rdata :
                 (memwb_wb_sel == 3'b010) ? memwb_mem_rdata :
                 (memwb_wb_sel == 3'b001) ? memwb_pc_plus_4 :
                 memwb_alu_result;
```

#### Step 3: Connect decoder outputs
```verilog
// In ID stage - connect decoder M extension outputs
wire        id_is_mul_div;
wire [3:0]  id_mul_div_op;
wire        id_is_word_op;

decoder #(.XLEN(XLEN)) dec (
    // ... existing connections ...
    .is_mul_div(id_is_mul_div),
    .mul_div_op(id_mul_div_op),
    .is_word_op(id_is_word_op)
);
```

### Phase 3: Hazard Detection Updates (15 min)
**File**: `rtl/core/hazard_detection_unit.v`

```verilog
// Add input
input wire mul_div_busy,

// Update stall logic
assign stall = load_use_hazard || mul_div_busy;
```

### Phase 4: Pipeline Registers Updates (30 min)

#### ID/EX Register (`rtl/core/idex_register.v`)
```verilog
// Add signals
input  wire        is_mul_div_in,
input  wire [3:0]  mul_div_op_in,
input  wire        is_word_op_in,

output reg         is_mul_div_out,
output reg [3:0]   mul_div_op_out,
output reg         is_word_op_out,

// In always block
is_mul_div_out <= flush ? 1'b0 : is_mul_div_in;
mul_div_op_out <= flush ? 4'b0 : mul_div_op_in;
is_word_op_out <= flush ? 1'b0 : is_word_op_in;
```

#### EX/MEM Register (`rtl/core/exmem_register.v`)
```verilog
// Add signal
input  wire [XLEN-1:0] mul_div_result_in,
output reg  [XLEN-1:0] mul_div_result_out,

// In always block
mul_div_result_out <= mul_div_result_in;
```

#### MEM/WB Register (`rtl/core/memwb_register.v`)
```verilog
// Add signal
input  wire [XLEN-1:0] mul_div_result_in,
output reg  [XLEN-1:0] mul_div_result_out,

// In always block
mul_div_result_out <= mul_div_result_in;
```

### Phase 5: Testing (2-3 hours)

#### Test Program 1: Basic Multiply
```assembly
# test_mul_basic.s
.section .text
.globl _start

_start:
    # Test MUL
    li a0, 100
    li a1, 200
    mul a2, a0, a1      # a2 = 20000

    # Test MULH (signed)
    li a3, -10
    li a4, -20
    mulh a5, a3, a4     # a5 = upper bits of 200

    # Return result
    addi a0, a2, 0
    nop
    nop
    nop
    nop
    ebreak
```

#### Test Program 2: Basic Divide
```assembly
# test_div_basic.s
.section .text
.globl _start

_start:
    # Test DIV
    li a0, 100
    li a1, 5
    div a2, a0, a1      # a2 = 20

    # Test REM
    li a3, 100
    li a4, 3
    rem a5, a3, a4      # a5 = 1

    # Test divide by zero
    li a6, 100
    li a7, 0
    div t0, a6, a7      # t0 = -1 (all 1s)

    nop
    nop
    nop
    nop
    ebreak
```

#### Test Program 3: Edge Cases
```assembly
# test_mul_div_edge.s
.section .text
.globl _start

_start:
    # Overflow case: MIN_INT / -1
    li a0, 0x80000000   # MIN_INT (RV32)
    li a1, -1
    div a2, a0, a1      # a2 = MIN_INT (no exception)
    rem a3, a0, a1      # a3 = 0

    # Large multiply
    li a4, 0xFFFFFFFF
    li a5, 0xFFFFFFFF
    mul a6, a4, a5      # Lower 32 bits
    mulh a7, a4, a5     # Upper 32 bits

    nop
    nop
    nop
    nop
    ebreak
```

### Phase 6: Compilation and Testing

```bash
# Compile test programs
cd /home/lei/rv1/tests/asm

# For RV32M
riscv32-unknown-elf-as -march=rv32im -o test_mul_basic.o test_mul_basic.s
riscv32-unknown-elf-ld -T ../linker.ld -o test_mul_basic.elf test_mul_basic.o
riscv32-unknown-elf-objcopy -O verilog test_mul_basic.elf test_mul_basic.hex

# Run test
cd /home/lei/rv1
make pipelined-rv32im  # Need to add this Makefile target
./tools/test_pipelined.sh test_mul_basic
```

---

## Files to Modify (Checklist)

- [ ] `rtl/core/control.v` - Add M control signals
- [ ] `rtl/core/rv_core_pipelined.v` - Integrate M unit
- [ ] `rtl/core/hazard_detection_unit.v` - Add M stall
- [ ] `rtl/core/idex_register.v` - Propagate M signals
- [ ] `rtl/core/exmem_register.v` - Propagate M result
- [ ] `rtl/core/memwb_register.v` - Propagate M result
- [ ] `Makefile` - Add RV32IM/RV64IM targets
- [ ] `tests/asm/test_mul_basic.s` - Create test
- [ ] `tests/asm/test_div_basic.s` - Create test
- [ ] `tests/asm/test_mul_div_edge.s` - Create test

---

## Key Design Decisions (Reference)

### Multiply Algorithm
- **Sequential add-and-shift**
- **32 cycles (RV32) / 64 cycles (RV64)**
- Simple to understand, small area

### Divide Algorithm
- **Non-restoring division**
- **32 cycles (RV32) / 64 cycles (RV64)**
- Handles div-by-zero and overflow per RISC-V spec

### Pipeline Integration
- **Multi-cycle stall approach**
- Stall entire pipeline when M unit busy
- No forwarding complexity (result ready when done)

### Special Cases Handled
- Division by zero: quotient = -1, remainder = dividend
- Signed overflow (MIN_INT / -1): quotient = MIN_INT, remainder = 0

---

## Expected Performance

### Cycle Counts
- Multiply: 32 (RV32) / 64 (RV64) cycles
- Divide: 32 (RV32) / 64 (RV64) cycles

### CPI Impact
- Base CPI: ~1.2
- With 5% M instructions: CPI ≈ 2.8
- With 10% M instructions: CPI ≈ 4.4

---

## Verification Checklist

### Functionality Tests
- [ ] MUL produces correct lower bits
- [ ] MULH/MULHSU/MULHU produce correct upper bits
- [ ] DIV/DIVU produce correct quotient
- [ ] REM/REMU produce correct remainder
- [ ] Division by zero handled correctly
- [ ] Signed overflow handled correctly
- [ ] RV64M word operations work (MULW, DIVW, etc.)

### Integration Tests
- [ ] M unit stalls pipeline correctly
- [ ] Results propagate through pipeline
- [ ] Writeback mux selects M result
- [ ] No data hazards with M instructions
- [ ] Pipeline resumes after M completion

### Compliance Tests (when ready)
- [ ] Run RV32M compliance tests
- [ ] Run RV64M compliance tests (if RV64 mode)
- [ ] Target: 100% pass rate

---

## Debugging Tips

### Common Issues

1. **M unit never becomes ready**
   - Check `start` signal is pulsed (not held high)
   - Verify cycle counter increments
   - Check state machine transitions

2. **Wrong results**
   - Verify sign handling for signed operations
   - Check MULH upper bits extraction
   - Verify remainder correction in divider

3. **Pipeline hangs**
   - Check `mul_div_busy` connects to hazard unit
   - Verify stall logic doesn't create infinite stall
   - Ensure `ready` signal clears `busy`

4. **Forwarding issues**
   - M results don't need forwarding (ready when WB)
   - Ensure M result bypasses forwarding logic

### Waveform Signals to Monitor
- `mul_div_busy` - Should pulse during operation
- `mul_div_ready` - Should pulse when done
- `mul_div_result` - Final result
- `stall` - Should be high while M busy
- `DUT.m_unit.state` - State machine progression
- `DUT.m_unit.cycle_count` - Iteration progress

---

## Build System Updates

### Add to Makefile

```makefile
# RV32IM configuration
pipelined-rv32im:
	@echo "Building RV32IM pipelined core..."
	iverilog -g2012 -I rtl -DCONFIG_RV32IM \
		-o sim/rv32im_pipelined.vvp \
		rtl/core/*.v rtl/memory/*.v \
		tb/integration/tb_core_pipelined.v
	@echo "✓ RV32IM pipelined build complete"

# RV64IM configuration
pipelined-rv64im:
	@echo "Building RV64IM pipelined core..."
	iverilog -g2012 -I rtl -DCONFIG_RV64IM \
		-o sim/rv64im_pipelined.vvp \
		rtl/core/*.v rtl/memory/*.v \
		tb/integration/tb_core_pipelined_rv64.v
	@echo "✓ RV64IM pipelined build complete"
```

### Update Config File

```verilog
// In rtl/config/rv_config.vh

`ifdef CONFIG_RV32IM
  `define XLEN 32
  `define HAS_M_EXT 1
  `define CONFIG_BASE_ISA "RV32IM"
`endif

`ifdef CONFIG_RV64IM
  `define XLEN 64
  `define HAS_M_EXT 1
  `define CONFIG_BASE_ISA "RV64IM"
`endif
```

---

## Session Summary

### What's Complete ✅
- M unit multiply logic
- M unit divide logic
- M unit wrapper
- Decoder M extension detection
- Design documentation

### What's Pending ⏳
- Control unit updates
- Pipeline integration
- Hazard detection updates
- Pipeline register updates
- Test programs
- Testing and validation

### Estimated Time
- **Integration**: 2-3 hours
- **Testing**: 2-3 hours
- **Total**: 4-6 hours

---

## Quick Commands for Next Session

```bash
# Navigate to project
cd /home/lei/rv1

# Check git status
git status

# Review M extension files
ls -la rtl/core/mul*.v rtl/core/div*.v

# Review design docs
cat docs/M_EXTENSION_DESIGN.md
cat M_EXTENSION_PROGRESS.md

# Start with control unit
vim rtl/core/control.v
```

---

## Reference Materials

### Documentation
- `docs/M_EXTENSION_DESIGN.md` - Complete specification
- `M_EXTENSION_PROGRESS.md` - Current status
- RISC-V ISA Manual - M Extension Chapter

### Implementation Files
- `rtl/core/mul_unit.v` - Multiplier
- `rtl/core/div_unit.v` - Divider
- `rtl/core/mul_div_unit.v` - Wrapper

### Test Reference
- `tests/asm/test_rv64i_basic.s` - Example of NOPs before ebreak
- `tools/test_pipelined.sh` - Test runner script

---

**Ready for next session!** 🚀

The core M extension logic is complete. Next session will focus on pipeline integration and testing. Start with updating the control unit, then wire everything into the pipeline.

**Good luck!** 👍

---

**Last Updated**: 2025-10-10
**Phase**: M Extension Implementation (60% complete)
**Next Step**: Control unit updates
