// div_unit.v - M 扩展除法器 (参考 PicoRV32)
// 实现 DIV, DIVU, REM, REMU 指令
// 基于 PicoRV32 经过验证的除法算法
// 参数化以支持 RV32/RV64

`include "config/rv_config.vh"

module div_unit #(
  parameter XLEN = `XLEN
)(
  input  wire                clk,
  input  wire                reset_n,

  // 控制接口
  input  wire                start,        // 开始一次除法
  input  wire  [1:0]         div_op,       // 操作: 00=DIV, 01=DIVU, 10=REM, 11=REMU
  input  wire                is_word_op,   // RV64: W 后缀指令 (32 位)

  // 数据接口
  input  wire  [XLEN-1:0]    dividend,     // 被除数 (操作数 A)
  input  wire  [XLEN-1:0]    divisor,      // 除数   (操作数 B)
  output reg   [XLEN-1:0]    result,       // 商或余数

  // 状态
  output wire                busy,         // 运算进行中
  output reg                 ready         // 结果就绪 (1 个周期脉冲)
);

  // 操作编码
  localparam DIV  = 2'b00;  // 商 (有符号)
  localparam DIVU = 2'b01;  // 商 (无符号)
  localparam REM  = 2'b10;  // 余数 (有符号)
  localparam REMU = 2'b11;  // 余数 (无符号)

  // 符号处理
  wire is_signed_op;
  assign is_signed_op = (div_op == DIV) || (div_op == REM);

  // 提取符号位
  wire sign_dividend, sign_divisor;

  generate
    if (XLEN == 64) begin : gen_sign_64
      assign sign_dividend = is_word_op ? dividend[31] : dividend[XLEN-1];
      assign sign_divisor  = is_word_op ? divisor[31] : divisor[XLEN-1];
    end else begin : gen_sign_32
      assign sign_dividend = dividend[XLEN-1];
      assign sign_divisor  = divisor[XLEN-1];
    end
  endgenerate

  wire negate_dividend = is_signed_op && sign_dividend;
  wire negate_divisor  = is_signed_op && sign_divisor;

  // 对于 word 操作, 只使用低 32 位
  // 有符号操作 (DIV/REM) 做符号扩展; 无符号操作 (DIVU/REMU) 做零扩展
  wire [XLEN-1:0] masked_dividend, masked_divisor;
  generate
    if (XLEN == 64) begin : gen_mask_64
      assign masked_dividend = is_word_op ?
                              (is_signed_op ? {{32{dividend[31]}}, dividend[31:0]} : {{32{1'b0}}, dividend[31:0]}) :
                              dividend;
      assign masked_divisor  = is_word_op ?
                              (is_signed_op ? {{32{divisor[31]}}, divisor[31:0]} : {{32{1'b0}}, divisor[31:0]}) :
                              divisor;
    end else begin : gen_mask_32
      assign masked_dividend = dividend;
      assign masked_divisor  = divisor;
    end
  endgenerate

  wire [XLEN-1:0] abs_dividend = negate_dividend ? (~masked_dividend + 1'b1) : masked_dividend;
  wire [XLEN-1:0] abs_divisor  = negate_divisor  ? (~masked_divisor + 1'b1)  : masked_divisor;

  // 除法寄存器 (PicoRV32 风格算法)
  reg [XLEN-1:0]     dividend_reg;   // 计算过程中保存余数
  reg [2*XLEN-2:0]   divisor_reg;    // 移位后的除数（对于 RV32 为 63 位，参考 PicoRV32）
  reg [XLEN-1:0]     quotient;
  reg [XLEN-1:0]     quotient_msk;   // 当前商位的掩码

  // 控制寄存器
  reg [1:0] op_reg;
  reg       word_op_reg;
  reg       outsign;               // 运算为有符号时的结果符号位
  reg       running;

  // 临时结果寄存器
  reg [XLEN-1:0] extracted_result;

  // 忙信号: running 时为高
  assign busy = running;

  // 数据通路 (PicoRV32 风格算法)
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      dividend_reg  <= {XLEN{1'b0}};
      divisor_reg   <= {(2*XLEN-1){1'b0}};
      quotient      <= {XLEN{1'b0}};
      quotient_msk  <= {XLEN{1'b0}};
      ready         <= 1'b0;
      result        <= {XLEN{1'b0}};
      op_reg        <= 2'b00;
      word_op_reg   <= 1'b0;
      outsign       <= 1'b0;
      running       <= 1'b0;
    end else begin
      // 默认清 ready
      ready <= 1'b0;

      // 启动新一次除法
      if (start && !running) begin
        running      <= 1'b1;
        op_reg       <= div_op;
        word_op_reg  <= is_word_op;

        // 转换为绝对值进行运算 (PicoRV32 风格)
        dividend_reg <= abs_dividend;
        divisor_reg  <= abs_divisor << (XLEN - 1);  // 将除数移位到最高有效位位置（63位寄存器）
        quotient     <= {XLEN{1'b0}};
        quotient_msk <= {1'b1, {(XLEN-1){1'b0}}};  // 从最高有效位开始

        // 计算输出符号（对于 DIV：符号不同且除数不为0，对于 REM：被除数符号）
        if (div_op == DIV)
          outsign <= (sign_dividend != sign_divisor) && (divisor != {XLEN{1'b0}});
        else if (div_op == REM)
          outsign <= sign_dividend;
        else
          outsign <= 1'b0;  // 无符号操作

        `ifdef DEBUG_DIV
        $display("[DIV] 开始: op=%b 被除数=%h (%h) 除数=%h (%h) 符号位=%b",
                 div_op, dividend, abs_dividend, divisor, abs_divisor,
                 (div_op == DIV) ? ((sign_dividend != sign_divisor) && (divisor != {XLEN{1'b0}})) :
                 (div_op == REM) ? sign_dividend : 1'b0);
        `endif
      end
      // 除法计算过程 (当 quotient_msk != 0 时运行)
      else if (quotient_msk != {XLEN{1'b0}} && running) begin
        // PicoRV32 算法: 将除数 (63 位) 与被除数 (32/64 位, 零扩展) 比较
        // Verilog 会自动将 dividend_reg 零扩展后比较
        if (divisor_reg <= dividend_reg) begin
          // 除数适合余数，执行减法并设置商位
          dividend_reg <= dividend_reg - divisor_reg[XLEN-1:0];
          quotient     <= quotient | quotient_msk;

          `ifdef DEBUG_DIV_STEPS
          $display("[DIV_STEP] 除数=%h <= 被除数=%h: 减法, 商掩码=%h -> 商=%h",
                   divisor_reg[XLEN-1:0], dividend_reg, quotient_msk, quotient | quotient_msk);
          `endif
        end else begin
          `ifdef DEBUG_DIV_STEPS
          $display("[DIV_STEP] 除数=%h > 被除数=%h: 跳过, 商掩码=%h",
                   divisor_reg[XLEN-1:0], dividend_reg, quotient_msk);
          `endif
        end

        // 将除数右移，商掩码右移
        divisor_reg  <= divisor_reg >> 1;
        quotient_msk <= quotient_msk >> 1;
      end
      // 除法完成 (quotient_msk 变为 0)
      else if (quotient_msk == {XLEN{1'b0}} && running) begin
        running <= 1'b0;
        ready   <= 1'b1;

        `ifdef DEBUG_DIV
        $display("[DIV] 完成: 商=%h 余数=%h 符号=%b",
                 quotient, dividend_reg, outsign);
        `endif

        // 根据操作类型选择最终结果
        case (op_reg)
          DIV, DIVU: begin
            // 返回商（如果设置了符号位则取反）
            extracted_result = outsign ? (~quotient + 1'b1) : quotient;
          end
          REM, REMU: begin
            // 返回余数（如果设置了符号位则取反）
            extracted_result = outsign ? (~dividend_reg + 1'b1) : dividend_reg;
          end
        endcase

        // RV64W 指令的符号扩展
        if (XLEN == 64 && word_op_reg) begin
          result <= {{32{extracted_result[31]}}, extracted_result[31:0]};
        end else begin
          result <= extracted_result;
        end

        `ifdef DEBUG_DIV
        $display("[DIV] 结果: op=%b result=%h", op_reg,
                 (op_reg == DIV || op_reg == DIVU) ? (outsign ? (~quotient + 1'b1) : quotient) :
                                                      (outsign ? (~dividend_reg + 1'b1) : dividend_reg));
        `endif
      end
    end
  end

endmodule
