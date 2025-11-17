// 浮点分类单元
// 实现 FCLASS.S/D 指令
// 纯组合逻辑 (1 周期)
// 在整数寄存器 rd 返回 10 位分类掩码

`include "config/rv_config.vh"

module fp_classify #(
  parameter FLEN = `FLEN  // 32 单精度，64 双精度
) (
  // 操作数
  input  wire [FLEN-1:0]   operand,

  // 控制
  input  wire              fmt,          // 0: 单精度, 1: 双精度

  // 结果 (10 位掩码，写入整数寄存器)
  output reg  [31:0]       result       // 10 位掩码，零扩展到 32 位
);

  // IEEE 754 格式参数
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;

  // 根据格式提取各个字段
  // 当 FLEN=64 且为单精度 (fmt=0) 时：使用 [31:0] 比特（[63:32] 为 NaN-boxing）
  // 当 FLEN=64 且为双精度 (fmt=1) 时：使用 [63:0] 比特
  // 当 FLEN=32 时：始终为单精度
  wire sign;
  wire [10:0] exp;  // 最大指数宽度（双精度为 11 位）
  wire [51:0] man;  // 最大尾数宽度（双精度为 52 位）

  generate
    if (FLEN == 64) begin : g_flen64
      // 对于 FLEN=64，同时支持单精度和双精度
      assign sign = fmt ? operand[63] : operand[31];
      assign exp = fmt ? operand[62:52] : {3'b000, operand[30:23]};
      assign man = fmt ? operand[51:0] : {29'b0, operand[22:0]};
    end else begin : g_flen32
      // 对于 FLEN=32，只支持单精度
      assign sign = operand[31];
      assign exp = {3'b000, operand[30:23]};
      assign man = {29'b0, operand[22:0]};
    end
  endgenerate

  // 分类位 (one-hot 编码)
  // bit 0: 负无穷
  // bit 1: 负正规数
  // bit 2: 负非正规数
  // bit 3: 负零
  // bit 4: 正零
  // bit 5: 正非正规数
  // bit 6: 正正规数
  // bit 7: 正无穷
  // bit 8: 信号 NaN
  // bit 9: 静默 NaN

  // 有效指数全为 1 的模式基于格式
  wire [10:0] exp_all_ones = fmt ? 11'h7FF : 11'h0FF;
  wire man_msb = fmt ? man[51] : man[22];  // 用于 NaN 检测的尾数最高位

  wire is_zero = (exp == 0) && (man == 0);
  wire is_subnormal = (exp == 0) && (man != 0);
  wire is_normal = (exp != 0) && (exp != exp_all_ones);
  wire is_inf = (exp == exp_all_ones) && (man == 0);
  wire is_nan = (exp == exp_all_ones) && (man != 0);
  wire is_snan = is_nan && !man_msb;  // 信号 NaN: 尾数最高位 = 0
  wire is_qnan = is_nan && man_msb;   // 静默 NaN: 尾数最高位 = 1

  always @(*) begin
    result = 32'd0;  // 默认：全零
    // 检查每个分类（独热编码，只有一位应被置位）
    if (is_qnan) begin
      result[9] = 1'b1;  // 静默 NaN
    end else if (is_snan) begin
      result[8] = 1'b1;  // 信号 NaN
    end else if (is_inf && !sign) begin
      result[7] = 1'b1;  // 正无穷
    end else if (is_normal && !sign) begin
      result[6] = 1'b1;  // 正正规数
    end else if (is_subnormal && !sign) begin
      result[5] = 1'b1;  // 正非正规数
    end else if (is_zero && !sign) begin
      result[4] = 1'b1;  // 正零
    end else if (is_zero && sign) begin
      result[3] = 1'b1;  // 负零
    end else if (is_subnormal && sign) begin
      result[2] = 1'b1;  // 负非正规数
    end else if (is_normal && sign) begin
      result[1] = 1'b1;  // 负正规数
    end else if (is_inf && sign) begin
      result[0] = 1'b1;  // 负无穷
    end
  end

endmodule
