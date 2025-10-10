// MEM/WB Pipeline Register
// Latches outputs from Memory stage for use in Write-Back stage
// No stall or flush needed (last pipeline stage)

module memwb_register (
  input  wire        clk,
  input  wire        reset_n,

  // Inputs from MEM stage
  input  wire [31:0] alu_result_in,      // Propagated from EX
  input  wire [31:0] mem_read_data_in,   // Data read from memory
  input  wire [4:0]  rd_addr_in,
  input  wire [31:0] pc_plus_4_in,       // For JAL/JALR

  // Control signals from MEM stage
  input  wire        reg_write_in,
  input  wire [1:0]  wb_sel_in,          // Write-back source select
  input  wire        valid_in,

  // Outputs to WB stage
  output reg  [31:0] alu_result_out,
  output reg  [31:0] mem_read_data_out,
  output reg  [4:0]  rd_addr_out,
  output reg  [31:0] pc_plus_4_out,

  // Control signals to WB stage
  output reg         reg_write_out,
  output reg  [1:0]  wb_sel_out,
  output reg         valid_out
);

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset: clear all outputs
      alu_result_out     <= 32'h0;
      mem_read_data_out  <= 32'h0;
      rd_addr_out        <= 5'h0;
      pc_plus_4_out      <= 32'h0;

      reg_write_out      <= 1'b0;
      wb_sel_out         <= 2'b0;
      valid_out          <= 1'b0;
    end else begin
      // Normal operation: latch all values
      alu_result_out     <= alu_result_in;
      mem_read_data_out  <= mem_read_data_in;
      rd_addr_out        <= rd_addr_in;
      pc_plus_4_out      <= pc_plus_4_in;

      reg_write_out      <= reg_write_in;
      wb_sel_out         <= wb_sel_in;
      valid_out          <= valid_in;
    end
  end

endmodule
