#!/bin/bash

# FPU Compliance Test Diagnostic Runner
# Runs all RV32UF tests with detailed failure analysis

set -e

TESTS=(
    "fadd"
    "fclass"
    "fcmp"
    "fcvt"
    "fcvt_w"
    "fdiv"
    "fmadd"
    "fmin"
    "ldst"
    "move"
    "recoding"
)

TIMEOUT=${TIMEOUT:-120}
TEST_DIR="tests/official-compliance"
SIM_DIR="sim"
RTL_DIRS="-I rtl/"

mkdir -p "$SIM_DIR"
mkdir -p "$SIM_DIR/fpu_reports"

echo "==============================================="
echo "RV32UF Compliance Test Diagnostic Report"
echo "Date: $(date)"
echo "Timeout: ${TIMEOUT}s per test"
echo "==============================================="
echo ""

PASS_COUNT=0
FAIL_COUNT=0
TIMEOUT_COUNT=0

# Results array
declare -A RESULTS
declare -A GP_VALUES
declare -A CYCLES
declare -A STATUS_MSGS

for test in "${TESTS[@]}"; do
    test_name="rv32uf-p-$test"
    hex_file="$TEST_DIR/$test_name.hex"
    vvp_file="$SIM_DIR/${test_name}_diag.vvp"
    log_file="$SIM_DIR/fpu_reports/${test_name}.log"

    echo "=== Testing: $test_name ==="

    if [ ! -f "$hex_file" ]; then
        echo "  ❌ SKIP: Hex file not found"
        RESULTS[$test]="SKIP"
        continue
    fi

    # Compile testbench
    echo "  Compiling..."
    if ! iverilog -g2012 $RTL_DIRS \
        -DCOMPLIANCE_TEST \
        -DMEM_FILE=\"$hex_file\" \
        -o "$vvp_file" \
        rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v \
        2>&1 | tee "$log_file.compile" > /dev/null; then
        echo "  ❌ COMPILE FAILED"
        RESULTS[$test]="COMPILE_FAIL"
        continue
    fi

    # Run simulation with timeout
    echo "  Running simulation (timeout: ${TIMEOUT}s)..."
    if timeout ${TIMEOUT}s vvp "$vvp_file" > "$log_file" 2>&1; then
        # Check for test completion
        if grep -q "TEST PASSED" "$log_file"; then
            echo "  ✅ PASSED"
            RESULTS[$test]="PASS"
            PASS_COUNT=$((PASS_COUNT + 1))

            # Extract cycle count
            cycle=$(grep -oP "Cycles: \K\d+" "$log_file" | tail -1)
            CYCLES[$test]=$cycle
            STATUS_MSGS[$test]="Completed in $cycle cycles"

        elif grep -q "TEST FAILED" "$log_file"; then
            echo "  ❌ FAILED"
            RESULTS[$test]="FAIL"
            FAIL_COUNT=$((FAIL_COUNT + 1))

            # Extract gp register value (test number that failed)
            gp_val=$(grep -oP "gp = 0x[0-9a-f]+" "$log_file" | tail -1 | grep -oP "0x\K[0-9a-f]+")
            if [ -n "$gp_val" ]; then
                test_num=$((16#$gp_val))
                GP_VALUES[$test]=$test_num
                STATUS_MSGS[$test]="Failed at test #$test_num"
                echo "     Failed at test #$test_num (gp=0x$gp_val)"
            fi

            # Extract cycle count
            cycle=$(grep -oP "Cycles: \K\d+" "$log_file" | tail -1)
            CYCLES[$test]=$cycle

        else
            echo "  ⚠️  NO RESULT (simulation ended without PASS/FAIL)"
            RESULTS[$test]="NO_RESULT"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            STATUS_MSGS[$test]="Simulation ended without clear result"
        fi
    else
        exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "  ⏱️  TIMEOUT (>${TIMEOUT}s)"
            RESULTS[$test]="TIMEOUT"
            TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
            STATUS_MSGS[$test]="Timeout after ${TIMEOUT}s"
        else
            echo "  ❌ RUNTIME ERROR (exit code: $exit_code)"
            RESULTS[$test]="ERROR"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            STATUS_MSGS[$test]="Runtime error (exit $exit_code)"
        fi
    fi

    echo ""
done

# Generate summary report
echo ""
echo "==============================================="
echo "SUMMARY REPORT"
echo "==============================================="
echo ""
echo "Total Tests:    ${#TESTS[@]}"
echo "Passed:         $PASS_COUNT ($(( PASS_COUNT * 100 / ${#TESTS[@]} ))%)"
echo "Failed:         $FAIL_COUNT"
echo "Timeouts:       $TIMEOUT_COUNT"
echo ""

echo "==============================================="
echo "DETAILED RESULTS"
echo "==============================================="
printf "%-15s %-12s %-10s %s\n" "TEST" "STATUS" "CYCLES" "DETAILS"
echo "---------------------------------------------------------------"

for test in "${TESTS[@]}"; do
    status=${RESULTS[$test]:-"UNKNOWN"}
    cycles=${CYCLES[$test]:-"N/A"}
    details=${STATUS_MSGS[$test]:-"No details"}

    # Format status with color indicator
    case $status in
        PASS)
            status_str="✅ PASS"
            ;;
        FAIL)
            status_str="❌ FAIL"
            ;;
        TIMEOUT)
            status_str="⏱️  TIMEOUT"
            ;;
        *)
            status_str="⚠️  $status"
            ;;
    esac

    printf "%-15s %-12s %-10s %s\n" "$test" "$status_str" "$cycles" "$details"
done

echo ""
echo "==============================================="
echo "FAILURE ANALYSIS"
echo "==============================================="
echo ""

# Group failures by test number
echo "Failed tests grouped by failure point:"
echo ""

for test in "${TESTS[@]}"; do
    if [ "${RESULTS[$test]}" = "FAIL" ] && [ -n "${GP_VALUES[$test]}" ]; then
        test_num=${GP_VALUES[$test]}
        echo "  $test: Failed at test #$test_num"
    fi
done

echo ""
echo "==============================================="
echo "NEXT STEPS RECOMMENDATIONS"
echo "==============================================="
echo ""

# Find tests that are closest to passing (highest test number before failure)
echo "Tests ordered by progress (closest to passing first):"
echo ""

# Create sorted list
declare -A test_progress
for test in "${TESTS[@]}"; do
    if [ "${RESULTS[$test]}" = "FAIL" ]; then
        test_num=${GP_VALUES[$test]:-0}
        test_progress[$test]=$test_num
    fi
done

# Sort and display
for test in $(for t in "${!test_progress[@]}"; do echo "$t:${test_progress[$t]}"; done | sort -t: -k2 -rn | cut -d: -f1); do
    test_num=${test_progress[$test]}
    echo "  $test: $test_num tests passed before failure"
done

echo ""
echo "Report saved to: $SIM_DIR/fpu_reports/"
echo "Individual logs: $SIM_DIR/fpu_reports/rv32uf-p-*.log"
echo ""
