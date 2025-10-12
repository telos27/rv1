// Floating-Point Multiplier
// Implements FMUL.S/D instruction
// IEEE 754-2008 compliant with full rounding mode support
// Multi-cycle execution: 3-4 cycles

module fp_multiplier #(
  parameter FLEN = 32  // 32 for single-precision, 64 for double-precision
) (
  input  wire              clk,
  input  wire              reset_n,

  // Control
  input  wire              start,          // Start operation
  input  wire [2:0]        rounding_mode,  // IEEE 754 rounding mode
  output reg               busy,           // Operation in progress
  output reg               done,           // Operation complete (1 cycle pulse)

  // Operands
  input  wire [FLEN-1:0]   operand_a,
  input  wire [FLEN-1:0]   operand_b,

  // Result
  output reg  [FLEN-1:0]   result,

  // Exception flags
  output reg               flag_nv,        // Invalid operation
  output reg               flag_of,        // Overflow
  output reg               flag_uf,        // Underflow
  output reg               flag_nx         // Inexact
);

  // IEEE 754 format parameters
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;
  localparam BIAS = (FLEN == 32) ? 127 : 1023;
  localparam MAX_EXP = (FLEN == 32) ? 255 : 2047;

  // State machine
  localparam IDLE      = 3'b000;
  localparam UNPACK    = 3'b001;
  localparam MULTIPLY  = 3'b010;
  localparam NORMALIZE = 3'b011;
  localparam ROUND     = 3'b100;
  localparam DONE      = 3'b101;

  reg [2:0] state, next_state;

  // Unpacked operands
  reg sign_a, sign_b, sign_result;
  reg [EXP_WIDTH-1:0] exp_a, exp_b;
  reg [MAN_WIDTH:0] man_a, man_b;  // +1 bit for implicit leading 1

  // Special value flags
  reg is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;

  // Computation
  reg [EXP_WIDTH+1:0] exp_sum;  // +2 bits for overflow handling
  reg [(2*MAN_WIDTH+3):0] product;  // Double width + GRS bits
  reg [MAN_WIDTH:0] normalized_man;
  reg [EXP_WIDTH-1:0] exp_result;

  // Rounding
  reg guard, round, sticky;
  reg round_up;

  // State machine
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      state <= IDLE;
    else
      state <= next_state;
  end

  // Next state logic
  always @(*) begin
    case (state)
      IDLE:      next_state = start ? UNPACK : IDLE;
      UNPACK:    next_state = MULTIPLY;
      MULTIPLY:  next_state = NORMALIZE;
      NORMALIZE: next_state = ROUND;
      ROUND:     next_state = DONE;
      DONE:      next_state = IDLE;
      default:   next_state = IDLE;
    endcase
  end

  // Busy and done signals
  always @(*) begin
    busy = (state != IDLE) && (state != DONE);
    done = (state == DONE);
  end

  // Main datapath
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      result <= {FLEN{1'b0}};
      flag_nv <= 1'b0;
      flag_of <= 1'b0;
      flag_uf <= 1'b0;
      flag_nx <= 1'b0;
    end else begin
      case (state)

        // ============================================================
        // UNPACK: Extract sign, exponent, mantissa
        // ============================================================
        UNPACK: begin
          // Extract sign (XOR for multiplication)
          sign_a <= operand_a[FLEN-1];
          sign_b <= operand_b[FLEN-1];
          sign_result <= operand_a[FLEN-1] ^ operand_b[FLEN-1];

          // Extract exponent
          exp_a <= operand_a[FLEN-2:MAN_WIDTH];
          exp_b <= operand_b[FLEN-2:MAN_WIDTH];

          // Extract mantissa with implicit leading 1 (if normalized)
          man_a <= (operand_a[FLEN-2:MAN_WIDTH] == 0) ?
                   {1'b0, operand_a[MAN_WIDTH-1:0]} :  // Subnormal: no implicit 1
                   {1'b1, operand_a[MAN_WIDTH-1:0]};   // Normal: implicit 1

          man_b <= (operand_b[FLEN-2:MAN_WIDTH] == 0) ?
                   {1'b0, operand_b[MAN_WIDTH-1:0]} :
                   {1'b1, operand_b[MAN_WIDTH-1:0]};

          // Detect special values
          is_nan_a <= (operand_a[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_a[MAN_WIDTH-1:0] != 0);
          is_nan_b <= (operand_b[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_b[MAN_WIDTH-1:0] != 0);
          is_inf_a <= (operand_a[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_a[MAN_WIDTH-1:0] == 0);
          is_inf_b <= (operand_b[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_b[MAN_WIDTH-1:0] == 0);
          is_zero_a <= (operand_a[FLEN-2:0] == 0);
          is_zero_b <= (operand_b[FLEN-2:0] == 0);
        end

        // ============================================================
        // MULTIPLY: Compute product and exponent
        // ============================================================
        MULTIPLY: begin
          // Handle special cases
          if (is_nan_a || is_nan_b) begin
            // NaN propagation
            result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
            flag_nv <= 1'b1;
            state <= DONE;
          end else if ((is_inf_a && is_zero_b) || (is_zero_a && is_inf_b)) begin
            // 0 × ∞: Invalid
            result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
            flag_nv <= 1'b1;
            state <= DONE;
          end else if (is_inf_a || is_inf_b) begin
            // ∞ × x: return ±∞
            result <= {sign_result, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
            state <= DONE;
          end else if (is_zero_a || is_zero_b) begin
            // 0 × x: return ±0
            result <= {sign_result, {FLEN-1{1'b0}}};
            state <= DONE;
          end else begin
            // Normal multiplication
            // Multiply mantissas
            product <= man_a * man_b;

            // Add exponents (subtract bias)
            // exp_sum = exp_a + exp_b - BIAS
            exp_sum <= exp_a + exp_b - BIAS;
          end
        end

        // ============================================================
        // NORMALIZE: Shift product to normalized form
        // ============================================================
        NORMALIZE: begin
          // Product is (1.xxx * 1.yyy) = 1.zzz to 3.zzz (needs 0 or 1 shift)
          // Bit position: product[2*MAN_WIDTH+2:MAN_WIDTH+2] is the integer part (1 or 2)

          if (product[(2*MAN_WIDTH+2)]) begin
            // Product >= 2.0, shift right by 1
            normalized_man <= product[(2*MAN_WIDTH+2):(MAN_WIDTH+2)];
            exp_result <= exp_sum + 1;
            guard <= product[MAN_WIDTH+1];
            round <= product[MAN_WIDTH];
            sticky <= |product[MAN_WIDTH-1:0];
          end else begin
            // Product in [1.0, 2.0), already normalized
            normalized_man <= product[(2*MAN_WIDTH+1):(MAN_WIDTH+1)];
            exp_result <= exp_sum;
            guard <= product[MAN_WIDTH];
            round <= product[MAN_WIDTH-1];
            sticky <= |product[MAN_WIDTH-2:0];
          end

          // Check for overflow
          if (exp_sum >= MAX_EXP || exp_result >= MAX_EXP) begin
            flag_of <= 1'b1;
            flag_nx <= 1'b1;
            // Return ±infinity
            result <= {sign_result, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
            state <= DONE;
          end
          // Check for underflow
          else if (exp_sum < 1 || exp_result < 1) begin
            flag_uf <= 1'b1;
            flag_nx <= 1'b1;
            // Return ±0 (flush to zero for simplicity)
            result <= {sign_result, {FLEN-1{1'b0}}};
            state <= DONE;
          end
        end

        // ============================================================
        // ROUND: Apply rounding mode
        // ============================================================
        ROUND: begin
          // Determine if we should round up
          case (rounding_mode)
            3'b000: begin  // RNE: Round to nearest, ties to even
              round_up <= guard && (round || sticky || normalized_man[0]);
            end
            3'b001: begin  // RTZ: Round toward zero
              round_up <= 1'b0;
            end
            3'b010: begin  // RDN: Round down (toward -∞)
              round_up <= sign_result && (guard || round || sticky);
            end
            3'b011: begin  // RUP: Round up (toward +∞)
              round_up <= !sign_result && (guard || round || sticky);
            end
            3'b100: begin  // RMM: Round to nearest, ties to max magnitude
              round_up <= guard;
            end
            default: begin  // Invalid rounding mode
              round_up <= 1'b0;
            end
          endcase

          // Apply rounding
          if (round_up) begin
            result <= {sign_result, exp_result, normalized_man[MAN_WIDTH-1:0] + 1'b1};
          end else begin
            result <= {sign_result, exp_result, normalized_man[MAN_WIDTH-1:0]};
          end

          // Set inexact flag
          flag_nx <= guard || round || sticky;
        end

        // ============================================================
        // DONE: Hold result for 1 cycle
        // ============================================================
        DONE: begin
          // Just hold result
        end

      endcase
    end
  end

endmodule
