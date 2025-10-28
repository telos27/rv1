// simple_bus.v - Simple Memory Bus Interconnect
// Priority-based address decoder for RV1 SoC peripherals
// Author: RV1 Project
// Date: 2025-10-27
//
// Memory Map:
//   0x0000_0000 - 0x0000_FFFF: IMEM (64KB) - read-only via bus for .rodata copy
//   0x0200_0000 - 0x0200_FFFF: CLINT (64KB) - timer + software interrupts
//   0x0C00_0000 - 0x0FFF_FFFF: PLIC (64MB) - platform-level interrupt controller
//   0x1000_0000 - 0x1000_0FFF: UART (4KB) - serial console
//   0x8000_0000 - 0x800F_FFFF: DMEM (1MB) - data RAM
//
// Features:
// - Single master (CPU core data port)
// - Multiple slaves (CLINT, UART, DMEM)
// - Priority-based address decoding
// - Single-cycle response (all peripherals respond in 1 cycle)
// - Supports byte/half/word/double accesses

`include "rv_config.vh"

module simple_bus #(
  parameter XLEN = `XLEN
) (
  input  wire             clk,
  input  wire             reset_n,

  //===========================================================================
  // Master Interface (from CPU Core - Data Port)
  //===========================================================================
  input  wire             master_req_valid,
  input  wire [XLEN-1:0]  master_req_addr,
  input  wire [63:0]      master_req_wdata,
  input  wire             master_req_we,
  input  wire [2:0]       master_req_size,     // 0=byte, 1=half, 2=word, 3=double
  output reg              master_req_ready,
  output reg  [63:0]      master_req_rdata,

  //===========================================================================
  // Slave 0: CLINT (Core-Local Interruptor)
  //===========================================================================
  output reg              clint_req_valid,
  output reg  [15:0]      clint_req_addr,      // 16-bit offset (64KB range)
  output reg  [63:0]      clint_req_wdata,
  output reg              clint_req_we,
  output reg  [2:0]       clint_req_size,
  input  wire             clint_req_ready,
  input  wire [63:0]      clint_req_rdata,

  //===========================================================================
  // Slave 1: UART (16550-Compatible Serial Console)
  //===========================================================================
  output reg              uart_req_valid,
  output reg  [2:0]       uart_req_addr,       // 3-bit offset (8 registers)
  output reg  [7:0]       uart_req_wdata,
  output reg              uart_req_we,
  input  wire             uart_req_ready,
  input  wire [7:0]       uart_req_rdata,

  //===========================================================================
  // Slave 2: DMEM (Data Memory)
  //===========================================================================
  output reg              dmem_req_valid,
  output reg  [XLEN-1:0]  dmem_req_addr,
  output reg  [63:0]      dmem_req_wdata,
  output reg              dmem_req_we,
  output reg  [2:0]       dmem_req_size,
  input  wire             dmem_req_ready,
  input  wire [63:0]      dmem_req_rdata,

  //===========================================================================
  // Slave 3: PLIC (Platform-Level Interrupt Controller)
  //===========================================================================
  output reg              plic_req_valid,
  output reg  [XLEN-1:0]  plic_req_addr,
  output reg  [31:0]      plic_req_wdata,
  output reg              plic_req_we,
  input  wire             plic_req_ready,
  input  wire [31:0]      plic_req_rdata,

  //===========================================================================
  // Slave 4: IMEM (Instruction Memory) - Read-only for data loads
  //===========================================================================
  output reg              imem_req_valid,
  output reg  [XLEN-1:0]  imem_req_addr,
  input  wire             imem_req_ready,
  input  wire [31:0]      imem_req_rdata
);

  //===========================================================================
  // Address Decode Logic
  //===========================================================================

  // Define address ranges (base addresses)
  localparam IMEM_BASE  = 32'h0000_0000;
  localparam IMEM_MASK  = 32'hFFFF_0000;   // 64KB range
  localparam CLINT_BASE = 32'h0200_0000;
  localparam CLINT_MASK = 32'hFFFF_0000;   // 64KB range
  localparam UART_BASE  = 32'h1000_0000;
  localparam UART_MASK  = 32'hFFFF_F000;   // 4KB range
  localparam DMEM_BASE  = 32'h8000_0000;
  localparam DMEM_MASK  = 32'hFFF0_0000;   // 1MB range (was 64KB - BUG FIX Session 27)
  localparam PLIC_BASE  = 32'h0C00_0000;
  localparam PLIC_MASK  = 32'hFC00_0000;   // 64MB range

  // Device selection signals
  wire sel_imem;
  wire sel_clint;
  wire sel_uart;
  wire sel_dmem;
  wire sel_plic;
  wire sel_none;

  // Address matching (priority order: most specific to least specific)
  assign sel_clint = ((master_req_addr & CLINT_MASK) == CLINT_BASE);
  assign sel_uart  = ((master_req_addr & UART_MASK)  == UART_BASE);
  assign sel_plic  = ((master_req_addr & PLIC_MASK)  == PLIC_BASE);
  assign sel_dmem  = ((master_req_addr & DMEM_MASK)  == DMEM_BASE);
  assign sel_imem  = ((master_req_addr & IMEM_MASK)  == IMEM_BASE);
  assign sel_none  = !(sel_clint || sel_uart || sel_plic || sel_dmem || sel_imem);

  //===========================================================================
  // Request Routing to Slaves
  //===========================================================================

  always @(*) begin
    // Default: all slaves idle
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

    // Route request to selected slave
    if (master_req_valid) begin
      if (sel_imem) begin
        imem_req_valid = 1'b1;
        imem_req_addr  = master_req_addr;
        // IMEM is read-only, ignore writes
      end else if (sel_clint) begin
        clint_req_valid = 1'b1;
        clint_req_addr  = master_req_addr[15:0];  // 16-bit offset within 64KB
        clint_req_wdata = master_req_wdata;
        clint_req_we    = master_req_we;
        clint_req_size  = master_req_size;
      end else if (sel_uart) begin
        uart_req_valid = 1'b1;
        uart_req_addr  = master_req_addr[2:0];    // 3-bit offset (8 registers)
        uart_req_wdata = master_req_wdata[7:0];   // UART is byte-oriented
        uart_req_we    = master_req_we;
        // Note: UART always operates on bytes, ignore req_size
      end else if (sel_plic) begin
        plic_req_valid = 1'b1;
        plic_req_addr  = master_req_addr;         // Full address (PLIC decodes internally)
        plic_req_wdata = master_req_wdata[31:0];  // PLIC is word-oriented
        plic_req_we    = master_req_we;
        // Note: PLIC operates on 32-bit words
      end else if (sel_dmem) begin
        dmem_req_valid = 1'b1;
        dmem_req_addr  = master_req_addr;
        dmem_req_wdata = master_req_wdata;
        dmem_req_we    = master_req_we;
        dmem_req_size  = master_req_size;
      end
      // If sel_none, no slave selected → ready will be 0, rdata will be 0
    end
  end

  //===========================================================================
  // Response Routing from Slaves
  //===========================================================================

  always @(*) begin
    // Default: no response
    master_req_ready = 1'b0;
    master_req_rdata = 64'h0;

    // Route response from selected slave
    if (sel_imem) begin
      master_req_ready = imem_req_ready;
      master_req_rdata = {32'h0, imem_req_rdata};  // Zero-extend 32-bit instruction to 64-bit
    end else if (sel_clint) begin
      master_req_ready = clint_req_ready;
      master_req_rdata = clint_req_rdata;
    end else if (sel_uart) begin
      master_req_ready = uart_req_ready;
      master_req_rdata = {56'h0, uart_req_rdata};  // Zero-extend byte to 64-bit
    end else if (sel_plic) begin
      master_req_ready = plic_req_ready;
      master_req_rdata = {32'h0, plic_req_rdata};  // Zero-extend word to 64-bit
    end else if (sel_dmem) begin
      master_req_ready = dmem_req_ready;
      master_req_rdata = dmem_req_rdata;
    end else if (sel_none && master_req_valid) begin
      // Invalid address → return error response (ready=1, data=0)
      // This allows core to continue instead of hanging
      master_req_ready = 1'b1;
      master_req_rdata = 64'h0;
    end
  end

  //===========================================================================
  // Debug Monitoring (Optional)
  //===========================================================================

  `ifdef DEBUG_BUS
  always @(posedge clk) begin
    if (master_req_valid) begin
      $display("[BUS] Cycle %0d: addr=0x%08h we=%b size=%0d | sel: clint=%b uart=%b plic=%b dmem=%b imem=%b none=%b",
               $time/10, master_req_addr, master_req_we, master_req_size,
               sel_clint, sel_uart, sel_plic, sel_dmem, sel_imem, sel_none);

      // Show address decode calculations for CLINT
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
