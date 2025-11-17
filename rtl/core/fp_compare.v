// 浮点比较单元
// 实现 FEQ.S/D, FLT.S/D, FLE.S/D 指令
// 纯组合逻辑 (1 周期)
// 结果写入整数寄存器 rd

`include "config/rv_config.vh"

module fp_compare #(
  parameter FLEN = `FLEN  // 32 单精度，64 双精度
) (
  // 操作数
  input  wire [FLEN-1:0]   operand_a,   // rs1
  input  wire [FLEN-1:0]   operand_b,   // rs2

  // 控制 (操作选择)
  input  wire [1:0]        operation,   // 00: FEQ, 01: FLT, 10: FLE
  input  wire              fmt,         // 0: 单精度, 1: 双精度

  // 结果 (写入整数寄存器)
  output reg  [31:0]       result,      // 0 或 1，零扩展到 32 位

  // 异常标志
  output reg               flag_nv      // 无效操作 (信号 NaN)
);

  // IEEE 754 格式参数
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;

  // 基于格式提取字段，FLEN=64 时区分单/双精度
  // 对于 FLEN=64 且为单精度 (fmt=0)：使用位 [31:0]（[63:32] 为 NaN-boxing）
  // 对于 FLEN=64 且为双精度 (fmt=1)：使用位 [63:0]
  // 对于 FLEN=32：始终为单精度
  wire sign_a;
  wire sign_b;
  wire [10:0] exp_a;  // 最大指数宽度（双精度为 11 位）
  wire [10:0] exp_b;
  wire [51:0] man_a;  // 最大尾数宽度（双精度为 52 位）
  wire [51:0] man_b;

  generate
    if (FLEN == 64) begin : g_flen64
      // 对于 FLEN=64，同时支持单精度和双精度
      assign sign_a = fmt ? operand_a[63] : operand_a[31];
      assign sign_b = fmt ? operand_b[63] : operand_b[31];
      assign exp_a = fmt ? operand_a[62:52] : {3'b000, operand_a[30:23]};
      assign exp_b = fmt ? operand_b[62:52] : {3'b000, operand_b[30:23]};
      assign man_a = fmt ? operand_a[51:0] : {29'b0, operand_a[22:0]};
      assign man_b = fmt ? operand_b[51:0] : {29'b0, operand_b[22:0]};
    end else begin : g_flen32
      // 对于 FLEN=32，只支持单精度
      assign sign_a = operand_a[31];
      assign sign_b = operand_b[31];
      assign exp_a = {3'b000, operand_a[30:23]};
      assign exp_b = {3'b000, operand_b[30:23]};
      assign man_a = {29'b0, operand_a[22:0]};
      assign man_b = {29'b0, operand_b[22:0]};
    end
  endgenerate

  // 基于格式的有效指数/尾数宽度
  wire [10:0] exp_all_ones = fmt ? 11'h7FF : 11'h0FF; // 当前格式的全 1
  wire man_msb_a = fmt ? man_a[51] : man_a[22];       // 用于 NaN 检测的尾数最高位
  wire man_msb_b = fmt ? man_b[51] : man_b[22];

  // 特殊值检测
  wire is_nan_a = (exp_a == exp_all_ones) && (man_a != 0);
  wire is_nan_b = (exp_b == exp_all_ones) && (man_b != 0);
  wire is_snan_a = is_nan_a && !man_msb_a;  // 信号 NaN: 尾数最高位 = 0
  wire is_snan_b = is_nan_b && !man_msb_b;
  wire is_qnan_a = is_nan_a && man_msb_a;   // 静默 NaN: 尾数最高位 = 1
  wire is_qnan_b = is_nan_b && man_msb_b;

  // 零检测 (+0/-0 均视为零) - 指数和尾数均为零
  wire is_zero_a = (exp_a == 0) && (man_a == 0);
  wire is_zero_b = (exp_b == 0) && (man_b == 0);

  // 检查是否都是零 (+0 == -0 在 IEEE 754 中)
  wire both_zero = is_zero_a && is_zero_b;

  // 浮点比较逻辑
  // 不能直接使用 $signed()，需考虑符号和指数/尾数
  //
  // 规则:
  // 1. 符号不同: 负 < 正 (除非都是 0)
  // 2. 同为正: 指数/尾数按无符号比较
  // 3. 同为负: 比特模式越大数值越小 (反向比较)

  wire both_positive = !sign_a && !sign_b;
  wire both_negative = sign_a && sign_b;
  wire signs_differ = sign_a != sign_b;

  // 对于正数或比较大小时
  // 先比较指数，再比较尾数
  wire mag_a_less_than_b = (exp_a < exp_b) || ((exp_a == exp_b) && (man_a < man_b));
  wire a_equal_b = (sign_a == sign_b) && (exp_a == exp_b) && (man_a == man_b);

  // 真正的浮点小于比较
  wire a_less_than_b = both_zero ? 1'b0 :  // +0 和 -0 相等，不小于
                       signs_differ ? sign_a :  // 如果符号不同，负数 (sign_a=1) < 正数 (sign_a=0)
                       both_positive ? mag_a_less_than_b :  // 同为正数: 正常大小比较
                       both_negative ? !mag_a_less_than_b && !a_equal_b : 1'b0;  // 同为负数: 反向比较

  always @(*) begin
    // 默认无异常
    flag_nv = 1'b0;
    result = 32'd0;

    // NaN 情况
    if (is_nan_a || is_nan_b) begin
      case (operation)
        2'b00: begin  // FEQ
          // FEQ 对任意 NaN 返回 0，仅 sNaN 置 NV
          result = 32'd0;
          flag_nv = is_snan_a || is_snan_b;  // 仅信号 NaN 置 NV
        end
        2'b01, 2'b10: begin  // FLT, FLE
          // FLT/FLE 对任意 NaN 返回 0，总是置 NV
          result = 32'd0;
          flag_nv = 1'b1;  // 总是为 FLT/FLE 与 NaN 置无效信号
        end
        default: begin
          result = 32'd0;
          flag_nv = 1'b0;
        end
      endcase
    end
    // 正常比较
    else begin
      case (operation)
        2'b00: begin  // FEQ: a == b
          // 特殊情况: +0 == -0
          if (both_zero)
            result = 32'd1;
          else if (a_equal_b)
            result = 32'd1;
          else
            result = 32'd0;
        end
        2'b01: begin  // FLT: a < b
          // 特殊情况: +0 和 -0 相等 (不小于)
          if (both_zero)
            result = 32'd0;
          else if (a_less_than_b)
            result = 32'd1;
          else
            result = 32'd0;
        end
        2'b10: begin  // FLE: a <= b
          // 特殊情况: +0 <= -0 为真
          if (both_zero)
            result = 32'd1;
          else if (a_less_than_b || a_equal_b)
            result = 32'd1;
          else
            result = 32'd0;
        end
        default: begin
          result = 32'd0;
        end
      endcase
    end
  end

endmodule
