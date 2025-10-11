# F/D Extension Design Document

**Date**: 2025-10-10
**Phase**: Phase 8 - F/D Extension Implementation
**Target**: RV32F/D and RV64F/D support

---

## Overview

The F and D extensions add IEEE 754-2008 compliant floating-point computation to the RISC-V ISA. The F extension provides single-precision (32-bit) floating-point, while the D extension extends this to double-precision (64-bit). This document outlines the design and implementation strategy for adding F/D extension support to the RV1 pipelined processor.

**Key Features**:
- IEEE 754-2008 compliant arithmetic
- 32 floating-point registers (f0-f31)
- Floating-point control and status register (fcsr)
- Full support for NaN boxing (D extension)
- Five rounding modes
- Five exception flags

---

## F Extension Instructions (26 total)

### Computational Instructions (9)
| Instruction | Format | Opcode | Funct7 | Description |
|-------------|--------|--------|--------|-------------|
| **FADD.S** | R4-type | 1010011 | 0000000 | Add single-precision |
| **FSUB.S** | R4-type | 1010011 | 0000100 | Subtract single-precision |
| **FMUL.S** | R4-type | 1010011 | 0001000 | Multiply single-precision |
| **FDIV.S** | R4-type | 1010011 | 0001100 | Divide single-precision |
| **FSQRT.S** | R4-type | 1010011 | 0101100 | Square root single-precision |
| **FMIN.S** | R-type | 1010011 | 0010100 | Minimum (funct3=000) |
| **FMAX.S** | R-type | 1010011 | 0010100 | Maximum (funct3=001) |
| **FMADD.S** | R4-type | 1000011 | rs3[4:0] | Fused multiply-add: (rs1×rs2)+rs3 |
| **FMSUB.S** | R4-type | 1000111 | rs3[4:0] | Fused multiply-sub: (rs1×rs2)-rs3 |
| **FNMSUB.S** | R4-type | 1001011 | rs3[4:0] | Fused negate multiply-sub: -(rs1×rs2)+rs3 |
| **FNMADD.S** | R4-type | 1001111 | rs3[4:0] | Fused negate multiply-add: -(rs1×rs2)-rs3 |

### Conversion Instructions (4)
| Instruction | Format | Opcode | Funct7 | rs2 | Description |
|-------------|--------|--------|--------|-----|-------------|
| **FCVT.W.S** | R-type | 1010011 | 1100000 | 00000 | Convert float to signed int32 |
| **FCVT.WU.S** | R-type | 1010011 | 1100000 | 00001 | Convert float to unsigned int32 |
| **FCVT.S.W** | R-type | 1010011 | 1101000 | 00000 | Convert signed int32 to float |
| **FCVT.S.WU** | R-type | 1010011 | 1101000 | 00001 | Convert unsigned int32 to float |
| **FCVT.L.S** | R-type | 1010011 | 1100000 | 00010 | Convert float to signed int64 (RV64 only) |
| **FCVT.LU.S** | R-type | 1010011 | 1100000 | 00011 | Convert float to unsigned int64 (RV64 only) |
| **FCVT.S.L** | R-type | 1010011 | 1101000 | 00010 | Convert signed int64 to float (RV64 only) |
| **FCVT.S.LU** | R-type | 1010011 | 1101000 | 00011 | Convert unsigned int64 to float (RV64 only) |

### Comparison Instructions (3)
| Instruction | Format | Opcode | Funct7 | Funct3 | Description |
|-------------|--------|--------|--------|--------|-------------|
| **FEQ.S** | R-type | 1010011 | 1010000 | 010 | Equal (result in integer rd) |
| **FLT.S** | R-type | 1010011 | 1010000 | 001 | Less than (result in integer rd) |
| **FLE.S** | R-type | 1010011 | 1010000 | 000 | Less or equal (result in integer rd) |

### Sign Injection (3)
| Instruction | Format | Opcode | Funct7 | Funct3 | Description |
|-------------|--------|--------|--------|--------|-------------|
| **FSGNJ.S** | R-type | 1010011 | 0010000 | 000 | Sign inject: |rs1| with sign of rs2 |
| **FSGNJN.S** | R-type | 1010011 | 0010000 | 001 | Sign inject negate: |rs1| with -sign of rs2 |
| **FSGNJX.S** | R-type | 1010011 | 0010000 | 010 | Sign inject XOR: |rs1| with sign(rs1)⊕sign(rs2) |

### Load/Store (2)
| Instruction | Format | Opcode | Funct3 | Description |
|-------------|--------|--------|--------|-------------|
| **FLW** | I-type | 0000111 | 010 | Load single-precision from memory |
| **FSW** | S-type | 0100111 | 010 | Store single-precision to memory |

### Move/Classify (3)
| Instruction | Format | Opcode | Funct7 | Funct3 | Description |
|-------------|--------|--------|--------|--------|-------------|
| **FMV.X.W** | R-type | 1010011 | 1110000 | 000 | Move float reg to integer reg |
| **FMV.W.X** | R-type | 1010011 | 1111000 | 000 | Move integer reg to float reg |
| **FCLASS.S** | R-type | 1010011 | 1110000 | 001 | Classify floating-point number |

---

## D Extension Instructions (Additional 26 for double-precision)

The D extension adds corresponding double-precision versions of all F instructions:
- **FADD.D, FSUB.D, FMUL.D, FDIV.D, FSQRT.D** - Double-precision arithmetic
- **FMIN.D, FMAX.D** - Double-precision min/max
- **FMADD.D, FMSUB.D, FNMSUB.D, FNMADD.D** - Double-precision FMA
- **FLD, FSD** - Load/store double-precision (opcode 0000111/0100111, funct3=011)
- **FCVT.W.D, FCVT.WU.D, FCVT.D.W, FCVT.D.WU** - Double ↔ int32 conversions
- **FCVT.L.D, FCVT.LU.D, FCVT.D.L, FCVT.D.LU** - Double ↔ int64 conversions (RV64 only)
- **FCVT.S.D, FCVT.D.S** - Single ↔ double conversions
- **FEQ.D, FLT.D, FLE.D** - Double-precision comparisons
- **FSGNJ.D, FSGNJN.D, FSGNJX.D** - Double-precision sign injection
- **FMV.X.D, FMV.D.X** - Move double (RV64 only, XLEN≥64)
- **FCLASS.D** - Classify double-precision number

**Encoding Note**: D instructions use `funct7[1:0] = 01` (vs `00` for S instructions)

---

## Floating-Point Register File

### F Extension (FLEN=32)
```
- 32 registers: f0 - f31
- Each register: 32 bits wide
- Separate from integer register file
- f0 NOT hardwired to zero (unlike x0)
```

### D Extension (FLEN=64)
```
- Same 32 registers: f0 - f31
- Each register: 64 bits wide
- Can hold single or double-precision values
- NaN boxing for single-precision values in double registers
```

### NaN Boxing (D Extension)
When a single-precision value is written to a 64-bit register:
- Lower 32 bits: actual single-precision value
- Upper 32 bits: all 1s (0xFFFFFFFF)
- Reading as double: if upper bits not all 1s, treat as canonical NaN

**Example**:
```
FLW f1, 0(x10)       # Load single-precision value 0x3F800000 (1.0)
                     # f1 = 0xFFFFFFFF_3F800000 (NaN-boxed)

FADD.S f2, f1, f1    # Read lower 32 bits: 1.0 + 1.0 = 2.0
                     # f2 = 0xFFFFFFFF_40000000 (NaN-boxed)

FADD.D f3, f1, f1    # Upper bits not valid → treat as NaN
                     # f3 = canonical double NaN
```

---

## FCSR Register (Floating-Point Control and Status Register)

### CSR Address: 0x003

### Bit Layout (32 bits)
```
 31:8  |  7:5  |  4:0
-------|-------|-------
 Rsvd  |  frm  | fflags

frm: Rounding mode (3 bits)
fflags: Accrued exception flags (5 bits)
```

### Sub-Registers
- **frm** (0x002): Floating-point rounding mode (write-only)
- **fflags** (0x001): Floating-point exception flags (read-write)

### Rounding Modes (frm field)
| Value | Mode | Description |
|-------|------|-------------|
| 000 | RNE | Round to Nearest, ties to Even (default) |
| 001 | RTZ | Round Towards Zero |
| 010 | RDN | Round Down (towards -∞) |
| 011 | RUP | Round Up (towards +∞) |
| 100 | RMM | Round to Nearest, ties to Max Magnitude |
| 101-110 | - | Reserved (invalid) |
| 111 | DYN | Dynamic (use frm from fcsr) |

**Note**: Most instructions have a 3-bit `rm` field. If rm=111 (DYN), use frm from fcsr.

### Exception Flags (fflags field)
| Bit | Flag | Description |
|-----|------|-------------|
| 4 | NV | Invalid Operation |
| 3 | DZ | Divide by Zero |
| 2 | OF | Overflow |
| 1 | UF | Underflow |
| 0 | NX | Inexact |

**Behavior**:
- Flags are "sticky" - once set, remain set until explicitly cleared
- No traps on exceptions (flags only)
- Software must check fflags explicitly

---

## IEEE 754-2008 Special Values

### Representation
| Value | Sign | Exponent | Mantissa | Example (Single) |
|-------|------|----------|----------|------------------|
| +Zero | 0 | 0x00 | 0x000000 | 0x00000000 |
| -Zero | 1 | 0x00 | 0x000000 | 0x80000000 |
| +Infinity | 0 | 0xFF | 0x000000 | 0x7F800000 |
| -Infinity | 1 | 0xFF | 0x000000 | 0xFF800000 |
| Quiet NaN | x | 0xFF | 1xxxxxx | 0x7FC00000 (canonical) |
| Signaling NaN | x | 0xFF | 0xxxxxx (≠0) | 0x7F800001 |
| Subnormal | x | 0x00 | ≠0 | 0x00000001 (smallest) |

### Canonical NaN
- Single-precision: `0x7FC00000`
- Double-precision: `0x7FF8000000000000`
- Used as default result for invalid operations

---

## Design Decisions

### 1. Floating-Point Unit Architecture

**Choice**: **Separate FPU with Multi-Cycle Execution**

**Rationale**:
- FP operations (esp. FDIV, FSQRT) take many cycles
- Separate pipeline avoids stalling integer pipeline for long FP ops
- Modular design for easier verification

**Structure**:
```
┌─────────────────────────────────────────────┐
│          Floating-Point Unit (FPU)          │
├──────────────┬──────────────┬───────────────┤
│   FP RegFile │   FP ALU     │  FP Converter │
│   (32 x 64)  │              │   (INT↔FP)    │
├──────────────┼──────────────┼───────────────┤
│  FP Compare  │ FP Classify  │  FP Load/Store│
│              │              │   Interface   │
└──────────────┴──────────────┴───────────────┘
```

### 2. Floating-Point ALU Design

**Option A**: Full combinational (1 cycle, very large area)
**Option B**: Multi-cycle iterative (small area, slow)
**Option C**: Hybrid (fast multiply, iterative divide)

**Choice**: **Option C - Hybrid Approach**

**Cycle Counts** (target):
```
FADD/FSUB:  3-4 cycles   (normalize + round)
FMUL:       3-4 cycles   (multiply + normalize)
FDIV:       16-32 cycles (iterative SRT divider)
FSQRT:      16-32 cycles (iterative Newton-Raphson or digit-recurrence)
FMADD:      4-5 cycles   (multiply-add-normalize)
FCVT:       2-3 cycles   (format conversion)
FMIN/FMAX:  1 cycle      (comparison)
FEQ/FLT/FLE: 1 cycle     (comparison)
FCLASS:     1 cycle      (decode special values)
```

### 3. Floating-Point Register File

**Implementation**:
```verilog
module fp_register_file #(
  parameter FLEN = 32  // 32 for F, 64 for D
) (
  input  wire        clk,
  input  wire        reset_n,

  // Read ports (3 for FMA instructions)
  input  wire [4:0]  rs1_addr,
  input  wire [4:0]  rs2_addr,
  input  wire [4:0]  rs3_addr,
  output wire [FLEN-1:0] rs1_data,
  output wire [FLEN-1:0] rs2_data,
  output wire [FLEN-1:0] rs3_data,

  // Write port
  input  wire        wr_en,
  input  wire [4:0]  rd_addr,
  input  wire [FLEN-1:0] rd_data
);
```

**Key Features**:
- 3 read ports (for FMA instructions: rs1, rs2, rs3)
- 1 write port
- NaN boxing logic for single-precision writes (D extension)

### 4. NaN Propagation

**Choice**: **Canonical NaN for All Invalid Operations**

**Rationale**:
- Simpler hardware (no payload tracking)
- RISC-V spec allows this
- Most software doesn't rely on NaN payloads

**Operations Producing Canonical NaN**:
- 0.0 / 0.0 (indeterminate)
- ∞ - ∞ (indeterminate)
- 0.0 × ∞ (indeterminate)
- sqrt(negative)
- Any operation with NaN input (NaN propagation)

### 5. Subnormal Number Handling

**Choice**: **Full Hardware Support for Subnormals**

**Rationale**:
- Required for IEEE 754 compliance
- Avoids "flush to zero" issues
- Better numerical accuracy

**Implementation**:
- Detect subnormal inputs (exponent = 0, mantissa ≠ 0)
- Normalize before computation
- Denormalize result if needed (gradual underflow)

### 6. Rounding Implementation

**Choice**: **Guard, Round, Sticky Bits (GRS)**

**Algorithm**:
```
After computation:
  G (guard):  bit after LSB of result
  R (round):  bit after guard bit
  S (sticky): OR of all bits after round bit

Round to nearest even (RNE):
  if (G == 0): truncate
  if (G == 1 && R == 0 && S == 0): round to even (LSB = 0)
  if (G == 1 && (R == 1 || S == 1)): round up

Round toward zero (RTZ):
  truncate

Round down (RDN):
  if (sign == 1 && (G|R|S)): round up magnitude
  else: truncate

Round up (RUP):
  if (sign == 0 && (G|R|S)): round up
  else: truncate

Round to nearest max magnitude (RMM):
  if (G == 1): round up magnitude
  else: truncate
```

---

## Floating-Point ALU Modules

### FP Adder/Subtractor (FADD.S/D, FSUB.S/D)

**Algorithm**:
1. **Unpack**: Extract sign, exponent, mantissa
2. **Align**: Shift smaller operand to match larger exponent
3. **Add/Sub**: Perform mantissa addition/subtraction
4. **Normalize**: Shift result to normalized form
5. **Round**: Apply rounding mode
6. **Pack**: Assemble result with sign, exponent, mantissa
7. **Exception flags**: Set NV, OF, UF, NX as needed

**Special Cases**:
- ±∞ + ±∞: Check for ∞ - ∞ (invalid)
- x + NaN: Propagate NaN
- x + 0: Return x (preserve sign)

**State Machine**:
```
IDLE → UNPACK → ALIGN → COMPUTE → NORMALIZE → ROUND → DONE
```

### FP Multiplier (FMUL.S/D)

**Algorithm**:
1. **Unpack**: Extract sign, exponent, mantissa
2. **Sign**: XOR signs
3. **Exponent**: Add exponents (subtract bias)
4. **Multiply**: Multiply mantissas (24×24 for single, 53×53 for double)
5. **Normalize**: Shift product to normalized form
6. **Round**: Apply rounding mode
7. **Pack**: Assemble result
8. **Exception flags**: Set NV, OF, UF, NX

**Special Cases**:
- 0 × ∞: Invalid (NaN)
- x × NaN: Propagate NaN
- ±∞ × ±∞: ±∞
- x × 1.0: Return x

### FP Divider (FDIV.S/D)

**Algorithm**: **SRT Radix-2 Division** (or radix-4 for better performance)

**Steps**:
1. **Unpack**: Extract operands
2. **Sign**: XOR signs
3. **Exponent**: Subtract exponents (add bias)
4. **Divide**: Iterative quotient digit selection (16-32 cycles)
5. **Normalize**: Shift quotient to normalized form
6. **Round**: Apply rounding mode
7. **Pack**: Assemble result
8. **Exception flags**: Set DZ, OF, UF, NX

**Special Cases**:
- x / 0: Divide by zero (±∞ if x≠0, NaN if x=0)
- ∞ / ∞: Invalid (NaN)
- 0 / 0: Invalid (NaN)

### FP Square Root (FSQRT.S/D)

**Algorithm**: **Digit Recurrence** (similar to SRT division)

**Steps**:
1. **Unpack**: Extract operand
2. **Sign check**: If sign=1 (negative), return NaN
3. **Square root**: Iterative digit selection (16-32 cycles)
4. **Normalize**: Already normalized
5. **Round**: Apply rounding mode
6. **Pack**: Assemble result
7. **Exception flags**: Set NV (if negative), NX

**Special Cases**:
- sqrt(+0): +0
- sqrt(-0): -0
- sqrt(+∞): +∞
- sqrt(negative): NaN (set NV flag)
- sqrt(NaN): NaN

### FP Fused Multiply-Add (FMADD.S/D, etc.)

**Key Feature**: **Single Rounding** (not two)

**Algorithm**:
1. **Multiply**: Compute rs1 × rs2 (keep full precision)
2. **Add**: Add rs3 to product (no intermediate rounding)
3. **Round once**: Round final result
4. **Pack**: Assemble result

**Advantage**: More accurate than separate FMUL + FADD

**Variants**:
- FMADD:  (rs1 × rs2) + rs3
- FMSUB:  (rs1 × rs2) - rs3
- FNMSUB: -(rs1 × rs2) + rs3
- FNMADD: -(rs1 × rs2) - rs3

### FP Compare (FEQ.S/D, FLT.S/D, FLE.S/D)

**Implementation**: Simple comparator (1 cycle)

**Algorithm**:
1. **Check NaN**: If either operand is NaN:
   - FEQ: return 0
   - FLT/FLE: return 0, set NV flag if signaling NaN
2. **Compare**: Check signs and magnitudes
3. **Return**: Write result to integer register rd

**Special Cases**:
- -0 == +0: true
- NaN comparison: false (set NV if sNaN)

### FP Classify (FCLASS.S/D)

**Implementation**: Decode special values (1 cycle)

**Output** (10-bit mask in rd):
```
Bit 0: Negative infinity
Bit 1: Negative normal number
Bit 2: Negative subnormal number
Bit 3: Negative zero
Bit 4: Positive zero
Bit 5: Positive subnormal number
Bit 6: Positive normal number
Bit 7: Positive infinity
Bit 8: Signaling NaN
Bit 9: Quiet NaN
```

**Algorithm**: Decode exponent and mantissa fields

---

## Floating-Point Conversion Units

### Integer to Float (FCVT.S.W, FCVT.D.W, etc.)

**Algorithm**:
1. **Check zero**: If int = 0, return +0.0
2. **Extract sign**: Take sign bit, absolute value
3. **Count leading zeros**: Find MSB position
4. **Normalize**: Shift to 1.mantissa form
5. **Exponent**: Calculate exponent from shift amount
6. **Round**: Apply rounding mode
7. **Pack**: Assemble float/double

### Float to Integer (FCVT.W.S, FCVT.D.W, etc.)

**Algorithm**:
1. **Unpack**: Extract sign, exponent, mantissa
2. **Special cases**:
   - NaN: return max_int, set NV flag
   - ±∞: return max_int or min_int, set NV flag
   - Out of range: return max/min, set NV flag
3. **Align**: Shift mantissa by exponent amount
4. **Round**: Apply rounding mode
5. **Convert**: Truncate to integer width
6. **Sign**: Apply sign if signed conversion

**RV64 Variants**:
- W/WU: Convert to/from 32-bit int
- L/LU: Convert to/from 64-bit int

---

## Pipeline Integration

### Pipeline Stages for FP Instructions

```
IF → ID → EX → FP_EXEC (1-32 cycles) → MEM → WB
              ↓
         (FP Reg Write)
```

### Hazard Detection for FP Instructions

**RAW Hazards**:
- FP instruction depends on previous FP result
- Solution: Forward from FP writeback stage

**Structural Hazards**:
- FPU busy with long operation (FDIV, FSQRT)
- Solution: Stall pipeline until FPU available

**Load-Use Hazards**:
- FLW/FLD followed by FP instruction using loaded value
- Solution: Stall 1 cycle (same as integer loads)

### Forwarding Paths

```
FP Reg File → FP ALU (rs1, rs2, rs3)
FP WB → FP ALU (forward result to next FP instruction)
FP WB → FP Reg File (write result)
```

### FPU Busy Signal

```verilog
// Hazard detection unit
assign fpu_busy = (fdiv_active || fsqrt_active) && !fpu_done;
assign stall_for_fpu = is_fp_instruction && fpu_busy;
```

---

## Control Unit Updates

### New Control Signals

```verilog
// FP operation types
output wire       is_fp_op,          // Any FP operation
output wire       is_fp_load,        // FLW/FLD
output wire       is_fp_store,       // FSW/FSD
output wire       is_fp_alu,         // FADD, FMUL, etc.
output wire       is_fp_fma,         // FMA instructions
output wire       is_fp_cvt,         // Conversions
output wire       is_fp_cmp,         // Comparisons
output wire       is_fp_mv,          // Moves (FMV.X.W, FMV.W.X)

// FP ALU operation select
output wire [3:0] fp_alu_op,         // Which FP operation
output wire [2:0] fp_rm,             // Rounding mode (from instruction)
output wire       fp_use_dynamic_rm, // rm=111 (use fcsr.frm)

// Register file controls
output wire       fp_reg_we,         // FP register write enable
output wire       int_reg_we_fp,     // Integer register write (for FMV.X.W, FP compare)
```

### Decoder Updates

**New Instruction Formats**:
```
R4-type (FMA):
  rs3[31:27] | funct2[26:25] | rs2[24:20] | rs1[19:15] | rm[14:12] | rd[11:7] | opcode[6:0]

FP R-type:
  funct7[31:25] | rs2[24:20] | rs1[19:15] | rm[14:12] | rd[11:7] | opcode[6:0]
```

**New Opcodes**:
```
LOAD-FP:  0000111 (FLW/FLD)
STORE-FP: 0100111 (FSW/FSD)
MADD:     1000011 (FMADD.S/D)
MSUB:     1000111 (FMSUB.S/D)
NMSUB:    1001011 (FNMSUB.S/D)
NMADD:    1001111 (FNMADD.S/D)
OP-FP:    1010011 (All other FP operations)
```

---

## CSR Integration

### New CSRs

```verilog
// Add to csr_file.v
parameter CSR_FFLAGS = 12'h001;  // Floating-point exception flags
parameter CSR_FRM    = 12'h002;  // Floating-point rounding mode
parameter CSR_FCSR   = 12'h003;  // Full floating-point CSR
```

### FCSR Structure

```verilog
// In csr_file.v
reg [2:0] frm;     // Rounding mode
reg [4:0] fflags;  // Exception flags

// Read
case (csr_addr)
  CSR_FFLAGS: csr_rdata = {27'b0, fflags};
  CSR_FRM:    csr_rdata = {29'b0, frm};
  CSR_FCSR:   csr_rdata = {24'b0, frm, fflags};
endcase

// Write
case (csr_addr)
  CSR_FFLAGS: fflags = csr_wdata[4:0];
  CSR_FRM:    frm = csr_wdata[2:0];
  CSR_FCSR:   {frm, fflags} = csr_wdata[7:0];
endcase
```

### Exception Flag Updates

```verilog
// Accumulate flags from FPU
always @(posedge clk) begin
  if (fp_op_done) begin
    fflags <= fflags | fp_exception_flags;  // Sticky OR
  end
end
```

---

## Memory Interface Updates

### FP Load/Store

**FLW** (Load Single-Precision):
```verilog
// Same as LW, but write to FP register file
// NaN-box result if D extension enabled (upper 32 bits = all 1s)
fp_reg_wdata = (FLEN == 64) ? {32'hFFFFFFFF, mem_rdata[31:0]} : mem_rdata;
```

**FLD** (Load Double-Precision):
```verilog
// Load 64-bit value from memory
// Requires 64-bit memory interface or two 32-bit loads
fp_reg_wdata = mem_rdata_64;
```

**FSW** (Store Single-Precision):
```verilog
// Extract lower 32 bits from FP register (ignore upper NaN-boxing)
mem_wdata = fp_reg_rdata[31:0];
```

**FSD** (Store Double-Precision):
```verilog
// Store full 64-bit value
mem_wdata_64 = fp_reg_rdata;
```

---

## Testing Strategy

### Unit Tests (Per Module)

1. **FP Register File**:
   - Read/write all 32 registers
   - NaN boxing verification
   - Three-operand read (FMA)

2. **FP Adder**:
   - Basic addition/subtraction
   - Special values (NaN, ±∞, ±0)
   - Overflow/underflow
   - All rounding modes
   - Subnormal handling

3. **FP Multiplier**:
   - Basic multiplication
   - Special values
   - Rounding modes
   - Edge cases (0×∞, etc.)

4. **FP Divider**:
   - Basic division
   - Divide by zero
   - Special values
   - Rounding modes

5. **FP Converter**:
   - Int to float (all widths)
   - Float to int (all widths)
   - Rounding modes
   - Overflow detection

6. **FP Compare**:
   - All comparison types
   - NaN handling
   - -0 == +0 case

### Integration Tests

1. **Basic FP Operations**:
```assembly
# Test FADD.S
  fli.s f1, 1.0        # f1 = 1.0 (pseudo-instruction)
  fli.s f2, 2.5        # f2 = 2.5
  fadd.s f3, f1, f2    # f3 = 3.5

# Test FMUL.S
  fli.s f4, 3.0
  fmul.s f5, f3, f4    # f5 = 10.5

# Test FMA
  fmadd.s f6, f1, f2, f4  # f6 = (1.0 * 2.5) + 3.0 = 5.5
```

2. **Conversion Tests**:
```assembly
  li t0, 42
  fcvt.s.w f10, t0     # f10 = 42.0
  fcvt.w.s t1, f10     # t1 = 42
  bne t0, t1, fail
```

3. **Comparison Tests**:
```assembly
  fli.s f1, 1.0
  fli.s f2, 2.0
  flt.s t0, f1, f2     # t0 = 1 (1.0 < 2.0)
  feq.s t1, f1, f1     # t1 = 1 (1.0 == 1.0)
```

4. **Special Value Tests**:
```assembly
  # Test division by zero
  fli.s f1, 1.0
  fmv.w.x f2, zero     # f2 = +0.0
  fdiv.s f3, f1, f2    # f3 = +∞
  fclass.s t0, f3      # t0 = bit 7 set (positive infinity)
```

5. **FCSR Tests**:
```assembly
  # Set rounding mode to round toward zero
  li t0, 1             # RTZ mode
  csrw frm, t0

  # Test rounding
  fli.s f1, 1.5
  fcvt.w.s t1, f1      # t1 = 1 (rounded toward zero)

  # Check exception flags
  csrr t2, fflags
  andi t3, t2, 1       # Check NX (inexact) flag
```

### Compliance Tests

Use official RISC-V compliance tests:
```
riscv-tests/isa/rv32uf-p-*    # RV32F tests
riscv-tests/isa/rv32ud-p-*    # RV32D tests
riscv-tests/isa/rv64uf-p-*    # RV64F tests
riscv-tests/isa/rv64ud-p-*    # RV64D tests
```

### Performance Tests

Benchmark floating-point intensive code:
- Matrix multiplication
- FFT (Fast Fourier Transform)
- Scientific computing kernels

---

## Implementation Phases

### Phase 8.1: Infrastructure (Week 1)
- [x] Design document (this file)
- [ ] FP register file module
- [ ] FCSR integration in CSR file
- [ ] Decoder updates for FP formats
- [ ] Control unit updates

### Phase 8.2: Basic FP Operations (Week 2)
- [ ] FP adder/subtractor
- [ ] FP multiplier
- [ ] FP sign injection (FSGNJ)
- [ ] FP min/max
- [ ] Unit tests for each

### Phase 8.3: Conversions & Comparisons (Week 3)
- [ ] Integer ↔ float conversion
- [ ] FP comparisons (FEQ, FLT, FLE)
- [ ] FP classify (FCLASS)
- [ ] Move instructions (FMV.X.W, FMV.W.X)

### Phase 8.4: Advanced Operations (Week 4)
- [ ] FP divider (iterative)
- [ ] FP square root
- [ ] Fused multiply-add (FMA)
- [ ] Performance optimization

### Phase 8.5: D Extension (Week 5)
- [ ] Widen FP registers to 64 bits
- [ ] NaN boxing logic
- [ ] Double-precision operations
- [ ] Single ↔ double conversions

### Phase 8.6: Integration & Testing (Week 6)
- [ ] Pipeline integration
- [ ] Hazard detection for FP
- [ ] Forwarding for FP results
- [ ] Integration tests
- [ ] Compliance tests

---

## Resource Estimates

### RTL Module Sizes (estimated)

```
fp_register_file.v       ~100 lines
fp_adder.v               ~250 lines
fp_multiplier.v          ~200 lines
fp_divider.v             ~300 lines
fp_sqrt.v                ~300 lines
fp_fma.v                 ~350 lines
fp_converter.v           ~200 lines
fp_compare.v             ~100 lines
fp_classify.v            ~80 lines
fp_control.v             ~150 lines
--------------------------------
Total:                   ~2030 lines (F + D extensions)
```

### FPGA Resources (estimated for F extension on Artix-7)

```
LUTs:          ~5000-8000 (depends on multiplier/divider)
Registers:     ~2000-3000
Block RAM:     1 BRAM (FP register file)
DSP slices:    2-4 (for fast multiply)
Fmax:          ~100 MHz (pipelined FP units)
```

---

## Performance Characteristics

### Cycle Counts (estimated)

```
FADD/FSUB:     3-4 cycles
FMUL:          3-4 cycles
FDIV:          16-32 cycles
FSQRT:         16-32 cycles
FMADD:         4-5 cycles
FCVT:          2-3 cycles
FCMP/FCLASS:   1 cycle
FLW/FSW:       Same as LW/SW (1 cycle in MEM stage)
```

### CPI Impact

For FP-heavy code:
- Without forwarding: CPI ~2.0-3.0
- With FP forwarding: CPI ~1.3-1.8
- With optimized FPU: CPI ~1.2-1.5

---

## Known Limitations & Future Work

### Limitations (Initial Implementation)

1. **No Hardware Support for**:
   - Transcendental functions (sin, cos, log, etc.) - software emulation required
   - Quad-precision (Q extension)
   - Half-precision (Zfh extension)

2. **Performance**:
   - Sequential FP divider/sqrt (16-32 cycles)
   - Can be improved with radix-4 or higher

3. **Subnormals**:
   - Full support (slow path)
   - Could add "flush to zero" mode for performance

### Future Enhancements

1. **Faster Divider**: Implement radix-4 SRT (8-16 cycles)
2. **Faster SQRT**: Newton-Raphson iteration with lookup table
3. **Parallel FPU**: Multiple FP operations in flight
4. **FP Forwarding**: More aggressive forwarding for back-to-back FP ops
5. **Zfh Extension**: Half-precision (16-bit) support
6. **Q Extension**: Quad-precision (128-bit) support

---

## References

1. **RISC-V ISA Manual**: https://riscv.org/technical/specifications/
   - Volume I, Chapter 11: "F" Standard Extension for Single-Precision Floating-Point
   - Volume I, Chapter 12: "D" Standard Extension for Double-Precision Floating-Point

2. **IEEE 754-2008**: Standard for Floating-Point Arithmetic

3. **Floating-Point Hardware Design**:
   - "Computer Arithmetic: Algorithms and Hardware Designs" by Behrooz Parhami
   - "Digital Arithmetic" by Ercegovac and Lang

4. **RISC-V F/D Compliance Tests**: https://github.com/riscv/riscv-tests

---

## Appendix: Instruction Encoding Reference

### Opcode Summary
```
0000111: LOAD-FP  (FLW, FLD)
0100111: STORE-FP (FSW, FSD)
1000011: FMADD
1000111: FMSUB
1001011: FNMSUB
1001111: FNMADD
1010011: OP-FP (all other FP operations)
```

### OP-FP Funct7 Encoding
```
Single-Precision:
0000000: FADD.S       0010100: FMIN.S/FMAX.S
0000100: FSUB.S       0010000: FSGNJ.S/FSGNJN.S/FSGNJX.S
0001000: FMUL.S       1010000: FEQ.S/FLT.S/FLE.S
0001100: FDIV.S       1100000: FCVT.W.S/FCVT.WU.S/FCVT.L.S/FCVT.LU.S
0101100: FSQRT.S      1101000: FCVT.S.W/FCVT.S.WU/FCVT.S.L/FCVT.S.LU
                      1110000: FMV.X.W/FCLASS.S
                      1111000: FMV.W.X

Double-Precision (same funct7, but bits [1:0] = 01):
0000001: FADD.D       0010101: FMIN.D/FMAX.D
0000101: FSUB.D       0010001: FSGNJ.D/FSGNJN.D/FSGNJX.D
0001001: FMUL.D       1010001: FEQ.D/FLT.D/FLE.D
0001101: FDIV.D       1100001: FCVT.W.D/FCVT.WU.D/FCVT.L.D/FCVT.LU.D
0101101: FSQRT.D      1101001: FCVT.D.W/FCVT.D.WU/FCVT.D.L/FCVT.D.LU
0100000: FCVT.S.D     1110001: FMV.X.D/FCLASS.D
0100001: FCVT.D.S     1111001: FMV.D.X
```

---

**End of Document**
