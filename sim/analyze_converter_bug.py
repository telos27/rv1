#!/usr/bin/env python3

# Analyze the converter bug for test #2: fcvt.w.s -1.1

fp_hex = 0xbf8ccccd
sign = (fp_hex >> 31) & 1
exp = (fp_hex >> 23) & 0xFF
man = fp_hex & 0x7FFFFF

print(f"Input: 0x{fp_hex:08x} = -1.1")
print(f"Sign: {sign}, Exp: {exp}, Mantissa: 0x{man:06x}\n")

BIAS = 127
int_exp = exp - BIAS
print(f"int_exp = {exp} - {BIAS} = {int_exp}")

man_extended = (1 << 63) | (man << 40)
print(f"\nBefore shift: 0x{man_extended:016x}")
print(f"  This represents: 1.{man:023b} (binary) shifted left by 40")

shift_amount = 63 - int_exp
print(f"\nShift amount: 63 - {int_exp} = {shift_amount}")

shifted_man = man_extended >> shift_amount
print(f"After shift: 0x{shifted_man:016x}")
print(f"  Binary: {bin(shifted_man)}")
print(f"  [63:32] = 0x{(shifted_man >> 32):08x}")
print(f"  [31:0]  = 0x{(shifted_man & 0xFFFFFFFF):08x}")

print("\n" + "="*60)
print("CURRENT (WRONG) LOGIC:")
print("="*60)
flag_nx_wrong = ((shifted_man >> 32) != 0)
print(f"flag_nx = (shifted_man[63:32] != 0) = {flag_nx_wrong}")
print(f"  ❌ This checks if bits [63:32] are non-zero")
print(f"  ❌ But those are the upper/integer bits!")

print("\n" + "="*60)
print("CORRECT LOGIC:")
print("="*60)
print(f"For int_exp={int_exp}, after shifting by {shift_amount}:")
print(f"  - The binary point is at bit {shift_amount-1}/{shift_amount}")
print(f"  - Integer bits are [63:{shift_amount}]")
print(f"  - Fractional bits are [{shift_amount-1}:0]")

frac_mask = (1 << shift_amount) - 1 if shift_amount > 0 else 0
frac_bits = shifted_man & frac_mask
print(f"\nFractional bits [{shift_amount-1}:0] = 0x{frac_bits:016x}")
print(f"Are fractional bits non-zero? {frac_bits != 0}")
print(f"  ✅ Correct flag_nx SHOULD be: {frac_bits != 0}")

print("\n" + "="*60)
print("SUMMARY:")
print("="*60)
print(f"Input: -1.1")
print(f"Expected result: -1 (truncate fractional .1)")
print(f"Expected flag_nx: 1 (inexact because we lost .1)")
print(f"")
print(f"Actual flag_nx (WRONG): {flag_nx_wrong}")
print(f"Correct flag_nx: {frac_bits != 0}")
print(f"")
print("BUG CONFIRMED: Line 192 checks the wrong bit range!")
