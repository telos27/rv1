// Floating-Point Fused Multiply-Add Unit
// Implements FMADD.S/D, FMSUB.S/D, FNMSUB.S/D, FNMADD.S/D instructions
// IEEE 754-2008 compliant with single rounding step (key advantage over separate ops)
// Multi-cycle execution: 4-5 cycles

`include "config/rv_config.vh"

module fp_fma #(
  parameter FLEN = `FLEN  // 32 for single-precision, 64 for double-precision
) (
  input  wire              clk,
  input  wire              reset_n,

  // Control
  input  wire              start,          // Start operation
  input  wire              fmt,            // Format: 0=single, 1=double
  input  wire [1:0]        fma_op,         // 00: FMADD, 01: FMSUB, 10: FNMSUB, 11: FNMADD
  input  wire [2:0]        rounding_mode,  // IEEE 754 rounding mode
  output reg               busy,           // Operation in progress
  output reg               done,           // Operation complete (1 cycle pulse)

  // Operands: (rs1 * rs2) ± rs3
  input  wire [FLEN-1:0]   operand_a,      // rs1 (multiplicand)
  input  wire [FLEN-1:0]   operand_b,      // rs2 (multiplier)
  input  wire [FLEN-1:0]   operand_c,      // rs3 (addend)

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
  localparam ADD       = 3'b011;
  localparam NORMALIZE = 3'b100;
  localparam ROUND     = 3'b101;
  localparam DONE      = 3'b110;

  reg [2:0] state, next_state;

  // Unpacked operands
  reg sign_a, sign_b, sign_c, sign_prod, sign_result;
  reg [EXP_WIDTH-1:0] exp_a, exp_b, exp_c;
  reg [MAN_WIDTH:0] man_a, man_b, man_c;

  // Special value flags
  reg is_nan_a, is_nan_b, is_nan_c;
  reg is_inf_a, is_inf_b, is_inf_c;
  reg is_zero_a, is_zero_b, is_zero_c;

  // Format latching
  reg fmt_latched;

  // Format-aware BIAS for exponent arithmetic
  wire [10:0] bias_val;
  assign bias_val = (FLEN == 64 && !fmt_latched) ? 11'd127 : 11'd1023;

  // Computation
  reg [EXP_WIDTH+1:0] exp_prod;               // Product exponent
  reg [(2*MAN_WIDTH+3):0] product;            // Product mantissa (double width)
  reg [(2*MAN_WIDTH+5):0] aligned_c;          // Aligned addend
  reg [(2*MAN_WIDTH+6):0] product_positioned; // Product positioned for addition
  reg [(2*MAN_WIDTH+6):0] sum;                // Sum result
  reg [EXP_WIDTH+1:0] exp_diff;               // Exponent difference
  reg [EXP_WIDTH-1:0] exp_result;

  // Rounding
  reg guard, round, sticky;
  reg round_up;

  // Format-aware LSB for RNE rounding (tie-breaking)
  // For single-precision in FLEN=64, mantissa is in upper bits, LSB is at sum[MAN_WIDTH+5+29]
  // For double-precision, LSB is at sum[3] (mantissa at [54:3])
  wire lsb_bit_fma;
  assign lsb_bit_fma = (FLEN == 64 && !fmt_latched) ? sum[MAN_WIDTH+5+29] : sum[3];

  // Compute round_up combinationally for use in same cycle
  wire round_up_comb;
  assign round_up_comb = (rounding_mode == 3'b000) ? (guard && (round || sticky || lsb_bit_fma)) :  // RNE
                         (rounding_mode == 3'b010) ? (sign_result && (guard || round || sticky)) :   // RDN
                         (rounding_mode == 3'b011) ? (!sign_result && (guard || round || sticky)) :  // RUP
                         (rounding_mode == 3'b100) ? guard : 1'b0;                                   // RMM or RTZ

  // FMA operation decode
  wire negate_product = fma_op[1];  // FNMSUB, FNMADD negate product
  wire subtract_addend = fma_op[0]; // FMSUB, FNMADD subtract addend

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
      MULTIPLY:  next_state = ADD;
      ADD:       next_state = NORMALIZE;
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
      // Initialize working registers to prevent X propagation
      sign_a <= 1'b0;
      sign_b <= 1'b0;
      sign_c <= 1'b0;
      sign_prod <= 1'b0;
      sign_result <= 1'b0;
      exp_a <= {EXP_WIDTH{1'b0}};
      exp_b <= {EXP_WIDTH{1'b0}};
      exp_c <= {EXP_WIDTH{1'b0}};
      man_a <= {(MAN_WIDTH+1){1'b0}};
      man_b <= {(MAN_WIDTH+1){1'b0}};
      man_c <= {(MAN_WIDTH+1){1'b0}};
      is_nan_a <= 1'b0;
      is_nan_b <= 1'b0;
      is_nan_c <= 1'b0;
      is_inf_a <= 1'b0;
      is_inf_b <= 1'b0;
      is_inf_c <= 1'b0;
      is_zero_a <= 1'b0;
      is_zero_b <= 1'b0;
      is_zero_c <= 1'b0;
      exp_prod <= {(EXP_WIDTH+2){1'b0}};
      product <= {(2*MAN_WIDTH+4){1'b0}};
      aligned_c <= {(2*MAN_WIDTH+6){1'b0}};
      sum <= {(2*MAN_WIDTH+7){1'b0}};
      exp_diff <= {(EXP_WIDTH+2){1'b0}};
      exp_result <= {EXP_WIDTH{1'b0}};
      guard <= 1'b0;
      round <= 1'b0;
      sticky <= 1'b0;
      round_up <= 1'b0;
    end else begin
      case (state)

        // ============================================================
        // UNPACK: Extract sign, exponent, mantissa from all 3 operands
        // ============================================================
        UNPACK: begin
          // Latch format for entire operation
          fmt_latched <= fmt;

          // Format-aware extraction for FLEN=64
          if (FLEN == 64) begin
            if (fmt) begin
              // Double-precision: use bits [63:0]
              // Operand A (rs1)
              sign_a <= operand_a[63];
              exp_a <= operand_a[62:52];
              man_a <= (operand_a[62:52] == 0) ?
                       {1'b0, operand_a[51:0]} :
                       {1'b1, operand_a[51:0]};
              is_nan_a <= (operand_a[62:52] == 11'h7FF) && (operand_a[51:0] != 0);
              is_inf_a <= (operand_a[62:52] == 11'h7FF) && (operand_a[51:0] == 0);
              is_zero_a <= (operand_a[62:0] == 0);

              // Operand B (rs2)
              sign_b <= operand_b[63];
              exp_b <= operand_b[62:52];
              man_b <= (operand_b[62:52] == 0) ?
                       {1'b0, operand_b[51:0]} :
                       {1'b1, operand_b[51:0]};
              is_nan_b <= (operand_b[62:52] == 11'h7FF) && (operand_b[51:0] != 0);
              is_inf_b <= (operand_b[62:52] == 11'h7FF) && (operand_b[51:0] == 0);
              is_zero_b <= (operand_b[62:0] == 0);

              // Operand C (rs3)
              sign_c <= operand_c[63] ^ subtract_addend;
              exp_c <= operand_c[62:52];
              man_c <= (operand_c[62:52] == 0) ?
                       {1'b0, operand_c[51:0]} :
                       {1'b1, operand_c[51:0]};
              is_nan_c <= (operand_c[62:52] == 11'h7FF) && (operand_c[51:0] != 0);
              is_inf_c <= (operand_c[62:52] == 11'h7FF) && (operand_c[51:0] == 0);
              is_zero_c <= (operand_c[62:0] == 0);
            end else begin
              // Single-precision: use bits [31:0] (NaN-boxed in [63:32])
              // Operand A (rs1)
              sign_a <= operand_a[31];
              exp_a <= {3'b000, operand_a[30:23]};
              man_a <= (operand_a[30:23] == 0) ?
                       {1'b0, operand_a[22:0], 29'b0} :
                       {1'b1, operand_a[22:0], 29'b0};
              is_nan_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] != 0);
              is_inf_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] == 0);
              is_zero_a <= (operand_a[30:0] == 0);

              // Operand B (rs2)
              sign_b <= operand_b[31];
              exp_b <= {3'b000, operand_b[30:23]};
              man_b <= (operand_b[30:23] == 0) ?
                       {1'b0, operand_b[22:0], 29'b0} :
                       {1'b1, operand_b[22:0], 29'b0};
              is_nan_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] != 0);
              is_inf_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] == 0);
              is_zero_b <= (operand_b[30:0] == 0);

              // Operand C (rs3)
              sign_c <= operand_c[31] ^ subtract_addend;
              exp_c <= {3'b000, operand_c[30:23]};
              man_c <= (operand_c[30:23] == 0) ?
                       {1'b0, operand_c[22:0], 29'b0} :
                       {1'b1, operand_c[22:0], 29'b0};
              is_nan_c <= (operand_c[30:23] == 8'hFF) && (operand_c[22:0] != 0);
              is_inf_c <= (operand_c[30:23] == 8'hFF) && (operand_c[22:0] == 0);
              is_zero_c <= (operand_c[30:0] == 0);
            end
          end else begin
            // FLEN=32: always single-precision
            // Operand A (rs1)
            sign_a <= operand_a[31];
            exp_a <= {3'b000, operand_a[30:23]};
            man_a <= (operand_a[30:23] == 0) ?
                     {1'b0, operand_a[22:0], 29'b0} :
                     {1'b1, operand_a[22:0], 29'b0};
            is_nan_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] != 0);
            is_inf_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] == 0);
            is_zero_a <= (operand_a[30:0] == 0);

            // Operand B (rs2)
            sign_b <= operand_b[31];
            exp_b <= {3'b000, operand_b[30:23]};
            man_b <= (operand_b[30:23] == 0) ?
                     {1'b0, operand_b[22:0], 29'b0} :
                     {1'b1, operand_b[22:0], 29'b0};
            is_nan_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] != 0);
            is_inf_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] == 0);
            is_zero_b <= (operand_b[30:0] == 0);

            // Operand C (rs3)
            sign_c <= operand_c[31] ^ subtract_addend;
            exp_c <= {3'b000, operand_c[30:23]};
            man_c <= (operand_c[30:23] == 0) ?
                     {1'b0, operand_c[22:0], 29'b0} :
                     {1'b1, operand_c[22:0], 29'b0};
            is_nan_c <= (operand_c[30:23] == 8'hFF) && (operand_c[22:0] != 0);
            is_inf_c <= (operand_c[30:23] == 8'hFF) && (operand_c[22:0] == 0);
            is_zero_c <= (operand_c[30:0] == 0);
          end
        end

        // ============================================================
        // MULTIPLY: Compute product (rs1 * rs2)
        // ============================================================
        MULTIPLY: begin
          // Handle special cases
          if (is_nan_a || is_nan_b || is_nan_c) begin
            // NaN propagation
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, 32'h7FC00000};
            else if (FLEN == 64 && fmt_latched)
              result <= 64'h7FF8000000000000;
            else
              result <= 32'h7FC00000;
            flag_nv <= 1'b1;
            state <= DONE;
          end else if ((is_inf_a && is_zero_b) || (is_zero_a && is_inf_b)) begin
            // 0 × ∞: Invalid
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, 32'h7FC00000};
            else if (FLEN == 64 && fmt_latched)
              result <= 64'h7FF8000000000000;
            else
              result <= 32'h7FC00000;
            flag_nv <= 1'b1;
            state <= DONE;
          end else if ((is_inf_a || is_inf_b) && is_inf_c &&
                       ((sign_a ^ sign_b ^ negate_product) != sign_c)) begin
            // ∞ + (-∞): Invalid
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, 32'h7FC00000};
            else if (FLEN == 64 && fmt_latched)
              result <= 64'h7FF8000000000000;
            else
              result <= 32'h7FC00000;
            flag_nv <= 1'b1;
            state <= DONE;
          end else if (is_inf_a || is_inf_b || is_inf_c) begin
            // Result is ±∞
            if (is_inf_c)
              sign_result <= sign_c;
            else
              sign_result <= sign_a ^ sign_b ^ negate_product;
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_result, 8'hFF, 23'h0};
            else if (FLEN == 64 && fmt_latched)
              result <= {sign_result, 11'h7FF, 52'h0};
            else
              result <= {sign_result, 8'hFF, 23'h0};
            state <= DONE;
          end else if ((is_zero_a || is_zero_b) && is_zero_c) begin
            // 0 + 0
            sign_result <= (sign_a ^ sign_b ^ negate_product) && sign_c;
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_result, 31'h0};
            else if (FLEN == 64 && fmt_latched)
              result <= {sign_result, 63'h0};
            else
              result <= {sign_result, 31'h0};
            state <= DONE;
          end else if (is_zero_a || is_zero_b) begin
            // Product is 0, return addend
            `ifdef DEBUG_FPU
            $display("[FMA_SPECIAL] Product is zero, returning addend: sign_c=%b exp_c=%h man_c=%h", sign_c, exp_c, man_c);
            `endif
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_c, exp_c[7:0], man_c[51:29]};
            else if (FLEN == 64 && fmt_latched)
              result <= {sign_c, exp_c[10:0], man_c[51:0]};
            else
              result <= {sign_c, exp_c[7:0], man_c[51:29]};
            state <= DONE;
          end else if (is_zero_c) begin
            // Addend is 0, return product
            `ifdef DEBUG_FPU
            $display("[FMA_SPECIAL] Addend is zero, computing product only");
            `endif
            sign_prod <= sign_a ^ sign_b ^ negate_product;
            exp_prod <= exp_a + exp_b - bias_val;
            // Store 48-bit product directly - we'll position it during ADD
            product <= man_a * man_b;
          end else begin
            // Normal multiplication
            sign_prod <= sign_a ^ sign_b ^ negate_product;
            // Store 48-bit product directly - we'll position it during ADD
            product <= man_a * man_b;
            exp_prod <= exp_a + exp_b - bias_val;
          end
        end

        // ============================================================
        // ADD: Add product and addend (single rounding point!)
        // ============================================================
        ADD: begin
          `ifdef DEBUG_FPU
          $display("[FMA_ADD_START] exp_prod=%d exp_c=%d man_c=%h product=%h",
                   exp_prod, exp_c, man_c, product);
          `endif

          // Align operands by exponent
          // Product is 48 bits (from man_a * man_b)
          // man_c is 24 bits
          // Strategy: Position both in 53-bit sum register, aligned by their exponents
          //
          // Key insight: product and addend must be aligned so that equal exponents
          // have their leading 1's at the SAME bit position in the sum register.
          // When exponents differ, the smaller one is shifted right.
          //
          // Use blocking assignments (=) for intermediate computations
          //
          // For FLEN=64: man_c is 53 bits with leading bit at position 52
          // After product positioning (>>53), product has leading bit at ~51
          // So man_c also needs to be positioned with leading bit at ~51
          //
          // Strategy: Position man_c similarly - shift LEFT to bit 51, then apply exp_diff

          if (exp_prod >= exp_c) begin
            exp_result = exp_prod;
            exp_diff = exp_prod - exp_c;

            // Product has larger exponent, so it sets the reference position
            // man_c needs to be positioned at same reference, then shifted right by exp_diff
            if (exp_diff > (2*MAN_WIDTH + 6))
              aligned_c = {1'b0, {(2*MAN_WIDTH+5){1'b0}}, 1'b1};  // Sticky bit only
            else begin
              // For FLEN=64:
              // - Double-precision: man_c[52] is leading bit, but product leading bit is at 55 after positioning
              //   So we need to shift man_c LEFT by 3, then RIGHT by exp_diff: net = shift left by (3-exp_diff)
              //   Actually simpler: position man_c to match product's position, then shift by exp_diff
              //   Product positioned with leading bit at [~55], so man_c needs same positioning
              // - Single-precision: man_c[52] has padding, product at 51 → shift by exp_diff+1
              if (FLEN == 64) begin
                if (fmt_latched)
                  aligned_c = ({man_c, 3'b0} >> exp_diff);  // Double-precision: shift left by 3 to align, then right by exp_diff
                else
                  aligned_c = (man_c >> (exp_diff + 1));  // Single-precision: product 1 bit lower
              end else
                aligned_c = ({man_c[MAN_WIDTH:0], 28'b0} >> exp_diff);  // FLEN=32 case
            end
          end else begin
            exp_result = exp_c;
            exp_diff = exp_c - exp_prod;

            // Addend has larger exponent
            // Shift product right by exp_diff relative to addend position
            if (exp_diff > (2*MAN_WIDTH + 6))
              product = {1'b0, {(2*MAN_WIDTH+3){1'b0}}, 1'b1};  // Sticky bit only
            else
              product = product >> exp_diff;

            // Position man_c to match product positioning
            if (FLEN == 64) begin
              if (fmt_latched)
                aligned_c = {man_c, 3'b0};  // Double-precision: shift left by 3 to match product position at [55]
              else
                aligned_c = man_c;  // Single-precision: already aligned
            end else
              aligned_c = {man_c, 28'b0};
          end

          // Perform addition/subtraction
          // Position product to have leading bit at correct sum position
          //
          // Product is (MAN_WIDTH+1) × (MAN_WIDTH+1) = 106 bits for FLEN=64
          // Leading bit is at position 104 for products >= 2.0, or 103 for products < 2.0
          //
          // For double-precision: Need leading bit at [52] to extract 52-bit mantissa from [51:0]
          // For single-precision with FLEN=64: Need leading bit at [51] to extract 23-bit mantissa from [50:28]
          //
          // Note: For single-precision with FLEN=64, mantissas have 29-bit padding,
          // but the multiplication result still has leading bit at position 104-105.

          if (FLEN == 64) begin
            if (fmt_latched) begin
              // Double-precision: Shift product right by 49 to position leading bit at [55]
              // This leaves room for 52-bit mantissa at [54:3] and GRS bits at [2:0]
              product_positioned = product >> 49;
            end else begin
              // Single-precision: Shift product right by 53 to position leading bit at [51]
              product_positioned = product >> 53;
            end
          end else begin
            // FLEN=32: product is 48 bits (24×24), leading bit at position 46
            // Shift LEFT by 5 to position at [51]
            product_positioned = product << 5;
          end

          if (sign_prod == sign_c) begin
            // Same sign: add magnitudes
            sum <= product_positioned + aligned_c;
            sign_result <= sign_prod;
          end else begin
            // Different signs: subtract magnitudes
            if (product_positioned >= aligned_c) begin
              sum <= product_positioned - aligned_c;
              sign_result <= sign_prod;
            end else begin
              sum <= aligned_c - product_positioned;
              sign_result <= sign_c;
            end
          end
          state <= NORMALIZE;
          `ifdef DEBUG_FPU
          $display("[FMA_ADD] product=%h aligned_c=%h exp_result=%d exp_diff=%d",
                   product, aligned_c, exp_result, exp_diff);
          $display("[FMA_ADD] product_positioned=%h sum_will_be=%h",
                   product_positioned, (sign_prod == sign_c) ? (product_positioned + aligned_c) :
                   (product_positioned >= aligned_c) ? (product_positioned - aligned_c) : (aligned_c - product_positioned));
          $display("[FMA_ADD_DEBUG] man_c=%h shift_in=%h shift_amount=%d",
                   man_c, {man_c[MAN_WIDTH:0], 29'b0}, exp_diff);
          `endif
        end

        // ============================================================
        // NORMALIZE: Shift result to normalized form
        // ============================================================
        NORMALIZE: begin
          // Check for zero result
          if (sum == 0) begin
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_result, 31'h0};
            else if (FLEN == 64 && fmt_latched)
              result <= {sign_result, 63'h0};
            else
              result <= {sign_result, 31'h0};
            state <= DONE;
          end
          // Check for overflow (carry out beyond normalized position)
          // For double-precision: normalized at 52, overflow at 53
          // For single-precision: normalized at 51, overflow at 52
          else if (FLEN == 64 && fmt_latched && sum[56]) begin
            // Double-precision overflow
            sum <= sum >> 1;
            exp_result <= exp_result + 1;
            // After shift, leading bit at [55], mantissa at [54:3], GRS at [2:0]
            guard <= sum[2];
            round <= sum[1];
            sticky <= sum[0];
          end else if (FLEN == 64 && !fmt_latched && sum[52]) begin
            // Single-precision overflow
            sum <= sum >> 1;
            exp_result <= exp_result + 1;
            guard <= sum[29];  // After shift, guard at bit 29 for single-precision
            round <= sum[28];
            sticky <= |sum[27:0];
          end
          // For FLEN=32: Check overflow at old position
          else if (FLEN == 32 && sum[(2*MAN_WIDTH+6)]) begin
            sum <= sum >> 1;
            exp_result <= exp_result + 1;
            guard <= sum[0];
            round <= 1'b0;
            sticky <= 1'b0;
          end
          // Check if leading 1 is at normalized position
          // Double-precision: leading bit at 52
          // Single-precision: leading bit at 51
          else if (FLEN == 64 && fmt_latched && sum[55]) begin
            // Double-precision already normalized - leading 1 at bit 55
            // Mantissa is at [54:3], GRS at [2:0]
            guard <= sum[2];
            round <= sum[1];
            sticky <= sum[0];
            state <= ROUND;
          end else if (FLEN == 64 && !fmt_latched && sum[51]) begin
            // Single-precision already normalized - leading 1 at bit 51
            // Sum[50:28] contains the 23-bit mantissa
            // GRS at bits [27:25]
            guard <= sum[27];
            round <= sum[26];
            sticky <= |sum[25:0];
            state <= ROUND;
          end
          // For FLEN=32: Check normalized position at bit (2*MAN_WIDTH+5)
          else if (FLEN == 32 && sum[(2*MAN_WIDTH+5)]) begin
            // FLEN=32 normalized case
            guard <= sum[MAN_WIDTH+4];
            round <= sum[MAN_WIDTH+3];
            sticky <= |sum[MAN_WIDTH+2:0];
          end
          // Leading 1 is below normalized position - need to shift left (can happen after subtraction)
          else begin
            sum <= sum << 1;
            exp_result <= exp_result - 1;
            // Stay in NORMALIZE state to continue shifting if needed
          end

          // Check for overflow
          if (exp_result >= MAX_EXP) begin
            flag_of <= 1'b1;
            flag_nx <= 1'b1;
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_result, 8'hFF, 23'h0};
            else if (FLEN == 64 && fmt_latched)
              result <= {sign_result, 11'h7FF, 52'h0};
            else
              result <= {sign_result, 8'hFF, 23'h0};
            state <= DONE;
          end
        end

        // ============================================================
        // ROUND: Apply rounding mode (SINGLE ROUNDING - key advantage!)
        // ============================================================
        ROUND: begin
          // Store round_up decision for debug (registered version)
          round_up <= round_up_comb;

          `ifdef DEBUG_FPU
          if (FLEN == 64 && fmt_latched)
            $display("[FMA_ROUND] sign=%b exp_result=%d sum=%h mantissa_extract=%h (bits [54:3])",
                     sign_result, exp_result, sum, sum[54:3]);
          else if (FLEN == 64 && !fmt_latched)
            $display("[FMA_ROUND] sign=%b exp_result=%d sum=%h mantissa_extract=%h (bits [50:28])",
                     sign_result, exp_result, sum, sum[50:28]);
          else
            $display("[FMA_ROUND] sign=%b exp_result=%d sum=%h mantissa_extract=%h (bits [25:3])",
                     sign_result, exp_result, sum, sum[25:3]);
          $display("[FMA_ROUND_BITS] guard=%b round=%b sticky=%b rounding_mode=%b round_up_comb=%b",
                   guard, round, sticky, rounding_mode, round_up_comb);
          `endif

          // Apply rounding using combinational value
          // Extract mantissa bits based on format
          // Double-precision: leading bit at 52, mantissa at [51:0]
          // Single-precision: leading bit at 51, mantissa is at sum[50:28]
          if (FLEN == 64 && !fmt_latched) begin
            // Single-precision in 64-bit register (NaN-boxed)
            // Extract 23-bit mantissa from sum[50:28]
            // Leading bit is implicit 1 at position 51
            if (round_up_comb) begin
              result <= {32'hFFFFFFFF, sign_result, exp_result[7:0],
                         sum[50:28] + 1'b1};
            end else begin
              result <= {32'hFFFFFFFF, sign_result, exp_result[7:0],
                         sum[50:28]};
            end
          end else if (FLEN == 64 && fmt_latched) begin
            // Double-precision in 64-bit register
            // Extract 52-bit mantissa from sum[54:3]
            // Leading bit is implicit 1 at position 55
            if (round_up_comb) begin
              result <= {sign_result, exp_result[10:0], sum[54:3] + 1'b1};
            end else begin
              result <= {sign_result, exp_result[10:0], sum[54:3]};
            end
          end else begin
            // FLEN=32: single-precision in 32-bit register
            // Extract 23-bit mantissa
            if (round_up_comb) begin
              result <= {sign_result, exp_result[7:0],
                         sum[25:3] + 1'b1};
            end else begin
              result <= {sign_result, exp_result[7:0],
                         sum[25:3]};
            end
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
