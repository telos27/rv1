// Floating-Point Square Root Unit
// Implements FSQRT.S/D instruction
// IEEE 754-2008 compliant with digit recurrence algorithm
// Multi-cycle execution: 16-32 cycles (depending on FLEN)

module fp_sqrt #(
  parameter FLEN = 32  // 32 for single-precision, 64 for double-precision
) (
  input  wire              clk,
  input  wire              reset_n,

  // Control
  input  wire              start,          // Start operation
  input  wire [2:0]        rounding_mode,  // IEEE 754 rounding mode
  output reg               busy,           // Operation in progress
  output reg               done,           // Operation complete (1 cycle pulse)

  // Operand
  input  wire [FLEN-1:0]   operand,

  // Result
  output reg  [FLEN-1:0]   result,

  // Exception flags
  output reg               flag_nv,        // Invalid operation (negative input)
  output reg               flag_nx         // Inexact
);

  // IEEE 754 format parameters
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;
  localparam BIAS = (FLEN == 32) ? 127 : 1023;
  localparam MAX_EXP = (FLEN == 32) ? 255 : 2047;
  localparam SQRT_CYCLES = (MAN_WIDTH + 4);  // Iterations needed: need MAN_WIDTH+4 bits of root (1 root bit per iteration)

  // State machine
  localparam IDLE      = 3'b000;
  localparam UNPACK    = 3'b001;
  localparam COMPUTE   = 3'b010;
  localparam NORMALIZE = 3'b011;
  localparam ROUND     = 3'b100;
  localparam DONE      = 3'b101;

  reg [2:0] state, next_state;

  // Unpacked operand
  reg sign;
  reg [EXP_WIDTH-1:0] exp;
  reg [MAN_WIDTH:0] mantissa;  // +1 bit for implicit leading 1

  // Special value flags
  reg is_nan, is_inf, is_zero, is_negative;

  // Square root computation (digit recurrence)
  reg [MAN_WIDTH+3:0] root;          // Square root result (27 bits for SP)
  reg [MAN_WIDTH+5:0] remainder;     // Current remainder (A register in algorithm) - needs root_width + 2 bits
  wire [MAN_WIDTH+5:0] ac;           // Accumulator for next 2 bits from radicand (combinational)
  wire [MAN_WIDTH+5:0] test_val;     // Test value: ac - (root<<2 | 1) (combinational)
  wire test_positive;                // True if test_val >= 0
  reg [5:0] sqrt_counter;            // Iteration counter
  reg [EXP_WIDTH-1:0] exp_result;
  reg exp_is_odd;                    // True if exponent is odd
  reg [(MAN_WIDTH+4)*2-1:0] radicand_shift;  // Full radicand for bit extraction

  // Combinational logic for sqrt iteration (2-bits-per-cycle, radix-4)
  // Following Project F algorithm: process 2 bits per iteration
  assign ac = (remainder << 2) | radicand_shift[(MAN_WIDTH+4)*2-1:(MAN_WIDTH+4)*2-2];  // Shift in 2 bits
  assign test_val = ac - {root, 2'b01};  // ac - (root << 2 | 1)
  assign test_positive = (test_val[MAN_WIDTH+5] == 1'b0);  // Check sign bit

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
      UNPACK:    next_state = COMPUTE;
      COMPUTE:   next_state = (sqrt_counter == 0) ? NORMALIZE : COMPUTE;
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

  `ifdef DEBUG_FPU_DIVIDER
  always @(posedge clk) begin
    // Always print when start is triggered
    if (start) begin
      $display("[SQRT_START] t=%0t operand=0x%h", $time, operand);
    end

    // Print state transitions
    if (state != next_state) begin
      $display("[SQRT_TRANSITION] t=%0t state=%d->%d", $time, state, next_state);
    end

    // Print UNPACK details
    if (state == UNPACK) begin
      $display("[SQRT_UNPACK] exp=0x%h mant=0x%h special: nan=%b inf=%b zero=%b neg=%b",
               operand[FLEN-2:MAN_WIDTH],
               (operand[FLEN-2:MAN_WIDTH] == 0) ? {1'b0, operand[MAN_WIDTH-1:0]} : {1'b1, operand[MAN_WIDTH-1:0]},
               (operand[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) && (operand[MAN_WIDTH-1:0] != 0),
               (operand[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) && (operand[MAN_WIDTH-1:0] == 0),
               operand[FLEN-2:0] == 0,
               operand[FLEN-1] && !(operand[FLEN-2:0] == 0));
    end

    // Print COMPUTE initialization
    if (state == COMPUTE && sqrt_counter == SQRT_CYCLES) begin
      $display("[SQRT_INIT] exp=%d exp_odd=%b exp_result=%d radicand_shift=0x%h",
               exp, exp[0],
               exp[0] ? (exp - BIAS) / 2 + BIAS : (exp - BIAS) / 2 + BIAS,
               exp[0] ? {mantissa, 4'b0000, {(MAN_WIDTH+3){1'b0}}} << 1 : {mantissa, 4'b0000, {(MAN_WIDTH+3){1'b0}}});
    end

    // Print ALL iterations to debug
    if (state == COMPUTE && sqrt_counter != SQRT_CYCLES) begin
      $display("[SQRT_ITER] counter=%0d root=0x%h rem=0x%h radicand=0x%h ac=0x%h test_val=0x%h accept=%b",
               sqrt_counter, root, remainder, radicand_shift, ac, test_val, test_positive);
    end

    // Print last few iterations before normalize
    if (state == COMPUTE && sqrt_counter <= 3) begin
      $display("[SQRT_LATE] counter=%0d root=0x%h rem=0x%h",
               sqrt_counter, root, remainder);
    end

    // Print normalization
    if (state == NORMALIZE) begin
      $display("[SQRT_NORM] root=0x%h exp_result=%d GRS=%b%b%b",
               root, exp_result, root[2], root[1], root[0] || (remainder != 0));
    end

    // Print final result
    if (state == DONE || next_state == DONE) begin
      $display("[SQRT_DONE] result=0x%h flags: nv=%b nx=%b", result, flag_nv, flag_nx);
    end
  end
  `endif

  // Main datapath
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      result <= {FLEN{1'b0}};
      flag_nv <= 1'b0;
      flag_nx <= 1'b0;
      sqrt_counter <= 6'd0;
      // Initialize working registers to prevent X propagation
      root <= {(MAN_WIDTH+4){1'b0}};
      remainder <= {(MAN_WIDTH+6){1'b0}};
      radicand_shift <= {((MAN_WIDTH+4)*2){1'b0}};
      exp_result <= {EXP_WIDTH{1'b0}};
      exp_is_odd <= 1'b0;
      sign <= 1'b0;
      exp <= {EXP_WIDTH{1'b0}};
      mantissa <= {(MAN_WIDTH+1){1'b0}};
      is_nan <= 1'b0;
      is_inf <= 1'b0;
      is_zero <= 1'b0;
      is_negative <= 1'b0;
    end else begin
      case (state)

        // ============================================================
        // UNPACK: Extract sign, exponent, mantissa
        // ============================================================
        UNPACK: begin
          // Clear flags for new operation
          flag_nv <= 1'b0;
          flag_nx <= 1'b0;

          // Extract sign
          sign <= operand[FLEN-1];

          // Extract exponent
          exp <= operand[FLEN-2:MAN_WIDTH];

          // Extract mantissa with implicit leading 1 (if normalized)
          mantissa <= (operand[FLEN-2:MAN_WIDTH] == 0) ?
                      {1'b0, operand[MAN_WIDTH-1:0]} :
                      {1'b1, operand[MAN_WIDTH-1:0]};

          // Detect special values
          is_nan <= (operand[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                    (operand[MAN_WIDTH-1:0] != 0);
          is_inf <= (operand[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                    (operand[MAN_WIDTH-1:0] == 0);
          is_zero <= (operand[FLEN-2:0] == 0);
          is_negative <= operand[FLEN-1] && !((operand[FLEN-2:0] == 0));  // -0 is OK

          // Initialize counter for COMPUTE state
          // Need SQRT_CYCLES iterations to get all mantissa bits + GRS
          sqrt_counter <= SQRT_CYCLES;  // Start at SQRT_CYCLES for first iteration check
        end

        // ============================================================
        // COMPUTE: Iterative square root computation
        // ============================================================
        COMPUTE: begin
          if (sqrt_counter == SQRT_CYCLES) begin
            // First iteration: special case handling and initialization
            if (is_nan) begin
              // sqrt(NaN) = NaN
              result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
              state <= DONE;
            end else if (is_negative) begin
              // sqrt(negative) = NaN, set invalid flag
              result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
              flag_nv <= 1'b1;
              state <= DONE;
            end else if (is_inf) begin
              // sqrt(+∞) = +∞
              result <= {1'b0, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
              state <= DONE;
            end else if (is_zero) begin
              // sqrt(±0) = ±0 (preserve sign)
              result <= operand;
              state <= DONE;
            end else begin
              // Initialize square root computation using digit-by-digit algorithm
              // Result exponent: (exp - BIAS) / 2 + BIAS
              exp_is_odd <= exp[0];  // Check if exponent is odd

              if (exp[0]) begin
                // Odd exponent: adjust by shifting mantissa left by 1
                exp_result <= (exp - BIAS) / 2 + BIAS;
                radicand_shift <= {mantissa, 4'b0000, {(MAN_WIDTH+3){1'b0}}} << 1;
              end else begin
                // Even exponent: no adjustment needed
                exp_result <= (exp - BIAS) / 2 + BIAS;
                radicand_shift <= {mantissa, 4'b0000, {(MAN_WIDTH+3){1'b0}}};
              end

              // Initialize registers for digit-by-digit algorithm
              root <= {(MAN_WIDTH+4){1'b0}};      // Q = 0
              remainder <= {(MAN_WIDTH+6){1'b0}}; // A = 0

              // Start iteration (process 2 bits per cycle, radix-4)
              // Need SQRT_CYCLES iterations to compute all bits including GRS
              // Decrement counter to start iterations
              sqrt_counter <= SQRT_CYCLES - 1;
            end
          end else begin
            // Digit-by-digit sqrt iteration (2 bits per cycle, radix-4)
            // Following Project F algorithm: process 2 bits of radicand per iteration
            // ac, test_val, and test_positive are computed combinationally

            // Shift radicand to prepare next 2 bits
            radicand_shift <= radicand_shift << 2;

            if (test_positive) begin
              // test_val >= 0: accept the bit (set LSB of root to 1)
              remainder <= test_val;
              root <= (root << 1) | 1'b1;  // Shift by 1, set LSB to 1
            end else begin
              // test_val < 0: reject the bit (set LSB of root to 0)
              remainder <= ac;
              root <= root << 1;  // Shift by 1, LSB stays 0
            end

            // Decrement counter
            sqrt_counter <= sqrt_counter - 1;
          end
        end

        // ============================================================
        // NORMALIZE: Result should already be normalized
        // ============================================================
        NORMALIZE: begin
          // Extract GRS bits from root
          guard <= root[2];
          round <= root[1];
          sticky <= root[0] || (remainder != 0);  // Any remaining bits in remainder
        end

        // ============================================================
        // ROUND: Apply rounding mode
        // ============================================================
        ROUND: begin
          // Determine if we should round up (computed combinationally)
          // Must be computed here to use in same cycle
          case (rounding_mode)
            3'b000: begin  // RNE: Round to nearest, ties to even
              round_up = guard && (round || sticky || root[3]);
            end
            3'b001: begin  // RTZ: Round toward zero
              round_up = 1'b0;
            end
            3'b010: begin  // RDN: Round down (toward -∞)
              round_up = 1'b0;  // sqrt is always positive
            end
            3'b011: begin  // RUP: Round up (toward +∞)
              round_up = guard || round || sticky;
            end
            3'b100: begin  // RMM: Round to nearest, ties to max magnitude
              round_up = guard;
            end
            default: begin
              round_up = 1'b0;
            end
          endcase

          // Apply rounding (result is always positive)
          // Extract MAN_WIDTH bits (23 for SP, 52 for DP) - NOT including implicit leading 1
          if (round_up) begin
            result <= {1'b0, exp_result, root[MAN_WIDTH+2:3] + 1'b1};
          end else begin
            result <= {1'b0, exp_result, root[MAN_WIDTH+2:3]};
          end

          // Set inexact flag
          flag_nx <= guard || round || sticky;
        end

        // ============================================================
        // DONE: Hold result for 1 cycle
        // ============================================================
        DONE: begin
          // Reset counter for next operation (will be set to SQRT_CYCLES-1 in UNPACK)
          sqrt_counter <= 6'd0;
        end

      endcase
    end
  end

endmodule
