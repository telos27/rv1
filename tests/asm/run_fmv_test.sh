#!/bin/bash
# Quick test script for FMV.X.W instruction

echo "=== Running FMV.X.W Test ==="

# Run simulation
vvp ../../sim/rv_core_pipelined.vvp +IMEM=test_fmv_xw.hex +CYCLES=100 +VERBOSE=0 > test_fmv_xw.log 2>&1

# Check results
if grep -q "a0 = 0000002a" test_fmv_xw.log; then
    echo "✅ TEST PASSED: a0 = 42 (success marker)"
    tail -50 test_fmv_xw.log | grep "a[0-3] ="
    exit 0
elif grep -q "a0 = 00000000" test_fmv_xw.log; then
    echo "❌ TEST FAILED: a0 = 0 (failure marker)"
    tail -50 test_fmv_xw.log | grep "a[0-3] ="
    exit 1
else
    echo "⚠️ TEST INCONCLUSIVE: Could not find result"
    tail -30 test_fmv_xw.log
    exit 2
fi
