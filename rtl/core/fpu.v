// Floating-Point Unit (FPU) - Top-Level Integration
// Integrates all 10 FP arithmetic units for F/D extension
// Implements IEEE 754-2008 single and double-precision operations
// Author: RV1 Project
// Date: 2025-10-10
//
// FPU Operations:
//   - Arithmetic: FADD, FSUB, FMUL, FDIV, FSQRT (multi-cycle)
//   - FMA: FMADD, FMSUB, FNMSUB, FNMADD (multi-cycle, single rounding)
//   - Sign Injection: FSGNJ, FSGNJN, FSGNJX (1 cycle)
//   - Min/Max: FMIN, FMAX (1 cycle)
//   - Compare: FEQ, FLT, FLE (1 cycle, writes to int register)
//   - Classify: FCLASS (1 cycle, writes to int register)
//   - Convert: INT↔FP, FLOAT↔DOUBLE (multi-cycle)
//
// Multi-cycle operation handling:
//   - FPU asserts 'busy' signal during multi-cycle operations
//   - Pipeline must stall when FPU is busy
//   - FPU asserts 'done' pulse when operation completes

`include "config/rv_config.vh"

module fpu #(
  parameter FLEN = 32,  // 32 for single-precision (F), 64 for double-precision (D)
  parameter XLEN = 32   // 32 for RV32, 64 for RV64
) (
  input  wire              clk,
  input  wire              reset_n,

  // Control
  input  wire              start,          // Start FP operation
  input  wire [4:0]        fp_alu_op,      // FP operation (from control unit)
  input  wire [2:0]        funct3,         // funct3 field (for compare ops: FEQ=010, FLT=001, FLE=000)
  input  wire [2:0]        rounding_mode,  // IEEE 754 rounding mode (from frm CSR or instruction)
  output wire              busy,           // FPU busy (multi-cycle operation in progress)
  output wire              done,           // Operation complete (1 cycle pulse)

  // Operands (from FP register file)
  input  wire [FLEN-1:0]   operand_a,      // rs1 (or multiplicand for FMA)
  input  wire [FLEN-1:0]   operand_b,      // rs2 (or multiplier for FMA)
  input  wire [FLEN-1:0]   operand_c,      // rs3 (for FMA only)

  // Integer operand (for INT→FP conversions)
  input  wire [XLEN-1:0]   int_operand,

  // Results
  output reg  [FLEN-1:0]   fp_result,      // FP result (to FP register file)
  output reg  [XLEN-1:0]   int_result,     // Integer result (for FP→INT, compare, classify)

  // Exception flags (accumulated into fflags CSR)
  output reg               flag_nv,        // Invalid operation
  output reg               flag_dz,        // Divide by zero
  output reg               flag_of,        // Overflow
  output reg               flag_uf,        // Underflow
  output reg               flag_nx         // Inexact
);

  // FP operation encoding (matches control.v)
  localparam FP_ADD    = 5'b00000;
  localparam FP_SUB    = 5'b00001;
  localparam FP_MUL    = 5'b00010;
  localparam FP_DIV    = 5'b00011;
  localparam FP_SQRT   = 5'b00100;
  localparam FP_SGNJ   = 5'b00101;
  localparam FP_SGNJN  = 5'b00110;
  localparam FP_SGNJX  = 5'b00111;
  localparam FP_MIN    = 5'b01000;
  localparam FP_MAX    = 5'b01001;
  localparam FP_CVT    = 5'b01010;
  localparam FP_CMP    = 5'b01011;
  localparam FP_CLASS  = 5'b01100;
  localparam FP_FMA    = 5'b01101;
  localparam FP_FMSUB  = 5'b01110;
  localparam FP_FNMSUB = 5'b01111;
  localparam FP_FNMADD = 5'b10000;
  localparam FP_MV_XW  = 5'b10001;  // FMV.X.W (bitcast FP→INT, 1 cycle)
  localparam FP_MV_WX  = 5'b10010;  // FMV.W.X (bitcast INT→FP, 1 cycle)

  // ========================================
  // FP Adder/Subtractor
  // ========================================
  wire              adder_start;
  wire              adder_busy;
  wire              adder_done;
  wire [FLEN-1:0]   adder_result;
  wire              adder_flag_nv;
  wire              adder_flag_of;
  wire              adder_flag_uf;
  wire              adder_flag_nx;

  assign adder_start = start && (fp_alu_op == FP_ADD || fp_alu_op == FP_SUB);

  fp_adder #(.FLEN(FLEN)) u_fp_adder (
    .clk            (clk),
    .reset_n        (reset_n),
    .start          (adder_start),
    .is_sub         (fp_alu_op == FP_SUB),
    .rounding_mode  (rounding_mode),
    .busy           (adder_busy),
    .done           (adder_done),
    .operand_a      (operand_a),
    .operand_b      (operand_b),
    .result         (adder_result),
    .flag_nv        (adder_flag_nv),
    .flag_of        (adder_flag_of),
    .flag_uf        (adder_flag_uf),
    .flag_nx        (adder_flag_nx)
  );

  // ========================================
  // FP Multiplier
  // ========================================
  wire              mul_start;
  wire              mul_busy;
  wire              mul_done;
  wire [FLEN-1:0]   mul_result;
  wire              mul_flag_nv;
  wire              mul_flag_of;
  wire              mul_flag_uf;
  wire              mul_flag_nx;

  assign mul_start = start && (fp_alu_op == FP_MUL);

  fp_multiplier #(.FLEN(FLEN)) u_fp_multiplier (
    .clk            (clk),
    .reset_n        (reset_n),
    .start          (mul_start),
    .rounding_mode  (rounding_mode),
    .busy           (mul_busy),
    .done           (mul_done),
    .operand_a      (operand_a),
    .operand_b      (operand_b),
    .result         (mul_result),
    .flag_nv        (mul_flag_nv),
    .flag_of        (mul_flag_of),
    .flag_uf        (mul_flag_uf),
    .flag_nx        (mul_flag_nx)
  );

  // ========================================
  // FP Divider
  // ========================================
  wire              div_start;
  wire              div_busy;
  wire              div_done;
  wire [FLEN-1:0]   div_result;
  wire              div_flag_nv;
  wire              div_flag_dz;
  wire              div_flag_of;
  wire              div_flag_uf;
  wire              div_flag_nx;

  assign div_start = start && (fp_alu_op == FP_DIV);

  fp_divider #(.FLEN(FLEN)) u_fp_divider (
    .clk            (clk),
    .reset_n        (reset_n),
    .start          (div_start),
    .rounding_mode  (rounding_mode),
    .busy           (div_busy),
    .done           (div_done),
    .operand_a      (operand_a),
    .operand_b      (operand_b),
    .result         (div_result),
    .flag_nv        (div_flag_nv),
    .flag_dz        (div_flag_dz),
    .flag_of        (div_flag_of),
    .flag_uf        (div_flag_uf),
    .flag_nx        (div_flag_nx)
  );

  // ========================================
  // FP Square Root
  // ========================================
  wire              sqrt_start;
  wire              sqrt_busy;
  wire              sqrt_done;
  wire [FLEN-1:0]   sqrt_result;
  wire              sqrt_flag_nv;
  wire              sqrt_flag_nx;

  assign sqrt_start = start && (fp_alu_op == FP_SQRT);

  fp_sqrt #(.FLEN(FLEN)) u_fp_sqrt (
    .clk            (clk),
    .reset_n        (reset_n),
    .start          (sqrt_start),
    .rounding_mode  (rounding_mode),
    .busy           (sqrt_busy),
    .done           (sqrt_done),
    .operand        (operand_a),
    .result         (sqrt_result),
    .flag_nv        (sqrt_flag_nv),
    .flag_nx        (sqrt_flag_nx)
  );

  // ========================================
  // FP Fused Multiply-Add (FMA)
  // ========================================
  wire              fma_start;
  wire [1:0]        fma_op_type;
  wire              fma_busy;
  wire              fma_done;
  wire [FLEN-1:0]   fma_result;
  wire              fma_flag_nv;
  wire              fma_flag_of;
  wire              fma_flag_uf;
  wire              fma_flag_nx;

  assign fma_start = start && (fp_alu_op == FP_FMA || fp_alu_op == FP_FMSUB ||
                                fp_alu_op == FP_FNMSUB || fp_alu_op == FP_FNMADD);

  // Map FP_ALU_OP to FMA operation type
  assign fma_op_type = (fp_alu_op == FP_FMA)    ? 2'b00 :
                       (fp_alu_op == FP_FMSUB)  ? 2'b01 :
                       (fp_alu_op == FP_FNMSUB) ? 2'b10 :
                       (fp_alu_op == FP_FNMADD) ? 2'b11 : 2'b00;

  fp_fma #(.FLEN(FLEN)) u_fp_fma (
    .clk            (clk),
    .reset_n        (reset_n),
    .start          (fma_start),
    .fma_op         (fma_op_type),
    .rounding_mode  (rounding_mode),
    .busy           (fma_busy),
    .done           (fma_done),
    .operand_a      (operand_a),  // rs1 (multiplicand)
    .operand_b      (operand_b),  // rs2 (multiplier)
    .operand_c      (operand_c),  // rs3 (addend)
    .result         (fma_result),
    .flag_nv        (fma_flag_nv),
    .flag_of        (fma_flag_of),
    .flag_uf        (fma_flag_uf),
    .flag_nx        (fma_flag_nx)
  );

  // ========================================
  // FP Sign Injection (combinational, 1 cycle)
  // ========================================
  wire [1:0]        sign_op;
  wire [FLEN-1:0]   sign_result;

  assign sign_op = (fp_alu_op == FP_SGNJ)  ? 2'b00 :
                   (fp_alu_op == FP_SGNJN) ? 2'b01 :
                   (fp_alu_op == FP_SGNJX) ? 2'b10 : 2'b00;

  fp_sign #(.FLEN(FLEN)) u_fp_sign (
    .operand_a      (operand_a),
    .operand_b      (operand_b),
    .operation      (sign_op),
    .result         (sign_result)
  );

  // ========================================
  // FP Min/Max (combinational, 1 cycle)
  // ========================================
  wire              minmax_is_max;
  wire [FLEN-1:0]   minmax_result;
  wire              minmax_flag_nv;

  assign minmax_is_max = (fp_alu_op == FP_MAX);

  fp_minmax #(.FLEN(FLEN)) u_fp_minmax (
    .operand_a      (operand_a),
    .operand_b      (operand_b),
    .is_max         (minmax_is_max),
    .result         (minmax_result),
    .flag_nv        (minmax_flag_nv)
  );

  // ========================================
  // FP Compare (combinational, 1 cycle)
  // ========================================
  wire [1:0]        cmp_op;
  wire [31:0]       cmp_result;
  wire              cmp_flag_nv;

  // Decode compare operation from funct3
  // FEQ: funct3=010 (2) -> cmp_op=00
  // FLT: funct3=001 (1) -> cmp_op=01
  // FLE: funct3=000 (0) -> cmp_op=10
  assign cmp_op = (funct3 == 3'b010) ? 2'b00 :  // FEQ
                  (funct3 == 3'b001) ? 2'b01 :  // FLT
                  (funct3 == 3'b000) ? 2'b10 :  // FLE
                  2'b00;  // Default to FEQ

  fp_compare #(.FLEN(FLEN)) u_fp_compare (
    .operand_a      (operand_a),
    .operand_b      (operand_b),
    .operation      (cmp_op),
    .result         (cmp_result),
    .flag_nv        (cmp_flag_nv)
  );

  // ========================================
  // FP Classify (combinational, 1 cycle)
  // ========================================
  wire [31:0]       class_result;

  fp_classify #(.FLEN(FLEN)) u_fp_classify (
    .operand        (operand_a),
    .result         (class_result)
  );

  // ========================================
  // FP Converter (multi-cycle, 2-3 cycles)
  // ========================================
  wire              cvt_start;
  wire [3:0]        cvt_op;
  wire              cvt_busy;
  wire              cvt_done;
  wire [XLEN-1:0]   cvt_int_result;
  wire [FLEN-1:0]   cvt_fp_result;
  wire              cvt_flag_nv;
  wire              cvt_flag_nx;

  assign cvt_start = start && (fp_alu_op == FP_CVT);
  assign cvt_op = 4'b0000; // TODO: decode conversion type from funct5

  fp_converter #(.FLEN(FLEN), .XLEN(XLEN)) u_fp_converter (
    .clk            (clk),
    .reset_n        (reset_n),
    .start          (cvt_start),
    .operation      (cvt_op),
    .rounding_mode  (rounding_mode),
    .busy           (cvt_busy),
    .done           (cvt_done),
    .int_operand    (int_operand),
    .fp_operand     (operand_a),
    .int_result     (cvt_int_result),
    .fp_result      (cvt_fp_result),
    .flag_nv        (cvt_flag_nv),
    .flag_nx        (cvt_flag_nx)
  );

  // ========================================
  // Output Multiplexing
  // ========================================

  // Busy signal: OR of all multi-cycle unit busy signals
  assign busy = adder_busy | mul_busy | div_busy | sqrt_busy | fma_busy | cvt_busy;

  // Done signal: OR of all unit done signals
  assign done = adder_done | mul_done | div_done | sqrt_done | fma_done | cvt_done |
                (start && (fp_alu_op == FP_SGNJ || fp_alu_op == FP_SGNJN || fp_alu_op == FP_SGNJX ||
                           fp_alu_op == FP_MIN || fp_alu_op == FP_MAX ||
                           fp_alu_op == FP_CMP || fp_alu_op == FP_CLASS ||
                           fp_alu_op == FP_MV_XW || fp_alu_op == FP_MV_WX));

  // Result multiplexing
  always @(*) begin
    // Default values
    fp_result  = {FLEN{1'b0}};
    int_result = {XLEN{1'b0}};
    flag_nv = 1'b0;
    flag_dz = 1'b0;
    flag_of = 1'b0;
    flag_uf = 1'b0;
    flag_nx = 1'b0;

    case (fp_alu_op)
      FP_ADD, FP_SUB: begin
        fp_result = adder_result;
        flag_nv = adder_flag_nv;
        flag_of = adder_flag_of;
        flag_uf = adder_flag_uf;
        flag_nx = adder_flag_nx;
      end

      FP_MUL: begin
        fp_result = mul_result;
        flag_nv = mul_flag_nv;
        flag_of = mul_flag_of;
        flag_uf = mul_flag_uf;
        flag_nx = mul_flag_nx;
      end

      FP_DIV: begin
        fp_result = div_result;
        flag_nv = div_flag_nv;
        flag_dz = div_flag_dz;
        flag_of = div_flag_of;
        flag_uf = div_flag_uf;
        flag_nx = div_flag_nx;
      end

      FP_SQRT: begin
        fp_result = sqrt_result;
        flag_nv = sqrt_flag_nv;
        flag_nx = sqrt_flag_nx;
      end

      FP_FMA, FP_FMSUB, FP_FNMSUB, FP_FNMADD: begin
        fp_result = fma_result;
        flag_nv = fma_flag_nv;
        flag_of = fma_flag_of;
        flag_uf = fma_flag_uf;
        flag_nx = fma_flag_nx;
      end

      FP_SGNJ, FP_SGNJN, FP_SGNJX: begin
        fp_result = sign_result;
        // Sign injection never raises exceptions
      end

      FP_MIN, FP_MAX: begin
        fp_result = minmax_result;
        flag_nv = minmax_flag_nv;
      end

      FP_CMP: begin
        int_result = {{(XLEN-32){1'b0}}, cmp_result};  // Zero-extend to XLEN
        flag_nv = cmp_flag_nv;
      end

      FP_CLASS: begin
        int_result = {{(XLEN-32){1'b0}}, class_result};  // Zero-extend to XLEN
        // FCLASS never raises exceptions
      end

      FP_CVT: begin
        fp_result = cvt_fp_result;
        int_result = cvt_int_result;
        flag_nv = cvt_flag_nv;
        flag_nx = cvt_flag_nx;
      end

      FP_MV_XW: begin
        // Bitcast FP→INT (no conversion, just reinterpret bits)
        if (FLEN == 32) begin
          int_result = {{(XLEN-32){operand_a[31]}}, operand_a[31:0]};  // Sign-extend
        end else begin
          int_result = operand_a[XLEN-1:0];  // For RV64 with double-precision
        end
        // No exceptions
      end

      FP_MV_WX: begin
        // Bitcast INT→FP (no conversion, just reinterpret bits)
        if (FLEN == 32) begin
          fp_result = {{(FLEN-32){1'b1}}, int_operand[31:0]};  // NaN-box for single-precision
        end else begin
          fp_result = int_operand[FLEN-1:0];
        end
        // No exceptions
      end

      default: begin
        // Illegal operation - should never happen if control unit is correct
        fp_result  = {FLEN{1'b0}};
        int_result = {XLEN{1'b0}};
      end
    endcase
  end

endmodule
