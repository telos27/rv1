// div_unit.v - Non-Restoring Divider for M Extension
// Implements DIV, DIVU, REM, REMU instructions
// Uses non-restoring division algorithm
// Parameterized for RV32/RV64 support

`include "config/rv_config.vh"

module div_unit #(
  parameter XLEN = `XLEN
)(
  input  wire                clk,
  input  wire                reset_n,

  // Control interface
  input  wire                start,        // Start division
  input  wire  [1:0]         div_op,       // Operation: 00=DIV, 01=DIVU, 10=REM, 11=REMU
  input  wire                is_word_op,   // RV64: W-suffix instruction (32-bit)

  // Data interface
  input  wire  [XLEN-1:0]    dividend,     // Operand A (numerator)
  input  wire  [XLEN-1:0]    divisor,      // Operand B (denominator)
  output reg   [XLEN-1:0]    result,       // Quotient or remainder

  // Status
  output wire                busy,         // Operation in progress
  output reg                 ready         // Result ready (1 cycle pulse)
);

  // Operation encoding
  localparam DIV  = 2'b00;  // Quotient (signed)
  localparam DIVU = 2'b01;  // Quotient (unsigned)
  localparam REM  = 2'b10;  // Remainder (signed)
  localparam REMU = 2'b11;  // Remainder (unsigned)

  // State machine
  localparam IDLE    = 2'b00;
  localparam COMPUTE = 2'b01;
  localparam DONE    = 2'b10;

  reg [1:0] state, state_next;

  // Determine effective operand width for RV64W operations
  wire [5:0] op_width;
  assign op_width = (XLEN == 64 && is_word_op) ? 6'd32 : XLEN[5:0];

  // Sign handling
  wire is_signed_op;
  assign is_signed_op = (div_op == DIV) || (div_op == REM);

  // Extract signs and compute absolute values
  wire sign_dividend, sign_divisor;

  generate
    if (XLEN == 64) begin : gen_sign_64
      assign sign_dividend = is_word_op ? dividend[31] : dividend[XLEN-1];
      assign sign_divisor  = is_word_op ? divisor[31] : divisor[XLEN-1];
    end else begin : gen_sign_32
      assign sign_dividend = dividend[XLEN-1];
      assign sign_divisor  = divisor[XLEN-1];
    end
  endgenerate

  wire negate_dividend = is_signed_op && sign_dividend;
  wire negate_divisor  = is_signed_op && sign_divisor;

  wire [XLEN-1:0] abs_dividend = negate_dividend ? (~dividend + 1'b1) : dividend;
  wire [XLEN-1:0] abs_divisor  = negate_divisor  ? (~divisor + 1'b1)  : divisor;

  // Division registers
  reg [XLEN-1:0]   quotient;
  reg [XLEN:0]     remainder;  // Need XLEN+1 bits for subtraction
  reg [XLEN-1:0]   divisor_reg;
  reg [6:0]        cycle_count;

  // Control registers
  reg [1:0] op_reg;
  reg       word_op_reg;
  reg       quotient_negative;
  reg       remainder_negative;
  reg       div_by_zero;
  reg       overflow;

  // Special case detection
  wire is_div_by_zero = (divisor == {XLEN{1'b0}});
  wire is_overflow    = is_signed_op &&
                        (dividend == {1'b1, {(XLEN-1){1'b0}}}) &&  // Most negative
                        (divisor == {XLEN{1'b1}});                  // -1

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
        // Transition to DONE after op_width cycles (0 to op_width-1)
        // Check if next cycle will be >= op_width
        if ((cycle_count + 1) >= op_width || div_by_zero || overflow)
          state_next = DONE;
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
      quotient           <= {XLEN{1'b0}};
      remainder          <= {(XLEN+1){1'b0}};
      divisor_reg        <= {XLEN{1'b0}};
      cycle_count        <= 7'd0;
      ready              <= 1'b0;
      result             <= {XLEN{1'b0}};
      op_reg             <= 2'b00;
      word_op_reg        <= 1'b0;
      quotient_negative  <= 1'b0;
      remainder_negative <= 1'b0;
      div_by_zero        <= 1'b0;
      overflow           <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          ready <= 1'b0;

          if (start) begin
            // Initialize for division
            // For non-restoring division:
            //   - quotient (Q) starts with dividend
            //   - remainder (A) starts at 0
            quotient           <= abs_dividend;
            remainder          <= {(XLEN+1){1'b0}};
            divisor_reg        <= abs_divisor;
            cycle_count        <= 7'd0;
            op_reg             <= div_op;
            word_op_reg        <= is_word_op;
            div_by_zero        <= is_div_by_zero;
            overflow           <= is_overflow;

            // Determine result signs
            quotient_negative  <= negate_dividend ^ negate_divisor;
            remainder_negative <= negate_dividend;
          end
        end

        COMPUTE: begin
          if (!div_by_zero && !overflow) begin
            // Non-restoring division algorithm
            // A = remainder[XLEN-1:0] (upper part)
            // Q = quotient[XLEN-1:0] (lower part)

            reg [XLEN-1:0] shifted_A;
            reg [XLEN-1:0] new_A;
            reg [XLEN-1:0] Q_shifted;
            reg q_bit;

            // Step 1: Shift {A, Q} left by 1
            // A = {A[XLEN-2:0], Q[XLEN-1]}
            // Q = {Q[XLEN-2:0], 0}
            shifted_A = {remainder[XLEN-2:0], quotient[XLEN-1]};
            Q_shifted = {quotient[XLEN-2:0], 1'b0};

            // Step 2: Add/subtract based on OLD A sign (before shift)
            if (remainder[XLEN-1]) begin  // A was negative
              new_A = shifted_A + divisor_reg;
            end else begin                 // A was positive/zero
              new_A = shifted_A - divisor_reg;
            end

            // Step 3: Set Q[0] based on new A sign
            q_bit = ~new_A[XLEN-1];  // 1 if positive, 0 if negative

            // Update registers
            remainder <= {1'b0, new_A};  // Extend to XLEN+1 with leading 0
            quotient  <= Q_shifted | {{(XLEN-1){1'b0}}, q_bit};
            cycle_count <= cycle_count + 1;
          end
        end

        DONE: begin
          ready <= 1'b1;

          // Handle special cases per RISC-V spec
          if (div_by_zero) begin
            case (op_reg)
              DIV, DIVU: result <= {XLEN{1'b1}};  // -1 (all 1s)
              REM, REMU: result <= dividend;       // Return dividend
            endcase
          end else if (overflow) begin
            // Overflow case: MIN_INT / -1
            case (op_reg)
              DIV:  result <= {1'b1, {(XLEN-1){1'b0}}};  // MIN_INT
              REM:  result <= {XLEN{1'b0}};               // 0
              default: result <= {XLEN{1'b0}};
            endcase
          end else begin
            // Normal division result
            // Final remainder correction if needed
            reg [XLEN:0] final_remainder;
            final_remainder = remainder;

            if (final_remainder[XLEN]) begin
              final_remainder = final_remainder + {1'b0, divisor_reg};
            end

            case (op_reg)
              DIV, DIVU: begin
                // Return quotient
                if (quotient_negative && op_reg == DIV) begin
                  result <= ~quotient + 1'b1;
                end else begin
                  result <= quotient;
                end
              end

              REM, REMU: begin
                // Return remainder
                if (remainder_negative && op_reg == REM) begin
                  result <= ~final_remainder[XLEN-1:0] + 1'b1;
                end else begin
                  result <= final_remainder[XLEN-1:0];
                end
              end

              default: result <= quotient;
            endcase
          end

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
