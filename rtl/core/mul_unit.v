// mul_unit.v - Sequential Multiplier for M Extension
// Implements MUL, MULH, MULHSU, MULHU instructions
// Uses iterative add-and-shift algorithm
// Parameterized for RV32/RV64 support

`include "config/rv_config.vh"

module mul_unit #(
  parameter XLEN = `XLEN
)(
  input  wire                clk,
  input  wire                reset_n,

  // Control interface
  input  wire                start,        // Start multiplication
  input  wire  [1:0]         mul_op,       // Operation: 00=MUL, 01=MULH, 10=MULHSU, 11=MULHU
  input  wire                is_word_op,   // RV64: W-suffix instruction (32-bit)

  // Data interface
  input  wire  [XLEN-1:0]    operand_a,    // Multiplicand
  input  wire  [XLEN-1:0]    operand_b,    // Multiplier
  output reg   [XLEN-1:0]    result,       // Result

  // Status
  output wire                busy,         // Operation in progress
  output reg                 ready         // Result ready (1 cycle pulse)
);

  // Operation encoding
  localparam MUL    = 2'b00;  // Lower XLEN bits
  localparam MULH   = 2'b01;  // Upper XLEN bits (signed × signed)
  localparam MULHSU = 2'b10;  // Upper XLEN bits (signed × unsigned)
  localparam MULHU  = 2'b11;  // Upper XLEN bits (unsigned × unsigned)

  // State machine
  localparam IDLE      = 2'b00;
  localparam COMPUTE   = 2'b01;
  localparam DONE      = 2'b10;

  reg [1:0] state, state_next;

  // Determine effective operand width for RV64W operations
  wire [6:0] op_width;
  assign op_width = (XLEN == 64 && is_word_op) ? 7'd32 : XLEN[6:0];

  // Sign handling
  wire op_a_signed, op_b_signed;
  assign op_a_signed = (mul_op == MULH) || (mul_op == MULHSU);
  assign op_b_signed = (mul_op == MULH);

  // Sign extension for signed operands
  wire [XLEN-1:0] abs_a, abs_b;
  wire sign_a, sign_b;

  generate
    if (XLEN == 64) begin : gen_sign_64
      assign sign_a = is_word_op ? operand_a[31] : operand_a[XLEN-1];
      assign sign_b = is_word_op ? operand_b[31] : operand_b[XLEN-1];
    end else begin : gen_sign_32
      assign sign_a = operand_a[XLEN-1];
      assign sign_b = operand_b[XLEN-1];
    end
  endgenerate

  wire negate_a = op_a_signed && sign_a;
  wire negate_b = op_b_signed && sign_b;

  // For word operations, mask to lower 32 bits and sign-extend
  wire [XLEN-1:0] masked_a, masked_b;
  generate
    if (XLEN == 64) begin : gen_mask_64
      assign masked_a = is_word_op ? {{32{operand_a[31]}}, operand_a[31:0]} : operand_a;
      assign masked_b = is_word_op ? {{32{operand_b[31]}}, operand_b[31:0]} : operand_b;
    end else begin : gen_mask_32
      assign masked_a = operand_a;
      assign masked_b = operand_b;
    end
  endgenerate

  assign abs_a = negate_a ? (~masked_a + 1'b1) : masked_a;
  assign abs_b = negate_b ? (~masked_b + 1'b1) : masked_b;

  // Double-width accumulator for product
  reg [2*XLEN-1:0] product;
  reg [2*XLEN-1:0] multiplicand;
  reg [XLEN-1:0]   multiplier;

  // Cycle counter
  reg [6:0] cycle_count;

  // Result sign (for signed operations)
  reg result_negative;

  // Control signals
  reg [1:0] op_reg;
  reg       word_op_reg;

  // Temporary result extraction register
  reg [XLEN-1:0] extracted_result;

  // State machine
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state <= IDLE;
    end else begin
      state <= state_next;
    end
  end

  always @(*) begin
    state_next = state;
    case (state)
      IDLE: begin
        if (start) state_next = COMPUTE;
      end

      COMPUTE: begin
        if (cycle_count >= op_width) state_next = DONE;
      end

      DONE: begin
        state_next = IDLE;
      end

      default: state_next = IDLE;
    endcase
  end

  // Datapath
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      product         <= {(2*XLEN){1'b0}};
      multiplicand    <= {(2*XLEN){1'b0}};
      multiplier      <= {XLEN{1'b0}};
      cycle_count     <= 7'd0;
      ready           <= 1'b0;
      result          <= {XLEN{1'b0}};
      result_negative <= 1'b0;
      op_reg          <= 2'b00;
      word_op_reg     <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          ready <= 1'b0;

          if (start) begin
            // Initialize for multiplication
            product         <= {(2*XLEN){1'b0}};
            multiplicand    <= {{XLEN{1'b0}}, abs_a};
            multiplier      <= abs_b;
            cycle_count     <= 7'd0;
            result_negative <= negate_a ^ negate_b;  // XOR for result sign
            op_reg          <= mul_op;
            word_op_reg     <= is_word_op;
          end
        end

        COMPUTE: begin
          // Add and shift algorithm
          if (multiplier[0]) begin
            product <= product + multiplicand;
          end

          // Shift for next iteration
          multiplicand <= multiplicand << 1;
          multiplier   <= multiplier >> 1;
          cycle_count  <= cycle_count + 1;
        end

        DONE: begin
          ready <= 1'b1;

          // Extract result based on operation
          // Note: For word operations, result will be sign-extended after extraction
          case (op_reg)
            MUL: begin
              // Lower XLEN bits
              if (result_negative) begin
                extracted_result = ~product[XLEN-1:0] + 1'b1;
              end else begin
                extracted_result = product[XLEN-1:0];
              end
            end

            MULH, MULHSU, MULHU: begin
              // Upper XLEN bits
              if (result_negative && op_reg != MULHU) begin
                // Negate 2*XLEN product, then take upper bits
                reg [2*XLEN-1:0] neg_product;
                neg_product = ~product + 1'b1;
                extracted_result = neg_product[2*XLEN-1:XLEN];
              end else begin
                extracted_result = product[2*XLEN-1:XLEN];
              end
            end

            default: extracted_result = product[XLEN-1:0];
          endcase

          // Sign-extend for RV64W operations
          if (XLEN == 64 && word_op_reg) begin
            result <= {{32{extracted_result[31]}}, extracted_result[31:0]};
          end else begin
            result <= extracted_result;
          end
        end

        default: begin
          ready <= 1'b0;
        end
      endcase
    end
  end

  // Combinational busy signal - asserts when not in IDLE state
  // This is one cycle faster than using a registered busy signal.
  assign busy = (state != IDLE);

  // Debug tracing
  `ifdef DEBUG_MULTIPLIER
  always @(posedge clk) begin
    if (start && state == IDLE) begin
      $display("[MUL_UNIT] START: op=%b (MUL=00,MULH=01,MULHSU=10,MULHU=11), a=0x%h, b=0x%h",
               mul_op, operand_a, operand_b);
      $display("[MUL_UNIT]   abs_a=0x%h, abs_b=0x%h, negate_a=%b, negate_b=%b",
               abs_a, abs_b, negate_a, negate_b);
    end

    if (state == COMPUTE) begin
      if (cycle_count == 0 || cycle_count == 1 || cycle_count >= op_width - 2) begin
        $display("[MUL_UNIT] COMPUTE[%2d]: product=0x%h, multiplicand=0x%h, multiplier=0x%h, mult[0]=%b",
                 cycle_count, product, multiplicand, multiplier, multiplier[0]);
      end
    end

    if (state == DONE) begin
      $display("[MUL_UNIT] DONE: op=%b, result_negative=%b, product=0x%h",
               op_reg, result_negative, product);
      $display("[MUL_UNIT]   product[%d:%d]=0x%h, product[%d:0]=0x%h",
               2*XLEN-1, XLEN, product[2*XLEN-1:XLEN],
               XLEN-1, product[XLEN-1:0]);
      $display("[MUL_UNIT]   result=0x%h, ready=%b", result, ready);

      // Special trace for MULHU
      if (op_reg == MULHU) begin
        $display("[MUL_UNIT] *** MULHU SPECIFIC: expected upper bits, got result=0x%h ***", result);
        $display("[MUL_UNIT]     If result equals operand_a (0x%h), THIS IS THE BUG!", operand_a);
      end
    end

    if (state != state_next) begin
      $display("[MUL_UNIT] STATE: %s -> %s",
               state == IDLE ? "IDLE" : state == COMPUTE ? "COMPUTE" : "DONE",
               state_next == IDLE ? "IDLE" : state_next == COMPUTE ? "COMPUTE" : "DONE");
    end
  end
  `endif

endmodule
