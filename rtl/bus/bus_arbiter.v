// bus_arbiter.v - Simple Bus Interconnect with Address Decoder
// Routes CPU memory requests to DMEM, CLINT, or UART based on address
// Single-cycle response, no pipelining, combinational routing
// Author: RV1 Project
// Date: 2025-10-26

`include "config/rv_config.vh"

module bus_arbiter #(
  parameter XLEN = `XLEN
) (
  // CPU/Master interface
  input  wire             req_valid,
  input  wire [XLEN-1:0]  req_addr,
  input  wire [63:0]      req_wdata,
  input  wire             req_we,
  input  wire [2:0]       req_size,
  output wire             req_ready,
  output wire [63:0]      req_rdata,
  output wire             req_error,

  // DMEM interface
  output wire             dmem_valid,
  output wire [XLEN-1:0]  dmem_addr,
  output wire [63:0]      dmem_wdata,
  output wire             dmem_we,
  output wire [2:0]       dmem_size,
  input  wire             dmem_ready,
  input  wire [63:0]      dmem_rdata,

  // CLINT interface (Core-Local Interruptor)
  output wire             clint_valid,
  output wire [15:0]      clint_addr,     // 16-bit offset within 64KB region
  output wire [63:0]      clint_wdata,
  output wire             clint_we,
  output wire [2:0]       clint_size,
  input  wire             clint_ready,
  input  wire [63:0]      clint_rdata,

  // UART interface (16550-compatible)
  output wire             uart_valid,
  output wire [2:0]       uart_addr,      // 3-bit offset (8 registers)
  output wire [7:0]       uart_wdata,
  output wire             uart_we,
  input  wire             uart_ready,
  input  wire [7:0]       uart_rdata
);

  //==========================================================================
  // Address Decode
  //==========================================================================
  // Memory map:
  //   0x0200_0000 - 0x0200_FFFF : CLINT (64KB)
  //   0x1000_0000 - 0x1000_0FFF : UART (4KB, only first 8 bytes used)
  //   0x8000_0000 - 0x8000_FFFF : DMEM (64KB)

  wire sel_clint = (req_addr[31:16] == 16'h0200);        // 0x0200_xxxx
  wire sel_uart  = (req_addr[31:12] == 20'h10000);       // 0x1000_0xxx
  wire sel_dmem  = (req_addr[31:28] == 4'h8);            // 0x8xxx_xxxx
  wire sel_none  = !(sel_dmem || sel_clint || sel_uart);

  //==========================================================================
  // Request Routing (Combinational)
  //==========================================================================

  // DMEM routing
  assign dmem_valid = req_valid && sel_dmem;
  assign dmem_addr  = req_addr;
  assign dmem_wdata = req_wdata;
  assign dmem_we    = req_we;
  assign dmem_size  = req_size;

  // CLINT routing
  assign clint_valid = req_valid && sel_clint;
  assign clint_addr  = req_addr[15:0];           // Extract 16-bit offset
  assign clint_wdata = req_wdata;
  assign clint_we    = req_we;
  assign clint_size  = req_size;

  // UART routing
  assign uart_valid = req_valid && sel_uart;
  assign uart_addr  = req_addr[2:0];             // Extract 3-bit register offset
  assign uart_wdata = req_wdata[7:0];            // UART is 8-bit only
  assign uart_we    = req_we;

  //==========================================================================
  // Response Multiplexing (Combinational)
  //==========================================================================

  // Ready signal (1-cycle response from all slaves)
  assign req_ready = sel_dmem  ? dmem_ready  :
                     sel_clint ? clint_ready :
                     sel_uart  ? uart_ready  :
                     sel_none  ? 1'b0 : 1'b0;

  // Read data multiplexing
  assign req_rdata = sel_dmem  ? dmem_rdata :
                     sel_clint ? clint_rdata :
                     sel_uart  ? {{56{1'b0}}, uart_rdata} :  // Zero-extend UART 8-bit
                     64'h0;                                   // Default: return 0

  // Bus error detection
  // Error if: (1) valid request to invalid address, or (2) no slave ready
  assign req_error = sel_none && req_valid;

  //==========================================================================
  // Debug Output (Optional)
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
