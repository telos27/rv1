// 浮点平方根单元
// 实现 FSQRT.S/D 指令
// 基于数字递推算法，实现 IEEE 754-2008 兼容
// 多周期执行: 16–32 周期 (取决于 FLEN)

`include "config/rv_config.vh"

module fp_sqrt #(
  parameter FLEN = `FLEN  // 32 表示单精度，64 表示双精度
) (
  input  wire              clk,
  input  wire              reset_n,

  // 控制信号
  input  wire              start,          // 启动操作
  input  wire              fmt,            // 格式: 0=单精度, 1=双精度
  input  wire [2:0]        rounding_mode,  // IEEE 754 舍入模式
  output reg               busy,           // 运算进行中
  output reg               done,           // 运算完成 (1 周期脉冲)

  // 操作数
  input  wire [FLEN-1:0]   operand,

  // 结果
  output reg  [FLEN-1:0]   result,

  // 异常标志
  output reg               flag_nv,        // 无效操作 (负数输入)
  output reg               flag_nx         // 不精确
);

  // IEEE 754 格式参数
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;
  localparam BIAS = (FLEN == 32) ? 127 : 1023;
  localparam MAX_EXP = (FLEN == 32) ? 255 : 2047;
  localparam SQRT_CYCLES = (MAN_WIDTH + 4);  // 迭代次数: 需要 MAN_WIDTH+4 位根 (每次迭代 1 位根)

  // 状态机
  localparam IDLE      = 3'b000;
  localparam UNPACK    = 3'b001;
  localparam COMPUTE   = 3'b010;
  localparam NORMALIZE = 3'b011;
  localparam ROUND     = 3'b100;
  localparam DONE      = 3'b101;

  reg [2:0] state, next_state;

  // 解包后的操作数
  reg sign;
  reg [EXP_WIDTH-1:0] exp;
  reg [MAN_WIDTH:0] mantissa;  // +1 位用于隐含的前导 1

  // 特殊值标志
  reg is_nan, is_inf, is_zero, is_negative;

  // 格式锁存
  reg fmt_latched;

  // 基于格式的 BIAS，用于指数运算
  wire [10:0] bias_val;
  assign bias_val = (FLEN == 64 && !fmt_latched) ? 11'd127 : 11'd1023;

  // 平方根计算 (数字递推)
  reg [MAN_WIDTH+3:0] root;          // 平方根结果 (单精度 27 位)
  reg [MAN_WIDTH+5:0] remainder;     // 当前余数 (算法中的 A 寄存器) - 需要 root_width + 2 位
  wire [MAN_WIDTH+5:0] ac;           // 用于从被开方数提取下两个比特的累加器 (组合逻辑)
  wire [MAN_WIDTH+5:0] test_val;     // 测试值: ac - (root<<2 | 1) (组合逻辑)
  wire test_positive;                // 如果 test_val >= 0 则为真
  reg [5:0] sqrt_counter;            // 迭代计数器
  reg [EXP_WIDTH-1:0] exp_result;
  reg exp_is_odd;                    // 如果指数是奇数则为真
  reg [(MAN_WIDTH+4)*2-1:0] radicand_shift;  // 用于比特提取的完整被开方数

  // 组合逻辑: sqrt 迭代 (每周期 2 位, 基 4)
  // 按照 Project F 算法: 每次处理 2 位
  assign ac = (remainder << 2) | radicand_shift[(MAN_WIDTH+4)*2-1:(MAN_WIDTH+4)*2-2];  // 移入 2 位
  assign test_val = ac - {root, 2'b01};  // ac - (root << 2 | 1)
  assign test_positive = (test_val[MAN_WIDTH+5] == 1'b0);  // 检查符号位

  // 舍入
  reg guard, round, sticky;
  reg round_up;

  // 基于格式的 RNE 舍入 LSB 位 (平局处理)
  wire lsb_bit_sqrt;
  assign lsb_bit_sqrt = (FLEN == 64 && !fmt_latched) ? root[32] : root[3];

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
      UNPACK:    next_state = COMPUTE;
      COMPUTE:   next_state = (sqrt_counter == 0) ? NORMALIZE : COMPUTE;
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

  `ifdef DEBUG_FPU_DIVIDER
  always @(posedge clk) begin
    // 当启动信号触发时总是打印
    if (start) begin
      $display("[SQRT_START] t=%0t operand=0x%h", $time, operand);
    end

    // 打印状态变迁
    if (state != next_state) begin
      $display("[SQRT_TRANSITION] t=%0t state=%d->%d", $time, state, next_state);
    end

    // 打印 UNPACK 细节
    if (state == UNPACK) begin
      $display("[SQRT_UNPACK] exp=0x%h mant=0x%h special: nan=%b inf=%b zero=%b neg=%b",
               operand[FLEN-2:MAN_WIDTH],
               (operand[FLEN-2:MAN_WIDTH] == 0) ? {1'b0, operand[MAN_WIDTH-1:0]} : {1'b1, operand[MAN_WIDTH-1:0]},
               (operand[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) && (operand[MAN_WIDTH-1:0] != 0),
               (operand[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) && (operand[MAN_WIDTH-1:0] == 0),
               operand[FLEN-2:0] == 0,
               operand[FLEN-1] && !(operand[FLEN-2:0] == 0));
    end

    // 打印 COMPUTE 初始化
    if (state == COMPUTE && sqrt_counter == SQRT_CYCLES) begin
      $display("[SQRT_INIT] exp=%d exp_odd=%b exp_result=%d radicand_shift=0x%h",
               exp, exp[0],
               exp[0] ? (exp - BIAS) / 2 + BIAS : (exp - BIAS) / 2 + BIAS,
               exp[0] ? {mantissa, 4'b0000, {(MAN_WIDTH+3){1'b0}}} << 1 : {mantissa, 4'b0000, {(MAN_WIDTH+3){1'b0}}});
    end

    // 打印所有迭代以供调试
    if (state == COMPUTE && sqrt_counter != SQRT_CYCLES) begin
      $display("[SQRT_ITER] counter=%0d root=0x%h rem=0x%h radicand=0x%h ac=0x%h test_val=0x%h accept=%b",
               sqrt_counter, root, remainder, radicand_shift, ac, test_val, test_positive);
    end

    // 打印归一化前的最后几次迭代
    if (state == COMPUTE && sqrt_counter <= 3) begin
      $display("[SQRT_LATE] counter=%0d root=0x%h rem=0x%h",
               sqrt_counter, root, remainder);
    end

    // 打印归一化
    if (state == NORMALIZE) begin
      $display("[SQRT_NORM] root=0x%h exp_result=%d GRS=%b%b%b",
               root, exp_result, root[2], root[1], root[0] || (remainder != 0));
    end

    // 打印最终结果
    if (state == DONE || next_state == DONE) begin
      $display("[SQRT_DONE] result=0x%h flags: nv=%b nx=%b", result, flag_nv, flag_nx);
    end
  end
  `endif

  // 主数据通路
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      result <= {FLEN{1'b0}};
      flag_nv <= 1'b0;
      flag_nx <= 1'b0;
      sqrt_counter <= 6'd0;
      // 初始化工作寄存器以防止 X 传播
      root <= {(MAN_WIDTH+4){1'b0}};
      remainder <= {(MAN_WIDTH+6){1'b0}};
      radicand_shift <= {((MAN_WIDTH+4)*2){1'b0}};
      exp_result <= {EXP_WIDTH{1'b0}};
      exp_is_odd <= 1'b0;
      sign <= 1'b0;
      exp <= {EXP_WIDTH{1'b0}};
      mantissa <= {(MAN_WIDTH+1){1'b0}};
      is_nan <= 1'b0;
      is_inf <= 1'b0;
      is_zero <= 1'b0;
      is_negative <= 1'b0;
    end else begin
      case (state)

        // ============================================================
        // UNPACK: 提取符号、指数、尾数
        // ============================================================
        UNPACK: begin
          // 清除新操作的标志
          flag_nv <= 1'b0;
          flag_nx <= 1'b0;

          // 锁存格式以供整个操作使用
          fmt_latched <= fmt;

          // 针对 FLEN=64 的格式感知提取
          if (FLEN == 64) begin
            if (fmt) begin
              // 双精度: 使用 [63:0] 位
              sign <= operand[63];
              exp <= operand[62:52];
              mantissa <= (operand[62:52] == 0) ?
                          {1'b0, operand[51:0]} :
                          {1'b1, operand[51:0]};

              is_nan <= (operand[62:52] == 11'h7FF) && (operand[51:0] != 0);
              is_inf <= (operand[62:52] == 11'h7FF) && (operand[51:0] == 0);
              is_zero <= (operand[62:0] == 0);
              is_negative <= operand[63] && (operand[62:0] != 0);  // -0 是可以接受的
            end else begin
              // 单精度: 使用 [31:0] 位 (NaN 装箱在 [63:32])
              sign <= operand[31];
              exp <= {3'b000, operand[30:23]};
              mantissa <= (operand[30:23] == 0) ?
                          {1'b0, operand[22:0], 29'b0} :
                          {1'b1, operand[22:0], 29'b0};

              is_nan <= (operand[30:23] == 8'hFF) && (operand[22:0] != 0);
              is_inf <= (operand[30:23] == 8'hFF) && (operand[22:0] == 0);
              is_zero <= (operand[30:0] == 0);
              is_negative <= operand[31] && (operand[30:0] != 0);  // -0 是可以接受的
            end
          end else begin
            // FLEN=32: 始终为单精度
            sign <= operand[31];
            exp <= {3'b000, operand[30:23]};
            mantissa <= (operand[30:23] == 0) ?
                        {1'b0, operand[22:0], 29'b0} :
                        {1'b1, operand[22:0], 29'b0};

            is_nan <= (operand[30:23] == 8'hFF) && (operand[22:0] != 0);
            is_inf <= (operand[30:23] == 8'hFF) && (operand[22:0] == 0);
            is_zero <= (operand[30:0] == 0);
            is_negative <= operand[31] && (operand[30:0] != 0);  // -0 是可以接受的
          end

          // 基于格式初始化计数器
          // 需要 SQRT_CYCLES 次迭代以获得全部尾数 + GRS
          sqrt_counter <= SQRT_CYCLES;  // 在 SQRT_CYCLES处开始以便于第一次迭代检查
        end

        // ============================================================
        // COMPUTE: 迭代平方根计算
        // ============================================================
        COMPUTE: begin
          if (sqrt_counter == SQRT_CYCLES) begin
            // 第一次迭代: 特殊情况处理和初始化
            if (is_nan) begin
              // sqrt(NaN) = NaN
              if (FLEN == 64 && !fmt_latched)
                result <= {32'hFFFFFFFF, 32'h7FC00000};  // 单精度 NaN (NaN 装箱)
              else if (FLEN == 64 && fmt_latched)
                result <= 64'h7FF8000000000000;  // 双精度 NaN
              else
                result <= 32'h7FC00000;  // FLEN=32 单精度 NaN
              state <= DONE;
            end else if (is_negative) begin
              // sqrt(负数) = NaN，并置无效标志
              if (FLEN == 64 && !fmt_latched)
                result <= {32'hFFFFFFFF, 32'h7FC00000};  // 单精度 NaN (NaN 装箱)
              else if (FLEN == 64 && fmt_latched)
                result <= 64'h7FF8000000000000;  // 双精度 NaN
              else
                result <= 32'h7FC00000;  // FLEN=32 单精度 NaN
              flag_nv <= 1'b1;
              state <= DONE;
            end else if (is_inf) begin
              // sqrt(+∞) = +∞
              if (FLEN == 64 && !fmt_latched)
                result <= {32'hFFFFFFFF, 1'b0, 8'hFF, 23'h0};  // 单精度 +∞ (NaN 装箱)
              else if (FLEN == 64 && fmt_latched)
                result <= {1'b0, 11'h7FF, 52'h0};  // 双精度 +∞
              else
                result <= {1'b0, 8'hFF, 23'h0};  // FLEN=32 单精度 +∞
              state <= DONE;
            end else if (is_zero) begin
              // sqrt(±0) = ±0 (保持符号)
              if (FLEN == 64 && !fmt_latched)
                result <= {32'hFFFFFFFF, sign, 31'h0};  // 单精度 ±0 (NaN 装箱)
              else if (FLEN == 64 && fmt_latched)
                result <= {sign, 63'h0};  // 双精度 ±0
              else
                result <= {sign, 31'h0};  // FLEN=32 单精度 ±0
              state <= DONE;
            end else begin
              // 初始化数字逐位平方根算法
              // 结果指数: (exp - BIAS) / 2 + BIAS
              exp_is_odd <= exp[0];  // 检查指数是否为奇数

              if (exp[0]) begin
                // 奇数指数: 通过将尾数左移 1 位进行调整
                exp_result <= (exp - bias_val) / 2 + bias_val;
                radicand_shift <= {mantissa, 4'b0000, {(MAN_WIDTH+3){1'b0}}} << 1;
              end else begin
                // 偶数指数: 无需调整
                exp_result <= (exp - bias_val) / 2 + bias_val;
                radicand_shift <= {mantissa, 4'b0000, {(MAN_WIDTH+3){1'b0}}};
              end

              // 初始化数字逐位算法的寄存器
              root <= {(MAN_WIDTH+4){1'b0}};      // Q = 0
              remainder <= {(MAN_WIDTH+6){1'b0}}; // A = 0

              // 开始迭代 (每周期处理 2 位, 基 4)
              // 需要 SQRT_CYCLES 次迭代以计算所有位包括 GRS
              // 递减计数器以开始迭代
              sqrt_counter <= SQRT_CYCLES - 1;
            end
          end else begin
            // 基 4 数字逐位平方根迭代，每周期处理 2 位
            // 按照 Project F 算法: 每次处理 2 位被开方数的比特
            // ac, test_val, 和 test_positive 是组合逻辑计算的

            // 移位被开方数以准备下两个比特
            radicand_shift <= radicand_shift << 2;

            if (test_positive) begin
              // test_val >= 0: 接受该比特 (将根的 LSB 设为 1)
              remainder <= test_val;
              root <= (root << 1) | 1'b1;  // 左移 1 位，LSB 设为 1
            end else begin
              // test_val < 0: 拒绝该比特 (将根的 LSB 设为 0)
              remainder <= ac;
              root <= root << 1;  // 左移 1 位，LSB 保持为 0
            end

            // 递减计数器
            sqrt_counter <= sqrt_counter - 1;
          end
        end

        // ============================================================
        // NORMALIZE: 结果应当已归一化
        // ============================================================
        NORMALIZE: begin
          // 从根中提取 GRS 比特
          // 对于 FLEN=64 的单精度，根在 LSB 处有 29 位填充
          // GRS 必须从 [31:29] 位提取 (而不是 [2:0])
          if (FLEN == 64 && !fmt_latched) begin
            // 单精度: GRS 位位于 [31:29]
            guard <= root[31];
            round <= root[30];
            sticky <= |root[29:0] || (remainder != 0);
          end else begin
            // 双精度: GRS 位位于 [2:0]
            guard <= root[2];
            round <= root[1];
            sticky <= root[0] || (remainder != 0);
          end
        end

        // ============================================================
        // ROUND: 应用舍入模式
        // ============================================================
        ROUND: begin
          // 确定是否需要进位 (组合逻辑计算)
          // 必须在同一周期计算以便使用
          case (rounding_mode)
            3'b000: begin  // RNE: 四舍五入，平局时舍入到偶数
              round_up = guard && (round || sticky || lsb_bit_sqrt);
            end
            3'b001: begin  // RTZ: 向零舍入
              round_up = 1'b0;
            end
            3'b010: begin  // RDN: 向下舍入 (向 -∞)
              round_up = 1'b0;  // sqrt 总是非负
            end
            3'b011: begin  // RUP: 向上舍入 (向 +∞)
              round_up = guard || round || sticky;
            end
            3'b100: begin  // RMM: 四舍五入，平局时舍入到最大幅度
              round_up = guard;
            end
            default: begin
              round_up = 1'b0;
            end
          endcase

          // 应用舍入 (结果总为非负)
          // 根据格式提取尾数
          if (FLEN == 64 && !fmt_latched) begin
            // 64 位寄存器中的单精度 (NaN 装箱)
            if (round_up) begin
              result <= {32'hFFFFFFFF, 1'b0, exp_result[7:0], root[MAN_WIDTH+2:32] + 1'b1};
            end else begin
              result <= {32'hFFFFFFFF, 1'b0, exp_result[7:0], root[MAN_WIDTH+2:32]};
            end
          end else if (FLEN == 64 && fmt_latched) begin
            // 64 位寄存器中的双精度
            if (round_up) begin
              result <= {1'b0, exp_result[10:0], root[MAN_WIDTH+2:3] + 1'b1};
            end else begin
              result <= {1'b0, exp_result[10:0], root[MAN_WIDTH+2:3]};
            end
          end else begin
            // FLEN=32: 32 位寄存器中的单精度
            if (round_up) begin
              result <= {1'b0, exp_result[7:0], root[25:3] + 1'b1};
            end else begin
              result <= {1'b0, exp_result[7:0], root[25:3]};
            end
          end

          // 置不精确标志
          flag_nx <= guard || round || sticky;
        end

        // ============================================================
        // DONE: 保持结果 1 个周期
        // ============================================================
        DONE: begin
          // 重置计数器以备下次操作 (将在 UNPACK 中设置为 SQRT_CYCLES-1)
          sqrt_counter <= 6'd0;
        end

      endcase
    end
  end

endmodule
