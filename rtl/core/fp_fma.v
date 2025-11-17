// 浮点融合乘加单元
// 实现 FMADD.S/D、FMSUB.S/D、FNMSUB.S/D、FNMADD.S/D 指令
// 符合 IEEE 754-2008，仅进行一次舍入（相对分步运算的关键优势）
// 多周期执行：4-5 个周期

`include "config/rv_config.vh"

module fp_fma #(
  parameter FLEN = `FLEN  // 32：单精度，64：双精度
) (
  input  wire              clk,
  input  wire              reset_n,

  // 控制信号
  input  wire              start,          // 启动运算
  input  wire              fmt,            // 格式：0=单精度，1=双精度
  input  wire [1:0]        fma_op,         // 00: FMADD, 01: FMSUB, 10: FNMSUB, 11: FNMADD
  input  wire [2:0]        rounding_mode,  // IEEE 754 舍入模式
  output reg               busy,           // 运算进行中
  output reg               done,           // 运算完成（1 个周期脉冲）

  // 操作数：(rs1 * rs2) ± rs3
  input  wire [FLEN-1:0]   operand_a,      // rs1（被乘数）
  input  wire [FLEN-1:0]   operand_b,      // rs2（乘数）
  input  wire [FLEN-1:0]   operand_c,      // rs3（加数）

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
  localparam ADD       = 3'b011;
  localparam NORMALIZE = 3'b100;
  localparam ROUND     = 3'b101;
  localparam DONE      = 3'b110;

  reg [2:0] state, next_state;

  // 反规范化后的操作数
  reg sign_a, sign_b, sign_c, sign_prod, sign_result;
  reg [EXP_WIDTH-1:0] exp_a, exp_b, exp_c;
  reg [MAN_WIDTH:0] man_a, man_b, man_c;

  // 特殊值标志
  reg is_nan_a, is_nan_b, is_nan_c;
  reg is_inf_a, is_inf_b, is_inf_c;
  reg is_zero_a, is_zero_b, is_zero_c;

  // 格式锁存
  reg fmt_latched;

  // 与格式相关的 BIAS，用于指数运算
  wire [10:0] bias_val;
  assign bias_val = (FLEN == 64 && !fmt_latched) ? 11'd127 : 11'd1023;

  // 计算
  reg [EXP_WIDTH+1:0] exp_prod;               // 乘积指数
  reg [(2*MAN_WIDTH+3):0] product;            // 乘积尾数（双宽）
  reg [(2*MAN_WIDTH+5):0] aligned_c;          // 对齐后的加数
  reg [(2*MAN_WIDTH+6):0] product_positioned; // 定位后的乘积，用于相加
  reg [(2*MAN_WIDTH+6):0] sum;                // 求和结果
  reg [EXP_WIDTH+1:0] exp_diff;               // 指数差
  reg [EXP_WIDTH-1:0] exp_result;

  // 舍入相关
  reg guard, round, sticky;
  reg round_up;

  // 与格式相关的 LSB，用于 RNE 平分舍入
  // FLEN=64 且单精度时，尾数在高位，LSB 位于 sum[MAN_WIDTH+5+29]
  // 双精度：LSB 位于 sum[3]（尾数在 [54:3]）
  wire lsb_bit_fma;
  assign lsb_bit_fma = (FLEN == 64 && !fmt_latched) ? sum[MAN_WIDTH+5+29] : sum[3];

  // 组合逻辑计算 round_up，用于同一周期
  wire round_up_comb;
  assign round_up_comb = (rounding_mode == 3'b000) ? (guard && (round || sticky || lsb_bit_fma)) :  // RNE：最近偶数
                         (rounding_mode == 3'b010) ? (sign_result && (guard || round || sticky)) :   // RDN：向 -∞
                         (rounding_mode == 3'b011) ? (!sign_result && (guard || round || sticky)) :  // RUP：向 +∞
                         (rounding_mode == 3'b100) ? guard : 1'b0;                                   // RMM 或 RTZ

  // FMA 操作译码
  wire negate_product = fma_op[1];  // FNMSUB、FNMADD 取反乘积
  wire subtract_addend = fma_op[0]; // FMSUB、FNMADD 减加数

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
      MULTIPLY:  next_state = ADD;
      ADD:       next_state = NORMALIZE;
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
      // 初始化工作寄存器以避免 X 传播
      sign_a <= 1'b0;
      sign_b <= 1'b0;
      sign_c <= 1'b0;
      sign_prod <= 1'b0;
      sign_result <= 1'b0;
      exp_a <= {EXP_WIDTH{1'b0}};
      exp_b <= {EXP_WIDTH{1'b0}};
      exp_c <= {EXP_WIDTH{1'b0}};
      man_a <= {(MAN_WIDTH+1){1'b0}};
      man_b <= {(MAN_WIDTH+1){1'b0}};
      man_c <= {(MAN_WIDTH+1){1'b0}};
      is_nan_a <= 1'b0;
      is_nan_b <= 1'b0;
      is_nan_c <= 1'b0;
      is_inf_a <= 1'b0;
      is_inf_b <= 1'b0;
      is_inf_c <= 1'b0;
      is_zero_a <= 1'b0;
      is_zero_b <= 1'b0;
      is_zero_c <= 1'b0;
      exp_prod <= {(EXP_WIDTH+2){1'b0}};
      product <= {(2*MAN_WIDTH+4){1'b0}};
      aligned_c <= {(2*MAN_WIDTH+6){1'b0}};
      sum <= {(2*MAN_WIDTH+7){1'b0}};
      exp_diff <= {(EXP_WIDTH+2){1'b0}};
      exp_result <= {EXP_WIDTH{1'b0}};
      guard <= 1'b0;
      round <= 1'b0;
      sticky <= 1'b0;
      round_up <= 1'b0;
    end else begin
      case (state)

        // ============================================================
        // UNPACK：从 3 个操作数中提取符号、指数和尾数
        // ============================================================
        UNPACK: begin
          // 为整个操作锁存格式
          fmt_latched <= fmt;

          // 针对 FLEN=64 的格式相关提取
          if (FLEN == 64) begin
            if (fmt) begin
              // 双精度：使用 [63:0] 位
              // 操作数 A (rs1)
              sign_a <= operand_a[63];
              exp_a <= operand_a[62:52];
              man_a <= (operand_a[62:52] == 0) ?
                       {1'b0, operand_a[51:0]} :
                       {1'b1, operand_a[51:0]};
              is_nan_a <= (operand_a[62:52] == 11'h7FF) && (operand_a[51:0] != 0);
              is_inf_a <= (operand_a[62:52] == 11'h7FF) && (operand_a[51:0] == 0);
              is_zero_a <= (operand_a[62:0] == 0);

              // 操作数 B (rs2)
              sign_b <= operand_b[63];
              exp_b <= operand_b[62:52];
              man_b <= (operand_b[62:52] == 0) ?
                       {1'b0, operand_b[51:0]} :
                       {1'b1, operand_b[51:0]};
              is_nan_b <= (operand_b[62:52] == 11'h7FF) && (operand_b[51:0] != 0);
              is_inf_b <= (operand_b[62:52] == 11'h7FF) && (operand_b[51:0] == 0);
              is_zero_b <= (operand_b[62:0] == 0);

              // 操作数 C (rs3)
              sign_c <= operand_c[63] ^ subtract_addend;
              exp_c <= operand_c[62:52];
              man_c <= (operand_c[62:52] == 0) ?
                       {1'b0, operand_c[51:0]} :
                       {1'b1, operand_c[51:0]};
              is_nan_c <= (operand_c[62:52] == 11'h7FF) && (operand_c[51:0] != 0);
              is_inf_c <= (operand_c[62:52] == 11'h7FF) && (operand_c[51:0] == 0);
              is_zero_c <= (operand_c[62:0] == 0);
            end else begin
              // 单精度：使用 [31:0] 位（NaN 被包装在 [63:32] 中）
              // 操作数 A (rs1)
              sign_a <= operand_a[31];
              exp_a <= {3'b000, operand_a[30:23]};
              man_a <= (operand_a[30:23] == 0) ?
                       {1'b0, operand_a[22:0], 29'b0} :
                       {1'b1, operand_a[22:0], 29'b0};
              is_nan_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] != 0);
              is_inf_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] == 0);
              is_zero_a <= (operand_a[30:0] == 0);

              // 操作数 B (rs2)
              sign_b <= operand_b[31];
              exp_b <= {3'b000, operand_b[30:23]};
              man_b <= (operand_b[30:23] == 0) ?
                       {1'b0, operand_b[22:0], 29'b0} :
                       {1'b1, operand_b[22:0], 29'b0};
              is_nan_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] != 0);
              is_inf_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] == 0);
              is_zero_b <= (operand_b[30:0] == 0);

              // 操作数 C (rs3)
              sign_c <= operand_c[31] ^ subtract_addend;
              exp_c <= {3'b000, operand_c[30:23]};
              man_c <= (operand_c[30:23] == 0) ?
                       {1'b0, operand_c[22:0], 29'b0} :
                       {1'b1, operand_c[22:0], 29'b0};
              is_nan_c <= (operand_c[30:23] == 8'hFF) && (operand_c[22:0] != 0);
              is_inf_c <= (operand_c[30:23] == 8'hFF) && (operand_c[22:0] == 0);
              is_zero_c <= (operand_c[30:0] == 0);
            end
          end else begin
            // FLEN=32：始终为单精度
            // 操作数 A (rs1)
            sign_a <= operand_a[31];
            exp_a <= {3'b000, operand_a[30:23]};
            man_a <= (operand_a[30:23] == 0) ?
                     {1'b0, operand_a[22:0], 29'b0} :
                     {1'b1, operand_a[22:0], 29'b0};
            is_nan_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] != 0);
            is_inf_a <= (operand_a[30:23] == 8'hFF) && (operand_a[22:0] == 0);
            is_zero_a <= (operand_a[30:0] == 0);

            // 操作数 B (rs2)
            sign_b <= operand_b[31];
            exp_b <= {3'b000, operand_b[30:23]};
            man_b <= (operand_b[30:23] == 0) ?
                     {1'b0, operand_b[22:0], 29'b0} :
                     {1'b1, operand_b[22:0], 29'b0};
            is_nan_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] != 0);
            is_inf_b <= (operand_b[30:23] == 8'hFF) && (operand_b[22:0] == 0);
            is_zero_b <= (operand_b[30:0] == 0);

            // 操作数 C (rs3)
            sign_c <= operand_c[31] ^ subtract_addend;
            exp_c <= {3'b000, operand_c[30:23]};
            man_c <= (operand_c[30:23] == 0) ?
                     {1'b0, operand_c[22:0], 29'b0} :
                     {1'b1, operand_c[22:0], 29'b0};
            is_nan_c <= (operand_c[30:23] == 8'hFF) && (operand_c[22:0] != 0);
            is_inf_c <= (operand_c[30:23] == 8'hFF) && (operand_c[22:0] == 0);
            is_zero_c <= (operand_c[30:0] == 0);
          end
        end

        // ============================================================
        // MULTIPLY：计算乘积 (rs1 * rs2)
        // ============================================================
        MULTIPLY: begin
          // 处理特殊情况
          if (is_nan_a || is_nan_b || is_nan_c) begin
            // NaN 传播
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, 32'h7FC00000};
            else if (FLEN == 64 && fmt_latched)
              result <= 64'h7FF8000000000000;
            else
              result <= 32'h7FC00000;
            flag_nv <= 1'b1;
            state <= DONE;
          end else if ((is_inf_a && is_zero_b) || (is_zero_a && is_inf_b)) begin
            // 0 × ∞：非法
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, 32'h7FC00000};
            else if (FLEN == 64 && fmt_latched)
              result <= 64'h7FF8000000000000;
            else
              result <= 32'h7FC00000;
            flag_nv <= 1'b1;
            state <= DONE;
          end else if ((is_inf_a || is_inf_b) && is_inf_c &&
                       ((sign_a ^ sign_b ^ negate_product) != sign_c)) begin
            // ∞ + (-∞)：非法
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, 32'h7FC00000};
            else if (FLEN == 64 && fmt_latched)
              result <= 64'h7FF8000000000000;
            else
              result <= 32'h7FC00000;
            flag_nv <= 1'b1;
            state <= DONE;
          end else if (is_inf_a || is_inf_b || is_inf_c) begin
            // 结果为 ±∞
            if (is_inf_c)
              sign_result <= sign_c;
            else
              sign_result <= sign_a ^ sign_b ^ negate_product;
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_result, 8'hFF, 23'h0};
            else if (FLEN == 64 && fmt_latched)
              result <= {sign_result, 11'h7FF, 52'h0};
            else
              result <= {sign_result, 8'hFF, 23'h0};
            state <= DONE;
          end else if ((is_zero_a || is_zero_b) && is_zero_c) begin
            // 0 + 0
            sign_result <= (sign_a ^ sign_b ^ negate_product) && sign_c;
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_result, 31'h0};
            else if (FLEN == 64 && fmt_latched)
              result <= {sign_result, 63'h0};
            else
              result <= {sign_result, 31'h0};
            state <= DONE;
          end else if (is_zero_a || is_zero_b) begin
            // 乘积为 0，返回加数
            `ifdef DEBUG_FPU
            $display("[FMA_SPECIAL] Product is zero, returning addend: sign_c=%b exp_c=%h man_c=%h", sign_c, exp_c, man_c);
            `endif
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_c, exp_c[7:0], man_c[51:29]};
            else if (FLEN == 64 && fmt_latched)
              result <= {sign_c, exp_c[10:0], man_c[51:0]};
            else
              result <= {sign_c, exp_c[7:0], man_c[51:29]};
            state <= DONE;
          end else if (is_zero_c) begin
            // 加数为 0，仅返回乘积
            `ifdef DEBUG_FPU
            $display("[FMA_SPECIAL] Addend is zero, computing product only");
            `endif
            sign_prod <= sign_a ^ sign_b ^ negate_product;
            exp_prod <= exp_a + exp_b - bias_val;
            // 仅存储 48 位乘积——在 ADD 阶段再定位
            product <= man_a * man_b;
          end else begin
            // 正常乘法
            sign_prod <= sign_a ^ sign_b ^ negate_product;
            // 仅存储 48 位乘积——在 ADD 阶段再定位
            product <= man_a * man_b;
            exp_prod <= exp_a + exp_b - bias_val;
          end
        end

        // ============================================================
        // ADD：对乘积与加数相加（单一舍入点）
        // ============================================================
        ADD: begin
          `ifdef DEBUG_FPU
          $display("[FMA_ADD_START] exp_prod=%d exp_c=%d man_c=%h product=%h",
                   exp_prod, exp_c, man_c, product);
          `endif

          // 按指数对齐操作数
          // product 为 48 位（man_a * man_b）
          // man_c 为 24 位
          // 策略：将两者都放入 53 位加法寄存器中，并按各自指数对齐
          //
          // 关键要点：乘积和加数必须对齐，使得在指数相等时，
          // 它们的隐藏 1 位在 sum 寄存器中的位置相同。
          // 当指数不同，较小指数一方右移对齐。
          //
          // 中间计算使用阻塞赋值（=）
          //
          // 对于 FLEN=64：man_c 为 53 位，最高有效位在位置 52
          // 在对乘积做 (>>53) 定位后，乘积的最高有效位大约在位置 51
          // 因此 man_c 也需要被定位，使其最高有效位大约在位置 51
          //
          // 策略：以相似方式定位 man_c —— 先左移到 bit 51，然后再应用 exp_diff

          if (exp_prod >= exp_c) begin
            exp_result = exp_prod;
            exp_diff = exp_prod - exp_c;

            // 乘积具有更大的指数，因此它设置了参考位置
            // man_c 需要在相同的参考位置对齐，然后根据 exp_diff 右移
            if (exp_diff > (2*MAN_WIDTH + 6))
              aligned_c = {1'b0, {(2*MAN_WIDTH+5){1'b0}}, 1'b1};  // 仅保留粘滞位
            else begin
              // 对于 FLEN=64：
              // - 双精度：man_c[52] 是最高位，但乘积在定位后最高位在 55
              //   因此我们需要将 man_c 左移 3 位，然后右移 exp_diff：净效果是左移 (3-exp_diff)
              //   实际上更简单：将 man_c 定位与乘积的定位相同，然后右移 exp_diff
              //   乘积定位后最高位在 [~55]，因此 man_c 需要相同的定位
              // - 单精度：man_c[52] 有填充，乘积在 51 → 左移 exp_diff+1
              if (FLEN == 64) begin
                if (fmt_latched)
                  aligned_c = ({man_c, 3'b0} >> exp_diff);  // 双精度：先左移 3 位对齐，然后右移 exp_diff
                else
                  aligned_c = (man_c >> (exp_diff + 1));  // 单精度：乘积低 1 位
              end else
                aligned_c = ({man_c[MAN_WIDTH:0], 28'b0} >> exp_diff);  // FLEN=32 情况
            end
          end else begin
            exp_result = exp_c;
            exp_diff = exp_c - exp_prod;

            // 加数具有更大的指数
            // 相对于加数位置，右移乘积 exp_diff 位
            if (exp_diff > (2*MAN_WIDTH + 6))
              product = {1'b0, {(2*MAN_WIDTH+3){1'b0}}, 1'b1};  // 仅保留粘滞位
            else
              product = product >> exp_diff;

            // 将 man_c 定位到与乘积对齐
            if (FLEN == 64) begin
              if (fmt_latched)
                aligned_c = {man_c, 3'b0};  // 双精度：左移 3 位以匹配乘积在 [55] 的位置
              else
                aligned_c = man_c;  // 单精度：已对齐
            end else
              aligned_c = {man_c, 28'b0};
          end

          // 执行加/减
          // 将乘积定位到和寄存器期望的最高位位置
          //
          // 当 FLEN=64 时，乘积宽度为 (MAN_WIDTH+1) × (MAN_WIDTH+1) = 106 位
          // 对于乘积 >= 2.0 时，其最高有效位在 104 位；对于乘积 < 2.0 时，在 103 位
          //
          // 对于双精度：需要把最高有效位对齐到 [52]，以便从 [51:0] 提取 52 位尾数
          // 对于 FLEN=64 的单精度：需要把最高有效位对齐到 [51]，以便从 [50:28] 提取 23 位尾数
          //
          // 注意：对于单精度与 FLEN=64，尾数有 29 位填充，
          // 但乘法结果的最高位仍在 104-105 位置。

          if (FLEN == 64) begin
            if (fmt_latched) begin
              // 双精度：右移 49 位以将最高位定位到 [55]
              // 这为 [54:3] 提供了 52 位尾数的空间，[2:0] 为 GRS 位
              product_positioned = product >> 49;
            end else begin
              // 单精度：右移 53 位以将最高位定位到 [51]
              product_positioned = product >> 53;
            end
          end else begin
            // FLEN=32：乘积为 48 位（24×24），最高位在 46 位置
            // 左移 5 位以将其定位到 [51]
            product_positioned = product << 5;
          end

          if (sign_prod == sign_c) begin
            // 符号相同：相加幅度
            sum <= product_positioned + aligned_c;
            sign_result <= sign_prod;
          end else begin
            // 符号不同：相减幅度
            if (product_positioned >= aligned_c) begin
              sum <= product_positioned - aligned_c;
              sign_result <= sign_prod;
            end else begin
              sum <= aligned_c - product_positioned;
              sign_result <= sign_c;
            end
          end
          state <= NORMALIZE;
          `ifdef DEBUG_FPU
          $display("[FMA_ADD] product=%h aligned_c=%h exp_result=%d exp_diff=%d",
                   product, aligned_c, exp_result, exp_diff);
          $display("[FMA_ADD] product_positioned=%h sum_will_be=%h",
                   product_positioned, (sign_prod == sign_c) ? (product_positioned + aligned_c) :
                   (product_positioned >= aligned_c) ? (product_positioned - aligned_c) : (aligned_c - product_positioned));
          $display("[FMA_ADD_DEBUG] man_c=%h shift_in=%h shift_amount=%d",
                   man_c, {man_c[MAN_WIDTH:0], 29'b0}, exp_diff);
          `endif
        end

        // ============================================================
        // NORMALIZE：将结果规格化
        // ============================================================
        NORMALIZE: begin
          // 零结果检查
          if (sum == 0) begin
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_result, 31'h0};
            else if (FLEN == 64 && fmt_latched)
              result <= {sign_result, 63'h0};
            else
              result <= {sign_result, 31'h0};
            state <= DONE;
          end
          // 溢出检测：若在规格化位置以外产生进位
          // 双精度：规格化位为 52，对应 sum[55] 为 1
          // 单精度：规格化位为 51
          else if (FLEN == 64 && fmt_latched && sum[56]) begin
            // 双精度溢出
            sum <= sum >> 1;
            exp_result <= exp_result + 1;
            // 移位后，最高位在 [55]，尾数在 [54:3]，[2:0] 为 GRS 位
            guard <= sum[2];
            round <= sum[1];
            sticky <= sum[0];
          end else if (FLEN == 64 && !fmt_latched && sum[52]) begin
            // 单精度溢出
            sum <= sum >> 1;
            exp_result <= exp_result + 1;
            guard <= sum[29];  // 移位后，单精度的守卫位在 29 位
            round <= sum[28];
            sticky <= |sum[27:0];
          end
          // 对于 FLEN=32：检查旧位置的溢出
          else if (FLEN == 32 && sum[(2*MAN_WIDTH+6)]) begin
            sum <= sum >> 1;
            exp_result <= exp_result + 1;
            guard <= sum[0];
            round <= 1'b0;
            sticky <= 1'b0;
          end
          // 检查最高位是否在规格化位置
          // 双精度：最高位在 52
          // 单精度：最高位在 51
          else if (FLEN == 64 && fmt_latched && sum[55]) begin
            // 双精度已规格化 - 最高位在 55 位
            // 尾数在 [54:3]，GRS 在 [2:0] 位
            guard <= sum[2];
            round <= sum[1];
            sticky <= sum[0];
            state <= ROUND;
          end else if (FLEN == 64 && !fmt_latched && sum[51]) begin
            // 单精度已规格化 - 最高位在 51 位
            // sum[50:28] 包含 23 位尾数
            // GRS 在 [27:25] 位
            guard <= sum[27];
            round <= sum[26];
            sticky <= |sum[25:0];
            state <= ROUND;
          end
          // 对于 FLEN=32：检查在 (2*MAN_WIDTH+5) 位的规格化位置
          else if (FLEN == 32 && sum[(2*MAN_WIDTH+5)]) begin
            // FLEN=32 规格化情况
            guard <= sum[MAN_WIDTH+4];
            round <= sum[MAN_WIDTH+3];
            sticky <= |sum[MAN_WIDTH+2:0];
          end
          // 最高位低于规格化位置，则左移（减法后可能发生）
          else begin
            sum <= sum << 1;
            exp_result <= exp_result - 1;
            // 保持在 NORMALIZE 状态以便继续移位（如有必要）
          end

          // 检查溢出
          if (exp_result >= MAX_EXP) begin
            flag_of <= 1'b1;
            flag_nx <= 1'b1;
            if (FLEN == 64 && !fmt_latched)
              result <= {32'hFFFFFFFF, sign_result, 8'hFF, 23'h0};
            else if (FLEN == 64 && fmt_latched)
              result <= {sign_result, 11'h7FF, 52'h0};
            else
              result <= {sign_result, 8'hFF, 23'h0};
            state <= DONE;
          end
        end

        // ============================================================
        // ROUND：应用舍入模式（单次舍入——关键优势）
        // ============================================================
        ROUND: begin
          // 保存 round_up 的寄存版本，便于调试
          round_up <= round_up_comb;

          `ifdef DEBUG_FPU
          if (FLEN == 64 && fmt_latched)
            $display("[FMA_ROUND] sign=%b exp_result=%d sum=%h mantissa_extract=%h (bits [54:3])",
                     sign_result, exp_result, sum, sum[54:3]);
          else if (FLEN == 64 && !fmt_latched)
            $display("[FMA_ROUND] sign=%b exp_result=%d sum=%h mantissa_extract=%h (bits [50:28])",
                     sign_result, exp_result, sum, sum[50:28]);
          else
            $display("[FMA_ROUND] sign=%b exp_result=%d sum=%h mantissa_extract=%h (bits [25:3])",
                     sign_result, exp_result, sum, sum[25:3]);
          $display("[FMA_ROUND_BITS] guard=%b round=%b sticky=%b rounding_mode=%b round_up_comb=%b",
                   guard, round, sticky, rounding_mode, round_up_comb);
          `endif

          // 使用组合计算的 round_up 进行舍入
          // 按格式提取尾数位
          // 双精度：最高位在 52，尾数在 [51:0]
          // 单精度：最高位在 51，尾数在 sum[50:28]
          if (FLEN == 64 && !fmt_latched) begin
            // 单精度在 64 位寄存器中（NaN 被包装）
            // 从 sum[50:28] 中提取 23 位尾数
            // 最高位在 51 位置隐含 1
            if (round_up_comb) begin
              result <= {32'hFFFFFFFF, sign_result, exp_result[7:0],
                         sum[50:28] + 1'b1};
            end else begin
              result <= {32'hFFFFFFFF, sign_result, exp_result[7:0],
                         sum[50:28]};
            end
          end else if (FLEN == 64 && fmt_latched) begin
            // 双精度在 64 位寄存器中
            // 从 sum[54:3] 中提取 52 位尾数
            // 最高位在 55 位置隐含 1
            if (round_up_comb) begin
              result <= {sign_result, exp_result[10:0], sum[54:3] + 1'b1};
            end else begin
              result <= {sign_result, exp_result[10:0], sum[54:3]};
            end
          end else begin
            // FLEN=32：单精度在 32 位寄存器中
            // 提取 23 位尾数
            if (round_up_comb) begin
              result <= {sign_result, exp_result[7:0],
                         sum[25:3] + 1'b1};
            end else begin
              result <= {sign_result, exp_result[7:0],
                         sum[25:3]};
            end
          end

          // 置不精确标志
          flag_nx <= guard || round || sticky;
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
