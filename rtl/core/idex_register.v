// ID/EX Pipeline Register
// Latches outputs from Instruction Decode stage for use in Execute stage
// Supports flush (insert NOP bubble for hazards/branches)

module idex_register (
  input  wire        clk,
  input  wire        reset_n,
  input  wire        flush,           // Clear to NOP (for load-use or branch)

  // Inputs from ID stage
  input  wire [31:0] pc_in,
  input  wire [31:0] rs1_data_in,
  input  wire [31:0] rs2_data_in,
  input  wire [4:0]  rs1_addr_in,     // For forwarding unit
  input  wire [4:0]  rs2_addr_in,     // For forwarding unit
  input  wire [4:0]  rd_addr_in,
  input  wire [31:0] imm_in,
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
  input  wire [1:0]  wb_sel_in,       // Write-back source select
  input  wire        valid_in,

  // Outputs to EX stage
  output reg  [31:0] pc_out,
  output reg  [31:0] rs1_data_out,
  output reg  [31:0] rs2_data_out,
  output reg  [4:0]  rs1_addr_out,
  output reg  [4:0]  rs2_addr_out,
  output reg  [4:0]  rd_addr_out,
  output reg  [31:0] imm_out,
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
  output reg  [1:0]  wb_sel_out,
  output reg         valid_out
);

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset: clear all outputs
      pc_out          <= 32'h0;
      rs1_data_out    <= 32'h0;
      rs2_data_out    <= 32'h0;
      rs1_addr_out    <= 5'h0;
      rs2_addr_out    <= 5'h0;
      rd_addr_out     <= 5'h0;
      imm_out         <= 32'h0;
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
      wb_sel_out      <= 2'b0;
      valid_out       <= 1'b0;
    end else if (flush) begin
      // Flush: insert NOP bubble (clear control signals, keep data)
      pc_out          <= pc_in;         // Keep PC for debugging
      rs1_data_out    <= rs1_data_in;
      rs2_data_out    <= rs2_data_in;
      rs1_addr_out    <= 5'h0;          // Clear addresses
      rs2_addr_out    <= 5'h0;
      rd_addr_out     <= 5'h0;          // Clear destination
      imm_out         <= 32'h0;
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
      wb_sel_out      <= 2'b0;
      valid_out       <= 1'b0;          // Mark as invalid
    end else begin
      // Normal operation: latch all values
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
    end
  end

endmodule
