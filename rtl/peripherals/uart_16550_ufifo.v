// uart_16550_ufifo.v - 16550-Compatible UART using wbuart32's FIFO
// Uses Dan Gisselquist's formally-verified ufifo.v for TX/RX FIFOs
// Provides 16550 register compatibility with provably-correct FIFO operation
// Author: RV1 Project
// Date: 2025-10-28
//
// This design replaces the problematic inline FIFOs with wbuart32's
// formally-verified synchronous FIFO that handles read-during-write correctly.
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
// - Formally verified FIFOs with read-during-write forwarding
// - 16-byte TX/RX FIFOs (configurable up to 1024)
// - Fixed 8N1 mode (8 data bits, no parity, 1 stop bit)
// - Programmable interrupt enables
// - Byte-level simulation (no actual serial timing)
//
// ufifo.v License: GPL-3.0
// Original FIFO Author: Dan Gisselquist, Ph.D. (Gisselquist Technology, LLC)
// Repository: https://github.com/ZipCPU/wbuart32

`include "config/rv_config.vh"

module uart_16550_ufifo #(
  parameter BASE_ADDR = 32'h1000_0000,    // Base address (informational)
  parameter LGFLEN = 4                     // Log2(FIFO depth) - 4 = 16 bytes
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

  //===========================================================================
  // TX FIFO (wbuart32's ufifo)
  //===========================================================================

  wire       tx_fifo_wr;
  wire [7:0] tx_fifo_wdata;
  wire       tx_fifo_empty_n;  // True if FIFO has data
  wire       tx_fifo_rd;
  wire [7:0] tx_fifo_rdata;
  wire [15:0] tx_fifo_status;
  wire       tx_fifo_err;

  // TX FIFO write: On THR write (one-shot, not continuous)
  reg req_valid_prev;
  wire req_valid_rising;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      req_valid_prev <= 1'b0;
    else
      req_valid_prev <= req_valid;
  end

  assign req_valid_rising = req_valid && !req_valid_prev;
  assign tx_fifo_wr = req_valid_rising && req_we && (req_addr == REG_RBR_THR);
  assign tx_fifo_wdata = req_wdata;

  // Debug: Monitor TX FIFO writes
  `ifdef DEBUG_UART_FIFO
  always @(posedge clk) begin
    if (tx_fifo_wr) begin
      $display("[UART-FIFO-WR] Cycle %0d: Write 0x%02h '%c' to TX FIFO (req_valid=%b, req_valid_prev=%b, req_we=%b, req_addr=%0d)",
               $time/10, req_wdata, req_wdata, req_valid, req_valid_prev, req_we, req_addr);
    end
  end
  `endif

  // TX FIFO read: Controlled by state machine (registered signal)
  reg tx_fifo_rd_reg;
  assign tx_fifo_rd = tx_fifo_rd_reg;

  ufifo #(
    .BW(8),
    .LGFLEN(LGFLEN),
    .RXFIFO(1'b0)  // TX FIFO (counts empty space)
  ) tx_fifo (
    .i_clk(clk),
    .i_reset(~reset_n),  // ufifo uses active-high reset
    .i_wr(tx_fifo_wr),
    .i_data(tx_fifo_wdata),
    .o_empty_n(tx_fifo_empty_n),
    .i_rd(tx_fifo_rd),
    .o_data(tx_fifo_rdata),
    .o_status(tx_fifo_status),
    .o_err(tx_fifo_err)
  );

  //===========================================================================
  // RX FIFO (wbuart32's ufifo)
  //===========================================================================

  wire       rx_fifo_wr;
  wire [7:0] rx_fifo_wdata;
  wire       rx_fifo_empty_n;  // True if FIFO has data
  wire       rx_fifo_rd;
  wire [7:0] rx_fifo_rdata;
  wire [15:0] rx_fifo_status;
  wire       rx_fifo_err;

  // RX FIFO write: On external rx_valid
  assign rx_fifo_wr = rx_valid;
  assign rx_fifo_wdata = rx_data;

  // RX FIFO read: On RBR read (one-shot, not continuous)
  assign rx_fifo_rd = req_valid_rising && !req_we && (req_addr == REG_RBR_THR);

  // RX ready: FIFO has space
  assign rx_ready = !rx_fifo_err;  // Can accept if not overflowing

  ufifo #(
    .BW(8),
    .LGFLEN(LGFLEN),
    .RXFIFO(1'b1)  // RX FIFO (counts full space)
  ) rx_fifo (
    .i_clk(clk),
    .i_reset(~reset_n),  // ufifo uses active-high reset
    .i_wr(rx_fifo_wr),
    .i_data(rx_fifo_wdata),
    .o_empty_n(rx_fifo_empty_n),
    .i_rd(rx_fifo_rd),
    .o_data(rx_fifo_rdata),
    .o_status(rx_fifo_status),
    .o_err(rx_fifo_err)
  );

  //===========================================================================
  // FIFO Status Signals
  //===========================================================================

  // TX FIFO status bits (from o_status)
  wire [9:0] tx_fill;
  wire       tx_full, tx_half_full;
  assign tx_fill = tx_fifo_status[9:0];
  assign tx_full = tx_fifo_status[12];
  assign tx_half_full = tx_fifo_status[11];

  // RX FIFO status bits (from o_status)
  wire [9:0] rx_fill;
  wire       rx_full, rx_half_full;
  assign rx_fill = rx_fifo_status[9:0];
  assign rx_full = rx_fifo_status[12];
  assign rx_half_full = rx_fifo_status[11];

  //===========================================================================
  // TX State Machine - Output to Testbench
  //===========================================================================

  // State machine states
  localparam TX_IDLE = 2'b00;
  localparam TX_READ = 2'b01;
  localparam TX_WAIT = 2'b10;

  reg [1:0] tx_state;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      tx_state <= TX_IDLE;
      tx_valid <= 1'b0;
      tx_data <= 8'h00;
      tx_fifo_rd_reg <= 1'b0;
    end else begin
      // Default: de-assert read
      tx_fifo_rd_reg <= 1'b0;

      // Clear valid when testbench acknowledges (MUST be before state machine!)
      // This prevents race condition where TX_IDLE sees !tx_valid in same cycle
      if (tx_valid && tx_ready) begin
        tx_valid <= 1'b0;
      end

      case (tx_state)
        TX_IDLE: begin
          // Wait for FIFO to have data and no outstanding transmission
          // CRITICAL: Check !tx_valid BEFORE clearing (prevents same-cycle race)
          if (tx_fifo_empty_n && !tx_valid && !(tx_valid && tx_ready)) begin
            tx_fifo_rd_reg <= 1'b1;  // Issue read command
            tx_state <= TX_READ;
          end
          // Stay in IDLE if tx_valid is still high (waiting for testbench to accept)
        end

        TX_READ: begin
          // Read command issued, data will be available next cycle
          tx_state <= TX_WAIT;
        end

        TX_WAIT: begin
          // Data now available on tx_fifo_rdata due to ufifo's bypass logic
          tx_data <= tx_fifo_rdata;
          tx_valid <= 1'b1;
          tx_state <= TX_IDLE;
        end

        default: begin
          tx_state <= TX_IDLE;
        end
      endcase
    end
  end

  //===========================================================================
  // Register Writes
  //===========================================================================

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      ier <= 8'h00;
      lcr <= 8'h03;    // 8N1 (8 data bits, no parity, 1 stop bit)
      mcr <= 8'h00;
      scr <= 8'h00;
      fcr_fifo_en <= 1'b1;  // FIFOs always enabled
    end else if (req_valid && req_we) begin
      case (req_addr)
        REG_IER: begin
          ier <= req_wdata;
        end
        REG_IIR_FCR: begin
          // FCR write
          fcr_fifo_en <= req_wdata[0];  // Bit 0: FIFO enable
          // Note: FIFO reset bits [1:2] ignored (FIFOs auto-clear on init)
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
          // THR write handled by FIFO directly
        end
      endcase
    end
  end

  //===========================================================================
  // Register Reads
  //===========================================================================

  always @(*) begin
    req_rdata = 8'h00;

    if (req_valid && !req_we) begin
      case (req_addr)
        REG_RBR_THR: begin
          // RBR read - Data from RX FIFO
          req_rdata = rx_fifo_rdata;
        end
        REG_IER: begin
          req_rdata = ier;
        end
        REG_IIR_FCR: begin
          // IIR read - Interrupt Identification
          // Bit [7:6]: FIFO enabled (11 = enabled)
          // Bit [3:0]: Interrupt ID (0001 = no interrupt)
          req_rdata = {2'b11, 4'h0, 2'b00, 4'h1};  // FIFOs enabled, no interrupt
        end
        REG_LCR: begin
          req_rdata = lcr;
        end
        REG_MCR: begin
          req_rdata = mcr;
        end
        REG_LSR: begin
          // LSR - Line Status Register
          // [7] Error in RXFIFO
          // [6] Transmitter Empty (TEMT) - TX FIFO empty and shift register empty
          // [5] Transmit Holding Register Empty (THRE) - TX FIFO not full
          // [4] Break Interrupt (BI)
          // [3] Framing Error (FE)
          // [2] Parity Error (PE)
          // [1] Overrun Error (OE)
          // [0] Data Ready (DR) - RX FIFO has data
          req_rdata = {
            rx_fifo_err,           // [7] Error in RXFIFO
            !tx_fifo_empty_n,      // [6] Transmitter Empty
            !tx_full,              // [5] THR Empty
            1'b0,                  // [4] Break Interrupt
            1'b0,                  // [3] Framing Error
            1'b0,                  // [2] Parity Error
            1'b0,                  // [1] Overrun Error
            rx_fifo_empty_n        // [0] Data Ready
          };
        end
        REG_MSR: begin
          // MSR - Modem Status Register (not implemented)
          req_rdata = 8'h00;
        end
        REG_SCR: begin
          req_rdata = scr;
        end
        default: begin
          req_rdata = 8'h00;
        end
      endcase
    end
  end

  //===========================================================================
  // Ready Signal
  //===========================================================================

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      req_ready <= 1'b0;
    end else begin
      // Always ready (single-cycle access)
      req_ready <= req_valid;
    end
  end

  //===========================================================================
  // Interrupt Generation
  //===========================================================================

  // Interrupt sources:
  // - IER[0]: Received Data Available (RDA) - RX FIFO has data
  // - IER[1]: Transmitter Holding Register Empty (THRE) - TX FIFO not full
  // - IER[2]: Receiver Line Status (RLS) - Errors

  wire irq_rda;
  wire irq_thre;
  wire irq_rls;

  assign irq_rda = ier[0] && rx_fifo_empty_n;    // RX data available
  assign irq_thre = ier[1] && !tx_full;          // TX ready to accept data
  assign irq_rls = ier[2] && rx_fifo_err;        // RX error

  assign irq_o = irq_rda || irq_thre || irq_rls;

endmodule
