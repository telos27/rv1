// 浮点最小/最大单元
// 实现 FMIN.S/D 和 FMAX.S/D 指令
// 纯组合逻辑 (1 周期)
//
// IEEE 754-2008 特殊情形处理:
// - 若任一操作数为 NaN，则返回另一个操作数 (若两者均为 NaN 则返回规范 NaN)
// - -0 与 +0 比较相等，但 FMIN 返回 -0，FMAX 返回 +0
// - 信号 NaN 会置 NV 标志

`include "config/rv_config.vh"

module fp_minmax #(
  parameter FLEN = `FLEN  // 32 单精度，64 双精度
) (
  // 操作数
  input  wire [FLEN-1:0]   operand_a,   // rs1
  input  wire [FLEN-1:0]   operand_b,   // rs2

  // 控制
  input  wire              is_max,      // 0: MIN, 1: MAX
  input  wire              fmt,         // 0: 单精度, 1: 双精度

  // 结果
  output reg  [FLEN-1:0]   result,

  // 异常标志
  output reg               flag_nv      // 无效操作 (信号 NaN)
);

  // IEEE 754 格式参数
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;

  // 基于格式提取字段
  // FLEN=64 且单精度 (fmt=0): 使用 [31:0] (高位 NaN-box)
  // FLEN=64 且双精度 (fmt=1): 使用 [63:0]
  // FLEN=32: 始终使用单精度
  wire sign_a;
  wire sign_b;
  wire [10:0] exp_a;  // 指数字段，最大宽度 11 位（对应双精度）
  wire [10:0] exp_b;
  wire [51:0] man_a;  // 尾数字段，最大宽度 52 位（对应双精度）
  wire [51:0] man_b;

  generate
    if (FLEN == 64) begin : g_flen64
      // 对于 FLEN=64，支持单精度和双精度
      assign sign_a = fmt ? operand_a[63] : operand_a[31];
      assign sign_b = fmt ? operand_b[63] : operand_b[31];
      assign exp_a = fmt ? operand_a[62:52] : {3'b000, operand_a[30:23]};
      assign exp_b = fmt ? operand_b[62:52] : {3'b000, operand_b[30:23]};
      assign man_a = fmt ? operand_a[51:0] : {29'b0, operand_a[22:0]};
      assign man_b = fmt ? operand_b[51:0] : {29'b0, operand_b[22:0]};
    end else begin : g_flen32
      // 对于 FLEN=32，仅支持单精度
      assign sign_a = operand_a[31];
      assign sign_b = operand_b[31];
      assign exp_a = {3'b000, operand_a[30:23]};
      assign exp_b = {3'b000, operand_b[30:23]};
      assign man_a = {29'b0, operand_a[22:0]};
      assign man_b = {29'b0, operand_b[22:0]};
    end
  endgenerate

  // 基于格式的有效指数/尾数宽度
  wire [10:0] exp_all_ones = fmt ? 11'h7FF : 11'h0FF;  // 当前格式的全 1
  wire man_msb_a = fmt ? man_a[51] : man_a[22];         // NaN 检测的 MSB
  wire man_msb_b = fmt ? man_b[51] : man_b[22];

  // 检测特殊值
  wire is_nan_a = (exp_a == exp_all_ones) && (man_a != 0);
  wire is_nan_b = (exp_b == exp_all_ones) && (man_b != 0);
  wire is_snan_a = is_nan_a && !man_msb_a;  // 信号 NaN 的 MSB=0
  wire is_snan_b = is_nan_b && !man_msb_b;
  wire is_qnan_a = is_nan_a && man_msb_a;   // 规范 NaN 的 MSB=1
  wire is_qnan_b = is_nan_b && man_msb_b;

  // 检查零值（包括 +0 和 -0） - 指数和尾数均为零
  wire is_zero_a = (exp_a == 0) && (man_a == 0);
  wire is_zero_b = (exp_b == 0) && (man_b == 0);

  // 浮点比较
  // 不能使用 $signed 比较，因为浮点位模式与有符号整数顺序不匹配
  // 对浮点数：需要先比较符号，再比较大小
  wire both_positive = !sign_a && !sign_b;
  wire both_negative = sign_a && sign_b;
  wire a_positive_b_negative = !sign_a && sign_b;
  wire a_negative_b_positive = sign_a && !sign_b;

  // 绝对值大小比较 (指数优先，再比较尾数)
  wire mag_a_less_than_b = (exp_a < exp_b) ||
                            ((exp_a == exp_b) && (man_a < man_b));

  // 完整浮点比较: a < b
  wire a_equal_b = (sign_a == sign_b) && (exp_a == exp_b) && (man_a == man_b);
  wire a_less_than_b = a_positive_b_negative ? 1'b0 :           // +a vs -b: a > b
                       a_negative_b_positive ? 1'b1 :           // -a vs +b: a < b
                         both_positive ? mag_a_less_than_b :      // 两者同为正数：比较绝对值大小
                         both_negative ? !mag_a_less_than_b && !a_equal_b : 1'b0;  // 两者同为负数：绝对值比较结果取反（排除相等）

  // 规范 NaN (按格式)
  wire [FLEN-1:0] canonical_nan;
  generate
    if (FLEN == 64) begin : g_can_nan_64
      assign canonical_nan = fmt ? 64'h7FF8000000000000 : {32'hFFFFFFFF, 32'h7FC00000};
    end else begin : g_can_nan_32
      assign canonical_nan = 32'h7FC00000;
    end
  endgenerate

  always @(*) begin
    // 默认无异常
    flag_nv = 1'b0;

    // 处理 NaN 情况
    if (is_nan_a && is_nan_b) begin
      // 两个都是 NaN: 返回规范 NaN
      result = canonical_nan;
      flag_nv = is_snan_a || is_snan_b;  // 如果任一为 sNaN 则发出信号
    end else if (is_nan_a) begin
      // 只有 a 是 NaN: 返回 b
      result = operand_b;
      flag_nv = is_snan_a;  // 如果是 sNaN 则发出信号
    end else if (is_nan_b) begin
      // 只有 b 是 NaN: 返回 a
      result = operand_a;
      flag_nv = is_snan_b;  // 如果是 sNaN 则发出信号
    end
    // 处理 +0 / -0 (FMIN/FMAX 需要区分)
    else if (is_zero_a && is_zero_b) begin
      if (is_max) begin
        // FMAX(+0, -0) = +0
        result = sign_a ? operand_b : operand_a;
      end else begin
        // FMIN(+0, -0) = -0
        result = sign_a ? operand_a : operand_b;
      end
    end
    // 正常比较
    else begin
      if (is_max) begin
        // FMAX: 返回较大值
        result = a_less_than_b ? operand_b : operand_a;
      end else begin
        // FMIN: 返回较小值
        result = a_less_than_b ? operand_a : operand_b;
      end
    end
  end

endmodule
