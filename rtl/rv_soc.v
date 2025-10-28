// rv_soc.v - RV1 System-on-Chip
// Full SoC with CPU core, bus interconnect, and peripherals
// Phase 1.4: Complete SoC integration with memory-mapped peripherals
// Author: RV1 Project
// Date: 2025-10-27

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

  // Interrupt signals (from peripherals)
  wire [NUM_HARTS-1:0] mtip_vec;      // Machine Timer Interrupt vector (from CLINT)
  wire [NUM_HARTS-1:0] msip_vec;      // Machine Software Interrupt vector (from CLINT)
  wire             mtip;              // Machine Timer Interrupt for hart 0
  wire             msip;              // Machine Software Interrupt for hart 0
  wire             meip;              // Machine External Interrupt (from PLIC)
  wire             seip;              // Supervisor External Interrupt (from PLIC)

  // Extract hart 0 interrupts from vectors
  assign mtip = mtip_vec[0];
  assign msip = msip_vec[0];
  wire             uart_irq;          // UART interrupt

  // Bus signals - Master (Core)
  wire             bus_master_req_valid;
  wire [XLEN-1:0]  bus_master_req_addr;
  wire [63:0]      bus_master_req_wdata;
  wire             bus_master_req_we;
  wire [2:0]       bus_master_req_size;
  wire             bus_master_req_ready;
  wire [63:0]      bus_master_req_rdata;

  // Bus signals - Slave 0 (CLINT)
  wire             clint_req_valid;
  wire [15:0]      clint_req_addr;
  wire [63:0]      clint_req_wdata;
  wire             clint_req_we;
  wire [2:0]       clint_req_size;
  wire             clint_req_ready;
  wire [63:0]      clint_req_rdata;

  // Bus signals - Slave 1 (UART)
  wire             uart_req_valid;
  wire [2:0]       uart_req_addr;
  wire [7:0]       uart_req_wdata;
  wire             uart_req_we;
  wire             uart_req_ready;
  wire [7:0]       uart_req_rdata;

  // Bus signals - Slave 2 (DMEM)
  wire             dmem_req_valid;
  wire [XLEN-1:0]  dmem_req_addr;
  wire [63:0]      dmem_req_wdata;
  wire             dmem_req_we;
  wire [2:0]       dmem_req_size;
  wire             dmem_req_ready;
  wire [63:0]      dmem_req_rdata;

  // Bus signals - Slave 3 (PLIC)
  wire             plic_req_valid;
  wire [XLEN-1:0]  plic_req_addr;      // From bus (full address)
  wire [23:0]      plic_req_addr_offset; // To PLIC (24-bit offset)
  wire [31:0]      plic_req_wdata;
  wire             plic_req_we;
  wire             plic_req_ready;
  wire [31:0]      plic_req_rdata;

  // Bus signals - Slave 4 (IMEM) - for .rodata copy
  wire             imem_req_valid;
  wire [XLEN-1:0]  imem_req_addr;
  wire             imem_req_ready;
  wire [31:0]      imem_req_rdata;

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
    // Interrupts
    .mtip_in(mtip),
    .msip_in(msip),
    .meip_in(meip),
    .seip_in(seip),
    // Bus master interface
    .bus_req_valid(bus_master_req_valid),
    .bus_req_addr(bus_master_req_addr),
    .bus_req_wdata(bus_master_req_wdata),
    .bus_req_we(bus_master_req_we),
    .bus_req_size(bus_master_req_size),
    .bus_req_ready(bus_master_req_ready),
    .bus_req_rdata(bus_master_req_rdata),
    // Debug
    .pc_out(pc_out),
    .instr_out(instr_out)
  );

  //==========================================================================
  // Bus Interconnect
  //==========================================================================

  simple_bus #(
    .XLEN(XLEN)
  ) bus (
    .clk(clk),
    .reset_n(reset_n),
    // Master interface (from Core)
    .master_req_valid(bus_master_req_valid),
    .master_req_addr(bus_master_req_addr),
    .master_req_wdata(bus_master_req_wdata),
    .master_req_we(bus_master_req_we),
    .master_req_size(bus_master_req_size),
    .master_req_ready(bus_master_req_ready),
    .master_req_rdata(bus_master_req_rdata),
    // Slave 0: CLINT
    .clint_req_valid(clint_req_valid),
    .clint_req_addr(clint_req_addr),
    .clint_req_wdata(clint_req_wdata),
    .clint_req_we(clint_req_we),
    .clint_req_size(clint_req_size),
    .clint_req_ready(clint_req_ready),
    .clint_req_rdata(clint_req_rdata),
    // Slave 1: UART
    .uart_req_valid(uart_req_valid),
    .uart_req_addr(uart_req_addr),
    .uart_req_wdata(uart_req_wdata),
    .uart_req_we(uart_req_we),
    .uart_req_ready(uart_req_ready),
    .uart_req_rdata(uart_req_rdata),
    // Slave 2: DMEM
    .dmem_req_valid(dmem_req_valid),
    .dmem_req_addr(dmem_req_addr),
    .dmem_req_wdata(dmem_req_wdata),
    .dmem_req_we(dmem_req_we),
    .dmem_req_size(dmem_req_size),
    .dmem_req_ready(dmem_req_ready),
    .dmem_req_rdata(dmem_req_rdata),
    // Slave 3: PLIC
    .plic_req_valid(plic_req_valid),
    .plic_req_addr(plic_req_addr),
    .plic_req_wdata(plic_req_wdata),
    .plic_req_we(plic_req_we),
    .plic_req_ready(plic_req_ready),
    .plic_req_rdata(plic_req_rdata),
    // Slave 4: IMEM
    .imem_req_valid(imem_req_valid),
    .imem_req_addr(imem_req_addr),
    .imem_req_ready(imem_req_ready),
    .imem_req_rdata(imem_req_rdata)
  );

  //==========================================================================
  // CLINT (Core-Local Interruptor)
  //==========================================================================

  clint #(
    .NUM_HARTS(NUM_HARTS),
    .BASE_ADDR(32'h0200_0000)
  ) clint_inst (
    .clk(clk),
    .reset_n(reset_n),
    // Memory-mapped interface (connected via bus)
    .req_valid(clint_req_valid),
    .req_addr(clint_req_addr),
    .req_wdata(clint_req_wdata),
    .req_we(clint_req_we),
    .req_size(clint_req_size),
    .req_ready(clint_req_ready),
    .req_rdata(clint_req_rdata),
    // Interrupt outputs (all harts)
    .mti_o(mtip_vec),  // Machine timer interrupt vector
    .msi_o(msip_vec)   // Machine software interrupt vector
  );

  //==========================================================================
  // UART (16550-Compatible Serial Console)
  //==========================================================================

  uart_16550 #(
    .BASE_ADDR(32'h1000_0000),
    .FIFO_DEPTH(16)
  ) uart_inst (
    .clk(clk),
    .reset_n(reset_n),
    // Memory-mapped interface (connected via bus)
    .req_valid(uart_req_valid),
    .req_addr(uart_req_addr),
    .req_wdata(uart_req_wdata),
    .req_we(uart_req_we),
    .req_ready(uart_req_ready),
    .req_rdata(uart_req_rdata),
    // Serial interface (exposed at SoC level)
    .tx_valid(uart_tx_valid),
    .tx_data(uart_tx_data),
    .tx_ready(uart_tx_ready),
    .rx_valid(uart_rx_valid),
    .rx_data(uart_rx_data),
    .rx_ready(uart_rx_ready),
    // Interrupt output
    .irq_o(uart_irq)
  );

  //==========================================================================
  // PLIC (Platform-Level Interrupt Controller)
  //==========================================================================

  // Extract 24-bit offset from full address for PLIC
  assign plic_req_addr_offset = plic_req_addr[23:0];

  plic #(
    .NUM_SOURCES(32),
    .NUM_HARTS(NUM_HARTS)
  ) plic_inst (
    .clk(clk),
    .reset_n(reset_n),
    // Memory-mapped interface (connected via bus)
    .req_valid(plic_req_valid),
    .req_addr(plic_req_addr_offset),
    .req_wdata(plic_req_wdata),
    .req_we(plic_req_we),
    .req_ready(plic_req_ready),
    .req_rdata(plic_req_rdata),
    // Interrupt sources (32 sources, only UART connected for now)
    .irq_sources({31'b0, uart_irq}),  // Source 1 = UART
    // Interrupt outputs to core
    .mei_o(meip),  // Machine External Interrupt
    .sei_o(seip)   // Supervisor External Interrupt
  );

  //==========================================================================
  // Instruction Memory (Bus Adapter - Read-only for .rodata copy)
  //==========================================================================

  // IMEM bus adapter allows data loads from instruction memory
  // This is needed for .rodata section copy during startup
  // We create a second read port by instantiating a second instruction_memory
  // that shares the same hex file (read-only, so no coherency issues)

  wire [31:0] imem_data_port_instruction;

  instruction_memory #(
    .XLEN(XLEN),
    .MEM_SIZE(IMEM_SIZE),
    .MEM_FILE(MEM_FILE)
  ) imem_data_port (
    .clk(clk),
    .addr(imem_req_addr),
    .instruction(imem_data_port_instruction),
    // Write interface unused (read-only port)
    .mem_write(1'b0),
    .write_addr({XLEN{1'b0}}),
    .write_data({XLEN{1'b0}}),
    .funct3(3'b0)
  );

  // Debug: Check what's in IMEM data port at .rodata addresses
  initial begin
    #1;  // Wait for memory to load
    $display("[SOC-IMEM-DATA-PORT] Checking .rodata section in IMEM data port:");
    $display("  [0x3de8] = 0x%02h%02h%02h%02h", imem_data_port.mem[32'h3deb], imem_data_port.mem[32'h3dea],
             imem_data_port.mem[32'h3de9], imem_data_port.mem[32'h3de8]);
    $display("  [0x42b8] = 0x%02h%02h%02h%02h", imem_data_port.mem[32'h42bb], imem_data_port.mem[32'h42ba],
             imem_data_port.mem[32'h42b9], imem_data_port.mem[32'h42b8]);
  end

  // Simple adapter: always ready, passthrough data
  assign imem_req_ready = imem_req_valid;
  assign imem_req_rdata = imem_data_port_instruction;

  //==========================================================================
  // Data Memory (Bus Adapter)
  //==========================================================================

  dmem_bus_adapter #(
    .XLEN(XLEN),
    .FLEN(`FLEN),
    .MEM_SIZE(DMEM_SIZE),
    .MEM_FILE("")  // DMEM should NOT be loaded from hex file (unified memory fix)
  ) dmem_adapter (
    .clk(clk),
    .reset_n(reset_n),
    // Bus slave interface
    .req_valid(dmem_req_valid),
    .req_addr(dmem_req_addr),
    .req_wdata(dmem_req_wdata),
    .req_we(dmem_req_we),
    .req_size(dmem_req_size),
    .req_ready(dmem_req_ready),
    .req_rdata(dmem_req_rdata)
  );

  //===========================================================================
  // Debug Monitoring
  //===========================================================================
  `ifdef DEBUG_CLINT
  always @(posedge clk) begin
    if (mtip_vec[0] || mtip) begin
      $display("[SOC] mtip_vec=%b mtip=%b msip_vec=%b msip=%b", mtip_vec, mtip, msip_vec, msip);
    end
  end
  `endif

endmodule
