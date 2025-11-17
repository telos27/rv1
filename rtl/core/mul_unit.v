// mul_unit.v - M 扩展顺序乘法器
// 实现 MUL, MULH, MULHSU, MULHU 指令
// 使用迭代 加法+移位 算法
// 支持 RV32/RV64 的参数化实现

`include "config/rv_config.vh"

module mul_unit #(
  parameter XLEN = `XLEN
)(
  input  wire                clk,
  input  wire                reset_n,

  // 控制接口
  input  wire                start,        // 启动乘法运算
  input  wire  [1:0]         mul_op,       // 操作类型: 00=MUL, 01=MULH, 10=MULHSU, 11=MULHU
  input  wire                is_word_op,   // RV64: W 后缀指令（32 位操作）

  // 数据接口
  input  wire  [XLEN-1:0]    operand_a,    // 被乘数
  input  wire  [XLEN-1:0]    operand_b,    // 乘数
  output reg   [XLEN-1:0]    result,       // 结果

  // 状态
  output wire                busy,         // 运算进行中
  output reg                 ready         // 结果准备好（1 周期脉冲）
);

  // 操作编码
  localparam MUL    = 2'b00;  // 取低 XLEN 位
  localparam MULH   = 2'b01;  // 取高 XLEN 位（有符号 × 有符号）
  localparam MULHSU = 2'b10;  // 取高 XLEN 位（有符号 × 无符号）
  localparam MULHU  = 2'b11;  // 取高 XLEN 位（无符号 × 无符号）

  // 状态机编码
  localparam IDLE      = 2'b00;
  localparam COMPUTE   = 2'b01;
  localparam DONE      = 2'b10;

  reg [1:0] state, state_next;

  // 对 RV64W 操作确定有效运算位宽
  wire [6:0] op_width;
  assign op_width = (XLEN == 64 && is_word_op) ? 7'd32 : XLEN[6:0];

  // 符号处理
  wire op_a_signed, op_b_signed;
  assign op_a_signed = (mul_op == MULH) || (mul_op == MULHSU);
  assign op_b_signed = (mul_op == MULH);

  // 对有符号操作数进行绝对值和符号扩展
  wire [XLEN-1:0] abs_a, abs_b;
  wire sign_a, sign_b;

  generate
    if (XLEN == 64) begin : gen_sign_64
      assign sign_a = is_word_op ? operand_a[31] : operand_a[XLEN-1];
      assign sign_b = is_word_op ? operand_b[31] : operand_b[XLEN-1];
    end else begin : gen_sign_32
      assign sign_a = operand_a[XLEN-1];
      assign sign_b = operand_b[XLEN-1];
    end
  endgenerate

  wire negate_a = op_a_signed && sign_a;
  wire negate_b = op_b_signed && sign_b;

  // 对 W 类型操作进行 32 位掩码并符号扩展
  wire [XLEN-1:0] masked_a, masked_b;
  generate
    if (XLEN == 64) begin : gen_mask_64
      assign masked_a = is_word_op ? {{32{operand_a[31]}}, operand_a[31:0]} : operand_a;
      assign masked_b = is_word_op ? {{32{operand_b[31]}}, operand_b[31:0]} : operand_b;
    end else begin : gen_mask_32
      assign masked_a = operand_a;
      assign masked_b = operand_b;
    end
  endgenerate

  assign abs_a = negate_a ? (~masked_a + 1'b1) : masked_a;
  assign abs_b = negate_b ? (~masked_b + 1'b1) : masked_b;

  // 双倍位宽乘积累加器
  reg [2*XLEN-1:0] product;
  reg [2*XLEN-1:0] multiplicand;
  reg [XLEN-1:0]   multiplier;

  // 周期计数器
  reg [6:0] cycle_count;

  // 结果符号（对有符号运算）
  reg result_negative;

  // 控制寄存
  reg [1:0] op_reg;
  reg       word_op_reg;

  // 临时结果提取寄存器
  reg [XLEN-1:0] extracted_result;

  // 状态机寄存
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state <= IDLE;
    end else begin
      state <= state_next;
    end
  end

  always @(*) begin
    state_next = state;
    case (state)
      IDLE: begin
        if (start) state_next = COMPUTE;
      end

      COMPUTE: begin
        if (cycle_count >= op_width) state_next = DONE;
      end

      DONE: begin
        state_next = IDLE;
      end

      default: state_next = IDLE;
    endcase
  end

  // 数据通路
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      product         <= {(2*XLEN){1'b0}};
      multiplicand    <= {(2*XLEN){1'b0}};
      multiplier      <= {XLEN{1'b0}};
      cycle_count     <= 7'd0;
      ready           <= 1'b0;
      result          <= {XLEN{1'b0}};
      result_negative <= 1'b0;
      op_reg          <= 2'b00;
      word_op_reg     <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          ready <= 1'b0;

          if (start) begin
            // 初始化乘法运算
            product         <= {(2*XLEN){1'b0}};
            multiplicand    <= {{XLEN{1'b0}}, abs_a};
            multiplier      <= abs_b;
            cycle_count     <= 7'd0;
            result_negative <= negate_a ^ negate_b;  // 结果符号 = 两个操作数符号的异或
            op_reg          <= mul_op;
            word_op_reg     <= is_word_op;
          end
        end

        COMPUTE: begin
          // 迭代加法与移位算法
          if (multiplier[0]) begin
            product <= product + multiplicand;
          end

          // 下一个迭代的移位
          multiplicand <= multiplicand << 1;
          multiplier   <= multiplier >> 1;
          cycle_count  <= cycle_count + 1;
        end

        DONE: begin
          ready <= 1'b1;

          // 根据操作类型提取结果
          // 注意：对 W 类型指令，提取后会再进行符号扩展
          case (op_reg)
            MUL: begin
              // 取低 XLEN 位
              if (result_negative) begin
                extracted_result = ~product[XLEN-1:0] + 1'b1;
              end else begin
                extracted_result = product[XLEN-1:0];
              end
            end

            MULH, MULHSU, MULHU: begin
              // 取高 XLEN 位
              if (result_negative && op_reg != MULHU) begin
                // 先对 2*XLEN 位乘积取负，再取高位
                reg [2*XLEN-1:0] neg_product;
                neg_product      = ~product + 1'b1;
                extracted_result = neg_product[2*XLEN-1:XLEN];
              end else begin
                extracted_result = product[2*XLEN-1:XLEN];
              end
            end

            default: extracted_result = product[XLEN-1:0];
          endcase

          // RV64W 指令的符号扩展
          if (XLEN == 64 && word_op_reg) begin
            result <= {{32{extracted_result[31]}}, extracted_result[31:0]};
          end else begin
            result <= extracted_result;
          end
        end

        default: begin
          ready <= 1'b0;
        end
      endcase
    end
  end

  // busy 信号为组合逻辑：只要不在 IDLE 状态即为忙
  // 这样比使用寄存 busy 信号少一个周期的延迟
  assign busy = (state != IDLE);

  // 调试跟踪
  `ifdef DEBUG_MULTIPLIER
  always @(posedge clk) begin
    if (start && state == IDLE) begin
      $display("[MUL_UNIT] START: op=%b (MUL=00,MULH=01,MULHSU=10,MULHU=11), a=0x%h, b=0x%h",
               mul_op, operand_a, operand_b);
      $display("[MUL_UNIT]   abs_a=0x%h, abs_b=0x%h, negate_a=%b, negate_b=%b",
               abs_a, abs_b, negate_a, negate_b);
    end

    if (state == COMPUTE) begin
      if (cycle_count == 0 || cycle_count == 1 || cycle_count >= op_width - 2) begin
        $display("[MUL_UNIT] COMPUTE[%2d]: product=0x%h, multiplicand=0x%h, multiplier=0x%h, mult[0]=%b",
                 cycle_count, product, multiplicand, multiplier, multiplier[0]);
      end
    end

    if (state == DONE) begin
      $display("[MUL_UNIT] DONE: op=%b, result_negative=%b, product=0x%h",
               op_reg, result_negative, product);
      $display("[MUL_UNIT]   product[%d:%d]=0x%h, product[%d:0]=0x%h",
               2*XLEN-1, XLEN, product[2*XLEN-1:XLEN],
               XLEN-1, product[XLEN-1:0]);
      $display("[MUL_UNIT]   result=0x%h, ready=%b", result, ready);

      // 针对 MULHU 的特殊跟踪
      if (op_reg == MULHU) begin
        $display("[MUL_UNIT] *** MULHU SPECIFIC: expected upper bits, got result=0x%h ***", result);
        $display("[MUL_UNIT]     If result equals operand_a (0x%h), THIS IS THE BUG!", operand_a);
      end
    end

    if (state != state_next) begin
      $display("[MUL_UNIT] STATE: %s -> %s",
               state == IDLE ? "IDLE" : state == COMPUTE ? "COMPUTE" : "DONE",
               state_next == IDLE ? "IDLE" : state_next == COMPUTE ? "COMPUTE" : "DONE");
    end
  end
  `endif

endmodule
