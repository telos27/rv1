// bus_arbiter.v - 带地址解码的简单总线互联
// 根据地址将 CPU 的存储器请求路由到 DMEM、CLINT 或 UART
// 单周期响应，无流水，组合逻辑路由
// 作者: RV1 项目组
// 日期: 2025-10-26

`include "config/rv_config.vh"

module bus_arbiter #(
  parameter XLEN = `XLEN
) (
  // CPU / 主设备接口
  input  wire             req_valid,
  input  wire [XLEN-1:0]  req_addr,
  input  wire [63:0]      req_wdata,
  input  wire             req_we,
  input  wire [2:0]       req_size,
  output wire             req_ready,
  output wire [63:0]      req_rdata,
  output wire             req_error,

  // DMEM 接口
  output wire             dmem_valid,
  output wire [XLEN-1:0]  dmem_addr,
  output wire [63:0]      dmem_wdata,
  output wire             dmem_we,
  output wire [2:0]       dmem_size,
  input  wire             dmem_ready,
  input  wire [63:0]      dmem_rdata,

  // CLINT 接口（Core-Local Interruptor）
  output wire             clint_valid,
  output wire [15:0]      clint_addr,     // 64KB 区间内的 16 位偏移
  output wire [63:0]      clint_wdata,
  output wire             clint_we,
  output wire [2:0]       clint_size,
  input  wire             clint_ready,
  input  wire [63:0]      clint_rdata,

  // UART 接口（16550 兼容）
  output wire             uart_valid,
  output wire [2:0]       uart_addr,      // 3 位偏移（8 个寄存器）
  output wire [7:0]       uart_wdata,
  output wire             uart_we,
  input  wire             uart_ready,
  input  wire [7:0]       uart_rdata
);

  //==========================================================================
  // 地址解码
  //==========================================================================
  // 内存映射：
  //   0x0200_0000 - 0x0200_FFFF : CLINT（64KB）
  //   0x1000_0000 - 0x1000_0FFF : UART（4KB，只使用前 8 字节）
  //   0x8000_0000 - 0x8000_FFFF : DMEM（64KB）

  wire sel_clint = (req_addr[31:16] == 16'h0200);        // 0x0200_xxxx
  wire sel_uart  = (req_addr[31:12] == 20'h10000);       // 0x1000_0xxx
  wire sel_dmem  = (req_addr[31:28] == 4'h8);            // 0x8xxx_xxxx
  wire sel_none  = !(sel_dmem || sel_clint || sel_uart);

  //==========================================================================
  // 请求路由（组合逻辑）
  //==========================================================================

  // DMEM 路由
  assign dmem_valid = req_valid && sel_dmem;
  assign dmem_addr  = req_addr;
  assign dmem_wdata = req_wdata;
  assign dmem_we    = req_we;
  assign dmem_size  = req_size;

  // CLINT 路由
  assign clint_valid = req_valid && sel_clint;
  assign clint_addr  = req_addr[15:0];           // 取 16 位偏移
  assign clint_wdata = req_wdata;
  assign clint_we    = req_we;
  assign clint_size  = req_size;

  // UART 路由
  assign uart_valid = req_valid && sel_uart;
  assign uart_addr  = req_addr[2:0];             // 取 3 位寄存器偏移
  assign uart_wdata = req_wdata[7:0];            // UART 仅 8 位宽
  assign uart_we    = req_we;

  //==========================================================================
  // 响应复用（组合逻辑）
  //==========================================================================

  // ready 信号（所有从设备均为 1 周期响应）
  assign req_ready = sel_dmem  ? dmem_ready  :
                     sel_clint ? clint_ready :
                     sel_uart  ? uart_ready  :
                     sel_none  ? 1'b0 : 1'b0;

  // 读数据复用
  assign req_rdata = sel_dmem  ? dmem_rdata :
                     sel_clint ? clint_rdata :
                     sel_uart  ? {{56{1'b0}}, uart_rdata} :  // UART 8 位零扩展
                     64'h0;                                   // 默认返回 0

  // 总线错误检测
  // 错误条件：(1) 对无效地址发起有效请求；或 (2) 没有从设备 ready
  assign req_error = sel_none && req_valid;

  //==========================================================================
  // 调试输出（可选）
  //==========================================================================
  `ifdef DEBUG_BUS
  always @(posedge clk) begin
    if (req_valid && req_ready) begin
      if (req_we) begin
        $display("[BUS] WRITE @ 0x%08h = 0x%016h, size=%0d, dev=%s",
                 req_addr, req_wdata, req_size,
                 sel_dmem ? "DMEM" : sel_clint ? "CLINT" : sel_uart ? "UART" : "NONE");
      end else begin
        $display("[BUS] READ  @ 0x%08h = 0x%016h, size=%0d, dev=%s",
                 req_addr, req_rdata, req_size,
                 sel_dmem ? "DMEM" : sel_clint ? "CLINT" : sel_uart ? "UART" : "NONE");
      end
    end
    if (req_error) begin
      $display("[BUS] ERROR: Invalid address 0x%08h", req_addr);
    end
  end
  `endif

endmodule
