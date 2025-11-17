// mul_div_unit.v - M 扩展执行单元
// 将乘法和除法单元整合在一起
// 处理所有 M 扩展指令
// 支持 RV32M 和 RV64M 的参数化实现

`include "config/rv_config.vh"

module mul_div_unit #(
  parameter XLEN = `XLEN
)(
  input  wire                clk,
  input  wire                reset_n,

  // 控制接口
  input  wire                start,        // 启动运算
  input  wire  [3:0]         operation,    // M 扩展指令操作码
  input  wire                is_word_op,   // RV64: W 后缀指令

  // 数据接口
  input  wire  [XLEN-1:0]    operand_a,
  input  wire  [XLEN-1:0]    operand_b,
  output wire  [XLEN-1:0]    result,

  // 状态
  output wire                busy,         // 运算进行中
  output wire                ready         // 结果准备好
);

  // M 扩展操作编码（对应 funct3）
  localparam OP_MUL    = 4'b0000;  // funct3 = 000
  localparam OP_MULH   = 4'b0001;  // funct3 = 001
  localparam OP_MULHSU = 4'b0010;  // funct3 = 010
  localparam OP_MULHU  = 4'b0011;  // funct3 = 011
  localparam OP_DIV    = 4'b0100;  // funct3 = 100
  localparam OP_DIVU   = 4'b0101;  // funct3 = 101
  localparam OP_REM    = 4'b0110;  // funct3 = 110
  localparam OP_REMU   = 4'b0111;  // funct3 = 111

  // 解码操作类型
  wire is_mul = (operation[3:2] == 2'b00);  // MUL, MULH, MULHSU, MULHU
  wire is_div = (operation[3:2] == 2'b01);  // DIV, DIVU, REM, REMU

  // 锁存操作数并将 start 信号延迟一个周期
  // 这样可以保证子单元开始工作时操作数已经稳定
  reg [XLEN-1:0] operand_a_reg;
  reg [XLEN-1:0] operand_b_reg;
  reg start_delayed;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      operand_a_reg <= {XLEN{1'b0}};
      operand_b_reg <= {XLEN{1'b0}};
      start_delayed <= 1'b0;
    end else begin
      if (start && !busy) begin
        // 启动新运算时锁存操作数
        operand_a_reg <= operand_a;
        operand_b_reg <= operand_b;
        start_delayed <= 1'b1;
      end else begin
        start_delayed <= 1'b0;
      end
    end
  end

  // 使用延迟后的 start 与锁存的操作数
  wire           start_to_units      = start_delayed;
  wire [XLEN-1:0] operand_a_to_unit  = operand_a_reg;
  wire [XLEN-1:0] operand_b_to_unit  = operand_b_reg;

  // 乘法单元信号
  wire            mul_start;
  wire [1:0]      mul_op;
  wire [XLEN-1:0] mul_result;
  wire            mul_busy;
  wire            mul_ready;

  assign mul_start = start_to_units && is_mul;
  assign mul_op    = operation[1:0];

  mul_unit #(
    .XLEN(XLEN)
  ) mul_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(mul_start),
    .mul_op(mul_op),
    .is_word_op(is_word_op),
    .operand_a(operand_a_to_unit),
    .operand_b(operand_b_to_unit),
    .result(mul_result),
    .busy(mul_busy),
    .ready(mul_ready)
  );

  // 除法单元信号
  wire            div_start;
  wire [1:0]      div_op;
  wire [XLEN-1:0] div_result;
  wire            div_busy;
  wire            div_ready;

  assign div_start = start_to_units && is_div;
  assign div_op    = operation[1:0];

  div_unit #(
    .XLEN(XLEN)
  ) div_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(div_start),
    .div_op(div_op),
    .is_word_op(is_word_op),
    .dividend(operand_a_to_unit),
    .divisor(operand_b_to_unit),
    .result(div_result),
    .busy(div_busy),
    .ready(div_ready)
  );

  // 调试：监控除法运算
  `ifdef DEBUG_DIV
  always @(posedge clk) begin
    if (start && !busy) begin
      $display("[MUL_DIV] Latch: operand_a=%h operand_b=%h", operand_a, operand_b);
    end
    if (div_start) begin
      $display("[MUL_DIV] DIV Start (delayed): op=%b operand_a_reg=%h operand_b_reg=%h",
               div_op, operand_a_to_unit, operand_b_to_unit);
    end
    if (div_ready) begin
      $display("[MUL_DIV] DIV Ready: result=%h", div_result);
    end
  end
  `endif

  // 输出多路选择
  assign result = is_mul ? mul_result : div_result;
  assign busy   = mul_busy || div_busy;
  assign ready  = mul_ready || div_ready;

endmodule
