// mul_unit.v - Sequential Multiplier for M Extension
// Implements MUL, MULH, MULHSU, MULHU instructions
// Uses iterative add-and-shift algorithm
// Parameterized for RV32/RV64 support

`include "config/rv_config.vh"

module mul_unit #(
  parameter XLEN = `XLEN
)(
  input  wire                clk,
  input  wire                reset_n,

  // Control interface
  input  wire                start,        // Start multiplication
  input  wire  [1:0]         mul_op,       // Operation: 00=MUL, 01=MULH, 10=MULHSU, 11=MULHU
  input  wire                is_word_op,   // RV64: W-suffix instruction (32-bit)

  // Data interface
  input  wire  [XLEN-1:0]    operand_a,    // Multiplicand
  input  wire  [XLEN-1:0]    operand_b,    // Multiplier
  output reg   [XLEN-1:0]    result,       // Result

  // Status
  output wire                busy,         // Operation in progress
  output reg                 ready         // Result ready (1 cycle pulse)
);

  // Operation encoding
  localparam MUL    = 2'b00;  // Lower XLEN bits
  localparam MULH   = 2'b01;  // Upper XLEN bits (signed × signed)
  localparam MULHSU = 2'b10;  // Upper XLEN bits (signed × unsigned)
  localparam MULHU  = 2'b11;  // Upper XLEN bits (unsigned × unsigned)

  // State machine
  localparam IDLE      = 2'b00;
  localparam COMPUTE   = 2'b01;
  localparam DONE      = 2'b10;

  reg [1:0] state, state_next;

  // Determine effective operand width for RV64W operations
  wire [5:0] op_width;
  assign op_width = (XLEN == 64 && is_word_op) ? 6'd32 : XLEN[5:0];

  // Sign handling
  wire op_a_signed, op_b_signed;
  assign op_a_signed = (mul_op == MULH) || (mul_op == MULHSU);
  assign op_b_signed = (mul_op == MULH);

  // Sign extension for signed operands
  wire [XLEN-1:0] abs_a, abs_b;
  wire sign_a, sign_b;

  generate
    if (XLEN == 64) begin : gen_sign_64
      assign sign_a = is_word_op ? operand_a[31] : operand_a[XLEN-1];
      assign sign_b = is_word_op ? operand_b[31] : operand_b[XLEN-1];
    end else begin : gen_sign_32
      assign sign_a = operand_a[XLEN-1];
      assign sign_b = operand_b[XLEN-1];
    end
  endgenerate

  wire negate_a = op_a_signed && sign_a;
  wire negate_b = op_b_signed && sign_b;

  assign abs_a = negate_a ? (~operand_a + 1'b1) : operand_a;
  assign abs_b = negate_b ? (~operand_b + 1'b1) : operand_b;

  // Double-width accumulator for product
  reg [2*XLEN-1:0] product;
  reg [2*XLEN-1:0] multiplicand;
  reg [XLEN-1:0]   multiplier;

  // Cycle counter
  reg [6:0] cycle_count;

  // Result sign (for signed operations)
  reg result_negative;

  // Control signals
  reg [1:0] op_reg;
  reg       word_op_reg;

  // State machine
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state <= IDLE;
    end else begin
      state <= state_next;
    end
  end

  always @(*) begin
    state_next = state;
    case (state)
      IDLE: begin
        if (start) state_next = COMPUTE;
      end

      COMPUTE: begin
        if (cycle_count >= op_width) state_next = DONE;
      end

      DONE: begin
        state_next = IDLE;
      end

      default: state_next = IDLE;
    endcase
  end

  // Datapath
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      product         <= {(2*XLEN){1'b0}};
      multiplicand    <= {(2*XLEN){1'b0}};
      multiplier      <= {XLEN{1'b0}};
      cycle_count     <= 7'd0;
      ready           <= 1'b0;
      result          <= {XLEN{1'b0}};
      result_negative <= 1'b0;
      op_reg          <= 2'b00;
      word_op_reg     <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          ready <= 1'b0;

          if (start) begin
            // Initialize for multiplication
            product         <= {(2*XLEN){1'b0}};
            multiplicand    <= {{XLEN{1'b0}}, abs_a};
            multiplier      <= abs_b;
            cycle_count     <= 7'd0;
            result_negative <= negate_a ^ negate_b;  // XOR for result sign
            op_reg          <= mul_op;
            word_op_reg     <= is_word_op;
          end
        end

        COMPUTE: begin
          // Add and shift algorithm
          if (multiplier[0]) begin
            product <= product + multiplicand;
          end

          // Shift for next iteration
          multiplicand <= multiplicand << 1;
          multiplier   <= multiplier >> 1;
          cycle_count  <= cycle_count + 1;
        end

        DONE: begin
          ready <= 1'b1;

          // Extract result based on operation
          case (op_reg)
            MUL: begin
              // Lower XLEN bits
              if (result_negative) begin
                result <= ~product[XLEN-1:0] + 1'b1;
              end else begin
                result <= product[XLEN-1:0];
              end
            end

            MULH, MULHSU, MULHU: begin
              // Upper XLEN bits
              if (result_negative && op_reg != MULHU) begin
                // Negate 2*XLEN product, then take upper bits
                reg [2*XLEN-1:0] neg_product;
                neg_product = ~product + 1'b1;
                result <= neg_product[2*XLEN-1:XLEN];
              end else begin
                result <= product[2*XLEN-1:XLEN];
              end
            end

            default: result <= product[XLEN-1:0];
          endcase

          // Sign-extend for RV64W operations
          if (XLEN == 64 && word_op_reg) begin
            result <= {{32{result[31]}}, result[31:0]};
          end
        end

        default: begin
          ready <= 1'b0;
        end
      endcase
    end
  end

  // Combinational busy signal - asserts when not in IDLE state
  // This is one cycle faster than using a registered busy signal.
  assign busy = (state != IDLE);

endmodule
