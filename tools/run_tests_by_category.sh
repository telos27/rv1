#!/bin/bash
# run_tests_by_category.sh - Run RISC-V tests by category/extension
# Usage: ./tools/run_tests_by_category.sh <category> [options]
#
# Examples:
#   ./tools/run_tests_by_category.sh m_extension
#   ./tools/run_tests_by_category.sh hazards --verbose
#   ./tools/run_tests_by_category.sh official --extension rv32um
#   ./tools/run_tests_by_category.sh all --timeout 5
#
# Categories:
#   base         - RV32I/RV64I base instructions
#   m            - M extension (multiply/divide)
#   a            - A extension (atomics)
#   f            - F extension (single-precision FP)
#   d            - D extension (double-precision FP)
#   c            - C extension (compressed)
#   csr          - CSR and Zicsr
#   privilege    - Privilege modes (M/S/U)
#   mmu          - Virtual memory/MMU
#   hazards      - Pipeline hazards
#   fp           - All floating-point (F+D)
#   official     - Official compliance tests
#   all          - All custom tests
#
# Options:
#   --extension <ext>  For 'official' category, specify extension (rv32ui, rv32um, etc.)
#   --verbose          Show detailed output
#   --timeout <sec>    Set timeout per test (default: 10)
#   --continue         Continue on failure (don't stop)
#   --help             Show this help message

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default options
CATEGORY=""
VERBOSE=false
TIMEOUT=10
CONTINUE_ON_FAIL=false
EXTENSION=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Show help
show_help() {
  echo "Usage: $0 <category> [options]"
  echo ""
  echo "Run RISC-V tests by category or extension"
  echo ""
  echo "Categories:"
  echo "  base         - RV32I/RV64I base instructions"
  echo "  m            - M extension (multiply/divide)"
  echo "  a            - A extension (atomics)"
  echo "  f            - F extension (single-precision FP)"
  echo "  d            - D extension (double-precision FP)"
  echo "  c            - C extension (compressed)"
  echo "  csr          - CSR and Zicsr"
  echo "  privilege    - Privilege modes (M/S/U)"
  echo "  mmu          - Virtual memory/MMU"
  echo "  hazards      - Pipeline hazards"
  echo "  fp           - All floating-point (F+D)"
  echo "  official     - Official compliance tests"
  echo "  all          - All custom tests"
  echo ""
  echo "Options:"
  echo "  --extension <ext>  For 'official' category, specify extension"
  echo "                     (rv32ui, rv32um, rv32ua, rv32uf, rv32ud, rv32uc)"
  echo "  --verbose          Show detailed output for each test"
  echo "  --timeout <sec>    Set timeout per test (default: 10)"
  echo "  --continue         Continue on failure (don't stop at first failure)"
  echo "  --help             Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0 m"
  echo "  $0 official --extension rv32um"
  echo "  $0 fp --verbose"
  echo "  $0 all --timeout 5 --continue"
  exit 0
}

# Parse arguments
if [ $# -eq 0 ]; then
  show_help
fi

CATEGORY="$1"
shift

while [[ $# -gt 0 ]]; do
  case $1 in
    --extension)
      EXTENSION="$2"
      shift
      ;;
    --verbose)
      VERBOSE=true
      ;;
    --timeout)
      TIMEOUT="$2"
      shift
      ;;
    --continue)
      CONTINUE_ON_FAIL=true
      ;;
    --help)
      show_help
      ;;
    *)
      echo -e "${RED}Error: Unknown option: $1${NC}"
      show_help
      ;;
  esac
  shift
done

# Find tests based on category
find_tests() {
  local category="$1"
  local tests=()

  case "$category" in
    base)
      # Base integer instructions (no extension-specific tests)
      tests=($(find "$PROJECT_ROOT/tests/asm" -name "*.s" | \
        grep -vE "(test_m_|test_div_|test_lr|test_sc|test_amo|test_fp_|test_rvc|test_csr|test_priv|test_s[mr]ode|test_mmu|test_page|test_medeleg)" | \
        xargs -n1 basename | sed 's/\.s$//' || true))
      ;;
    m)
      # M extension tests
      tests=($(find "$PROJECT_ROOT/tests/asm" -name "test_m_*.s" -o -name "test_div_*.s" | \
        xargs -n1 basename | sed 's/\.s$//' || true))
      ;;
    a)
      # A extension tests (LR/SC and AMO)
      tests=($(find "$PROJECT_ROOT/tests/asm" -name "*atomic*.s" -o -name "*lr*.s" -o -name "*sc*.s" -o -name "*amo*.s" | \
        xargs -n1 basename | sed 's/\.s$//' || true))
      ;;
    f)
      # F extension tests (single-precision FP, exclude double-precision)
      tests=($(find "$PROJECT_ROOT/tests/asm" -name "test_fp_*.s" | \
        grep -vE "(fld|fsd|fadd\.d|fsub\.d)" "$PROJECT_ROOT/tests/asm/test_fp_"*.s | \
        xargs -n1 basename | sed 's/\.s$//' || true))
      ;;
    d)
      # D extension tests (double-precision FP)
      # These will have fld, fsd, or double-precision operations
      tests=($(grep -l "fld\|fsd\|fadd\.d\|fsub\.d" "$PROJECT_ROOT/tests/asm"/test_fp_*.s 2>/dev/null | \
        xargs -n1 basename | sed 's/\.s$//' || true))
      ;;
    c)
      # C extension tests (compressed)
      tests=($(find "$PROJECT_ROOT/tests/asm" -name "*rvc*.s" | \
        xargs -n1 basename | sed 's/\.s$//' || true))
      ;;
    csr)
      # CSR tests
      tests=($(find "$PROJECT_ROOT/tests/asm" -name "*csr*.s" | \
        xargs -n1 basename | sed 's/\.s$//' || true))
      ;;
    privilege)
      # Privilege mode tests
      tests=($(find "$PROJECT_ROOT/tests/asm" -name "*priv*.s" -o -name "*smode*.s" -o -name "*supervisor*.s" -o -name "*medeleg*.s" -o -name "*ecall*.s" -o -name "*[ms]ret*.s" | \
        xargs -n1 basename | sed 's/\.s$//' || true))
      ;;
    mmu)
      # MMU/virtual memory tests
      tests=($(find "$PROJECT_ROOT/tests/asm" -name "*mmu*.s" -o -name "*page*.s" -o -name "*vm_*.s" | \
        xargs -n1 basename | sed 's/\.s$//' || true))
      ;;
    hazards)
      # Pipeline hazard tests
      tests=($(find "$PROJECT_ROOT/tests/asm" -name "*hazard*.s" -o -name "*forward*.s" -o -name "*load_use*.s" -o -name "*raw*.s" | \
        xargs -n1 basename | sed 's/\.s$//' || true))
      ;;
    fp)
      # All floating-point tests (F + D)
      tests=($(find "$PROJECT_ROOT/tests/asm" -name "test_fp_*.s" | \
        xargs -n1 basename | sed 's/\.s$//' || true))
      ;;
    official)
      # Official compliance tests
      if [ -z "$EXTENSION" ]; then
        # All official tests
        tests=($(find "$PROJECT_ROOT/tests/official-compliance" -name "*.hex" | \
          xargs -n1 basename | sed 's/\.hex$//' || true))
      else
        # Specific extension
        tests=($(find "$PROJECT_ROOT/tests/official-compliance" -name "${EXTENSION}-*.hex" | \
          xargs -n1 basename | sed 's/\.hex$//' || true))
      fi
      ;;
    all)
      # All custom tests
      tests=($(find "$PROJECT_ROOT/tests/asm" -name "*.s" | \
        xargs -n1 basename | sed 's/\.s$//' || true))
      ;;
    *)
      echo -e "${RED}Error: Unknown category: $category${NC}"
      show_help
      ;;
  esac

  echo "${tests[@]}"
}

# Main execution
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}RISC-V Category Test Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Category: $CATEGORY"
if [ ! -z "$EXTENSION" ]; then
  echo "Extension filter: $EXTENSION"
fi
echo "Timeout: ${TIMEOUT}s per test"
echo ""

# Find tests
TESTS=($(find_tests "$CATEGORY"))

if [ ${#TESTS[@]} -eq 0 ]; then
  echo -e "${YELLOW}Warning: No tests found for category: $CATEGORY${NC}"
  if [ "$CATEGORY" = "official" ] && [ ! -z "$EXTENSION" ]; then
    echo "Try without --extension or check extension name"
  fi
  exit 1
fi

echo "Found ${#TESTS[@]} tests"
echo ""

# Run tests
PASSED=0
FAILED=0
TIMEOUT_COUNT=0
FAILED_TESTS=()

for test in "${TESTS[@]}"; do
  if [ "$VERBOSE" = true ]; then
    echo -e "${CYAN}Running: $test${NC}"
  else
    echo -n "Testing $test... "
  fi

  # Determine if official test
  if [ "$CATEGORY" = "official" ]; then
    OFFICIAL_FLAG="--official"
  else
    OFFICIAL_FLAG=""
  fi

  # Run test
  if [ "$VERBOSE" = true ]; then
    "$SCRIPT_DIR/run_test_by_name.sh" "$test" $OFFICIAL_FLAG --timeout "$TIMEOUT"
    TEST_EXIT=$?
  else
    "$SCRIPT_DIR/run_test_by_name.sh" "$test" $OFFICIAL_FLAG --timeout "$TIMEOUT" &>/dev/null
    TEST_EXIT=$?
  fi

  # Check result
  if [ $TEST_EXIT -eq 0 ]; then
    PASSED=$((PASSED + 1))
    if [ "$VERBOSE" = false ]; then
      echo -e "${GREEN}✓ PASSED${NC}"
    fi
  elif [ $TEST_EXIT -eq 124 ]; then
    # Timeout
    TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
    FAILED_TESTS+=("$test (timeout)")
    if [ "$VERBOSE" = false ]; then
      echo -e "${YELLOW}⏱ TIMEOUT${NC}"
    fi
    if [ "$CONTINUE_ON_FAIL" = false ]; then
      break
    fi
  else
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("$test")
    if [ "$VERBOSE" = false ]; then
      echo -e "${RED}✗ FAILED${NC}"
    fi
    if [ "$CONTINUE_ON_FAIL" = false ]; then
      break
    fi
  fi
done

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Category: $CATEGORY"
echo "Total tests: ${#TESTS[@]}"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${YELLOW}Timeout: $TIMEOUT_COUNT${NC}"
echo ""

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
  echo -e "${RED}Failed tests:${NC}"
  for test in "${FAILED_TESTS[@]}"; do
    echo "  - $test"
  done
  echo ""
fi

# Calculate percentage
TOTAL_RUN=$((PASSED + FAILED + TIMEOUT_COUNT))
if [ $TOTAL_RUN -gt 0 ]; then
  PASS_PERCENT=$(( (PASSED * 100) / TOTAL_RUN ))
  echo "Pass rate: ${PASS_PERCENT}% ($PASSED/$TOTAL_RUN)"
fi

# Exit code
if [ $FAILED -eq 0 ] && [ $TIMEOUT_COUNT -eq 0 ]; then
  echo -e "${GREEN}✓ All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}✗ Some tests failed${NC}"
  exit 1
fi
