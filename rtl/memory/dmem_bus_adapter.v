// dmem_bus_adapter.v - 数据存储器总线适配器
// 将 data_memory 模块适配到 simple_bus 接口
// 作者: RV1 项目组
// 日期: 2025-10-27

`include "config/rv_config.vh"

module dmem_bus_adapter #(
  parameter XLEN     = `XLEN,
  parameter FLEN     = `FLEN,
  parameter MEM_SIZE = 16384,
  parameter MEM_FILE = ""
) (
  input  wire             clk,
  input  wire             reset_n,

  // 总线从设备接口
  input  wire             req_valid,
  input  wire [XLEN-1:0]  req_addr,
  input  wire [63:0]      req_wdata,
  input  wire             req_we,
  input  wire [2:0]       req_size,
  output wire             req_ready,
  output wire [63:0]      req_rdata
);

  // Session 114：寄存器化存储器具有 1 个周期的读延迟
  // - 写：0 周期完成（立即 ready）
  // - 读：1 周期完成（请求被接受的下一个周期 ready）
  // 这与 FPGA BRAM 带寄存器输出的行为一致
  //
  // 协议：
  // 周期 N:   req_valid=1, req_we=0（读请求） → req_ready=0（尚未准备好）
  // 周期 N+1: req_valid=1（仍在请求） → req_ready=1（数据已经准备好）
  //
  // 当 req_ready=0 时，CPU 会停顿一个周期，在 req_ready=1 时继续

  reg read_in_progress_r;

  always @(posedge clk) begin
    if (!reset_n) begin
      read_in_progress_r <= 1'b0;
    end else begin
      // 在接受一个读请求时置位，在数据准备好时清零
      if (req_valid && !req_we && !read_in_progress_r) begin
        // 新的读请求——将会花费 1 个周期
        read_in_progress_r <= 1'b1;
      end else if (read_in_progress_r) begin
        // 读在 1 个周期后完成
        read_in_progress_r <= 1'b0;
      end
    end
  end

  // ready 信号：
  // - 写：总是立即 ready（0 周期延迟）
  // - 读：在第一个周期不 ready（req_valid && !req_we && !read_in_progress）
  //        在第二个周期 ready（read_in_progress_r 为 1）
  assign req_ready = req_we || read_in_progress_r;

  // 实例化数据存储器
  data_memory #(
    .XLEN(XLEN),
    .FLEN(FLEN),
    .MEM_SIZE(MEM_SIZE),
    .MEM_FILE(MEM_FILE)
  ) dmem (
    .clk(clk),
    .addr(req_addr),
    .write_data(req_wdata),
    .mem_read(req_valid && !req_we),
    .mem_write(req_valid && req_we),
    .funct3(req_size),
    .read_data(req_rdata)
  );

endmodule
