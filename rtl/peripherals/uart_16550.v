// uart_16550.v - 16550 兼容 UART
// 实现 16550 UART 的一个子集，用于串行控制台
// 与标准 16550 驱动程序兼容（Linux、FreeRTOS、xv6）
// 作者：RV1 项目组
// 日期：2025-10-26
//
// 内存映射（基地址：0x1000_0000）：
//   0x00: RBR (读) / THR (写) - 接收缓冲寄存器 / 发送保持寄存器
//   0x01: IER (读写) - 中断使能寄存器
//   0x02: IIR (读) / FCR (写) - 中断标识寄存器 / FIFO 控制寄存器
//   0x03: LCR (读写) - 线路控制寄存器
//   0x04: MCR (读写) - 调制解调器控制寄存器
//   0x05: LSR (读) - 线路状态寄存器
//   0x06: MSR (读) - 调制解调器状态寄存器
//   0x07: SCR (读写) - 暂存寄存器
//
// 特性：
// - 16 字节的 TX/RX FIFO
// - 固定的 8N1 模式（8 数据位，无奇偶校验，1 停止位）
// - 可编程中断使能
// - 用于轮询或中断驱动 I/O 的状态寄存器
// - 字节级仿真（无实际串行时序）

`include "config/rv_config.vh"

module uart_16550 #(
  parameter BASE_ADDR = 32'h1000_0000,    // 基地址（仅供参考）
  parameter FIFO_DEPTH = 16               // TX/RX FIFO 深度
) (
  input  wire        clk,
  input  wire        reset_n,

  // 内存映射接口
  input  wire        req_valid,
  input  wire [2:0]  req_addr,      // 3 位偏移 (8 个寄存器)
  input  wire [7:0]  req_wdata,     // 8 位数据总线（字节导向）
  input  wire        req_we,
  output reg         req_ready,
  output reg  [7:0]  req_rdata,

  // 串行接口（用于测试平台/仿真）
  output reg         tx_valid,      // TX 数据有效
  output reg  [7:0]  tx_data,       // TX 数据字节
  input  wire        tx_ready,      // TX 准备好（流控制）

  input  wire        rx_valid,      // RX 数据有效
  input  wire [7:0]  rx_data,       // RX 数据字节
  output wire        rx_ready,      // RX 准备好（流控制）
  // 中断输出
  output wire        irq_o          // UART 中断请求
);

  //===========================================================================
  // 寄存器地址
  //===========================================================================

  localparam REG_RBR_THR = 3'h0;  // 接收缓冲寄存器 (读) / 发送保持寄存器 (写)
  localparam REG_IER     = 3'h1;  // 中断使能寄存器
  localparam REG_IIR_FCR = 3'h2;  // 中断标识寄存器 (读) / FIFO 控制寄存器 (写)
  localparam REG_LCR     = 3'h3;  // 线路控制寄存器
  localparam REG_MCR     = 3'h4;  // 调制解调器控制寄存器
  localparam REG_LSR     = 3'h5;  // 线路状态寄存器 (只读)
  localparam REG_MSR     = 3'h6;  // 调制解调器状态寄存器 (只读)
  localparam REG_SCR     = 3'h7;  // 暂存寄存器

  //===========================================================================
  // 内部寄存器
  //===========================================================================

  // 控制/配置寄存器
  reg [7:0] ier;      // 中断使能寄存器
  reg [7:0] lcr;      // 线路控制寄存器
  reg [7:0] mcr;      // 调制解调器控制寄存器
  reg [7:0] scr;      // 暂存寄存器
  reg       fcr_fifo_en;  // FIFO 使能位（来自 FCR）

  // TX FIFO
  reg [7:0] tx_fifo [0:FIFO_DEPTH-1];
  reg [4:0] tx_fifo_wptr;  // 写指针（5 位，范围 0-16）
  reg [4:0] tx_fifo_rptr;  // 读指针
  reg tx_fifo_write_last_cycle;  // 跟踪写操作以避免读写冲突
  wire [4:0] tx_fifo_count;
  wire tx_fifo_empty;
  wire tx_fifo_full;

  // RX FIFO
  reg [7:0] rx_fifo [0:FIFO_DEPTH-1];
  reg [4:0] rx_fifo_wptr;  // 写指针
  reg [4:0] rx_fifo_rptr;  // 读指针
  wire [4:0] rx_fifo_count;
  wire rx_fifo_empty;
  wire rx_fifo_full;

  //===========================================================================
  // FIFO 控制逻辑
  //===========================================================================

  assign tx_fifo_count = tx_fifo_wptr - tx_fifo_rptr;
  assign tx_fifo_empty = (tx_fifo_count == 5'd0);
  assign tx_fifo_full  = (tx_fifo_count >= FIFO_DEPTH);

  assign rx_fifo_count = rx_fifo_wptr - rx_fifo_rptr;
  assign rx_fifo_empty = (rx_fifo_count == 5'd0);
  assign rx_fifo_full  = (rx_fifo_count >= FIFO_DEPTH);

  //===========================================================================
  // 线路状态寄存器 (LSR) - 动态计算
  //===========================================================================

  wire [7:0] lsr;
  assign lsr[0] = !rx_fifo_empty;     // DR: 数据准备好
  assign lsr[1] = 1'b0;                // OE: 溢出错误（未实现）
  assign lsr[2] = 1'b0;                // PE: 奇偶校验错误（无奇偶校验）
  assign lsr[3] = 1'b0;                // FE: 帧错误（未实现）
  assign lsr[4] = 1'b0;                // BI: 断开中断（未实现）
  assign lsr[5] = !tx_fifo_full;       // THRE: 发送保持寄存器空
  assign lsr[6] = tx_fifo_empty;       // TEMT: 发送器空
  assign lsr[7] = 1'b0;                // RX FIFO 中的错误（未实现）

  //===========================================================================
  // 中断标识寄存器 (IIR) - 动态计算
  //===========================================================================

  wire irq_rx_data_avail;
  wire irq_tx_empty;
  wire [7:0] iir;

  assign irq_rx_data_avail = !rx_fifo_empty && ier[0];  // RDA 中断使能
  // THRE 中断: FIFO 空且发送器不忙
  assign irq_tx_empty      = tx_fifo_empty && !tx_valid && ier[1];

  // IIR 格式：
  // Bit 0: 0=中断挂起, 1=无中断
  // Bits 3:1: 中断 ID（优先级编码）
  //   001 = 无中断挂起
  //   010 = 发送保持寄存器空
  //   100 = 接收数据可用
  assign iir[0] = !(irq_rx_data_avail || irq_tx_empty);  // 如果有任意中断挂起则为 0
  assign iir[3:1] = irq_rx_data_avail ? 3'b010 :          // RX 拥有更高优先级
                    irq_tx_empty ? 3'b001 :
                    3'b000;                               // 无中断
  assign iir[7:4] = 4'b0000;  // 保留

  assign irq_o = irq_rx_data_avail || irq_tx_empty;

  //===========================================================================
  // TX FIFO → 串行输出逻辑
  //===========================================================================

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      tx_valid <= 1'b0;
      tx_data <= 8'h0;
      tx_fifo_rptr <= 5'd0;
    end else begin
      // 如果 FIFO 有数据且 TX 接口空闲，则发送下一个字节
      // 重要：写操作后阻止读操作 1 个周期以避免读写冲突
      if (!tx_fifo_empty && !tx_valid && !tx_fifo_write_last_cycle) begin
        tx_valid <= 1'b1;
        tx_data <= tx_fifo[tx_fifo_rptr[3:0]];  // 使用低 4 位进行索引
        tx_fifo_rptr <= tx_fifo_rptr + 5'd1;
        `ifdef DEBUG_UART
        $display("UART TX: 0x%02h ('%c') at time %t", tx_fifo[tx_fifo_rptr[3:0]],
                 tx_fifo[tx_fifo_rptr[3:0]], $time);
        `endif
      end else if (tx_valid && tx_ready) begin
        // 当接收端接受数据时清除 valid 信号
        tx_valid <= 1'b0;
      end
    end
  end

  //===========================================================================
  // RX 串行输入 → FIFO 逻辑
  //===========================================================================

  assign rx_ready = !rx_fifo_full;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      rx_fifo_wptr <= 5'd0;
    end else begin
      // 如果 RX 数据到达且 FIFO 有空间，则存储数据
      if (rx_valid && !rx_fifo_full) begin
        rx_fifo[rx_fifo_wptr[3:0]] <= rx_data;
        rx_fifo_wptr <= rx_fifo_wptr + 5'd1;
        `ifdef DEBUG_UART
        $display("UART RX: 0x%02h ('%c') at time %t", rx_data, rx_data, $time);
        `endif
      end
    end
  end

  //===========================================================================
  // 内存映射寄存器访问
  //===========================================================================

  // 写逻辑
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      ier <= 8'h00;
      lcr <= 8'h03;  // 默认：8N1 模式
      mcr <= 8'h00;
      scr <= 8'h00;
      fcr_fifo_en <= 1'b1;  // 默认启用 FIFO
      tx_fifo_wptr <= 5'd0;
      tx_fifo_write_last_cycle <= 1'b0;
    end else begin
      // 默认：本周期不写入（如果发生 THR 写入则设置为 1）
      tx_fifo_write_last_cycle <= 1'b0;

      if (req_valid && req_we) begin
        case (req_addr)
          REG_RBR_THR: begin
            // 写入 THR：将数据推入 TX FIFO
            if (!tx_fifo_full) begin
              tx_fifo[tx_fifo_wptr[3:0]] <= req_wdata;
              tx_fifo_wptr <= tx_fifo_wptr + 5'd1;
              tx_fifo_write_last_cycle <= 1'b1;  // 标记写入以阻止 TX 读取
              `ifdef DEBUG_UART
              $display("UART THR write: 0x%02h ('%c') at time %t", req_wdata, req_wdata, $time);
              `endif
            end else begin
              `ifdef DEBUG_UART
              $display("UART THR write FAILED: FIFO full at time %t", $time);
              `endif
            end
          end

          REG_IER: begin
            ier <= req_wdata;
          end

          REG_IIR_FCR: begin
            // 写入 FCR（FIFO 控制寄存器）
            fcr_fifo_en <= req_wdata[0];  // 第 0 位：FIFO 使能
            if (req_wdata[1]) begin        // 第 1 位：清空 RX FIFO
              rx_fifo_rptr <= rx_fifo_wptr;  // 将读指针重置为写指针
            end
            if (req_wdata[2]) begin        // 第 2 位：清空 TX FIFO
              tx_fifo_rptr <= tx_fifo_wptr;  // 将读指针重置为写指针
            end
          end

          REG_LCR: begin
            lcr <= req_wdata;
          end

          REG_MCR: begin
            mcr <= req_wdata;
          end

          REG_SCR: begin
            scr <= req_wdata;
          end

          default: begin
            // LSR, MSR 是只读寄存器
          end
        endcase
      end
    end
  end

  // Read Logic
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      req_rdata <= 8'h00;
      req_ready <= 1'b0;
      rx_fifo_rptr <= 5'd0;
    end else begin
      req_ready <= req_valid;  // 单周期响应

      if (req_valid && !req_we) begin
        case (req_addr)
          REG_RBR_THR: begin
            // 从 RBR 读取：从 RX FIFO 弹出数据
            if (!rx_fifo_empty) begin
              req_rdata <= rx_fifo[rx_fifo_rptr[3:0]];
              rx_fifo_rptr <= rx_fifo_rptr + 5'd1;
              `ifdef DEBUG_UART
              $display("UART RBR read: 0x%02h ('%c') at time %t",
                       rx_fifo[rx_fifo_rptr[3:0]], rx_fifo[rx_fifo_rptr[3:0]], $time);
              `endif
            end else begin
              req_rdata <= 8'h00;  // 无可用数据
            end
          end

          REG_IER: begin
            req_rdata <= ier;
          end

          REG_IIR_FCR: begin
            // 从 IIR 读取（中断识别寄存器）
            req_rdata <= iir;
          end

          REG_LCR: begin
            req_rdata <= lcr;
          end

          REG_MCR: begin
            req_rdata <= mcr;
          end

          REG_LSR: begin
            req_rdata <= lsr;
          end

          REG_MSR: begin
            // 调制解调器状态寄存器（占位实现 - 始终指示就绪）
            req_rdata <= 8'b1011_0000;  // CTS, DSR, CD 设置
          end

          REG_SCR: begin
            req_rdata <= scr;
          end

          default: begin
            req_rdata <= 8'h00;
          end
        endcase
      end else begin
        req_rdata <= 8'h00;
      end
    end
  end

  //===========================================================================
  // 调试监控 (可选)
  //===========================================================================

  `ifdef DEBUG_UART
  always @(posedge clk) begin
    if (req_valid) begin
      $display("UART[@%t]: addr=0x%01h we=%b wdata=0x%02h rdata=0x%02h",
               $time, req_addr, req_we, req_wdata, req_rdata);
      $display("  TX_FIFO: wptr=%d rptr=%d count=%d empty=%b full=%b",
               tx_fifo_wptr, tx_fifo_rptr, tx_fifo_count, tx_fifo_empty, tx_fifo_full);
      $display("  RX_FIFO: wptr=%d rptr=%d count=%d empty=%b full=%b",
               rx_fifo_wptr, rx_fifo_rptr, rx_fifo_count, rx_fifo_empty, rx_fifo_full);
      $display("  LSR=0x%02h IER=0x%02h IIR=0x%02h IRQ=%b", lsr, ier, iir, irq_o);
    end
  end
  `endif

endmodule
