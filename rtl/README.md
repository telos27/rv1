# RTL 目录

此目录包含 RV1 处理器的所有 Verilog RTL 源文件。

## 子目录

### core/
核心 CPU 模块：
- `rv32i_core.v` - 顶层处理器模块
- `pc.v` - 程序计数器
- `register_file.v` - 32 寄存器寄存器堆
- `alu.v` - 算术逻辑单元
- `decoder.v` - 指令译码器
- `control.v` - 控制单元
- `imm_gen.v` - 立即数生成器
- `branch_unit.v` - 分支条件判定单元

Phase 2 新增：
- `fsm_control.v` - 基于 FSM 的多周期控制

Phase 3 新增：
- `pipeline_regs.v` - 流水线寄存器（IF/ID、ID/EX、EX/MEM、MEM/WB）
- `forwarding_unit.v` - 数据前递逻辑
- `hazard_unit.v` - 冒险检测

Phase 4 新增：
- `mul_div.v` - M 扩展乘除法单元
- `csr_file.v` - 控制与状态寄存器
- `trap_unit.v` - 异常和中断处理单元

### memory/
存储子系统：
- `instruction_memory.v` - 指令存储器（ROM）
- `data_memory.v` - 数据存储器（RAM）
- `memory_arbiter.v` - 共享存储器仲裁器（Phase 2+）

Phase 4 新增：
- `icache.v` - 指令缓存
- `dcache.v` - 数据缓存
- `cache_controller.v` - 缓存控制逻辑

### peripherals/
I/O 和外设模块（未来规划）：
- `uart.v` - UART 控制器
- `gpio.v` - 通用 I/O
- `timer.v` - 定时/计数器

## 编码风格

### 文件组织
```verilog
// 模块描述的头部注释
// 作者、日期、用途

// 模块定义
module module_name #(
    parameter PARAM1 = 32,
    parameter PARAM2 = 8
) (
    // 按功能分组的输入端口
    input  wire        clk,
    input  wire        reset_n,
    input  wire [31:0] data_in,

    // 输出端口
    output wire [31:0] data_out
);

// 内部信号
wire [31:0] internal_sig;
reg  [31:0] registered_sig;

// 逻辑块（先组合逻辑再时序逻辑）
always @(*) begin
    // 组合逻辑
end

always @(posedge clk or negedge reset_n) begin
    // 时序逻辑
end

endmodule
```

### 命名约定
- 模块文件：`snake_case.v`
- 参数：`UPPER_CASE`
- 信号：`snake_case`
- 低有效：后缀 `_n`
- 寄存器：可选后缀 `_r`
- 下一状态：后缀 `_next`

### 最佳实践
1. 使用 2 空格缩进
2. 单行长度不超过 100 字符
3. 将相关信号分组
4. 为复杂逻辑添加注释
5. 使用有意义的名字
6. 避免魔法数字（使用参数）
7. 初始化所有寄存器
8. 不要产生锁存器（总是覆盖所有分支）
9. 不要产生组合环路
10. 优先使用同步复位（或异步低有效复位）
