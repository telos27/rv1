// uart_16550.v - 16550-Compatible UART
// Implements a subset of the 16550 UART for serial console
// Compatible with standard 16550 drivers (Linux, FreeRTOS, xv6)
// Author: RV1 Project
// Date: 2025-10-26
//
// Memory Map (Base: 0x1000_0000):
//   0x00: RBR (R) / THR (W) - Receive Buffer / Transmit Holding Register
//   0x01: IER (RW) - Interrupt Enable Register
//   0x02: IIR (R) / FCR (W) - Interrupt Identification / FIFO Control
//   0x03: LCR (RW) - Line Control Register
//   0x04: MCR (RW) - Modem Control Register
//   0x05: LSR (R) - Line Status Register
//   0x06: MSR (R) - Modem Status Register
//   0x07: SCR (RW) - Scratch Register
//
// Features:
// - 16-byte TX/RX FIFOs
// - Fixed 8N1 mode (8 data bits, no parity, 1 stop bit)
// - Programmable interrupt enables
// - Status registers for polling or interrupt-driven I/O
// - Byte-level simulation (no actual serial timing)

`include "config/rv_config.vh"

module uart_16550 #(
  parameter BASE_ADDR = 32'h1000_0000,    // Base address (informational)
  parameter FIFO_DEPTH = 16               // TX/RX FIFO depth
) (
  input  wire        clk,
  input  wire        reset_n,

  // Memory-mapped interface
  input  wire        req_valid,
  input  wire [2:0]  req_addr,      // 3-bit offset (8 registers)
  input  wire [7:0]  req_wdata,     // 8-bit data bus (byte-oriented)
  input  wire        req_we,
  output reg         req_ready,
  output reg  [7:0]  req_rdata,

  // Serial interface (for testbench/simulation)
  output reg         tx_valid,      // TX data valid
  output reg  [7:0]  tx_data,       // TX data byte
  input  wire        tx_ready,      // TX ready (flow control)

  input  wire        rx_valid,      // RX data valid
  input  wire [7:0]  rx_data,       // RX data byte
  output wire        rx_ready,      // RX ready (flow control)

  // Interrupt output
  output wire        irq_o          // UART interrupt request
);

  //===========================================================================
  // Register Addresses
  //===========================================================================

  localparam REG_RBR_THR = 3'h0;  // Receive Buffer (R) / Transmit Holding (W)
  localparam REG_IER     = 3'h1;  // Interrupt Enable Register
  localparam REG_IIR_FCR = 3'h2;  // Interrupt ID (R) / FIFO Control (W)
  localparam REG_LCR     = 3'h3;  // Line Control Register
  localparam REG_MCR     = 3'h4;  // Modem Control Register
  localparam REG_LSR     = 3'h5;  // Line Status Register (read-only)
  localparam REG_MSR     = 3'h6;  // Modem Status Register (read-only)
  localparam REG_SCR     = 3'h7;  // Scratch Register

  //===========================================================================
  // Internal Registers
  //===========================================================================

  // Control/Config Registers
  reg [7:0] ier;      // Interrupt Enable Register
  reg [7:0] lcr;      // Line Control Register
  reg [7:0] mcr;      // Modem Control Register
  reg [7:0] scr;      // Scratch Register
  reg       fcr_fifo_en;  // FIFO enable bit (from FCR)

  // TX FIFO
  reg [7:0] tx_fifo [0:FIFO_DEPTH-1];
  reg [4:0] tx_fifo_wptr;  // Write pointer (5 bits for 0-16 range)
  reg [4:0] tx_fifo_rptr;  // Read pointer
  reg tx_fifo_write_last_cycle;  // Track writes to avoid read-during-write hazard
  wire [4:0] tx_fifo_count;
  wire tx_fifo_empty;
  wire tx_fifo_full;

  // RX FIFO
  reg [7:0] rx_fifo [0:FIFO_DEPTH-1];
  reg [4:0] rx_fifo_wptr;  // Write pointer
  reg [4:0] rx_fifo_rptr;  // Read pointer
  wire [4:0] rx_fifo_count;
  wire rx_fifo_empty;
  wire rx_fifo_full;

  //===========================================================================
  // FIFO Control Logic
  //===========================================================================

  assign tx_fifo_count = tx_fifo_wptr - tx_fifo_rptr;
  assign tx_fifo_empty = (tx_fifo_count == 5'd0);
  assign tx_fifo_full  = (tx_fifo_count >= FIFO_DEPTH);

  assign rx_fifo_count = rx_fifo_wptr - rx_fifo_rptr;
  assign rx_fifo_empty = (rx_fifo_count == 5'd0);
  assign rx_fifo_full  = (rx_fifo_count >= FIFO_DEPTH);

  //===========================================================================
  // Line Status Register (LSR) - Computed Dynamically
  //===========================================================================

  wire [7:0] lsr;
  assign lsr[0] = !rx_fifo_empty;     // DR: Data Ready
  assign lsr[1] = 1'b0;                // OE: Overrun Error (not implemented)
  assign lsr[2] = 1'b0;                // PE: Parity Error (no parity)
  assign lsr[3] = 1'b0;                // FE: Framing Error (not implemented)
  assign lsr[4] = 1'b0;                // BI: Break Interrupt (not implemented)
  assign lsr[5] = !tx_fifo_full;       // THRE: Transmit Holding Register Empty
  assign lsr[6] = tx_fifo_empty;       // TEMT: Transmitter Empty
  assign lsr[7] = 1'b0;                // Error in RX FIFO (not implemented)

  //===========================================================================
  // Interrupt Identification Register (IIR) - Computed Dynamically
  //===========================================================================

  wire irq_rx_data_avail;
  wire irq_tx_empty;
  wire [7:0] iir;

  assign irq_rx_data_avail = !rx_fifo_empty && ier[0];  // RDA interrupt enabled
  // THRE interrupt: FIFO empty AND transmitter not busy
  assign irq_tx_empty      = tx_fifo_empty && !tx_valid && ier[1];

  // IIR format:
  // Bit 0: 0=interrupt pending, 1=no interrupt
  // Bits 3:1: Interrupt ID (priority encoded)
  //   001 = No interrupt pending
  //   010 = THR empty
  //   100 = Received data available
  assign iir[0] = !(irq_rx_data_avail || irq_tx_empty);  // 0 if any interrupt pending
  assign iir[3:1] = irq_rx_data_avail ? 3'b010 :          // RX has higher priority
                    irq_tx_empty ? 3'b001 :
                    3'b000;                               // No interrupt
  assign iir[7:4] = 4'b0000;  // Reserved

  assign irq_o = irq_rx_data_avail || irq_tx_empty;

  //===========================================================================
  // TX FIFO → Serial Output Logic
  //===========================================================================

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      tx_valid <= 1'b0;
      tx_data <= 8'h0;
      tx_fifo_rptr <= 5'd0;
    end else begin
      // If FIFO has data and TX interface is not busy, send next byte
      // IMPORTANT: Block reads for 1 cycle after writes to avoid read-during-write hazard
      if (!tx_fifo_empty && !tx_valid && !tx_fifo_write_last_cycle) begin
        tx_valid <= 1'b1;
        tx_data <= tx_fifo[tx_fifo_rptr[3:0]];  // Use lower 4 bits for indexing
        tx_fifo_rptr <= tx_fifo_rptr + 5'd1;
        `ifdef DEBUG_UART
        $display("UART TX: 0x%02h ('%c') at time %t", tx_fifo[tx_fifo_rptr[3:0]],
                 tx_fifo[tx_fifo_rptr[3:0]], $time);
        `endif
      end else if (tx_valid && tx_ready) begin
        // Clear valid when consumer accepts data
        tx_valid <= 1'b0;
      end
    end
  end

  //===========================================================================
  // RX Serial Input → FIFO Logic
  //===========================================================================

  assign rx_ready = !rx_fifo_full;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      rx_fifo_wptr <= 5'd0;
    end else begin
      // If RX data arrives and FIFO has space, store it
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
  // Memory-Mapped Register Access
  //===========================================================================

  // Write Logic
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      ier <= 8'h00;
      lcr <= 8'h03;  // Default: 8N1 mode
      mcr <= 8'h00;
      scr <= 8'h00;
      fcr_fifo_en <= 1'b1;  // FIFO enabled by default
      tx_fifo_wptr <= 5'd0;
      tx_fifo_write_last_cycle <= 1'b0;
    end else begin
      // Default: no write this cycle (will be set to 1 if THR write occurs)
      tx_fifo_write_last_cycle <= 1'b0;

      if (req_valid && req_we) begin
        case (req_addr)
          REG_RBR_THR: begin
            // Write to THR: Push data to TX FIFO
            if (!tx_fifo_full) begin
              tx_fifo[tx_fifo_wptr[3:0]] <= req_wdata;
              tx_fifo_wptr <= tx_fifo_wptr + 5'd1;
              tx_fifo_write_last_cycle <= 1'b1;  // Flag write for TX read blocking
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
            // Write to FCR (FIFO Control Register)
            fcr_fifo_en <= req_wdata[0];  // Bit 0: FIFO enable
            if (req_wdata[1]) begin        // Bit 1: Clear RX FIFO
              rx_fifo_rptr <= rx_fifo_wptr;  // Reset read pointer to write pointer
            end
            if (req_wdata[2]) begin        // Bit 2: Clear TX FIFO
              tx_fifo_rptr <= tx_fifo_wptr;  // Reset read pointer to write pointer
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
            // LSR, MSR are read-only
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
      req_ready <= req_valid;  // Single-cycle response

      if (req_valid && !req_we) begin
        case (req_addr)
          REG_RBR_THR: begin
            // Read from RBR: Pop data from RX FIFO
            if (!rx_fifo_empty) begin
              req_rdata <= rx_fifo[rx_fifo_rptr[3:0]];
              rx_fifo_rptr <= rx_fifo_rptr + 5'd1;
              `ifdef DEBUG_UART
              $display("UART RBR read: 0x%02h ('%c') at time %t",
                       rx_fifo[rx_fifo_rptr[3:0]], rx_fifo[rx_fifo_rptr[3:0]], $time);
              `endif
            end else begin
              req_rdata <= 8'h00;  // No data available
            end
          end

          REG_IER: begin
            req_rdata <= ier;
          end

          REG_IIR_FCR: begin
            // Read from IIR (Interrupt Identification Register)
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
            // Modem Status Register (stub - always indicate ready)
            req_rdata <= 8'b1011_0000;  // CTS, DSR, CD set
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
  // Debug Monitoring (Optional)
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
