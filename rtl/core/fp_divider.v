// 浮点除法器
// 实现 FDIV.S/D 指令
// 符合 IEEE 754-2008，采用 SRT 基 2 除法算法
// 多周期执行：16-32 个周期（取决于 FLEN）

`include "config/rv_config.vh"

module fp_divider #(
  parameter FLEN = `FLEN  // 32：单精度，64：双精度
) (
  input  wire              clk,
  input  wire              reset_n,

  // 控制信号
  input  wire              start,          // 启动运算
  input  wire              fmt,            // 格式：0=单精度，1=双精度
  input  wire [2:0]        rounding_mode,  // IEEE 754 舍入模式
  output reg               busy,           // 运算进行中
  output reg               done,           // 运算完成（1 个周期脉冲）

  // 操作数
  input  wire [FLEN-1:0]   operand_a,      // 被除数
  input  wire [FLEN-1:0]   operand_b,      // 除数

  // 结果
  output reg  [FLEN-1:0]   result,

  // 异常标志
  output reg               flag_nv,        // 非法操作
  output reg               flag_dz,        // 被零除
  output reg               flag_of,        // 上溢
  output reg               flag_uf,        // 下溢
  output reg               flag_nx         // 不精确
);

  // IEEE 754 格式参数
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;
  localparam BIAS = (FLEN == 32) ? 127 : 1023;
  localparam MAX_EXP = (FLEN == 32) ? 255 : 2047;
  localparam DIV_CYCLES = MAN_WIDTH + 4;  // 所需迭代次数

  // 状态机
  localparam IDLE      = 3'b000;
  localparam UNPACK    = 3'b001;
  localparam DIVIDE    = 3'b010;
  localparam NORMALIZE = 3'b011;
  localparam ROUND     = 3'b100;
  localparam DONE      = 3'b101;

  reg [2:0] state, next_state;

  // 反规范化后的操作数
  reg sign_a, sign_b, sign_result;
  reg [EXP_WIDTH-1:0] exp_a, exp_b;
  reg [MAN_WIDTH:0] man_a, man_b;  // +1 位用于隐含的最高位 1

  // 特殊值标志
  reg is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;
  reg special_case_handled;  // 标记特殊情况是否已经处理
  reg fmt_latched;  // 锁存的格式信号

  // 与格式相关的 BIAS，用于指数运算
  wire [10:0] bias_val;
  assign bias_val = (FLEN == 64 && !fmt_latched) ? 11'd127 : 11'd1023;

  // 除法计算（SRT 基 2）
  reg [MAN_WIDTH+3:0] quotient;        // 商结果
  reg [MAN_WIDTH+5:0] remainder;       // 当前余数
  reg [MAN_WIDTH+5:0] divisor_shifted; // 对齐后的除数，用于比较
  reg [5:0] div_counter;               // 迭代计数器
  reg [EXP_WIDTH+1:0] exp_diff;        // 指数差
  reg [EXP_WIDTH-1:0] exp_result;

  // 舍入相关
  reg guard, round, sticky;
  reg lsb_bit;  // RNE 平分舍入用的 LSB 锁存

  // 组合逻辑计算 round_up（在 ROUND 状态中使用）
  reg round_up_comb;
  always @(*) begin
    case (rounding_mode)
      3'b000: round_up_comb = guard && (round || sticky || lsb_bit);  // RNE：最近偶数
      3'b001: round_up_comb = 1'b0;                                    // RTZ：向零舍入
      3'b010: round_up_comb = sign_result && (guard || round || sticky);  // RDN：向 -∞
      3'b011: round_up_comb = !sign_result && (guard || round || sticky); // RUP：向 +∞
      3'b100: round_up_comb = guard;                                   // RMM：最近，远离 0
      default: round_up_comb = 1'b0;
    endcase
  end

  // 用于 RNE 平分舍入的 LSB（与格式相关）——只在 NORMALIZE 中锁存
  wire lsb_bit_div;
  // FLEN=64 的单精度：商尾数位于 [MAN_WIDTH+3:32]，LSB 在位 32
  // 双精度：商尾数位于 [MAN_WIDTH+3:3]，LSB 在位 3
  assign lsb_bit_div = (FLEN == 64 && !fmt_latched) ? quotient[32] : quotient[3];

  // 调试输出
  `ifdef DEBUG_FPU_DIVIDER
  always @(posedge clk) begin
    if (state != IDLE || busy || done) begin
      $display("[FDIV_STATE] t=%0t state=%d next=%d busy=%b done=%b counter=%0d special=%b",
               $time, state, next_state, busy, done, div_counter, special_case_handled);
    end

    if (state == DIVIDE && div_counter <= 3) begin
      $display("[FDIV_ITER] t=%0t counter=%0d quo=0x%h rem=0x%h div=0x%h cmp=%b",
               $time, div_counter, quotient, remainder, divisor_shifted,
               remainder >= divisor_shifted);
    end

    if (state == UNPACK) begin
      $display("[FDIV_UNPACK] t=%0t a=0x%h b=0x%h", $time, operand_a, operand_b);
      $display("[FDIV_UNPACK] special: nan_a=%b nan_b=%b inf_a=%b inf_b=%b zero_a=%b zero_b=%b",
               is_nan_a || (operand_a[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}} && operand_a[MAN_WIDTH-1:0] != 0),
               is_nan_b || (operand_b[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}} && operand_b[MAN_WIDTH-1:0] != 0),
               is_inf_a || (operand_a[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}} && operand_a[MAN_WIDTH-1:0] == 0),
               is_inf_b || (operand_b[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}} && operand_b[MAN_WIDTH-1:0] == 0),
               is_zero_a || (operand_a[FLEN-2:0] == 0),
               is_zero_b || (operand_b[FLEN-2:0] == 0));
    end

    if (state == DIVIDE && div_counter == DIV_CYCLES) begin
      $display("[FDIV_INIT] t=%0t exp_diff=%0d rem=0x%h (width=%0d) div=0x%h (width=%0d)",
               $time, exp_diff, remainder, $bits(remainder), divisor_shifted, $bits(divisor_shifted));
      $display("[FDIV_INIT] man_a=0x%h man_b=0x%h", man_a, man_b);
    end

    if (next_state == NORMALIZE && state == DIVIDE) begin
      $display("[FDIV_PRENORM] t=%0t quo=0x%h rem=0x%h", $time, quotient, remainder);
    end

    if (state == NORMALIZE) begin
      $display("[FDIV_NORM] t=%0t quo=0x%h exp_diff=%0d exp_res=%0d",
               $time, quotient, exp_diff, exp_result);
    end

    if (state == ROUND) begin
      $display("[FDIV_ROUND] t=%0t quo[bits]=0x%h g=%b r=%b s=%b lsb=%b rm=%d round_up=%b",
               $time, quotient[MAN_WIDTH+2:3], guard, round, sticky, lsb_bit, rounding_mode, round_up_comb);
    end

    if (state == DONE) begin
      $display("[FDIV_DONE] t=%0t result=0x%h flags=nv:%b dz:%b of:%b uf:%b nx:%b",
               $time, result, flag_nv, flag_dz, flag_of, flag_uf, flag_nx);
    end
  end
  `endif

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
      UNPACK:    next_state = DIVIDE;
      // 在完成所有 DIV_CYCLES 次迭代后跳转（计数器：DIV_CYCLES-1 → 0）
      // 当计数器到 0 时执行最后一次迭代，然后跳转
      // 特殊情况通过数据通路中的状态赋值直接跳到 DONE
      DIVIDE:    next_state = (div_counter == 6'd0) ? NORMALIZE : DIVIDE;
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
      flag_dz <= 1'b0;
      flag_of <= 1'b0;
      flag_uf <= 1'b0;
      flag_nx <= 1'b0;
      div_counter <= 6'd0;
      special_case_handled <= 1'b0;
      // 初始化工作寄存器以避免 X 传播
      quotient <= {(MAN_WIDTH+4){1'b0}};
      remainder <= {(MAN_WIDTH+6){1'b0}};
      divisor_shifted <= {(MAN_WIDTH+6){1'b0}};
      exp_diff <= {(EXP_WIDTH+2){1'b0}};
      exp_result <= {EXP_WIDTH{1'b0}};
      sign_a <= 1'b0;
      sign_b <= 1'b0;
      sign_result <= 1'b0;
      exp_a <= {EXP_WIDTH{1'b0}};
      exp_b <= {EXP_WIDTH{1'b0}};
      man_a <= {(MAN_WIDTH+1){1'b0}};
      man_b <= {(MAN_WIDTH+1){1'b0}};
      is_nan_a <= 1'b0;
      is_nan_b <= 1'b0;
      is_inf_a <= 1'b0;
      is_inf_b <= 1'b0;
      is_zero_a <= 1'b0;
      is_zero_b <= 1'b0;
      guard <= 1'b0;
      round <= 1'b0;
      sticky <= 1'b0;
      lsb_bit <= 1'b0;
    end else begin
      case (state)

        // ============================================================
        // UNPACK：提取符号、指数、尾数
        // ============================================================
        UNPACK: begin
          // 锁存格式信号
          fmt_latched <= fmt;

            // 针对 FLEN=64 的格式感知提取
            if (FLEN == 64) begin
            if (fmt) begin
              // 双精度：使用位 [63:0]
              sign_a <= operand_a[63];
              sign_b <= operand_b[63];
              sign_result <= operand_a[63] ^ operand_b[63];
              exp_a  <= operand_a[62:52];
              exp_b  <= operand_b[62:52];

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
              // 单精度：使用位 [31:0]（NaN 被包装在 [63:32] 中）
              sign_a <= operand_a[31];
              sign_b <= operand_b[31];
              sign_result <= operand_a[31] ^ operand_b[31];
              exp_a  <= {3'b000, operand_a[30:23]};
              exp_b  <= {3'b000, operand_b[30:23]};

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
            // FLEN=32：始终为单精度
            sign_a <= operand_a[31];
            sign_b <= operand_b[31];
            sign_result <= operand_a[31] ^ operand_b[31];
            exp_a  <= {3'b000, operand_a[30:23]};
            exp_b  <= {3'b000, operand_b[30:23]};

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

          // 初始化除法计数器
          div_counter <= DIV_CYCLES;

          // 清除新运算的特殊情况标志
          special_case_handled <= 1'b0;

          // 处理特殊情况（在下一个状态检查，便于时序）
        end

        // ============================================================
        // DIVIDE：迭代 SRT 基 2 除法
        // ============================================================
        DIVIDE: begin
          if (div_counter == DIV_CYCLES) begin
            // 特殊情况处理
            if (is_nan_a || is_nan_b) begin
              // NaN 传播
              if (FLEN == 64 && !fmt_latched)
                result <= {32'hFFFFFFFF, 32'h7FC00000};  // 单精度 NaN（NaN-boxed）
              else if (FLEN == 64 && fmt_latched)
                result <= 64'h7FF8000000000000;  // 双精度 NaN
              else
                result <= 32'h7FC00000;  // FLEN=32 单精度 NaN
              flag_nv <= 1'b1;
              flag_dz <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;
              special_case_handled <= 1'b1;
              state <= DONE;
            end else if ((is_inf_a && is_inf_b) || (is_zero_a && is_zero_b)) begin
              // ∞/∞ 或 0/0：非法
              if (FLEN == 64 && !fmt_latched)
                result <= {32'hFFFFFFFF, 32'h7FC00000};  // 单精度 NaN（NaN-boxed）
              else if (FLEN == 64 && fmt_latched)
                result <= 64'h7FF8000000000000;  // 双精度 NaN
              else
                result <= 32'h7FC00000;  // FLEN=32 单精度 NaN
              flag_nv <= 1'b1;
              flag_dz <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;
              special_case_handled <= 1'b1;
              state <= DONE;
            end else if (is_inf_a) begin
              // ∞/x：返回 ±∞
              if (FLEN == 64 && !fmt_latched)
                result <= {32'hFFFFFFFF, sign_result, 8'hFF, 23'h0};  // 单精度 ∞（NaN-boxed）
              else if (FLEN == 64 && fmt_latched)
                result <= {sign_result, 11'h7FF, 52'h0};  // 双精度 ∞
              else
                result <= {sign_result, 8'hFF, 23'h0};  // FLEN=32 单精度 ∞
              flag_nv <= 1'b0;
              flag_dz <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;
              special_case_handled <= 1'b1;
              state <= DONE;
            end else if (is_inf_b) begin
              // x/∞：返回 ±0
              if (FLEN == 64 && !fmt_latched)
                result <= {32'hFFFFFFFF, sign_result, 31'h0};  // 单精度 0（NaN-boxed）
              else if (FLEN == 64 && fmt_latched)
                result <= {sign_result, 63'h0};  // 双精度 0
              else
                result <= {sign_result, 31'h0};  // FLEN=32 单精度 0
              flag_nv <= 1'b0;
              flag_dz <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;
              special_case_handled <= 1'b1;
              state <= DONE;
            end else if (is_zero_a) begin
              // 0/x：返回 ±0
              if (FLEN == 64 && !fmt_latched)
                result <= {32'hFFFFFFFF, sign_result, 31'h0};  // 单精度 0（NaN-boxed）
              else if (FLEN == 64 && fmt_latched)
                result <= {sign_result, 63'h0};  // 双精度 0
              else
                result <= {sign_result, 31'h0};  // FLEN=32 单精度 0
              flag_nv <= 1'b0;
              flag_dz <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;
              special_case_handled <= 1'b1;
              state <= DONE;
            end else if (is_zero_b) begin
              // x/0：被零除，返回 ±∞
              if (FLEN == 64 && !fmt_latched)
                result <= {32'hFFFFFFFF, sign_result, 8'hFF, 23'h0};  // 单精度 ∞（NaN-boxed）
              else if (FLEN == 64 && fmt_latched)
                result <= {sign_result, 11'h7FF, 52'h0};  // 双精度 ∞
              else
                result <= {sign_result, 8'hFF, 23'h0};  // FLEN=32 单精度 ∞
              flag_nv <= 1'b0;
              flag_dz <= 1'b1;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;
              special_case_handled <= 1'b1;
              state <= DONE;
            end else begin
              // 初始化除法
              // 计算指数：exp_a - exp_b + BIAS（与格式相关）
              exp_diff <= exp_a - exp_b + bias_val;

              // 初始化余数 = 被除数（左移对齐）
              // 现在使用 29 位寄存器，最高位补 0
              remainder <= {1'b0, man_a, 4'b0000};

              // 初始化除数（对齐）
              // 现在使用 29 位寄存器，最高位补 0
              divisor_shifted <= {1'b0, man_b, 4'b0000};

              // 初始化商
              quotient <= {(MAN_WIDTH+4){1'b0}};

              // 开始迭代计数
              div_counter <= DIV_CYCLES - 1;
            end
          end else begin
            // SRT 基 2 除法迭代
            // 比较余数与除数
            if (remainder >= divisor_shifted) begin
              // 本位商为 1，减去除数
              quotient <= (quotient << 1) | 1'b1;
              remainder <= (remainder - divisor_shifted) << 1;
            end else begin
              // 本位商为 0，仅移位
              quotient <= quotient << 1;
              remainder <= remainder << 1;
            end

            // 迭代计数器减一
            div_counter <= div_counter - 1;
          end
        end

        // ============================================================
        // NORMALIZE：将商调整为规格化形式
        // ============================================================
        NORMALIZE: begin
          // 商应当在位 MAN_WIDTH+3 处有最高位 1
          // 若没有，则左移并调整指数

          if (quotient[MAN_WIDTH+3]) begin
            // 已经规格化
            exp_result <= exp_diff[EXP_WIDTH-1:0];
            lsb_bit <= lsb_bit_div;  // 锁存 RNE 舍入用的 LSB
            // 格式相关的 GRS 提取：
            // - 单精度（FLEN=64，fmt=0）：GRS 在位 [31:29]（填充边界）
            // - 双精度或 FLEN=32：GRS 在位 [2:0]（正常位置）
            if (FLEN == 64 && !fmt_latched) begin
              guard <= quotient[31];
              round <= quotient[30];
              sticky <= |quotient[29:0] || (remainder != 0);
            end else begin
              guard <= quotient[2];
              round <= quotient[1];
              sticky <= quotient[0] || (remainder != 0);
            end
          end else if (quotient[MAN_WIDTH+2]) begin
            // 左移 1 位
            quotient <= quotient << 1;
            exp_result <= exp_diff - 1;
            // 移位后 LSB 位于当前位 1 的位置（双精度）或 30 位（单精度 FLEN=64）
            lsb_bit <= (FLEN == 64 && !fmt_latched) ? quotient[29] : quotient[1];
            if (FLEN == 64 && !fmt_latched) begin
              guard <= quotient[30];
              round <= quotient[29];
              sticky <= |quotient[28:0] || (remainder != 0);
            end else begin
              guard <= quotient[1];
              round <= quotient[0];
              sticky <= (remainder != 0);  // quotient[0] 被移到 round，无位丢失
            end
          end else begin
            // 需要更大移位（少见情况，简化处理）
            quotient <= quotient << 2;
            exp_result <= exp_diff - 2;
            // 2 位移位后的 LSB
            lsb_bit <= (FLEN == 64 && !fmt_latched) ? quotient[28] : quotient[0];
            if (FLEN == 64 && !fmt_latched) begin
              guard <= quotient[29];
              round <= quotient[28];
              sticky <= |quotient[27:0] || (remainder != 0);
            end else begin
              guard <= quotient[0];
              round <= 1'b0;
              sticky <= remainder != 0;
            end
          end

          // 上溢检查
          if (exp_diff >= MAX_EXP) begin
            flag_of <= 1'b1;
            flag_nx <= 1'b1;
            result <= {sign_result, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
            state <= DONE;
          end
          // 下溢检查
          else if (exp_diff < 1) begin
            flag_uf <= 1'b1;
            flag_nx <= 1'b1;
            result <= {sign_result, {FLEN-1{1'b0}}};
            state <= DONE;
          end
        end

        // ============================================================
        // ROUND：应用舍入模式
        // ============================================================
        ROUND: begin
          // round_up_comb 由 guard、round、sticky、lsb_bit 组合计算
          // 此处无需重新赋值

          // 带上溢处理的舍入
          if (FLEN == 64 && !fmt_latched) begin
            // 单精度在 64 位寄存器中（NaN-boxed）
            if (round_up_comb) begin
              // 检查舍入是否导致尾数上溢（23 位尾数）
              if (quotient[MAN_WIDTH+2:32] == 23'h7FFFFF) begin
                // 尾数上溢：指数加 1，尾数清零
                result <= {32'hFFFFFFFF, sign_result, exp_result[7:0] + 1'b1, 23'h0};
              end else begin
                result <= {32'hFFFFFFFF, sign_result, exp_result[7:0], quotient[MAN_WIDTH+2:32] + 1'b1};
              end
            end else begin
              result <= {32'hFFFFFFFF, sign_result, exp_result[7:0], quotient[MAN_WIDTH+2:32]};
            end
          end else if (FLEN == 64 && fmt_latched) begin
            // 双精度在 64 位寄存器中
            if (round_up_comb) begin
              // 检查舍入是否导致尾数上溢（52 位尾数）
              if (quotient[MAN_WIDTH+2:3] == {MAN_WIDTH{1'b1}}) begin
                // 尾数上溢：指数加 1，尾数清零
                result <= {sign_result, exp_result[10:0] + 1'b1, {MAN_WIDTH{1'b0}}};
              end else begin
                result <= {sign_result, exp_result[10:0], quotient[MAN_WIDTH+2:3] + 1'b1};
              end
            end else begin
              result <= {sign_result, exp_result[10:0], quotient[MAN_WIDTH+2:3]};
            end
          end else begin
            // FLEN=32：单精度在 32 位寄存器中
            if (round_up_comb) begin
              // 检查舍入是否导致尾数上溢（23 位尾数）
              if (quotient[25:3] == 23'h7FFFFF) begin
                // 尾数上溢：指数加 1，尾数清零
                result <= {sign_result, exp_result[7:0] + 1'b1, 23'h0};
              end else begin
                result <= {sign_result, exp_result[7:0], quotient[25:3] + 1'b1};
              end
            end else begin
              result <= {sign_result, exp_result[7:0], quotient[25:3]};
            end
          end

          // 置不精确标志
          flag_nx <= guard || round || sticky;
        end

        // ============================================================
        // DONE：保持结果 1 个周期
        // ============================================================
        DONE: begin
          div_counter <= DIV_CYCLES;  // 为下一次运算复位
        end

      endcase
    end
  end

endmodule
