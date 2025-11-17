// alu.v - RISC-V 算术逻辑单元
// 执行算术和逻辑运算
// 作者: RV1 Project
// 日期: 2025-10-09
// 更新: 2025-10-10 - 参数化 XLEN (支持 32/64 位)

`include "config/rv_config.vh"

module alu #(
  parameter XLEN = `XLEN  // 数据宽度: 32 或 64 位
) (
  input  wire [XLEN-1:0] operand_a,      // 第一个操作数
  input  wire [XLEN-1:0] operand_b,      // 第二个操作数
  input  wire [3:0]      alu_control,    // 运算选择
  output reg  [XLEN-1:0] result,         // ALU 结果
  output wire            zero,           // 结果为零标志
  output wire            less_than,      // 有符号小于标志
  output wire            less_than_unsigned  // 无符号小于标志
);

  // 比较用内部信号
  wire signed [XLEN-1:0] signed_a;
  wire signed [XLEN-1:0] signed_b;

  // 移位量宽度: RV32 为 5 位 (0-31), RV64 为 6 位 (0-63)
  localparam SHAMT_WIDTH = $clog2(XLEN);
  wire [SHAMT_WIDTH-1:0] shamt;

  assign signed_a = operand_a;
  assign signed_b = operand_b;
  assign shamt = operand_b[SHAMT_WIDTH-1:0];

  // ALU 运算
  always @(*) begin
    case (alu_control)
      4'b0000: result = operand_a + operand_b;           // ADD 加法
      4'b0001: result = operand_a - operand_b;           // SUB 减法
      4'b0010: result = operand_a << shamt;              // SLL 逻辑左移
      4'b0011: result = (signed_a < signed_b) ? {{(XLEN-1){1'b0}}, 1'b1} : {XLEN{1'b0}};  // SLT 有符号小于
      4'b0100: result = (operand_a < operand_b) ? {{(XLEN-1){1'b0}}, 1'b1} : {XLEN{1'b0}}; // SLTU 无符号小于
      4'b0101: result = operand_a ^ operand_b;           // XOR 异或
      4'b0110: result = operand_a >> shamt;              // SRL 逻辑右移
      4'b0111: result = signed_a >>> shamt;              // SRA 算术右移
      4'b1000: result = operand_a | operand_b;           // OR 或
      4'b1001: result = operand_a & operand_b;           // AND 与
      default: result = {XLEN{1'b0}};                    // 默认置零
    endcase
  end

  // 标志位生成
  assign zero = (result == {XLEN{1'b0}});
  assign less_than = (signed_a < signed_b);
  assign less_than_unsigned = (operand_a < operand_b);

endmodule
