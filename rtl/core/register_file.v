// register_file.v - RISC-V 32 个通用寄存器文件
// 实现 32 个通用寄存器，其中 x0 永远为零
// 作者: RV1 项目
// 日期: 2025-10-09
// 更新: 2025-10-10 - 支持参数化 XLEN（32/64 位）

`include "config/rv_config.vh"

module register_file #(
  parameter XLEN = `XLEN  // 寄存器位宽：32 或 64 位
) (
  input  wire             clk,         // 时钟
  input  wire             reset_n,     // 低有效复位
  input  wire [4:0]       rs1_addr,    // 读端口 1 地址
  input  wire [4:0]       rs2_addr,    // 读端口 2 地址
  input  wire [4:0]       rd_addr,     // 写端口地址
  input  wire [XLEN-1:0]  rd_data,     // 写端口数据
  input  wire             rd_wen,      // 写使能
  output wire [XLEN-1:0]  rs1_data,    // 读端口 1 数据
  output wire [XLEN-1:0]  rs2_data     // 读端口 2 数据
);

  // 寄存器数组 (x0-x31)
  // RV32: 32 x 32 位寄存器
  // RV64: 32 x 64 位寄存器
  reg [XLEN-1:0] registers [0:31];

  // 在时钟上升沿进行初始化和写入
  integer i;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // 复位所有寄存器为 0
      for (i = 0; i < 32; i = i + 1) begin
        registers[i] <= {XLEN{1'b0}};
      end
    end else begin
      // 写操作
      if (rd_wen && rd_addr != 5'h0) begin
        // x0 硬连为 0，因此不允许写入
        registers[rd_addr] <= rd_data;
      end
    end
  end

  // 读操作（组合逻辑 + 内部前递）
  // x0 始终读出 0
  // 内部前递：当读的寄存器正好是当前周期要写的寄存器时，直接返回写数据
  assign rs1_data = (rs1_addr == 5'h0) ? {XLEN{1'b0}} :
                    (rd_wen && (rd_addr == rs1_addr) && (rd_addr != 5'h0)) ? rd_data :
                    registers[rs1_addr];
  assign rs2_data = (rs2_addr == 5'h0) ? {XLEN{1'b0}} :
                    (rd_wen && (rd_addr == rs2_addr) && (rd_addr != 5'h0)) ? rd_data :
                    registers[rs2_addr];

  // 调试寄存器写入（追踪 x7/t2 损坏问题）
  `ifdef DEBUG_REG_WRITE
  always @(posedge clk) begin
    if (reset_n && rd_wen && rd_addr != 5'h0) begin
      // 追踪对 x7 (t2) 的写入 —— 被观测到发生损坏的寄存器
      if (rd_addr == 5'd7) begin
        $display("[REG_WRITE] x7 (t2) <= %h", rd_data);
      end
      // 也打印任何写入“损坏模式”数据的情况
      if (rd_data == 32'ha5a5a5a5 || rd_data == 64'ha5a5a5a5a5a5a5a5) begin
        $display("[REG_WRITE_CORRUPT] x%0d <= %h (corruption pattern!)", rd_addr, rd_data);
      end
    end
  end
  `endif

endmodule
