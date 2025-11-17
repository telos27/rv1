// simple_bus.v - 简单存储总线互连
// RV1 SoC 外设的基于优先级的地址解码器
// 作者: RV1 项目组
// 日期: 2025-10-27
//
// 内存映射:
//   0x0000_0000 - 0x0000_FFFF: IMEM (64KB) - 通过总线只读，用于 .rodata 拷贝
//   0x0200_0000 - 0x0200_FFFF: CLINT (64KB) - 定时器 + 软件中断
//   0x0C00_0000 - 0x0FFF_FFFF: PLIC (64MB) - 平台级中断控制器
//   0x1000_0000 - 0x1000_0FFF: UART (4KB) - 串口控制台
//   0x8000_0000 - 0x800F_FFFF: DMEM (1MB) - 数据 RAM
//
// 特性:
// - 单主设备（CPU 核心数据端口）
// - 多从设备（CLINT, UART, DMEM）
// - 基于优先级的地址译码
// - 单周期响应（所有外设在 1 个周期内响应）
// - 支持 字节/半字/字/双字 访问

`include "rv_config.vh"

module simple_bus #(
  parameter XLEN = `XLEN
) (
  input  wire             clk,
  input  wire             reset_n,

  //===========================================================================
  // 主设备接口（来自 CPU 核心 - 数据端口）
  //===========================================================================
  input  wire             master_req_valid,
  input  wire [XLEN-1:0]  master_req_addr,
  input  wire [63:0]      master_req_wdata,
  input  wire             master_req_we,
  input  wire [2:0]       master_req_size,     // 0=字节, 1=半字, 2=字, 3=双字
  output reg              master_req_ready,
  output reg  [63:0]      master_req_rdata,

  //===========================================================================
  // 从设备 0: CLINT (核心本地中断控制器)
  //===========================================================================
  output reg              clint_req_valid,
  output reg  [15:0]      clint_req_addr,      // 16 位偏移（64KB 范围）
  output reg  [63:0]      clint_req_wdata,
  output reg              clint_req_we,
  output reg  [2:0]       clint_req_size,
  input  wire             clint_req_ready,
  input  wire [63:0]      clint_req_rdata,

  //===========================================================================
  // 从设备 1: UART (16550 兼容串口控制台)
  //===========================================================================
  output reg              uart_req_valid,
  output reg  [2:0]       uart_req_addr,       // 3 位偏移（8 个寄存器）
  output reg  [7:0]       uart_req_wdata,
  output reg              uart_req_we,
  input  wire             uart_req_ready,
  input  wire [7:0]       uart_req_rdata,

  //===========================================================================
  // 从设备 2: DMEM (数据 RAM)
  //===========================================================================
  output reg              dmem_req_valid,
  output reg  [XLEN-1:0]  dmem_req_addr,
  output reg  [63:0]      dmem_req_wdata,
  output reg              dmem_req_we,
  output reg  [2:0]       dmem_req_size,
  input  wire             dmem_req_ready,
  input  wire [63:0]      dmem_req_rdata,

  //===========================================================================
  // 从设备 3: PLIC (平台级中断控制器)
  //===========================================================================
  output reg              plic_req_valid,
  output reg  [XLEN-1:0]  plic_req_addr,
  output reg  [31:0]      plic_req_wdata,
  output reg              plic_req_we,
  input  wire             plic_req_ready,
  input  wire [31:0]      plic_req_rdata,

  //===========================================================================
  // 从设备 4: IMEM (指令存储器) - 只读，用于数据加载
  //===========================================================================
  output reg              imem_req_valid,
  output reg  [XLEN-1:0]  imem_req_addr,
  input  wire             imem_req_ready,
  input  wire [31:0]      imem_req_rdata
);

  //===========================================================================
  // 地址译码逻辑
  //===========================================================================

  // 定义地址范围（基地址）
  localparam IMEM_BASE  = 32'h0000_0000;
  localparam IMEM_MASK  = 32'hFFFF_0000;   // 64KB 范围
  localparam CLINT_BASE = 32'h0200_0000;
  localparam CLINT_MASK = 32'hFFFF_0000;   // 64KB 范围
  localparam UART_BASE  = 32'h1000_0000;
  localparam UART_MASK  = 32'hFFFF_F000;   // 4KB 范围
  localparam DMEM_BASE  = 32'h8000_0000;
  localparam DMEM_MASK  = 32'hFFF0_0000;   // 1MB 范围 (之前是 64KB - BUG 修复 Session 27)
  localparam PLIC_BASE  = 32'h0C00_0000;
  localparam PLIC_MASK  = 32'hFC00_0000;   // 64MB 范围

  // 设备选择信号
  wire sel_imem;
  wire sel_clint;
  wire sel_uart;
  wire sel_dmem;
  wire sel_plic;
  wire sel_none;

  // 地址匹配（优先级顺序：从最具体到最不具体）
  assign sel_clint = ((master_req_addr & CLINT_MASK) == CLINT_BASE);
  assign sel_uart  = ((master_req_addr & UART_MASK)  == UART_BASE);
  assign sel_plic  = ((master_req_addr & PLIC_MASK)  == PLIC_BASE);
  assign sel_dmem  = ((master_req_addr & DMEM_MASK)  == DMEM_BASE);
  assign sel_imem  = ((master_req_addr & IMEM_MASK)  == IMEM_BASE);
  assign sel_none  = !(sel_clint || sel_uart || sel_plic || sel_dmem || sel_imem);

  //===========================================================================
  // 请求路由到从设备
  //===========================================================================

  always @(*) begin
    // 默认：所有从设备空闲
    imem_req_valid  = 1'b0;
    clint_req_valid = 1'b0;
    uart_req_valid  = 1'b0;
    dmem_req_valid  = 1'b0;
    plic_req_valid  = 1'b0;

    imem_req_addr   = {XLEN{1'b0}};
    clint_req_addr  = 16'h0;
    uart_req_addr   = 3'h0;
    dmem_req_addr   = {XLEN{1'b0}};
    plic_req_addr   = {XLEN{1'b0}};

    clint_req_wdata = 64'h0;
    uart_req_wdata  = 8'h0;
    dmem_req_wdata  = 64'h0;
    plic_req_wdata  = 32'h0;

    clint_req_we    = 1'b0;
    uart_req_we     = 1'b0;
    dmem_req_we     = 1'b0;
    plic_req_we     = 1'b0;

    clint_req_size  = 3'h0;
    dmem_req_size   = 3'h0;

    // 请求路由到从设备
    if (master_req_valid) begin
      if (sel_imem) begin
        imem_req_valid = 1'b1;
        imem_req_addr  = master_req_addr;
        // IMEM 是只读的，忽略写操作
      end else if (sel_clint) begin
        clint_req_valid = 1'b1;
        clint_req_addr  = master_req_addr[15:0];  // 64KB 以内的 16 位偏移量
        clint_req_wdata = master_req_wdata;
        clint_req_we    = master_req_we;
        clint_req_size  = master_req_size;
      end else if (sel_uart) begin
        uart_req_valid = 1'b1;
        uart_req_addr  = master_req_addr[2:0];    // 3 位偏移 (8 个寄存器)
        uart_req_wdata = master_req_wdata[7:0];   // UART 是字节导向的
        uart_req_we    = master_req_we;
        // 注意：UART 总是以字节为单位操作，忽略 req_size
      end else if (sel_plic) begin
        plic_req_valid = 1'b1;
        plic_req_addr  = master_req_addr;         // 全地址 (PLIC 内部进行译码)
        plic_req_wdata = master_req_wdata[31:0];  // PLIC 是字(word)导向的
        plic_req_we    = master_req_we;
        // 注意：PLIC 以 32 位字为单位操作
      end else if (sel_dmem) begin
        dmem_req_valid = 1'b1;
        dmem_req_addr  = master_req_addr;
        dmem_req_wdata = master_req_wdata;
        dmem_req_we    = master_req_we;
        dmem_req_size  = master_req_size;
      end
      // 如果 sel_none，没有从设备被选中 → ready 将为 0，rdata 将为 0
    end
  end

  //===========================================================================
  // 响应从从设备路由
  //===========================================================================

  always @(*) begin
    // 默认：无响应
    master_req_ready = 1'b0;
    master_req_rdata = 64'h0;

    // 从选中的从设备路由响应
    if (sel_imem) begin
      master_req_ready = imem_req_ready;
      master_req_rdata = {32'h0, imem_req_rdata};  // 零扩展 32 位指令到 64 位
    end else if (sel_clint) begin
      master_req_ready = clint_req_ready;
      // CLINT 返回完整的 64 位数据，但我们需要根据访问大小和地址对齐
      // 提取对应的部分（用于地址 +4 偏移的 32 位访问）
      case (master_req_size)
        3'h3: master_req_rdata = clint_req_rdata;  // 64 位：完整值
        3'h2: begin  // 32 位：根据地址[2]提取
          if (master_req_addr[2]) begin
            master_req_rdata = {32'h0, clint_req_rdata[63:32]};  // 高字 (+4 偏移)
            `ifdef DEBUG_BUS
            $display("[BUS] CLINT read @ +4: addr=0x%08h addr[2]=%b clint_data=0x%016h -> master_rdata=0x%016h",
                     master_req_addr, master_req_addr[2], clint_req_rdata, {32'h0, clint_req_rdata[63:32]});
            `endif
          end else begin
            master_req_rdata = {32'h0, clint_req_rdata[31:0]};   // 低字 (+0 偏移)
            `ifdef DEBUG_BUS
            $display("[BUS] CLINT read @ +0: addr=0x%08h addr[2]=%b clint_data=0x%016h -> master_rdata=0x%016h",
                     master_req_addr, master_req_addr[2], clint_req_rdata, {32'h0, clint_req_rdata[31:0]});
            `endif
          end
        end
        3'h1: begin  // 16 位：根据地址[2:1]提取
          case (master_req_addr[2:1])
            2'h0: master_req_rdata = {48'h0, clint_req_rdata[15:0]};
            2'h1: master_req_rdata = {48'h0, clint_req_rdata[31:16]};
            2'h2: master_req_rdata = {48'h0, clint_req_rdata[47:32]};
            2'h3: master_req_rdata = {48'h0, clint_req_rdata[63:48]};
          endcase
        end
        3'h0: begin  // 8 位：根据地址[2:0]提取
          case (master_req_addr[2:0])
            3'h0: master_req_rdata = {56'h0, clint_req_rdata[7:0]};
            3'h1: master_req_rdata = {56'h0, clint_req_rdata[15:8]};
            3'h2: master_req_rdata = {56'h0, clint_req_rdata[23:16]};
            3'h3: master_req_rdata = {56'h0, clint_req_rdata[31:24]};
            3'h4: master_req_rdata = {56'h0, clint_req_rdata[39:32]};
            3'h5: master_req_rdata = {56'h0, clint_req_rdata[47:40]};
            3'h6: master_req_rdata = {56'h0, clint_req_rdata[55:48]};
            3'h7: master_req_rdata = {56'h0, clint_req_rdata[63:56]};
          endcase
        end
        default: master_req_rdata = clint_req_rdata;
      endcase
    end else if (sel_uart) begin
      master_req_ready = uart_req_ready;
      master_req_rdata = {56'h0, uart_req_rdata};  // 零扩展字节到 64 位
    end else if (sel_plic) begin
      master_req_ready = plic_req_ready;
      master_req_rdata = {32'h0, plic_req_rdata};  // 零扩展字到 64 位
    end else if (sel_dmem) begin
      master_req_ready = dmem_req_ready;
      master_req_rdata = dmem_req_rdata;
    end else if (sel_none && master_req_valid) begin
      // 无效地址 → 返回错误响应 (ready=1, data=0)
      // 这允许核心继续执行而不是挂起
      master_req_ready = 1'b1;
      master_req_rdata = 64'h0;
    end
  end

  //===========================================================================
  // 调试监控（可选）
  //===========================================================================

  `ifdef DEBUG_BUS
  always @(posedge clk) begin
    if (master_req_valid) begin
      $display("[BUS] Cycle %0d: addr=0x%08h we=%b size=%0d | sel: clint=%b uart=%b plic=%b dmem=%b imem=%b none=%b",
               $time/10, master_req_addr, master_req_we, master_req_size,
               sel_clint, sel_uart, sel_plic, sel_dmem, sel_imem, sel_none);

      // 显示 CLINT 的地址解码计算
      if (master_req_addr >= 32'h0200_0000 && master_req_addr <= 32'h0200_FFFF) begin
        $display("       CLINT range detected: addr & mask = 0x%08h == base 0x%08h ? %b",
                 master_req_addr & CLINT_MASK, CLINT_BASE, sel_clint);
      end

      if (sel_clint) begin
        $display("  -> CLINT: offset=0x%04h we=%b wdata=0x%016h valid=%b ready=%b",
                 clint_req_addr, clint_req_we, clint_req_wdata, clint_req_valid, clint_req_ready);
      end
      if (sel_uart) begin
        $display("  -> UART: reg=0x%01h data=0x%02h '%c' we=%b valid=%b ready=%b",
                 uart_req_addr, uart_req_wdata,
                 (uart_req_wdata >= 32 && uart_req_wdata < 127) ? uart_req_wdata : 8'h2E,
                 uart_req_we, uart_req_valid, uart_req_ready);
      end
      if (sel_plic) begin
        $display("  -> PLIC: addr=0x%08h valid=%b ready=%b", plic_req_addr, plic_req_valid, plic_req_ready);
      end
      if (sel_dmem) begin
        $display("  -> DMEM: addr=0x%08h valid=%b ready=%b", dmem_req_addr, dmem_req_valid, dmem_req_ready);
      end
      if (sel_imem) begin
        $display("  -> IMEM: addr=0x%08h valid=%b ready=%b", imem_req_addr, imem_req_valid, imem_req_ready);
      end
      if (sel_none) begin
        $display("  -> UNMAPPED ADDRESS! (returning dummy response)");
      end
    end
  end
  `endif

endmodule
