#!/bin/bash
# check_env.sh - Check development environment setup

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "======================================"
echo "  RV1 Environment Check"
echo "======================================"
echo ""

# Function to check command
check_cmd() {
    local cmd=$1
    local name=$2
    local required=$3

    echo -n "Checking $name... "

    if command -v "$cmd" &> /dev/null; then
        VERSION=$($cmd --version 2>&1 | head -1)
        echo -e "${GREEN}✓${NC} Found: $VERSION"
        return 0
    else
        if [ "$required" = "required" ]; then
            echo -e "${RED}✗${NC} Not found (REQUIRED)"
            return 1
        else
            echo -e "${YELLOW}⚠${NC} Not found (optional)"
            return 0
        fi
    fi
}

ALL_GOOD=0

echo "Required Tools:"
echo "---------------"
check_cmd "iverilog" "Icarus Verilog" "required" || ALL_GOOD=1
check_cmd "vvp" "VVP (Verilog simulator)" "required" || ALL_GOOD=1

echo ""
echo "RISC-V Toolchain:"
echo "-----------------"
RISCV_PREFIX=${RISCV_PREFIX:-riscv32-unknown-elf-}
check_cmd "${RISCV_PREFIX}gcc" "RISC-V GCC" "required" || ALL_GOOD=1
check_cmd "${RISCV_PREFIX}as" "RISC-V Assembler" "required" || ALL_GOOD=1
check_cmd "${RISCV_PREFIX}ld" "RISC-V Linker" "required" || ALL_GOOD=1
check_cmd "${RISCV_PREFIX}objcopy" "RISC-V Objcopy" "required" || ALL_GOOD=1
check_cmd "${RISCV_PREFIX}objdump" "RISC-V Objdump" "required" || ALL_GOOD=1

echo ""
echo "Optional Tools:"
echo "---------------"
check_cmd "gtkwave" "GTKWave (waveform viewer)" "optional"
check_cmd "verilator" "Verilator (fast simulator)" "optional"
check_cmd "yosys" "Yosys (synthesis)" "optional"
check_cmd "spike" "Spike (RISC-V ISA simulator)" "optional"

echo ""
echo "Directory Structure:"
echo "--------------------"

DIRS=("rtl/core" "rtl/memory" "tb/unit" "tb/integration" "tests/asm" "tests/vectors" "sim" "docs")

for dir in "${DIRS[@]}"; do
    echo -n "Checking $dir... "
    if [ -d "$dir" ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC} Missing"
        ALL_GOOD=1
    fi
done

echo ""
echo "Key Files:"
echo "----------"

FILES=("Makefile" "tests/linker.ld" "README.md" "ARCHITECTURE.md" "PHASES.md" "CLAUDE.md")

for file in "${FILES[@]}"; do
    echo -n "Checking $file... "
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC} Missing"
        ALL_GOOD=1
    fi
done

echo ""
echo "======================================"

if [ $ALL_GOOD -eq 0 ]; then
    echo -e "${GREEN}Environment setup complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review documentation: README.md, ARCHITECTURE.md, PHASES.md"
    echo "  2. Start implementing Phase 1: make test-alu"
    echo "  3. Write test programs in: tests/asm/"
    echo ""
    exit 0
else
    echo -e "${RED}Environment setup incomplete!${NC}"
    echo ""
    echo "Required tools installation:"
    echo ""
    echo "Icarus Verilog:"
    echo "  Ubuntu/Debian: sudo apt-get install iverilog"
    echo "  macOS: brew install icarus-verilog"
    echo ""
    echo "RISC-V Toolchain:"
    echo "  Pre-built: https://github.com/riscv-collab/riscv-gnu-toolchain/releases"
    echo "  Or build from source: https://github.com/riscv-collab/riscv-gnu-toolchain"
    echo ""
    echo "GTKWave (optional):"
    echo "  Ubuntu/Debian: sudo apt-get install gtkwave"
    echo "  macOS: brew install gtkwave"
    echo ""
    exit 1
fi
