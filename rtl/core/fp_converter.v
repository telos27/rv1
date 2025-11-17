// 浮点转换单元
// 实现 INT↔FP 和 FLOAT↔DOUBLE 转换
// 多周期执行: 2–3 周期

`include "config/rv_config.vh"

module fp_converter #(
  parameter FLEN = `FLEN,  // 32 单精度, 64 双精度
  parameter XLEN = `XLEN   // 32: RV32, 64: RV64
) (
  input  wire              clk,
  input  wire              reset_n,

  // 控制信号
  input  wire              start,          // 启动操作
  input  wire [3:0]        operation,      // 转换类型 (编码见下)
  input  wire [2:0]        rounding_mode,  // IEEE 754 舍入模式
  input  wire              fmt,            // 0: 单精度, 1: 双精度
  output reg               busy,           // 运算进行中
  output reg               done,           // 运算完成 (1 周期脉冲)

  // 输入 (根据操作类型可以是整数或浮点数)
  input  wire [XLEN-1:0]   int_operand,   // 整数输入 (用于 INT→FP)
  input  wire [FLEN-1:0]   fp_operand,    // FP 输入 (用于 FP→INT 或 FP→FP)

  // 输出
  output reg  [XLEN-1:0]   int_result,    // 整数结果 (用于 FP→INT)
  output reg  [FLEN-1:0]   fp_result,     // FP 结果 (用于 INT→FP 或 FP→FP)

  // 异常标志
  output reg               flag_nv,        // 无效操作
  output reg               flag_of,        // 上溢
  output reg               flag_uf,        // 下溢
  output reg               flag_nx         // 不精确
);

  // 操作编码
  localparam FCVT_W_S   = 4'b0000;  // 浮点转有符号 int32
  localparam FCVT_WU_S  = 4'b0001;  // 浮点转无符号 int32
  localparam FCVT_L_S   = 4'b0010;  // 浮点转有符号 int64 (仅 RV64)
  localparam FCVT_LU_S  = 4'b0011;  // 浮点转无符号 int64 (仅 RV64)
  localparam FCVT_S_W   = 4'b0100;  // 有符号 int32 转浮点
  localparam FCVT_S_WU  = 4'b0101;  // 无符号 int32 转浮点
  localparam FCVT_S_L   = 4'b0110;  // 有符号 int64 转浮点 (仅 RV64)
  localparam FCVT_S_LU  = 4'b0111;  // 无符号 int64 转浮点 (仅 RV64)
  localparam FCVT_S_D   = 4'b1000;  // 双精度转单精度
  localparam FCVT_D_S   = 4'b1001;  // 单精度转双精度

  // IEEE 754 格式参数
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;
  localparam BIAS = (FLEN == 32) ? 127 : 1023;
  localparam MAX_EXP = (FLEN == 32) ? 255 : 2047;

  // 状态机
  localparam IDLE      = 2'b00;
  localparam CONVERT   = 2'b01;
  localparam ROUND     = 2'b10;
  localparam DONE      = 2'b11;

  reg [1:0] state, next_state;

  // 中间量
  reg sign_result;
  reg [EXP_WIDTH-1:0] exp_result;
  reg [MAN_WIDTH:0] man_result;
  reg [63:0] int_abs;              // INT→FP 的绝对值
  reg [5:0] leading_zeros;         // 前导零计数
  reg guard, round, sticky;
  reg round_up;

  // FP 分量提取临时信号
  reg sign_fp;
  reg [EXP_WIDTH-1:0] exp_fp;
  reg [MAN_WIDTH-1:0] man_fp;
  reg is_nan, is_inf, is_zero;
  reg signed [15:0] int_exp;
  reg [63:0] shifted_man;

  // 锁存输入操作数 (Bug #28 修复: 在启动时锁存操作数以防止重新采样)
  reg [XLEN-1:0] int_operand_latched;
  reg [FLEN-1:0] fp_operand_latched;
  reg [3:0] operation_latched;
  reg [2:0] rounding_mode_latched;
  reg fmt_latched;  // 锁存的格式信号

  // 有效操作数: 在转换过程中使用锁存值，空闲时使用直接值
  wire [XLEN-1:0] int_operand_eff;
  wire [FLEN-1:0] fp_operand_eff;
  wire [3:0] operation_eff;
  wire [2:0] rounding_mode_eff;

  assign int_operand_eff = (state == IDLE) ? int_operand_latched : int_operand_latched;
  assign fp_operand_eff = (state == IDLE) ? fp_operand : fp_operand_latched;
  assign operation_eff = (state == IDLE) ? operation : operation_latched;
  assign rounding_mode_eff = (state == IDLE) ? rounding_mode : rounding_mode_latched;

  // 单/双精度提取辅助寄存器
  reg sign_d, sign_s;
  reg [10:0] exp_d, adjusted_exp_11;
  reg [51:0] man_d;
  reg [7:0] exp_s;
  reg [22:0] man_s;
  reg is_nan_d, is_inf_d, is_zero_d;
  reg is_nan_s, is_inf_s, is_zero_s;
  reg [10:0] adjusted_exp;
  reg [7:0] adjusted_exp_8;

  // 状态机与输入锁存
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state <= IDLE;
      int_operand_latched <= {XLEN{1'b0}};
      fp_operand_latched <= {FLEN{1'b0}};
      operation_latched <= 4'b0;
      rounding_mode_latched <= 3'b0;
      fmt_latched <= 1'b0;
    end else begin
      state <= next_state;
      // 锁存输入操作数 (从 IDLE 到 CONVERT 的转换)
      if (state == IDLE && start) begin
        int_operand_latched <= int_operand;
        fp_operand_latched <= fp_operand;
        operation_latched <= operation;
        rounding_mode_latched <= rounding_mode;
        fmt_latched <= fmt;
      end
    end
  end

  // 下一状态逻辑
  // Bug #28 修复: 仅在 IDLE 状态接受 start
  // 这防止了在 start 信号多次有效时操作数被重新采样
  always @(*) begin
    case (state)
      IDLE:    next_state = start ? CONVERT : IDLE;
      CONVERT: next_state = ROUND;
      ROUND:   next_state = DONE;
      DONE:    next_state = IDLE;
      default: next_state = IDLE;
    endcase
  end

  // busy/done 信号
  // Bug #28 修复: DONE 状态保持 busy=1，防止立即重启
  always @(*) begin
    busy = (state != IDLE);
    done = (state == DONE);
  end

  // 主数据通路
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      int_result <= {XLEN{1'b0}};
      fp_result <= {FLEN{1'b0}};
      flag_nv <= 1'b0;
      flag_of <= 1'b0;
      flag_uf <= 1'b0;
      flag_nx <= 1'b0;
    end else begin
      case (state)

        // ============================================================
        // CONVERT: 执行转换
        // ============================================================
        CONVERT: begin
          case (operation_latched)  // Bug #28 修复: 使用锁存的操作

            // --------------------------------------------------------
            // FP → INT 转换
            // --------------------------------------------------------
            FCVT_W_S, FCVT_WU_S, FCVT_L_S, FCVT_LU_S: begin
              // Bug #14 修复: 在 FP→INT 转换开始时清除标志
              flag_nv <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;

              // 提取 FP 分量 - Bug #43 修复: 根据 fmt_latched 提取
              if (FLEN == 64) begin
                if (fmt_latched) begin
                  // 双精度
                  sign_fp = fp_operand_latched[63];
                  exp_fp = fp_operand_latched[62:52];
                  man_fp = fp_operand_latched[51:0];
                  is_nan = (fp_operand_latched[62:52] == 11'h7FF) && (fp_operand_latched[51:0] != 0);
                  is_inf = (fp_operand_latched[62:52] == 11'h7FF) && (fp_operand_latched[51:0] == 0);
                  is_zero = (fp_operand_latched[62:0] == 0);
                end else begin
                  // 单精度 (从低 32 位提取)
                  sign_fp = fp_operand_latched[31];
                  exp_fp = {3'b000, fp_operand_latched[30:23]};  // 填充到 EXP_WIDTH
                  man_fp = {fp_operand_latched[22:0], 29'b0};    // 填充到 MAN_WIDTH
                  is_nan = (fp_operand_latched[30:23] == 8'hFF) && (fp_operand_latched[22:0] != 0);
                  is_inf = (fp_operand_latched[30:23] == 8'hFF) && (fp_operand_latched[22:0] == 0);
                  is_zero = (fp_operand_latched[30:0] == 0);
                end
              end else begin
                // FLEN=32, 始终单精度
                sign_fp = fp_operand_latched[31];
                exp_fp = fp_operand_latched[30:23];
                man_fp = fp_operand_latched[22:0];
                is_nan = (fp_operand_latched[30:23] == 8'hFF) && (fp_operand_latched[22:0] != 0);
                is_inf = (fp_operand_latched[30:23] == 8'hFF) && (fp_operand_latched[22:0] == 0);
                is_zero = (fp_operand_latched[30:0] == 0);
              end

              `ifdef DEBUG_FPU_CONVERTER
              $display("[CONVERTER] FP→INT: fp_operand=%h, sign=%b, exp=%d, man=%h",
                       fp_operand, sign_fp, exp_fp, man_fp);
              $display("[CONVERTER]   is_nan=%b, is_inf=%b, is_zero=%b", is_nan, is_inf, is_zero);
              $display("[CONVERTER]   operation_latched=%b (%d)", operation_latched, operation_latched);
              `endif

              if (is_nan || is_inf) begin
                // Bug #26 修复: NaN 始终转换为最大正整数 (符合 RISC-V 规范)
                // 无穷大遵循符号位: +Inf→max, -Inf→min (有符号) 或 0 (无符号)
                // Bug #24 修复: 使用 operation_latched 而不是 operation
                case (operation_latched)
                  FCVT_W_S:  int_result <= (is_nan || !sign_fp) ? 32'h7FFFFFFF : 32'h80000000;
                  FCVT_WU_S: int_result <= (is_nan || !sign_fp) ? 32'hFFFFFFFF : 32'h00000000;
                  FCVT_L_S:  int_result <= (is_nan || !sign_fp) ? 64'h7FFFFFFFFFFFFFFF : 64'h8000000000000000;
                  FCVT_LU_S: int_result <= (is_nan || !sign_fp) ? 64'hFFFFFFFFFFFFFFFF : 64'h0000000000000000;
                endcase
                flag_nv <= 1'b1;

                `ifdef DEBUG_FPU_CONVERTER
                $display("[CONVERTER]   NaN/Inf path: sign_fp=%b, 结果将基于操作设置", sign_fp);
                `endif
              end else if (is_zero) begin
                // 零: 返回 0
                int_result <= {XLEN{1'b0}};
              end else begin
                // 正常转换
                // 计算整数指数 (Bug #43 修复: 根据格式使用正确的偏移量)
                if (fmt_latched)
                  int_exp = exp_fp - 16'd1023;  // 双精度偏移量
                else
                  int_exp = exp_fp - 16'd127;   // 单精度偏移量

                // Bug #20 修复: 检查指数是否过大 (上溢)
                // Bug #25 修复: 修正无符号字上溢检测
                // Bug #Session86d 修复: 区分 W 和 L 转换的上溢检测
                // 对于 32 位转换 (W/WU, operation_latched[1]==0):
                //   - 有符号字 (W): 当 int_exp > 31 时上溢, 或 int_exp==31 且值 != -2^31
                //   - 无符号字 (WU): 当 int_exp >= 32 (int_exp > 31) 时上溢
                // 对于 64 位转换 (L/LU, operation_latched[1]==1):
                //   - 有符号长整型 (L): 当 int_exp > 63 时上溢, 或 int_exp==63 且值 != -2^63
                //   - 无符号长整型 (LU): 当 int_exp >= 64 (int_exp > 63) 时上溢

                // 根据 W 与 L 检查上溢
                if ((operation_latched[1] == 1'b0 && int_exp > 31) ||  // W/WU: 32 位上溢
                    (operation_latched[1] == 1'b0 && int_exp == 31 && operation_latched[0] == 1'b0 && (man_fp != 0 || !sign_fp)) ||  // W: special case at 2^31
                    (operation_latched[1] == 1'b1 && int_exp > 63) ||  // L/LU: 64 位上溢
                    (operation_latched[1] == 1'b1 && int_exp == 63 && operation_latched[0] == 1'b1) ||  // LU: 无符号长整型在 2^63 处总是上溢
                    (operation_latched[1] == 1'b1 && int_exp == 63 && operation_latched[0] == 1'b0 && (man_fp != 0 || !sign_fp))) begin  // L: 有符号长整型溢出，除非恰好是 -2^63
                  // 上溢: 返回最大/最小值
                  // Bug #23 修复: 无符号转换中带有负值的情况应饱和为 0
                  // Bug #24 修复: 使用 operation_latched 而不是 operation
                  case (operation_latched)
                    FCVT_W_S:  int_result <= sign_fp ? 32'h80000000 : 32'h7FFFFFFF;
                    FCVT_WU_S: int_result <= sign_fp ? 32'h00000000 : 32'hFFFFFFFF;
                    FCVT_L_S:  int_result <= sign_fp ? 64'h8000000000000000 : 64'h7FFFFFFFFFFFFFFF;
                    FCVT_LU_S: int_result <= sign_fp ? 64'h0000000000000000 : 64'hFFFFFFFFFFFFFFFF;
                  endcase
                  flag_nv <= 1'b1;

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   OVERFLOW: int_exp=%d, man_fp=%h, sign=%b -> saturate",
                           int_exp, man_fp, sign_fp);
                  `endif
                end
                // 检查指数是否为负 (分数结果)
                else if (int_exp < 0) begin
                  // Bug #27 修复: 分数值 (0 < 值 < 1) 需要舍入
                  // 结果是 0 或 1，具体取决于舍入模式
                  reg should_round_up_frac;

                  // 对于值 < 1.0:
                  // - 截断值始终为 0
                  // - 需要检查是否应舍入到 1
                  // - Guard 位是隐含的 1 位 (尾数的 MSB)
                  // - Round/sticky 是尾数位

                  flag_nx <= !is_zero;

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   int_exp=%d < 0, 分数结果 (0 < 值 < 1)", int_exp);
                  $display("[CONVERTER]   sign=%b, mantissa=0x%h", sign_fp, man_fp);
                  `endif

                  // 确定分数值的舍入方式
                  case (rounding_mode)
                    3'b000: begin // RNE
                      // 对于 int_exp = -1: value = 1.mantissa * 2^-1 = 0.1mantissa (binary)
                      // Guard 位是隐含的 1，规范数的值始终为 1
                      // 舍入位是尾数的 MSB
                      // Sticky 位是剩余尾数位的 OR
                      // 如果 guard=1 且 (round=1 或 sticky=1 或 LSB=1)，则向上舍入
                      // 由于截断结果是 0 (LSB=0)，因此如果满足以下条件，则向上舍入: 1 AND (MSB_man=1 OR other_bits≠0)
                      // 这简化为: 当值 >= 0.5 时向上舍入
                      // 对于值=0.5 (man=0)，舍入到偶数 (0)
                      // 对于值>0.5 (man!=0 且 MSB=0，或 MSB=1)，舍入到 1

                      // int_exp=-1: 0.1mantissa, rounds up if >= 0.75 (MSB=1) OR = 0.5 + epsilon (MSB=0, rest!=0)
                      // 但实际上对于 0.5 精确值，我们舍入到偶数 (0)
                      if (int_exp == -1) begin
                        // 值在 0.5 到 1.0 之间
                        // 0.5 精确: man_fp = 0, 舍入到 0 (偶数)
                        // > 0.5: 舍入到 1
                        should_round_up_frac = (man_fp != 0);
                      end else begin
                        // int_exp < -1: 值 < 0.5, 始终舍入到 0
                        should_round_up_frac = 1'b0;
                      end
                    end
                    3'b001: begin // RTZ - 始终截断为 0
                      should_round_up_frac = 1'b0;
                    end
                    3'b010: begin // RDN - 向下舍入 (朝向 -inf)
                      // 如果为负且有分数位，则增加幅度
                      should_round_up_frac = sign_fp && !is_zero;
                    end
                    3'b011: begin // RUP - 向上舍入 (朝向 +inf)
                      // 如果为正且非零，则向上舍入
                      should_round_up_frac = !sign_fp && !is_zero;
                    end
                    3'b100: begin // RMM - 舍入到远离零
                      // 如果大于等于 0.5，则向上舍入
                      should_round_up_frac = (int_exp == -1);
                    end
                    default: begin
                      should_round_up_frac = 1'b0;
                    end
                  endcase

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   舍入模式=%b, should_round_up=%b",
                           rounding_mode, should_round_up_frac);
                  `endif

                  // 应用舍入
                  if (operation_latched[0] == 1'b1 && sign_fp) begin
                    // Bug #22 修复: 无符号转换带负值: 饱和为 0
                    // 仅当舍入后的幅度 >= 1.0 时设置无效标志
                    // 对于舍入到 0 的分数值，仅设置不精确标志 (已处理)
                    int_result <= {XLEN{1'b0}};
                    if (should_round_up_frac) begin
                      // 舍入到 -1 (幅度 1)，在无符号下溢出: 无效
                      flag_nv <= 1'b1;
                    end
                    // else: 舍入到 0，合法 (仅不精确，已处理)
                  end else if (operation_latched[0] == 1'b0 && sign_fp) begin
                    // 有符号负数: -0 或 -1
                    int_result <= should_round_up_frac ? {XLEN{1'b1}} : {XLEN{1'b0}}; // -1 或 0
                  end else begin
                    // 正数 (有符号或无符号): 0 或 1
                    int_result <= should_round_up_frac ? {{(XLEN-1){1'b0}}, 1'b1} : {XLEN{1'b0}};
                  end

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   最终结果=%h",
                           should_round_up_frac ? (sign_fp ? {XLEN{1'b1}} : 1) : 0);
                  `endif
                end else begin
                  // 正常转换: 移位尾数
                  // 构建 64 位尾数: {隐含的 1, 23 位尾数, 40 个零位}
                  reg [63:0] man_64_full;
                  reg [63:0] lost_bits;
                  reg        frac_guard, frac_round, frac_sticky;
                  reg        should_round_up;
                  reg [63:0] rounded_result;

                  // Bug #48 修复: 根据格式调整填充
                  // 对于 FLEN=64:
                  //   - 单精度: man_fp[51:29] 包含 23 位尾数，man_fp[28:0] 为零
                  //                      构建: {1'b1, man_fp[51:29], 40'b0} = 64 位
                  //   - 双精度: man_fp[51:0] 包含 52 位尾数
                  //                      构建: {1'b1, man_fp[51:0], 11'b0} = 64 位
                  // 对于 FLEN=32:
                  //   - 单精度: man_fp[22:0] 包含 23 位尾数
                  //                      构建: {1'b1, man_fp[22:0], 40'b0} = 64 位
                  if (FLEN == 64) begin
                    if (fmt_latched)
                      man_64_full = {1'b1, man_fp[51:0], 11'b0};  // 双精度
                    else
                      man_64_full = {1'b1, man_fp[51:29], 40'b0}; // 单精度
                  end else begin
                    man_64_full = {1'b1, man_fp[22:0], 40'b0};    // FLEN=32, 单精度
                  end

                  shifted_man = man_64_full >> (63 - int_exp);

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   int_exp=%d >= 0, 正常转换", int_exp);
                  $display("[CONVERTER]   man_64_full=%h, shift_amount=%d",
                           man_64_full, (63 - int_exp));
                  $display("[CONVERTER]   shifted_man=%h",
                           shifted_man);
                  `endif

                  // Bug #26 修复: 提取分数位并应用舍入用于 FP→INT
                  // 提取被移出的位 (分数部分)
                  if (int_exp < 63) begin
                    reg [63:0] lost_bits_mask;
                    lost_bits_mask = (64'h1 << (63 - int_exp)) - 1;
                    lost_bits = man_64_full & lost_bits_mask;

                    // 从分数部分提取 guard, round, sticky 位
                    // Guard 位: 分数部分的 MSB (位位置 63-int_exp-1)
                    // Round 位: 下一位 (位位置 63-int_exp-2)
                    // Sticky 位: 所有剩余位的 OR
                    if (int_exp <= 61) begin
                      frac_guard  = lost_bits[63 - int_exp - 1];
                      frac_round  = (int_exp <= 60) ? lost_bits[63 - int_exp - 2] : 1'b0;
                      frac_sticky = (int_exp <= 60) ? (|(lost_bits & ((64'h1 << (63 - int_exp - 2)) - 1))) :
                                    (int_exp == 61) ? (|(lost_bits & ((64'h1 << (63 - int_exp - 1)) - 1))) : 1'b0;
                    end else if (int_exp == 62) begin
                      frac_guard  = lost_bits[0];
                      frac_round  = 1'b0;
                      frac_sticky = 1'b0;
                    end else begin
                      frac_guard  = 1'b0;
                      frac_round  = 1'b0;
                      frac_sticky = 1'b0;
                    end

                    flag_nx <= (lost_bits != 0);
                  end else begin
                    // 如果指数 >= 63，则没有分数位
                    lost_bits = 64'h0;
                    frac_guard = 1'b0;
                    frac_round = 1'b0;
                    frac_sticky = 1'b0;
                    flag_nx <= 1'b0;
                  end

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   丢失位=%h, GRS=%b%b%b",
                           lost_bits, frac_guard, frac_round, frac_sticky);
                  `endif

                  // 根据舍入模式确定是否应舍入
                  // IEEE 754 舍入模式:
                  // 000 = RNE (舍入到最近，平局时舍入到偶数)
                  // 001 = RTZ (朝零舍入) - 始终截断
                  // 010 = RDN (向下舍入 / 朝 -无穷大)
                  // 011 = RUP (向上舍入 / 朝 +无穷大)
                  // 100 = RMM (舍入到最近，平局时舍入到最大幅度)
                  case (rounding_mode)
                    3'b000: begin // RNE
                      // 如果: guard=1 且 (round=1 或 sticky=1 或 LSB=1)，则向上舍入
                      should_round_up = frac_guard && (frac_round || frac_sticky || shifted_man[0]);
                    end
                    3'b001: begin // RTZ
                      should_round_up = 1'b0;
                    end
                    3'b010: begin // RDN
                      // 向下舍入 (朝 -无穷大): 如果为负，则增加幅度
                      should_round_up = sign_fp && (frac_guard || frac_round || frac_sticky);
                    end
                    3'b011: begin // RUP
                      // 向上舍入 (朝 +无穷大): 如果为正，则增加幅度
                      should_round_up = !sign_fp && (frac_guard || frac_round || frac_sticky);
                    end
                    3'b100: begin // RMM
                      // 舍入到最近，平局时远离零
                      should_round_up = frac_guard;
                    end
                    default: begin
                      should_round_up = 1'b0;
                    end
                  endcase

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   舍入模式=%b, should_round_up=%b",
                           rounding_mode, should_round_up);
                  `endif

                  // 应用舍入增量
                  rounded_result = shifted_man + (should_round_up ? 64'h1 : 64'h0);

                  // 对于有符号转换应用符号，或对无符号饱和
                  if (operation_latched[0] == 1'b1 && sign_fp) begin
                    // Bug #21 修复: 无符号转换带负值: 饱和为 0 并设置无效标志
                    int_result <= {XLEN{1'b0}};
                    flag_nv <= 1'b1;
                  end else if (operation_latched[0] == 1'b0 && sign_fp) begin
                    // 有符号负数
                    int_result <= -rounded_result[XLEN-1:0];
                  end else begin
                    // 正数 (有符号或无符号)
                    int_result <= rounded_result[XLEN-1:0];
                  end

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   舍入结果=%h, 最终整数结果=%h",
                           rounded_result[XLEN-1:0],
                           (operation_latched[0] == 1'b0 && sign_fp) ? -rounded_result[XLEN-1:0] : rounded_result[XLEN-1:0]);
                  `endif
                end
              end
            end

            // --------------------------------------------------------
            // INT → FP 转换
            // --------------------------------------------------------
            FCVT_S_W, FCVT_S_WU, FCVT_S_L, FCVT_S_LU: begin
              // Bug #14 修复: 在 INT→FP 转换开始时清除标志
              flag_nv <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;

              `ifdef DEBUG_FPU_CONVERTER
              $display("[CONVERTER] INT→FP 转换阶段: op=%b, int_operand_latched=0x%h", operation, int_operand_latched);
              `endif

              // 检查零
              if (int_operand_latched == 0) begin
                // 对于零输入，设置中间值以便 ROUND 状态不破坏结果
                sign_result <= 1'b0;
                exp_result <= {EXP_WIDTH{1'b0}};
                man_result <= {(MAN_WIDTH+1){1'b0}};
                guard <= 1'b0;
                round <= 1'b0;
                sticky <= 1'b0;
                `ifdef DEBUG_FPU_CONVERTER
                $display("[CONVERTER]   零输入，设置中间值为零");
                `endif
              end else begin
                // Bug #18 修复: 首先使用阻塞赋值计算所有值
                // 然后在最后注册以避免时序问题

                reg [63:0] int_abs_temp;
                reg sign_temp;
                reg [5:0] lz_temp;
                reg [63:0] shifted_temp;
                reg [EXP_WIDTH-1:0] exp_temp;
                reg [MAN_WIDTH:0] man_temp;
                reg g_temp, r_temp, s_temp;

                // 提取符号和绝对值
                // Bug #Session86b 修复: 正确处理 W/WU 与 L/LU 转换
                // operation_latched[1]: 0=W/WU (32 位), 1=L/LU (64 位)
                // operation_latched[0]: 0=有符号, 1=无符号

                // 检查这是否是一个有符号的负值
                // 对于 W/WU: 检查第 31 位，对于 L/LU: 检查第 XLEN-1 位
                if (operation_latched[0] == 1'b0 &&
                    (operation_latched[1] == 1'b0 ? int_operand_latched[31] : int_operand_latched[XLEN-1])) begin
                  // 有符号负数
                  sign_temp = 1'b1;
                  // Bug #24 修复: 显式处理宽度转换以避免符号扩展
                  // Bug #Session86c 修复: 对于 W 转换，左移 32 位以便前导零
                  // 计数相对于 64 位位置 (使指数计算一致)
                  if (operation_latched[1] == 1'b0) begin
                    // W 转换: 取反低 32 位，左移到上半部分
                    int_abs_temp = {(-int_operand_latched[31:0]), 32'b0};
                  end else if (XLEN == 32) begin
                    // RV32 上的 L 转换: 使用完整 XLEN (已经在低 32 位)
                    int_abs_temp = {(-int_operand_latched[31:0]), 32'b0};
                  end else begin
                    // RV64 上的 L 转换: 使用完整 64 位 (无移位)
                    int_abs_temp = -int_operand_latched;
                  end
                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   有符号负数: int_abs = 0x%h, is_w=%b", int_abs_temp, (operation_latched[1] == 1'b0));
                  `endif
                end else begin
                  // 正数或无符号
                  sign_temp = 1'b0;
                  // Bug #24 修复: 显式处理宽度转换以避免符号扩展
                  // Bug #Session86c 修复: 对于 W 转换，左移 32 位以便前导零
                  // 计数相对于 64 位位置 (使指数计算一致)
                  if (operation_latched[1] == 1'b0) begin
                    // W 转换: 提取低 32 位，左移到上半部分
                    int_abs_temp = {int_operand_latched[31:0], 32'b0};
                  end else if (XLEN == 32) begin
                    // RV32 上的 L 转换: 使用完整 XLEN (已经在低 32 位)
                    int_abs_temp = {int_operand_latched[31:0], 32'b0};
                  end else begin
                    // RV64 上的 L 转换: 使用完整 64 位 (无移位)
                    int_abs_temp = int_operand_latched;
                  end
                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   正数/无符号: int_abs = 0x%h, is_w=%b", int_abs_temp, (operation_latched[1] == 1'b0));
                  `endif
                end

                // 计数前导零以找到 MSB 位置
                // Bug #13 修复: 使用优先编码器正确计数前导零
                // Bug #18 修复: 对所有中间值使用阻塞赋值
                casez (int_abs_temp)
                  64'b1???????????????????????????????????????????????????????????????: lz_temp = 6'd0;
                  64'b01??????????????????????????????????????????????????????????????: lz_temp = 6'd1;
                  64'b001?????????????????????????????????????????????????????????????: lz_temp = 6'd2;
                  64'b0001????????????????????????????????????????????????????????????: lz_temp = 6'd3;
                  64'b00001???????????????????????????????????????????????????????????: lz_temp = 6'd4;
                  64'b000001??????????????????????????????????????????????????????????: lz_temp = 6'd5;
                  64'b0000001?????????????????????????????????????????????????????????: lz_temp = 6'd6;
                  64'b00000001????????????????????????????????????????????????????????: lz_temp = 6'd7;
                  64'b000000001???????????????????????????????????????????????????????: lz_temp = 6'd8;
                  64'b0000000001??????????????????????????????????????????????????????: lz_temp = 6'd9;
                  64'b00000000001?????????????????????????????????????????????????????: lz_temp = 6'd10;
                  64'b000000000001????????????????????????????????????????????????????: lz_temp = 6'd11;
                  64'b0000000000001???????????????????????????????????????????????????: lz_temp = 6'd12;
                  64'b00000000000001??????????????????????????????????????????????????: lz_temp = 6'd13;
                  64'b000000000000001?????????????????????????????????????????????????: lz_temp = 6'd14;
                  64'b0000000000000001????????????????????????????????????????????????: lz_temp = 6'd15;
                  64'b00000000000000001???????????????????????????????????????????????: lz_temp = 6'd16;
                  64'b000000000000000001??????????????????????????????????????????????: lz_temp = 6'd17;
                  64'b0000000000000000001?????????????????????????????????????????????: lz_temp = 6'd18;
                  64'b00000000000000000001????????????????????????????????????????????: lz_temp = 6'd19;
                  64'b000000000000000000001???????????????????????????????????????????: lz_temp = 6'd20;
                  64'b0000000000000000000001??????????????????????????????????????????: lz_temp = 6'd21;
                  64'b00000000000000000000001?????????????????????????????????????????: lz_temp = 6'd22;
                  64'b000000000000000000000001????????????????????????????????????????: lz_temp = 6'd23;
                  64'b0000000000000000000000001???????????????????????????????????????: lz_temp = 6'd24;
                  64'b00000000000000000000000001??????????????????????????????????????: lz_temp = 6'd25;
                  64'b000000000000000000000000001?????????????????????????????????????: lz_temp = 6'd26;
                  64'b0000000000000000000000000001????????????????????????????????????: lz_temp = 6'd27;
                  64'b00000000000000000000000000001???????????????????????????????????: lz_temp = 6'd28;
                  64'b000000000000000000000000000001??????????????????????????????????: lz_temp = 6'd29;
                  64'b0000000000000000000000000000001?????????????????????????????????: lz_temp = 6'd30;
                  64'b00000000000000000000000000000001????????????????????????????????: lz_temp = 6'd31;
                  64'b000000000000000000000000000000001???????????????????????????????: lz_temp = 6'd32;
                  64'b0000000000000000000000000000000001??????????????????????????????: lz_temp = 6'd33;
                  64'b00000000000000000000000000000000001?????????????????????????????: lz_temp = 6'd34;
                  64'b000000000000000000000000000000000001????????????????????????????: lz_temp = 6'd35;
                  64'b0000000000000000000000000000000000001???????????????????????????: lz_temp = 6'd36;
                  64'b00000000000000000000000000000000000001??????????????????????????: lz_temp = 6'd37;
                  64'b000000000000000000000000000000000000001?????????????????????????: lz_temp = 6'd38;
                  64'b0000000000000000000000000000000000000001????????????????????????: lz_temp = 6'd39;
                  64'b00000000000000000000000000000000000000001???????????????????????: lz_temp = 6'd40;
                  64'b000000000000000000000000000000000000000001??????????????????????: lz_temp = 6'd41;
                  64'b0000000000000000000000000000000000000000001?????????????????????: lz_temp = 6'd42;
                  64'b00000000000000000000000000000000000000000001????????????????????: lz_temp = 6'd43;
                  64'b000000000000000000000000000000000000000000001???????????????????: lz_temp = 6'd44;
                  64'b0000000000000000000000000000000000000000000001??????????????????: lz_temp = 6'd45;
                  64'b00000000000000000000000000000000000000000000001?????????????????: lz_temp = 6'd46;
                  64'b000000000000000000000000000000000000000000000001????????????????: lz_temp = 6'd47;
                  64'b0000000000000000000000000000000000000000000000001???????????????: lz_temp = 6'd48;
                  64'b00000000000000000000000000000000000000000000000001??????????????: lz_temp = 6'd49;
                  64'b000000000000000000000000000000000000000000000000001?????????????: lz_temp = 6'd50;
                  64'b0000000000000000000000000000000000000000000000000001????????????: lz_temp = 6'd51;
                  64'b00000000000000000000000000000000000000000000000000001???????????: lz_temp = 6'd52;
                  64'b000000000000000000000000000000000000000000000000000001??????????: lz_temp = 6'd53;
                  64'b0000000000000000000000000000000000000000000000000000001?????????: lz_temp = 6'd54;
                  64'b00000000000000000000000000000000000000000000000000000001????????: lz_temp = 6'd55;
                  64'b000000000000000000000000000000000000000000000000000000001???????: lz_temp = 6'd56;
                  64'b0000000000000000000000000000000000000000000000000000000001??????: lz_temp = 6'd57;
                  64'b00000000000000000000000000000000000000000000000000000000001?????: lz_temp = 6'd58;
                  64'b000000000000000000000000000000000000000000000000000000000001????: lz_temp = 6'd59;
                  64'b0000000000000000000000000000000000000000000000000000000000001???: lz_temp = 6'd60;
                  64'b00000000000000000000000000000000000000000000000000000000000001??: lz_temp = 6'd61;
                  64'b000000000000000000000000000000000000000000000000000000000000001?: lz_temp = 6'd62;
                  64'b0000000000000000000000000000000000000000000000000000000000000001: lz_temp = 6'd63;
                  default: lz_temp = 6'd63;  // 全零 (由于零检查，不应发生)
                endcase

                // 计算指数 (Bug #43 修复: 根据格式使用正确的偏移量)
                // Bug #Session86 修复: 调整 W 与 L 转换的指数
                // 对于 W/WU (32 位整数): 位位置 = 31 - lz_temp
                // 对于 L/LU (64 位整数): 位位置 = 63 - lz_temp
                if (fmt_latched) begin
                  // 双精度偏移量
                  if (operation_latched[1])
                    exp_temp = 11'd1023 + (63 - lz_temp);  // L/LU: 64 位整数
                  else
                    exp_temp = 11'd1023 + (31 - lz_temp);  // W/WU: 32 位整数
                end else begin
                  // 单精度偏移量
                  if (operation_latched[1])
                    exp_temp = 8'd127 + (63 - lz_temp);    // L/LU: 64 位整数
                  else
                    exp_temp = 8'd127 + (31 - lz_temp);    // W/WU: 32 位整数
                end

                // 规范化尾数 (移位以对齐 MSB 到位 63)
                // Bug #13b 修复: 仅移位 leading_zeros (不 +1)
                // Bug #18 修复: 对所有中间值使用阻塞赋值
                // +1 跳过在提取 [62:62-MAN_WIDTH+1] 中隐含
                shifted_temp = int_abs_temp << lz_temp;

                // 提取尾数位 (Bug #43 修复: 根据格式提取正确宽度)
                // 对于双精度: 52 位，对于单精度: 23 位
                if (fmt_latched) begin
                  // 双精度: 提取位 [62:11] (52 位)
                  man_temp = shifted_temp[62:11];
                  // 双精度的 GRS 位
                  g_temp = shifted_temp[10];
                  r_temp = shifted_temp[9];
                  s_temp = |shifted_temp[8:0];
                end else begin
                  // 单精度: 提取位 [62:40] (23 位)，填充零
                  man_temp = {shifted_temp[62:40], 29'b0};
                  // 单精度的 GRS 位
                  g_temp = shifted_temp[39];
                  r_temp = shifted_temp[38];
                  s_temp = |shifted_temp[37:0];
                end

                // 现在注册所有计算值
                sign_result <= sign_temp;
                int_abs <= int_abs_temp;
                leading_zeros <= lz_temp;
                exp_result <= exp_temp;
                man_result <= man_temp;
                guard <= g_temp;
                round <= r_temp;
                sticky <= s_temp;

                `ifdef DEBUG_FPU_CONVERTER
                $display("[CONVERTER]   lz_temp=%d, exp_temp=%d (0x%h)",
                         lz_temp, exp_temp, exp_temp);
                $display("[CONVERTER]   shifted_temp=0x%h", shifted_temp);
                $display("[CONVERTER]   man_temp=0x%h", man_temp);
                $display("[CONVERTER]   GRS 位: g=%b, r=%b, s=%b", g_temp, r_temp, s_temp);
                `endif
              end
            end

            // --------------------------------------------------------
            // FLOAT ↔ DOUBLE 转换
            // --------------------------------------------------------
            FCVT_S_D: begin
              // 双精度转单精度 (可能损失精度)
              // 提取双精度分量
              sign_d = fp_operand_latched[63];
              exp_d = fp_operand_latched[62:52];
              man_d = fp_operand_latched[51:0];

              // 检查特殊值
              is_nan_d = (exp_d == 11'h7FF) && (man_d != 0);
              is_inf_d = (exp_d == 11'h7FF) && (man_d == 0);
              is_zero_d = (fp_operand_latched[62:0] == 0);

              if (is_nan_d) begin
                fp_result <= 32'h7FC00000;  // 规范 NaN
              end else if (is_inf_d) begin
                fp_result <= {sign_d, 8'hFF, 23'b0};  // ±无穷大
              end else if (is_zero_d) begin
                fp_result <= {sign_d, 31'b0};  // ±0
              end else begin
                // 正常转换: 调整指数偏移量 (1023 → 127)
                adjusted_exp = exp_d - 1023 + 127;

                // 检查上溢
                if (adjusted_exp >= 255) begin
                  fp_result <= {sign_d, 8'hFF, 23'b0};  // ±无穷大
                  flag_of <= 1'b1;
                  flag_nx <= 1'b1;
                end
                // 检查下溢
                else if (adjusted_exp < 1) begin
                  fp_result <= {sign_d, 31'b0};  // ±0
                  flag_uf <= 1'b1;
                  flag_nx <= 1'b1;
                end else begin
                  // 截断尾数 (52 位 → 23 位)
                  fp_result <= {sign_d, adjusted_exp[7:0], man_d[51:29]};
                  flag_nx <= |man_d[28:0];  // 如果低位非零则不精确
                end
              end
            end

            FCVT_D_S: begin
              // 单精度转双精度 (无精度损失)
              // 提取单精度分量
              sign_s = fp_operand_latched[31];
              exp_s = fp_operand_latched[30:23];
              man_s = fp_operand_latched[22:0];

              `ifdef DEBUG_FCVT_TRACE
              $display("[FCVT_D_S] fp_operand=%h", fp_operand_latched);
              $display("[FCVT_D_S] sign=%b, exp=%h, man=%h", sign_s, exp_s, man_s);
              `endif

              // 检查特殊值
              is_nan_s = (exp_s == 8'hFF) && (man_s != 0);
              is_inf_s = (exp_s == 8'hFF) && (man_s == 0);
              is_zero_s = (fp_operand_latched[30:0] == 0);

              `ifdef DEBUG_FCVT_TRACE
              $display("[FCVT_D_S] is_nan=%b, is_inf=%b, is_zero=%b", is_nan_s, is_inf_s, is_zero_s);
              `endif

              if (is_nan_s) begin
                fp_result <= 64'h7FF8000000000000;  // 规范 NaN
              end else if (is_inf_s) begin
                fp_result <= {sign_s, 11'h7FF, 52'b0};  // ±无穷大
              end else if (is_zero_s) begin
                fp_result <= {sign_s, 63'b0};  // ±0
              end else begin
                // 正常转换: 调整指数偏移量 (127 → 1023)
                reg [10:0] adjusted_exp;
                adjusted_exp = exp_s + 1023 - 127;

                `ifdef DEBUG_FCVT_TRACE
                $display("[FCVT_D_S] adjusted_exp=%h", adjusted_exp);
                $display("[FCVT_D_S] result={%b, %h, %h, 29'b0}", sign_s, adjusted_exp, man_s);
                `endif

                // 扩展尾数 (23 位 → 52 位，零填充)
                fp_result <= {sign_s, adjusted_exp, man_s, 29'b0};
              end
            end

            default: begin
              // 无效操作
              fp_result <= {FLEN{1'b0}};
              int_result <= {XLEN{1'b0}};
            end
          endcase
        end

        // ============================================================
        // ROUND: 仅 INT→FP 使用的舍入阶段
        // ============================================================
        ROUND: begin
          // 仅对 INT→FP 转换应用舍入
          if (operation_latched[3:2] == 2'b01) begin
            `ifdef DEBUG_FPU_CONVERTER
            $display("[CONVERTER] ROUND stage:");
            $display("[CONVERTER]   sign=%b, exp=%d (0x%h), man=0x%h",
                     sign_result, exp_result, exp_result, man_result);
            $display("[CONVERTER]   GRS: guard=%b, round=%b, sticky=%b",
                     guard, round, sticky);
            $display("[CONVERTER]   rounding_mode_latched=%b", rounding_mode_latched);
            `endif

            // 确定是否应舍入
            // 根据舍入模式直接计算 round_up
            round_up <= (rounding_mode == 3'b000) ? (guard && (round || sticky || man_result[0])) :
                        (rounding_mode == 3'b001) ? 1'b0 :
                        (rounding_mode == 3'b010) ? (sign_result && (guard || round || sticky)) :
                        (rounding_mode == 3'b011) ? (!sign_result && (guard || round || sticky)) :
                        (rounding_mode == 3'b100) ? guard : 1'b0;

            `ifdef DEBUG_FPU_CONVERTER
            $display("[CONVERTER]   round_up=%b",
                     (rounding_mode == 3'b000) ? (guard && (round || sticky || man_result[0])) :
                     (rounding_mode == 3'b001) ? 1'b0 :
                     (rounding_mode == 3'b010) ? (sign_result && (guard || round || sticky)) :
                     (rounding_mode == 3'b011) ? (!sign_result && (guard || round || sticky)) :
                     (rounding_mode == 3'b100) ? guard : 1'b0);
            `endif

            // 应用舍入 - Bug #43 修复: 同时处理单精度和双精度
            if ((rounding_mode == 3'b000 && guard && (round || sticky || man_result[0])) ||
                (rounding_mode == 3'b010 && sign_result && (guard || round || sticky)) ||
                (rounding_mode == 3'b011 && !sign_result && (guard || round || sticky)) ||
                (rounding_mode == 3'b100 && guard)) begin
              // 需要向上舍入 - 检查尾数上溢
              if (fmt_latched) begin
                // 双精度 (52 位尾数)
                if (man_result[51:0] == 52'hFFFFFFFFFFFFF) begin
                  fp_result <= {sign_result, exp_result + 1'b1, 52'b0};
                end else begin
                  fp_result <= {sign_result, exp_result, man_result[51:0] + 1'b1};
                end
              end else begin
                // 单精度 (23 位尾数，FLEN=64 时 NaN-boxed)
                if (man_result[51:29] == 23'h7FFFFF) begin
                  // 尾数上溢
                  if (FLEN == 64)
                    fp_result <= {32'hFFFFFFFF, sign_result, exp_result[7:0] + 1'b1, 23'b0};
                  else
                    fp_result <= {sign_result, exp_result[7:0] + 1'b1, 23'b0};
                end else begin
                  // 无上溢
                  if (FLEN == 64)
                    fp_result <= {32'hFFFFFFFF, sign_result, exp_result[7:0], man_result[51:29] + 1'b1};
                  else
                    fp_result <= {sign_result, exp_result[7:0], man_result[51:29] + 1'b1};
                end
              end
            end else begin
              // 无需舍入
              if (fmt_latched) begin
                // 双精度
                fp_result <= {sign_result, exp_result, man_result[51:0]};
              end else begin
                // 单精度 (NaN-boxed if FLEN=64)
                if (FLEN == 64)
                  fp_result <= {32'hFFFFFFFF, sign_result, exp_result[7:0], man_result[51:29]};
                else
                  fp_result <= {sign_result, exp_result[7:0], man_result[51:29]};
              end
            end

            flag_nx <= guard || round || sticky;
          end
        end

        // ============================================================
        // DONE: 保持结果并打印调试信息 (可选)
        // ============================================================
        DONE: begin
          // 仅保持结果
          `ifdef DEBUG_FPU_CONVERTER
          $display("[CONVERTER] DONE 状态: fp_result=0x%h, int_result=0x%h",
                   fp_result, int_result);
          `endif
        end

      endcase
    end
  end

endmodule
