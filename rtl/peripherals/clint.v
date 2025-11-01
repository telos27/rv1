// clint.v - Core-Local Interruptor (CLINT)
// Implements RISC-V CLINT specification for timer and software interrupts
// Compatible with QEMU virt machine and SiFive devices
// Author: RV1 Project
// Date: 2025-10-26
//
// Memory Map (Base: 0x0200_0000):
//   0x0000 - 0x3FFF: MSIP (Machine Software Interrupt Pending) - 4 bytes per hart
//   0x4000 - 0xBFF7: MTIMECMP (Machine Timer Compare) - 8 bytes per hart
//   0xBFF8 - 0xBFFF: MTIME (Machine Time Counter) - 8 bytes (shared)
//
// Features:
// - 64-bit real-time counter (MTIME)
// - Per-hart timer compare (MTIMECMP)
// - Per-hart software interrupt (MSIP)
// - Timer interrupt assertion when MTIME >= MTIMECMP
// - Little-endian memory access

`include "config/rv_config.vh"

module clint #(
  parameter NUM_HARTS = 1,                    // Number of hardware threads
  parameter BASE_ADDR = 32'h0200_0000         // Base address (informational)
) (
  input  wire                       clk,
  input  wire                       reset_n,

  // Memory-mapped interface
  input  wire                       req_valid,
  input  wire [15:0]                req_addr,    // 16-bit offset from base (64KB range)
  input  wire [63:0]                req_wdata,
  input  wire                       req_we,
  input  wire [2:0]                 req_size,    // 0=byte, 1=half, 2=word, 3=double
  output wire                       req_ready,   // Combinational - always ready
  output reg  [63:0]                req_rdata,

  // Interrupt outputs (one per hart)
  output wire [NUM_HARTS-1:0]       mti_o,       // Machine Timer Interrupt
  output wire [NUM_HARTS-1:0]       msi_o        // Machine Software Interrupt
);

  //===========================================================================
  // Register Definitions
  //===========================================================================

  // MTIME: 64-bit real-time counter (shared across all harts)
  // Increments every clock cycle
  reg [63:0] mtime;

  // MTIMECMP: 64-bit timer compare register (one per hart)
  // When mtime >= mtimecmp[i], mti_o[i] is asserted
  reg [63:0] mtimecmp [0:NUM_HARTS-1];

  // MSIP: Machine Software Interrupt Pending (one bit per hart)
  // Software can write 1 to trigger interrupt, 0 to clear
  reg [NUM_HARTS-1:0] msip;

  //===========================================================================
  // Address Decoding
  //===========================================================================

  // CLINT memory map offsets:
  localparam MSIP_BASE     = 16'h0000;  // 0x0000 - 0x3FFF (4 bytes per hart)
  localparam MTIMECMP_BASE = 16'h4000;  // 0x4000 - 0xBFF7 (8 bytes per hart)
  localparam MTIME_ADDR    = 16'hBFF8;  // 0xBFF8 - 0xBFFF (8 bytes, shared)

  wire is_msip;
  wire is_mtimecmp;
  wire is_mtime;
  wire [7:0] hart_id;          // Hart ID for MSIP/MTIMECMP access
  wire [3:0] mtimecmp_offset;  // Offset within MTIMECMP array

  // Decode which register is being accessed
  // Prioritize MTIME first (most specific), then MTIMECMP, then MSIP
  assign is_mtime    = (req_addr[15:3] == 13'h17FF);  // 0xBFF8-0xBFFF (check top 13 bits)
  assign is_mtimecmp = (req_addr >= 16'h4000) && (req_addr[15:3] != 13'h17FF);  // 0x4000-0xBFF7
  assign is_msip     = (req_addr < 16'h4000);  // 0x0000-0x3FFF

  // Calculate hart ID from address
  // MSIP: 4 bytes per hart starting at 0x0000
  // MTIMECMP: 8 bytes per hart starting at 0x4000
  assign hart_id = is_msip ? (req_addr - MSIP_BASE) >> 2 :           // Divide by 4 for MSIP
                   is_mtimecmp ? (req_addr - MTIMECMP_BASE) >> 3 :   // Divide by 8 for MTIMECMP
                   8'h0;

  // Calculate offset for MTIMECMP access (0-7 for 8-byte register)
  assign mtimecmp_offset = req_addr[2:0] - 4'h0;  // Offset within 8-byte MTIMECMP

  //===========================================================================
  // MTIME Counter (Free-Running)
  //===========================================================================

  // Prescaler for mtime - increment every N cycles
  // Real systems: mtime runs at fixed freq (1-10 MHz), not CPU freq
  // For 50 MHz CPU with 1 MHz mtime: prescaler = 50
  // FreeRTOS expects mtime freq = CPU freq, so prescaler = 1
  localparam MTIME_PRESCALER = 1;
  reg [7:0] mtime_prescaler_count;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      mtime <= 64'h0;
      mtime_prescaler_count <= 8'h0;
    end else begin
      // Increment MTIME every MTIME_PRESCALER cycles
      // Software can also write to MTIME (typically only at boot)
      if (req_valid && req_we && is_mtime) begin
        // Allow writes to MTIME (for initialization)
        case (req_size)
          3'h3: mtime <= req_wdata;                                      // 64-bit write
          3'h2: begin                                                     // 32-bit write
            if (req_addr[2] == 1'b0)
              mtime[31:0] <= req_wdata[31:0];                            // Lower 32 bits
            else
              mtime[63:32] <= req_wdata[31:0];                           // Upper 32 bits
          end
          default: begin
            // Byte/halfword writes not common for MTIME, but support them
            if (req_addr[2:0] == 3'h0) mtime[7:0]   <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h1) mtime[15:8]  <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h2) mtime[23:16] <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h3) mtime[31:24] <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h4) mtime[39:32] <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h5) mtime[47:40] <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h6) mtime[55:48] <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h7) mtime[63:56] <= req_wdata[7:0];
          end
        endcase
        mtime_prescaler_count <= 8'h0;  // Reset prescaler on write
      end else begin
        // Normal operation: increment every MTIME_PRESCALER cycles
        if (mtime_prescaler_count == MTIME_PRESCALER - 1) begin
          mtime <= mtime + 64'h1;
          mtime_prescaler_count <= 8'h0;
        end else begin
          mtime_prescaler_count <= mtime_prescaler_count + 8'h1;
        end
      end
    end
  end

  //===========================================================================
  // MTIMECMP Registers (One per Hart)
  //===========================================================================

  integer i;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      for (i = 0; i < NUM_HARTS; i = i + 1) begin
        mtimecmp[i] <= 64'hFFFF_FFFF_FFFF_FFFF;  // Initialize to max (no interrupt)
      end
    end else begin
      // Handle writes to MTIMECMP
      if (req_valid && req_we && is_mtimecmp && (hart_id < NUM_HARTS)) begin
        `ifdef DEBUG_CLINT
        $display("MTIMECMP WRITE: hart_id=%0d data=0x%016h (addr=0x%04h)", hart_id, req_wdata, req_addr);
        `endif
        case (req_size)
          3'h3: begin  // 64-bit write
            mtimecmp[hart_id] <= req_wdata;
          end
          3'h2: begin  // 32-bit write
            if (req_addr[2] == 1'b0)
              mtimecmp[hart_id][31:0] <= req_wdata[31:0];    // Lower 32 bits
            else
              mtimecmp[hart_id][63:32] <= req_wdata[31:0];   // Upper 32 bits
          end
          3'h1: begin  // 16-bit write
            case (req_addr[2:1])
              2'h0: mtimecmp[hart_id][15:0]  <= req_wdata[15:0];
              2'h1: mtimecmp[hart_id][31:16] <= req_wdata[15:0];
              2'h2: mtimecmp[hart_id][47:32] <= req_wdata[15:0];
              2'h3: mtimecmp[hart_id][63:48] <= req_wdata[15:0];
            endcase
          end
          3'h0: begin  // 8-bit write
            case (req_addr[2:0])
              3'h0: mtimecmp[hart_id][7:0]   <= req_wdata[7:0];
              3'h1: mtimecmp[hart_id][15:8]  <= req_wdata[7:0];
              3'h2: mtimecmp[hart_id][23:16] <= req_wdata[7:0];
              3'h3: mtimecmp[hart_id][31:24] <= req_wdata[7:0];
              3'h4: mtimecmp[hart_id][39:32] <= req_wdata[7:0];
              3'h5: mtimecmp[hart_id][47:40] <= req_wdata[7:0];
              3'h6: mtimecmp[hart_id][55:48] <= req_wdata[7:0];
              3'h7: mtimecmp[hart_id][63:56] <= req_wdata[7:0];
            endcase
          end
        endcase
      end
    end
  end

  //===========================================================================
  // MSIP Registers (Software Interrupt Pending)
  //===========================================================================

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      msip <= {NUM_HARTS{1'b0}};
    end else begin
      // Handle writes to MSIP
      if (req_valid && req_we && is_msip && (hart_id < NUM_HARTS)) begin
        // Only bit 0 is writable, rest are reserved
        msip[hart_id] <= req_wdata[0];
      end
    end
  end

  //===========================================================================
  // Memory Read Logic
  //===========================================================================

  // CLINT is always ready for requests (combinational response)
  assign req_ready = req_valid;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      req_rdata <= 64'h0;
    end else begin
      if (req_valid && !req_we) begin
        // Handle reads
        if (is_mtime) begin
          // Read MTIME (64-bit)
          req_rdata <= mtime;
        end else if (is_mtimecmp && (hart_id < NUM_HARTS)) begin
          // Read MTIMECMP for specific hart
          req_rdata <= mtimecmp[hart_id];
          `ifdef DEBUG_CLINT
          $display("MTIMECMP READ: hart_id=%0d data=0x%016h (addr=0x%04h)",  hart_id, mtimecmp[hart_id], req_addr);
          `endif
        end else if (is_msip && (hart_id < NUM_HARTS)) begin
          // Read MSIP for specific hart (only bit 0 valid)
          req_rdata <= {63'h0, msip[hart_id]};
        end else begin
          // Invalid address or out-of-range hart ID
          req_rdata <= 64'h0;
        end
      end else if (req_valid && req_we) begin
        // Write operations don't return data, but set ready
        req_rdata <= 64'h0;
      end else begin
        req_rdata <= 64'h0;
      end
    end
  end

  //===========================================================================
  // Interrupt Generation Logic
  //===========================================================================

  // Generate timer interrupt for each hart
  // MTI[i] is asserted when mtime >= mtimecmp[i]
  genvar g;
  generate
    for (g = 0; g < NUM_HARTS; g = g + 1) begin : gen_interrupts
      assign mti_o[g] = (mtime >= mtimecmp[g]);
    end
  endgenerate

  // Software interrupts are directly driven by MSIP register
  assign msi_o = msip;

  // Debug interrupt generation
  `ifdef DEBUG_CLINT
  always @(posedge clk) begin
    if (mtime % 100 == 0 && mtime > 0 && mtime < 1000) begin
      $display("[CLINT] mtime=%0d mtimecmp[0]=%0d mti_o[0]=%b", mtime, mtimecmp[0], mti_o[0]);
    end
    if (mti_o[0] && mtime < 1000) begin
      $display("[CLINT] TIMER INTERRUPT ASSERTED: mtime=%0d >= mtimecmp[0]=%0d", mtime, mtimecmp[0]);
    end
    // Debug mtime value periodically during FreeRTOS init
    if (mtime % 10000 == 0 && mtime >= 50000 && mtime <= 150000) begin
      $display("[CLINT_MTIME] cycle=%0d mtime=%0d (0x%h)", mtime, mtime, mtime);
    end
  end
  `endif

  //===========================================================================
  // Debug Monitoring (Optional)
  //===========================================================================

  `ifdef DEBUG_CLINT
  // Monitor for debugging (Icarus Verilog compatible)
  always @(posedge clk) begin
    if (req_valid) begin
      $display("[CLINT-REQ] Cycle %0d: req_valid=%b addr=0x%04h we=%b wdata=0x%016h size=%0d ready=%b | is_mtime=%b is_mtimecmp=%b is_msip=%b hart_id=%0d",
               $time/10, req_valid, req_addr, req_we, req_wdata, req_size, req_ready, is_mtime, is_mtimecmp, is_msip, hart_id);
    end
    if (req_valid && req_we && is_mtime) begin
      $display("  -> MTIME WRITE: 0x%016h (cycle %0d)", req_wdata, $time/10);
    end
    if (req_valid && req_we && is_mtimecmp) begin
      $display("  -> MTIMECMP[%0d] WRITE: 0x%016h size=%0d addr[2]=%b (cycle %0d) | mtime=%0d | mtimecmp_before=0x%016h", hart_id, req_wdata, req_size, req_addr[2], $time/10, mtime, mtimecmp[hart_id]);
    end
  end

  // Display MTIMECMP value after write completes
  always @(posedge clk) begin
    if (req_valid && req_we && is_mtimecmp && req_ready) begin
      $display("  -> MTIMECMP[%0d] AFTER WRITE: 0x%016h (cycle %0d)", hart_id, mtimecmp[hart_id], $time/10);
    end
    // Monitor timer interrupt triggering
    if (mtime >= 53800 && mtime <= 54000) begin
      $display("[CLINT-TIMER] mtime=%0d mtimecmp[0]=0x%016h mti_o[0]=%b (cycle %0d)", mtime, mtimecmp[0], mti_o[0], $time/10);
    end
    if (req_valid && req_we && is_msip) begin
      $display("  -> MSIP[%0d] WRITE: %b (cycle %0d)", hart_id, req_wdata[0], $time/10);
    end
  end
  `endif

endmodule
