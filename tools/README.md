# Tools Directory

Helper scripts for building, testing, and verifying the RV1 processor.

## Scripts

### check_env.sh
Check development environment setup and tool availability.

```bash
./tools/check_env.sh
```

Checks for:
- Icarus Verilog (required)
- RISC-V toolchain (required)
- Optional tools (GTKWave, Verilator, Yosys, Spike)
- Directory structure
- Key configuration files

### assemble.sh
Assemble RISC-V assembly files to hex format for simulation.

```bash
./tools/assemble.sh <assembly_file.s> [output_hex]

# Examples:
./tools/assemble.sh tests/asm/fibonacci.s
./tools/assemble.sh tests/asm/fibonacci.s tests/vectors/fib.hex
```

Produces:
- `.hex` file for Verilog simulation
- `.elf` executable
- `.dump` disassembly for reference

### run_test.sh
Run a single test program on the core.

```bash
./tools/run_test.sh <test_name> [timeout_cycles]

# Examples:
./tools/run_test.sh fibonacci
./tools/run_test.sh fibonacci 50000
```

Output:
- Test pass/fail status
- Simulation log in `sim/<test>.log`
- Waveform in `sim/waves/<test>.vcd`

### run_all_tests.sh
Run all test programs in `tests/vectors/`.

```bash
./tools/run_all_tests.sh
```

Provides:
- Progress indication for each test
- Summary of passed/failed tests
- Colorized output

## Usage Workflow

### 1. Check Environment
```bash
./tools/check_env.sh
```

### 2. Write Assembly Test
```bash
cat > tests/asm/mytest.s << 'EOF'
.text
.globl _start
_start:
    li x10, 42
    ebreak
EOF
```

### 3. Assemble
```bash
./tools/assemble.sh tests/asm/mytest.s
```

### 4. Run Test
```bash
./tools/run_test.sh mytest
```

### 5. Debug with Waveforms
```bash
gtkwave sim/waves/mytest.vcd
```

## Environment Variables

### RISCV_PREFIX
Override default RISC-V toolchain prefix.

```bash
export RISCV_PREFIX=riscv64-unknown-elf-
./tools/assemble.sh tests/asm/test.s
```

Default: `riscv32-unknown-elf-`

## Adding New Scripts

When adding new tools:

1. Use bash shebang: `#!/bin/bash`
2. Add error handling: `set -e`
3. Provide help text for arguments
4. Make executable: `chmod +x tools/script.sh`
5. Document here in README

## Common Issues

### RISC-V Toolchain Not Found

Install pre-built toolchain:
```bash
# Download from: https://github.com/riscv-collab/riscv-gnu-toolchain/releases
# Extract and add to PATH:
export PATH=$PATH:/path/to/riscv/bin
```

Or set custom prefix:
```bash
export RISCV_PREFIX=riscv64-linux-gnu-
```

### Icarus Verilog Not Found

Install:
```bash
# Ubuntu/Debian
sudo apt-get install iverilog

# macOS
brew install icarus-verilog
```

### Permission Denied

Make scripts executable:
```bash
chmod +x tools/*.sh
```
