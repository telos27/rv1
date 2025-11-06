// mmu.v - Memory Management Unit with TLB
// Implements RISC-V Sv32 (RV32) and Sv39 (RV64) virtual memory translation
// Includes a Translation Lookaside Buffer (TLB) for performance
// Supports page fault exceptions
// Author: RV1 Project
// Date: 2025-10-11

`include "config/rv_config.vh"

module mmu #(
  parameter XLEN = `XLEN,
  parameter TLB_ENTRIES = `TLB_ENTRIES  // Number of TLB entries (power of 2)
) (
  input  wire             clk,
  input  wire             reset_n,

  // Virtual address translation request
  input  wire             req_valid,        // Translation request valid
  input  wire [XLEN-1:0]  req_vaddr,        // Virtual address to translate
  input  wire             req_is_store,     // 1=store, 0=load
  input  wire             req_is_fetch,     // 1=instruction fetch, 0=data access
  input  wire [2:0]       req_size,         // Access size (0=byte, 1=half, 2=word, 3=double)
  output reg              req_ready,        // Translation complete
  output reg  [XLEN-1:0]  req_paddr,        // Physical address (translated)
  output reg              req_page_fault,   // Page fault exception
  output reg  [XLEN-1:0]  req_fault_vaddr,  // Faulting virtual address

  // Memory interface for page table walks
  output reg              ptw_req_valid,    // Page table walk memory request
  output reg  [XLEN-1:0]  ptw_req_addr,     // Physical address for PTW
  input  wire             ptw_req_ready,    // Memory ready
  input  wire [XLEN-1:0]  ptw_resp_data,    // Page table entry data
  input  wire             ptw_resp_valid,   // Response valid

  // CSR interface
  input  wire [XLEN-1:0]  satp,             // SATP register (page table base + mode)
  input  wire [1:0]       privilege_mode,   // Current privilege mode (0=U, 1=S, 3=M)
  input  wire             mstatus_sum,      // Supervisor User Memory access
  input  wire             mstatus_mxr,      // Make eXecutable Readable

  // TLB flush control
  input  wire             tlb_flush_all,    // Flush entire TLB
  input  wire             tlb_flush_vaddr,  // Flush specific virtual address
  input  wire [XLEN-1:0]  tlb_flush_addr    // Address to flush (if tlb_flush_vaddr)
);

  // =========================================================================
  // RISC-V Virtual Memory Parameters
  // =========================================================================

  // Sv32 (RV32): 2-level page table, 4KB pages
  // Sv39 (RV64): 3-level page table, 4KB pages
  localparam PAGE_SHIFT = 12;                    // 4KB pages
  localparam PAGE_SIZE = 1 << PAGE_SHIFT;        // 4096 bytes

  // For Sv32 (RV32)
  localparam SV32_LEVELS = 2;
  localparam SV32_VPN_BITS = 10;                 // VPN[1:0] each 10 bits
  localparam SV32_PPN_BITS = 22;                 // PPN = 22 bits

  // For Sv39 (RV64)
  localparam SV39_LEVELS = 3;
  localparam SV39_VPN_BITS = 9;                  // VPN[2:0] each 9 bits
  localparam SV39_PPN_BITS = 44;                 // PPN = 44 bits

  // SATP mode encodings
  localparam SATP_MODE_BARE = (XLEN == 32) ? 4'h0 : 4'h0;  // No translation
  localparam SATP_MODE_SV32 = (XLEN == 32) ? 4'h1 : 4'h0;  // Sv32 (RV32 only)
  localparam SATP_MODE_SV39 = (XLEN == 64) ? 4'h8 : 4'h0;  // Sv39 (RV64 only)

  // PTE (Page Table Entry) bit fields
  localparam PTE_V = 0;  // Valid
  localparam PTE_R = 1;  // Readable
  localparam PTE_W = 2;  // Writable
  localparam PTE_X = 3;  // Executable
  localparam PTE_U = 4;  // User accessible
  localparam PTE_G = 5;  // Global mapping
  localparam PTE_A = 6;  // Accessed
  localparam PTE_D = 7;  // Dirty

  // =========================================================================
  // SATP Register Decoding
  // =========================================================================

  wire [3:0] satp_mode;
  wire [XLEN-1:0] satp_ppn;
  wire translation_enabled;

  generate
    if (XLEN == 32) begin : gen_satp_sv32
      assign satp_mode = satp[31:31];  // 1 bit mode for Sv32
      assign satp_ppn = {{10{1'b0}}, satp[21:0]};  // 22-bit PPN
      assign translation_enabled = (satp_mode == 1'b1) && (privilege_mode != 2'b11);
    end else begin : gen_satp_sv39
      assign satp_mode = satp[63:60];  // 4 bits mode for Sv39
      assign satp_ppn = {{20{1'b0}}, satp[43:0]};  // 44-bit PPN
      assign translation_enabled = (satp_mode == 4'h8) && (privilege_mode != 2'b11);
    end
  endgenerate

  // =========================================================================
  // TLB Structure
  // =========================================================================

  // TLB entry structure
  reg                   tlb_valid [0:TLB_ENTRIES-1];
  reg [XLEN-1:0]        tlb_vpn   [0:TLB_ENTRIES-1];  // Virtual page number
  reg [XLEN-1:0]        tlb_ppn   [0:TLB_ENTRIES-1];  // Physical page number
  reg [7:0]             tlb_pte   [0:TLB_ENTRIES-1];  // PTE flags (V,R,W,X,U,G,A,D)
  reg [XLEN-1:0]        tlb_level [0:TLB_ENTRIES-1];  // Page level (for superpages)

  // TLB replacement policy: simple round-robin
  reg [$clog2(TLB_ENTRIES)-1:0] tlb_replace_idx;

  // =========================================================================
  // Page Table Walk State Machine
  // =========================================================================

  localparam PTW_IDLE       = 3'b000;
  localparam PTW_LEVEL_0    = 3'b001;
  localparam PTW_LEVEL_1    = 3'b010;
  localparam PTW_LEVEL_2    = 3'b011;
  localparam PTW_UPDATE_TLB = 3'b100;
  localparam PTW_FAULT      = 3'b101;

  reg [2:0] ptw_state;
  reg [2:0] ptw_level;           // Current page table level
  reg [XLEN-1:0] ptw_pte_addr;   // Address of current PTE
  reg [XLEN-1:0] ptw_pte_data;   // Current PTE data
  reg [XLEN-1:0] ptw_vpn_save;   // Saved VPN during walk
  reg [XLEN-1:0] ptw_vaddr_save; // Saved full virtual address during walk
  reg ptw_is_store_save;         // Saved access type
  reg ptw_is_fetch_save;         // Saved fetch flag
  reg [1:0] ptw_priv_save;       // Saved privilege mode
  reg ptw_sum_save;              // Saved SUM bit
  reg ptw_mxr_save;              // Saved MXR bit

  // =========================================================================
  // VPN Extraction
  // =========================================================================

  function [XLEN-1:0] extract_vpn;
    input [XLEN-1:0] vaddr;
    input integer level;
    begin
      if (XLEN == 32) begin
        // Sv32: VPN[1] = bits[31:22], VPN[0] = bits[21:12]
        case (level)
          0: extract_vpn = vaddr[21:12];
          1: extract_vpn = vaddr[31:22];
          default: extract_vpn = 0;
        endcase
      end else begin
        // Sv39: VPN[2] = bits[38:30], VPN[1] = bits[29:21], VPN[0] = bits[20:12]
        case (level)
          0: extract_vpn = vaddr[20:12];
          1: extract_vpn = vaddr[29:21];
          2: extract_vpn = vaddr[38:30];
          default: extract_vpn = 0;
        endcase
      end
    end
  endfunction

  function [XLEN-1:0] get_full_vpn;
    input [XLEN-1:0] vaddr;
    begin
      if (XLEN == 32) begin
        // Sv32: VPN = bits[31:12] (20 bits)
        get_full_vpn = {{(XLEN-20){1'b0}}, vaddr[31:12]};
      end else begin
        // Sv39: VPN = bits[38:12] (27 bits)
        get_full_vpn = {{(XLEN-27){1'b0}}, vaddr[38:12]};
      end
    end
  endfunction

  // =========================================================================
  // TLB Lookup
  // =========================================================================

  reg tlb_hit;
  reg [$clog2(TLB_ENTRIES)-1:0] tlb_hit_idx;
  reg [XLEN-1:0] tlb_ppn_out;
  reg [7:0] tlb_pte_out;
  reg [XLEN-1:0] tlb_level_out;
  reg perm_check_result;  // Debug: store permission check result

  integer i;
  always @(*) begin
    tlb_hit = 0;
    tlb_hit_idx = 0;
    tlb_ppn_out = 0;
    tlb_pte_out = 0;
    tlb_level_out = 0;

    if (translation_enabled && req_valid) begin
      for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
        if (tlb_valid[i] && (tlb_vpn[i] == get_full_vpn(req_vaddr))) begin
          tlb_hit = 1;
          tlb_hit_idx = i[$clog2(TLB_ENTRIES)-1:0];
          tlb_ppn_out = tlb_ppn[i];
          tlb_pte_out = tlb_pte[i];
          tlb_level_out = tlb_level[i];
        end
      end
    end
  end

  // =========================================================================
  // Permission Checking
  // =========================================================================

  function check_permission;
    input [7:0] pte_flags;
    input is_store;
    input is_fetch;
    input [1:0] priv_mode;
    input sum;
    input mxr;
    begin
      check_permission = 1;

      // Check valid bit
      if (!pte_flags[PTE_V]) begin
        check_permission = 0;
      end
      // Check for leaf PTE (at least one of R, X must be set)
      else if (!pte_flags[PTE_R] && !pte_flags[PTE_W] && !pte_flags[PTE_X]) begin
        check_permission = 0;  // Non-leaf PTE at wrong level
      end
      // Check write permission (W=1 requires R=1)
      else if (pte_flags[PTE_W] && !pte_flags[PTE_R]) begin
        check_permission = 0;
      end
      // Check user mode access
      else if (priv_mode == 2'b00) begin  // User mode
        if (!pte_flags[PTE_U]) begin
          check_permission = 0;  // User accessing supervisor page
        end
      end
      else if (priv_mode == 2'b01) begin  // Supervisor mode
        if (pte_flags[PTE_U] && !sum) begin
          check_permission = 0;  // Supervisor accessing user page without SUM
        end
      end

      // Check specific access type
      if (check_permission) begin
        if (is_fetch) begin
          check_permission = pte_flags[PTE_X];
        end else if (is_store) begin
          check_permission = pte_flags[PTE_W];
        end else begin
          // Load: need R or (X and MXR)
          check_permission = pte_flags[PTE_R] || (pte_flags[PTE_X] && mxr);
        end
      end
    end
  endfunction

  // =========================================================================
  // Physical Address Construction
  // =========================================================================

  // Construct physical address from PPN and virtual address based on page level
  // For Sv32:
  //   - Level 1 (megapage, 4MB): PA = {PPN[1], VA[21:0]}
  //   - Level 0 (page, 4KB):     PA = {PPN[1], PPN[0], VA[11:0]}
  // For Sv39:
  //   - Level 2 (gigapage, 1GB): PA = {PPN[2], VA[29:0]}
  //   - Level 1 (megapage, 2MB): PA = {PPN[2], PPN[1], VA[20:0]}
  //   - Level 0 (page, 4KB):     PA = {PPN[2], PPN[1], PPN[0], VA[11:0]}
  function [XLEN-1:0] construct_pa;
    input [XLEN-1:0] ppn;    // Full PPN from PTE
    input [XLEN-1:0] vaddr;  // Virtual address
    input [XLEN-1:0] level;  // Page table level
    begin
      if (XLEN == 32) begin
        // Sv32
        case (level)
          0: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};     // 4KB: {PPN, VA[11:0]}
          1: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:10], vaddr[PAGE_SHIFT+9:0]};    // 4MB: {PPN[1], VA[21:0]}
          default: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};
        endcase
      end else begin
        // Sv39
        case (level)
          0: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};     // 4KB: {PPN, VA[11:0]}
          1: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:9], vaddr[PAGE_SHIFT+8:0]};     // 2MB: {PPN[2:1], VA[20:0]}
          2: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:18], vaddr[PAGE_SHIFT+17:0]};   // 1GB: {PPN[2], VA[29:0]}
          default: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};
        endcase
      end
    end
  endfunction

  // =========================================================================
  // Page Table Walk Logic
  // =========================================================================

  wire [XLEN-1:0] max_levels = (XLEN == 32) ? SV32_LEVELS : SV39_LEVELS;
  wire [XLEN-1:0] pte_size = (XLEN == 32) ? 4 : 8;  // PTE is 4 bytes (RV32) or 8 bytes (RV64)

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      ptw_state <= PTW_IDLE;
      ptw_level <= 0;
      ptw_pte_addr <= 0;
      ptw_pte_data <= 0;
      ptw_vpn_save <= 0;
      ptw_vaddr_save <= 0;
      ptw_is_store_save <= 0;
      ptw_is_fetch_save <= 0;
      ptw_priv_save <= 0;
      ptw_sum_save <= 0;
      ptw_mxr_save <= 0;
      ptw_req_valid <= 0;
      ptw_req_addr <= 0;
      req_ready <= 0;
      req_paddr <= 0;
      req_page_fault <= 0;
      req_fault_vaddr <= 0;
      tlb_replace_idx <= 0;

      // Initialize TLB
      for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
        tlb_valid[i] <= 0;
        tlb_vpn[i] <= 0;
        tlb_ppn[i] <= 0;
        tlb_pte[i] <= 0;
        tlb_level[i] <= 0;
      end
    end else begin
      // Default outputs (keep req_ready and req_paddr valid in bare mode)
      if (!translation_enabled && req_valid) begin
        req_ready <= 1'b1;
        req_paddr <= req_vaddr;  // Bare mode: VA == PA
      end else begin
        req_ready <= 1'b0;
        req_paddr <= req_paddr;  // Hold previous value
      end
      req_page_fault <= 0;
      // Don't clear ptw_req_valid by default - let state machine control it
      // Otherwise, PTW handshake breaks when waiting for ptw_resp_valid
      // ptw_req_valid <= 0;  // BUG: This clears the request before response arrives!

      // TLB flush logic
      if (tlb_flush_all) begin
        for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
          tlb_valid[i] <= 0;
        end
      end else if (tlb_flush_vaddr) begin
        for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
          if (tlb_vpn[i] == get_full_vpn(tlb_flush_addr)) begin
            tlb_valid[i] <= 0;
          end
        end
      end

      case (ptw_state)
        PTW_IDLE: begin
          if (req_valid) begin
            // Check if translation is enabled
            if (!translation_enabled) begin
              // Bare mode: direct mapping (req_ready and req_paddr already set in default)
              // $display("MMU: Bare mode, VA=0x%h -> PA=0x%h", req_vaddr, req_vaddr);
              // Note: req_paddr and req_ready are set in the default case above
            end else begin
              // Check TLB
              // $display("MMU: Translation mode, VA=0x%h, TLB hit=%b", req_vaddr, tlb_hit);
              if (tlb_hit) begin
                // TLB hit: check permissions
                perm_check_result = check_permission(tlb_pte_out, req_is_store, req_is_fetch,
                                                     privilege_mode, mstatus_sum, mstatus_mxr);
                // $display("MMU: TLB HIT VA=0x%h PTE=0x%h[U=%b] priv=%b sum=%b result=%b",
                //          req_vaddr, tlb_pte_out, tlb_pte_out[PTE_U], privilege_mode, mstatus_sum, perm_check_result);
                if (perm_check_result) begin
                  // Permission granted - construct PA based on page level
                  req_paddr <= construct_pa(tlb_ppn_out, req_vaddr, tlb_level_out);
                  req_ready <= 1;
                  // $display("MMU: TLB HIT - VA=0x%h -> PA=0x%h (PPN=0x%h, level=%0d)",
                  //          req_vaddr, construct_pa(tlb_ppn_out, req_vaddr, tlb_level_out), tlb_ppn_out, tlb_level_out);
                end else begin
                  // Permission denied
                  $display("MMU: Permission DENIED - PAGE FAULT!");
                  req_page_fault <= 1;
                  req_fault_vaddr <= req_vaddr;
                  req_ready <= 1;
                end
              end else begin
                // TLB miss: start page table walk
                ptw_vpn_save <= get_full_vpn(req_vaddr);
                ptw_vaddr_save <= req_vaddr;
                ptw_is_store_save <= req_is_store;
                ptw_is_fetch_save <= req_is_fetch;
                ptw_priv_save <= privilege_mode;
                ptw_sum_save <= mstatus_sum;
                ptw_mxr_save <= mstatus_mxr;
                ptw_level <= max_levels - 1;  // Start at highest level

                // Calculate first PTE address
                // a = satp.ppn * PAGESIZE + va.vpn[i] * PTESIZE
                if (XLEN == 32) begin
                  ptw_pte_addr <= (satp_ppn << PAGE_SHIFT) +
                                  (extract_vpn(req_vaddr, max_levels - 1) << 2);
                end else begin
                  ptw_pte_addr <= (satp_ppn << PAGE_SHIFT) +
                                  (extract_vpn(req_vaddr, max_levels - 1) << 3);
                end

                ptw_state <= PTW_LEVEL_0;
              end
            end
          end
        end

        PTW_LEVEL_0, PTW_LEVEL_1, PTW_LEVEL_2: begin
          // Issue memory request for PTE
          if (!ptw_req_valid) begin
            ptw_req_valid <= 1;
            ptw_req_addr <= ptw_pte_addr;
          end else if (ptw_req_ready && ptw_resp_valid) begin
            // Got PTE response
            ptw_pte_data <= ptw_resp_data;
            ptw_req_valid <= 0;

            // First check if PTE is valid
            if (!ptw_resp_data[PTE_V]) begin
              // Invalid PTE: page fault
              ptw_state <= PTW_FAULT;
            // Check if this is a leaf PTE
            end else if (ptw_resp_data[PTE_R] || ptw_resp_data[PTE_X]) begin
              // Leaf PTE found: check permissions
              if (check_permission(ptw_resp_data[7:0], ptw_is_store_save, ptw_is_fetch_save,
                                   ptw_priv_save, ptw_sum_save, ptw_mxr_save)) begin
                // Permission granted: update TLB
                ptw_state <= PTW_UPDATE_TLB;
              end else begin
                // Permission denied
                ptw_state <= PTW_FAULT;
              end
            end else if (ptw_level == 0) begin
              // Non-leaf at level 0: fault
              ptw_state <= PTW_FAULT;
            end else begin
              // Non-leaf PTE: go to next level
              ptw_level <= ptw_level - 1;

              // Calculate next PTE address
              // a = pte.ppn * PAGESIZE + va.vpn[i-1] * PTESIZE
              if (XLEN == 32) begin
                ptw_pte_addr <= (ptw_resp_data[31:10] << PAGE_SHIFT) +
                                (extract_vpn(req_vaddr, ptw_level - 1) << 2);
              end else begin
                ptw_pte_addr <= (ptw_resp_data[53:10] << PAGE_SHIFT) +
                                (extract_vpn(req_vaddr, ptw_level - 1) << 3);
              end

              // Stay in PTW state (next level)
              case (ptw_level)
                2: ptw_state <= PTW_LEVEL_1;
                1: ptw_state <= PTW_LEVEL_0;
                default: ptw_state <= PTW_FAULT;
              endcase
            end
          end else begin
            // Waiting for response - hold request valid
            ptw_req_valid <= 1;
          end
        end

        PTW_UPDATE_TLB: begin
          // Update TLB with new translation
          tlb_valid[tlb_replace_idx] <= 1;
          tlb_vpn[tlb_replace_idx] <= ptw_vpn_save;

          // Extract PPN from PTE
          // RV32 Sv32: PPN is 22 bits [31:10], pad to XLEN (32-22=10 zeros)
          // RV64 Sv39: PPN is 44 bits [53:10], pad to XLEN (64-44=20 zeros)
          if (XLEN == 32) begin
            tlb_ppn[tlb_replace_idx] <= {{10{1'b0}}, ptw_pte_data[31:10]};
          end else begin
            tlb_ppn[tlb_replace_idx] <= {{20{1'b0}}, ptw_pte_data[53:10]};
          end

          tlb_pte[tlb_replace_idx] <= ptw_pte_data[7:0];
          tlb_level[tlb_replace_idx] <= ptw_level;

          // Debug output
          $display("MMU: TLB[%0d] updated: VPN=0x%h, PPN=0x%h, PTE=0x%h",
                   tlb_replace_idx, ptw_vpn_save, ptw_pte_data[53:10], ptw_pte_data[7:0]);

          // Update replacement index
          tlb_replace_idx <= tlb_replace_idx + 1;

          // Check permissions for the current access (same as TLB hit path)
          perm_check_result = check_permission(ptw_pte_data[7:0], ptw_is_store_save, ptw_is_fetch_save,
                                               ptw_priv_save, ptw_sum_save, ptw_mxr_save);
          // $display("MMU: PTW complete VA=0x%h PTE=0x%h[U=%b] priv=%b sum=%b result=%b",
          //          ptw_vaddr_save, ptw_pte_data[7:0], ptw_pte_data[PTE_U], ptw_priv_save, ptw_sum_save, perm_check_result);

          if (perm_check_result) begin
            // Permission granted - generate physical address
            if (XLEN == 32) begin
              req_paddr <= construct_pa({{10{1'b0}}, ptw_pte_data[31:10]}, ptw_vaddr_save, ptw_level);
            end else begin
              req_paddr <= construct_pa({{20{1'b0}}, ptw_pte_data[53:10]}, ptw_vaddr_save, ptw_level);
            end
            req_ready <= 1;
          end else begin
            // Permission denied - generate page fault
            $display("MMU: PTW Permission DENIED - PAGE FAULT! VA=0x%h PTE=0x%h priv=%b sum=%b",
                     ptw_vaddr_save, ptw_pte_data[7:0], ptw_priv_save, ptw_sum_save);
            req_page_fault <= 1;
            req_fault_vaddr <= ptw_vaddr_save;
            req_ready <= 1;
          end

          ptw_req_valid <= 0;  // Clear PTW request
          ptw_state <= PTW_IDLE;
        end

        PTW_FAULT: begin
          // Page fault
          req_page_fault <= 1;
          req_fault_vaddr <= ptw_vaddr_save;
          req_ready <= 1;
          ptw_req_valid <= 0;  // Clear PTW request
          ptw_state <= PTW_IDLE;
        end

        default: ptw_state <= PTW_IDLE;
      endcase
    end
  end

endmodule
