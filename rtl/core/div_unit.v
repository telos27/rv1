// div_unit.v - Divider for M Extension (PicoRV32-inspired)
// Implements DIV, DIVU, REM, REMU instructions
// Based on PicoRV32's proven division algorithm
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

  // Sign handling
  wire is_signed_op;
  assign is_signed_op = (div_op == DIV) || (div_op == REM);

  // Extract signs
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

  // For word operations, mask to lower 32 bits
  // For signed operations (DIV/REM), sign-extend; for unsigned (DIVU/REMU), zero-extend
  wire [XLEN-1:0] masked_dividend, masked_divisor;
  generate
    if (XLEN == 64) begin : gen_mask_64
      assign masked_dividend = is_word_op ?
                              (is_signed_op ? {{32{dividend[31]}}, dividend[31:0]} : {{32{1'b0}}, dividend[31:0]}) :
                              dividend;
      assign masked_divisor  = is_word_op ?
                              (is_signed_op ? {{32{divisor[31]}}, divisor[31:0]} : {{32{1'b0}}, divisor[31:0]}) :
                              divisor;
    end else begin : gen_mask_32
      assign masked_dividend = dividend;
      assign masked_divisor  = divisor;
    end
  endgenerate

  wire [XLEN-1:0] abs_dividend = negate_dividend ? (~masked_dividend + 1'b1) : masked_dividend;
  wire [XLEN-1:0] abs_divisor  = negate_divisor  ? (~masked_divisor + 1'b1)  : masked_divisor;

  // Division registers (PicoRV32-style algorithm)
  reg [XLEN-1:0]     dividend_reg;   // Holds remainder during computation
  reg [2*XLEN-2:0]   divisor_reg;    // Shifted divisor (63 bits for RV32, like PicoRV32)
  reg [XLEN-1:0]     quotient;
  reg [XLEN-1:0]     quotient_msk;   // Mask for current quotient bit

  // Control registers
  reg [1:0] op_reg;
  reg       word_op_reg;
  reg       outsign;               // Output sign for signed operations
  reg       running;

  // Temporary result extraction register
  reg [XLEN-1:0] extracted_result;

  // Busy signal: high when running
  assign busy = running;

  // Datapath (PicoRV32-inspired algorithm)
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      dividend_reg  <= {XLEN{1'b0}};
      divisor_reg   <= {(2*XLEN-1){1'b0}};
      quotient      <= {XLEN{1'b0}};
      quotient_msk  <= {XLEN{1'b0}};
      ready         <= 1'b0;
      result        <= {XLEN{1'b0}};
      op_reg        <= 2'b00;
      word_op_reg   <= 1'b0;
      outsign       <= 1'b0;
      running       <= 1'b0;
    end else begin
      // Always clear ready by default
      ready <= 1'b0;

      // Start new division
      if (start && !running) begin
        running      <= 1'b1;
        op_reg       <= div_op;
        word_op_reg  <= is_word_op;

        // Convert to absolute values for computation (PicoRV32 style)
        dividend_reg <= abs_dividend;
        divisor_reg  <= abs_divisor << (XLEN - 1);  // Shift divisor to MSB position (63-bit register)
        quotient     <= {XLEN{1'b0}};
        quotient_msk <= {1'b1, {(XLEN-1){1'b0}}};  // Start with MSB set

        // Calculate output sign (for DIV: signs differ AND divisor != 0, for REM: dividend sign)
        if (div_op == DIV)
          outsign <= (sign_dividend != sign_divisor) && (divisor != {XLEN{1'b0}});
        else if (div_op == REM)
          outsign <= sign_dividend;
        else
          outsign <= 1'b0;  // Unsigned operations

        `ifdef DEBUG_DIV
        $display("[DIV] Start: op=%b dividend=%h (%h) divisor=%h (%h) outsign=%b",
                 div_op, dividend, abs_dividend, divisor, abs_divisor,
                 (div_op == DIV) ? ((sign_dividend != sign_divisor) && (divisor != {XLEN{1'b0}})) :
                 (div_op == REM) ? sign_dividend : 1'b0);
        `endif
      end
      // Division computation (runs when quotient_msk != 0)
      else if (quotient_msk != {XLEN{1'b0}} && running) begin
        // PicoRV32 algorithm: compare divisor (63-bit) with dividend (32-bit, zero-extended)
        // Verilog will zero-extend dividend_reg to 63 bits for comparison
        if (divisor_reg <= dividend_reg) begin
          // Divisor fits in remainder, subtract it and set quotient bit
          dividend_reg <= dividend_reg - divisor_reg[XLEN-1:0];
          quotient     <= quotient | quotient_msk;

          `ifdef DEBUG_DIV_STEPS
          $display("[DIV_STEP] divisor=%h <= dividend=%h: subtract, quotient_msk=%h -> quotient=%h",
                   divisor_reg[XLEN-1:0], dividend_reg, quotient_msk, quotient | quotient_msk);
          `endif
        end else begin
          `ifdef DEBUG_DIV_STEPS
          $display("[DIV_STEP] divisor=%h > dividend=%h: skip, quotient_msk=%h",
                   divisor_reg[XLEN-1:0], dividend_reg, quotient_msk);
          `endif
        end

        // Shift divisor right and quotient mask right
        divisor_reg  <= divisor_reg >> 1;
        quotient_msk <= quotient_msk >> 1;
      end
      // Division complete (quotient_msk reached 0)
      else if (quotient_msk == {XLEN{1'b0}} && running) begin
        running <= 1'b0;
        ready   <= 1'b1;

        `ifdef DEBUG_DIV
        $display("[DIV] Complete: quotient=%h remainder=%h outsign=%b",
                 quotient, dividend_reg, outsign);
        `endif

        // Compute final result based on operation
        case (op_reg)
          DIV, DIVU: begin
            // Return quotient (negated if outsign is set)
            extracted_result = outsign ? (~quotient + 1'b1) : quotient;
          end
          REM, REMU: begin
            // Return remainder (dividend_reg, negated if outsign is set)
            extracted_result = outsign ? (~dividend_reg + 1'b1) : dividend_reg;
          end
        endcase

        // Sign-extend for RV64W operations
        if (XLEN == 64 && word_op_reg) begin
          result <= {{32{extracted_result[31]}}, extracted_result[31:0]};
        end else begin
          result <= extracted_result;
        end

        `ifdef DEBUG_DIV
        $display("[DIV] Result: op=%b result=%h", op_reg,
                 (op_reg == DIV || op_reg == DIVU) ? (outsign ? (~quotient + 1'b1) : quotient) :
                                                      (outsign ? (~dividend_reg + 1'b1) : dividend_reg));
        `endif
      end
    end
  end

endmodule
