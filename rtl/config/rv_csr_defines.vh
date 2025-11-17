// rv_csr_defines.vh
// RISC-V CSR 常量与定义
//
// 该头文件包含内核中所有与 CSR 相关的共享常量。
// 作为 CSR 地址、位位置、特权级、异常/中断原因码的唯一“真值来源”。
//
// 参考：RISC-V Privileged Specification v1.12
//
// 用法: `include "config/rv_csr_defines.vh"

`ifndef RV_CSR_DEFINES_VH
`define RV_CSR_DEFINES_VH

// =============================================================================
// 特权模式编码 (RISC-V 规范 第 1.2 节)
// =============================================================================
// 注意: 特权级 2'b10 保留供将来使用

localparam [1:0] PRIV_U_MODE = 2'b00;  // 用户模式
localparam [1:0] PRIV_S_MODE = 2'b01;  // 监督模式
localparam [1:0] PRIV_M_MODE = 2'b11;  // 机器模式

// =============================================================================
// 机器级 CSR 地址 (RISC-V 规范 第 2 章)
// =============================================================================

// 机器信息寄存器 (只读)
localparam [11:0] CSR_MVENDORID = 12'hF11;  // 供应商 ID
localparam [11:0] CSR_MARCHID   = 12'hF12;  // 架构 ID
localparam [11:0] CSR_MIMPID    = 12'hF13;  // 实现 ID
localparam [11:0] CSR_MHARTID   = 12'hF14;  // 硬件线程 ID

// 机器陷入设置
localparam [11:0] CSR_MSTATUS   = 12'h300;  // 机器状态寄存器
localparam [11:0] CSR_MISA      = 12'h301;  // ISA 与扩展
localparam [11:0] CSR_MEDELEG   = 12'h302;  // 机器异常委托
localparam [11:0] CSR_MIDELEG   = 12'h303;  // 机器中断委托
localparam [11:0] CSR_MIE       = 12'h304;  // 机器中断使能
localparam [11:0] CSR_MTVEC     = 12'h305;  // 机器陷入处理程序基地址

// 机器陷入处理
localparam [11:0] CSR_MSCRATCH  = 12'h340;  // 机器暂存寄存器
localparam [11:0] CSR_MEPC      = 12'h341;  // 机器异常程序计数器
localparam [11:0] CSR_MCAUSE    = 12'h342;  // 机器陷入原因
localparam [11:0] CSR_MTVAL     = 12'h343;  // 机器错误地址或指令
localparam [11:0] CSR_MIP       = 12'h344;  // 机器中断挂起

// =============================================================================
// 监督级 CSR 地址 (RISC-V 规范 第 4 章)
// =============================================================================

// 监督陷入设置
localparam [11:0] CSR_SSTATUS   = 12'h100;  // 监督状态寄存器
localparam [11:0] CSR_SIE       = 12'h104;  // 监督中断使能
localparam [11:0] CSR_STVEC     = 12'h105;  // 监督陷入处理程序基地址

// 监督陷入处理
localparam [11:0] CSR_SSCRATCH  = 12'h140;  // 监督暂存寄存器
localparam [11:0] CSR_SEPC      = 12'h141;  // 监督异常程序计数器
localparam [11:0] CSR_SCAUSE    = 12'h142;  // 监督陷入原因
localparam [11:0] CSR_STVAL     = 12'h143;  // 监督错误地址或指令
localparam [11:0] CSR_SIP       = 12'h144;  // 监督中断挂起

// 监督地址转换与保护
localparam [11:0] CSR_SATP      = 12'h180;  // 监督地址转换与保护

// =============================================================================
// 浮点 CSR 地址 (RISC-V 规范 第 11.2 节)
// =============================================================================

localparam [11:0] CSR_FFLAGS    = 12'h001;  // 浮点异常标志
localparam [11:0] CSR_FRM       = 12'h002;  // 浮点舍入模式
localparam [11:0] CSR_FCSR      = 12'h003;  // 浮点控制与状态寄存器

// =============================================================================
// CSR 指令操作码 (funct3 字段)
// =============================================================================

localparam [2:0] CSR_RW  = 3'b001;  // CSRRW  - 读/写
localparam [2:0] CSR_RS  = 3'b010;  // CSRRS  - 读并置位
localparam [2:0] CSR_RC  = 3'b011;  // CSRRC  - 读并清零
localparam [2:0] CSR_RWI = 3'b101;  // CSRRWI - 读/写立即数
localparam [2:0] CSR_RSI = 3'b110;  // CSRRSI - 读并置位立即数
localparam [2:0] CSR_RCI = 3'b111;  // CSRRCI - 读并清零立即数

// =============================================================================
// MSTATUS/SSTATUS 位位置 (RISC-V 规范 第 3.1.6 节)
// =============================================================================

// 中断使能位
localparam MSTATUS_SIE_BIT  = 1;   // 监督中断使能
localparam MSTATUS_MIE_BIT  = 3;   // 机器中断使能

// 先前中断使能位
localparam MSTATUS_SPIE_BIT = 5;   // 监督先前中断使能
localparam MSTATUS_MPIE_BIT = 7;   // 机器先前中断使能

// 先前特权模式位
localparam MSTATUS_SPP_BIT  = 8;   // 监督先前特权级 (1 位: 0=U, 1=S)
localparam MSTATUS_MPP_LSB  = 11;  // 机器先前特权级 [11:12] (2 位)
localparam MSTATUS_MPP_MSB  = 12;

// 浮点单元状态位
localparam MSTATUS_FS_LSB   = 13;  // FPU 状态 [13:14] (2 位)
localparam MSTATUS_FS_MSB   = 14;
// FS 编码: 00=关闭, 01=初始, 10=干净, 11=脏

// 内存访问控制位
localparam MSTATUS_SUM_BIT  = 18;  // 监督访问用户内存
localparam MSTATUS_MXR_BIT  = 19;  // 可执行视为可读 (Make eXecutable Readable)

// =============================================================================
// 异常原因码 (RISC-V 规范 表 3.6)
// =============================================================================
// 注意: mcause[XLEN-1] = 1 表示中断, 0 表示异常
// 当 mcause[XLEN-1] = 0 时，这些编码放在 mcause[XLEN-2:0]

localparam [4:0] CAUSE_INST_ADDR_MISALIGNED  = 5'd0;   // 指令地址未对齐
localparam [4:0] CAUSE_INST_ACCESS_FAULT     = 5'd1;   // 指令访问错误
localparam [4:0] CAUSE_ILLEGAL_INST          = 5'd2;   // 非法指令
localparam [4:0] CAUSE_BREAKPOINT            = 5'd3;   // 断点
localparam [4:0] CAUSE_LOAD_ADDR_MISALIGNED  = 5'd4;   // 读地址未对齐
localparam [4:0] CAUSE_LOAD_ACCESS_FAULT     = 5'd5;   // 读访问错误
localparam [4:0] CAUSE_STORE_ADDR_MISALIGNED = 5'd6;   // 写/AMO 地址未对齐
localparam [4:0] CAUSE_STORE_ACCESS_FAULT    = 5'd7;   // 写/AMO 访问错误
localparam [4:0] CAUSE_ECALL_FROM_U_MODE     = 5'd8;   // 来自 U 模式的环境调用
localparam [4:0] CAUSE_ECALL_FROM_S_MODE     = 5'd9;   // 来自 S 模式的环境调用
localparam [4:0] CAUSE_ECALL_FROM_M_MODE     = 5'd11;  // 来自 M 模式的环境调用
localparam [4:0] CAUSE_INST_PAGE_FAULT       = 5'd12;  // 指令页错误
localparam [4:0] CAUSE_LOAD_PAGE_FAULT       = 5'd13;  // 读页错误
localparam [4:0] CAUSE_STORE_PAGE_FAULT      = 5'd15;  // 写/AMO 页错误

// =============================================================================
// 中断原因码 (RISC-V 规范 表 3.6)
// =============================================================================
// 注意: mcause[XLEN-1] = 1 表示中断
// 当 mcause[XLEN-1] = 1 时，这些编码放在 mcause[XLEN-2:0]

localparam [4:0] INT_SUPERVISOR_SOFTWARE  = 5'd1;   // 监督软件中断
localparam [4:0] INT_MACHINE_SOFTWARE     = 5'd3;   // 机器软件中断
localparam [4:0] INT_SUPERVISOR_TIMER     = 5'd5;   // 监督定时器中断
localparam [4:0] INT_MACHINE_TIMER        = 5'd7;   // 机器定时器中断
localparam [4:0] INT_SUPERVISOR_EXTERNAL  = 5'd9;   // 监督外部中断
localparam [4:0] INT_MACHINE_EXTERNAL     = 5'd11;  // 机器外部中断

`endif // RV_CSR_DEFINES_VH
