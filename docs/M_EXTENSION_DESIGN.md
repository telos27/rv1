# M Extension Design Document

**Date**: 2025-10-10
**Phase**: Phase 6 - M Extension Implementation
**Target**: RV32M and RV64M support

---

## Overview

The M extension adds integer multiplication and division instructions to the RISC-V ISA. This document outlines the design and implementation strategy for adding M extension support to the RV1 pipelined processor.

---

## M Extension Instructions

### RV32M Instructions (8 total)

| Instruction | Format | Opcode | Funct3 | Funct7 | Description |
|-------------|--------|--------|--------|--------|-------------|
| **MUL** | R-type | 0110011 | 000 | 0000001 | Multiply (lower 32/64 bits) |
| **MULH** | R-type | 0110011 | 001 | 0000001 | Multiply high (signed × signed) |
| **MULHSU** | R-type | 0110011 | 010 | 0000001 | Multiply high (signed × unsigned) |
| **MULHU** | R-type | 0110011 | 011 | 0000001 | Multiply high (unsigned × unsigned) |
| **DIV** | R-type | 0110011 | 100 | 0000001 | Divide (signed) |
| **DIVU** | R-type | 0110011 | 101 | 0000001 | Divide (unsigned) |
| **REM** | R-type | 0110011 | 110 | 0000001 | Remainder (signed) |
| **REMU** | R-type | 0110011 | 111 | 0000001 | Remainder (unsigned) |

### RV64M Additional Instructions (5 total)

| Instruction | Format | Opcode | Funct3 | Funct7 | Description |
|-------------|--------|--------|--------|--------|-------------|
| **MULW** | R-type | 0111011 | 000 | 0000001 | Multiply word (32-bit, sign-extend) |
| **DIVW** | R-type | 0111011 | 100 | 0000001 | Divide word (32-bit, sign-extend) |
| **DIVUW** | R-type | 0111011 | 101 | 0000001 | Divide word unsigned |
| **REMW** | R-type | 0111011 | 110 | 0000001 | Remainder word (signed) |
| **REMUW** | R-type | 0111011 | 111 | 0000001 | Remainder word (unsigned) |

**Key Identifier**: All M extension instructions have `funct7 = 0000001`

---

## Design Decisions

### 1. Multiplier Design

**Options**:
- **Combinational** - Fast (1 cycle) but large area
- **Iterative (Booth)** - Slower (32/64 cycles) but smaller area
- **Radix-4 Booth** - Balanced (16/32 cycles), moderate area

**Choice**: **Iterative Sequential Multiplier** (initial implementation)

**Rationale**:
- Educational clarity (easier to understand)
- Reasonable performance (32 cycles for RV32, 64 for RV64)
- Small area footprint
- Can be upgraded to Booth later

**Algorithm**:
```
result = 0
for i = 0 to XLEN-1:
    if multiplier[i] == 1:
        result += multiplicand << i
```

### 2. Divider Design

**Options**:
- **Restoring** - Simple but slower
- **Non-restoring** - Faster, more complex
- **SRT** - Very fast, very complex

**Choice**: **Non-Restoring Divider**

**Rationale**:
- Good balance of speed and complexity
- 32/64 cycles for completion
- Standard implementation in many processors
- More efficient than restoring division

**Algorithm**:
```
remainder = dividend
for i = XLEN-1 down to 0:
    remainder = remainder << 1
    if remainder >= 0:
        remainder -= divisor
    else:
        remainder += divisor
    quotient[i] = (remainder >= 0) ? 1 : 0
```

### 3. Pipeline Integration

**Challenge**: M instructions take 32-64 cycles, but pipeline expects 1 cycle

**Solutions Considered**:
1. **Stall pipeline** - Simple, wastes cycles
2. **Separate execution unit** - Complex, allows out-of-order
3. **Multi-cycle with stall** - Balanced approach

**Choice**: **Multi-cycle execution with pipeline stall**

**Implementation**:
- Add `mul_div_busy` signal to hazard detection unit
- Stall entire pipeline while M instruction executes
- No forwarding needed (result available when done)
- Simple state machine in M unit

---

## Architecture

### Module Structure

```
rv_mul_div_unit
├── Inputs
│   ├── clk, reset_n
│   ├── start             # Trigger computation
│   ├── operation[3:0]    # Which M instruction
│   ├── operand_a[XLEN-1:0]
│   ├── operand_b[XLEN-1:0]
│   └── is_word_op        # RV64W flag
├── Outputs
│   ├── result[XLEN-1:0]
│   ├── ready             # Computation complete
│   └── busy              # Currently computing
└── Internal
    ├── State machine (IDLE, MUL, DIV, DONE)
    ├── Cycle counter
    ├── Partial products/quotients
    └── Sign handling logic
```

### Operation Encoding

```verilog
// M extension operations
localparam OP_MUL    = 4'b0000;  // Multiply lower
localparam OP_MULH   = 4'b0001;  // Multiply high (signed×signed)
localparam OP_MULHSU = 4'b0010;  // Multiply high (signed×unsigned)
localparam OP_MULHU  = 4'b0011;  // Multiply high (unsigned×unsigned)
localparam OP_DIV    = 4'b0100;  // Divide (signed)
localparam OP_DIVU   = 4'b0101;  // Divide (unsigned)
localparam OP_REM    = 4'b0110;  // Remainder (signed)
localparam OP_REMU   = 4'b0111;  // Remainder (unsigned)
```

### Pipeline Integration Points

**Decode Stage (ID)**:
- Detect M extension instructions (funct7 = 0000001)
- Assert `is_mul_div` control signal
- Extract operation type from funct3

**Execute Stage (EX)**:
- Start M unit when `is_mul_div` asserted
- Wait for `ready` signal
- Forward result when complete

**Hazard Detection**:
- Check `mul_div_busy` signal
- Stall IF, ID stages while busy
- Insert bubble in EX stage

**Control Signals** (new):
- `is_mul_div` - M instruction detected
- `mul_div_start` - Start M unit
- `mul_div_busy` - M unit busy
- `mul_div_ready` - Result ready

---

## Performance Analysis

### Cycle Counts

| Instruction Type | Cycles | Notes |
|-----------------|--------|-------|
| MUL/MULH/MULHU/MULHSU | 32 (RV32) / 64 (RV64) | Sequential multiply |
| DIV/DIVU/REM/REMU | 32 (RV32) / 64 (RV64) | Non-restoring divide |
| MULW/DIVW/REMW (RV64) | 32 | Word operations |

### CPI Impact

**Without M extension**: CPI ≈ 1.2
**With M extension** (5% M instructions): CPI ≈ 1.2 + 0.05 × 32 = 2.8

**Mitigation strategies** (future):
- Radix-4 Booth multiplier (halve multiply cycles)
- Early termination for small operands
- Separate M unit (allow other instructions to execute)

---

## Special Cases and Edge Conditions

### Division by Zero

**Behavior** (per RISC-V spec):
- `DIV(U) rd, rs1, x0` → rd = -1 (all 1s)
- `REM(U) rd, rs1, x0` → rd = rs1 (dividend)

### Signed Overflow

**Case**: Most negative number divided by -1
- RV32: -2,147,483,648 / -1 = overflow
- RV64: -9,223,372,036,854,775,808 / -1 = overflow

**Behavior** (per RISC-V spec):
- `DIV rd, MIN_INT, -1` → rd = MIN_INT (no exception)
- `REM rd, MIN_INT, -1` → rd = 0

### Multiplication High Bits

**MUL** returns lower XLEN bits
**MULH/MULHSU/MULHU** return upper XLEN bits

Example (RV32):
```
operand_a = 0xFFFFFFFF (-1 signed)
operand_b = 0xFFFFFFFF (-1 signed)

Full product = 0x0000000000000001 (64-bit)

MUL result    = 0x00000001 (lower 32 bits)
MULH result   = 0x00000000 (upper 32 bits)
```

---

## Implementation Phases

### Phase 6.1: Multiply Unit ✓ (This Session)
- [ ] Create `mul_unit.v` - Sequential multiplier
- [ ] Support all multiply variants (MUL, MULH, MULHSU, MULHU)
- [ ] Handle signed/unsigned operands
- [ ] Add XLEN parameterization

### Phase 6.2: Divide Unit
- [ ] Create `div_unit.v` - Non-restoring divider
- [ ] Support DIV, DIVU, REM, REMU
- [ ] Handle division by zero
- [ ] Handle signed overflow case

### Phase 6.3: Integration
- [ ] Create `mul_div_unit.v` - Wrapper for both units
- [ ] Update decoder for M extension detection
- [ ] Update control unit with M signals
- [ ] Modify hazard detection for multi-cycle stall
- [ ] Integrate into EX stage

### Phase 6.4: Testing
- [ ] Unit tests for multiply operations
- [ ] Unit tests for divide operations
- [ ] Edge case tests (div-by-zero, overflow)
- [ ] Integration tests with pipeline
- [ ] RV32M compliance tests

### Phase 6.5: RV64M Support
- [ ] Add MULW, DIVW, DIVUW, REMW, REMUW
- [ ] Test word operations with sign-extension
- [ ] RV64M compliance tests

---

## Decoder Updates

### Current Decoder Output
```verilog
output reg [6:0]  opcode,
output reg [4:0]  rd,
output reg [2:0]  funct3,
output reg [4:0]  rs1,
output reg [4:0]  rs2,
output reg [6:0]  funct7,
// ... immediates ...
```

### New Decoder Outputs (for M extension)
```verilog
output reg        is_mul_div,      // M extension instruction
output reg [3:0]  mul_div_op       // Operation type
```

### Detection Logic
```verilog
// Detect M extension (R-type with funct7 = 0000001)
assign is_mul_div = (opcode == 7'b0110011 || opcode == 7'b0111011) &&
                    (funct7 == 7'b0000001);

// Extract operation from funct3
assign mul_div_op = {1'b0, funct3};  // 4-bit operation code
```

---

## Control Unit Updates

### New Control Signals
```verilog
output reg        mul_div_start,   // Start M unit
output reg        mul_div_en,      // Enable M result
input  wire       mul_div_busy,    // M unit busy (from hazard unit)
input  wire       mul_div_ready    // M result ready
```

### Control Logic
```verilog
always @(*) begin
    if (is_mul_div) begin
        mul_div_start = 1'b1;
        mul_div_en = 1'b1;
        alu_src_a = 2'b00;  // Use rs1
        alu_src_b = 2'b00;  // Use rs2
        reg_write = 1'b1;
        wb_sel = 3'b100;    // Select M unit result
    end
end
```

---

## Hazard Detection Updates

### New Stall Condition
```verilog
// Existing: Load-use hazard
assign load_use_hazard = idex_mem_read &&
                        ((idex_rd_addr == ifid_rs1) ||
                         (idex_rd_addr == ifid_rs2));

// New: M extension hazard
assign mul_div_hazard = mul_div_busy;

// Combined stall signal
assign stall = load_use_hazard || mul_div_hazard;
```

---

## Testing Strategy

### Unit Tests
1. **Multiply Tests**
   - Small numbers (2 × 3 = 6)
   - Large numbers (0xFFFFFFFF × 0xFFFFFFFF)
   - Signed vs unsigned
   - MULH variants

2. **Divide Tests**
   - Simple division (10 / 2 = 5)
   - Remainder (10 % 3 = 1)
   - Division by zero
   - Signed overflow
   - Negative operands

### Integration Tests
```assembly
# Test MUL
li x5, 100
li x6, 200
mul x7, x5, x6      # x7 = 20000

# Test DIV
li x8, 100
li x9, 5
div x10, x8, x9     # x10 = 20

# Test edge case: divide by zero
li x11, 100
li x12, 0
div x13, x11, x12   # x13 = -1 (all 1s)
```

### Compliance Tests
- Use official RISC-V M extension compliance tests
- Target: 100% pass rate for RV32M
- Target: 100% pass rate for RV64M (after RV64M implementation)

---

## Resource Estimates

### Area (FPGA)
- Multiplier: ~500 LUTs + 128 FFs (32-bit)
- Divider: ~800 LUTs + 128 FFs (32-bit)
- Control logic: ~100 LUTs
- **Total**: ~1400 LUTs, ~256 FFs

### Timing
- Critical path: Similar to ALU (combinational MUX)
- No impact on maximum frequency (multi-cycle execution)

---

## Future Optimizations

1. **Booth Multiplier**
   - Reduce cycles by 2× (16 cycles for RV32)
   - Radix-4 encoding

2. **Early Termination**
   - Detect leading zeros in multiplier
   - Skip unnecessary iterations

3. **Separate Execution**
   - Allow pipeline to continue during M operations
   - Out-of-order completion

4. **Dedicated Multiply** (if critical)
   - Use DSP blocks on FPGA
   - 1-cycle multiply

---

## References

- [RISC-V ISA Manual - M Extension](https://riscv.org/technical/specifications/)
- Computer Organization and Design, RISC-V Edition (Patterson & Hennessy)
- "High-Speed Booth Encoded Parallel Multiplier Design" (IEEE)

---

## Summary

The M extension implementation will follow a phased approach:
1. Sequential multiplier (32/64 cycles)
2. Non-restoring divider (32/64 cycles)
3. Pipeline integration with stall mechanism
4. Comprehensive testing

This design prioritizes clarity and correctness over maximum performance, suitable for an educational processor. Future optimizations can reduce latency significantly.

**Next Step**: Implement the multiply unit (`mul_unit.v`)
