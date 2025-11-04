#!/bin/bash
# audit_rv64.sh - Audit RTL files for RV64 compatibility
# Finds hardcoded 32-bit widths that should use XLEN parameter

echo "=== RV64 Compatibility Audit ==="
echo ""

echo "1. Checking for hardcoded [31:0] widths (excluding instructions and comments)..."
echo "   (Instructions are always 32-bit, so those are OK)"
echo ""

grep -rn "\[31:0\]" rtl/core/*.v \
  | grep -v "instruction" \
  | grep -v "//.*\[31:0\]" \
  | grep -v "NOP.*=.*32'h" \
  | grep -v "\* \[31:0\]" \
  | sort

echo ""
echo "2. Checking for hardcoded 32'h or 32'd constants..."
echo ""

grep -rn "32'[hdb]" rtl/core/*.v \
  | grep -v "//.*32'[hdb]" \
  | grep -v "NOP.*32'h" \
  | grep -v "instruction.*32'h" \
  | head -20

echo ""
echo "3. Checking for {{32{" sign-extension patterns..."
echo ""

grep -rn "{{32{" rtl/core/*.v

echo ""
echo "4. Checking for module parameters without XLEN..."
echo ""

grep -rn "^module " rtl/core/*.v | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  if ! grep -q "parameter XLEN" "$file"; then
    echo "$line - NO XLEN PARAMETER"
  fi
done

echo ""
echo "=== Audit Complete ==="
