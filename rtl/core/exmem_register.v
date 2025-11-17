// EX/MEM 流水级寄存器
// 锁存执行阶段的输出供访存阶段使用
// 无需停顿或冲刷水泡 (冒险在前级已处理)
// 更新: 2025-10-10 - 参数化 XLEN (支持 32/64 位)

`include "config/rv_config.vh"

module exmem_register #(
  parameter XLEN = `XLEN,  // 数据/地址宽度: 32 或 64 位
  parameter FLEN = `FLEN   // 浮点寄存器宽度: 32 或 64 位
) (
  input  wire             clk,
  input  wire             reset_n,
  input  wire             hold,           // 保持寄存器 (不更新)
  input  wire             flush,          // 清成 NOP (用于异常/陷入)

  // 来自 EX 阶段的输入
  input  wire [XLEN-1:0]  alu_result_in,
  input  wire [XLEN-1:0]  mem_write_data_in,      // 整数存储数据 (转发的 rs2)
  input  wire [FLEN-1:0]  fp_mem_write_data_in,   // 浮点存储数据 (用于 FSD)
  input  wire [4:0]       rd_addr_in,
  input  wire [XLEN-1:0]  pc_plus_4_in,           // 用于 JAL/JALR 写回
  input  wire [2:0]       funct3_in,              // 用于访存大小/有符号控制

  // 来自 EX 阶段的控制信号
  input  wire        mem_read_in,
  input  wire        mem_write_in,
  input  wire        reg_write_in,
  input  wire [2:0]  wb_sel_in,
  input  wire        valid_in,

  // 来自 EX 阶段的 M 扩展结果
  input  wire [XLEN-1:0] mul_div_result_in,

  // 来自 EX 阶段的 A 扩展结果
  input  wire [XLEN-1:0] atomic_result_in,
  input  wire            is_atomic_in,       // 原子指令标志

  // 来自 EX 阶段的 F/D 扩展信号
  input  wire [FLEN-1:0]  fp_result_in,          // 浮点结果
  input  wire [XLEN-1:0]  int_result_fp_in,      // 整数结果 (浮点比较/分类/FMV.X.W)
  input  wire [4:0]       fp_rd_addr_in,         // 浮点目的寄存器
  input  wire             fp_reg_write_in,       // 浮点寄存器写使能
  input  wire             int_reg_write_fp_in,   // 整数寄存器写使能 (来自 FP 运算)
  input  wire             fp_mem_op_in,          // 浮点访存操作标志
  input  wire             fp_flag_nv_in,         // 浮点异常标志
  input  wire             fp_flag_dz_in,
  input  wire             fp_flag_of_in,
  input  wire             fp_flag_uf_in,
  input  wire             fp_flag_nx_in,
  input  wire             fp_fmt_in,             // 浮点格式: 0=单精度, 1=双精度

  // 来自 EX 阶段的 CSR 信号
  input  wire [11:0]      csr_addr_in,
  input  wire             csr_we_in,
  input  wire [XLEN-1:0]  csr_rdata_in,    // 来自 CSR 文件的读数据

  // 来自 EX 阶段的异常信号
  input  wire        is_mret_in,
  input  wire        is_sret_in,
  input  wire        is_sfence_vma_in,
  input  wire [4:0]  rs1_addr_in,
  input  wire [4:0]  rs2_addr_in,
  input  wire [XLEN-1:0] rs1_data_in,
  input  wire [31:0] instruction_in,
  input  wire [XLEN-1:0] pc_in,           // 用于异常处理

  // 来自 EX 阶段的 MMU 翻译结果
  input  wire [XLEN-1:0] mmu_paddr_in,         // 翻译后的物理地址
  input  wire            mmu_ready_in,         // 翻译完成
  input  wire            mmu_page_fault_in,    // 页错误检测到
  input  wire [XLEN-1:0] mmu_fault_vaddr_in,   // 发生错误的虚拟地址

  // 输出到 MEM 阶段
  output reg  [XLEN-1:0]  alu_result_out,
  output reg  [XLEN-1:0]  mem_write_data_out,      // 整数存储数据
  output reg  [FLEN-1:0]  fp_mem_write_data_out,   // 浮点存储数据
  output reg  [4:0]       rd_addr_out,
  output reg  [XLEN-1:0]  pc_plus_4_out,
  output reg  [2:0]       funct3_out,

  // 输出到 MEM 阶段的控制信号
  output reg         mem_read_out,
  output reg         mem_write_out,
  output reg         reg_write_out,
  output reg  [2:0]  wb_sel_out,
  output reg         valid_out,

  // 输出到 MEM 阶段的 M 扩展结果
  output reg  [XLEN-1:0] mul_div_result_out,

  // 输出到 MEM 阶段的 A 扩展结果
  output reg  [XLEN-1:0] atomic_result_out,
  output reg             is_atomic_out,       // 原子指令标志

  // 输出到 MEM 阶段的 F/D 扩展信号
  output reg  [FLEN-1:0]  fp_result_out,
  output reg  [XLEN-1:0]  int_result_fp_out,
  output reg  [4:0]       fp_rd_addr_out,
  output reg              fp_reg_write_out,
  output reg              int_reg_write_fp_out,
  output reg              fp_mem_op_out,         // 浮点访存操作标志
  output reg              fp_flag_nv_out,
  output reg              fp_flag_dz_out,
  output reg              fp_flag_of_out,
  output reg              fp_flag_uf_out,
  output reg              fp_flag_nx_out,
  output reg              fp_fmt_out,            // 浮点格式: 0=单精度, 1=双精度

  // 输出到 MEM 阶段的 CSR 信号
  output reg  [11:0]      csr_addr_out,
  output reg              csr_we_out,
  output reg  [XLEN-1:0]  csr_rdata_out,

  // 输出到 MEM 阶段的异常信号
  output reg         is_mret_out,
  output reg         is_sret_out,
  output reg         is_sfence_vma_out,
  output reg  [4:0]  rs1_addr_out,
  output reg  [4:0]  rs2_addr_out,
  output reg  [XLEN-1:0] rs1_data_out,
  output reg  [31:0] instruction_out,
  output reg  [XLEN-1:0] pc_out,

  // 输出到 MEM 阶段的 MMU 翻译结果
  output reg  [XLEN-1:0] mmu_paddr_out,        // 翻译后的物理地址
  output reg             mmu_ready_out,        // 翻译完成
  output reg             mmu_page_fault_out,   // 页错误检测到
  output reg  [XLEN-1:0] mmu_fault_vaddr_out   // 发生错误的虚拟地址
);

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // 复位: 清空所有输出
      alu_result_out        <= {XLEN{1'b0}};
      mem_write_data_out    <= {XLEN{1'b0}};
      fp_mem_write_data_out <= {FLEN{1'b0}};
      rd_addr_out           <= 5'h0;
      pc_plus_4_out         <= {XLEN{1'b0}};
      funct3_out            <= 3'h0;

      mem_read_out       <= 1'b0;
      mem_write_out      <= 1'b0;
      reg_write_out      <= 1'b0;
      wb_sel_out         <= 3'b0;
      valid_out          <= 1'b0;

      mul_div_result_out <= {XLEN{1'b0}};

      atomic_result_out  <= {XLEN{1'b0}};
      is_atomic_out      <= 1'b0;

      fp_result_out      <= {FLEN{1'b0}};
      int_result_fp_out  <= {XLEN{1'b0}};
      fp_rd_addr_out     <= 5'h0;
      fp_reg_write_out   <= 1'b0;
      int_reg_write_fp_out <= 1'b0;
      fp_mem_op_out      <= 1'b0;
      fp_flag_nv_out     <= 1'b0;
      fp_flag_dz_out     <= 1'b0;
      fp_flag_of_out     <= 1'b0;
      fp_flag_uf_out     <= 1'b0;
      fp_flag_nx_out     <= 1'b0;
      fp_fmt_out         <= 1'b0;

      csr_addr_out       <= 12'h0;
      csr_we_out         <= 1'b0;
      csr_rdata_out      <= {XLEN{1'b0}};

      is_mret_out        <= 1'b0;
      is_sret_out        <= 1'b0;
      is_sfence_vma_out  <= 1'b0;
      rs1_addr_out       <= 5'h0;
      rs2_addr_out       <= 5'h0;
      rs1_data_out       <= {XLEN{1'b0}};
      instruction_out    <= 32'h0;
      pc_out             <= {XLEN{1'b0}};

      mmu_paddr_out      <= {XLEN{1'b0}};
      mmu_ready_out      <= 1'b0;
      mmu_page_fault_out <= 1'b0;
      mmu_fault_vaddr_out <= {XLEN{1'b0}};
    end else if (flush && !hold) begin
      // 冲刷: 插入 NOP 气泡 (清控制信号, 保留数据)
      // 关键修复: 清除页错误信号以避免异常重新触发！
      // 注意: hold 优先级高于 flush
      alu_result_out        <= alu_result_in;  // 保留用于调试
      mem_write_data_out    <= mem_write_data_in;
      fp_mem_write_data_out <= fp_mem_write_data_in;
      rd_addr_out           <= 5'h0;           // 清除目的地
      pc_plus_4_out         <= pc_plus_4_in;
      funct3_out            <= 3'h0;

      mem_read_out       <= 1'b0;              // 清除控制信号
      mem_write_out      <= 1'b0;
      reg_write_out      <= 1'b0;
      wb_sel_out         <= 3'b0;
      valid_out          <= 1'b0;              // 标记为无效

      mul_div_result_out <= {XLEN{1'b0}};

      atomic_result_out  <= {XLEN{1'b0}};
      is_atomic_out      <= 1'b0;

      fp_result_out      <= {FLEN{1'b0}};
      int_result_fp_out  <= {XLEN{1'b0}};
      fp_rd_addr_out     <= 5'h0;
      fp_reg_write_out   <= 1'b0;
      int_reg_write_fp_out <= 1'b0;
      fp_mem_op_out      <= 1'b0;
      fp_flag_nv_out     <= 1'b0;
      fp_flag_dz_out     <= 1'b0;
      fp_flag_of_out     <= 1'b0;
      fp_flag_uf_out     <= 1'b0;
      fp_flag_nx_out     <= 1'b0;
      fp_fmt_out         <= 1'b0;

      csr_addr_out       <= 12'h0;
      csr_we_out         <= 1'b0;
      csr_rdata_out      <= {XLEN{1'b0}};

      is_mret_out        <= 1'b0;
      is_sret_out        <= 1'b0;
      is_sfence_vma_out  <= 1'b0;
      rs1_addr_out       <= 5'h0;
      rs2_addr_out       <= 5'h0;
      rs1_data_out       <= {XLEN{1'b0}};
      instruction_out    <= 32'h0;
      pc_out             <= pc_in;             // 保留 PC 用于调试

      // 关键: 清除页错误信号以防止异常循环！
      mmu_paddr_out      <= {XLEN{1'b0}};
      mmu_ready_out      <= 1'b0;
      mmu_page_fault_out <= 1'b0;              // 关键修复！
      mmu_fault_vaddr_out <= {XLEN{1'b0}};
    end else if (!hold) begin
      // 只有在未保持时才更新 (M 扩展可能需要在 EX 保持指令)
      alu_result_out        <= alu_result_in;
      mem_write_data_out    <= mem_write_data_in;
      fp_mem_write_data_out <= fp_mem_write_data_in;
      rd_addr_out           <= rd_addr_in;
      pc_plus_4_out         <= pc_plus_4_in;
      funct3_out            <= funct3_in;

      mem_read_out       <= mem_read_in;
      mem_write_out      <= mem_write_in;
      reg_write_out      <= reg_write_in;
      wb_sel_out         <= wb_sel_in;
      valid_out          <= valid_in;

      mul_div_result_out <= mul_div_result_in;

      atomic_result_out  <= atomic_result_in;
      is_atomic_out      <= is_atomic_in;

      fp_result_out      <= fp_result_in;
      int_result_fp_out  <= int_result_fp_in;
      fp_rd_addr_out     <= fp_rd_addr_in;
      fp_reg_write_out   <= fp_reg_write_in;
      int_reg_write_fp_out <= int_reg_write_fp_in;
      fp_mem_op_out      <= fp_mem_op_in;
      fp_flag_nv_out     <= fp_flag_nv_in;
      fp_flag_dz_out     <= fp_flag_dz_in;
      fp_flag_of_out     <= fp_flag_of_in;
      fp_flag_uf_out     <= fp_flag_uf_in;
      fp_flag_nx_out     <= fp_flag_nx_in;
      fp_fmt_out         <= fp_fmt_in;

      csr_addr_out       <= csr_addr_in;
      csr_we_out         <= csr_we_in;
      csr_rdata_out      <= csr_rdata_in;

      is_mret_out        <= is_mret_in;
      is_sret_out        <= is_sret_in;
      is_sfence_vma_out  <= is_sfence_vma_in;
      rs1_addr_out       <= rs1_addr_in;
      rs2_addr_out       <= rs2_addr_in;
      rs1_data_out       <= rs1_data_in;
      instruction_out    <= instruction_in;
      pc_out             <= pc_in;

      mmu_paddr_out      <= mmu_paddr_in;
      mmu_ready_out      <= mmu_ready_in;
      mmu_page_fault_out <= mmu_page_fault_in;
      mmu_fault_vaddr_out <= mmu_fault_vaddr_in;
    end
    // 若 hold 置位, 保持之前的值 (寄存器保持不变)
  end

endmodule
