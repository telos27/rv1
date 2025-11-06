.option norvc
.section .text
.globl _start
_start:
    la      t0, test_data
    mv      x10, t0
    li      x28, 0xDEADBEEF
    ebreak

.section .data
.align 12
page_table:
    .skip 4096

.align 4
test_data:
    .word 0xCAFEBABE
