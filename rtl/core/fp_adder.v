// 浮点加/减单元
// 实现 FADD.S/D 和 FSUB.S/D 指令
// 完整支持 IEEE 754-2008 舍入模式
// 多周期执行: 3–4 周期

`include "config/rv_config.vh"

module fp_adder #(
  parameter FLEN = `FLEN  // 32 单精度，64 双精度
) (
  input  wire              clk,
  input  wire              reset_n,

  // 控制信号
  input  wire              start,          // 启动操作
  input  wire              is_sub,         // 0: 加法, 1: 减法
  input  wire              fmt,            // 0: 单精度, 1: 双精度
  input  wire [2:0]        rounding_mode,  // IEEE 754 舍入模式
  output reg               busy,           // 运算进行中
  output reg               done,           // 运算完成 (1 周期脉冲)

  // 操作数
  input  wire [FLEN-1:0]   operand_a,
  input  wire [FLEN-1:0]   operand_b,

  // 结果
  output reg  [FLEN-1:0]   result,

  // 异常标志
  output reg               flag_nv,        // 无效操作
  output reg               flag_of,        // 上溢
  output reg               flag_uf,        // 下溢
  output reg               flag_nx         // 不精确
);

  // IEEE 754 格式参数
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;
  localparam BIAS = (FLEN == 32) ? 127 : 1023;
  localparam MAX_EXP = (FLEN == 32) ? 255 : 2047;

  // 状态机
  localparam IDLE      = 3'b000;
  localparam UNPACK    = 3'b001;
  localparam ALIGN     = 3'b010;
  localparam COMPUTE   = 3'b011;
  localparam NORMALIZE = 3'b100;
  localparam ROUND     = 3'b101;
  localparam DONE      = 3'b110;

  reg [2:0] state, next_state;

  // 解包后的操作数 (使用最大位宽以支持双精度)
  reg sign_a, sign_b, sign_result;
  reg [10:0] exp_a, exp_b, exp_result;  // 最多 11 位用于双精度
  reg [52:0] man_a, man_b;              // 最多 53 位 (52+1 隐含位) 用于双精度
  reg fmt_latched;                      // 存储格式信号

  // 特殊值标志
  reg is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;
  reg is_subnormal_a, is_subnormal_b;
  reg special_case_handled;  // 标记特殊情况是否已在对齐阶段处理

  // 对齐、求和、归一化与舍入所需的临时变量
  reg [55:0] aligned_man_a, aligned_man_b;  // 52+3 GRS 位 + 1 位用于对齐
  reg [56:0] sum;                            // +1 位用于溢出
  reg [11:0] exp_diff;                       // 11+1 位
  reg [56:0] normalized_man;
  reg [11:0] adjusted_exp;

  // 舍入相关寄存器
  reg guard, round, sticky;
  reg round_up;

  // 组合舍入决策
  wire round_up_comb;
  wire lsb_bit;  // 尾数的最低有效位，用于舍入时平分情况的判断（与格式相关）

  // 与格式相关的 LSB 选择用于舍入
  // 对于 FLEN=64 的单精度：尾数位于 [54:32]，因此 LSB 是第 32 位
  // 对于双精度：尾数位于 [54:3]，因此 LSB 是第 3 位
  // 对于 FLEN=32：尾数位于 [25:3]，因此 LSB 是第 3 位
  assign lsb_bit = (FLEN == 64 && !fmt_latched) ? normalized_man[32] : normalized_man[3];

  // 组合舍入逻辑
  assign round_up_comb = (state == ROUND) ? (
    (rounding_mode == 3'b000) ? (guard && (round || sticky || lsb_bit)) : // RNE
    (rounding_mode == 3'b001) ? 1'b0 :  // RTZ
    (rounding_mode == 3'b010) ? (sign_result && (guard || round || sticky)) : // RDN
    (rounding_mode == 3'b011) ? (!sign_result && (guard || round || sticky)) : // RUP
    (rounding_mode == 3'b100) ? guard : // RMM
    1'b0  // 默认
  ) : 1'b0;

  // 状态机
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      state <= IDLE;
    else
      state <= next_state;
  end

  // 下一状态逻辑
  always @(*) begin
    case (state)
      IDLE:      next_state = start ? UNPACK : IDLE;
      UNPACK:    next_state = ALIGN;
      ALIGN:     next_state = COMPUTE;
      COMPUTE:   next_state = NORMALIZE;
      NORMALIZE: next_state = ROUND;
      ROUND:     next_state = DONE;
      DONE:      next_state = IDLE;
      default:   next_state = IDLE;
    endcase
  end

  // busy 和 done 信号
  always @(*) begin
    busy = (state != IDLE) && (state != DONE);
    done = (state == DONE);
  end

  // 主数据通路
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      result <= {FLEN{1'b0}};
      flag_nv <= 1'b0;
      flag_of <= 1'b0;
      flag_uf <= 1'b0;
      flag_nx <= 1'b0;
      sign_result <= 1'b0;
      exp_result <= {EXP_WIDTH{1'b0}};
      special_case_handled <= 1'b0;
    end else begin
      case (state)

        // ============================================================
        // UNPACK: 提取符号、指数、尾数，区分 FLEN=64 单/双精度
        // ============================================================
        UNPACK: begin
          // 清除特殊情况标志以便进行新操作
          special_case_handled <= 1'b0;

          // 存储格式信号
          fmt_latched <= fmt;

          // 针对 FLEN=64 的格式化提取
          if (FLEN == 64) begin
            if (fmt) begin
              // 双精度: 使用 [63:0] 位
              sign_a <= operand_a[63];
              sign_b <= operand_b[63] ^ is_sub;
              exp_a  <= operand_a[62:52];
              exp_b  <= operand_b[62:52];

              is_subnormal_a <= (operand_a[62:52] == 0) && (operand_a[51:0] != 0);
              is_subnormal_b <= (operand_b[62:52] == 0) && (operand_b[51:0] != 0);

              man_a <= (operand_a[62:52] == 0) ?
                       {1'b0, operand_a[51:0]} :
                       {1'b1, operand_a[51:0]};
              man_b <= (operand_b[62:52] == 0) ?
                       {1'b0, operand_b[51:0]} :
                       {1'b1, operand_b[51:0]};

              is_nan_a <= (operand_a[62:52] == 11'h7FF) && (operand_a[51:0] != 0);
              is_nan_b <= (operand_b[62:52] == 11'h7FF) && (operand_b[51:0] != 0);
              is_inf_a <= (operand_a[62:52] == 11'h7FF) && (operand_a[51:0] == 0);
              is_inf_b <= (operand_b[62:52] == 11'h7FF) && (operand_b[51:0] == 0);
              is_zero_a <= (operand_a[62:0] == 0);
              is_zero_b <= (operand_b[62:0] == 0);
            end else begin
              // 单精度: 使用 [31:0] 位 (NaN-boxed 在 [63:32])
              sign_a <= operand_a[31];
              sign_b <= operand_b[31] ^ is_sub;
              exp_a  <= {3'b000, operand_a[30:23]};
              exp_b  <= {3'b000, operand_b[30:23]};

              is_subnormal_a <= (operand_a[30:23] == 0) && (operand_a[22:0] != 0);
              is_subnormal_b <= (operand_b[30:23] == 0) && (operand_b[22:0] != 0);

              man_a <= (operand_a[30:23] == 0) ?
                       {1'b0, operand_a[22:0], 29'b0} :
                       {1'b1, operand_a[22:0], 29'b0};
              man_b <= (operand_b[30:23] == 0) ?
                       {1'b0, operand_b[22:0], 29'b0} :
                       {1'b1, operand_b[22:0], 29'b0};

              is_nan_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] != 0);
              is_nan_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] != 0);
              is_inf_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] == 0);
              is_inf_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] == 0);
              is_zero_a <= (operand_a[30:0] == 0);
              is_zero_b <= (operand_b[30:0] == 0);
            end
          end else begin
            // FLEN=32: 始终为单精度
            sign_a <= operand_a[31];
            sign_b <= operand_b[31] ^ is_sub;
            exp_a  <= {3'b000, operand_a[30:23]};
            exp_b  <= {3'b000, operand_b[30:23]};

            is_subnormal_a <= (operand_a[30:23] == 0) && (operand_a[22:0] != 0);
            is_subnormal_b <= (operand_b[30:23] == 0) && (operand_b[22:0] != 0);

            man_a <= (operand_a[30:23] == 0) ?
                     {1'b0, operand_a[22:0], 29'b0} :
                     {1'b1, operand_a[22:0], 29'b0};
            man_b <= (operand_b[30:23] == 0) ?
                     {1'b0, operand_b[22:0], 29'b0} :
                     {1'b1, operand_b[22:0], 29'b0};

            is_nan_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] != 0);
            is_nan_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] != 0);
            is_inf_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] == 0);
            is_inf_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] == 0);
            is_zero_a <= (operand_a[30:0] == 0);
            is_zero_b <= (operand_b[30:0] == 0);
          end
        end

        // ============================================================
        // ALIGN：对齐尾数，通过移位较小的操作数
        // ============================================================
        ALIGN: begin
          `ifdef DEBUG_FPU
          $display("[FP_ADDER] ALIGN: sign_a=%b sign_b=%b exp_a=%h exp_b=%h man_a=%h man_b=%h",
                   sign_a, sign_b, exp_a, exp_b, man_a, man_b);
          `endif
          // 先处理特殊情况
          if (is_nan_a || is_nan_b) begin
            // NaN 传播: 返回基于格式的规范 NaN
            if (FLEN == 64 && fmt_latched)
              result <= 64'h7FF8000000000000;  // 双精度规范 NaN
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, 32'h7FC00000};  // 单精度规范 NaN (NaN-boxed)
            else
              result <= 32'h7FC00000;  // FLEN=32 单精度规范 NaN
            flag_nv <= 1'b1;  // 无效操作
            flag_nx <= 1'b0;  // 清除特殊情况的非精确标志
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // 标记为特殊情况
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] NaN 检测到，返回规范 NaN");
            `endif
          end else if (is_inf_a && is_inf_b && (sign_a != sign_b)) begin
            // ∞ - ∞: 无效
            if (FLEN == 64 && fmt_latched)
              result <= 64'h7FF8000000000000;  // 双精度规范 NaN
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, 32'h7FC00000};  // 单精度规范 NaN (NaN-boxed)
            else
              result <= 32'h7FC00000;  // FLEN=32 单精度规范 NaN
            flag_nv <= 1'b1;
            flag_nx <= 1'b0;  // 清除无效操作的非精确标志
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // 标记为特殊情况
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] Inf - Inf 检测到，无效操作");
            `endif
          end else if (is_inf_a) begin
            // a 为 ∞: 返回 a (精确结果，无异常)
            if (FLEN == 64 && fmt_latched)
              result <= {sign_a, 11'h7FF, 52'h0};  // 双精度 ∞
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_a, 8'hFF, 23'h0};  // 单精度 ∞ (NaN-boxed)
            else
              result <= {sign_a, 8'hFF, 23'h0};  // FLEN=32 单精度 ∞
            flag_nv <= 1'b0;
            flag_nx <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // 标记为特殊情况
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] 操作数 A 是无穷大，返回无穷大");
            `endif
          end else if (is_inf_b) begin
            // b 为 ∞: 返回 b (精确结果，无异常)
            if (FLEN == 64 && fmt_latched)
              result <= {sign_b, 11'h7FF, 52'h0};  // 双精度 ∞
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_b, 8'hFF, 23'h0};  // 单精度 ∞ (NaN-boxed)
            else
              result <= {sign_b, 8'hFF, 23'h0};  // FLEN=32 单精度 ∞
            flag_nv <= 1'b0;
            flag_nx <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // 标记为特殊情况
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] 操作数 B 是无穷大，返回无穷大");
            `endif
          end else if (is_zero_a && is_zero_b) begin
            // 0 + 0: 符号取决于舍入模式和操作数符号 (精确结果)
            sign_result <= (sign_a && sign_b) || ((sign_a || sign_b) && (rounding_mode == 3'b010));
            result <= {sign_result, {FLEN-1{1'b0}}};
            flag_nv <= 1'b0;
            flag_nx <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // 标记为特殊情况
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] 两个操作数都是零，返回零");
            `endif
          end else if (is_zero_a) begin
            // a 为 0: 返回 b (精确结果)
            // 针对格式的结果组装
            if (FLEN == 64 && fmt_latched)
              result <= {sign_b, exp_b, man_b[51:0]};  // 双精度: 52 位尾数
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_b, exp_b[7:0], man_b[51:29]};  // 单精度: 23 位尾数 (NaN-boxed)
            else
              result <= {sign_b, exp_b[7:0], man_b[51:29]};  // FLEN=32 单精度: 23 位尾数
            flag_nv <= 1'b0;
            flag_nx <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // 标记为特殊情况
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] 操作数 A 是零，返回操作数 B");
            `endif
          end else if (is_zero_b) begin
            // b 为 0: 返回 a (精确结果)
            // 针对格式的结果组装
            if (FLEN == 64 && fmt_latched)
              result <= {sign_a, exp_a, man_a[51:0]};  // 双精度: 52 位尾数
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_a, exp_a[7:0], man_a[51:29]};  // 单精度: 23 位尾数 (NaN-boxed)
            else
              result <= {sign_a, exp_a[7:0], man_a[51:29]};  // FLEN=32 单精度: 23 位尾数
            flag_nv <= 1'b0;
            flag_nx <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            special_case_handled <= 1'b1;  // 标记为特殊情况
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] 操作数 B 是零，返回操作数 A");
            `endif
          end else begin
            // 正常情况: 对齐尾数
            if (exp_a >= exp_b) begin
              exp_result <= exp_a;
              exp_diff <= exp_a - exp_b;
              aligned_man_a <= {man_a, 3'b000};  // 添加 GRS 位
              // 右移较小的尾数
              if (exp_a - exp_b > (MAN_WIDTH + 4))
                aligned_man_b <= {{MAN_WIDTH+4{1'b0}}, 1'b1};  // 全部移出 -> sticky
              else
                aligned_man_b <= ({man_b, 3'b000} >> (exp_a - exp_b));
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] ALIGN: exp_diff=%d, aligned_man_a=%h, aligned_man_b=%h (shifted)",
                       exp_a - exp_b, {man_a, 3'b000}, ({man_b, 3'b000} >> (exp_a - exp_b)));
              `endif
            end else begin
              exp_result <= exp_b;
              exp_diff <= exp_b - exp_a;
              aligned_man_b <= {man_b, 3'b000};
              if (exp_b - exp_a > (MAN_WIDTH + 4))
                aligned_man_a <= {{MAN_WIDTH+4{1'b0}}, 1'b1};
              else
                aligned_man_a <= ({man_a, 3'b000} >> (exp_b - exp_a));
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] ALIGN: exp_diff=%d, aligned_man_a=%h (shifted), aligned_man_b=%h",
                       exp_b - exp_a, ({man_a, 3'b000} >> (exp_b - exp_a)), {man_b, 3'b000});
              `endif
            end
          end
        end

        // ============================================================
        // COMPUTE: 根据符号进行加法或减法
        // ============================================================
        COMPUTE: begin
          if (sign_a == sign_b) begin
            // 相同符号: 相加绝对值
            sum <= aligned_man_a + aligned_man_b;
            sign_result <= sign_a;
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] COMPUTE: ADD aligned_man_a=%h + aligned_man_b=%h = %h",
                     aligned_man_a, aligned_man_b, aligned_man_a + aligned_man_b);
            `endif
          end else begin
            // 不同符号: 相减绝对值
            if (aligned_man_a >= aligned_man_b) begin
              sum <= aligned_man_a - aligned_man_b;
              sign_result <= sign_a;
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] COMPUTE: SUB aligned_man_a=%h - aligned_man_b=%h = %h",
                       aligned_man_a, aligned_man_b, aligned_man_a - aligned_man_b);
              `endif
            end else begin
              sum <= aligned_man_b - aligned_man_a;
              sign_result <= sign_b;
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] COMPUTE: SUB aligned_man_b=%h - aligned_man_a=%h = %h",
                       aligned_man_b, aligned_man_a, aligned_man_b - aligned_man_a);
              `endif
            end
          end
        end

        // ============================================================
        // NORMALIZE: 将结果移位到规范化形式
        // ============================================================
        NORMALIZE: begin
          `ifdef DEBUG_FPU
          $display("[FP_ADDER] NORMALIZE: sum=%h exp_result=%h", sum, exp_result);
          `endif

          adjusted_exp <= exp_result;

          // 检查结果是否为零 (针对格式)
          if (sum == 0) begin
            if (FLEN == 64 && fmt_latched)
              result <= {sign_result, 63'b0};  // 双精度零
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_result, 31'b0};  // 单精度零 (NaN-boxed)
            else
              result <= {sign_result, 31'b0};  // FLEN=32 单精度零
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] NORMALIZE: 和是零，返回零");
            `endif
          end
          // 检查溢出 (进位输出)
          else if (sum[MAN_WIDTH+4]) begin
            normalized_man <= sum >> 1;
            adjusted_exp <= exp_result + 1;
            guard <= sum[0];
            round <= 1'b0;
            sticky <= 1'b0;
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] NORMALIZE: 溢出检测到，normalized_man=%h adj_exp=%h",
                     sum >> 1, exp_result + 1);
            `endif
          end
          // 检查前导零 (需要左移)
          else begin
            // 归一化: 左移直到第 MAN_WIDTH+3 位为 1
            // 简单的级联 if-else 优先级编码
            // 对于单精度: MAN_WIDTH+3 = 26, 检查 26 位到 3 位

            // 从 MSB 开始检查每个位
            if (sum[MAN_WIDTH+3]) begin
              // 已归一化 - 第 26 位被设置
              normalized_man <= sum;
              adjusted_exp <= exp_result;
              // 针对格式的 GRS 提取:
              // - 单精度 (FLEN=64, fmt=0): GRS 在 [31:29] 位 (填充边界)
              // - 双精度或 FLEN=32: GRS 在 [2:0] 位 (正常位置)
              if (FLEN == 64 && !fmt_latched) begin
                guard <= sum[31];
                round <= sum[30];
                sticky <= |sum[29:0];  // OR 其余所有位
              end else begin
                guard <= sum[2];
                round <= sum[1];
                sticky <= sum[0];
              end
              `ifdef DEBUG_FPU
              if (FLEN == 64 && !fmt_latched)
                $display("[FP_ADDER] NORMALIZE: 已归一化（单精度），normalized_man=%h adj_exp=%h GRS=%b%b%b",
                     sum, exp_result, sum[31], sum[30], |sum[29:0]);
                else
                $display("[FP_ADDER] NORMALIZE: 已归一化，normalized_man=%h adj_exp=%h GRS=%b%b%b",
                     sum, exp_result, sum[2], sum[1], sum[0]);
              `endif
            end else if (sum[MAN_WIDTH+2]) begin
              // 左移 1 位
              normalized_man <= sum << 1;
              adjusted_exp <= exp_result - 1;
              if (FLEN == 64 && !fmt_latched) begin
                guard <= sum[30];
                round <= sum[29];
                sticky <= |sum[28:0];
              end else begin
                guard <= sum[1];
                round <= sum[0];
                sticky <= 1'b0;
              end
              `ifdef DEBUG_FPU
              if (FLEN == 64 && !fmt_latched)
                $display("[FP_ADDER] 归一化: 左移 1 位（单精度），normalized_man=%h adj_exp=%h GRS=%b%b%b",
                     sum << 1, exp_result - 1, sum[30], sum[29], |sum[28:0]);
                else
                $display("[FP_ADDER] 归一化: 左移 1 位，normalized_man=%h adj_exp=%h GRS=%b%b%b",
                     sum << 1, exp_result - 1, sum[1], sum[0], 1'b0);
              `endif
            end else if (sum[MAN_WIDTH+1]) begin
              // 左移 2 位
              normalized_man <= sum << 2;
              adjusted_exp <= exp_result - 2;
              if (FLEN == 64 && !fmt_latched) begin
                guard <= sum[29];
                round <= sum[28];
                sticky <= |sum[27:0];
              end else begin
                guard <= sum[0];
                round <= 1'b0;
                sticky <= 1'b0;
              end
              `ifdef DEBUG_FPU
              if (FLEN == 64 && !fmt_latched)
                $display("[FP_ADDER] NORMALIZE: 左移 2 位（单精度），normalized_man=%h adj_exp=%h GRS=%b%b%b",
                         sum << 2, exp_result - 2, sum[29], sum[28], |sum[27:0]);
              else
                $display("[FP_ADDER] NORMALIZE: 左移 2 位，normalized_man=%h adj_exp=%h GRS=%b%b%b",
                         sum << 2, exp_result - 2, sum[0], 1'b0, 1'b0);
              `endif
            end else begin
              // 需要左移超过 2 位 (少见情况 - 非常小的结果)
              // 目前左移 3 位，未来处理更大移位
              normalized_man <= sum << 3;
              adjusted_exp <= exp_result - 3;
              // 左移 3+ 位后，精度丢失 - GRS 变为 0
              guard <= 1'b0;
              round <= 1'b0;
              sticky <= 1'b0;
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] NORMALIZE: 左移 3 位以上，normalized_man=%h adj_exp=%h GRS=%b%b%b",
                       sum << 3, exp_result - 3, 1'b0, 1'b0, 1'b0);
              `endif
            end
          end

          // 检查溢出 (针对格式)
          if ((FLEN == 64 && fmt_latched && adjusted_exp >= 12'd2047) ||
              (FLEN == 64 && !fmt_latched && adjusted_exp >= 12'd255) ||
              (FLEN == 32 && adjusted_exp >= 12'd255)) begin
            flag_of <= 1'b1;
            // 返回 ±∞ 基于格式
            if (FLEN == 64 && fmt_latched)
              result <= {sign_result, 11'h7FF, 52'h0};  // 双精度 ∞
            else if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_result, 8'hFF, 23'h0};  // 单精度 ∞ (NaN-boxed)
            else
              result <= {sign_result, 8'hFF, 23'h0};  // FLEN=32 单精度 ∞
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] NORMALIZE: 指数溢出，返回无穷大");
            `endif
          end
        end

        // ============================================================
        // ROUND: 应用舍入模式，组装最终结果
        // ============================================================
        ROUND: begin
          // 仅处理正常情况 - 特殊情况已在 ALIGN 阶段处理
          if (!special_case_handled) begin
            `ifdef DEBUG_FPU
            $display("[FP_ADDER] 舍入 输入: G=%b R=%b S=%b LSB=%b (lsb_bit=%b) rmode=%d",
                     guard, round, sticky, normalized_man[3], lsb_bit, rounding_mode);
            `endif

            // 应用舍入 (使用组合逻辑 round_up_comb)
            // 针对格式的结果组装
            if (FLEN == 64 && fmt_latched) begin
              // 双精度: 64 位结果
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] 舍入 (双精度): sign=%b exp=%h man=%h round_up=%b",
                       sign_result, adjusted_exp[10:0], normalized_man[54:3], round_up_comb);
              `endif
              if (round_up_comb) begin
                result <= {sign_result, adjusted_exp[10:0], normalized_man[54:3] + 1'b1};
              end else begin
                result <= {sign_result, adjusted_exp[10:0], normalized_man[54:3]};
              end
            end else if (FLEN == 64 && !fmt_latched) begin
              // 单精度在 64 位寄存器中 (NaN-boxed)
              // 从 [54:32] 位提取尾数 (实际 SP尾数在填充后的位置)
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] 舍入 (单精度/64): sign=%b exp=%h man=%h round_up=%b",
                       sign_result, adjusted_exp[7:0], normalized_man[54:32], round_up_comb);
              `endif
              if (round_up_comb) begin
                result <= {32'hFFFFFFFF, sign_result, adjusted_exp[7:0], normalized_man[54:32] + 1'b1};
              end else begin
                result <= {32'hFFFFFFFF, sign_result, adjusted_exp[7:0], normalized_man[54:32]};
              end
            end else begin
              // FLEN=32: 单精度在 32 位寄存器中
              // 对于 FLEN=32，normalized_man 布局不同 (无填充)
              // 尾数位于 [25:3] 位 (23 位)
              `ifdef DEBUG_FPU
              $display("[FP_ADDER] 舍入 (单精度/32): sign=%b exp=%h man=%h round_up=%b",
                       sign_result, adjusted_exp[7:0], normalized_man[25:3], round_up_comb);
              `endif
              if (round_up_comb) begin
                result <= {sign_result, adjusted_exp[7:0], normalized_man[25:3] + 1'b1};
              end else begin
                result <= {sign_result, adjusted_exp[7:0], normalized_man[25:3]};
              end
            end

            // 设置非精确标志 (仅针对正常情况)
            flag_nx <= guard || round || sticky;
          end
          // else: 特殊情况 - 结果和标志已在 ALIGN 阶段设置
        end

        // ============================================================
        // DONE: 保持结果 (调试宏下打印结果)
        // ============================================================
        DONE: begin
          // 仅保持结果
          `ifdef DEBUG_FPU
          $display("[FP_ADDER] 结果: %h", result);
          `endif
        end

      endcase
    end
  end

endmodule
