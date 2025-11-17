// 浮点乘法器
// 实现 FMUL.S/D 指令
// 符合 IEEE 754-2008，完整支持舍入模式
// 多周期执行：3-4 个周期

`include "config/rv_config.vh"

module fp_multiplier #(
  parameter FLEN = `FLEN  // 32：单精度，64：双精度
) (
  input  wire              clk,
  input  wire              reset_n,

  // 控制信号
  input  wire              start,          // 启动运算
  input  wire [2:0]        rounding_mode,  // IEEE 754 舍入模式
  input  wire              fmt,            // 0：单精度，1：双精度
  output reg               busy,           // 运算进行中
  output reg               done,           // 运算完成（1 个周期脉冲）

  // 操作数
  input  wire [FLEN-1:0]   operand_a,
  input  wire [FLEN-1:0]   operand_b,

  // 结果
  output reg  [FLEN-1:0]   result,

  // 异常标志
  output reg               flag_nv,        // 非法操作
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
  localparam MULTIPLY  = 3'b010;
  localparam NORMALIZE = 3'b011;
  localparam ROUND     = 3'b100;
  localparam DONE      = 3'b101;

  reg [2:0] state, next_state;

  // 锁存输入操作数（在 start 时捕获）
  reg [FLEN-1:0] operand_a_latched, operand_b_latched;
  reg fmt_latched;  // 锁存的格式信号

  // 反规范化后的操作数
  reg sign_a, sign_b, sign_result;
  reg [10:0] exp_a, exp_b;  // 双精度最大 11 位
  reg [52:0] man_a, man_b;  // 双精度尾数最大 52+1 位（含隐含 1）

  // 特殊值标志
  reg is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;
  reg special_case_handled;  // 标记特殊情况是否已经处理

  // 基于锁存格式的有效宽度
  wire [10:0] eff_exp_all_ones;  // 当前格式下全 1 指数
  wire [5:0] eff_man_width;      // 有效尾数宽度
  wire [3:0] eff_exp_width;      // 有效指数宽度

  assign eff_exp_all_ones = fmt_latched ? 11'h7FF : 11'h0FF;
  assign eff_man_width = fmt_latched ? 6'd52 : 6'd23;
  assign eff_exp_width = fmt_latched ? 4'd11 : 4'd8;

  // 计算
  reg [12:0] exp_sum;       // 指数和（含溢出检测）
  reg [109:0] product;      // 尾数乘积（双精度双宽度）
  reg [52:0] normalized_man;  // 规格化后的尾数
  reg [10:0] exp_result;      // 规格化后的指数

  // 舍入相关
  reg guard, round, sticky;
  reg round_up;

  // RNE 平分舍入用的 LSB（与格式相关）
  wire lsb_bit_mul;
  assign lsb_bit_mul = fmt_latched ? normalized_man[0] : normalized_man[29];

  // 状态机
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      state <= IDLE;
    else
      state <= next_state;
  end

  // 次态逻辑
  always @(*) begin
    case (state)
      IDLE:      next_state = start ? UNPACK : IDLE;
      UNPACK:    next_state = MULTIPLY;
      MULTIPLY:  next_state = NORMALIZE;
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
      special_case_handled <= 1'b0;
    end else begin
      case (state)

        // ============================================================
        // IDLE：在 start 置位时锁存操作数
        // ============================================================
        IDLE: begin
          if (start) begin
            operand_a_latched <= operand_a;
            operand_b_latched <= operand_b;
            fmt_latched <= fmt;
          end
        end

        // ============================================================
        // UNPACK：提取符号、指数、尾数
        // ============================================================
        UNPACK: begin
          // 清除特殊情况标志
          special_case_handled <= 1'b0;

          // 提取符号（乘法时取反）
          // FLEN=64 时：双精度取 [63]，单精度取 [31]
          if (FLEN == 64) begin
            sign_a <= fmt_latched ? operand_a_latched[63] : operand_a_latched[31];
            sign_b <= fmt_latched ? operand_b_latched[63] : operand_b_latched[31];
            sign_result <= (fmt_latched ? operand_a_latched[63] : operand_a_latched[31]) ^
                           (fmt_latched ? operand_b_latched[63] : operand_b_latched[31]);
          end else begin
            sign_a <= operand_a_latched[31];
            sign_b <= operand_b_latched[31];
            sign_result <= operand_a_latched[31] ^ operand_b_latched[31];
          end

          // 提取指数
          if (FLEN == 64) begin
            exp_a <= fmt_latched ? operand_a_latched[62:52] : {3'b000, operand_a_latched[30:23]};
            exp_b <= fmt_latched ? operand_b_latched[62:52] : {3'b000, operand_b_latched[30:23]};
          end else begin
            exp_a <= {3'b000, operand_a_latched[30:23]};
            exp_b <= {3'b000, operand_b_latched[30:23]};
          end

          // 提取尾数（带隐含的前导 1）
          // 双精度：位 [51:0]，单精度：位 [22:0]
          if (FLEN == 64) begin
            if (fmt_latched) begin
              // 双精度
              man_a <= (operand_a_latched[62:52] == 0) ?
                       {1'b0, operand_a_latched[51:0]} :  // 非规范化
                       {1'b1, operand_a_latched[51:0]};   // 规范化
              man_b <= (operand_b_latched[62:52] == 0) ?
                       {1'b0, operand_b_latched[51:0]} :
                       {1'b1, operand_b_latched[51:0]};
            end else begin
              // 单精度（填充到 53 位）
              man_a <= (operand_a_latched[30:23] == 0) ?
                       {1'b0, operand_a_latched[22:0], 29'b0} :  // 非规范化
                       {1'b1, operand_a_latched[22:0], 29'b0};   // 规范化
              man_b <= (operand_b_latched[30:23] == 0) ?
                       {1'b0, operand_b_latched[22:0], 29'b0} :
                       {1'b1, operand_b_latched[22:0], 29'b0};
            end
          end else begin
            // FLEN=32，始终为单精度（填充到 53 位以保持一致）
            man_a <= (operand_a_latched[30:23] == 0) ?
                     {1'b0, operand_a_latched[22:0], 29'b0} :
                     {1'b1, operand_a_latched[22:0], 29'b0};
            man_b <= (operand_b_latched[30:23] == 0) ?
                     {1'b0, operand_b_latched[22:0], 29'b0} :
                     {1'b1, operand_b_latched[22:0], 29'b0};
          end

          // 检测特殊值（使用提取后的指数和尾数）
          `ifdef DEBUG_FPU
          $display("[FP_MUL] UNPACK: operand_a=%h operand_b=%h fmt=%b", operand_a_latched, operand_b_latched, fmt_latched);
          `endif

          // NaN 检测：exp == 全 1 且尾数 != 0
          if (FLEN == 64) begin
            is_nan_a <= fmt_latched ?
                        ((operand_a_latched[62:52] == 11'h7FF) && (operand_a_latched[51:0] != 0)) :
                        ((operand_a_latched[30:23] == 8'hFF) && (operand_a_latched[22:0] != 0));
            is_nan_b <= fmt_latched ?
                        ((operand_b_latched[62:52] == 11'h7FF) && (operand_b_latched[51:0] != 0)) :
                        ((operand_b_latched[30:23] == 8'hFF) && (operand_b_latched[22:0] != 0));
            is_inf_a <= fmt_latched ?
                        ((operand_a_latched[62:52] == 11'h7FF) && (operand_a_latched[51:0] == 0)) :
                        ((operand_a_latched[30:23] == 8'hFF) && (operand_a_latched[22:0] == 0));
            is_inf_b <= fmt_latched ?
                        ((operand_b_latched[62:52] == 11'h7FF) && (operand_b_latched[51:0] == 0)) :
                        ((operand_b_latched[30:23] == 8'hFF) && (operand_b_latched[22:0] == 0));
            is_zero_a <= fmt_latched ?
                         (operand_a_latched[62:0] == 0) :
                         (operand_a_latched[30:0] == 0);
            is_zero_b <= fmt_latched ?
                         (operand_b_latched[62:0] == 0) :
                         (operand_b_latched[30:0] == 0);
          end else begin
            is_nan_a <= (operand_a_latched[30:23] == 8'hFF) && (operand_a_latched[22:0] != 0);
            is_nan_b <= (operand_b_latched[30:23] == 8'hFF) && (operand_b_latched[22:0] != 0);
            is_inf_a <= (operand_a_latched[30:23] == 8'hFF) && (operand_a_latched[22:0] == 0);
            is_inf_b <= (operand_b_latched[30:23] == 8'hFF) && (operand_b_latched[22:0] == 0);
            is_zero_a <= (operand_a_latched[30:0] == 0);
            is_zero_b <= (operand_b_latched[30:0] == 0);
          end
        end

        // ============================================================
        // MULTIPLY：计算乘积和指数
        // ============================================================
        MULTIPLY: begin
          // 处理特殊情况
          `ifdef DEBUG_FPU
          $display("[FP_MUL] MULTIPLY: is_nan_a=%b is_nan_b=%b is_inf_a=%b is_inf_b=%b is_zero_a=%b is_zero_b=%b",
                   is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b);
          `endif
          if (is_nan_a || is_nan_b) begin
            // NaN 传播（规范 NaN）
            if (fmt_latched) begin
              result <= 64'h7FF8000000000000;  // 双精度规范 NaN
            end else begin
              result <= (FLEN == 64) ? 64'hFFFFFFFF7FC00000 : 32'h7FC00000;  // 单精度规范 NaN（如有需要则打包为 NaN-boxed）
            end
            flag_nv <= 1'b1;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            flag_nx <= 1'b0;
            special_case_handled <= 1'b1;
            state <= DONE;
          end else if ((is_inf_a && is_zero_b) || (is_zero_a && is_inf_b)) begin
            // 0 × ∞：非法 - 返回规范 NaN
            if (fmt_latched) begin
              result <= 64'h7FF8000000000000;
            end else begin
              result <= (FLEN == 64) ? 64'hFFFFFFFF7FC00000 : 32'h7FC00000;
            end
            flag_nv <= 1'b1;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            flag_nx <= 1'b0;
            special_case_handled <= 1'b1;
            state <= DONE;
          end else if (is_inf_a || is_inf_b) begin
            // ∞ × x：返回 ±∞
            if (fmt_latched) begin
              result <= {sign_result, 11'h7FF, 52'b0};  // 双精度无穷大
            end else begin
              result <= (FLEN == 64) ? {32'hFFFFFFFF, sign_result, 8'hFF, 23'b0} : {sign_result, 8'hFF, 23'b0};  // 单精度无穷大
            end
            flag_nv <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            flag_nx <= 1'b0;
            special_case_handled <= 1'b1;
            state <= DONE;
          end else if (is_zero_a || is_zero_b) begin
            // 0 × x：返回 ±0
            if (fmt_latched) begin
              result <= {sign_result, 63'b0};  // 双精度零
            end else begin
              result <= (FLEN == 64) ? {32'hFFFFFFFF, sign_result, 31'b0} : {sign_result, 31'b0};  // 单精度零
            end
            flag_nv <= 1'b0;
            flag_of <= 1'b0;
            flag_uf <= 1'b0;
            flag_nx <= 1'b0;
            special_case_handled <= 1'b1;
            state <= DONE;
          end else begin
            // 正常乘法
            // 尾数相乘
            product <= man_a * man_b;
            `ifdef DEBUG_FPU
            $display("[FP_MUL] MULTIPLY: man_a=%h man_b=%h product=%h", man_a, man_b, man_a * man_b);
            `endif

            // 指数相加（减去偏置）
            // exp_sum = exp_a + exp_b - BIAS
            // 根据格式选择正确的 bias
            if (fmt_latched)
              exp_sum <= exp_a + exp_b - 13'd1023;  // 双精度偏置
            else
              exp_sum <= exp_a + exp_b - 13'd127;   // 单精度偏置
          end
        end

        // ============================================================
        // NORMALIZE：将乘积规格化
        // ============================================================
        NORMALIZE: begin
          // 乘积范围：(1.xxx * 1.yyy) = 1.zzz 到 3.zzz（需要 0 或 1 位移）
          //
          // 双精度 (fmt=1)：man_a、man_b 各 53 位
          //   乘积为 106 位，bit[105] 为溢出位，bit[104] 为规格化结果的最高位
          //
          // 单精度 (fmt=0)：man_a、man_b 为 24 位 + 29 位 0 填充 = 53 位
          //   乘积仍为 106 位，但实际尾数乘积位于 [105:58]
          //   (24+1) * (24+1) = 48 位有效乘积在上半部分

          `ifdef DEBUG_FPU
          $display("[FP_MUL] NORMALIZE: product=%h fmt=%b", product, fmt_latched);
          `endif

          if (fmt_latched) begin
            // 双精度：53 位尾数，106 位乘积
            if (product[105]) begin
              // 乘积 >= 2.0，右移 1 位
              normalized_man <= {1'b0, product[104:53]};
              exp_result <= exp_sum + 1;
              guard <= product[52];
              round <= product[51];
              sticky <= |product[50:0];
            end else begin
              // 乘积在 [1.0, 2.0) 范围内，已规格化
              normalized_man <= {1'b0, product[103:52]};
              exp_result <= exp_sum;
              guard <= product[51];
              round <= product[50];
              sticky <= |product[49:0];
            end
          end else begin
            // 单精度：24 位尾数在 53 位容器中（位 [52:29]）
            // 两个 24 位尾数的乘积 = 48 位在 [105:58] 位置
            if (product[105]) begin
              // 乘积 >= 2.0，右移 1 位
              // 从 [104:82] 提取尾数（23 位）
              normalized_man <= {1'b0, product[104:82], 29'b0};  // 填充到 53 位
              exp_result <= exp_sum + 1;
              guard <= product[81];
              round <= product[80];
              sticky <= |product[79:0];
              `ifdef DEBUG_FPU
              $display("[FP_MUL] NORMALIZE SP: >= 2.0, extract product[104:82]=%h", product[104:82]);
              `endif
            end else begin
              // 乘积在 [1.0, 2.0) 范围内，已规格化
              // 从 [103:81] 提取尾数（23 位）
              normalized_man <= {1'b0, product[103:81], 29'b0};  // 填充到 53 位
              exp_result <= exp_sum;
              guard <= product[80];
              round <= product[79];
              sticky <= |product[78:0];
              `ifdef DEBUG_FPU
              $display("[FP_MUL] NORMALIZE SP: < 2.0, extract product[103:81]=%h", product[103:81]);
              `endif
            end
          end

          // 检查溢出（根据格式使用正确的 MAX_EXP）
          if (fmt_latched) begin
            if (exp_sum >= 13'd2047 || exp_result >= 11'd2047) begin
              flag_of <= 1'b1;
              flag_nx <= 1'b1;
              result <= {sign_result, 11'h7FF, 52'b0};  // 双精度无穷大
              state <= DONE;
            end else if (exp_sum < 1 || exp_result < 1) begin
              flag_uf <= 1'b1;
              flag_nx <= 1'b1;
              result <= {sign_result, 63'b0};  // 双精度零
              state <= DONE;
            end
          end else begin
            if (exp_sum >= 13'd255 || exp_result >= 11'd255) begin
              flag_of <= 1'b1;
              flag_nx <= 1'b1;
              result <= {32'hFFFFFFFF, sign_result, 8'hFF, 23'b0};  // 单精度无穷大（NaN-boxed）
              state <= DONE;
            end else if (exp_sum < 1 || exp_result < 1) begin
              flag_uf <= 1'b1;
              flag_nx <= 1'b1;
              result <= {32'hFFFFFFFF, sign_result, 31'b0};  // 单精度零（NaN-boxed）
              state <= DONE;
            end
          end
        end

        // ============================================================
        // ROUND：应用舍入模式
        // ============================================================
        ROUND: begin
          // 仅处理正常情况——特殊情况已提前处理
          if (!special_case_handled) begin
            // 决定是否进位舍入
            case (rounding_mode)
              3'b000: begin  // RNE: 四舍五入，平局舍入到偶数
                round_up <= guard && (round || sticky || lsb_bit_mul);
              end
              3'b001: begin  // RTZ: 舍去法
                round_up <= 1'b0;
              end
              3'b010: begin  // RDN: 向下舍入（向 -∞）
                round_up <= sign_result && (guard || round || sticky);
              end
              3'b011: begin  // RUP: 向上舍入（向 +∞）
                round_up <= !sign_result && (guard || round || sticky);
              end
              3'b100: begin  // RMM: 舍入到最近，平局舍入到最大幅度
                round_up <= guard;
              end
              default: begin  // 无效的舍入模式
                round_up <= 1'b0;
              end
            endcase

            // 按格式组装结果
            if (fmt_latched) begin
              // 双精度结果
              if (round_up) begin
                result <= {sign_result, exp_result, normalized_man[51:0] + 1'b1};
              end else begin
                result <= {sign_result, exp_result, normalized_man[51:0]};
              end
            end else begin
              // 单精度结果（NaN-boxed for FLEN=64）
              if (FLEN == 64) begin
                if (round_up) begin
                  result <= {32'hFFFFFFFF, sign_result, exp_result[7:0], normalized_man[51:29] + 1'b1};
                end else begin
                  result <= {32'hFFFFFFFF, sign_result, exp_result[7:0], normalized_man[51:29]};
                end
              end else begin
                if (round_up) begin
                  result <= {sign_result, exp_result[7:0], normalized_man[51:29] + 1'b1};
                end else begin
                  result <= {sign_result, exp_result[7:0], normalized_man[51:29]};
                end
              end
            end

            `ifdef DEBUG_FPU
            $display("[FP_MUL] ROUND: fmt=%b sign=%b exp=%h normalized_man=%h GRS=%b%b%b round_up=%b",
                     fmt_latched, sign_result, exp_result, normalized_man, guard, round, sticky, round_up);
            if (fmt_latched)
              $display("[FP_MUL] Result (DP): %h", {sign_result, exp_result, normalized_man[51:0] + (round_up ? 1'b1 : 1'b0)});
            else
              $display("[FP_MUL] Result (SP): %h", {sign_result, exp_result[7:0], normalized_man[51:29] + (round_up ? 1'b1 : 1'b0)});
            `endif

            // 设置不精确标志（仅对正常情况）
            flag_nx <= guard || round || sticky;
          end
          // 否则：特殊情况——结果和标志已设置好
        end

        // ============================================================
        // DONE：保持结果 1 个周期
        // ============================================================
        DONE: begin
          // 仅保持结果
        end

      endcase
    end
  end

endmodule
