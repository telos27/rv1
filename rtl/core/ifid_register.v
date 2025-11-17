// IF/ID 流水线寄存器
// 锁存取指阶段的输出供译码阶段使用
// 支持停顿（保持当前值）和清空（插入 NOP 冒泡）
// 更新：2025-10-10 - 按 XLEN 参数化（支持 32/64 位）

`include "config/rv_config.vh"

module ifid_register #(
  parameter XLEN = `XLEN  // PC 位宽：32 或 64 位
) (
  input  wire             clk,
  input  wire             reset_n,
  input  wire             stall,           // 保持当前值（用于 load-use 冒险）
  input  wire             flush,           // 清空为 NOP（用于分支误判）

  // 来自 IF 阶段的输入
  input  wire [XLEN-1:0]  pc_in,
  input  wire [31:0]      instruction_in,  // 指令始终为 32 位
  input  wire             is_compressed_in, // 原始指令是否为压缩指令？
  input  wire             page_fault_in,    // Session 117：指令页错误
  input  wire [XLEN-1:0]  fault_vaddr_in,   // Session 117：产生错误的虚拟地址

  // 输出到 ID 阶段
  output reg  [XLEN-1:0]  pc_out,
  output reg  [31:0]      instruction_out,
  output reg              valid_out,       // 0 = 冒泡（NOP），1 = 有效指令
  output reg              is_compressed_out, // 传递压缩标志
  output reg              page_fault_out,    // Session 117：指令页错误
  output reg  [XLEN-1:0]  fault_vaddr_out   // Session 117：产生错误的虚拟地址
);

  // NOP 指令编码（ADDI x0, x0, 0）
  localparam NOP = 32'h00000013;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // 复位：插入 NOP 冒泡
      pc_out            <= {XLEN{1'b0}};
      instruction_out   <= NOP;
      valid_out         <= 1'b0;
      is_compressed_out <= 1'b0;  // NOP 不是压缩指令
      page_fault_out    <= 1'b0;  // Session 117
      fault_vaddr_out   <= {XLEN{1'b0}};  // Session 117
    end else if (flush) begin
      // 清空：插入 NOP 冒泡（分支被采纳）
      pc_out            <= {XLEN{1'b0}};
      instruction_out   <= NOP;
      valid_out         <= 1'b0;
      is_compressed_out <= 1'b0;  // NOP 不是压缩指令
      page_fault_out    <= 1'b0;  // Session 117：flush 时清除页错误
      fault_vaddr_out   <= {XLEN{1'b0}};  // Session 117
    end else if (stall) begin
      // 停顿：保持当前值（load-use 冒险）
      pc_out            <= pc_out;
      instruction_out   <= instruction_out;
      valid_out         <= valid_out;
      is_compressed_out <= is_compressed_out;
      page_fault_out    <= page_fault_out;  // Session 117
      fault_vaddr_out   <= fault_vaddr_out;  // Session 117
    end else begin
      // 正常工作：锁存新值
      pc_out            <= pc_in;
      instruction_out   <= instruction_in;
      valid_out         <= 1'b1;
      is_compressed_out <= is_compressed_in;
      page_fault_out    <= page_fault_in;  // Session 117
      fault_vaddr_out   <= fault_vaddr_in;  // Session 117
    end
  end

endmodule
