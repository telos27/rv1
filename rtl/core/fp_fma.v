// Floating-Point Fused Multiply-Add Unit
// Implements FMADD.S/D, FMSUB.S/D, FNMSUB.S/D, FNMADD.S/D instructions
// IEEE 754-2008 compliant with single rounding step (key advantage over separate ops)
// Multi-cycle execution: 4-5 cycles

module fp_fma #(
  parameter FLEN = 32  // 32 for single-precision, 64 for double-precision
) (
  input  wire              clk,
  input  wire              reset_n,

  // Control
  input  wire              start,          // Start operation
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

  // Computation
  reg [EXP_WIDTH+1:0] exp_prod;               // Product exponent
  reg [(2*MAN_WIDTH+3):0] product;            // Product mantissa (double width)
  reg [(2*MAN_WIDTH+5):0] aligned_c;          // Aligned addend
  reg [(2*MAN_WIDTH+6):0] sum;                // Sum result
  reg [EXP_WIDTH+1:0] exp_diff;               // Exponent difference
  reg [EXP_WIDTH-1:0] exp_result;

  // Rounding
  reg guard, round, sticky;
  reg round_up;

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
          // Operand A (rs1)
          sign_a <= operand_a[FLEN-1];
          exp_a <= operand_a[FLEN-2:MAN_WIDTH];
          man_a <= (operand_a[FLEN-2:MAN_WIDTH] == 0) ?
                   {1'b0, operand_a[MAN_WIDTH-1:0]} :
                   {1'b1, operand_a[MAN_WIDTH-1:0]};
          is_nan_a <= (operand_a[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_a[MAN_WIDTH-1:0] != 0);
          is_inf_a <= (operand_a[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_a[MAN_WIDTH-1:0] == 0);
          is_zero_a <= (operand_a[FLEN-2:0] == 0);

          // Operand B (rs2)
          sign_b <= operand_b[FLEN-1];
          exp_b <= operand_b[FLEN-2:MAN_WIDTH];
          man_b <= (operand_b[FLEN-2:MAN_WIDTH] == 0) ?
                   {1'b0, operand_b[MAN_WIDTH-1:0]} :
                   {1'b1, operand_b[MAN_WIDTH-1:0]};
          is_nan_b <= (operand_b[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_b[MAN_WIDTH-1:0] != 0);
          is_inf_b <= (operand_b[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_b[MAN_WIDTH-1:0] == 0);
          is_zero_b <= (operand_b[FLEN-2:0] == 0);

          // Operand C (rs3)
          sign_c <= operand_c[FLEN-1] ^ subtract_addend;  // Flip sign if subtract
          exp_c <= operand_c[FLEN-2:MAN_WIDTH];
          man_c <= (operand_c[FLEN-2:MAN_WIDTH] == 0) ?
                   {1'b0, operand_c[MAN_WIDTH-1:0]} :
                   {1'b1, operand_c[MAN_WIDTH-1:0]};
          is_nan_c <= (operand_c[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_c[MAN_WIDTH-1:0] != 0);
          is_inf_c <= (operand_c[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_c[MAN_WIDTH-1:0] == 0);
          is_zero_c <= (operand_c[FLEN-2:0] == 0);
        end

        // ============================================================
        // MULTIPLY: Compute product (rs1 * rs2)
        // ============================================================
        MULTIPLY: begin
          // Handle special cases
          if (is_nan_a || is_nan_b || is_nan_c) begin
            // NaN propagation
            result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
            flag_nv <= 1'b1;
            state <= DONE;
          end else if ((is_inf_a && is_zero_b) || (is_zero_a && is_inf_b)) begin
            // 0 × ∞: Invalid
            result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
            flag_nv <= 1'b1;
            state <= DONE;
          end else if ((is_inf_a || is_inf_b) && is_inf_c &&
                       ((sign_a ^ sign_b ^ negate_product) != sign_c)) begin
            // ∞ + (-∞): Invalid
            result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
            flag_nv <= 1'b1;
            state <= DONE;
          end else if (is_inf_a || is_inf_b || is_inf_c) begin
            // Result is ±∞
            if (is_inf_c)
              sign_result <= sign_c;
            else
              sign_result <= sign_a ^ sign_b ^ negate_product;
            result <= {sign_result, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
            state <= DONE;
          end else if ((is_zero_a || is_zero_b) && is_zero_c) begin
            // 0 + 0
            sign_result <= (sign_a ^ sign_b ^ negate_product) && sign_c;
            result <= {sign_result, {FLEN-1{1'b0}}};
            state <= DONE;
          end else if (is_zero_a || is_zero_b) begin
            // Product is 0, return addend
            result <= {sign_c, exp_c, man_c[MAN_WIDTH-1:0]};
            state <= DONE;
          end else if (is_zero_c) begin
            // Addend is 0, return product
            sign_prod <= sign_a ^ sign_b ^ negate_product;
            exp_prod <= exp_a + exp_b - BIAS;
            // Store 48-bit product directly - we'll position it during ADD
            product <= man_a * man_b;
          end else begin
            // Normal multiplication
            sign_prod <= sign_a ^ sign_b ^ negate_product;
            // Store 48-bit product directly - we'll position it during ADD
            product <= man_a * man_b;
            exp_prod <= exp_a + exp_b - BIAS;
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
          if (exp_prod >= exp_c) begin
            exp_result = exp_prod;
            exp_diff = exp_prod - exp_c;

            // Product has larger exponent, so it sets the reference position
            // Position product: 48 bits with leading bit at sum[51]
            // Position addend: 24 bits shifted right by exp_diff from sum[51]
            if (exp_diff > (2*MAN_WIDTH + 6))
              aligned_c = {1'b0, {(2*MAN_WIDTH+5){1'b0}}, 1'b1};  // Sticky bit only
            else
              // Position man_c with leading bit at sum[51], then shift right by exp_diff
              // man_c needs 51-23=28 bits of padding to reach bit [51]
              aligned_c = ({man_c[MAN_WIDTH:0], 28'b0} >> exp_diff);
          end else begin
            exp_result = exp_c;
            exp_diff = exp_c - exp_prod;

            // Addend has larger exponent
            // Shift product right by exp_diff relative to addend position
            if (exp_diff > (2*MAN_WIDTH + 6))
              product = {1'b0, {(2*MAN_WIDTH+3){1'b0}}, 1'b1};  // Sticky bit only
            else
              product = product >> exp_diff;

            // Position man_c with leading bit at sum[51]: need 28 bits of padding
            aligned_c = {man_c, 28'b0};
          end

          // Perform addition/subtraction
          // Position product to have leading bit at sum[51]: need (51-46)=5 bits of shift
          // (product has 48 bits in Q2.46 format, leading 1 at bit [46], we want it at [51])
          if (sign_prod == sign_c) begin
            // Same sign: add magnitudes
            sum <= (product << 5) + aligned_c;
            sign_result <= sign_prod;
          end else begin
            // Different signs: subtract magnitudes
            if ((product << 5) >= aligned_c) begin
              sum <= (product << 5) - aligned_c;
              sign_result <= sign_prod;
            end else begin
              sum <= aligned_c - (product << 5);
              sign_result <= sign_c;
            end
          end
          state <= NORMALIZE;
          `ifdef DEBUG_FPU
          $display("[FMA_ADD] product=%h aligned_c=%h exp_result=%d exp_diff=%d",
                   product, aligned_c, exp_result, exp_diff);
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
            result <= {sign_result, {FLEN-1{1'b0}}};
            state <= DONE;
          end
          // Check for overflow (carry out)
          else if (sum[(2*MAN_WIDTH+6)]) begin
            sum <= sum >> 1;
            exp_result <= exp_result + 1;
            guard <= sum[0];
            round <= 1'b0;
            sticky <= 1'b0;
          end
          // Already normalized (assume leading 1 is in correct position)
          else begin
            guard <= sum[MAN_WIDTH+2];
            round <= sum[MAN_WIDTH+1];
            sticky <= |sum[MAN_WIDTH:0];
          end

          // Check for overflow
          if (exp_result >= MAX_EXP) begin
            flag_of <= 1'b1;
            flag_nx <= 1'b1;
            result <= {sign_result, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
            state <= DONE;
          end
        end

        // ============================================================
        // ROUND: Apply rounding mode (SINGLE ROUNDING - key advantage!)
        // ============================================================
        ROUND: begin
          // Determine if we should round up
          case (rounding_mode)
            3'b000: begin  // RNE: Round to nearest, ties to even
              round_up <= guard && (round || sticky || sum[MAN_WIDTH+3]);
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
            default: begin
              round_up <= 1'b0;
            end
          endcase

          `ifdef DEBUG_FPU
          $display("[FMA_ROUND] sign=%b exp_result=%d sum=%h mantissa_extract=%h (bits [50:28])",
                   sign_result, exp_result, sum, sum[(2*MAN_WIDTH+4):(MAN_WIDTH+5)]);
          `endif

          // Apply rounding
          // Extract mantissa from sum[50:28] (23 bits), assuming sum[51] is the implicit 1
          if (round_up) begin
            result <= {sign_result, exp_result[EXP_WIDTH-1:0],
                       sum[(2*MAN_WIDTH+4):(MAN_WIDTH+5)] + 1'b1};
          end else begin
            result <= {sign_result, exp_result[EXP_WIDTH-1:0],
                       sum[(2*MAN_WIDTH+4):(MAN_WIDTH+5)]};
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
