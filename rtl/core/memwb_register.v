// MEM/WB Pipeline Register
// Latches outputs from Memory stage for use in Write-Back stage
// No stall or flush needed (last pipeline stage)
// Updated: 2025-10-10 - Parameterized for XLEN (32/64-bit support)

`include "config/rv_config.vh"

module memwb_register #(
  parameter XLEN = `XLEN,  // Data/address width: 32 or 64 bits
  parameter FLEN = `FLEN   // FP register width: 32 or 64 bits
) (
  input  wire             clk,
  input  wire             reset_n,

  // Inputs from MEM stage
  input  wire [XLEN-1:0]  alu_result_in,      // Propagated from EX
  input  wire [XLEN-1:0]  mem_read_data_in,   // Integer load data (lower bits)
  input  wire [FLEN-1:0]  fp_mem_read_data_in,// FP load data (full FLD for RV32D)
  input  wire [4:0]       rd_addr_in,
  input  wire [XLEN-1:0]  pc_plus_4_in,       // For JAL/JALR

  // Control signals from MEM stage
  input  wire        reg_write_in,
  input  wire [2:0]  wb_sel_in,          // Write-back source select
  input  wire        valid_in,

  // M extension result from MEM stage
  input  wire [XLEN-1:0] mul_div_result_in,

  // A extension result from MEM stage
  input  wire [XLEN-1:0] atomic_result_in,

  // F/D extension signals from MEM stage
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
  input  wire             fp_fmt_in,             // FP format: 0=single, 1=double

  // CSR signals from MEM stage
  input  wire [XLEN-1:0] csr_rdata_in,       // CSR read data
  input  wire            csr_we_in,          // CSR write enable

  // Outputs to WB stage
  output reg  [XLEN-1:0]  alu_result_out,
  output reg  [XLEN-1:0]  mem_read_data_out,   // Integer load data
  output reg  [FLEN-1:0]  fp_mem_read_data_out,// FP load data
  output reg  [4:0]       rd_addr_out,
  output reg  [XLEN-1:0]  pc_plus_4_out,

  // Control signals to WB stage
  output reg         reg_write_out,
  output reg  [2:0]  wb_sel_out,
  output reg         valid_out,

  // M extension result to WB stage
  output reg  [XLEN-1:0] mul_div_result_out,

  // A extension result to WB stage
  output reg  [XLEN-1:0] atomic_result_out,

  // F/D extension signals to WB stage
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
  output reg              fp_fmt_out,            // FP format: 0=single, 1=double

  // CSR signals to WB stage
  output reg  [XLEN-1:0] csr_rdata_out,
  output reg             csr_we_out
);

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset: clear all outputs
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
      // Normal operation: latch all values
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
