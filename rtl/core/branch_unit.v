// branch_unit.v - RISC-V 分支条件判断单元
// 根据 funct3 和操作数判断是否应当跳转
// 作者: RV1 Project
// 日期: 2025-10-09
// 更新: 2025-10-10 - 参数化 XLEN (支持 32/64 位)

`include "config/rv_config.vh"

module branch_unit #(
  parameter XLEN = `XLEN  // 数据宽度: 32 或 64 位
) (
  input  wire [XLEN-1:0]  rs1_data,     // 第一个操作数
  input  wire [XLEN-1:0]  rs2_data,     // 第二个操作数
  input  wire [2:0]       funct3,       // funct3 (分支类型)
  input  wire             branch,       // 分支指令标志
  input  wire             jump,         // 跳转指令标志
  output reg              take_branch   // 是否采纳分支/跳转
);

  // 有符号比较
  wire signed [XLEN-1:0] signed_rs1;
  wire signed [XLEN-1:0] signed_rs2;

  assign signed_rs1 = rs1_data;
  assign signed_rs2 = rs2_data;

  // 分支条件判断
  always @(*) begin
    if (jump) begin
      // JAL 和 JALR 总是跳转
      take_branch = 1'b1;
    end else if (branch) begin
      case (funct3)
        3'b000: take_branch = (rs1_data == rs2_data);           // BEQ
        3'b001: take_branch = (rs1_data != rs2_data);           // BNE
        3'b100: take_branch = (signed_rs1 < signed_rs2);        // BLT
        3'b101: take_branch = (signed_rs1 >= signed_rs2);       // BGE
        3'b110: take_branch = (rs1_data < rs2_data);            // BLTU
        3'b111: take_branch = (rs1_data >= rs2_data);           // BGEU
        default: take_branch = 1'b0;
      endcase
    end else begin
      take_branch = 1'b0;
    end
  end

endmodule
