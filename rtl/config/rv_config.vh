// rv_config.vh - RISC-V 内核配置参数
// 用于参数化不同内核变体的集中配置文件
// 作者: RV1 项目组
// 日期: 2025-10-10
// 更新: 2025-10-23 - 新增 C 扩展配置说明

`ifndef RV_CONFIG_VH
`define RV_CONFIG_VH

// ============================================================================
// 重要：C 扩展配置要求
// ============================================================================
//
// 在运行带“压缩指令”的测试时，你必须使用一个
// 设置了 ENABLE_C_EXT=1 的配置：
//
//   ✅ 正确示例:   -DCONFIG_RV32IMC, -DCONFIG_RV32IMAFC, -DCONFIG_RV32IMAFDC
//   ❌ 错误示例:   -DCONFIG_RV32I, -DCONFIG_RV32IM, -DCONFIG_RV32IMA
//
// 原因：异常单元会根据 ENABLE_C_EXT 检查 PC 对齐情况。
//      如果没有启用 C 扩展，则 2 字节对齐的 PC（0x02, 0x06 等）
//      会触发“指令地址未对齐”异常，导致在地址 0x00 的无限陷入循环。
//
// 详细分析参见 KNOWN_ISSUES.md。
// ============================================================================

// ============================================================================
// 架构位宽配置
// ============================================================================

// XLEN：整数寄存器与数据通路位宽（32 或 64）
// 阶段 3（2025-11-03）：默认改为 64，用于 RV64 升级
`ifndef XLEN
  `define XLEN 64
`endif

// FLEN：浮点寄存器位宽（0=无 FPU，32=仅 F，64=F+D）
`ifndef FLEN
  `define FLEN 64  // 默认 64，支持 F 与 D 两种扩展
`endif

// DWIDTH：数据存储器接口位宽（用 FLEN 支持 RV32D 中的 64 位浮点读写）
// 对于 RV32I/M/A/C：XLEN=32, FLEN=0, DWIDTH 应为 32
// 对于 RV32F：XLEN=32, FLEN=32, DWIDTH=32
// 对于 RV32D：XLEN=32, FLEN=64, DWIDTH=64
`ifndef DWIDTH
  `define DWIDTH `FLEN  // 使用 FLEN 作为数据位宽以支持宽浮点读写
`endif

// 派生参数
`define XLEN_MINUS_1 (`XLEN - 1)
`define SHAMT_WIDTH  ($clog2(`XLEN))  // 移位量位宽：RV32 为 5，RV64 为 6

// ============================================================================
// ISA 扩展配置
// ============================================================================

// M 扩展：整数乘除
`ifndef ENABLE_M_EXT
  `define ENABLE_M_EXT 0
`endif

// A 扩展：原子指令
`ifndef ENABLE_A_EXT
  `define ENABLE_A_EXT 0
`endif

// C 扩展：压缩指令（16 位）
`ifndef ENABLE_C_EXT
  `define ENABLE_C_EXT 0
`endif

// Zicsr：CSR 指令（当前始终启用）
`ifndef ENABLE_ZICSR
  `define ENABLE_ZICSR 1
`endif

// Zifencei：指令栅栏（需要 I-Cache）
`ifndef ENABLE_ZIFENCEI
  `define ENABLE_ZIFENCEI 0
`endif

// ============================================================================
// Cache 配置
// ============================================================================

// 指令 Cache
`ifndef ICACHE_SIZE
  `define ICACHE_SIZE 4096  // 默认 4KB
`endif

`ifndef ICACHE_LINE_SIZE
  `define ICACHE_LINE_SIZE 32  // 32 字节（8 个字）
`endif

`ifndef ICACHE_WAYS
  `define ICACHE_WAYS 1  // 默认直接映射
`endif

// 数据 Cache
`ifndef DCACHE_SIZE
  `define DCACHE_SIZE 4096  // 默认 4KB
`endif

`ifndef DCACHE_LINE_SIZE
  `define DCACHE_LINE_SIZE 32  // 32 字节（8 个字）
`endif

`ifndef DCACHE_WAYS
  `define DCACHE_WAYS 1  // 默认直接映射
`endif

// L2 Cache（用于多核）
`ifndef L2_CACHE_SIZE
  `define L2_CACHE_SIZE 65536  // 默认 64KB
`endif

`ifndef L2_CACHE_ENABLE
  `define L2_CACHE_ENABLE 0
`endif

// ============================================================================
// 多核配置
// ============================================================================

`ifndef NUM_CORES
  `define NUM_CORES 1
`endif

`ifndef ENABLE_COHERENCY
  `define ENABLE_COHERENCY 0
`endif

// ============================================================================
// 存储器配置
// ============================================================================

// 存储器大小（以字节为单位）
// 阶段 2（2025-10-27）：为 FreeRTOS 将 DMEM 扩展到 1MB
// 阶段 3（2025-11-03）：为 xv6/Linux 将 IMEM 扩展到 1MB，DMEM 扩展到 4MB
`ifndef IMEM_SIZE
  `define IMEM_SIZE 1048576  // 1MB 指令存储器（阶段 3：RV64 升级）
`endif

`ifndef DMEM_SIZE
  `define DMEM_SIZE 4194304  // 4MB 数据存储器（阶段 3：RV64 升级，xv6 准备）
`endif

// 地址位宽（根据存储器大小推导）
`define IMEM_ADDR_WIDTH $clog2(`IMEM_SIZE)
`define DMEM_ADDR_WIDTH $clog2(`DMEM_SIZE)

// TLB 配置
`ifndef TLB_ENTRIES
  `define TLB_ENTRIES 16  // TLB 项数（2 的幂）
`endif

// ============================================================================
// 流水线配置
// ============================================================================

`ifndef PIPELINE_STAGES
  `define PIPELINE_STAGES 5  // 经典 5 级流水线
`endif

// ============================================================================
// 调试与验证
// ============================================================================

`ifndef ENABLE_ASSERTIONS
  `define ENABLE_ASSERTIONS 1
`endif

`ifndef ENABLE_COVERAGE
  `define ENABLE_COVERAGE 0
`endif

// ============================================================================
// 常用预设
// ============================================================================
//
// 若要使用某个预设，在包含 rv_config.vh 之前定义以下之一：
//
// RV32I - 最小 32 位基础 ISA
//   -DCONFIG_RV32I
//
// RV32IM - 带乘除的 32 位
//   -DCONFIG_RV32IM
//
// RV32IMC - 带 M 和压缩指令的 32 位
//   -DCONFIG_RV32IMC
//
// RV64I - 64 位基础 ISA
//   -DCONFIG_RV64I
//
// RV64GC - 64 位全功能（IMAFC + Zicsr + Zifencei）
//   -DCONFIG_RV64GC

`ifdef CONFIG_RV32I
  `undef XLEN
  `define XLEN 32
  // 仅当未从命令行定义时才设置默认值
  `ifndef ENABLE_M_EXT
    `define ENABLE_M_EXT 0
  `endif
  `ifndef ENABLE_A_EXT
    `define ENABLE_A_EXT 0
  `endif
  `ifndef ENABLE_C_EXT
    `define ENABLE_C_EXT 0
  `endif
`endif

`ifdef CONFIG_RV32IM
  `undef XLEN
  `define XLEN 32
  `define ENABLE_M_EXT 1
  // 仅当未从命令行定义时才设置默认值
  `ifndef ENABLE_A_EXT
    `define ENABLE_A_EXT 0
  `endif
  `ifndef ENABLE_C_EXT
    `define ENABLE_C_EXT 0
  `endif
`endif

`ifdef CONFIG_RV32IMA
  `undef XLEN
  `define XLEN 32
  `undef ENABLE_M_EXT
  `define ENABLE_M_EXT 1
  `undef ENABLE_A_EXT
  `define ENABLE_A_EXT 1
  `undef ENABLE_C_EXT
  `define ENABLE_C_EXT 0
`endif

`ifdef CONFIG_RV32IMC
  `undef XLEN
  `define XLEN 32
  `undef ENABLE_M_EXT
  `define ENABLE_M_EXT 1
  `undef ENABLE_A_EXT
  `define ENABLE_A_EXT 0
  `undef ENABLE_C_EXT
  `define ENABLE_C_EXT 1
`endif

`ifdef CONFIG_RV32IMAF
  `undef XLEN
  `define XLEN 32
  `undef ENABLE_M_EXT
  `define ENABLE_M_EXT 1
  `undef ENABLE_A_EXT
  `define ENABLE_A_EXT 1
  `undef ENABLE_C_EXT
  `define ENABLE_C_EXT 0
  `undef ENABLE_F_EXT
  `define ENABLE_F_EXT 1
`endif

// ============================================================================
// 已废弃：CONFIG_RV64I 和 CONFIG_RV64GC
// ============================================================================
// 这些配置快捷方式已废弃，推荐使用显式定义。
// 请改用命令行定义：
//   RV64I:  -DXLEN=64
//   RV64GC: -DXLEN=64 -DENABLE_M_EXT=1 -DENABLE_A_EXT=1 -DENABLE_C_EXT=1
//
// 下方代码块保留用于向后兼容，但不会覆盖命令行定义
// （即不会对命令行参数执行 undef）。
// ============================================================================

`ifdef CONFIG_RV64I
  `undef XLEN
  `define XLEN 64
  // 对于最小 RV64I，强制关闭扩展（需要使用 undef/define 覆盖默认值）
  `undef ENABLE_M_EXT
  `define ENABLE_M_EXT 0
  `undef ENABLE_A_EXT
  `define ENABLE_A_EXT 0
  `undef ENABLE_C_EXT
  `define ENABLE_C_EXT 0
`endif

`ifdef CONFIG_RV64GC
  `undef XLEN
  `define XLEN 64
  // 对于 RV64GC，强制打开扩展（需要使用 undef/define 覆盖默认值）
  `undef ENABLE_M_EXT
  `define ENABLE_M_EXT 1
  `undef ENABLE_A_EXT
  `define ENABLE_A_EXT 1
  `undef ENABLE_C_EXT
  `define ENABLE_C_EXT 1
  `undef ENABLE_ZIFENCEI
  `define ENABLE_ZIFENCEI 1
`endif

`endif // RV_CONFIG_VH
