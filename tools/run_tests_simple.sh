#!/bin/bash
# Simple test runner for RISC-V compliance tests

passed=0
failed=0
failed_tests=""

echo "Running 42 RV32UI Compliance Tests..."
echo ""

for hex in tests/riscv-compliance/rv32ui-p-*.hex; do
  name=$(basename "$hex" .hex)

  printf "%-25s ... " "$name"

  # Compile
  iverilog -g2012 -DCOMPLIANCE_TEST -DMEM_FILE="\"$hex\"" \
    -o "sim/$name.vvp" rtl/core/*.v rtl/memory/*.v tb/integration/tb_core.v 2>&1 | grep -v warning > /dev/null

  # Run
  result=$(vvp "sim/$name.vvp" 2>&1)

  if echo "$result" | grep -q "RISC-V COMPLIANCE TEST PASSED"; then
    echo "✓ PASSED"
    passed=$((passed + 1))
  else
    echo "✗ FAILED"
    failed=$((failed + 1))
    failed_tests="$failed_tests\n  - $name"
  fi
done

echo ""
echo "========================================="
echo "Results: $passed passed, $failed failed"
pass_rate=$((passed * 100 / (passed + failed)))
echo "Pass rate: ${pass_rate}%"

if [ $failed -gt 0 ]; then
  echo ""
  echo "Failed tests:$failed_tests"
fi
