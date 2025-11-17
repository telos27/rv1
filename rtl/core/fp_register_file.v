// 浮点寄存器文件
// 实现 32 个浮点寄存器（f0-f31）
// 支持 F 扩展（FLEN=32）和 D 扩展（FLEN=64）
// 包含单精度值在双精度寄存器中的 NaN boxing 逻辑

`include "config/rv_config.vh"

module fp_register_file #(
  parameter FLEN = `FLEN  // 32：F 扩展，64：D 扩展
) (
  input  wire              clk,
  input  wire              reset_n,

  // 读端口（3 端口，用于 FMA 指令：rs1 × rs2 + rs3）
  input  wire [4:0]        rs1_addr,
  input  wire [4:0]        rs2_addr,
  input  wire [4:0]        rs3_addr,
  output wire [FLEN-1:0]   rs1_data,
  output wire [FLEN-1:0]   rs2_data,
  output wire [FLEN-1:0]   rs3_data,

  // 写端口
  input  wire              wr_en,
  input  wire [4:0]        rd_addr,
  input  wire [FLEN-1:0]   rd_data,

  // NaN boxing 控制（当 FLEN=64 且写入单精度时）
  input  wire              write_single  // 1：写入单精度，进行 NaN boxing
);

  // 寄存器数组：32 x FLEN 位
  reg [FLEN-1:0] registers [0:31];

  // 带 NaN boxing 的写数据（组合逻辑）
  wire [FLEN-1:0] wr_data_boxed;
  assign wr_data_boxed = (FLEN == 64 && write_single) ? {32'hFFFFFFFF, rd_data[31:0]} : rd_data;

  // 组合读 + 内部前递（3 个独立读端口）
  // 当同一周期读写同一寄存器时，前递写数据
  // 这对 WB 阶段写、ID 阶段读的 FP 载入-使用场景非常关键
  assign rs1_data = (wr_en && (rd_addr == rs1_addr)) ? wr_data_boxed : registers[rs1_addr];
  assign rs2_data = (wr_en && (rd_addr == rs2_addr)) ? wr_data_boxed : registers[rs2_addr];
  assign rs3_data = (wr_en && (rd_addr == rs3_addr)) ? wr_data_boxed : registers[rs3_addr];

  `ifdef DEBUG_FPU
  always @(*) begin
    if (wr_en && (rd_addr == rs1_addr) && rs1_addr != 0) begin
      $display("[FP_REG_FWD] 内部前递 rs1: f%0d = %h (write_data)", rs1_addr, wr_data_boxed);
    end
    if (wr_en && (rd_addr == rs2_addr) && rs2_addr != 0) begin
      $display("[FP_REG_FWD] 内部前递 rs2: f%0d = %h (write_data)", rs2_addr, wr_data_boxed);
    end
    if (wr_en && (rd_addr == rs3_addr) && rs3_addr != 0) begin
      $display("[FP_REG_FWD] 内部前递 rs3: f%0d = %h (write_data)", rs3_addr, wr_data_boxed);
    end
  end
  `endif

  // 时序写
  integer i;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // 复位时将所有寄存器置为 +0.0
      for (i = 0; i < 32; i = i + 1) begin
        registers[i] <= {FLEN{1'b0}};
      end
    end else if (wr_en) begin
      // 带可选 NaN boxing 的写
      registers[rd_addr] <= wr_data_boxed;
      `ifdef DEBUG_FPU
      if (FLEN == 64 && write_single) begin
        $display("[FP_REG] 写 f%0d = %h (NaN-boxed 单精度)", rd_addr, wr_data_boxed);
      end else begin
        $display("[FP_REG] 写 f%0d = %h", rd_addr, wr_data_boxed);
      end
      `endif
    end
  end

  // 注意：不同于整数寄存器文件，f0 不硬连为零
  // 所有浮点寄存器都是通用寄存器

endmodule
