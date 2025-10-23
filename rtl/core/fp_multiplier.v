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
  input  wire              fmt,            // 0: single-precision, 1: double-precision
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

  // Latched input operands (captured on start)
  reg [FLEN-1:0] operand_a_latched, operand_b_latched;
  reg fmt_latched;  // Latched format signal

  // Unpacked operands
  reg sign_a, sign_b, sign_result;
  reg [10:0] exp_a, exp_b;  // Max width for double-precision (11 bits)
  reg [52:0] man_a, man_b;  // Max width for double-precision (52+1 bits for implicit 1)

  // Special value flags
  reg is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;
  reg special_case_handled;  // Track if special case was processed

  // Effective widths based on latched format
  wire [10:0] eff_exp_all_ones;  // All 1s for current format
  wire [5:0] eff_man_width;      // Effective mantissa width
  wire [3:0] eff_exp_width;      // Effective exponent width

  assign eff_exp_all_ones = fmt_latched ? 11'h7FF : 11'h0FF;
  assign eff_man_width = fmt_latched ? 6'd52 : 6'd23;
  assign eff_exp_width = fmt_latched ? 4'd11 : 4'd8;

  // Computation
  reg [12:0] exp_sum;  // Max 11+2 bits for double-precision overflow handling
  reg [109:0] product;  // Double width for double-precision: (52+1)*2 + extra = 106+4
  reg [52:0] normalized_man;  // Max width for double-precision
  reg [10:0] exp_result;  // Max width for double-precision

  // Rounding
  reg guard, round, sticky;
  reg round_up;

  // LSB for RNE tie-breaking (format-aware)
  wire lsb_bit_mul;
  assign lsb_bit_mul = fmt_latched ? normalized_man[0] : normalized_man[29];

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
      special_case_handled <= 1'b0;
    end else begin
      case (state)

        // ============================================================
        // IDLE: Latch operands when start asserted
        // ============================================================
        IDLE: begin
          if (start) begin
            operand_a_latched <= operand_a;
            operand_b_latched <= operand_b;
            fmt_latched <= fmt;
          end
        end

        // ============================================================
        // UNPACK: Extract sign, exponent, mantissa
        // ============================================================
        UNPACK: begin
          // Clear special case flag for new operation
          special_case_handled <= 1'b0;

          // Extract sign (XOR for multiplication)
          // For FLEN=64: use bit [63] for double, bit [31] for single
          if (FLEN == 64) begin
            sign_a <= fmt_latched ? operand_a_latched[63] : operand_a_latched[31];
            sign_b <= fmt_latched ? operand_b_latched[63] : operand_b_latched[31];
            sign_result <= (fmt_latched ? operand_a_latched[63] : operand_a_latched[31]) ^
                           (fmt_latched ? operand_b_latched[63] : operand_b_latched[31]);
          end else begin
            sign_a <= operand_a_latched[31];
            sign_b <= operand_b_latched[31];
            sign_result <= operand_a_latched[31] ^ operand_b_latched[31];
          end

          // Extract exponent based on format
          if (FLEN == 64) begin
            exp_a <= fmt_latched ? operand_a_latched[62:52] : {3'b000, operand_a_latched[30:23]};
            exp_b <= fmt_latched ? operand_b_latched[62:52] : {3'b000, operand_b_latched[30:23]};
          end else begin
            exp_a <= {3'b000, operand_a_latched[30:23]};
            exp_b <= {3'b000, operand_b_latched[30:23]};
          end

          // Extract mantissa with implicit leading 1 (if normalized)
          // For double: bits [51:0], for single: bits [22:0]
          if (FLEN == 64) begin
            if (fmt_latched) begin
              // Double-precision
              man_a <= (operand_a_latched[62:52] == 0) ?
                       {1'b0, operand_a_latched[51:0]} :  // Subnormal
                       {1'b1, operand_a_latched[51:0]};   // Normal
              man_b <= (operand_b_latched[62:52] == 0) ?
                       {1'b0, operand_b_latched[51:0]} :
                       {1'b1, operand_b_latched[51:0]};
            end else begin
              // Single-precision (pad to 53 bits)
              man_a <= (operand_a_latched[30:23] == 0) ?
                       {1'b0, operand_a_latched[22:0], 29'b0} :  // Subnormal
                       {1'b1, operand_a_latched[22:0], 29'b0};   // Normal
              man_b <= (operand_b_latched[30:23] == 0) ?
                       {1'b0, operand_b_latched[22:0], 29'b0} :
                       {1'b1, operand_b_latched[22:0], 29'b0};
            end
          end else begin
            // FLEN=32, always single-precision (pad to 53 bits for consistency)
            man_a <= (operand_a_latched[30:23] == 0) ?
                     {1'b0, operand_a_latched[22:0], 29'b0} :
                     {1'b1, operand_a_latched[22:0], 29'b0};
            man_b <= (operand_b_latched[30:23] == 0) ?
                     {1'b0, operand_b_latched[22:0], 29'b0} :
                     {1'b1, operand_b_latched[22:0], 29'b0};
          end

          // Detect special values (using extracted exponent and mantissa)
          `ifdef DEBUG_FPU
          $display("[FP_MUL] UNPACK: operand_a=%h operand_b=%h fmt=%b", operand_a_latched, operand_b_latched, fmt_latched);
          `endif

          // NaN detection: exp == all 1s AND mantissa != 0
          if (FLEN == 64) begin
            is_nan_a <= fmt_latched ?
                        ((operand_a_latched[62:52] == 11'h7FF) && (operand_a_latched[51:0] != 0)) :
                        ((operand_a_latched[30:23] == 8'hFF) && (operand_a_latched[22:0] != 0));
            is_nan_b <= fmt_latched ?
                        ((operand_b_latched[62:52] == 11'h7FF) && (operand_b_latched[51:0] != 0)) :
                        ((operand_b_latched[30:23] == 8'hFF) && (operand_b_latched[22:0] != 0));
            is_inf_a <= fmt_latched ?
                        ((operand_a_latched[62:52] == 11'h7FF) && (operand_a_latched[51:0] == 0)) :
                        ((operand_a_latched[30:23] == 8'hFF) && (operand_a_latched[22:0] == 0));
            is_inf_b <= fmt_latched ?
                        ((operand_b_latched[62:52] == 11'h7FF) && (operand_b_latched[51:0] == 0)) :
                        ((operand_b_latched[30:23] == 8'hFF) && (operand_b_latched[22:0] == 0));
            is_zero_a <= fmt_latched ?
                         (operand_a_latched[62:0] == 0) :
                         (operand_a_latched[30:0] == 0);
            is_zero_b <= fmt_latched ?
                         (operand_b_latched[62:0] == 0) :
                         (operand_b_latched[30:0] == 0);
          end else begin
            is_nan_a <= (operand_a_latched[30:23] == 8'hFF) && (operand_a_latched[22:0] != 0);
            is_nan_b <= (operand_b_latched[30:23] == 8'hFF) && (operand_b_latched[22:0] != 0);
            is_inf_a <= (operand_a_latched[30:23] == 8'hFF) && (operand_a_latched[22:0] == 0);
            is_inf_b <= (operand_b_latched[30:23] == 8'hFF) && (operand_b_latched[22:0] == 0);
            is_zero_a <= (operand_a_latched[30:0] == 0);
            is_zero_b <= (operand_b_latched[30:0] == 0);
          end
        end

        // ============================================================
        // MULTIPLY: Compute product and exponent
        // ============================================================
        MULTIPLY: begin
          // Handle special cases
          `ifdef DEBUG_FPU
          $display("[FP_MUL] MULTIPLY: is_nan_a=%b is_nan_b=%b is_inf_a=%b is_inf_b=%b is_zero_a=%b is_zero_b=%b",
                   is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b);
          `endif
          if (is_nan_a || is_nan_b) begin
            // NaN propagation (canonical NaN)
            if (fmt_latched) begin
              result <= 64'h7FF8000000000000;  // Double canonical NaN
            end else begin
              result <= (FLEN == 64) ? 64'hFFFFFFFF7FC00000 : 32'h7FC00000;  // Single canonical NaN (NaN-boxed if needed)
            end
            flag_nv <= 1'b1;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            flag_nx <= 1'b0;
            special_case_handled <= 1'b1;
            state <= DONE;
          end else if ((is_inf_a && is_zero_b) || (is_zero_a && is_inf_b)) begin
            // 0 × ∞: Invalid - return canonical NaN
            if (fmt_latched) begin
              result <= 64'h7FF8000000000000;
            end else begin
              result <= (FLEN == 64) ? 64'hFFFFFFFF7FC00000 : 32'h7FC00000;
            end
            flag_nv <= 1'b1;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            flag_nx <= 1'b0;
            special_case_handled <= 1'b1;
            state <= DONE;
          end else if (is_inf_a || is_inf_b) begin
            // ∞ × x: return ±∞
            if (fmt_latched) begin
              result <= {sign_result, 11'h7FF, 52'b0};  // Double infinity
            end else begin
              result <= (FLEN == 64) ? {32'hFFFFFFFF, sign_result, 8'hFF, 23'b0} : {sign_result, 8'hFF, 23'b0};  // Single infinity
            end
            flag_nv <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            flag_nx <= 1'b0;
            special_case_handled <= 1'b1;
            state <= DONE;
          end else if (is_zero_a || is_zero_b) begin
            // 0 × x: return ±0
            if (fmt_latched) begin
              result <= {sign_result, 63'b0};  // Double zero
            end else begin
              result <= (FLEN == 64) ? {32'hFFFFFFFF, sign_result, 31'b0} : {sign_result, 31'b0};  // Single zero
            end
            flag_nv <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            flag_nx <= 1'b0;
            special_case_handled <= 1'b1;
            state <= DONE;
          end else begin
            // Normal multiplication
            // Multiply mantissas
            product <= man_a * man_b;
            `ifdef DEBUG_FPU
            $display("[FP_MUL] MULTIPLY: man_a=%h man_b=%h product=%h", man_a, man_b, man_a * man_b);
            `endif

            // Add exponents (subtract bias)
            // exp_sum = exp_a + exp_b - BIAS
            // Use correct bias based on format
            if (fmt_latched)
              exp_sum <= exp_a + exp_b - 13'd1023;  // Double-precision bias
            else
              exp_sum <= exp_a + exp_b - 13'd127;   // Single-precision bias
          end
        end

        // ============================================================
        // NORMALIZE: Shift product to normalized form
        // ============================================================
        NORMALIZE: begin
          // Product is (1.xxx * 1.yyy) = 1.zzz to 3.zzz (needs 0 or 1 shift)
          //
          // For double-precision (fmt=1): man_a, man_b are 53 bits each
          //   Product is 106 bits, bit [105] = overflow, bit [104] = MSB of normal result
          //
          // For single-precision (fmt=0): man_a, man_b are 24 bits + 29 zero padding = 53 bits
          //   Product is 106 bits, but actual mantissa product is at bits [105:58]
          //   (24+1) * (24+1) = 48-bit product at top, padding below

          `ifdef DEBUG_FPU
          $display("[FP_MUL] NORMALIZE: product=%h fmt=%b", product, fmt_latched);
          `endif

          if (fmt_latched) begin
            // Double-precision: 53-bit mantissas, 106-bit product
            if (product[105]) begin
              // Product >= 2.0, shift right by 1
              normalized_man <= {1'b0, product[104:53]};
              exp_result <= exp_sum + 1;
              guard <= product[52];
              round <= product[51];
              sticky <= |product[50:0];
            end else begin
              // Product in [1.0, 2.0), already normalized
              normalized_man <= {1'b0, product[103:52]};
              exp_result <= exp_sum;
              guard <= product[51];
              round <= product[50];
              sticky <= |product[49:0];
            end
          end else begin
            // Single-precision: 24-bit mantissas in 53-bit container (bits [52:29])
            // Product of two 24-bit mantissas = 48 bits at positions [105:58]
            if (product[105]) begin
              // Product >= 2.0, shift right by 1
              // Extract mantissa from [104:82] (23 bits)
              normalized_man <= {1'b0, product[104:82], 29'b0};  // Pad to 53 bits
              exp_result <= exp_sum + 1;
              guard <= product[81];
              round <= product[80];
              sticky <= |product[79:0];
              `ifdef DEBUG_FPU
              $display("[FP_MUL] NORMALIZE SP: >= 2.0, extract product[104:82]=%h", product[104:82]);
              `endif
            end else begin
              // Product in [1.0, 2.0), already normalized
              // Extract mantissa from [103:81] (23 bits)
              normalized_man <= {1'b0, product[103:81], 29'b0};  // Pad to 53 bits
              exp_result <= exp_sum;
              guard <= product[80];
              round <= product[79];
              sticky <= |product[78:0];
              `ifdef DEBUG_FPU
              $display("[FP_MUL] NORMALIZE SP: < 2.0, extract product[103:81]=%h", product[103:81]);
              `endif
            end
          end

          // Check for overflow (use correct MAX_EXP based on format)
          if (fmt_latched) begin
            if (exp_sum >= 13'd2047 || exp_result >= 11'd2047) begin
              flag_of <= 1'b1;
              flag_nx <= 1'b1;
              result <= {sign_result, 11'h7FF, 52'b0};  // Double infinity
              state <= DONE;
            end else if (exp_sum < 1 || exp_result < 1) begin
              flag_uf <= 1'b1;
              flag_nx <= 1'b1;
              result <= {sign_result, 63'b0};  // Double zero
              state <= DONE;
            end
          end else begin
            if (exp_sum >= 13'd255 || exp_result >= 11'd255) begin
              flag_of <= 1'b1;
              flag_nx <= 1'b1;
              result <= {32'hFFFFFFFF, sign_result, 8'hFF, 23'b0};  // Single infinity (NaN-boxed)
              state <= DONE;
            end else if (exp_sum < 1 || exp_result < 1) begin
              flag_uf <= 1'b1;
              flag_nx <= 1'b1;
              result <= {32'hFFFFFFFF, sign_result, 31'b0};  // Single zero (NaN-boxed)
              state <= DONE;
            end
          end
        end

        // ============================================================
        // ROUND: Apply rounding mode
        // ============================================================
        ROUND: begin
          // Only process normal cases - special cases already handled
          if (!special_case_handled) begin
            // Determine if we should round up
            case (rounding_mode)
              3'b000: begin  // RNE: Round to nearest, ties to even
                round_up <= guard && (round || sticky || lsb_bit_mul);
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

            // Apply rounding and assemble result based on format
            if (fmt_latched) begin
              // Double-precision result
              if (round_up) begin
                result <= {sign_result, exp_result, normalized_man[51:0] + 1'b1};
              end else begin
                result <= {sign_result, exp_result, normalized_man[51:0]};
              end
            end else begin
              // Single-precision result (NaN-boxed for FLEN=64)
              if (FLEN == 64) begin
                if (round_up) begin
                  result <= {32'hFFFFFFFF, sign_result, exp_result[7:0], normalized_man[51:29] + 1'b1};
                end else begin
                  result <= {32'hFFFFFFFF, sign_result, exp_result[7:0], normalized_man[51:29]};
                end
              end else begin
                if (round_up) begin
                  result <= {sign_result, exp_result[7:0], normalized_man[51:29] + 1'b1};
                end else begin
                  result <= {sign_result, exp_result[7:0], normalized_man[51:29]};
                end
              end
            end

            `ifdef DEBUG_FPU
            $display("[FP_MUL] ROUND: fmt=%b sign=%b exp=%h normalized_man=%h GRS=%b%b%b round_up=%b",
                     fmt_latched, sign_result, exp_result, normalized_man, guard, round, sticky, round_up);
            if (fmt_latched)
              $display("[FP_MUL] Result (DP): %h", {sign_result, exp_result, normalized_man[51:0] + (round_up ? 1'b1 : 1'b0)});
            else
              $display("[FP_MUL] Result (SP): %h", {sign_result, exp_result[7:0], normalized_man[51:29] + (round_up ? 1'b1 : 1'b0)});
            `endif

            // Set inexact flag (only for normal cases)
            flag_nx <= guard || round || sticky;
          end
          // else: special case - result and flags already set
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
