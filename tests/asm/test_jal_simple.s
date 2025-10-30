# Simple JAL test - minimal version
# Just verify JAL writes ra and returns

.section .text
.globl _start

_start:
    # Test 1: Basic JAL
    jal ra, func1

    # If we get here, JAL worked
    li x28, 0xFEEDFACE
    ebreak

func1:
    # Just return
    ret

# Should not reach here
fail:
    li x28, 0xDEADDEAD
    ebreak
