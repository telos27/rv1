#!/bin/bash

echo "=== Phase 4 Week 1 Test Results ==="
echo ""

tests=(
  "test_vm_identity_basic"
  "test_sum_disabled"
  "test_vm_identity_multi"
  "test_vm_sum_simple"
  "test_vm_sum_read"
  "test_sum_enabled"
  "test_sum_minimal"
  "test_mxr_basic"
  "test_tlb_basic_hit_miss"
)

passed=0
failed=0

for test in "${tests[@]}"; do
  result=$(timeout 10 bash tools/run_test_by_name.sh "$test" 2>&1 | grep -E "TEST (PASSED|FAILED)")
  if echo "$result" | grep -q "PASSED"; then
    echo "✓ $test"
    ((passed++))
  else
    echo "✗ $test"
    ((failed++))
  fi
done

echo ""
echo "Summary: $passed/9 passed, $failed/9 failed"
