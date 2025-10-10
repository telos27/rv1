// IF/ID Pipeline Register
// Latches outputs from Instruction Fetch stage for use in Decode stage
// Supports stall (hold current value) and flush (insert NOP bubble)

module ifid_register (
  input  wire        clk,
  input  wire        reset_n,
  input  wire        stall,           // Hold current values (for load-use hazard)
  input  wire        flush,           // Clear to NOP (for branch misprediction)

  // Inputs from IF stage
  input  wire [31:0] pc_in,
  input  wire [31:0] instruction_in,

  // Outputs to ID stage
  output reg  [31:0] pc_out,
  output reg  [31:0] instruction_out,
  output reg         valid_out        // 0 = bubble (NOP), 1 = valid instruction
);

  // NOP instruction encoding (ADDI x0, x0, 0)
  localparam NOP = 32'h00000013;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset: insert NOP bubble
      pc_out          <= 32'h0;
      instruction_out <= NOP;
      valid_out       <= 1'b0;
    end else if (flush) begin
      // Flush: insert NOP bubble (branch taken)
      pc_out          <= 32'h0;
      instruction_out <= NOP;
      valid_out       <= 1'b0;
    end else if (stall) begin
      // Stall: hold current values (load-use hazard)
      pc_out          <= pc_out;
      instruction_out <= instruction_out;
      valid_out       <= valid_out;
    end else begin
      // Normal operation: latch new values
      pc_out          <= pc_in;
      instruction_out <= instruction_in;
      valid_out       <= 1'b1;
    end
  end

endmodule
