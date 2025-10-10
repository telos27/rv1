// pc.v - Program Counter for RV32I
// Holds and updates the program counter
// Author: RV1 Project
// Date: 2025-10-09

module pc #(
  parameter RESET_VECTOR = 32'h00000000
) (
  input  wire        clk,         // Clock
  input  wire        reset_n,     // Active-low reset
  input  wire        stall,       // Stall signal (freeze PC)
  input  wire [31:0] pc_next,     // Next PC value
  output reg  [31:0] pc_current   // Current PC value
);

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      pc_current <= RESET_VECTOR;
    end else if (!stall) begin
      pc_current <= pc_next;
    end
    // If stall is high, PC holds its current value
  end

endmodule
