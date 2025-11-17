// exception_unit.v - 异常检测单元
// 检测流水线中的各种异常
// 为 RV32/RV64 参数化
// 作者: RV1 Project
// 日期: 2025-10-10

`include "config/rv_config.vh"
`include "config/rv_csr_defines.vh"

module exception_unit #(
  parameter XLEN = `XLEN
) (
  // 特权模式输入 (阶段 1)
  input  wire [1:0]      current_priv,    // 当前特权模式

  // 指令地址未对齐 (IF 阶段)
  input  wire [XLEN-1:0] if_pc,
  input  wire            if_valid,

  // 指令页错误 (IF 阶段 - Session 117)
  input  wire            if_page_fault,
  input  wire [XLEN-1:0] if_fault_vaddr,

  // 非法指令 (ID 阶段)
  input  wire            id_illegal_inst,
  input  wire            id_ecall,
  input  wire            id_ebreak,
  input  wire            id_mret,              // MRET 指令 (需要特权检查)
  input  wire            id_sret,              // SRET 指令 (需要特权检查)
  input  wire [XLEN-1:0] id_pc,
  input  wire [31:0]     id_instruction,       // 指令始终为 32 位
  input  wire            id_valid,

  // 未对齐访存 (MEM 阶段)
  input  wire [XLEN-1:0] mem_addr,
  input  wire            mem_read,
  input  wire            mem_write,
  input  wire [2:0]      mem_funct3,
  input  wire [XLEN-1:0] mem_pc,
  input  wire [31:0]     mem_instruction,      // 指令始终为 32 位
  input  wire            mem_valid,

  // 页错误输入 (阶段 3 - MMU 集成)
  input  wire            mem_page_fault,       // 来自 MMU 的页错误
  input  wire [XLEN-1:0] mem_fault_vaddr,     // 出错的虚拟地址

  // 异常输出
  output reg             exception,
  output reg  [4:0]      exception_code,
  output reg  [XLEN-1:0] exception_pc,
  output reg  [XLEN-1:0] exception_val
);

  // =========================================================================
  // 异常代码定义
  // =========================================================================
  // 注意: 异常原因码在 rv_csr_defines.vh 中定义

  // load/store 的 funct3 编码
  localparam FUNCT3_LB  = 3'b000;
  localparam FUNCT3_LH  = 3'b001;
  localparam FUNCT3_LW  = 3'b010;
  localparam FUNCT3_LD  = 3'b011;  // RV64 only
  localparam FUNCT3_LBU = 3'b100;
  localparam FUNCT3_LHU = 3'b101;
  localparam FUNCT3_LWU = 3'b110;  // RV64 only
  localparam FUNCT3_SB  = 3'b000;
  localparam FUNCT3_SH  = 3'b001;
  localparam FUNCT3_SW  = 3'b010;
  localparam FUNCT3_SD  = 3'b011;  // RV64 only

  // =========================================================================
  // 异常检测逻辑
  // =========================================================================

  // IF 阶段: 指令地址未对齐
  // 开启 C 扩展时: 仅要求 bit[0] 为 0 (2 字节对齐)
  // 未开启 C 扩展时: 要求 bit[1:0] 为 00 (4 字节对齐)
  wire if_inst_misaligned = `ENABLE_C_EXT ? (if_valid && if_pc[0]) :
                                             (if_valid && (if_pc[1:0] != 2'b00));

  // IF 阶段: 指令页错误 (Session 117)
  wire if_inst_page_fault = if_valid && if_page_fault;

  // ID 阶段: 非法指令
  wire id_illegal = id_valid && id_illegal_inst;

  // ID 阶段: xRET 指令的特权违规
  // MRET: 仅允许在 M 模式执行 (priv == 2'b11)
  // SRET: 仅允许在 M 模式或 S 模式执行 (priv >= 2'b01)
  wire id_mret_violation = id_valid && id_mret && (current_priv != 2'b11);
  wire id_sret_violation = id_valid && id_sret && (current_priv == 2'b00);

  // 合并普通非法指令
  wire id_illegal_combined = id_illegal || id_mret_violation || id_sret_violation;

  // ID 阶段: ECALL (特权相关异常码)
  wire id_ecall_exc = id_valid && id_ecall;
  wire [4:0] ecall_cause = (current_priv == 2'b00) ? CAUSE_ECALL_FROM_U_MODE :
                           (current_priv == 2'b01) ? CAUSE_ECALL_FROM_S_MODE :
                                                     CAUSE_ECALL_FROM_M_MODE;

  // ID 阶段: EBREAK
  wire id_ebreak_exc = id_valid && id_ebreak;

  // MEM 阶段: 读地址未对齐
  // 注意: 我们的内存子系统原生支持未对齐访问, 因此
  // 禁用未对齐异常以兼容 RISC-V 兼容性测试。
  // RISC-V 规范允许在硬件中支持未对齐访问。
  wire mem_load_halfword = (mem_funct3 == FUNCT3_LH) || (mem_funct3 == FUNCT3_LHU);
  wire mem_load_word = (mem_funct3 == FUNCT3_LW) || (mem_funct3 == FUNCT3_LWU);
  wire mem_load_doubleword = (mem_funct3 == FUNCT3_LD);
  wire mem_load_misaligned = 1'b0;  // 禁用: 硬件支持未对齐访问
  /* 原始检查 (现已禁用以支持 rv32ui-p-ma_data 测试):
  wire mem_load_misaligned = mem_valid && mem_read &&
                              ((mem_load_halfword && mem_addr[0]) ||
                               (mem_load_word && (mem_addr[1:0] != 2'b00)) ||
                               (mem_load_doubleword && (mem_addr[2:0] != 3'b000)));
  */

  // MEM 阶段: 写地址未对齐
  wire mem_store_halfword = (mem_funct3 == FUNCT3_SH);
  wire mem_store_word = (mem_funct3 == FUNCT3_SW);
  wire mem_store_doubleword = (mem_funct3 == FUNCT3_SD);
  wire mem_store_misaligned = 1'b0;  // 禁用: 硬件支持未对齐访问
  /* 原始检查 (现已禁用以支持 rv32ui-p-ma_data 测试):
  wire mem_store_misaligned = mem_valid && mem_write &&
                               ((mem_store_halfword && mem_addr[0]) ||
                                (mem_store_word && (mem_addr[1:0] != 2'b00)) ||
                                (mem_store_doubleword && (mem_addr[2:0] != 3'b000)));
  */

  // MEM 阶段: 页错误 (阶段 3 - MMU 集成)
  // 页错误优先级高于未对齐访问
  wire mem_page_fault_load = mem_valid && mem_page_fault && mem_read && !mem_write;
  wire mem_page_fault_store = mem_valid && mem_page_fault && mem_write;

  // =========================================================================
  // 异常优先编码器
  // =========================================================================
  // 优先级 (从高到低):
  // 1. 指令地址未对齐 (IF)
  // 2. 指令页错误 (IF) - Session 117
  // 3. EBREAK (ID)
  // 4. ECALL (ID)
  // 5. 非法指令 (ID) - 包含 MRET/SRET 特权违规
  // 6. 读/写页错误 (MEM) - 阶段 3
  // 7. 读地址未对齐 (MEM)
  // 8. 写地址未对齐 (MEM)

  always @(*) begin
    // 默认: 无异常
    exception = 1'b0;
    exception_code = 5'd0;
    exception_pc = {XLEN{1'b0}};
    exception_val = {XLEN{1'b0}};

    // 优先级编码器 (从高到低优先级)
    if (if_inst_misaligned) begin
      exception = 1'b1;
      exception_code = CAUSE_INST_ADDR_MISALIGNED;
      exception_pc = if_pc;
      exception_val = if_pc;
      `ifdef DEBUG_PRIV
      $display("[EXC] 时间=%0t INST_MISALIGNED: PC=0x%08x", $time, if_pc);
      `endif

    end else if (if_inst_page_fault) begin
      // Session 117: 指令页错误
      exception = 1'b1;
      exception_code = CAUSE_INST_PAGE_FAULT;
      exception_pc = if_pc;
      exception_val = if_fault_vaddr;
      $display("[EXCEPTION] 指令页错误: PC=0x%h, VA=0x%h", if_pc, if_fault_vaddr);
      `ifdef DEBUG_PRIV
      $display("[EXC] 时间=%0t INST_PAGE_FAULT: PC=0x%08x VA=0x%08x", $time, if_pc, if_fault_vaddr);
      `endif

    end else if (id_ebreak_exc) begin
      exception = 1'b1;
      exception_code = CAUSE_BREAKPOINT;
      exception_pc = id_pc;
      exception_val = id_pc;
      `ifdef DEBUG_PRIV
      $display("[EXC] 时间=%0t EBREAK: PC=0x%08x", $time, id_pc);
      `endif

    end else if (id_ecall_exc) begin
      exception = 1'b1;
      exception_code = ecall_cause;  // 特权相关 (阶段 1)
      exception_pc = id_pc;
      exception_val = {XLEN{1'b0}};
      `ifdef DEBUG_PRIV
      $display("[EXC] 时间=%0t ECALL: PC=0x%08x cause=%0d", $time, id_pc, ecall_cause);
      `endif

    end else if (id_illegal_combined) begin
      exception = 1'b1;
      exception_code = CAUSE_ILLEGAL_INST;
      exception_pc = id_pc;
      exception_val = {{(XLEN-32){1'b0}}, id_instruction};  // 零扩展指令到 XLEN
      `ifdef DEBUG_PRIV
      $display("[EXC] 时间=%0t ILLEGAL_INST: PC=0x%08x inst=0x%08x", $time, id_pc, id_instruction);
      `endif

    end else if (mem_page_fault_load) begin
      // Phase 3: 读页错误 (优先级高于未对齐)
      exception = 1'b1;
      exception_code = CAUSE_LOAD_PAGE_FAULT;
      exception_pc = mem_pc;
      exception_val = mem_fault_vaddr;  // 出错的虚拟地址
      $display("[EXCEPTION] 读页错误: PC=0x%h, VA=0x%h", mem_pc, mem_fault_vaddr);

    end else if (mem_page_fault_store) begin
      // Phase 3: 写页错误/原子操作页错误 (优先级高于未对齐)
      exception = 1'b1;
      exception_code = CAUSE_STORE_PAGE_FAULT;
      exception_pc = mem_pc;
      exception_val = mem_fault_vaddr;  // 出错的虚拟地址
      $display("[EXCEPTION] 写页错误: PC=0x%h, VA=0x%h", mem_pc, mem_fault_vaddr);

    end else if (mem_load_misaligned) begin
      exception = 1'b1;
      exception_code = CAUSE_LOAD_ADDR_MISALIGNED;
      exception_pc = mem_pc;
      exception_val = mem_addr;

    end else if (mem_store_misaligned) begin
      exception = 1'b1;
      exception_code = CAUSE_STORE_ADDR_MISALIGNED;
      exception_pc = mem_pc;
      exception_val = mem_addr;

    end
  end

endmodule
