// mul_div_unit.v - M Extension Execution Unit
// Combines multiply and divide units
// Handles all M extension instructions
// Parameterized for RV32M and RV64M support

`include "config/rv_config.vh"

module mul_div_unit #(
  parameter XLEN = `XLEN
)(
  input  wire                clk,
  input  wire                reset_n,

  // Control interface
  input  wire                start,        // Start operation
  input  wire  [3:0]         operation,    // M extension operation
  input  wire                is_word_op,   // RV64: W-suffix instruction

  // Data interface
  input  wire  [XLEN-1:0]    operand_a,
  input  wire  [XLEN-1:0]    operand_b,
  output wire  [XLEN-1:0]    result,

  // Status
  output wire                busy,         // Operation in progress
  output wire                ready         // Result ready
);

  // M extension operation encoding
  localparam OP_MUL    = 4'b0000;  // funct3 = 000
  localparam OP_MULH   = 4'b0001;  // funct3 = 001
  localparam OP_MULHSU = 4'b0010;  // funct3 = 010
  localparam OP_MULHU  = 4'b0011;  // funct3 = 011
  localparam OP_DIV    = 4'b0100;  // funct3 = 100
  localparam OP_DIVU   = 4'b0101;  // funct3 = 101
  localparam OP_REM    = 4'b0110;  // funct3 = 110
  localparam OP_REMU   = 4'b0111;  // funct3 = 111

  // Decode operation type
  wire is_mul = (operation[3:2] == 2'b00);  // MUL, MULH, MULHSU, MULHU
  wire is_div = (operation[3:2] == 2'b01);  // DIV, DIVU, REM, REMU

  // Multiply unit signals
  wire        mul_start;
  wire [1:0]  mul_op;
  wire [XLEN-1:0] mul_result;
  wire        mul_busy;
  wire        mul_ready;

  assign mul_start = start && is_mul;
  assign mul_op    = operation[1:0];

  mul_unit #(
    .XLEN(XLEN)
  ) mul_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(mul_start),
    .mul_op(mul_op),
    .is_word_op(is_word_op),
    .operand_a(operand_a),
    .operand_b(operand_b),
    .result(mul_result),
    .busy(mul_busy),
    .ready(mul_ready)
  );

  // Divide unit signals
  wire        div_start;
  wire [1:0]  div_op;
  wire [XLEN-1:0] div_result;
  wire        div_busy;
  wire        div_ready;

  assign div_start = start && is_div;
  assign div_op    = operation[1:0];

  div_unit #(
    .XLEN(XLEN)
  ) div_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(div_start),
    .div_op(div_op),
    .is_word_op(is_word_op),
    .dividend(operand_a),
    .divisor(operand_b),
    .result(div_result),
    .busy(div_busy),
    .ready(div_ready)
  );

  // Output multiplexing
  assign result = is_mul ? mul_result : div_result;
  assign busy   = mul_busy || div_busy;
  assign ready  = mul_ready || div_ready;

endmodule
