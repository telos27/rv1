#!/bin/bash
# run_test_by_name.sh - Run individual RISC-V tests by name
# Usage: ./tools/run_test_by_name.sh <test_name> [options]
#
# Examples:
#   ./tools/run_test_by_name.sh fibonacci
#   ./tools/run_test_by_name.sh rv32ui-p-add --official
#   ./tools/run_test_by_name.sh test_fp_basic --debug --waves
#   ./tools/run_test_by_name.sh test_m_basic --timeout 30
#
# Options:
#   --official       Run official compliance test
#   --debug          Enable debug output
#   --waves          Generate waveforms (VCD)
#   --timeout <sec>  Set timeout in seconds (default: 10)
#   --rv64           Use RV64 configuration (default: RV32)
#   --help           Show this help message

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default options
TEST_NAME=""
OFFICIAL=false
DEBUG=false
WAVES=false
TIMEOUT=10
XLEN=${XLEN:-32}  # Respect XLEN environment variable, default to 32

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Show help
show_help() {
  echo "Usage: $0 <test_name> [options]"
  echo ""
  echo "Run individual RISC-V tests by name"
  echo ""
  echo "Options:"
  echo "  --official       Run official compliance test"
  echo "  --debug          Enable debug output (DEBUG_CORE)"
  echo "  --waves          Generate waveforms (VCD files)"
  echo "  --timeout <sec>  Set timeout in seconds (default: 10)"
  echo "  --rv64           Use RV64 configuration (default: RV32)"
  echo "  --help           Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0 fibonacci"
  echo "  $0 rv32ui-p-add --official"
  echo "  $0 test_fp_basic --debug --waves"
  echo "  $0 test_m_basic --timeout 30"
  echo ""
  echo "Custom tests are searched in:"
  echo "  - tests/asm/*.s (current structure)"
  echo "  - tests/custom/**/*.s (future structure)"
  echo ""
  echo "Official tests are searched in:"
  echo "  - tests/official-compliance/*.hex"
  exit 0
}

# Parse arguments
if [ $# -eq 0 ]; then
  show_help
fi

TEST_NAME="$1"
shift

while [[ $# -gt 0 ]]; do
  case $1 in
    --official)
      OFFICIAL=true
      ;;
    --debug)
      DEBUG=true
      ;;
    --waves)
      WAVES=true
      ;;
    --timeout)
      TIMEOUT="$2"
      shift
      ;;
    --rv64)
      XLEN=64
      ;;
    --help)
      show_help
      ;;
    *)
      echo -e "${RED}Error: Unknown option: $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
  shift
done

# Check test name
if [ -z "$TEST_NAME" ]; then
  echo -e "${RED}Error: Test name required${NC}"
  show_help
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}RISC-V Test Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Test: $TEST_NAME"
echo "XLEN: $XLEN"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Find and prepare test file
if [ "$OFFICIAL" = true ]; then
  # Search official compliance tests
  echo -e "${YELLOW}[1/3] Searching official tests...${NC}"
  HEX_FILE=$(find "$PROJECT_ROOT/tests/official-compliance" -name "${TEST_NAME}*.hex" 2>/dev/null | head -1)

  if [ -z "$HEX_FILE" ] || [ ! -f "$HEX_FILE" ]; then
    echo -e "${RED}Error: Official test not found: $TEST_NAME${NC}"
    echo "Available official tests:"
    find "$PROJECT_ROOT/tests/official-compliance" -name "*.hex" -print0 2>/dev/null | xargs -0 -n1 basename 2>/dev/null | head -10
    exit 1
  fi

  echo "Found: $HEX_FILE"
else
  # Search custom assembly tests
  echo -e "${YELLOW}[1/3] Searching custom tests...${NC}"

  # Try new structure first (tests/custom/**)
  ASM_FILE=$(find "$PROJECT_ROOT/tests/custom" -name "${TEST_NAME}.s" 2>/dev/null | head -1)

  # Fall back to old location (tests/asm/)
  if [ -z "$ASM_FILE" ] || [ ! -f "$ASM_FILE" ]; then
    ASM_FILE="$PROJECT_ROOT/tests/asm/${TEST_NAME}.s"
  fi

  # Check if file exists
  if [ ! -f "$ASM_FILE" ]; then
    echo -e "${RED}Error: Test not found: $TEST_NAME${NC}"
    echo "Searched in:"
    echo "  - tests/custom/**/*.s"
    echo "  - tests/asm/*.s"
    echo ""
    echo "Available tests (first 10):"
    find "$PROJECT_ROOT/tests/asm" -name "*.s" -print0 2>/dev/null | xargs -0 -n1 basename 2>/dev/null | sed 's/\.s$//' | head -10
    exit 1
  fi

  echo "Found: $ASM_FILE"

  # Build test (assemble to hex)
  echo ""
  echo -e "${YELLOW}Building test...${NC}"

  # Determine architecture flags
  MARCH="rv${XLEN}imafc"
  MABI="ilp32f"
  if [ "$XLEN" = "64" ]; then
    MABI="lp64f"
  fi

  # Check if test needs D extension
  if grep -q "fld\|fsd\|fadd\.d\|fsub\.d" "$ASM_FILE" 2>/dev/null; then
    MARCH="${MARCH}d"
    MABI="${MABI/f/d}"
  fi

  # Check if test needs C extension
  if grep -q "c\.\|\.rvc\|CONFIG_RV32IMC" "$ASM_FILE" 2>/dev/null || [[ "$TEST_NAME" == *"rvc"* ]]; then
    MARCH="${MARCH}_zicsr"
  fi

  "$SCRIPT_DIR/asm_to_hex.sh" "$ASM_FILE" -march="$MARCH" -mabi="$MABI" 2>&1 | grep -E "(Error|Success|✓)"

  HEX_FILE="${ASM_FILE%.s}.hex"

  if [ ! -f "$HEX_FILE" ]; then
    echo -e "${RED}Error: Failed to build hex file${NC}"
    exit 1
  fi
fi

# Determine configuration flags
echo ""
echo -e "${YELLOW}[2/3] Compiling simulation...${NC}"

CONFIG_FLAG="-DCONFIG_RV32I"
TESTBENCH="$PROJECT_ROOT/tb/integration/tb_core_pipelined.v"
SIM_FILE="$PROJECT_ROOT/sim/${TEST_NAME}.vvp"
WAVES_FILE="$PROJECT_ROOT/sim/waves/${TEST_NAME}.vcd"

if [ "$XLEN" = "64" ]; then
  CONFIG_FLAG="-DCONFIG_RV64I"
  TESTBENCH="$PROJECT_ROOT/tb/integration/tb_core_pipelined_rv64.v"
fi

# Check if test needs C extension configuration
if [[ "$TEST_NAME" == *"rvc"* ]] || [[ "$TEST_NAME" == *"rv32uc"* ]]; then
  CONFIG_FLAG="-DCONFIG_RV32IMC"
fi

# Build iverilog flags
IVERILOG_FLAGS="-g2012 -I$PROJECT_ROOT/rtl $CONFIG_FLAG -DMEM_FILE=\"$HEX_FILE\""

if [ "$OFFICIAL" = true ]; then
  IVERILOG_FLAGS="$IVERILOG_FLAGS -DCOMPLIANCE_TEST"
fi

if [ "$DEBUG" = true ]; then
  IVERILOG_FLAGS="$IVERILOG_FLAGS -DDEBUG_CORE -DDEBUG_FPU -DDEBUG_M"
fi

# Create output directories
mkdir -p "$PROJECT_ROOT/sim"
mkdir -p "$PROJECT_ROOT/sim/waves"

# Compile simulation
iverilog $IVERILOG_FLAGS \
  -o "$SIM_FILE" \
  "$TESTBENCH" \
  "$PROJECT_ROOT/rtl/core"/*.v \
  "$PROJECT_ROOT/rtl/memory"/*.v 2>&1 | grep -v "warning: choosing typ"

if [ ${PIPESTATUS[0]} -ne 0 ]; then
  echo -e "${RED}Error: Compilation failed${NC}"
  exit 1
fi

echo "✓ Compilation successful"

# Run simulation
echo ""
echo -e "${YELLOW}[3/3] Running simulation...${NC}"
echo "----------------------------------------"

# Run with timeout
if [ "$WAVES" = true ]; then
  # Keep VCD output messages
  timeout ${TIMEOUT}s vvp "$SIM_FILE"
else
  # Filter out VCD messages for cleaner output
  timeout ${TIMEOUT}s vvp "$SIM_FILE" 2>&1 | grep -v "VCD info:"
fi

EXIT_CODE=${PIPESTATUS[0]}

echo "----------------------------------------"
echo ""

# Check result
if [ $EXIT_CODE -eq 124 ]; then
  echo -e "${RED}✗ Test TIMED OUT after ${TIMEOUT}s${NC}"
  echo ""
  echo "Hint: Try increasing timeout with --timeout <seconds>"
  exit 1
elif [ $EXIT_CODE -ne 0 ]; then
  echo -e "${RED}✗ Test FAILED (exit code: $EXIT_CODE)${NC}"
  echo ""
  if [ "$DEBUG" = false ]; then
    echo "Hint: Try running with --debug for more information"
  fi
  if [ "$WAVES" = false ]; then
    echo "Hint: Try running with --waves to generate waveforms"
  fi
  exit 1
else
  echo -e "${GREEN}✓ Test PASSED: $TEST_NAME${NC}"
  echo ""
  if [ "$WAVES" = true ]; then
    echo "Waveform saved to: $WAVES_FILE"
    echo "View with: gtkwave $WAVES_FILE"
  fi
fi
