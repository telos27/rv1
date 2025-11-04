# RV64I SD Only Test

.section .text
.globl _start

_start:
    li      a0, 0x2000              # Address
    li      a1, 0x99                # Value
    sd      a1, 0(a0)               # Store doubleword
    li      a0, 1                   # Success indicator
    ebreak
