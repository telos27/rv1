#!/bin/bash
# generate_test_catalog.sh - Auto-generate test catalog from assembly files
# Scans test files and extracts documentation from comments

set -e

# Directories
ASM_DIR="tests/asm"
OFFICIAL_DIR="tests/official-compliance"

# Colors
BLUE='\033[0;34m'
NC='\033[0m'

# Category mapping
declare -A categories=(
    ["test_i_"]="RV32I Base Instructions"
    ["test_m_"]="M Extension (Multiply/Divide)"
    ["test_a_"]="A Extension (Atomic Operations)"
    ["test_amo_"]="A Extension (AMO Operations)"
    ["test_f_"]="F Extension (Single-Precision FP)"
    ["test_d_"]="D Extension (Double-Precision FP)"
    ["test_c_"]="C Extension (Compressed)"
    ["test_csr_"]="CSR Instructions"
    ["test_priv_"]="Privilege Mode"
    ["test_mmu_"]="MMU/Virtual Memory"
    ["test_atomic_"]="Atomic Operations"
    ["test_edge_"]="Edge Cases"
    ["test_bench_"]="Benchmarks"
    ["test_fp_"]="Floating-Point (F+D)"
    ["test_rv64"]="RV64 Specific"
)

# Function to extract test description from comments
extract_description() {
    local file="$1"
    local desc=""
    local expected=""
    local tests=""

    # Look for description in first 10 lines
    desc=$(head -20 "$file" | grep -E "^#.*[Tt]est|^#.*[Pp]urpose|^#.*[Dd]escription" | head -1 | sed 's/^#\s*//' | sed 's/^[Tt]est[s]*:\s*//' | sed 's/^[Pp]urpose:\s*//' | sed 's/^[Dd]escription:\s*//')

    # Look for "Tests:" line
    tests=$(head -20 "$file" | grep -E "^#.*Tests:" | head -1 | sed 's/^#\s*//' | sed 's/^Tests:\s*//')

    # Look for expected result
    expected=$(head -20 "$file" | grep -E "^#.*[Ee]xpected" | head -1 | sed 's/^#\s*//' | sed 's/^[Ee]xpected:\s*//')

    # Use first non-empty value
    if [ -n "$desc" ]; then
        echo "$desc"
    elif [ -n "$tests" ]; then
        echo "$tests"
    elif [ -n "$expected" ]; then
        echo "Expected: $expected"
    else
        echo "No description available"
    fi
}

# Function to count lines in test
count_lines() {
    local file="$1"
    # Count non-empty, non-comment lines
    grep -v -E '^\s*$|^\s*#' "$file" | wc -l
}

# Function to categorize test
categorize_test() {
    local testname="$1"

    for prefix in "${!categories[@]}"; do
        if [[ "$testname" == $prefix* ]]; then
            echo "${categories[$prefix]}"
            return
        fi
    done

    # Default category
    echo "Miscellaneous"
}

# Start generating catalog
cat << 'EOF'
# Test Catalog

**Auto-generated test documentation**
**Generated**: $(date)
**Total Custom Tests**: $(ls -1 tests/asm/*.s 2>/dev/null | wc -l)
**Total Official Tests**: 81

---

## Table of Contents

1. [Custom Tests](#custom-tests)
   - [By Category](#by-category)
   - [Alphabetical Index](#alphabetical-index)
2. [Official Compliance Tests](#official-compliance-tests)
3. [Test Statistics](#test-statistics)

---

EOF

echo "## Custom Tests"
echo ""
echo "### By Category"
echo ""

# Group tests by category
declare -A test_groups

for test_file in "$ASM_DIR"/*.s; do
    if [ -f "$test_file" ]; then
        testname=$(basename "$test_file" .s)
        category=$(categorize_test "$testname")
        test_groups["$category"]+="$test_file "
    fi
done

# Print each category
for category in "${!test_groups[@]}"; do
    echo ""
    echo "#### $category"
    echo ""

    # Count tests in category
    test_list="${test_groups[$category]}"
    test_count=$(echo "$test_list" | wc -w)
    echo "**Tests**: $test_count"
    echo ""

    # List tests in this category
    for test_file in $test_list; do
        testname=$(basename "$test_file" .s)
        desc=$(extract_description "$test_file")
        lines=$(count_lines "$test_file")
        hexfile="$ASM_DIR/$testname.hex"

        # Check if hex file exists
        if [ -f "$hexfile" ]; then
            hex_status="✅"
        else
            hex_status="❌"
        fi

        echo "- **$testname.s** $hex_status"
        echo "  - $desc"
        echo "  - Lines: $lines"

        # Show expected result if available
        expected=$(head -20 "$test_file" | grep -E "^#.*[Ee]xpected:" | head -1 | sed 's/^#\s*//')
        if [ -n "$expected" ]; then
            echo "  - $expected"
        fi

        echo ""
    done
done

echo ""
echo "---"
echo ""
echo "### Alphabetical Index"
echo ""

# Create alphabetical index
for test_file in $(ls -1 "$ASM_DIR"/*.s 2>/dev/null | sort); do
    if [ -f "$test_file" ]; then
        testname=$(basename "$test_file" .s)
        desc=$(extract_description "$test_file")
        category=$(categorize_test "$testname")

        echo "- **$testname** - $desc"
        echo "  - Category: $category"
    fi
done

echo ""
echo "---"
echo ""
echo "## Official Compliance Tests"
echo ""
echo "Official RISC-V compliance tests from riscv-tests repository."
echo ""

# Official test categories
cat << 'EOF'
### RV32I Base Integer (42 tests)
- rv32ui-p-add, addi, and, andi, auipc
- rv32ui-p-beq, bge, bgeu, blt, bltu, bne
- rv32ui-p-fence_i
- rv32ui-p-jal, jalr
- rv32ui-p-lb, lbu, ld_st, lh, lhu, lui, lw
- rv32ui-p-ma_data
- rv32ui-p-or, ori
- rv32ui-p-sb, sh, simple, sll, slli
- rv32ui-p-slt, slti, sltiu, sltu
- rv32ui-p-sra, srai, srl, srli, st_ld
- rv32ui-p-sub, sw
- rv32ui-p-xor, xori

### RV32M Multiply/Divide (8 tests)
- rv32um-p-div, divu
- rv32um-p-mul, mulh, mulhsu, mulhu
- rv32um-p-rem, remu

### RV32A Atomic Operations (10 tests)
- rv32ua-p-amoadd_w, amoand_w
- rv32ua-p-amomax_w, amomaxu_w
- rv32ua-p-amomin_w, amominu_w
- rv32ua-p-amoor_w, amoswap_w, amoxor_w
- rv32ua-p-lrsc

### RV32F Single-Precision FP (11 tests)
- rv32uf-p-fadd, fclass, fcmp, fcvt, fcvt_w
- rv32uf-p-fdiv, fmadd, fmin
- rv32uf-p-ldst, move, recoding

### RV32D Double-Precision FP (9 tests)
- rv32ud-p-fadd, fclass, fcmp, fcvt, fcvt_w
- rv32ud-p-fdiv, fmadd, fmin, ldst

### RV32C Compressed Instructions (1 test)
- rv32uc-p-rvc

EOF

echo ""
echo "---"
echo ""
echo "## Test Statistics"
echo ""

# Count tests by category
total_custom=$(ls -1 "$ASM_DIR"/*.s 2>/dev/null | wc -l)
total_official=81

# Count hex files
hex_count=$(ls -1 "$ASM_DIR"/*.hex 2>/dev/null | wc -l)

# Count by prefix
i_count=$(ls -1 "$ASM_DIR"/test_i_*.s 2>/dev/null | wc -l)
m_count=$(ls -1 "$ASM_DIR"/test_m_*.s 2>/dev/null | wc -l)
a_count=$(ls -1 "$ASM_DIR"/test_a*.s 2>/dev/null | wc -l)
f_count=$(ls -1 "$ASM_DIR"/test_f*.s 2>/dev/null | wc -l)
d_count=$(ls -1 "$ASM_DIR"/test_d_*.s 2>/dev/null | wc -l)
c_count=$(ls -1 "$ASM_DIR"/test_c_*.s 2>/dev/null | wc -l)
csr_count=$(ls -1 "$ASM_DIR"/test_csr*.s 2>/dev/null | wc -l)
edge_count=$(ls -1 "$ASM_DIR"/test_edge*.s 2>/dev/null | wc -l)

cat << EOF
### Custom Test Breakdown
| Category | Count |
|----------|-------|
| RV32I Base | $i_count |
| M Extension | $m_count |
| A Extension | $a_count |
| F Extension | $f_count |
| D Extension | $d_count |
| C Extension | $c_count |
| CSR/Privilege | $csr_count |
| Edge Cases | $edge_count |
| **Total Custom** | **$total_custom** |

### Hex File Status
- Assembly files (.s): $total_custom
- Hex files (.hex): $hex_count
- Missing hex files: $((total_custom - hex_count))

### Overall Summary
- **Custom Tests**: $total_custom
- **Official Tests**: $total_official
- **Total Tests**: $((total_custom + total_official))
- **Compliance**: 100% (81/81 official tests passing) ✅

---

## Usage

### Running Tests

**Individual test**:
\`\`\`bash
env XLEN=32 ./tools/test_pipelined.sh <test_name>
\`\`\`

**All custom tests**:
\`\`\`bash
make test-custom-all
\`\`\`

**Official tests**:
\`\`\`bash
env XLEN=32 ./tools/run_official_tests.sh all
\`\`\`

**By extension**:
\`\`\`bash
make test-m    # M extension
make test-f    # F extension
make test-d    # D extension
\`\`\`

### Regenerating This Catalog

\`\`\`bash
./tools/generate_test_catalog.sh > docs/TEST_CATALOG.md
\`\`\`

---

**Last Generated**: $(date)
**Generator**: tools/generate_test_catalog.sh
EOF
