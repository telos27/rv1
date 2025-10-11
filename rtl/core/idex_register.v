// ID/EX Pipeline Register
// Latches outputs from Instruction Decode stage for use in Execute stage
// Supports flush (insert NOP bubble for hazards/branches)
// Updated: 2025-10-10 - Parameterized for XLEN (32/64-bit support)

`include "config/rv_config.vh"

module idex_register #(
  parameter XLEN = `XLEN  // Data/address width: 32 or 64 bits
) (
  input  wire             clk,
  input  wire             reset_n,
  input  wire             hold,            // Hold register (don't update)
  input  wire             flush,           // Clear to NOP (for load-use or branch)

  // Inputs from ID stage
  input  wire [XLEN-1:0]  pc_in,
  input  wire [XLEN-1:0]  rs1_data_in,
  input  wire [XLEN-1:0]  rs2_data_in,
  input  wire [4:0]       rs1_addr_in,     // For forwarding unit
  input  wire [4:0]       rs2_addr_in,     // For forwarding unit
  input  wire [4:0]       rd_addr_in,
  input  wire [XLEN-1:0]  imm_in,
  input  wire [6:0]  opcode_in,
  input  wire [2:0]  funct3_in,
  input  wire [6:0]  funct7_in,

  // Control signals from ID stage
  input  wire [3:0]  alu_control_in,
  input  wire        alu_src_in,      // 0=rs2, 1=imm
  input  wire        branch_in,
  input  wire        jump_in,
  input  wire        mem_read_in,
  input  wire        mem_write_in,
  input  wire        reg_write_in,
  input  wire [2:0]  wb_sel_in,       // Write-back source select
  input  wire        valid_in,

  // M extension signals from ID stage
  input  wire        is_mul_div_in,
  input  wire [3:0]  mul_div_op_in,
  input  wire        is_word_op_in,

  // A extension signals from ID stage
  input  wire        is_atomic_in,
  input  wire [4:0]  funct5_in,
  input  wire        aq_in,
  input  wire        rl_in,

  // F/D extension signals from ID stage
  input  wire [XLEN-1:0] fp_rs1_data_in,      // FP register rs1 data
  input  wire [XLEN-1:0] fp_rs2_data_in,      // FP register rs2 data
  input  wire [XLEN-1:0] fp_rs3_data_in,      // FP register rs3 data (for FMA)
  input  wire [4:0]      fp_rs1_addr_in,      // FP rs1 address
  input  wire [4:0]      fp_rs2_addr_in,      // FP rs2 address
  input  wire [4:0]      fp_rs3_addr_in,      // FP rs3 address
  input  wire [4:0]      fp_rd_addr_in,       // FP rd address
  input  wire            fp_reg_write_in,     // FP register write enable
  input  wire            int_reg_write_fp_in, // Integer register write (FP compare/classify/FMV.X.W)
  input  wire            fp_alu_en_in,        // FP ALU enable
  input  wire [4:0]      fp_alu_op_in,        // FP ALU operation
  input  wire [2:0]      fp_rm_in,            // FP rounding mode
  input  wire            fp_use_dynamic_rm_in,// Use dynamic rounding mode

  // CSR signals from ID stage
  input  wire [11:0]      csr_addr_in,
  input  wire             csr_we_in,
  input  wire             csr_src_in,      // 0=rs1, 1=uimm
  input  wire [XLEN-1:0]  csr_wdata_in,    // rs1 data or uimm (XLEN-wide)

  // Exception signals from ID stage
  input  wire        is_ecall_in,
  input  wire        is_ebreak_in,
  input  wire        is_mret_in,
  input  wire        illegal_inst_in,
  input  wire [31:0] instruction_in,  // For exception value

  // Outputs to EX stage
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

  // Control signals to EX stage
  output reg  [3:0]  alu_control_out,
  output reg         alu_src_out,
  output reg         branch_out,
  output reg         jump_out,
  output reg         mem_read_out,
  output reg         mem_write_out,
  output reg         reg_write_out,
  output reg  [2:0]  wb_sel_out,
  output reg         valid_out,

  // M extension signals to EX stage
  output reg         is_mul_div_out,
  output reg  [3:0]  mul_div_op_out,
  output reg         is_word_op_out,

  // A extension signals to EX stage
  output reg         is_atomic_out,
  output reg  [4:0]  funct5_out,
  output reg         aq_out,
  output reg         rl_out,

  // F/D extension signals to EX stage
  output reg  [XLEN-1:0] fp_rs1_data_out,
  output reg  [XLEN-1:0] fp_rs2_data_out,
  output reg  [XLEN-1:0] fp_rs3_data_out,
  output reg  [4:0]      fp_rs1_addr_out,
  output reg  [4:0]      fp_rs2_addr_out,
  output reg  [4:0]      fp_rs3_addr_out,
  output reg  [4:0]      fp_rd_addr_out,
  output reg             fp_reg_write_out,
  output reg             int_reg_write_fp_out,
  output reg             fp_alu_en_out,
  output reg  [4:0]      fp_alu_op_out,
  output reg  [2:0]      fp_rm_out,
  output reg             fp_use_dynamic_rm_out,

  // CSR signals to EX stage
  output reg  [11:0]      csr_addr_out,
  output reg              csr_we_out,
  output reg              csr_src_out,
  output reg  [XLEN-1:0]  csr_wdata_out,

  // Exception signals to EX stage
  output reg         is_ecall_out,
  output reg         is_ebreak_out,
  output reg         is_mret_out,
  output reg         illegal_inst_out,
  output reg  [31:0] instruction_out
);

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset: clear all outputs
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

      fp_rs1_data_out <= {XLEN{1'b0}};
      fp_rs2_data_out <= {XLEN{1'b0}};
      fp_rs3_data_out <= {XLEN{1'b0}};
      fp_rs1_addr_out <= 5'h0;
      fp_rs2_addr_out <= 5'h0;
      fp_rs3_addr_out <= 5'h0;
      fp_rd_addr_out  <= 5'h0;
      fp_reg_write_out<= 1'b0;
      int_reg_write_fp_out <= 1'b0;
      fp_alu_en_out   <= 1'b0;
      fp_alu_op_out   <= 5'h0;
      fp_rm_out       <= 3'h0;
      fp_use_dynamic_rm_out <= 1'b0;

      csr_addr_out    <= 12'h0;
      csr_we_out      <= 1'b0;
      csr_src_out     <= 1'b0;
      csr_wdata_out   <= {XLEN{1'b0}};

      is_ecall_out    <= 1'b0;
      is_ebreak_out   <= 1'b0;
      is_mret_out     <= 1'b0;
      illegal_inst_out <= 1'b0;
      instruction_out <= 32'h0;
    end else if (flush && !hold) begin
      // Flush: insert NOP bubble (clear control signals, keep data)
      // Note: hold takes priority over flush (M instructions must stay in place)
      pc_out          <= pc_in;         // Keep PC for debugging
      rs1_data_out    <= rs1_data_in;
      rs2_data_out    <= rs2_data_in;
      rs1_addr_out    <= 5'h0;          // Clear addresses
      rs2_addr_out    <= 5'h0;
      rd_addr_out     <= 5'h0;          // Clear destination
      imm_out         <= {XLEN{1'b0}};
      opcode_out      <= 7'h0;
      funct3_out      <= 3'h0;
      funct7_out      <= 7'h0;

      // Clear all control signals (creates NOP)
      alu_control_out <= 4'h0;
      alu_src_out     <= 1'b0;
      branch_out      <= 1'b0;
      jump_out        <= 1'b0;
      mem_read_out    <= 1'b0;
      mem_write_out   <= 1'b0;
      reg_write_out   <= 1'b0;          // Critical: no register write
      wb_sel_out      <= 3'b0;
      valid_out       <= 1'b0;          // Mark as invalid

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
      fp_rd_addr_out  <= 5'h0;          // Clear destination
      fp_reg_write_out<= 1'b0;          // Critical: no FP register write
      int_reg_write_fp_out <= 1'b0;     // Critical: no INT register write
      fp_alu_en_out   <= 1'b0;
      fp_alu_op_out   <= 5'h0;
      fp_rm_out       <= 3'h0;
      fp_use_dynamic_rm_out <= 1'b0;

      csr_addr_out    <= 12'h0;
      csr_we_out      <= 1'b0;          // Critical: no CSR write
      csr_src_out     <= 1'b0;
      csr_wdata_out   <= {XLEN{1'b0}};

      is_ecall_out    <= 1'b0;          // Critical: clear exceptions
      is_ebreak_out   <= 1'b0;
      is_mret_out     <= 1'b0;
      illegal_inst_out <= 1'b0;
      instruction_out <= 32'h0;
    end else if (!hold) begin
      // Normal operation: latch all values (only if not held)
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
      fp_alu_en_out   <= fp_alu_en_in;
      fp_alu_op_out   <= fp_alu_op_in;
      fp_rm_out       <= fp_rm_in;
      fp_use_dynamic_rm_out <= fp_use_dynamic_rm_in;

      csr_addr_out    <= csr_addr_in;
      csr_we_out      <= csr_we_in;
      csr_src_out     <= csr_src_in;
      csr_wdata_out   <= csr_wdata_in;

      is_ecall_out    <= is_ecall_in;
      is_ebreak_out   <= is_ebreak_in;
      is_mret_out     <= is_mret_in;
      illegal_inst_out <= illegal_inst_in;
      instruction_out <= instruction_in;
    end
    // If hold is asserted, keep previous values (register holds in place)
  end

endmodule
