// pc.v - RISC-V 程序计数器
// 保存并更新程序计数器
// 作者: RV1 项目
// 日期: 2025-10-09
// 更新: 2025-10-10 - 支持参数化 XLEN（32/64 位）

`include "config/rv_config.vh"

module pc #(
  parameter XLEN = `XLEN,               // PC 位宽：32 或 64 位
  parameter RESET_VECTOR = {XLEN{1'b0}} // 复位向量（默认：0x0）
) (
  input  wire             clk,         // 时钟
  input  wire             reset_n,     // 低有效复位
  input  wire             stall,       // 暂停信号（冻结 PC）
  input  wire [XLEN-1:0]  pc_next,     // 下一个 PC 值
  output reg  [XLEN-1:0]  pc_current   // 当前 PC 值
);

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      pc_current <= RESET_VECTOR;
    end else if (!stall) begin
      pc_current <= pc_next;
    end
    // 当 stall 为高电平时，PC 保持当前值
  end

endmodule
