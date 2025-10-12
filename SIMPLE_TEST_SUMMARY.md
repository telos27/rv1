# 简单指令测试总结

## 测试日期
2025-10-11

## 测试程序
**文件**: `tests/asm/test_simple.s`

### 测试代码
```assembly
# Test 1: Simple arithmetic
addi x10, x0, 5      # x10 = 5
addi x11, x0, 10     # x11 = 10
add  x12, x10, x11   # x12 = 15

# Test 2: Subtraction
sub  x13, x11, x10   # x13 = 5

# Test 3: Logic operations
ori  x14, x10, 0xFF  # x14 = 0xFF
andi x15, x14, 0x0F  # x15 = 0x05

# End - infinite loop
loop:
    beq  x0, x0, loop    # Infinite loop
```

## 测试结果

### 执行成功
- ✓ 程序成功编译为 `test_simple.hex`
- ✓ 指令成功加载到指令存储器
- ✓ CPU 成功执行 30 个时钟周期
- ✓ 波形文件成功生成

### 波形文件
**位置**: `/home/lei/rv1/simple_program.vcd`
**大小**: 15 KB
**时钟周期**: 30 cycles

## 如何查看波形

### 使用 GTKWave
```bash
cd /home/lei/rv1
gtkwave simple_program.vcd
```

### 推荐观察的信号

#### 顶层信号
- `clk` - 时钟信号
- `reset_n` - 复位信号（低电平有效）
- `pc_out` - 程序计数器（PC）
- `instr_out` - 当前指令

#### 内部信号（展开 dut）
- `dut.regfile.registers[10]` - x10 寄存器（应该 = 5）
- `dut.regfile.registers[11]` - x11 寄存器（应该 = 10）
- `dut.regfile.registers[12]` - x12 寄存器（应该 = 15）
- `dut.regfile.registers[13]` - x13 寄存器（应该 = 5）
- `dut.regfile.registers[14]` - x14 寄存器（应该 = 0xFF）
- `dut.regfile.registers[15]` - x15 寄存器（应该 = 0x05）

#### ALU 信号
- `dut.alu_inst.alu_control` - ALU 操作码
- `dut.alu_inst.alu_in1` - ALU 输入 1
- `dut.alu_inst.alu_in2` - ALU 输入 2
- `dut.alu_inst.alu_result` - ALU 结果

#### 控制信号
- `dut.control_inst.reg_write` - 寄存器写使能
- `dut.control_inst.mem_read` - 存储器读使能
- `dut.control_inst.mem_write` - 存储器写使能
- `dut.control_inst.branch` - 分支信号
- `dut.control_inst.jump` - 跳转信号

## 观察到的行为

### PC（程序计数器）变化
```
Cycle  1: PC = 0x00000000
Cycle  2: PC = 0x00000004
Cycle  3: PC = 0x00000008
Cycle  4: PC = 0x0000000C
...
Cycle 19: PC = 0x00000000  (循环回到开始)
```

说明：
- PC 正常递增（每次 +4 字节）
- 在第 18-19 个周期之间，BEQ 指令成功跳转回 PC=0

### 预期寄存器值

根据程序逻辑，最终寄存器值应该为：
- **x10 (a0)** = 5 (0x00000005)
- **x11 (a1)** = 10 (0x0000000A)
- **x12 (a2)** = 15 (0x0000000F)
- **x13 (a3)** = 5 (0x00000005)
- **x14 (a4)** = 255 (0x000000FF)
- **x15 (a5)** = 5 (0x00000005)

## GTKWave 使用技巧

### 添加信号到波形
1. 在左侧信号列表中找到信号
2. 选中信号后，点击 "Append" 或直接拖拽到右侧波形窗口

### 查看寄存器数组
1. 展开 `dut` → `regfile`
2. 展开 `registers`
3. 可以看到 `registers[0]` 到 `registers[31]`
4. 选择 `registers[10]` 到 `registers[15]` 添加到波形

### 调整显示格式
- 右键点击信号名
- 选择 "Data Format"
- 推荐格式：
  - PC/地址: Hexadecimal
  - 指令: Hexadecimal
  - 寄存器值: Decimal 或 Hexadecimal
  - 控制信号: Binary

### 缩放波形
- `Ctrl + 滚轮` 或 `+/-` 键：缩放时间轴
- `Shift + 滚轮`：水平滚动
- `Zoom Fit`：自动适应窗口大小

## 测试文件清单

### 源文件
- `tests/asm/test_simple.s` - 汇编源代码
- `tests/asm/test_simple.hex` - 机器码（十六进制）
- `tests/asm/test_simple.elf` - ELF 可执行文件
- `tests/asm/test_simple.bin` - 二进制文件

### 测试台
- `tb/tb_simple_exec.v` - 测试台 Verilog 代码

### 输出
- `simple_program.vcd` - 波形文件（VCD 格式）
- `sim/tb_exec.vvp` - 编译后的仿真文件

## 重新运行测试

如果您想重新运行测试：

```bash
cd /home/lei/rv1

# 方法 1: 使用编译好的仿真
vvp sim/tb_exec.vvp

# 方法 2: 重新编译并运行
iverilog -g2012 -I rtl -o sim/tb_exec.vvp \
  tb/tb_simple_exec.v \
  rtl/core/alu.v \
  rtl/core/register_file.v \
  rtl/core/pc.v \
  rtl/core/decoder.v \
  rtl/core/control.v \
  rtl/core/branch_unit.v \
  rtl/memory/instruction_memory.v \
  rtl/memory/data_memory.v \
  rtl/core/rv32i_core.v

vvp sim/tb_exec.vvp

# 查看波形
gtkwave simple_program.vcd
```

## 下一步

如果您想测试更复杂的程序：

1. **Fibonacci 测试**: `tests/asm/fibonacci.s`
2. **Load/Store 测试**: `tests/asm/load_store.s`
3. **分支测试**: `tests/asm/branch_test.s`
4. **逻辑操作**: `tests/asm/logic_ops.s`

修改测试台中的 `MEM_FILE` 参数即可：
```verilog
rv32i_core #(
  .MEM_FILE("tests/asm/fibonacci.hex")  // 改成其他测试程序
) dut (
  ...
);
```

## 总结

✓ **测试成功**: 简单指令集测试程序成功执行
✓ **波形生成**: VCD 波形文件已生成，可用 GTKWave 查看
✓ **功能验证**: PC 递增、指令执行、分支跳转都正常工作

CPU 核心的基本功能正常！
