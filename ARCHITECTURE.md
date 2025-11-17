# RV1 架构文档

## 概览

本文件详细说明 RV1 RISC-V 处理器内核的微架构。

**实现状态**：阶段 13 完成 - 完整 RV32IMAFDC，带监督模式和虚拟内存  
**最后更新**：2025-10-23（100% 兼容 - 所有扩展完成）

## 实现概要

### 当前状态
- **ISA**：RV32IMAFDC + RV64IMAFDC（参数化）
- **架构**：5 级流水线，带完整冒险处理
- **特权模式**：M 模式、S 模式、U 模式（完整特权系统）
- **虚拟内存**：带 16 项 TLB 的 Sv32 (RV32) 和 Sv39 (RV64)
- **扩展**：M（乘/除）、A（原子）、F/D（浮点）、C（压缩）
- **兼容性**：**81/81 测试 (100%)** ✅
  - RV32I: 42/42 (100%) ✅
  - RV32M: 8/8 (100%) ✅
  - RV32A: 10/10 (100%) ✅
  - RV32C: 1/1 (100%) ✅
  - RV32F: 11/11 (100%) ✅
  - RV32D: 9/9 (100%) ✅

### 实现规模
- **总 RTL**：约 7,500 行，36 个模块
- **指令数**：共 184 条（47 基础 + 13 M + 22 A + 52 F/D + 40 C + 10 系统）
- **测试平台**：约 3,000 行
- **文档**：约 6,000 行

### 核心模块（共 36 个）

**数据通路与控制**（9 个模块）：
- `alu.v`, `register_file.v`, `pc.v`, `decoder.v`, `control.v`, `branch_unit.v`
- `exception_unit.v`, `csr_file.v`, `mmu.v`

**流水线基础设施**（8 个模块）：
- `rv32i_core_pipelined.v`（顶层）、`ifid_register.v`, `idex_register.v`, `exmem_register.v`, `memwb_register.v`
- `forwarding_unit.v`, `hazard_detection_unit.v`, `rvc_decoder.v`

**M 扩展**（3 个模块）：
- `mul_unit.v`, `div_unit.v`, `mul_div_unit.v`

**A 扩展**（2 个模块）：
- `atomic_unit.v`, `reservation_station.v`

**F/D 扩展**（11 个模块）：
- `fpu.v`, `fp_register_file.v`, `fp_adder.v`, `fp_multiplier.v`, `fp_divider.v`, `fp_sqrt.v`
- `fp_fma.v`, `fp_converter.v`, `fp_compare.v`, `fp_classify.v`, `fp_minmax.v`, `fp_sign.v`

**存储器**（2 个模块）：
- `instruction_memory.v`, `data_memory.v`

**遗留模块**（1 个模块）：
- `rv32i_core.v`（原单周期内核，保留作参考）

## 设计参数

```verilog
parameter DATA_WIDTH = 32;          // 32 位数据通路
parameter ADDR_WIDTH = 32;          // 32 位地址空间
parameter REG_COUNT = 32;           // 32 个架构寄存器
parameter RESET_VECTOR = 32'h0000_0000;  // 复位 PC 值
```

## 阶段 1：单周期架构

### 高层数据通路

```
                    ┌─────────────┐
                    │     PC      │
                    └─────┬───────┘
                          │
                          ▼
                    ┌─────────────┐
                    │   Inst Mem  │
                    └─────┬───────┘
                          │ instruction
                          ▼
                    ┌─────────────┐
                    │   Decoder   │
                    └──┬──┬──┬────┘
                       │  │  │
         ┌─────────────┘  │  └─────────────┐
         ▼                ▼                 ▼
    ┌────────┐       ┌─────────┐      ┌─────────┐
    │ RegFile│◄──────│ Control │      │ Imm Gen │
    └────┬───┘       └────┬────┘      └────┬────┘
         │                │                 │
         │ rs1  rs2       │                 │
         ▼    ▼           ▼                 │
       ┌────────────┐   controls            │
       │  ALU Mux   │◄────────────────────┬─┘
       └─────┬──────┘                      │
             ▼                              │
         ┌───────┐                          │
         │  ALU  │                          │
         └───┬───┘                          │
             ▼                              │
       ┌──────────┐                         │
       │ Data Mem │                         │
       └─────┬────┘                         │
             ▼                              │
       ┌──────────┐                         │
       │  WB Mux  │◄────────────────────────┘
       └─────┬────┘
             │
             ▼ (write back to RegFile)
```

### 模块描述

#### 1. 程序计数器（PC）
```verilog
module pc (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall,
    input  wire [31:0] pc_next,
    output reg  [31:0] pc_current
);
```
- 保存当前指令地址
- 在时钟上升沿更新
- 在复位时置为 RESET_VECTOR
- 支持为冒险而停顿（为后续阶段准备）

#### 2. 指令存储器
```verilog
module instruction_memory #(
    parameter MEM_SIZE = 4096,  // 默认 4KB
    parameter MEM_FILE = ""
) (
    input  wire [31:0] addr,
    output wire [31:0] instruction
);
```
- 只读程序存储器
- 以字对齐访问（忽略 addr[1:0]）
- 组合逻辑读取（阶段 1 中无需时钟）
- 通过 `$readmemh` 从 hex 文件加载

#### 3. 寄存器文件
```verilog
module register_file (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    input  wire        rd_wen,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);
```
- 32 个寄存器：x0-x31
- x0 硬连为零
- 2 个读端口（组合逻辑）
- 1 个写端口（时钟上升沿同步写）
- 写使能由 rd_wen 控制

#### 4. 指令解码器
```verilog
module decoder (
    input  wire [31:0] instruction,
    output wire [6:0]  opcode,
    output wire [4:0]  rd,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [2:0]  funct3,
    output wire [6:0]  funct7,
    output wire [31:0] imm_i,
    output wire [31:0] imm_s,
    output wire [31:0] imm_b,
    output wire [31:0] imm_u,
    output wire [31:0] imm_j
);
```
- 提取指令字段
- 生成所有类型的立即数（带符号扩展）
- 纯组合逻辑

#### 5. 控制单元
```verilog
module control (
    input  wire [6:0]  opcode,
    input  wire [2:0]  funct3,
    input  wire [6:0]  funct7,
    output wire        reg_write,
    output wire        mem_read,
    output wire        mem_write,
    output wire        branch,
    output wire        jump,
    output wire [1:0]  alu_op,
    output wire        alu_src,
    output wire [1:0]  wb_sel,
    output wire        pc_src
);
```
- 根据 opcode 解码控制信号
- 组合逻辑
- 控制信号可采用 one-hot 或二进制编码

#### 6. 立即数生成器
```verilog
module imm_gen (
    input  wire [31:0] instruction,
    input  wire [2:0]  imm_sel,
    output reg  [31:0] immediate
);
```
- 根据指令类型选择并构造立即数
- 正确符号扩展
- 支持 I, S, B, U, J 格式

#### 7. 算术逻辑单元（ALU）
```verilog
module alu (
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    input  wire [3:0]  alu_control,
    output reg  [31:0] result,
    output wire        zero,
    output wire        less_than,
    output wire        less_than_unsigned
);
```
- 实现算术与逻辑运算
- 操作：ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
- 输出用于分支判断的标志位
- 32 位运算

**ALU 控制编码：**
```
4'b0000: ADD
4'b0001: SUB
4'b0010: SLL (逻辑左移)
4'b0011: SLT (小于置位)
4'b0100: SLTU (无符号小于置位)
4'b0101: XOR
4'b0110: SRL (逻辑右移)
4'b0111: SRA (算术右移)
4'b1000: OR
4'b1001: AND
```

#### 8. 数据存储器
```verilog
module data_memory #(
    parameter MEM_SIZE = 4096
) (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [2:0]  funct3,      // 用于加载/存储大小
    output reg  [31:0] read_data
);
```
- 按字节寻址的存储器
- 支持字节（B）、半字（H）、字（W）访问
- 支持有符号与无符号加载
- 同步写、组合读（阶段 1）

#### 9. 分支单元
```verilog
module branch_unit (
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [2:0]  funct3,
    input  wire        branch,
    input  wire        jump,
    output wire        take_branch
);
```
- 计算分支条件
- 支持：BEQ, BNE, BLT, BGE, BLTU, BGEU
- 跳转指令总是“跳转”

### 控制信号

| 信号 | 宽度 | 描述 |
|------|------|------|
| reg_write | 1 | 使能寄存器文件写入 |
| mem_read | 1 | 使能存储器读取 |
| mem_write | 1 | 使能存储器写入 |
| branch | 1 | 指令为分支 |
| jump | 1 | 指令为跳转 |
| alu_src | 1 | ALU 操作数 B：0=rs2，1=立即数 |
| alu_op | 2 | ALU 操作类型 |
| wb_sel | 2 | 写回来源：00=ALU，01=MEM，10=PC+4 |
| pc_src | 1 | PC 来源：0=PC+4，1=分支/跳转目标 |
| imm_sel | 3 | 立即数格式选择 |

### 指令操作码映射

```
LOAD     = 7'b0000011
LOAD-FP  = 7'b0000111  （未实现）
MISC-MEM = 7'b0001111  （FENCE）
OP-IMM   = 7'b0010011  （ADDI, SLTI 等）
AUIPC    = 7'b0010111
STORE    = 7'b0100011
STORE-FP = 7'b0100111  （未实现）
OP       = 7'b0110011  （ADD, SUB 等）
LUI      = 7'b0110111
BRANCH   = 7'b1100011
JALR     = 7'b1100111
JAL      = 7'b1101111
SYSTEM   = 7'b1110011  （ECALL, EBREAK）
```

### 定时（单周期）

所有指令在一个时钟周期内完成：
```
周期 1：IF + ID + EX + MEM + WB（全部在同一周期
         └─── 临界路径 ───┘
```

**临界路径：**
1. PC 寄存器 → 指令存储器读取
2. 指令 → 解码器 → 控制
3. 寄存器文件读取
4. ALU 运算
5. 数据存储器读取（若为加载）
6. 写回多路选择器 → 寄存器文件（写入准备）

**估计延迟**（用于简单时序分析）：
- 寄存器建立/保持：约 0.5ns
- 指令存储器：约 2ns
- 解码 + 控制：约 1ns
- 寄存器文件读取：约 1ns
- ALU：约 2ns
- 数据存储器：约 2ns
- 多路选择 + 走线：约 0.5ns  
**总计：约 9ns → 约 111MHz 最大频率**

## 阶段 2：多周期架构

### 状态机

```
状态：
- FETCH:    从存储器取指
- DECODE:   解码并读取寄存器
- EXECUTE:  ALU 运算
- MEMORY:   访存（如需要）
- WRITEBACK: 结果写回寄存器

状态转移：
FETCH → DECODE → EXECUTE → MEMORY → WRITEBACK → FETCH
                             ↓ （若无需访存）
                         WRITEBACK
```

### 相对单周期的修改

1. **共享存储器**：指令与数据共用一个存储器
2. **多周期控制**：基于 FSM 的控制单元
3. **内部寄存器**：在状态之间保存值
   - 指令寄存器（IR）
   - 内存数据寄存器（MDR）
   - ALU 输出寄存器
   - 操作数 A、B 寄存器

## 阶段 3：流水线架构

### 流水线阶段

```
┌────┐    ┌────┐    ┌────┐    ┌─────┐    ┌────┐
│ IF │ -> │ ID │ -> │ EX │ -> │ MEM │ -> │ WB │
└────┘    └────┘    └────┘    └─────┘    └────┘
  │         │         │          │          │
  PC      RegFile    ALU      DataMem    RegFile
  IMem    Decoder              Write      Write
```

### 流水线寄存器

```verilog
// IF/ID 流水线寄存器
struct {
    logic [31:0] pc;
    logic [31:0] instruction;
} if_id;

// ID/EX 流水线寄存器
struct {
    logic [31:0] pc;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] immediate;
    logic [4:0]  rd;
    // ... 控制信号
} id_ex;

// EX/MEM 流水线寄存器
struct {
    logic [31:0] alu_result;
    logic [31:0] rs2_data;
    logic [4:0]  rd;
    // ... 控制信号
} ex_mem;

// MEM/WB 流水线寄存器
struct {
    logic [31:0] alu_result;
    logic [31:0] mem_data;
    logic [4:0]  rd;
    // ... 控制信号
} mem_wb;
```

### 冒险处理

#### 1. 数据冒险（RAW - 读后写）

**集中式前递架构**（阶段 12）：

RV1 内核实现了一个**双阶段前递系统**，集中控制在 `forwarding_unit.v` 中：

**ID 阶段前递**（用于早期分支决策）：
- 来自 EX 阶段（IDEX 寄存器）→ 优先级 1
- 来自 MEM 阶段（EXMEM 寄存器）→ 优先级 2
- 来自 WB 阶段（MEMWB 寄存器）→ 优先级 3
- 3 位编码：`3'b100`=EX，`3'b010`=MEM，`3'b001`=WB，`3'b000`=无前递

**EX 阶段前递**（用于 ALU 运算）：
- 来自 MEM 阶段（EXMEM 寄存器）→ 优先级 1
- 来自 WB 阶段（MEMWB 寄存器）→ 优先级 2
- 2 位编码：`2'b10`=MEM，`2'b01`=WB，`2'b00`=无前递

```verilog
// 前递单元接口（简化版）
module forwarding_unit (
    // ID 阶段（分支判定）
    input  [4:0] id_rs1, id_rs2,
    output [2:0] id_forward_a, id_forward_b,    // 3 位: EX/MEM/WB/无

    // EX 阶段（ALU 运算）
    input  [4:0] idex_rs1, idex_rs2,
    output [1:0] forward_a, forward_b,          // 2 位: MEM/WB/无

    // 流水线写端口
    input  [4:0] idex_rd, exmem_rd, memwb_rd,
    input        idex_reg_write, exmem_reg_write, memwb_reg_write,
    // ... 浮点与交叉寄存器前递信号
);
```

**优先级解析：**
```
EX→ID 前递（最高优先级）：
    if (idex_reg_write && idex_rd != 0 && idex_rd == id_rs1)
        id_forward_a = 3'b100

MEM→ID 前递（中优先级）：
    else if (exmem_reg_write && exmem_rd != 0 && exmem_rd == id_rs1)
        id_forward_a = 3'b010

WB→ID 前递（最低优先级）：
    else if (memwb_reg_write && memwb_rd != 0 && memwb_rd == id_rs1)
        id_forward_a = 3'b001
```

**加载-使用冒险**：

仅靠前递无法解决，必须插入 1 个周期停顿：
```verilog
// 位于 hazard_detection_unit.v
assign load_use_hazard = idex_mem_read &&
                         ((idex_rd == id_rs1) || (idex_rd == id_rs2)) &&
                         (idex_rd != 5'h0);

assign stall_pc   = load_use_hazard || fp_load_use_hazard ||
                    m_extension_stall || a_extension_stall ||
                    fp_extension_stall || mmu_stall;
assign stall_ifid = stall_pc;
```

**MMU 停顿传播**（阶段 12 关键修复）：
```verilog
// MMU 在页表遍历期间忙碌 — 必须停顿整个流水线
wire mmu_stall;
assign mmu_stall = mmu_busy;
```

**前递覆盖范围**：
- ✅ 整数寄存器前递（EX→ID, MEM→ID, WB→ID, MEM→EX, WB→EX）
- ✅ 浮点寄存器前递（与整数相同路径）
- ✅ 交叉寄存器前递（INT→FP 的 FMV.W.X、FP→INT 的 FMV.X.W）
- ✅ 三操作数 FP 前递（FMADD/FMSUB/FNMADD/FNMSUB）

详见 `docs/FORWARDING_ARCHITECTURE.md` 获取前递架构的详细说明。

#### 2. 控制冒险

**分支决策位置**：
- 在 **ID 阶段** 进行早期分支判定（非 EX 阶段）
- 在 ID 阶段计算分支目标
- 使用前递后的值在 ID 阶段计算分支条件
- 将控制冒险损失从 3 个周期减至 1 个周期

**分支处理**：
```verilog
// 在 ID 阶段产生分支是否跳转信号
wire ex_take_branch;

// 分支/跳转时刷新流水线
assign flush_idex = ex_take_branch;  // 刷新 ID/EX 中的指令

// 分支时 PC 更新
wire [31:0] branch_target;  // 在 ID 阶段计算
assign pc_next = ex_take_branch ? branch_target : pc_plus_4;
```

**分支预测**（尚未实现）：
- 阶段 3.1：预测不跳转（跳转则刷新）← 当前实现
- 阶段 3.2：1 位预测器（未来）
- 阶段 3.3：2 位饱和计数器（未来）

### 前递单元架构（阶段 12）

**模块**：`rtl/core/forwarding_unit.v`（268 行）

前递单元是流水线内所有数据前递的集中控制模块。它监控流水线寄存器的写端口，并为 ID 与 EX 两个阶段生成前递控制信号。

#### 设计原则

1. **集中控制**：所有前递决策集中在一个模块中
2. **多级前递**：支持来自 3 个流水线阶段（EX、MEM、WB）的前递
3. **基于优先级**：最新的指令数据优先级最高
4. **双阶段支持**：为 ID（分支）与 EX（ALU）提供独立前递路径
5. **可扩展**：接口设计支持未来的超标量扩展

#### 前递路径

**ID 阶段前递路径**：
```
EX  → ID  (IDEX.rd  → ID.rs1/rs2)  [优先级 1 - 最新]
MEM → ID  (EXMEM.rd → ID.rs1/rs2)  [优先级 2]
WB  → ID  (MEMWB.rd → ID.rs1/rs2)  [优先级 3 - 最旧]
```

**EX 阶段前递路径**：
```
MEM → EX  (EXMEM.rd → IDEX.rs1/rs2)  [优先级 1]
WB  → EX  (MEMWB.rd → IDEX.rs1/rs2)  [优先级 2]
```

注意：EX→EX 前递不可能（会形成环路）— 此类情况属于加载-使用冒险，必须通过停顿解决。

#### 信号编码

**3 位 ID 阶段编码**：
- `3'b100`：来自 EX 阶段（IDEX 寄存器）
- `3'b010`：来自 MEM 阶段（EXMEM 寄存器）
- `3'b001`：来自 WB 阶段（MEMWB 寄存器）
- `3'b000`：无前递（使用寄存器文件）

**2 位 EX 阶段编码**：
- `2'b10`：来自 MEM 阶段（EXMEM 寄存器）
- `2'b01`：来自 WB 阶段（MEMWB 寄存器）
- `2'b00`：无前递（使用 IDEX 寄存器值）

#### 实现示例

ID 阶段 rs1 前递逻辑：
```verilog
always @(*) begin
    id_forward_a = 3'b000;  // 默认：无前递

    // 优先级 1：来自 EX 阶段（最新）
    if (idex_reg_write && (idex_rd != 5'h0) && (idex_rd == id_rs1))
        id_forward_a = 3'b100;

    // 优先级 2：来自 MEM 阶段
    else if (exmem_reg_write && (exmem_rd != 5'h0) && (exmem_rd == id_rs1))
        id_forward_a = 3'b010;

    // 优先级 3：来自 WB 阶段
    else if ((memwb_reg_write | memwb_int_reg_write_fp) &&
             (memwb_rd != 5'h0) && (memwb_rd == id_rs1))
        id_forward_a = 3'b001;
end
```

关键保护：`idex_rd != 5'h0` 防止向 x0（零寄存器）前递。

#### 交叉寄存器前递

支持整数与浮点寄存器文件交叉前递：
- **INT→FP**：`memwb_fp_reg_write_int`（FMV.W.X, FCVT.S.W 等）
- **FP→INT**：`memwb_int_reg_write_fp`（FMV.X.W, FCVT.W.S 等）

#### 前递多路选择器

前递多路选择器在 `rv32i_core_pipelined.v` 中实现：

**ID 阶段整数前递**：
```verilog
assign id_rs1_data = (id_forward_a == 3'b100) ? ex_alu_result :      // EX 阶段
                     (id_forward_a == 3'b010) ? exmem_alu_result :   // MEM 阶段
                     (id_forward_a == 3'b001) ? wb_data :            // WB 阶段
                     id_rs1_data_raw;                                // 寄存器文件
```

**EX 阶段整数前递**：
```verilog
assign ex_operand_a = (forward_a == 2'b10) ? exmem_alu_result :  // MEM 阶段
                      (forward_a == 2'b01) ? wb_data :           // WB 阶段
                      idex_rs1_data;                             // IDEX 寄存器
```

#### 时序考虑

**ID 阶段临界路径**：
```
寄存器文件 → 前递比较器 → 4:1 多路选择器 → 分支单元
```
这条路径对分支判定的时序最为关键。前递比较与寄存器文件读取并行进行，以减少延迟。

**EX 阶段临界路径**：
```
ALU 结果 → 前递多路选择器 → ALU 输入
```
相对不那么关键 — 不涉及寄存器文件，且多路选择器更简单（3:1）。

#### 验证结果

**测试覆盖率**：41/42 条 RISC-V RV32I 兼容性测试通过 (97.6%)
- 唯一未过测试：`rv32ui-p-ma_data`（非对齐访问，在无陷入处理的情况下预期失败）

**已测试的前递场景**：
- ✅ EX→ID 前递（ALU 之后紧接分支）
- ✅ MEM→ID 前递（加载之后紧接分支）
- ✅ WB→ID 前递（寄存器写回之后的分支）
- ✅ MEM→EX 前递（ALU 之后紧接 ALU）
- ✅ WB→EX 前递（寄存器写回之后的 ALU）
- ✅ 加载-使用冒险检测与停顿
- ✅ MMU 停顿传播（阶段 12 关键修复）

### 性能指标

**CPI（每指令周期数）**：
- 理想：1.0（无冒险）
- 带前递：1.0-1.2（仅加载-使用冒险）
- 无前递：1.3-1.8（频繁停顿）

**前递带来的 CPI 改进**：对典型代码约提升 30-40%

**相对单周期的加速比**：
- 理论：5 倍（5 级流水线）
- 实际：3-4 倍（受剩余冒险影响）

**面积开销**：
- 前递单元：约占内核总面积 5%
- 比较器：12 个 5 位比较器（60 比特）
- 多路选择器：12 个 32 位 4:1 MUX（整数 + 浮点）

## 阶段 4：扩展

### M 扩展（乘/除）

**新增指令：**
- MUL, MULH, MULHSU, MULHU
- DIV, DIVU, REM, REMU

**实现方式：**
- 方案 1：迭代（34 周期）
- 方案 2：单周期（超大组合逻辑）
- 方案 3：多周期状态机（可配置）

### CSR（控制与状态寄存器）

**CSR 指令：**
- CSRRW, CSRRS, CSRRC
- CSRRWI, CSRRSI, CSRRCI

**关键 CSR：**
```
mstatus   (0x300)：机器状态
mie       (0x304)：中断使能
mtvec     (0x305)：陷入向量
mepc      (0x341)：异常 PC
mcause    (0x342)：陷入原因
mtval     (0x343)：陷入值
```

### 陷入处理

**异常流程：**
1. 将 PC 保存到 mepc
2. 将异常原因保存到 mcause
3. 跳转到 mtvec
4. 关闭中断
5. 将特权级切换到 Machine

**返回流程**（MRET）：
1. 从 mepc 恢复 PC
2. 恢复特权级
3. 重新使能中断

### 监督模式（阶段 10.2）

**特权等级：**
- 00（U 模式）：用户应用
- 01（S 模式）：操作系统内核
- 11（M 模式）：固件/引导程序

**监督模式 CSR**（8 个寄存器）：
```
sstatus   (0x100)：监督状态（mstatus 的子集）
sie       (0x104)：监督中断使能（mie 的子集）
stvec     (0x105)：监督陷入向量
sscratch  (0x140)：监督备用寄存器
sepc      (0x141)：监督异常 PC
scause    (0x142)：监督陷入原因
stval     (0x143)：监督陷入值
sip       (0x144)：监督中断挂起（mip 的子集）
```

**陷入委托 CSR**：
```
medeleg   (0x302)：机器异常委托至 S 模式
mideleg   (0x303)：机器中断委托至 S 模式
```

**关键特性：**
- **SSTATUS**：mstatus 的只读视图（仅显示 S 模式字段）
  - 可见：SIE[1], SPIE[5], SPP[8], SUM[18], MXR[19]
  - 不可见：MIE[3], MPIE[7], MPP[12:11]
- **SIE/SIP**：MIE/MIP 的子集掩码（仅使用位 1, 5, 9）
- **SRET 指令**：从监督陷入返回
  - 从 SEPC 恢复 PC
  - 从 SPP 恢复特权等级
  - 恢复中断使能：SIE ← SPIE
- **CSR 特权检查**：S 模式不能访问 M 模式 CSR
  - 违规将触发非法指令异常

**陷入路由：**
```
┌─────────────────┐
│    Exception    │
└────────┬────────┘
         │
         ▼
   ┌─────────────┐
   │ Current     │
   │ Priv = M?   │
   └──┬──────┬───┘
      │Yes   │No
      ▼      ▼
   M-mode  ┌──────────┐
   Handler │Delegated?│
           │(medeleg) │
           └──┬───┬───┘
              │Y  │N
              ▼   ▼
           S-mode M-mode
           Handler Handler
```

**实现文件**：
- `rtl/core/csr_file.v`：全部 S 模式 CSR + 委托逻辑
- `rtl/core/decoder.v`：SRET 指令检测
- `rtl/core/control.v`：SRET 控制信号
- `rtl/core/rv32i_core_pipelined.v`：特权跟踪与切换
- `rtl/core/exception_unit.v`：带特权感知的 ECALL

### Cache（未来）

**I-Cache**：
- 直接映射，16KB
- 64 字节 Cache 行
- 写直达策略

**D-Cache**：
- 2 路组相联，16KB
- 64 字节 Cache 行
- 写回策略
- LRU 替换

## 内存映射

```
0x0000_0000 - 0x0000_0FFF: 指令存储器 (4KB)
0x0000_1000 - 0x0000_1FFF: 数据存储器 (4KB)
0x1000_0000 - 0x1000_00FF: 存储映射 I/O
0x8000_0000 - 0x8FFF_FFFF: 外部存储器（未来）
```

## 复位行为

1. PC ← RESET_VECTOR (0x0000_0000)
2. 所有寄存器 ← 0
3. 流水线寄存器 ← 0
4. 控制信号 ← 0（空操作）

## 设计约束

1. **禁止组合环路**
2. **所有 FSM 必须有默认状态**
3. **所有存储器必须初始化**
4. **禁止锁存器**（在所有分支中给出赋值）
5. **时钟域**：阶段 1-3 均为单时钟域

## 已知限制

**⚠️ 在添加大型新特性前请优先处理：**

1. **原子前递开销 (6%)**
   - 位置：`hazard_detection_unit.v:126-155`
   - 问题：保守停顿导致每个 LR/SC 测试额外 1,049 个周期（约 6% 开销）
   - 修复思路：加入单周期状态跟踪（可将开销降到约 0.3%）
   - 说明：当前选择简单性 > 性能，但长期应优化

2. **FPU 兼容性问题（官方测试通过率 15%）**
   - 自定义测试：13/13 通过（基础运算正常）
   - 官方测试：3/20 通过（边界情况暴露 Bug）
   - 可能根因：fflags、舍入模式、NaN-boxing、带符号零等
   - 行动：修复官方兼容性测试暴露的 Bug
   - 详情：见 docs/FPU_COMPLIANCE_RESULTS.md

3. **混合 16/32 位指令流**
   - 纯压缩：正常
   - 纯 32 位：正常
   - 混合：部分情况下存在寻址 Bug
   - 行动：在生产使用前先调试

**详见**：[KNOWN_ISSUES.md](../KNOWN_ISSUES.md)。

---

## 后续工作

### 性能增强（优化）
- **原子前递优化**（6% → 0.3%）⚡ *高优先级*
- 分支预测（2 位饱和计数器，BTB）
- Cache 层次结构（I-Cache，带写回的 D-Cache）
- 更大的 TLB（16 → 64 项）
- 超标量执行（双发射）

### 测试与验证（质量）
- **官方 RISC-V F/D 兼容性测试** 🧪 *高优先级*
- **混合指令调试** 🔀 *高优先级*
- 对关键路径进行形式化验证
- 性能基准测试（Dhrystone, CoreMark, SPEC）

### 系统特性（功能）
- 中断控制器（PLIC - Platform-Level Interrupt Controller）
- 定时器（CLINT - Core-Local Interruptor）
- 调试模块（JTAG，硬件断点）
- 性能计数器（周期、指令、缓存未命中计数）
- 物理内存保护（PMP）

### 硬件部署（实际应用）
- FPGA 综合与验证
- 外设接口（UART, GPIO, SPI, I2C）
- Boot ROM 与引导加载程序
- 运行 Linux 或 xv6-riscv
- 多核/SMP 支持
