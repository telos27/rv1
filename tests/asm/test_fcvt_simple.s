# Simple FCVT.S.W test - convert integer to float
# Test converting 0, 1, 2, -1

.section .text
.globl _start

_start:
    # Test 1: FCVT.S.W f10, x0 (convert 0 to float)
    # Expected: f10 = 0x00000000 (0.0)
    fcvt.s.w f10, x0
    fmv.x.w a0, f10     # Move result to a0 for checking
    
    # Test 2: FCVT.S.W f11, x1 (convert 1 to float)
    li x1, 1
    fcvt.s.w f11, x1
    fmv.x.w a1, f11     # Expected: 0x3F800000 (1.0)
    
    # Test 3: FCVT.S.W f12, x2 (convert 2 to float)
    li x2, 2
    fcvt.s.w f12, x2
    fmv.x.w a2, f12     # Expected: 0x40000000 (2.0)
    
    # Test 4: FCVT.S.W f13, x3 (convert -1 to float)
    li x3, -1
    fcvt.s.w f13, x3
    fmv.x.w a3, f13     # Expected: 0xBF800000 (-1.0)
    
    # Exit
    li a7, 93
    ecall

.section .data
