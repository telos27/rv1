# fibonacci.s
# Compute the 10th Fibonacci number using iteration
# Expected result: x10 = 55

.section .text
.globl _start

_start:
    # Initialize
    addi x10, x0, 10     # n = 10 (compute fib(10))
    addi x5, x0, 0       # fib(0) = 0
    addi x6, x0, 1       # fib(1) = 1
    addi x7, x0, 0       # counter = 0

    # Handle base cases
    beq x10, x0, done_zero    # if n == 0, return 0
    addi x8, x0, 1
    beq x10, x8, done_one     # if n == 1, return 1

    # Fibonacci loop
    addi x7, x0, 2       # counter = 2 (start from fib(2))

fib_loop:
    bge x7, x10, done    # if counter >= n, done
    add x8, x5, x6       # fib(n) = fib(n-1) + fib(n-2)
    addi x5, x6, 0       # fib(n-2) = fib(n-1)
    addi x6, x8, 0       # fib(n-1) = fib(n)
    addi x7, x7, 1       # counter++
    jal x0, fib_loop     # loop

done:
    addi x10, x6, 0      # result = fib(n-1)
    ebreak

done_zero:
    addi x10, x0, 0      # result = 0
    ebreak

done_one:
    addi x10, x0, 1      # result = 1
    ebreak
