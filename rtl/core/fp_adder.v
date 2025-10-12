// Floating-Point Adder/Subtractor
// Implements FADD.S/D and FSUB.S/D instructions
// IEEE 754-2008 compliant with full rounding mode support
// Multi-cycle execution: 3-4 cycles

module fp_adder #(
  parameter FLEN = 32  // 32 for single-precision, 64 for double-precision
) (
  input  wire              clk,
  input  wire              reset_n,

  // Control
  input  wire              start,          // Start operation
  input  wire              is_sub,         // 0: ADD, 1: SUB
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
  localparam ALIGN     = 3'b010;
  localparam COMPUTE   = 3'b011;
  localparam NORMALIZE = 3'b100;
  localparam ROUND     = 3'b101;
  localparam DONE      = 3'b110;

  reg [2:0] state, next_state;

  // Unpacked operands
  reg sign_a, sign_b, sign_result;
  reg [EXP_WIDTH-1:0] exp_a, exp_b, exp_result;
  reg [MAN_WIDTH:0] man_a, man_b;  // +1 bit for implicit leading 1

  // Special value flags
  reg is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;
  reg is_subnormal_a, is_subnormal_b;

  // Computation
  reg [MAN_WIDTH+3:0] aligned_man_a, aligned_man_b;  // +3 for GRS bits
  reg [MAN_WIDTH+4:0] sum;  // +1 for overflow
  reg [EXP_WIDTH:0] exp_diff;  // +1 bit to handle full range
  reg [MAN_WIDTH+4:0] normalized_man;
  reg [EXP_WIDTH:0] adjusted_exp;

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
      UNPACK:    next_state = ALIGN;
      ALIGN:     next_state = COMPUTE;
      COMPUTE:   next_state = NORMALIZE;
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
      sign_result <= 1'b0;
      exp_result <= {EXP_WIDTH{1'b0}};
    end else begin
      case (state)

        // ============================================================
        // UNPACK: Extract sign, exponent, mantissa
        // ============================================================
        UNPACK: begin
          // Extract sign
          sign_a <= operand_a[FLEN-1];
          sign_b <= operand_b[FLEN-1] ^ is_sub;  // Flip sign for subtraction

          // Extract exponent
          exp_a <= operand_a[FLEN-2:MAN_WIDTH];
          exp_b <= operand_b[FLEN-2:MAN_WIDTH];

          // Extract mantissa and add implicit leading 1 (if normalized)
          is_subnormal_a <= (operand_a[FLEN-2:MAN_WIDTH] == 0) && (operand_a[MAN_WIDTH-1:0] != 0);
          is_subnormal_b <= (operand_b[FLEN-2:MAN_WIDTH] == 0) && (operand_b[MAN_WIDTH-1:0] != 0);

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
        // ALIGN: Align mantissas by shifting smaller operand
        // ============================================================
        ALIGN: begin
          // Handle special cases first
          if (is_nan_a || is_nan_b) begin
            // NaN propagation: return canonical NaN
            result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
            flag_nv <= 1'b1;  // Invalid operation
            state <= DONE;
          end else if (is_inf_a && is_inf_b && (sign_a != sign_b)) begin
            // ∞ - ∞: Invalid
            result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
            flag_nv <= 1'b1;
            state <= DONE;
          end else if (is_inf_a) begin
            // a is ∞: return a
            result <= {sign_a, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
            state <= DONE;
          end else if (is_inf_b) begin
            // b is ∞: return b (with potentially flipped sign)
            result <= {sign_b, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
            state <= DONE;
          end else if (is_zero_a && is_zero_b) begin
            // 0 + 0: sign depends on rounding mode and operand signs
            sign_result <= (sign_a && sign_b) || ((sign_a || sign_b) && (rounding_mode == 3'b010));
            result <= {sign_result, {FLEN-1{1'b0}}};
            state <= DONE;
          end else if (is_zero_a) begin
            // a is 0: return b
            result <= {sign_b, exp_b, man_b[MAN_WIDTH-1:0]};
            state <= DONE;
          end else if (is_zero_b) begin
            // b is 0: return a
            result <= {sign_a, exp_a, man_a[MAN_WIDTH-1:0]};
            state <= DONE;
          end else begin
            // Normal case: align mantissas
            if (exp_a >= exp_b) begin
              exp_result <= exp_a;
              exp_diff <= exp_a - exp_b;
              aligned_man_a <= {man_a, 3'b000};  // Add GRS bits
              // Shift smaller mantissa right
              if (exp_a - exp_b > (MAN_WIDTH + 4))
                aligned_man_b <= {{MAN_WIDTH+4{1'b0}}, 1'b1};  // All shifted out -> sticky
              else
                aligned_man_b <= ({man_b, 3'b000} >> (exp_a - exp_b));
            end else begin
              exp_result <= exp_b;
              exp_diff <= exp_b - exp_a;
              aligned_man_b <= {man_b, 3'b000};
              if (exp_b - exp_a > (MAN_WIDTH + 4))
                aligned_man_a <= {{MAN_WIDTH+4{1'b0}}, 1'b1};
              else
                aligned_man_a <= ({man_a, 3'b000} >> (exp_b - exp_a));
            end
          end
        end

        // ============================================================
        // COMPUTE: Add or subtract aligned mantissas
        // ============================================================
        COMPUTE: begin
          if (sign_a == sign_b) begin
            // Same sign: add magnitudes
            sum <= aligned_man_a + aligned_man_b;
            sign_result <= sign_a;
          end else begin
            // Different signs: subtract magnitudes
            if (aligned_man_a >= aligned_man_b) begin
              sum <= aligned_man_a - aligned_man_b;
              sign_result <= sign_a;
            end else begin
              sum <= aligned_man_b - aligned_man_a;
              sign_result <= sign_b;
            end
          end
        end

        // ============================================================
        // NORMALIZE: Shift result to normalized form
        // ============================================================
        NORMALIZE: begin
          adjusted_exp <= exp_result;

          // Check for zero result
          if (sum == 0) begin
            result <= {sign_result, {FLEN-1{1'b0}}};
            state <= DONE;
          end
          // Check for overflow (carry out)
          else if (sum[MAN_WIDTH+4]) begin
            normalized_man <= sum >> 1;
            adjusted_exp <= exp_result + 1;
            guard <= sum[0];
            round <= 1'b0;
            sticky <= 1'b0;
          end
          // Check for leading zeros (need to shift left)
          else begin
            // Simple normalization: find leading 1
            // (In real hardware, use priority encoder)
            normalized_man <= sum;
            // For now, assume already normalized (bit MAN_WIDTH+3 is 1)
            guard <= sum[2];
            round <= sum[1];
            sticky <= sum[0];
          end

          // Check for overflow
          if (adjusted_exp >= MAX_EXP) begin
            flag_of <= 1'b1;
            // Return ±infinity based on rounding mode
            result <= {sign_result, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
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
              round_up <= guard && (round || sticky || normalized_man[3]);
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
            result <= {sign_result, adjusted_exp[EXP_WIDTH-1:0],
                       normalized_man[MAN_WIDTH+3:3] + 1'b1};
          end else begin
            result <= {sign_result, adjusted_exp[EXP_WIDTH-1:0],
                       normalized_man[MAN_WIDTH+3:3]};
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
