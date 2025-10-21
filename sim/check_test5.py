#!/usr/bin/env python3
import struct

# Test #5: fcvt.w.s 0.9, rtz
# Expected: result=0, flags=0x01 (NX)

# Encode 0.9 as single-precision float
fp_value = 0.9
fp_bytes = struct.pack('>f', fp_value)
fp_hex = struct.unpack('>I', fp_bytes)[0]

print(f"Test #5: fcvt.w.s 0.9, rtz")
print(f"="*60)
print(f"FP value: 0.9")
print(f"FP hex: 0x{fp_hex:08x}")
print(f"Sign: {(fp_hex >> 31) & 1}")
print(f"Exp: {(fp_hex >> 23) & 0xFF}")
print(f"Man: 0x{fp_hex & 0x7FFFFF:06x}")

exp = (fp_hex >> 23) & 0xFF
man = fp_hex & 0x7FFFFF
int_exp = exp - 127

print(f"\nint_exp = {exp} - 127 = {int_exp}")

if int_exp < 0:
    print(f"Takes int_exp < 0 path")
    print(f"Result: 0")
    print(f"flag_nx: should be 1 (non-zero value truncated)")
else:
    print(f"Takes int_exp >= 0 path")

