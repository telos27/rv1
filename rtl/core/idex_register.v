// ID/EX 流水线寄存器
// 存储来自指令解码阶段的输出，以供执行阶段使用
// 支持刷新（插入 NOP 气泡以处理冒险/分支）
// 更新日期：2025-10-10 - 针对 XLEN 参数化（支持 32/64 位）

`include "config/rv_config.vh"

module idex_register #(
  parameter XLEN = `XLEN,  // 数据/地址宽度：32 或 64 位
  parameter FLEN = `FLEN   // FP 寄存器宽度：32 或 64 位
) (
  input  wire             clk,
  input  wire             reset_n,
  input  wire             hold,            // 保持寄存器（不更新）
  input  wire             flush,           // 清除为 NOP（用于加载-使用或分支）

  // 来自 ID 阶段的输入
  input  wire [XLEN-1:0]  pc_in,
  input  wire [XLEN-1:0]  rs1_data_in,
  input  wire [XLEN-1:0]  rs2_data_in,
  input  wire [4:0]       rs1_addr_in,     // 用于转发单元
  input  wire [4:0]       rs2_addr_in,     // 用于转发单元
  input  wire [4:0]       rd_addr_in,
  input  wire [XLEN-1:0]  imm_in,
  input  wire [6:0]  opcode_in,
  input  wire [2:0]  funct3_in,
  input  wire [6:0]  funct7_in,

  // 来自 ID 阶段的控制信号
  input  wire [3:0]  alu_control_in,
  input  wire        alu_src_in,      // 0=rs2, 1=imm
  input  wire        branch_in,
  input  wire        jump_in,
  input  wire        mem_read_in,
  input  wire        mem_write_in,
  input  wire        reg_write_in,
  input  wire [2:0]  wb_sel_in,       // 写回源选择
  input  wire        valid_in,

  // 来自 ID 阶段的 M 扩展信号
  input  wire        is_mul_div_in,
  input  wire [3:0]  mul_div_op_in,
  input  wire        is_word_op_in,

  // 来自 ID 阶段的 A 扩展信号
  input  wire        is_atomic_in,
  input  wire [4:0]  funct5_in,
  input  wire        aq_in,
  input  wire        rl_in,

  // 来自 ID 阶段的 F/D 扩展信号
  input  wire [FLEN-1:0] fp_rs1_data_in,      // FP 寄存器 rs1 数据
  input  wire [FLEN-1:0] fp_rs2_data_in,      // FP 寄存器 rs2 数据
  input  wire [FLEN-1:0] fp_rs3_data_in,      // FP 寄存器 rs3 数据（用于 FMA）
  input  wire [4:0]      fp_rs1_addr_in,      // FP rs1 地址
  input  wire [4:0]      fp_rs2_addr_in,      // FP rs2 地址
  input  wire [4:0]      fp_rs3_addr_in,      // FP rs3 地址
  input  wire [4:0]      fp_rd_addr_in,       // FP rd 地址
  input  wire            fp_reg_write_in,     // FP 寄存器写使能
  input  wire            int_reg_write_fp_in, // 整数寄存器写入（FP 比较/分类/FMV.X.W）
  input  wire            fp_mem_op_in,        // FP 内存操作（加载/存储）
  input  wire            fp_alu_en_in,        // FP ALU 使能
  input  wire [4:0]      fp_alu_op_in,        // FP ALU 操作
  input  wire [2:0]      fp_rm_in,            // FP 舍入模式
  input  wire            fp_use_dynamic_rm_in,// 使用动态舍入模式
  input  wire            fp_fmt_in,           // FP 格式：0=单精度，1=双精度

  // 来自 ID 阶段的 CSR 信号
  input  wire [11:0]      csr_addr_in,
  input  wire             csr_we_in,
  input  wire             csr_src_in,      // 0=rs1, 1=uimm
  input  wire [XLEN-1:0]  csr_wdata_in,    // rs1 数据或 uimm（XLEN 宽）
  input  wire             is_csr_in,       // CSR 指令

  // 来自 ID 阶段的异常信号
  input  wire        is_ecall_in,
  input  wire        is_ebreak_in,
  input  wire        is_mret_in,
  input  wire        is_sret_in,
  input  wire        is_sfence_vma_in,
  input  wire        illegal_inst_in,
  input  wire [31:0] instruction_in,  // 用于异常值

  // 来自 ID 阶段的 C 扩展信号
  input  wire        is_compressed_in, // 指令最初是否被压缩？

  // 输出到 EX 阶段
  output reg  [XLEN-1:0]  pc_out,
  output reg  [XLEN-1:0]  rs1_data_out,
  output reg  [XLEN-1:0]  rs2_data_out,
  output reg  [4:0]       rs1_addr_out,
  output reg  [4:0]       rs2_addr_out,
  output reg  [4:0]       rd_addr_out,
  output reg  [XLEN-1:0]  imm_out,
  output reg  [6:0]  opcode_out,
  output reg  [2:0]  funct3_out,
  output reg  [6:0]  funct7_out,

  // 控制信号到 EX 阶段
  output reg  [3:0]  alu_control_out,
  output reg         alu_src_out,
  output reg         branch_out,
  output reg         jump_out,
  output reg         mem_read_out,
  output reg         mem_write_out,
  output reg         reg_write_out,
  output reg  [2:0]  wb_sel_out,
  output reg         valid_out,

  // M 扩展信号到 EX 阶段
  output reg         is_mul_div_out,
  output reg  [3:0]  mul_div_op_out,
  output reg         is_word_op_out,

  // A 扩展信号到 EX 阶段
  output reg         is_atomic_out,
  output reg  [4:0]  funct5_out,
  output reg         aq_out,
  output reg         rl_out,

  // F/D 扩展信号到 EX 阶段
  output reg  [FLEN-1:0] fp_rs1_data_out,
  output reg  [FLEN-1:0] fp_rs2_data_out,
  output reg  [FLEN-1:0] fp_rs3_data_out,
  output reg  [4:0]      fp_rs1_addr_out,
  output reg  [4:0]      fp_rs2_addr_out,
  output reg  [4:0]      fp_rs3_addr_out,
  output reg  [4:0]      fp_rd_addr_out,
  output reg             fp_reg_write_out,
  output reg             int_reg_write_fp_out,
  output reg             fp_mem_op_out,
  output reg             fp_alu_en_out,
  output reg  [4:0]      fp_alu_op_out,
  output reg  [2:0]      fp_rm_out,
  output reg             fp_use_dynamic_rm_out,
  output reg             fp_fmt_out,           // FP 格式：0=单精度，1=双精度

  // CSR 信号到 EX 阶段
  output reg  [11:0]      csr_addr_out,
  output reg              csr_we_out,
  output reg              csr_src_out,
  output reg  [XLEN-1:0]  csr_wdata_out,
  output reg              is_csr_out,

  // 异常信号到 EX 阶段
  output reg         is_ecall_out,
  output reg         is_ebreak_out,
  output reg         is_mret_out,
  output reg         is_sret_out,
  output reg         is_sfence_vma_out,
  output reg         illegal_inst_out,
  output reg  [31:0] instruction_out,

  // C 扩展信号到 EX 阶段
  output reg         is_compressed_out // 指令最初是否被压缩？
);

  `ifdef DEBUG_IDEX
  always @(posedge clk) begin
    if (hold) begin
      $display("[IDEX] @%0t HELD: rs1=x%0d[%h] rs2=x%0d[%h] rd=x%0d mul_div=%0b",
               $time, rs1_addr_out, rs1_data_out, rs2_addr_out, rs2_data_out, rd_addr_out, is_mul_div_out);
    end else if (!flush) begin
      $display("[IDEX] @%0t UPDATE: rs1=x%0d[%h]→[%h] rs2=x%0d[%h]→[%h] rd=x%0d→x%0d mul_div=%0b→%0b",
               $time, rs1_addr_out, rs1_data_out, rs1_data_in,
               rs2_addr_out, rs2_data_out, rs2_data_in,
               rd_addr_out, rd_addr_in, is_mul_div_out, is_mul_div_in);
    end else begin
      $display("[IDEX] @%0t FLUSH: inserting NOP bubble", $time);
    end
  end
  `endif

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // 复位：清除所有输出
      pc_out          <= {XLEN{1'b0}};
      rs1_data_out    <= {XLEN{1'b0}};
      rs2_data_out    <= {XLEN{1'b0}};
      rs1_addr_out    <= 5'h0;
      rs2_addr_out    <= 5'h0;
      rd_addr_out     <= 5'h0;
      imm_out         <= {XLEN{1'b0}};
      opcode_out      <= 7'h0;
      funct3_out      <= 3'h0;
      funct7_out      <= 7'h0;

      alu_control_out <= 4'h0;
      alu_src_out     <= 1'b0;
      branch_out      <= 1'b0;
      jump_out        <= 1'b0;
      mem_read_out    <= 1'b0;
      mem_write_out   <= 1'b0;
      reg_write_out   <= 1'b0;
      wb_sel_out      <= 3'b0;
      valid_out       <= 1'b0;

      is_mul_div_out  <= 1'b0;
      mul_div_op_out  <= 4'h0;
      is_word_op_out  <= 1'b0;

      is_atomic_out   <= 1'b0;
      funct5_out      <= 5'h0;
      aq_out          <= 1'b0;
      rl_out          <= 1'b0;

      fp_rs1_data_out <= {FLEN{1'b0}};
      fp_rs2_data_out <= {FLEN{1'b0}};
      fp_rs3_data_out <= {FLEN{1'b0}};
      fp_rs1_addr_out <= 5'h0;
      fp_rs2_addr_out <= 5'h0;
      fp_rs3_addr_out <= 5'h0;
      fp_rd_addr_out  <= 5'h0;
      fp_reg_write_out<= 1'b0;
      int_reg_write_fp_out <= 1'b0;
      fp_mem_op_out   <= 1'b0;
      fp_alu_en_out   <= 1'b0;
      fp_alu_op_out   <= 5'h0;
      fp_rm_out       <= 3'h0;
      fp_use_dynamic_rm_out <= 1'b0;
      fp_fmt_out      <= 1'b0;

      csr_addr_out    <= 12'h0;
      csr_we_out      <= 1'b0;
      csr_src_out     <= 1'b0;
      csr_wdata_out   <= {XLEN{1'b0}};
      is_csr_out      <= 1'b0;

      is_ecall_out    <= 1'b0;
      is_ebreak_out   <= 1'b0;
      is_mret_out     <= 1'b0;
      is_sret_out     <= 1'b0;
      is_sfence_vma_out <= 1'b0;
      illegal_inst_out <= 1'b0;
      instruction_out <= 32'h0;

      is_compressed_out <= 1'b0;
    end else if (flush && !hold) begin
      // 刷新：插入 NOP 气泡（清除控制信号，保留数据）
      // 注意：保持优先于刷新（M 指令必须保持不变）
      pc_out          <= pc_in;         // 保留 PC 以便调试
      rs1_data_out    <= rs1_data_in;
      rs2_data_out    <= rs2_data_in;
      rs1_addr_out    <= 5'h0;          // 清除地址
      rs2_addr_out    <= 5'h0;
      rd_addr_out     <= 5'h0;          // 清除目的地
      imm_out         <= {XLEN{1'b0}};
      opcode_out      <= 7'h0;
      funct3_out      <= 3'h0;
      funct7_out      <= 7'h0;

      // 清除所有控制信号（创建 NOP）
      alu_control_out <= 4'h0;
      alu_src_out     <= 1'b0;
      branch_out      <= 1'b0;
      jump_out        <= 1'b0;
      mem_read_out    <= 1'b0;
      mem_write_out   <= 1'b0;
      reg_write_out   <= 1'b0;          // 关键：不写寄存器
      wb_sel_out      <= 3'b0;
      valid_out       <= 1'b0;          // 标记为无效

      is_mul_div_out  <= 1'b0;
      mul_div_op_out  <= 4'h0;
      is_word_op_out  <= 1'b0;

      is_atomic_out   <= 1'b0;
      funct5_out      <= 5'h0;
      aq_out          <= 1'b0;
      rl_out          <= 1'b0;

      fp_rs1_data_out <= fp_rs1_data_in;
      fp_rs2_data_out <= fp_rs2_data_in;
      fp_rs3_data_out <= fp_rs3_data_in;
      fp_rs1_addr_out <= 5'h0;
      fp_rs2_addr_out <= 5'h0;
      fp_rs3_addr_out <= 5'h0;
      fp_rd_addr_out  <= 5'h0;          // 清除目的地
      fp_reg_write_out<= 1'b0;          // 关键：不写 FP 寄存器
      int_reg_write_fp_out <= 1'b0;     // 关键：不写 INT 寄存器
      fp_mem_op_out   <= 1'b0;
      fp_alu_en_out   <= 1'b0;
      fp_alu_op_out   <= 5'h0;
      fp_rm_out       <= 3'h0;
      fp_use_dynamic_rm_out <= 1'b0;
      fp_fmt_out      <= 1'b0;

      csr_addr_out    <= 12'h0;
      csr_we_out      <= 1'b0;          // 关键：不写 CSR
      csr_src_out     <= 1'b0;
      csr_wdata_out   <= {XLEN{1'b0}};
      is_csr_out      <= 1'b0;

      is_ecall_out    <= 1'b0;          // 关键：清除异常
      is_ebreak_out   <= 1'b0;
      is_mret_out     <= 1'b0;
      is_sret_out     <= 1'b0;
      is_sfence_vma_out <= 1'b0;
      illegal_inst_out <= 1'b0;
      instruction_out <= 32'h0;

      is_compressed_out <= 1'b0;
    end else if (!hold) begin
      // 正常操作：锁存所有值（仅当未保持时）
      pc_out          <= pc_in;
      rs1_data_out    <= rs1_data_in;
      rs2_data_out    <= rs2_data_in;
      rs1_addr_out    <= rs1_addr_in;
      rs2_addr_out    <= rs2_addr_in;
      rd_addr_out     <= rd_addr_in;
      imm_out         <= imm_in;
      opcode_out      <= opcode_in;
      funct3_out      <= funct3_in;
      funct7_out      <= funct7_in;

      alu_control_out <= alu_control_in;
      alu_src_out     <= alu_src_in;
      branch_out      <= branch_in;
      jump_out        <= jump_in;
      mem_read_out    <= mem_read_in;
      mem_write_out   <= mem_write_in;
      reg_write_out   <= reg_write_in;
      wb_sel_out      <= wb_sel_in;
      valid_out       <= valid_in;

      is_mul_div_out  <= is_mul_div_in;
      mul_div_op_out  <= mul_div_op_in;
      is_word_op_out  <= is_word_op_in;

      is_atomic_out   <= is_atomic_in;
      funct5_out      <= funct5_in;
      aq_out          <= aq_in;
      rl_out          <= rl_in;

      fp_rs1_data_out <= fp_rs1_data_in;
      fp_rs2_data_out <= fp_rs2_data_in;
      fp_rs3_data_out <= fp_rs3_data_in;
      fp_rs1_addr_out <= fp_rs1_addr_in;
      fp_rs2_addr_out <= fp_rs2_addr_in;
      fp_rs3_addr_out <= fp_rs3_addr_in;
      fp_rd_addr_out  <= fp_rd_addr_in;
      fp_reg_write_out<= fp_reg_write_in;
      int_reg_write_fp_out <= int_reg_write_fp_in;
      fp_mem_op_out   <= fp_mem_op_in;
      fp_alu_en_out   <= fp_alu_en_in;
      fp_alu_op_out   <= fp_alu_op_in;
      fp_rm_out       <= fp_rm_in;
      fp_use_dynamic_rm_out <= fp_use_dynamic_rm_in;
      fp_fmt_out      <= fp_fmt_in;

      csr_addr_out    <= csr_addr_in;
      csr_we_out      <= csr_we_in;
      csr_src_out     <= csr_src_in;
      csr_wdata_out   <= csr_wdata_in;
      is_csr_out      <= is_csr_in;

      is_ecall_out    <= is_ecall_in;
      is_ebreak_out   <= is_ebreak_in;
      is_mret_out     <= is_mret_in;
      is_sret_out     <= is_sret_in;
      is_sfence_vma_out <= is_sfence_vma_in;
      illegal_inst_out <= illegal_inst_in;
      instruction_out <= instruction_in;

      is_compressed_out <= is_compressed_in;
    end
    // 如果保持被断言，则保持先前的值（寄存器保持不变）
  end

endmodule
