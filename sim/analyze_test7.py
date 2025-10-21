#!/usr/bin/env python3
import struct

val = 1.1
fp_bits = struct.unpack('>I', struct.pack('>f', val))[0]
exp_biased = (fp_bits >> 23) & 0xFF
mantissa = fp_bits & 0x7FFFFF
int_exp = exp_biased - 127

print(f'Value: {val}')
print(f'int_exp: {int_exp}')

man_64 = (1 << 63) | (mantissa << 40)
print(f'64-bit mantissa (before shift): 0x{man_64:016x}')

shift_amount = 63 - int_exp
shifted_man = man_64 >> shift_amount
print(f'After shift by {shift_amount}: 0x{shifted_man:016x} = {shifted_man}')

print('\n=== CURRENT CODE (Bug #13 fix) ===')
frac_mask = (1 << (63 - int_exp)) - 1
frac_check_current = (shifted_man & frac_mask) != 0
print(f'mask = (1 << {63 - int_exp}) - 1 = 0x{frac_mask:016x}')
print(f'shifted_man & mask = 0x{shifted_man & frac_mask:016x}')
print(f'flag_nx = {frac_check_current}')

print('\n=== WHAT WE SHOULD CHECK ===')
frac_bits_lost = man_64 & ((1 << shift_amount) - 1)
print(f'Bits lost in shift [{shift_amount-1}:0]: 0x{frac_bits_lost:016x}')
print(f'flag_nx should be: {frac_bits_lost != 0}')
