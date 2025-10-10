// register_file.v - 32-register register file for RV32I
// Implements 32 general-purpose registers with x0 hardwired to zero
// Author: RV1 Project
// Date: 2025-10-09

module register_file (
  input  wire        clk,         // Clock
  input  wire        reset_n,     // Active-low reset
  input  wire [4:0]  rs1_addr,    // Read port 1 address
  input  wire [4:0]  rs2_addr,    // Read port 2 address
  input  wire [4:0]  rd_addr,     // Write port address
  input  wire [31:0] rd_data,     // Write port data
  input  wire        rd_wen,      // Write enable
  output wire [31:0] rs1_data,    // Read port 1 data
  output wire [31:0] rs2_data     // Read port 2 data
);

  // Register array (x0-x31)
  reg [31:0] registers [0:31];

  // Initialize registers and write on posedge
  integer i;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset all registers to zero
      for (i = 0; i < 32; i = i + 1) begin
        registers[i] <= 32'h0;
      end
    end else begin
      // Write operation
      if (rd_wen && rd_addr != 5'h0) begin
        // x0 is hardwired to zero, so don't write to it
        registers[rd_addr] <= rd_data;
      end
    end
  end

  // Read operations (combinational)
  // x0 always reads as zero
  assign rs1_data = (rs1_addr == 5'h0) ? 32'h0 : registers[rs1_addr];
  assign rs2_data = (rs2_addr == 5'h0) ? 32'h0 : registers[rs2_addr];

endmodule
