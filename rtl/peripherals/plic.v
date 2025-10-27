// plic.v - Platform-Level Interrupt Controller (PLIC)
// Implements RISC-V PLIC specification for external device interrupts
// Compatible with QEMU virt machine and SiFive devices
// Author: RV1 Project
// Date: 2025-10-27
//
// Memory Map (Base: 0x0C00_0000):
//   0x000000 - 0x000FFF: Interrupt Source Priorities (1-31, 4 bytes each)
//   0x001000 - 0x001FFF: Interrupt Pending Bits (read-only)
//   0x002000 - 0x00207F: M-mode Hart 0 Interrupt Enables (32 sources, 4 bytes)
//   0x002080 - 0x0020FF: S-mode Hart 0 Interrupt Enables (32 sources, 4 bytes)
//   0x200000 - 0x200003: M-mode Hart 0 Priority Threshold
//   0x200004 - 0x200007: M-mode Hart 0 Claim/Complete
//   0x201000 - 0x201003: S-mode Hart 0 Priority Threshold
//   0x201004 - 0x201007: S-mode Hart 0 Claim/Complete
//
// Features:
// - 32 interrupt sources (source 0 reserved, 1-31 usable)
// - Priority-based arbitration (1-7, 0=never interrupt)
// - Per-hart, per-mode interrupt enables
// - Claim/complete mechanism for interrupt acknowledgment
// - Supports M-mode and S-mode contexts

`include "config/rv_config.vh"

module plic #(
  parameter NUM_SOURCES = 32,           // Number of interrupt sources (including 0)
  parameter NUM_HARTS = 1,              // Number of hardware threads
  parameter BASE_ADDR = 32'h0C00_0000   // Base address (informational)
) (
  input  wire                       clk,
  input  wire                       reset_n,

  // Memory-mapped interface
  input  wire                       req_valid,
  input  wire [23:0]                req_addr,    // 24-bit offset from base (16MB range)
  input  wire [31:0]                req_wdata,
  input  wire                       req_we,
  output reg                        req_ready,
  output reg  [31:0]                req_rdata,

  // Interrupt source inputs (1-31, source 0 is reserved)
  input  wire [NUM_SOURCES-1:0]     irq_sources,

  // Interrupt outputs to core (per hart, per mode)
  output wire [NUM_HARTS-1:0]       mei_o,        // Machine External Interrupt
  output wire [NUM_HARTS-1:0]       sei_o         // Supervisor External Interrupt
);

  //===========================================================================
  // Register Definitions
  //===========================================================================

  // Interrupt source priorities (0-7, where 0 = never interrupt)
  // priorities[0] is reserved and always 0
  reg [2:0] priorities [0:NUM_SOURCES-1];

  // Interrupt pending bits (read-only, set by hardware)
  reg [NUM_SOURCES-1:0] pending;

  // Interrupt enables (per hart, per mode)
  // For single hart: enables_m[0] = M-mode, enables_s[0] = S-mode
  reg [NUM_SOURCES-1:0] enables_m [0:NUM_HARTS-1];
  reg [NUM_SOURCES-1:0] enables_s [0:NUM_HARTS-1];

  // Priority thresholds (per hart, per mode)
  // Interrupts with priority <= threshold are masked
  reg [2:0] threshold_m [0:NUM_HARTS-1];
  reg [2:0] threshold_s [0:NUM_HARTS-1];

  // Claim/Complete tracking (per hart, per mode)
  // Stores the currently claimed interrupt ID (0 = no claim)
  reg [4:0] claimed_m [0:NUM_HARTS-1];  // 5 bits for 0-31 range
  reg [4:0] claimed_s [0:NUM_HARTS-1];

  //===========================================================================
  // Address Decode
  //===========================================================================

  // PLIC memory map regions
  localparam ADDR_PRIORITIES    = 24'h000000;  // 0x000000 - 0x00007F (32 sources × 4B)
  localparam ADDR_PENDING       = 24'h001000;  // 0x001000 - 0x001003 (1 word for 32 bits)
  localparam ADDR_ENABLE_M      = 24'h002000;  // 0x002000 - 0x002003 (1 word for hart 0 M-mode)
  localparam ADDR_ENABLE_S      = 24'h002080;  // 0x002080 - 0x002083 (1 word for hart 0 S-mode)
  localparam ADDR_THRESHOLD_M   = 24'h200000;  // 0x200000 - 0x200003 (hart 0 M-mode)
  localparam ADDR_CLAIM_M       = 24'h200004;  // 0x200004 - 0x200007 (hart 0 M-mode)
  localparam ADDR_THRESHOLD_S   = 24'h201000;  // 0x201000 - 0x201003 (hart 0 S-mode)
  localparam ADDR_CLAIM_S       = 24'h201004;  // 0x201004 - 0x201007 (hart 0 S-mode)

  wire is_priority;
  wire is_pending;
  wire is_enable_m;
  wire is_enable_s;
  wire is_threshold_m;
  wire is_claim_m;
  wire is_threshold_s;
  wire is_claim_s;

  wire [4:0] priority_id;  // Which source priority (0-31)

  // Decode address
  assign is_priority    = (req_addr < 24'h001000);  // 0x000000 - 0x000FFF
  assign is_pending     = (req_addr == ADDR_PENDING);
  assign is_enable_m    = (req_addr == ADDR_ENABLE_M);
  assign is_enable_s    = (req_addr == ADDR_ENABLE_S);
  assign is_threshold_m = (req_addr == ADDR_THRESHOLD_M);
  assign is_claim_m     = (req_addr == ADDR_CLAIM_M);
  assign is_threshold_s = (req_addr == ADDR_THRESHOLD_S);
  assign is_claim_s     = (req_addr == ADDR_CLAIM_S);

  // Calculate source ID for priority access (address / 4)
  assign priority_id = req_addr[6:2];  // Divide by 4 to get source ID

  //===========================================================================
  // Interrupt Pending Logic
  //===========================================================================

  integer i;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      pending <= {NUM_SOURCES{1'b0}};
    end else begin
      // Update pending bits based on interrupt sources
      // Source 0 is always 0 (reserved)
      pending[0] <= 1'b0;
      for (i = 1; i < NUM_SOURCES; i = i + 1) begin
        // Set pending if source is active
        if (irq_sources[i] && !pending[i]) begin
          pending[i] <= 1'b1;
        end
        // Clear pending if claimed (handled in claim logic below)
      end
    end
  end

  //===========================================================================
  // Priority Arbitration (Find Highest Priority Pending Interrupt)
  //===========================================================================

  // For M-mode hart 0
  reg [4:0] highest_id_m;
  reg [2:0] highest_pri_m;

  // For S-mode hart 0
  reg [4:0] highest_id_s;
  reg [2:0] highest_pri_s;

  always @(*) begin
    // M-mode arbitration
    highest_id_m = 5'd0;
    highest_pri_m = 3'd0;

    for (i = 1; i < NUM_SOURCES; i = i + 1) begin
      if (pending[i] && enables_m[0][i] && (priorities[i] > threshold_m[0])) begin
        if (priorities[i] > highest_pri_m) begin
          highest_id_m = i[4:0];
          highest_pri_m = priorities[i];
        end
      end
    end

    // S-mode arbitration
    highest_id_s = 5'd0;
    highest_pri_s = 3'd0;

    for (i = 1; i < NUM_SOURCES; i = i + 1) begin
      if (pending[i] && enables_s[0][i] && (priorities[i] > threshold_s[0])) begin
        if (priorities[i] > highest_pri_s) begin
          highest_id_s = i[4:0];
          highest_pri_s = priorities[i];
        end
      end
    end
  end

  //===========================================================================
  // Interrupt Output Generation
  //===========================================================================

  // Assert MEI if there's a pending interrupt for M-mode
  assign mei_o[0] = (highest_id_m != 5'd0);

  // Assert SEI if there's a pending interrupt for S-mode
  assign sei_o[0] = (highest_id_s != 5'd0);

  //===========================================================================
  // Memory-Mapped Register Access
  //===========================================================================

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset all configuration registers
      for (i = 0; i < NUM_SOURCES; i = i + 1) begin
        priorities[i] <= 3'd0;
      end
      for (i = 0; i < NUM_HARTS; i = i + 1) begin
        enables_m[i] <= {NUM_SOURCES{1'b0}};
        enables_s[i] <= {NUM_SOURCES{1'b0}};
        threshold_m[i] <= 3'd0;
        threshold_s[i] <= 3'd0;
        claimed_m[i] <= 5'd0;
        claimed_s[i] <= 5'd0;
      end
      req_rdata <= 32'h0;
      req_ready <= 1'b0;
    end else begin
      req_ready <= req_valid;  // Single-cycle response

      if (req_valid && req_we) begin
        //=====================================================================
        // Write Operations
        //=====================================================================

        if (is_priority && priority_id < NUM_SOURCES && priority_id != 0) begin
          // Write to interrupt source priority (source 0 is read-only)
          priorities[priority_id] <= req_wdata[2:0];  // 3-bit priority
        end else if (is_enable_m) begin
          // Write to M-mode interrupt enables (hart 0)
          enables_m[0] <= req_wdata[NUM_SOURCES-1:0];
        end else if (is_enable_s) begin
          // Write to S-mode interrupt enables (hart 0)
          enables_s[0] <= req_wdata[NUM_SOURCES-1:0];
        end else if (is_threshold_m) begin
          // Write to M-mode priority threshold (hart 0)
          threshold_m[0] <= req_wdata[2:0];
        end else if (is_threshold_s) begin
          // Write to S-mode priority threshold (hart 0)
          threshold_s[0] <= req_wdata[2:0];
        end else if (is_claim_m) begin
          // Complete M-mode interrupt (write claimed ID back)
          if (req_wdata[4:0] == claimed_m[0] && claimed_m[0] != 5'd0) begin
            pending[claimed_m[0]] <= 1'b0;  // Clear pending bit
            claimed_m[0] <= 5'd0;           // Clear claimed ID
          end
        end else if (is_claim_s) begin
          // Complete S-mode interrupt (write claimed ID back)
          if (req_wdata[4:0] == claimed_s[0] && claimed_s[0] != 5'd0) begin
            pending[claimed_s[0]] <= 1'b0;  // Clear pending bit
            claimed_s[0] <= 5'd0;           // Clear claimed ID
          end
        end
        // Pending register is read-only, writes are ignored

        req_rdata <= 32'h0;  // Writes don't return data

      end else if (req_valid && !req_we) begin
        //=====================================================================
        // Read Operations
        //=====================================================================

        if (is_priority && priority_id < NUM_SOURCES) begin
          // Read interrupt source priority
          req_rdata <= {29'h0, priorities[priority_id]};
        end else if (is_pending) begin
          // Read interrupt pending bits (all 32 sources in 1 word)
          req_rdata <= pending;
        end else if (is_enable_m) begin
          // Read M-mode interrupt enables (hart 0)
          req_rdata <= enables_m[0];
        end else if (is_enable_s) begin
          // Read S-mode interrupt enables (hart 0)
          req_rdata <= enables_s[0];
        end else if (is_threshold_m) begin
          // Read M-mode priority threshold (hart 0)
          req_rdata <= {29'h0, threshold_m[0]};
        end else if (is_threshold_s) begin
          // Read S-mode priority threshold (hart 0)
          req_rdata <= {29'h0, threshold_s[0]};
        end else if (is_claim_m) begin
          // Claim M-mode interrupt (returns highest-priority pending ID)
          req_rdata <= {27'h0, highest_id_m};
          if (highest_id_m != 5'd0) begin
            claimed_m[0] <= highest_id_m;  // Record claimed interrupt
            // Don't clear pending yet - wait for completion write
          end
        end else if (is_claim_s) begin
          // Claim S-mode interrupt (returns highest-priority pending ID)
          req_rdata <= {27'h0, highest_id_s};
          if (highest_id_s != 5'd0) begin
            claimed_s[0] <= highest_id_s;  // Record claimed interrupt
            // Don't clear pending yet - wait for completion write
          end
        end else begin
          // Invalid address
          req_rdata <= 32'h0;
        end

      end else begin
        req_rdata <= 32'h0;
      end
    end
  end

  //===========================================================================
  // Debug Monitoring (Optional)
  //===========================================================================

  `ifdef DEBUG_PLIC
  always @(posedge clk) begin
    if (req_valid) begin
      if (req_we) begin
        if (is_priority)
          $display("PLIC[@%t]: WRITE Priority[%0d] = %0d", $time, priority_id, req_wdata[2:0]);
        if (is_enable_m)
          $display("PLIC[@%t]: WRITE Enable_M = 0x%08h", $time, req_wdata);
        if (is_enable_s)
          $display("PLIC[@%t]: WRITE Enable_S = 0x%08h", $time, req_wdata);
        if (is_threshold_m)
          $display("PLIC[@%t]: WRITE Threshold_M = %0d", $time, req_wdata[2:0]);
        if (is_threshold_s)
          $display("PLIC[@%t]: WRITE Threshold_S = %0d", $time, req_wdata[2:0]);
        if (is_claim_m)
          $display("PLIC[@%t]: COMPLETE M-mode IRQ %0d", $time, req_wdata[4:0]);
        if (is_claim_s)
          $display("PLIC[@%t]: COMPLETE S-mode IRQ %0d", $time, req_wdata[4:0]);
      end else begin
        if (is_claim_m && highest_id_m != 0)
          $display("PLIC[@%t]: CLAIM M-mode IRQ %0d", $time, highest_id_m);
        if (is_claim_s && highest_id_s != 0)
          $display("PLIC[@%t]: CLAIM S-mode IRQ %0d", $time, highest_id_s);
      end
    end
    if (mei_o[0])
      $display("PLIC[@%t]: MEI asserted (IRQ %0d, pri %0d)", $time, highest_id_m, highest_pri_m);
    if (sei_o[0])
      $display("PLIC[@%t]: SEI asserted (IRQ %0d, pri %0d)", $time, highest_id_s, highest_pri_s);
  end
  `endif

endmodule
