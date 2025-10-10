# Test Programs Directory

This directory contains test programs and vectors for verifying the RV1 processor.

## Subdirectories

### asm/
Hand-written assembly test programs:
- `hello.s` - Simple hello world (UART output)
- `fibonacci.s` - Fibonacci sequence
- `bubblesort.s` - Bubble sort array
- `factorial.s` - Factorial calculation (recursive)
- `gcd.s` - Greatest common divisor
- `strlen.s` - String length calculation
- `memcpy.s` - Memory copy routine

Each program should:
- Have clear comments
- Define expected results
- Use standard calling conventions
- Include test data in .data section

### riscv-tests/
Official RISC-V compliance tests:
```
# Clone the official test suite
git clone https://github.com/riscv/riscv-tests.git
cd riscv-tests
git submodule update --init --recursive

# Build for RV32I
./configure --prefix=$RISCV/target
make
```

Key test categories:
- `rv32ui-p-*` - User-level integer tests (physical memory)
- `rv32um-p-*` - Multiply/divide tests
- `rv32ua-p-*` - Atomic instruction tests
- `rv32uc-p-*` - Compressed instruction tests

### vectors/
Pre-compiled test vectors in hex format:
- `*.hex` - Memory initialization files
- `*.dat` - Expected output data
- `*.log` - Expected register/memory state

## Assembly Program Structure

### Standard Template
```assembly
# test_name.s
# Description: What this test does
# Expected: What the result should be

.section .text
.globl _start

_start:
    # Initialize stack pointer
    li sp, 0x1000

    # Test code here
    li a0, 10           # Load test value
    jal ra, test_func   # Call function

    # Store result in x10 for verification
    mv a0, a1

    # End test (infinite loop or EBREAK)
    ebreak
    j .

test_func:
    # Function body
    addi a1, a0, 5
    ret

.section .data
test_data:
    .word 1, 2, 3, 4, 5
```

### Calling Convention (RV32I)
```
Registers:
  x0      : zero (hardwired to 0)
  x1  ra  : return address
  x2  sp  : stack pointer
  x3  gp  : global pointer
  x4  tp  : thread pointer
  x5-x7   : temporaries (t0-t2)
  x8-x9   : saved registers (s0-s1)
  x10-x17 : arguments/results (a0-a7)
  x18-x27 : saved registers (s2-s11)
  x28-x31 : temporaries (t3-t6)

Stack:
  Grows downward (from high to low addresses)
  sp points to top of stack
```

## Creating Test Programs

### 1. Write Assembly
```bash
# Create test program
cat > tests/asm/add_test.s << 'EOF'
.section .text
.globl _start
_start:
    li x10, 5
    li x11, 7
    add x12, x10, x11    # 5 + 7 = 12
    ebreak
EOF
```

### 2. Assemble and Link
```bash
# Assemble
riscv32-unknown-elf-as -march=rv32i -o add_test.o add_test.s

# Link
riscv32-unknown-elf-ld -T linker.ld -o add_test.elf add_test.o

# Generate hex file
riscv32-unknown-elf-objcopy -O verilog add_test.elf add_test.hex
```

### 3. Linker Script (linker.ld)
```
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    IMEM : ORIGIN = 0x00000000, LENGTH = 4K
    DMEM : ORIGIN = 0x00001000, LENGTH = 4K
}

SECTIONS {
    .text : {
        *(.text)
        *(.text.*)
    } > IMEM

    .data : {
        *(.data)
        *(.data.*)
        *(.rodata)
        *(.rodata.*)
    } > DMEM

    .bss : {
        *(.bss)
        *(.bss.*)
    } > DMEM
}
```

## Example Test Programs

### Fibonacci Sequence
```assembly
# fibonacci.s
# Computes nth Fibonacci number
# Input: n in x10
# Output: fib(n) in x10

.text
.globl _start

_start:
    li x10, 10          # n = 10
    jal ra, fibonacci
    # Result in x10 (should be 55)
    ebreak

fibonacci:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    sw s1, 4(sp)

    li s0, 0            # fib(0) = 0
    li s1, 1            # fib(1) = 1

    beq x10, x0, fib_base_0
    li t0, 1
    beq x10, t0, fib_base_1

fib_loop:
    addi x10, x10, -1
    add t0, s0, s1      # next = fib(n-1) + fib(n-2)
    mv s0, s1
    mv s1, t0
    bnez x10, fib_loop

fib_base_1:
    mv x10, s1
    j fib_return

fib_base_0:
    mv x10, s0

fib_return:
    lw ra, 12(sp)
    lw s0, 8(sp)
    lw s1, 4(sp)
    addi sp, sp, 16
    ret
```

### Bubble Sort
```assembly
# bubblesort.s
# Sorts array in ascending order

.text
.globl _start

_start:
    la x10, array       # x10 = array address
    li x11, 5           # x11 = array length
    jal ra, bubblesort
    ebreak

bubblesort:
    addi sp, sp, -20
    sw ra, 16(sp)
    sw s0, 12(sp)
    sw s1, 8(sp)
    sw s2, 4(sp)
    sw s3, 0(sp)

    mv s0, x10          # s0 = array
    mv s1, x11          # s1 = length
    li s2, 0            # s2 = i

outer_loop:
    bge s2, s1, sort_done
    li s3, 0            # s3 = j

inner_loop:
    sub t0, s1, s2
    addi t0, t0, -1
    bge s3, t0, outer_next

    slli t1, s3, 2      # t1 = j * 4
    add t1, s0, t1      # t1 = &array[j]
    lw t2, 0(t1)        # t2 = array[j]
    lw t3, 4(t1)        # t3 = array[j+1]

    ble t2, t3, inner_next

    # Swap
    sw t3, 0(t1)
    sw t2, 4(t1)

inner_next:
    addi s3, s3, 1
    j inner_loop

outer_next:
    addi s2, s2, 1
    j outer_loop

sort_done:
    lw ra, 16(sp)
    lw s0, 12(sp)
    lw s1, 8(sp)
    lw s2, 4(sp)
    lw s3, 0(sp)
    addi sp, sp, 20
    ret

.data
array:
    .word 64, 34, 25, 12, 22
```

## Test Automation

### Makefile Targets
```makefile
# Assemble all tests
asm-tests:
    for file in tests/asm/*.s; do \
        riscv32-unknown-elf-as -march=rv32i -o $${file%.s}.o $$file; \
        riscv32-unknown-elf-ld -T linker.ld -o $${file%.s}.elf $${file%.s}.o; \
        riscv32-unknown-elf-objcopy -O verilog $${file%.s}.elf tests/vectors/$${file%.s}.hex; \
    done

# Run all tests
run-tests:
    for hex in tests/vectors/*.hex; do \
        ./sim/run_test.sh $$hex; \
    done
```

### Verification Script
```bash
#!/bin/bash
# run_test.sh

TEST_HEX=$1
TEST_NAME=$(basename $TEST_HEX .hex)

echo "Running test: $TEST_NAME"

# Run simulation
iverilog -DMEM_FILE=\"$TEST_HEX\" -o sim/${TEST_NAME}.vvp \
    rtl/core/*.v tb/integration/tb_core.v

vvp sim/${TEST_NAME}.vvp > sim/${TEST_NAME}.log

# Check results
if grep -q "PASS" sim/${TEST_NAME}.log; then
    echo "✓ $TEST_NAME PASSED"
else
    echo "✗ $TEST_NAME FAILED"
    cat sim/${TEST_NAME}.log
fi
```

## Expected Results

Each test should document expected results:

### add_test.s
```
Expected Registers:
  x10 = 5
  x11 = 7
  x12 = 12
```

### fibonacci.s
```
Input: x10 = 10
Expected: x10 = 55 (10th Fibonacci number)
```

### bubblesort.s
```
Input Array: [64, 34, 25, 12, 22]
Expected Array: [12, 22, 25, 34, 64]
Memory at array[0..4]: 0x0C, 0x16, 0x19, 0x22, 0x40
```

## Debugging Tests

1. **Disassemble**: View what was assembled
   ```bash
   riscv32-unknown-elf-objdump -d test.elf
   ```

2. **Inspect Memory**: Check hex file
   ```bash
   cat test.hex
   ```

3. **Trace Execution**: Add print statements in testbench
   ```verilog
   $display("PC=%h Instr=%h x10=%h", pc, instruction, x10);
   ```

4. **Compare with Spike**: Run on RISC-V ISA simulator
   ```bash
   spike --isa=RV32I test.elf
   ```
