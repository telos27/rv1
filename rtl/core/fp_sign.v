// 浮点符号注入单元
// 实现 FSGNJ.S/D, FSGNJN.S/D, FSGNJX.S/D 指令
// 纯组合逻辑 (1 周期)
//
// FSGNJ:  结果 = |rs1|，符号取自 rs2
// FSGNJN: 结果 = |rs1|，符号为 rs2 的取反
// FSGNJX: 结果 = |rs1|，符号 = sign(rs1) XOR sign(rs2)

`include "config/rv_config.vh"

module fp_sign #(
  parameter FLEN = `FLEN  // 32 为单精度，64 为双精度
) (
  // 操作数
  input  wire [FLEN-1:0]   operand_a,   // rs1
  input  wire [FLEN-1:0]   operand_b,   // rs2

  // 控制 (操作选择)
  input  wire [1:0]        operation,   // 00: FSGNJ, 01: FSGNJN, 10: FSGNJX
  input  wire              fmt,         // 0: 单精度, 1: 双精度

  // 结果
  output wire [FLEN-1:0]   result
);

  // 基于格式提取符号和幅度
  // 单精度: 符号为 bit[31]，双精度: 符号为 bit[FLEN-1]
  wire sign_a;
  wire sign_b;
  wire [FLEN-1:0] magnitude_a;

  generate
    if (FLEN == 64) begin : g_flen64
      // 对于 FLEN=64，支持单精度和双精度
      assign sign_a = fmt ? operand_a[63] : operand_a[31];
      assign sign_b = fmt ? operand_b[63] : operand_b[31];
      // 对于单精度：幅度仅为低 31 位 [30:0]
      // 对于双精度：幅度为低 63 位 [62:0]
      assign magnitude_a = fmt ? operand_a[62:0] : operand_a[30:0];
    end else begin : g_flen32
      // 对于 FLEN=32，仅支持单精度
      assign sign_a = operand_a[31];
      assign sign_b = operand_b[31];
      assign magnitude_a = operand_a[30:0];
    end
  endgenerate

  // 依据操作计算结果符号
  reg result_sign;

  always @(*) begin
    case (operation)
      2'b00:   result_sign = sign_b;           // FSGNJ: 使用 rs2 的符号
      2'b01:   result_sign = ~sign_b;          // FSGNJN: 使用 rs2 的取反符号
      2'b10:   result_sign = sign_a ^ sign_b;  // FSGNJX: 符号异或
      default: result_sign = sign_a;           // 默认: 保持原符号
    endcase
  end

  // 组装结果: 新符号 + 原幅度
  // FLEN=64 且单精度 (fmt=0) 时保留高位 NaN-box
  generate
    if (FLEN == 64) begin : g_result_flen64
      assign result = fmt ? {result_sign, magnitude_a} :
                            {operand_a[63:32], result_sign, magnitude_a[30:0]};
    end else begin : g_result_flen32
      assign result = {result_sign, magnitude_a};
    end
  endgenerate

endmodule
