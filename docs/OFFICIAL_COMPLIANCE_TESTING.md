# Official RISC-V Compliance Testing Infrastructure

## Overview

This document describes the infrastructure for running official RISC-V compliance tests from the [riscv/riscv-tests](https://github.com/riscv/riscv-tests) repository.

**Status**: ✅ Infrastructure Complete (81 tests built, runner ready)
**Created**: 2025-10-12

## Directory Structure

```
rv1/
├── riscv-tests/                    # Official test suite (git submodule)
│   ├── isa/                        # ISA tests by extension
│   │   ├── rv32ui-p-*              # Base integer (42 tests)
│   │   ├── rv32um-p-*              # M extension (8 tests)
│   │   ├── rv32ua-p-*              # A extension (10 tests)
│   │   ├── rv32uf-p-*              # F extension (11 tests)
│   │   ├── rv32ud-p-*              # D extension (9 tests)
│   │   └── rv32uc-p-*              # C extension (1 test)
│   └── env/                        # Test environment headers
├── tools/
│   ├── build_riscv_tests.sh        # Build all test binaries
│   └── run_official_tests.sh       # Run tests through RV1 core
├── tests/official-compliance/       # Converted hex files
└── sim/official-compliance/         # Simulation results and logs
```

## Test Suite Statistics

| Extension | Description | Tests | Status |
|-----------|-------------|-------|--------|
| RV32UI | Base Integer ISA | 42 | ✅ Built |
| RV32UM | Multiply/Divide | 8 | ✅ Built |
| RV32UA | Atomic Operations | 10 | ✅ Built |
| RV32UF | Single-Precision FP | 11 | ✅ Built |
| RV32UD | Double-Precision FP | 9 | ✅ Built |
| RV32UC | Compressed Instructions | 1 | ✅ Built |
| **Total** | | **81** | ✅ Built |

## Build Instructions

### 1. Clone and Initialize the Test Repository

The `riscv-tests` repository should already be cloned. If not:

```bash
git clone --depth 1 https://github.com/riscv/riscv-tests.git
cd riscv-tests
git submodule update --init --recursive
```

### 2. Build All Tests

```bash
./tools/build_riscv_tests.sh
```

This script:
- Configures the riscv-tests build system
- Compiles all `-p` (physical memory mode) tests
- Skips `-v` (virtual memory mode) tests (require full libc)
- Reports summary of built tests

**Expected Output**:
```
========================================
Build Summary
========================================
RV32UI (Base Integer):     42 tests
RV32UM (Multiply/Divide):  8 tests
RV32UA (Atomic):           10 tests
RV32UF (Single-FP):        11 tests
RV32UD (Double-FP):        9 tests
RV32UC (Compressed):       1 tests

Total: 81 test binaries built
```

## Running Tests

### Basic Usage

```bash
./tools/run_official_tests.sh <extension> [test_name]
```

### Examples

```bash
# Run all RV32I base tests
./tools/run_official_tests.sh i

# Run all M extension tests
./tools/run_official_tests.sh m

# Run specific test
./tools/run_official_tests.sh i add

# Run ALL tests (all extensions)
./tools/run_official_tests.sh all
```

### Extension Names

| Short | Full | Description |
|-------|------|-------------|
| i, ui | rv32ui | Base Integer |
| m, um | rv32um | Multiply/Divide |
| a, ua | rv32ua | Atomic |
| f, uf | rv32uf | Single-Precision FP |
| d, ud | rv32ud | Double-Precision FP |
| c, uc | rv32uc | Compressed |
| all | all | All extensions |

## Test Execution Flow

### 1. Test Binary to Hex Conversion

The runner automatically converts ELF binaries to hex format:

```
ELF binary → Binary (objcopy) → Byte-wise hex → Memory $readmemh
```

Example:
```bash
riscv64-unknown-elf-objcopy -O binary rv32ui-p-add rv32ui-p-add.bin
hexdump -v -e '1/1 "%02x\n"' rv32ui-p-add.bin > rv32ui-p-add.hex
```

### 2. Testbench Compilation

```bash
iverilog -g2012 \
  -I rtl \
  -DCOMPLIANCE_TEST \
  -DMEM_FILE="path/to/test.hex" \
  -o sim/test.vvp \
  rtl/core/*.v rtl/memory/*.v \
  tb/integration/tb_core_pipelined.v
```

### 3. Simulation Execution

```bash
timeout 10s vvp sim/test.vvp > sim/test.log 2>&1
```

### 4. Result Detection

The testbench (`tb_core_pipelined.v`) detects test completion via:

**ECALL instruction detection** (COMPLIANCE_TEST mode):
- Test calls `ECALL` when complete
- `gp` (x3) register indicates pass/fail:
  - `gp == 1`: TEST PASSED
  - `gp != 1`: TEST FAILED (gp = failed test number)

## Test Structure

### Memory Layout

Official tests use this memory map:

```
0x80000000  - Start of test code (_start)
0x80000004  - Trap vector
0x80001000  - tohost (test result communication)
0x80001008  - fromhost (for interactive tests)
```

### Reset Vector

The testbench sets reset vector based on mode:
- **Normal mode**: `0x00000000`
- **COMPLIANCE_TEST mode**: `0x80000000` ✅

### Address Masking

Memory modules use address masking for flexibility:
```verilog
wire [XLEN-1:0] masked_addr = addr & (MEM_SIZE - 1);
```

For 16KB memory (`MEM_SIZE = 16384`):
- `0x80000000 & 0x3FFF = 0x0000` → Maps to start of memory
- `0x80001000 & 0x3FFF = 0x1000` → Maps to offset 0x1000

This allows high-address tests to run on small memories.

## Test Pass/Fail Mechanism

### Source Code Macros

Tests use these macros from `env/p/riscv_test.h`:

```c
#define RVTEST_PASS
    fence;
    li TESTNUM, 1;        // Set gp = 1
    li a7, 93;            // Exit syscall number
    li a0, 0;             // Success code
    ecall                 // Trigger test end

#define RVTEST_FAIL
    fence;
    sll TESTNUM, TESTNUM, 1;  // Shift test number
    or TESTNUM, TESTNUM, 1;   // Set LSB
    li a7, 93;
    addi a0, TESTNUM, 0;
    ecall
```

### Testbench Detection

From `tb/integration/tb_core_pipelined.v` (lines 139-168):

```verilog
`ifdef COMPLIANCE_TEST
  // Check for ECALL (0x00000073)
  if (instruction == 32'h00000073) begin
    if (DUT.regfile.registers[3] == 1) begin
      $display("RISC-V COMPLIANCE TEST PASSED");
    end else begin
      $display("RISC-V COMPLIANCE TEST FAILED");
      $display("Failed at test number: %0d", DUT.regfile.registers[3]);
    end
    $finish;
  end
`endif
```

## Current Status and Known Issues

### ✅ Completed Infrastructure

1. **Test Repository**: Cloned and initialized
2. **Build System**: 81 tests compiled successfully
3. **Test Runner**: Automated script with colored output
4. **Testbench**: Compliance mode support implemented
5. **Documentation**: Complete setup guide

### ⚠️ Known Issues

1. **Tests Hanging**: Some tests timeout during simulation
   - **Possible causes**:
     - CSR implementation differences (mtvec, mepc, etc.)
     - Missing CSR registers used in test setup
     - Trap handling differences
     - PMP (Physical Memory Protection) not implemented

2. **Debug Needed**:
   - Enable verbose PC/instruction tracing
   - Check CSR register access patterns
   - Verify trap vector behavior
   - Add PMP stub registers

### 🔧 Debugging Steps

1. **Enable Debug Output**:
   ```verilog
   // In tb_core_pipelined.v, uncomment line 88:
   $display("[%0d] PC=0x%08h, Instr=0x%08h", cycle_count, pc, instruction);
   ```

2. **Run with Waveforms**:
   ```bash
   ./tools/run_official_tests.sh i add
   gtkwave sim/waves/core_pipelined.vcd
   ```

3. **Check CSR Coverage**:
   ```bash
   grep -o "csr[rw][iw]*\s*\w\+" riscv-tests/isa/rv32ui-p-add.dump | sort -u
   ```

4. **Compare with Working Tests**:
   - Our custom tests pass (42/42 RV32I previously)
   - Official tests have different initialization
   - Focus on CSR setup differences

## Next Steps

### Immediate (Debugging)

1. **Add verbose logging** to identify where tests hang
2. **Check CSR implementation** against test requirements
3. **Add PMP stub** (tests use `pmpcfg0`, `pmpaddr0`)
4. **Verify trap handling** for ECALL, exceptions

### Short Term (Validation)

1. Get RV32UI tests passing (42 tests)
2. Run M extension tests (8 tests)
3. Run A extension tests (10 tests)
4. Run F/D extension tests (20 tests)
5. Run C extension test (1 test)

### Long Term (Compliance)

1. **Full RV32I Compliance**: All 42 tests passing
2. **Extension Compliance**: M, A, F, D, C tests passing
3. **RV64 Support**: Build and run RV64 test variants
4. **Performance**: Optimize test runtime
5. **CI Integration**: Automated compliance testing

## References

### Official RISC-V Resources

- **Test Repository**: https://github.com/riscv/riscv-tests
- **ISA Specification**: https://riscv.org/technical/specifications/
- **Compliance Framework**: https://github.com/riscv/riscv-compliance

### RV1 Project Documentation

- **README.md**: Project overview and current status
- **CLAUDE.md**: Development guidelines and context
- **ARCHITECTURE.md**: Core microarchitecture details
- **Phase Documents**: Detailed implementation notes

## Usage Tips

### Quick Test Run

```bash
# Test a single instruction
./tools/run_official_tests.sh i add

# If it passes, test the whole extension
./tools/run_official_tests.sh i
```

### Batch Testing

```bash
# Create a test script
for ext in i m a f d c; do
  echo "Testing $ext..."
  ./tools/run_official_tests.sh $ext
done
```

### Log Analysis

```bash
# Check compilation errors
cat sim/official-compliance/rv32ui-p-add_compile.log

# Check simulation output
cat sim/official-compliance/rv32ui-p-add.log

# Find failed tests
grep "FAILED" sim/official-compliance/*.log
```

## Troubleshooting

### "riscv-tests directory not found"

```bash
# Clone the repository
git clone --depth 1 https://github.com/riscv/riscv-tests.git
cd riscv-tests
git submodule update --init --recursive
```

### "No tests built"

```bash
# Run the build script
./tools/build_riscv_tests.sh

# Check for compiler
which riscv64-unknown-elf-gcc
```

### "Compilation failed"

```bash
# Check compile log
cat sim/official-compliance/<test>_compile.log

# Verify RTL files exist
ls rtl/core/*.v rtl/memory/*.v
```

### "All tests timeout"

1. Check testbench timeout setting (default 50,000 cycles)
2. Enable debug output to see execution
3. Verify memory initialization
4. Check reset vector configuration

## Conclusion

The official RISC-V compliance testing infrastructure is **fully set up** and ready for debugging. With 81 tests built across 6 extensions, we have comprehensive coverage of the RV1 core's capabilities.

The next phase is **debugging and validation** to identify why tests are hanging and bring the pass rate up to 100% for full RISC-V compliance certification.

---

**Document Version**: 1.0
**Last Updated**: 2025-10-12
**Author**: RV1 Project with Claude Code
