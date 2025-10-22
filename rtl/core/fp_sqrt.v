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
  localparam SQRT_CYCLES = (MAN_WIDTH / 2) + 4;  // Iterations needed (2 bits per cycle)

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
  reg [MAN_WIDTH+3:0] root;          // Square root result
  reg [MAN_WIDTH+4:0] radicand;      // Current radicand (remaining value)
  reg [MAN_WIDTH+4:0] test_value;    // Test value for subtraction
  reg [5:0] sqrt_counter;            // Iteration counter
  reg [EXP_WIDTH-1:0] exp_result;
  reg exp_is_odd;                    // True if exponent is odd

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

    // Print when busy changes
    if (busy) begin
      $display("[SQRT_BUSY] t=%0t state=%d counter=%0d", $time, state, sqrt_counter);
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
      radicand <= {(MAN_WIDTH+5){1'b0}};
      test_value <= {(MAN_WIDTH+5){1'b0}};
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
          sqrt_counter <= SQRT_CYCLES;
        end

        // ============================================================
        // COMPUTE: Iterative square root computation
        // ============================================================
        COMPUTE: begin
          if (sqrt_counter == SQRT_CYCLES) begin
            // Special case handling
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
              // Initialize square root computation
              // Result exponent: (exp - BIAS) / 2 + BIAS
              exp_is_odd <= exp[0];  // Check if exponent is odd

              if (exp[0]) begin
                // Odd exponent: adjust by shifting mantissa
                exp_result <= (exp - BIAS) / 2 + BIAS;
                radicand <= {mantissa, 4'b0000} << 1;  // Shift mantissa left by 1
              end else begin
                // Even exponent
                exp_result <= (exp - BIAS) / 2 + BIAS;
                radicand <= {mantissa, 4'b0000};
              end

              // Initialize root
              root <= {(MAN_WIDTH+4){1'b0}};

              // Start iteration
              sqrt_counter <= SQRT_CYCLES - 1;
            end
          end else begin
            // Digit recurrence iteration (non-restoring algorithm)
            // Test if (root << 1 + 1)^2 <= radicand
            test_value <= ((root << 1) + 1'b1) * ((root << 1) + 1'b1);

            if (test_value <= radicand) begin
              // Accept the bit
              root <= (root << 1) | 1'b1;
              radicand <= radicand - test_value;
            end else begin
              // Reject the bit
              root <= root << 1;
            end

            // Decrement counter
            sqrt_counter <= sqrt_counter - 1;
          end
        end

        // ============================================================
        // NORMALIZE: Result should already be normalized
        // ============================================================
        NORMALIZE: begin
          // Extract GRS bits
          guard <= root[2];
          round <= root[1];
          sticky <= root[0] || (radicand != 0);
        end

        // ============================================================
        // ROUND: Apply rounding mode
        // ============================================================
        ROUND: begin
          // Determine if we should round up
          case (rounding_mode)
            3'b000: begin  // RNE: Round to nearest, ties to even
              round_up <= guard && (round || sticky || root[3]);
            end
            3'b001: begin  // RTZ: Round toward zero
              round_up <= 1'b0;
            end
            3'b010: begin  // RDN: Round down (toward -∞)
              round_up <= 1'b0;  // sqrt is always positive
            end
            3'b011: begin  // RUP: Round up (toward +∞)
              round_up <= guard || round || sticky;
            end
            3'b100: begin  // RMM: Round to nearest, ties to max magnitude
              round_up <= guard;
            end
            default: begin
              round_up <= 1'b0;
            end
          endcase

          // Apply rounding (result is always positive)
          if (round_up) begin
            result <= {1'b0, exp_result, root[MAN_WIDTH+3:3] + 1'b1};
          end else begin
            result <= {1'b0, exp_result, root[MAN_WIDTH+3:3]};
          end

          // Set inexact flag
          flag_nx <= guard || round || sticky;
        end

        // ============================================================
        // DONE: Hold result for 1 cycle
        // ============================================================
        DONE: begin
          sqrt_counter <= SQRT_CYCLES;  // Reset for next operation
        end

      endcase
    end
  end

endmodule
