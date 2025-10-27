// rv_soc.v - RV1 System-on-Chip
// Simple SoC wrapper integrating CPU core with peripherals
// Phase 1.2: CLINT timer/software interrupts + UART serial console
// Author: RV1 Project
// Date: 2025-10-26

`include "config/rv_config.vh"

module rv_soc #(
  parameter XLEN = `XLEN,
  parameter RESET_VECTOR = {XLEN{1'b0}},
  parameter IMEM_SIZE = 16384,      // 16KB instruction memory
  parameter DMEM_SIZE = 16384,      // 16KB data memory
  parameter MEM_FILE = "",
  parameter NUM_HARTS = 1           // Number of hardware threads
) (
  input  wire             clk,
  input  wire             reset_n,

  // UART serial interface
  output wire             uart_tx_valid,
  output wire [7:0]       uart_tx_data,
  input  wire             uart_tx_ready,
  input  wire             uart_rx_valid,
  input  wire [7:0]       uart_rx_data,
  output wire             uart_rx_ready,

  // Debug outputs
  output wire [XLEN-1:0]  pc_out,
  output wire [31:0]      instr_out
);

  //==========================================================================
  // Internal Signals
  //==========================================================================

  // CLINT interrupt outputs
  wire             mtip;              // Machine Timer Interrupt
  wire             msip;              // Machine Software Interrupt

  //==========================================================================
  // CPU Core
  //==========================================================================

  rv_core_pipelined #(
    .XLEN(XLEN),
    .RESET_VECTOR(RESET_VECTOR),
    .IMEM_SIZE(IMEM_SIZE),
    .DMEM_SIZE(DMEM_SIZE),
    .MEM_FILE(MEM_FILE)
  ) core (
    .clk(clk),
    .reset_n(reset_n),
    .mtip_in(mtip),
    .msip_in(msip),
    .meip_in(1'b0),      // TODO: Connect to PLIC MEI output (Phase 1.3)
    .seip_in(1'b0),      // TODO: Connect to PLIC SEI output (Phase 1.3)
    .pc_out(pc_out),
    .instr_out(instr_out)
  );

  //==========================================================================
  // CLINT (Core-Local Interruptor)
  //==========================================================================
  // Note: For Phase 1, CLINT is included but not memory-mapped yet.
  // Memory-mapped access will be added in future phases when we implement
  // a proper bus interconnect. For now, CLINT runs autonomously with
  // MTIME incrementing and MTIMECMP initialized to max (no interrupts).

  clint #(
    .NUM_HARTS(NUM_HARTS),
    .BASE_ADDR(32'h0200_0000)
  ) clint_inst (
    .clk(clk),
    .reset_n(reset_n),
    // Memory-mapped interface (not connected yet - Phase 2)
    .req_valid(1'b0),                // No memory-mapped access yet
    .req_addr(16'h0),
    .req_wdata(64'h0),
    .req_we(1'b0),
    .req_size(3'h0),
    .req_ready(),                    // Unused
    .req_rdata(),                    // Unused
    // Interrupt outputs
    .mti_o(mtip),
    .msi_o(msip)
  );

  //==========================================================================
  // UART (16550-Compatible Serial Console)
  //==========================================================================
  // Note: For Phase 1.2, UART is included but not memory-mapped yet.
  // Memory-mapped access will be added in future phases when we implement
  // a proper bus interconnect. For now, UART TX/RX interfaces are exposed
  // at the SoC level for testbench interaction.

  uart_16550 #(
    .BASE_ADDR(32'h1000_0000),
    .FIFO_DEPTH(16)
  ) uart_inst (
    .clk(clk),
    .reset_n(reset_n),
    // Memory-mapped interface (not connected yet - Phase 2)
    .req_valid(1'b0),                // No memory-mapped access yet
    .req_addr(3'h0),
    .req_wdata(8'h0),
    .req_we(1'b0),
    .req_ready(),                    // Unused
    .req_rdata(),                    // Unused
    // Serial interface (exposed at SoC level)
    .tx_valid(uart_tx_valid),
    .tx_data(uart_tx_data),
    .tx_ready(uart_tx_ready),
    .rx_valid(uart_rx_valid),
    .rx_data(uart_rx_data),
    .rx_ready(uart_rx_ready),
    // Interrupt output (not connected yet - Phase 2)
    .irq_o()                         // Unused for now
  );

endmodule
