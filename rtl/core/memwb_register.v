// MEM/WB 流水线寄存器
// 锁存存储器阶段的输出供回写阶段使用
// 不需要停顿或清空（最后一级流水线阶段）
// 更新：2025-10-10 - 按 XLEN 参数化（支持 32/64 位）

`include "config/rv_config.vh"

module memwb_register #(
  parameter XLEN = `XLEN,  // 数据/地址位宽：32 或 64 位
  parameter FLEN = `FLEN   // 浮点寄存器位宽：32 或 64 位
) (
  input  wire             clk,
  input  wire             reset_n,

  // 来自 MEM 阶段的输入
  input  wire [XLEN-1:0]  alu_result_in,      // 从 EX 阶段传来的结果
  input  wire [XLEN-1:0]  mem_read_data_in,   // 整数加载数据（低位部分）
  input  wire [FLEN-1:0]  fp_mem_read_data_in,// 浮点加载数据（RV32D 下完整 FLD）
  input  wire [4:0]       rd_addr_in,
  input  wire [XLEN-1:0]  pc_plus_4_in,       // 用于 JAL/JALR

  // 来自 MEM 阶段的控制信号
  input  wire        reg_write_in,
  input  wire [2:0]  wb_sel_in,          // 回写源选择
  input  wire        valid_in,

  // 来自 MEM 阶段的 M 扩展结果
  input  wire [XLEN-1:0] mul_div_result_in,

  // 来自 MEM 阶段的 A 扩展结果
  input  wire [XLEN-1:0] atomic_result_in,

  // 来自 MEM 阶段的 F/D 扩展信号
  input  wire [FLEN-1:0]  fp_result_in,
  input  wire [XLEN-1:0]  int_result_fp_in,
  input  wire [4:0]       fp_rd_addr_in,
  input  wire             fp_reg_write_in,
  input  wire             int_reg_write_fp_in,
  input  wire             fp_flag_nv_in,
  input  wire             fp_flag_dz_in,
  input  wire             fp_flag_of_in,
  input  wire             fp_flag_uf_in,
  input  wire             fp_flag_nx_in,
  input  wire             fp_fmt_in,             // 浮点格式：0=单精度，1=双精度

  // 来自 MEM 阶段的 CSR 信号
  input  wire [XLEN-1:0] csr_rdata_in,       // CSR 读数据
  input  wire            csr_we_in,          // CSR 写使能

  // 输出到 WB 阶段
  output reg  [XLEN-1:0]  alu_result_out,
  output reg  [XLEN-1:0]  mem_read_data_out,   // 整数加载数据
  output reg  [FLEN-1:0]  fp_mem_read_data_out,// 浮点加载数据
  output reg  [4:0]       rd_addr_out,
  output reg  [XLEN-1:0]  pc_plus_4_out,

  // 输出到 WB 阶段的控制信号
  output reg         reg_write_out,
  output reg  [2:0]  wb_sel_out,
  output reg         valid_out,

  // 输出到 WB 阶段的 M 扩展结果
  output reg  [XLEN-1:0] mul_div_result_out,

  // 输出到 WB 阶段的 A 扩展结果
  output reg  [XLEN-1:0] atomic_result_out,

  // 输出到 WB 阶段的 F/D 扩展信号
  output reg  [FLEN-1:0]  fp_result_out,
  output reg  [XLEN-1:0]  int_result_fp_out,
  output reg  [4:0]       fp_rd_addr_out,
  output reg              fp_reg_write_out,
  output reg              int_reg_write_fp_out,
  output reg              fp_flag_nv_out,
  output reg              fp_flag_dz_out,
  output reg              fp_flag_of_out,
  output reg              fp_flag_uf_out,
  output reg              fp_flag_nx_out,
  output reg              fp_fmt_out,            // 浮点格式：0=单精度，1=双精度

  // 输出到 WB 阶段的 CSR 信号
  output reg  [XLEN-1:0] csr_rdata_out,
  output reg             csr_we_out
);

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // 复位：清除所有输出
      alu_result_out        <= {XLEN{1'b0}};
      mem_read_data_out     <= {XLEN{1'b0}};
      fp_mem_read_data_out  <= {FLEN{1'b0}};
      rd_addr_out           <= 5'h0;
      pc_plus_4_out         <= {XLEN{1'b0}};

      reg_write_out      <= 1'b0;
      wb_sel_out         <= 3'b0;
      valid_out          <= 1'b0;

      mul_div_result_out <= {XLEN{1'b0}};

      atomic_result_out  <= {XLEN{1'b0}};

      fp_result_out      <= {FLEN{1'b0}};
      int_result_fp_out  <= {XLEN{1'b0}};
      fp_rd_addr_out     <= 5'h0;
      fp_reg_write_out   <= 1'b0;
      int_reg_write_fp_out <= 1'b0;
      fp_flag_nv_out     <= 1'b0;
      fp_flag_dz_out     <= 1'b0;
      fp_flag_of_out     <= 1'b0;
      fp_flag_uf_out     <= 1'b0;
      fp_flag_nx_out     <= 1'b0;
      fp_fmt_out         <= 1'b0;

      csr_rdata_out      <= {XLEN{1'b0}};
      csr_we_out         <= 1'b0;
    end else begin
      // 正常工作：锁存所有值
      alu_result_out        <= alu_result_in;
      mem_read_data_out     <= mem_read_data_in;
      fp_mem_read_data_out  <= fp_mem_read_data_in;
      rd_addr_out           <= rd_addr_in;
      pc_plus_4_out         <= pc_plus_4_in;

      reg_write_out      <= reg_write_in;
      wb_sel_out         <= wb_sel_in;
      valid_out          <= valid_in;

      mul_div_result_out <= mul_div_result_in;

      atomic_result_out  <= atomic_result_in;

      fp_result_out      <= fp_result_in;
      int_result_fp_out  <= int_result_fp_in;
      fp_rd_addr_out     <= fp_rd_addr_in;
      fp_reg_write_out   <= fp_reg_write_in;
      int_reg_write_fp_out <= int_reg_write_fp_in;
      fp_flag_nv_out     <= fp_flag_nv_in;
      fp_flag_dz_out     <= fp_flag_dz_in;
      fp_flag_of_out     <= fp_flag_of_in;
      fp_flag_uf_out     <= fp_flag_uf_in;
      fp_flag_nx_out     <= fp_flag_nx_in;
      fp_fmt_out         <= fp_fmt_in;

      csr_rdata_out      <= csr_rdata_in;
      csr_we_out         <= csr_we_in;
    end
  end

endmodule
