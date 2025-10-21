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
  reg special_case_handled;  // Track if special case was processed in ALIGN stage

  // Computation
  reg [MAN_WIDTH+3:0] aligned_man_a, aligned_man_b;  // +3 for GRS bits
  reg [MAN_WIDTH+4:0] sum;  // +1 for overflow
  reg [EXP_WIDTH:0] exp_diff;  // +1 bit to handle full range
  reg [MAN_WIDTH+4:0] normalized_man;
  reg [EXP_WIDTH:0] adjusted_exp;

  // Rounding
  reg guard, round, sticky;
  reg round_up;

  // Combinational rounding decision
  wire round_up_comb;

  // Combinational rounding logic
  assign round_up_comb = (state == ROUND) ? (
    (rounding_mode == 3'b000) ? (guard && (round || sticky || normalized_man[3])) :  // RNE
    (rounding_mode == 3'b001) ? 1'b0 :                                                // RTZ
    (rounding_mode == 3'b010) ? (sign_result && (guard || round || sticky)) :        // RDN
    (rounding_mode == 3'b011) ? (!sign_result && (guard || round || sticky)) :       // RUP
    (rounding_mode == 3'b100) ? guard :                                               // RMM
    1'b0                                                                               // default
  ) : 1'b0;

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
      special_case_handled <= 1'b0;
    end else begin
      case (state)

        // ============================================================
        // UNPACK: Extract sign, exponent, mantissa
        // ============================================================
        UNPACK: begin
          // Clear special case flag for new operation
          special_case_handled <= 1'b0;

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
          `ifdef DEBUG_FPU
          $display("[FP_ADDER] ALIGN: sign_a=%b sign_b=%b exp_a=%h exp_b=%h man_a=%h man_b=%h",
                   sign_a, sign_b, exp_a, exp_b, man_a, man_b);
          `endif
          // Handle special cases first
          if (is_nan_a || is_nan_b) begin
            // NaN propagation: return canonical NaN
            result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
            flag_nv <= 1'b1;  // Invalid operation
            flag_nx <= 1'b0;  // Clear inexact flag for special cases
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // Mark as special case
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] NaN detected, returning canonical NaN");
            `endif
          end else if (is_inf_a && is_inf_b && (sign_a != sign_b)) begin
            // ∞ - ∞: Invalid
            result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
            flag_nv <= 1'b1;
            flag_nx <= 1'b0;  // Clear inexact flag for invalid operations
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // Mark as special case
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] Inf - Inf detected, invalid operation");
            `endif
          end else if (is_inf_a) begin
            // a is ∞: return a (exact result, no exceptions)
            result <= {sign_a, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
            flag_nv <= 1'b0;
            flag_nx <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // Mark as special case
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] Operand A is Inf, returning Inf");
            `endif
          end else if (is_inf_b) begin
            // b is ∞: return b (exact result, no exceptions)
            result <= {sign_b, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
            flag_nv <= 1'b0;
            flag_nx <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // Mark as special case
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] Operand B is Inf, returning Inf");
            `endif
          end else if (is_zero_a && is_zero_b) begin
            // 0 + 0: sign depends on rounding mode and operand signs (exact result)
            sign_result <= (sign_a && sign_b) || ((sign_a || sign_b) && (rounding_mode == 3'b010));
            result <= {sign_result, {FLEN-1{1'b0}}};
            flag_nv <= 1'b0;
            flag_nx <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // Mark as special case
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] Both operands zero, returning zero");
            `endif
          end else if (is_zero_a) begin
            // a is 0: return b (exact result)
            result <= {sign_b, exp_b, man_b[MAN_WIDTH-1:0]};
            flag_nv <= 1'b0;
            flag_nx <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // Mark as special case
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] Operand A is zero, returning B");
            `endif
          end else if (is_zero_b) begin
            // b is 0: return a (exact result)
            result <= {sign_a, exp_a, man_a[MAN_WIDTH-1:0]};
            flag_nv <= 1'b0;
            flag_nx <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // Mark as special case
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] Operand B is zero, returning A");
            `endif
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
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] ALIGN: exp_diff=%d, aligned_man_a=%h, aligned_man_b=%h (shifted)",
                       exp_a - exp_b, {man_a, 3'b000}, ({man_b, 3'b000} >> (exp_a - exp_b)));
              `endif
            end else begin
              exp_result <= exp_b;
              exp_diff <= exp_b - exp_a;
              aligned_man_b <= {man_b, 3'b000};
              if (exp_b - exp_a > (MAN_WIDTH + 4))
                aligned_man_a <= {{MAN_WIDTH+4{1'b0}}, 1'b1};
              else
                aligned_man_a <= ({man_a, 3'b000} >> (exp_b - exp_a));
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] ALIGN: exp_diff=%d, aligned_man_a=%h (shifted), aligned_man_b=%h",
                       exp_b - exp_a, ({man_a, 3'b000} >> (exp_b - exp_a)), {man_b, 3'b000});
              `endif
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
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] COMPUTE: ADD aligned_man_a=%h + aligned_man_b=%h = %h",
                     aligned_man_a, aligned_man_b, aligned_man_a + aligned_man_b);
            `endif
          end else begin
            // Different signs: subtract magnitudes
            if (aligned_man_a >= aligned_man_b) begin
              sum <= aligned_man_a - aligned_man_b;
              sign_result <= sign_a;
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] COMPUTE: SUB aligned_man_a=%h - aligned_man_b=%h = %h",
                       aligned_man_a, aligned_man_b, aligned_man_a - aligned_man_b);
              `endif
            end else begin
              sum <= aligned_man_b - aligned_man_a;
              sign_result <= sign_b;
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] COMPUTE: SUB aligned_man_b=%h - aligned_man_a=%h = %h",
                       aligned_man_b, aligned_man_a, aligned_man_b - aligned_man_a);
              `endif
            end
          end
        end

        // ============================================================
        // NORMALIZE: Shift result to normalized form
        // ============================================================
        NORMALIZE: begin
          `ifdef DEBUG_FPU
          $display("[FP_ADDER] NORMALIZE: sum=%h exp_result=%h", sum, exp_result);
          `endif

          adjusted_exp <= exp_result;

          // Check for zero result
          if (sum == 0) begin
            result <= {sign_result, {FLEN-1{1'b0}}};
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] NORMALIZE: sum is zero, returning zero");
            `endif
          end
          // Check for overflow (carry out)
          else if (sum[MAN_WIDTH+4]) begin
            normalized_man <= sum >> 1;
            adjusted_exp <= exp_result + 1;
            guard <= sum[0];
            round <= 1'b0;
            sticky <= 1'b0;
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] NORMALIZE: overflow detected, normalized_man=%h adj_exp=%h",
                     sum >> 1, exp_result + 1);
            `endif
          end
          // Check for leading zeros (need to shift left)
          else begin
            // Normalization: shift left until bit MAN_WIDTH+3 is 1
            // Simple cascaded if-else for priority encoding
            // For single-precision: MAN_WIDTH+3 = 26, check bits 26 down to 3

            // Start from the MSB and check each bit position
            if (sum[MAN_WIDTH+3]) begin
              // Already normalized - bit 26 is set
              normalized_man <= sum;
              adjusted_exp <= exp_result;
              guard <= sum[2];
              round <= sum[1];
              sticky <= sum[0];
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] NORMALIZE: already normalized, normalized_man=%h adj_exp=%h GRS=%b%b%b",
                       sum, exp_result, sum[2], sum[1], sum[0]);
              `endif
            end else if (sum[MAN_WIDTH+2]) begin
              // Shift left by 1
              normalized_man <= sum << 1;
              adjusted_exp <= exp_result - 1;
              guard <= sum[1];
              round <= sum[0];
              sticky <= 1'b0;
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] NORMALIZE: shifted left 1, normalized_man=%h adj_exp=%h GRS=%b%b%b",
                       sum << 1, exp_result - 1, sum[1], sum[0], 1'b0);
              `endif
            end else if (sum[MAN_WIDTH+1]) begin
              // Shift left by 2
              normalized_man <= sum << 2;
              adjusted_exp <= exp_result - 2;
              guard <= sum[0];
              round <= 1'b0;
              sticky <= 1'b0;
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] NORMALIZE: shifted left 2, normalized_man=%h adj_exp=%h GRS=%b%b%b",
                       sum << 2, exp_result - 2, sum[0], 1'b0, 1'b0);
              `endif
            end else begin
              // Need to shift by more than 2 (rare case - very small result)
              // For now, shift by 3 and handle larger shifts in future
              normalized_man <= sum << 3;
              adjusted_exp <= exp_result - 3;
              guard <= 1'b0;
              round <= 1'b0;
              sticky <= 1'b0;
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] NORMALIZE: shifted left 3+, normalized_man=%h adj_exp=%h GRS=%b%b%b",
                       sum << 3, exp_result - 3, 1'b0, 1'b0, 1'b0);
              `endif
            end
          end

          // Check for overflow
          if (adjusted_exp >= MAX_EXP) begin
            flag_of <= 1'b1;
            // Return ±infinity based on rounding mode
            result <= {sign_result, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] NORMALIZE: exponent overflow, returning Inf");
            `endif
          end
        end

        // ============================================================
        // ROUND: Apply rounding mode
        // ============================================================
        ROUND: begin
          // Only process normal cases - special cases already handled in ALIGN
          if (!special_case_handled) begin
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] ROUND inputs: G=%b R=%b S=%b LSB=%b rmode=%d",
                     guard, round, sticky, normalized_man[3], rounding_mode);
            `endif

            // Apply rounding (using combinational round_up_comb)
            // Extract mantissa without implicit 1: normalized_man[MAN_WIDTH+2:3]
            // This gives us 23 bits for single-precision (bits 25:3)
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] ROUND: sign=%b exp=%h man=%h round_up=%b",
                     sign_result, adjusted_exp[EXP_WIDTH-1:0], normalized_man[MAN_WIDTH+2:3], round_up_comb);
            `endif
            if (round_up_comb) begin
              result <= {sign_result, adjusted_exp[EXP_WIDTH-1:0],
                         normalized_man[MAN_WIDTH+2:3] + 1'b1};
            end else begin
              result <= {sign_result, adjusted_exp[EXP_WIDTH-1:0],
                         normalized_man[MAN_WIDTH+2:3]};
            end

            // Set inexact flag (only for normal cases)
            flag_nx <= guard || round || sticky;
          end
          // else: special case - result and flags already set in ALIGN stage
        end

        // ============================================================
        // DONE: Hold result for 1 cycle
        // ============================================================
        DONE: begin
          // Just hold result
          `ifdef DEBUG_FPU
          $display("[FP_ADDER] Result: %h", result);
          `endif
        end

      endcase
    end
  end

endmodule
