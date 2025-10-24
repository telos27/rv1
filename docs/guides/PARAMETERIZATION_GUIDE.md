# RV1 Parameterization Guide

**Date**: 2025-10-10
**Status**: Initial parameterization complete for core modules
**Version**: 0.1

---

## Overview

This document describes the parameterization strategy for creating multiple variants of the RV1 RISC-V processor (RV32/RV64, single/multi-core, different ISA extensions).

## Parameterization Philosophy

The RV1 processor uses a **parameter-based configuration system** that allows:

1. **XLEN parameterization**: Support both 32-bit (RV32) and 64-bit (RV64) architectures
2. **Extension selection**: Enable/disable ISA extensions via compile-time parameters
3. **Cache configuration**: Adjust cache sizes and associativity
4. **Multicore support**: Scale from 1 to N cores with optional coherency

## Configuration System

### Central Configuration File

**Location**: `rtl/config/rv_config.vh`

This header file contains all global configuration parameters using Verilog `define` macros.

**Key Parameters**:

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `XLEN` | Register/data width | 32 | 32, 64 |
| `ENABLE_M_EXT` | Multiply/Divide | 0 | 0, 1 |
| `ENABLE_A_EXT` | Atomics | 0 | 0, 1 |
| `ENABLE_C_EXT` | Compressed | 0 | 0, 1 |
| `ENABLE_ZICSR` | CSR Support | 1 | 0, 1 |
| `NUM_CORES` | Number of cores | 1 | 1, 2, 4, 8, ... |
| `ICACHE_SIZE` | I-cache size (bytes) | 4096 | Any power of 2 |
| `DCACHE_SIZE` | D-cache size (bytes) | 4096 | Any power of 2 |

### Configuration Presets

The config file includes preset configurations:

- **CONFIG_RV32I**: Minimal 32-bit base ISA
- **CONFIG_RV32IM**: 32-bit with multiply/divide
- **CONFIG_RV32IMC**: 32-bit with M and compressed extensions
- **CONFIG_RV64I**: 64-bit base ISA
- **CONFIG_RV64GC**: 64-bit full-featured (IMAFC)

**Usage**:
```bash
# Compile with preset configuration
iverilog -g2012 -DCONFIG_RV32IM rtl/**/*.v
```

Or use custom parameters:
```bash
# Custom configuration
iverilog -g2012 -DXLEN=64 -DENABLE_M_EXT=1 rtl/**/*.v
```

---

## Parameterized Modules

### ✅ Completed Modules

#### 1. ALU (`rtl/core/alu.v`)

**Parameters**:
- `XLEN`: Data width (32 or 64 bits)

**Changes**:
- All data paths parameterized: `operand_a[XLEN-1:0]`, `operand_b[XLEN-1:0]`, `result[XLEN-1:0]`
- Shift amount width: `$clog2(XLEN)` (5 bits for RV32, 6 bits for RV64)
- Comparison results properly sized
- Zero detection works for any XLEN

**Instantiation**:
```verilog
alu #(
  .XLEN(32)  // or 64
) alu_inst (
  .operand_a(alu_in_a),
  .operand_b(alu_in_b),
  // ...
);
```

#### 2. Register File (`rtl/core/register_file.v`)

**Parameters**:
- `XLEN`: Register width (32 or 64 bits)

**Changes**:
- Register array: `reg [XLEN-1:0] registers [0:31]`
- Data ports: `rs1_data[XLEN-1:0]`, `rs2_data[XLEN-1:0]`, `rd_data[XLEN-1:0]`
- x0 hardwired to 0 for any XLEN
- Internal forwarding logic width-agnostic

**Notes**:
- RV32: 32 x 32-bit registers
- RV64: 32 x 64-bit registers

#### 3. Decoder (`rtl/core/decoder.v`)

**Parameters**:
- `XLEN`: Immediate and address width (32 or 64 bits)

**Changes**:
- All immediate outputs: `imm_i[XLEN-1:0]`, `imm_s[XLEN-1:0]`, etc.
- Sign-extension parameterized: `{{(XLEN-12){instruction[31]}}, ...}`
- Handles proper immediate width for both RV32 and RV64
- Instruction encoding remains 32-bit (RISC-V spec)

**Important**:
- Instructions are always 32-bit in base ISA (even for RV64)
- Only immediates are sign-extended to XLEN

#### 4. Data Memory (`rtl/memory/data_memory.v`)

**Parameters**:
- `XLEN`: Data/address width (32 or 64 bits)
- `MEM_SIZE`: Memory size in bytes (default 64KB)
- `MEM_FILE`: Hex file for initialization

**Changes**:
- Address and data ports: `addr[XLEN-1:0]`, `write_data[XLEN-1:0]`, `read_data[XLEN-1:0]`
- RV64-specific instructions:
  - LD (load doubleword): funct3 = 3'b011
  - SD (store doubleword): funct3 = 3'b011
  - LWU (load word unsigned): funct3 = 3'b110
- Sign-extension for LW in RV64 mode
- Byte-addressable memory (8-bit per address)

**RV64 Memory Operations**:
```
RV32: LB, LH, LW, LBU, LHU, SB, SH, SW
RV64: LB, LH, LW, LD, LBU, LHU, LWU, SB, SH, SW, SD
```

#### 5. Instruction Memory (`rtl/memory/instruction_memory.v`)

**Parameters**:
- `XLEN`: Address width (32 or 64 bits)
- `MEM_SIZE`: Memory size in bytes (default 64KB)
- `MEM_FILE`: Hex file for program loading

**Changes**:
- Address input: `addr[XLEN-1:0]`
- Word-aligned addressing handles XLEN-bit addresses
- Instruction output remains 32-bit (RISC-V standard)

---

## ⏳ Pending Modules

The following modules still need parameterization:

### Pipeline Registers

- `ifid_register.v`: PC and instruction (PC needs XLEN)
- `idex_register.v`: All control and data signals (multiple XLEN fields)
- `exmem_register.v`: ALU result, memory data (XLEN fields)
- `memwb_register.v`: Write-back data (XLEN fields)

### Control and Support Units

- `control.v`: Mainly control signals (minimal changes needed)
- `branch_unit.v`: May need XLEN for branch target calculation
- `pc.v`: PC counter needs XLEN parameterization
- `forwarding_unit.v`: No changes needed (address comparison only)
- `hazard_detection_unit.v`: No changes needed (address comparison only)
- `csr_file.v`: CSRs are XLEN-wide in RV spec
- `exception_unit.v`: Address fields need XLEN

### Top-Level Cores

- `rv32i_core.v`: Needs full parameterization and rename to `rv_core.v`
- `rv32i_core_pipelined.v`: Needs full parameterization and rename to `rv_core_pipelined.v`

---

## Usage Examples

### Example 1: Build RV32I Configuration (Default)

```bash
# Uses default XLEN=32 from rv_config.vh
iverilog -g2012 \
  -I rtl/config \
  -o sim/rv32i.vvp \
  rtl/**/*.v tb/integration/tb_core_pipelined.v

vvp sim/rv32i.vvp
```

### Example 2: Build RV32IM Configuration

```bash
# Use CONFIG_RV32IM preset
iverilog -g2012 \
  -DCONFIG_RV32IM \
  -I rtl/config \
  -o sim/rv32im.vvp \
  rtl/**/*.v tb/integration/tb_core_pipelined.v

vvp sim/rv32im.vvp
```

### Example 3: Build RV64I Configuration

```bash
# Use CONFIG_RV64I preset (or manual -DXLEN=64)
iverilog -g2012 \
  -DCONFIG_RV64I \
  -I rtl/config \
  -o sim/rv64i.vvp \
  rtl/**/*.v tb/integration/tb_core_pipelined.v

vvp sim/rv64i.vvp
```

### Example 4: Custom Configuration

```bash
# 64-bit with multiply and atomics
iverilog -g2012 \
  -DXLEN=64 \
  -DENABLE_M_EXT=1 \
  -DENABLE_A_EXT=1 \
  -DICACHE_SIZE=8192 \
  -DDCACHE_SIZE=8192 \
  -I rtl/config \
  -o sim/custom.vvp \
  rtl/**/*.v tb/integration/tb_core_pipelined.v

vvp sim/custom.vvp
```

---

## Build System Integration

### Recommended Makefile Structure

```makefile
# Makefile - RV1 Build System

# Include paths
INC_PATH = -I rtl/config

# Source files
RTL_CORE = rtl/core/*.v
RTL_MEM  = rtl/memory/*.v
RTL_ALL  = $(RTL_CORE) $(RTL_MEM)

# Simulator
SIM = iverilog -g2012 $(INC_PATH)
RUN = vvp

# Build targets
.PHONY: rv32i rv32im rv32imc rv64i rv64gc clean

# RV32I - Base 32-bit ISA
rv32i:
	$(SIM) -DCONFIG_RV32I -o sim/rv32i.vvp $(RTL_ALL) tb/integration/tb_core_pipelined.v

# RV32IM - 32-bit with multiply/divide
rv32im:
	$(SIM) -DCONFIG_RV32IM -o sim/rv32im.vvp $(RTL_ALL) tb/integration/tb_core_pipelined.v

# RV32IMC - 32-bit with M and compressed
rv32imc:
	$(SIM) -DCONFIG_RV32IMC -o sim/rv32imc.vvp $(RTL_ALL) tb/integration/tb_core_pipelined.v

# RV64I - Base 64-bit ISA
rv64i:
	$(SIM) -DCONFIG_RV64I -o sim/rv64i.vvp $(RTL_ALL) tb/integration/tb_core_pipelined.v

# RV64GC - Full-featured 64-bit
rv64gc:
	$(SIM) -DCONFIG_RV64GC -o sim/rv64gc.vvp $(RTL_ALL) tb/integration/tb_core_pipelined.v

# Run simulation
run-%:
	$(RUN) sim/$*.vvp

# Clean
clean:
	rm -f sim/*.vvp sim/*.vcd
```

**Usage**:
```bash
make rv32i          # Build RV32I configuration
make run-rv32i      # Run RV32I simulation

make rv64i          # Build RV64I configuration
make run-rv64i      # Run RV64I simulation
```

---

## Extension Support Framework

### Adding M Extension (Multiply/Divide)

When `ENABLE_M_EXT = 1`, the core should instantiate a multiply/divide unit:

```verilog
// In rv_core_pipelined.v
generate
  if (`ENABLE_M_EXT) begin : gen_m_ext
    mul_div_unit #(
      .XLEN(`XLEN)
    ) mdu (
      .clk(clk),
      .rst_n(rst_n),
      .op_a(rs1_data),
      .op_b(rs2_data),
      .funct3(funct3),
      .start(m_ext_start),
      .result(m_ext_result),
      .done(m_ext_done)
    );
  end else begin : gen_no_m_ext
    // Tie off signals
    assign m_ext_result = {`XLEN{1'b0}};
    assign m_ext_done = 1'b0;
  end
endgenerate
```

### Adding A Extension (Atomics)

Similar approach for atomic memory operations (LR/SC, AMO instructions).

---

## Testing Strategy

### Test Matrix

| Configuration | XLEN | Extensions | Status |
|---------------|------|------------|--------|
| RV32I         | 32   | None       | ✅ Baseline (95% compliance) |
| RV32IM        | 32   | M          | ⏳ Pending M ext implementation |
| RV32IMC       | 32   | M, C       | ⏳ Pending M, C ext |
| RV64I         | 64   | None       | ⏳ Needs pipeline parameterization |
| RV64GC        | 64   | IMAFC      | ⏳ Future work |

### Regression Testing

After completing parameterization:

1. **RV32I Regression**: Verify all 40/42 compliance tests still pass
2. **RV64I Compliance**: Run RV64I compliance test suite
3. **Cross-config**: Ensure same functionality across configs

---

## Migration Path

### Phase 1: Core Module Parameterization ✅

**Completed**:
- ✅ Configuration system (`rv_config.vh`)
- ✅ ALU
- ✅ Register File
- ✅ Decoder
- ✅ Data Memory
- ✅ Instruction Memory

### Phase 2: Pipeline and Control Units (Next)

**TODO**:
- ⏳ Pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB)
- ⏳ PC module
- ⏳ Branch unit
- ⏳ CSR file (XLEN-wide CSRs)
- ⏳ Exception unit

### Phase 3: Top-Level Integration

**TODO**:
- ⏳ Parameterize `rv32i_core_pipelined.v`
- ⏳ Rename to `rv_core_pipelined.v`
- ⏳ Update testbenches for parameterization
- ⏳ Create build targets in Makefile

### Phase 4: Verification

**TODO**:
- ⏳ Run RV32I compliance (verify no regression)
- ⏳ Test RV64I configuration
- ⏳ Validate all presets

### Phase 5: Extensions

**TODO**:
- ⏳ Implement M extension
- ⏳ Implement A extension
- ⏳ Implement C extension

---

## Design Patterns and Best Practices

### 1. Always Use Parameters, Not Constants

❌ **Bad**:
```verilog
wire [31:0] data;
wire [4:0] shamt = data[4:0];
```

✅ **Good**:
```verilog
wire [XLEN-1:0] data;
localparam SHAMT_WIDTH = $clog2(XLEN);
wire [SHAMT_WIDTH-1:0] shamt = data[SHAMT_WIDTH-1:0];
```

### 2. Proper Sign Extension

❌ **Bad**:
```verilog
assign imm_i = {{20{instruction[31]}}, instruction[31:20]};  // Fixed 32-bit
```

✅ **Good**:
```verilog
assign imm_i = {{(XLEN-12){instruction[31]}}, instruction[31:20]};  // Scales with XLEN
```

### 3. Zero Initialization

❌ **Bad**:
```verilog
result = 32'h0;  // Fixed width
```

✅ **Good**:
```verilog
result = {XLEN{1'b0}};  // Width-agnostic
```

### 4. Conditional Instantiation

```verilog
generate
  if (ENABLE_M_EXT) begin : gen_m_unit
    // Instantiate multiply/divide unit
  end
endgenerate
```

### 5. Include Configuration Header

Every parameterized module should include:
```verilog
`include "config/rv_config.vh"

module my_module #(
  parameter XLEN = `XLEN  // Use default from config
) (
  // ...
);
```

---

## Known Limitations

1. **Instruction width**: Always 32-bit (RISC-V spec), even for RV64
2. **CSR width**: CSRs should be XLEN-wide (pending implementation)
3. **Compressed extension**: Requires 16-bit instruction fetch (future work)

---

## Future Enhancements

1. **Multicore support**: Add NUM_CORES parameter and interconnect
2. **Cache parameterization**: Finish cache size/associativity parameters
3. **SystemVerilog packages**: Migrate from `define` to SV packages for type safety
4. **Automated testing**: CI/CD for all configurations

---

## References

- RISC-V ISA Specification: https://riscv.org/technical/specifications/
- RISC-V Unprivileged Spec (Volume 1): RV32I and RV64I differences
- SiFive Cores: Industry examples of parameterized RISC-V designs

---

**Next Steps**:
1. Complete pipeline register parameterization
2. Parameterize top-level cores
3. Update build system (Makefile)
4. Run regression tests on RV32I
5. Create RV64I test suite

---

**Document Version**: 0.1
**Last Updated**: 2025-10-10
**Author**: RV1 Parameterization Team
