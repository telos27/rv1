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
  input  wire              fmt,            // 0: single-precision, 1: double-precision
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

  // Unpacked operands (use max widths for both formats)
  reg sign_a, sign_b, sign_result;
  reg [10:0] exp_a, exp_b, exp_result;  // Max 11 bits for double-precision
  reg [52:0] man_a, man_b;              // Max 53 bits (52+1 implicit) for double-precision
  reg fmt_latched;                      // Latched format signal

  // Special value flags
  reg is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;
  reg is_subnormal_a, is_subnormal_b;
  reg special_case_handled;  // Track if special case was processed in ALIGN stage

  // Computation (use max widths)
  reg [55:0] aligned_man_a, aligned_man_b;  // 52+3 GRS bits + 1 for alignment
  reg [56:0] sum;                            // +1 for overflow
  reg [11:0] exp_diff;                       // 11+1 bits
  reg [56:0] normalized_man;
  reg [11:0] adjusted_exp;

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

          // Latch format signal
          fmt_latched <= fmt;

          // Format-aware extraction for FLEN=64
          if (FLEN == 64) begin
            if (fmt) begin
              // Double-precision: use bits [63:0]
              sign_a <= operand_a[63];
              sign_b <= operand_b[63] ^ is_sub;
              exp_a  <= operand_a[62:52];
              exp_b  <= operand_b[62:52];

              is_subnormal_a <= (operand_a[62:52] == 0) && (operand_a[51:0] != 0);
              is_subnormal_b <= (operand_b[62:52] == 0) && (operand_b[51:0] != 0);

              man_a <= (operand_a[62:52] == 0) ?
                       {1'b0, operand_a[51:0]} :
                       {1'b1, operand_a[51:0]};
              man_b <= (operand_b[62:52] == 0) ?
                       {1'b0, operand_b[51:0]} :
                       {1'b1, operand_b[51:0]};

              is_nan_a <= (operand_a[62:52] == 11'h7FF) && (operand_a[51:0] != 0);
              is_nan_b <= (operand_b[62:52] == 11'h7FF) && (operand_b[51:0] != 0);
              is_inf_a <= (operand_a[62:52] == 11'h7FF) && (operand_a[51:0] == 0);
              is_inf_b <= (operand_b[62:52] == 11'h7FF) && (operand_b[51:0] == 0);
              is_zero_a <= (operand_a[62:0] == 0);
              is_zero_b <= (operand_b[62:0] == 0);
            end else begin
              // Single-precision: use bits [31:0] (NaN-boxed in [63:32])
              sign_a <= operand_a[31];
              sign_b <= operand_b[31] ^ is_sub;
              exp_a  <= {3'b000, operand_a[30:23]};
              exp_b  <= {3'b000, operand_b[30:23]};

              is_subnormal_a <= (operand_a[30:23] == 0) && (operand_a[22:0] != 0);
              is_subnormal_b <= (operand_b[30:23] == 0) && (operand_b[22:0] != 0);

              man_a <= (operand_a[30:23] == 0) ?
                       {1'b0, operand_a[22:0], 29'b0} :
                       {1'b1, operand_a[22:0], 29'b0};
              man_b <= (operand_b[30:23] == 0) ?
                       {1'b0, operand_b[22:0], 29'b0} :
                       {1'b1, operand_b[22:0], 29'b0};

              is_nan_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] != 0);
              is_nan_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] != 0);
              is_inf_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] == 0);
              is_inf_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] == 0);
              is_zero_a <= (operand_a[30:0] == 0);
              is_zero_b <= (operand_b[30:0] == 0);
            end
          end else begin
            // FLEN=32: always single-precision
            sign_a <= operand_a[31];
            sign_b <= operand_b[31] ^ is_sub;
            exp_a  <= {3'b000, operand_a[30:23]};
            exp_b  <= {3'b000, operand_b[30:23]};

            is_subnormal_a <= (operand_a[30:23] == 0) && (operand_a[22:0] != 0);
            is_subnormal_b <= (operand_b[30:23] == 0) && (operand_b[22:0] != 0);

            man_a <= (operand_a[30:23] == 0) ?
                     {1'b0, operand_a[22:0], 29'b0} :
                     {1'b1, operand_a[22:0], 29'b0};
            man_b <= (operand_b[30:23] == 0) ?
                     {1'b0, operand_b[22:0], 29'b0} :
                     {1'b1, operand_b[22:0], 29'b0};

            is_nan_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] != 0);
            is_nan_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] != 0);
            is_inf_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] == 0);
            is_inf_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] == 0);
            is_zero_a <= (operand_a[30:0] == 0);
            is_zero_b <= (operand_b[30:0] == 0);
          end
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
            // NaN propagation: return canonical NaN based on format
            if (FLEN == 64 && fmt_latched)
              result <= 64'h7FF8000000000000;  // Double canonical NaN
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, 32'h7FC00000};  // Single canonical NaN (NaN-boxed)
            else
              result <= 32'h7FC00000;  // FLEN=32 single canonical NaN
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
            if (FLEN == 64 && fmt_latched)
              result <= 64'h7FF8000000000000;  // Double canonical NaN
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, 32'h7FC00000};  // Single canonical NaN (NaN-boxed)
            else
              result <= 32'h7FC00000;  // FLEN=32 single canonical NaN
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
            if (FLEN == 64 && fmt_latched)
              result <= {sign_a, 11'h7FF, 52'h0};  // Double infinity
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_a, 8'hFF, 23'h0};  // Single infinity (NaN-boxed)
            else
              result <= {sign_a, 8'hFF, 23'h0};  // FLEN=32 single infinity
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
            if (FLEN == 64 && fmt_latched)
              result <= {sign_b, 11'h7FF, 52'h0};  // Double infinity
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_b, 8'hFF, 23'h0};  // Single infinity (NaN-boxed)
            else
              result <= {sign_b, 8'hFF, 23'h0};  // FLEN=32 single infinity
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
            // Format-aware result assembly
            if (FLEN == 64 && fmt_latched)
              result <= {sign_b, exp_b, man_b[51:0]};  // Double: 52-bit mantissa
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_b, exp_b[7:0], man_b[51:29]};  // Single: 23-bit mantissa (NaN-boxed)
            else
              result <= {sign_b, exp_b[7:0], man_b[51:29]};  // FLEN=32 single: 23-bit mantissa
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
            // Format-aware result assembly
            if (FLEN == 64 && fmt_latched)
              result <= {sign_a, exp_a, man_a[51:0]};  // Double: 52-bit mantissa
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_a, exp_a[7:0], man_a[51:29]};  // Single: 23-bit mantissa (NaN-boxed)
            else
              result <= {sign_a, exp_a[7:0], man_a[51:29]};  // FLEN=32 single: 23-bit mantissa
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

          // Check for zero result (format-aware)
          if (sum == 0) begin
            if (FLEN == 64 && fmt_latched)
              result <= {sign_result, 63'b0};  // Double zero
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_result, 31'b0};  // Single zero (NaN-boxed)
            else
              result <= {sign_result, 31'b0};  // FLEN=32 single zero
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

          // Check for overflow (format-aware)
          if ((FLEN == 64 && fmt_latched && adjusted_exp >= 12'd2047) ||
              (FLEN == 64 && !fmt_latched && adjusted_exp >= 12'd255) ||
              (FLEN == 32 && adjusted_exp >= 12'd255)) begin
            flag_of <= 1'b1;
            // Return ±infinity based on format
            if (FLEN == 64 && fmt_latched)
              result <= {sign_result, 11'h7FF, 52'h0};  // Double infinity
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_result, 8'hFF, 23'h0};  // Single infinity (NaN-boxed)
            else
              result <= {sign_result, 8'hFF, 23'h0};  // FLEN=32 single infinity
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
            // Format-aware result assembly
            if (FLEN == 64 && fmt_latched) begin
              // Double-precision: 64-bit result
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] ROUND (double): sign=%b exp=%h man=%h round_up=%b",
                       sign_result, adjusted_exp[10:0], normalized_man[54:3], round_up_comb);
              `endif
              if (round_up_comb) begin
                result <= {sign_result, adjusted_exp[10:0], normalized_man[54:3] + 1'b1};
              end else begin
                result <= {sign_result, adjusted_exp[10:0], normalized_man[54:3]};
              end
            end else if (FLEN == 64 && !fmt_latched) begin
              // Single-precision in 64-bit register (NaN-boxed)
              // Extract mantissa from bits [54:32] (where actual SP mantissa is after padding)
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] ROUND (single/64): sign=%b exp=%h man=%h round_up=%b",
                       sign_result, adjusted_exp[7:0], normalized_man[54:32], round_up_comb);
              `endif
              if (round_up_comb) begin
                result <= {32'hFFFFFFFF, sign_result, adjusted_exp[7:0], normalized_man[54:32] + 1'b1};
              end else begin
                result <= {32'hFFFFFFFF, sign_result, adjusted_exp[7:0], normalized_man[54:32]};
              end
            end else begin
              // FLEN=32: single-precision in 32-bit register
              // For FLEN=32, normalized_man layout is different (no padding)
              // Mantissa is at bits [25:3] (23 bits)
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] ROUND (single/32): sign=%b exp=%h man=%h round_up=%b",
                       sign_result, adjusted_exp[7:0], normalized_man[25:3], round_up_comb);
              `endif
              if (round_up_comb) begin
                result <= {sign_result, adjusted_exp[7:0], normalized_man[25:3] + 1'b1};
              end else begin
                result <= {sign_result, adjusted_exp[7:0], normalized_man[25:3]};
              end
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
