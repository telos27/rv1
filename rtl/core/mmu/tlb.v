// tlb.v - Translation Lookaside Buffer (TLB)
// Reusable TLB module for both I-TLB and D-TLB
// Provides fast virtual-to-physical address translation with permission checking
// Author: RV1 Project
// Date: 2025-11-08 (Session 125)

`include "config/rv_config.vh"

module tlb #(
  parameter XLEN = `XLEN,
  parameter TLB_ENTRIES = 8  // Number of TLB entries
) (
  input  wire             clk,
  input  wire             reset_n,

  // Lookup request
  input  wire             lookup_valid,      // Lookup request valid
  input  wire [XLEN-1:0]  lookup_vaddr,      // Virtual address to translate
  input  wire             lookup_is_store,   // 1=store, 0=load
  input  wire             lookup_is_fetch,   // 1=instruction fetch, 0=data access
  output wire             lookup_hit,        // TLB hit
  output wire [XLEN-1:0]  lookup_paddr,      // Physical address (if hit)
  output wire             lookup_page_fault, // Page fault (if hit but no permission)

  // TLB update from PTW
  input  wire             update_valid,      // Update TLB entry
  input  wire [XLEN-1:0]  update_vpn,        // Virtual page number
  input  wire [XLEN-1:0]  update_ppn,        // Physical page number
  input  wire [7:0]       update_pte,        // PTE flags (V,R,W,X,U,G,A,D)
  input  wire [XLEN-1:0]  update_level,      // Page level (0=4KB, 1=2/4MB, 2=1GB)

  // CSR interface for permission checking
  input  wire [1:0]       privilege_mode,    // Current privilege mode (0=U, 1=S, 3=M)
  input  wire             mstatus_sum,       // Supervisor User Memory access
  input  wire             mstatus_mxr,       // Make eXecutable Readable
  input  wire             translation_enabled, // Translation enabled (satp.MODE != 0)

  // TLB flush control
  input  wire             flush_all,         // Flush entire TLB
  input  wire             flush_vaddr,       // Flush specific virtual address
  input  wire [XLEN-1:0]  flush_addr         // Address to flush (if flush_vaddr)
);

  // =========================================================================
  // RISC-V Virtual Memory Parameters
  // =========================================================================

  localparam PAGE_SHIFT = 12;  // 4KB pages

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
  // TLB Storage
  // =========================================================================

  reg                   tlb_valid [0:TLB_ENTRIES-1];
  reg [XLEN-1:0]        tlb_vpn   [0:TLB_ENTRIES-1];  // Virtual page number
  reg [XLEN-1:0]        tlb_ppn   [0:TLB_ENTRIES-1];  // Physical page number
  reg [7:0]             tlb_pte   [0:TLB_ENTRIES-1];  // PTE flags
  reg [XLEN-1:0]        tlb_level [0:TLB_ENTRIES-1];  // Page level

  // TLB replacement policy: simple round-robin
  reg [$clog2(TLB_ENTRIES)-1:0] tlb_replace_idx;

  // =========================================================================
  // VPN Extraction
  // =========================================================================

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
  // TLB Lookup (Combinational)
  // =========================================================================

  reg tlb_hit_found;
  reg [$clog2(TLB_ENTRIES)-1:0] tlb_hit_idx;
  reg [XLEN-1:0] tlb_ppn_out;
  reg [7:0] tlb_pte_out;
  reg [XLEN-1:0] tlb_level_out;

  integer i;
  always @(*) begin
    tlb_hit_found = 0;
    tlb_hit_idx = 0;
    tlb_ppn_out = 0;
    tlb_pte_out = 0;
    tlb_level_out = 0;

    if (translation_enabled && lookup_valid) begin
      for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
        if (tlb_valid[i] && (tlb_vpn[i] == get_full_vpn(lookup_vaddr))) begin
          tlb_hit_found = 1;
          tlb_hit_idx = i[$clog2(TLB_ENTRIES)-1:0];
          tlb_ppn_out = tlb_ppn[i];
          tlb_pte_out = tlb_pte[i];
          tlb_level_out = tlb_level[i];
        end
      end
    end
  end

  assign lookup_hit = tlb_hit_found;

  // =========================================================================
  // Permission Checking (Combinational)
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
        check_permission = 0;  // Non-leaf PTE
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

  // Check permissions for lookup
  wire perm_ok = check_permission(tlb_pte_out, lookup_is_store, lookup_is_fetch,
                                  privilege_mode, mstatus_sum, mstatus_mxr);

  assign lookup_page_fault = tlb_hit_found && !perm_ok;

  // =========================================================================
  // Physical Address Construction (Combinational)
  // =========================================================================

  // Construct physical address from PPN and virtual address based on page level
  function [XLEN-1:0] construct_pa;
    input [XLEN-1:0] ppn;    // Full PPN from PTE
    input [XLEN-1:0] vaddr;  // Virtual address
    input [XLEN-1:0] level;  // Page table level
    begin
      if (XLEN == 32) begin
        // Sv32
        case (level)
          0: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};     // 4KB
          1: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:10], vaddr[PAGE_SHIFT+9:0]};    // 4MB
          default: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};
        endcase
      end else begin
        // Sv39
        case (level)
          0: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};     // 4KB
          1: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:9], vaddr[PAGE_SHIFT+8:0]};     // 2MB
          2: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:18], vaddr[PAGE_SHIFT+17:0]};   // 1GB
          default: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};
        endcase
      end
    end
  endfunction

  assign lookup_paddr = construct_pa(tlb_ppn_out, lookup_vaddr, tlb_level_out);

  // =========================================================================
  // TLB Update and Flush Logic (Sequential)
  // =========================================================================

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      tlb_replace_idx <= 0;
      for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
        tlb_valid[i] <= 0;
        tlb_vpn[i] <= 0;
        tlb_ppn[i] <= 0;
        tlb_pte[i] <= 0;
        tlb_level[i] <= 0;
      end
    end else begin
      // TLB flush logic
      if (flush_all) begin
        for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
          tlb_valid[i] <= 0;
        end
      end else if (flush_vaddr) begin
        for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
          if (tlb_vpn[i] == get_full_vpn(flush_addr)) begin
            tlb_valid[i] <= 0;
          end
        end
      end

      // TLB update from PTW
      if (update_valid) begin
        tlb_valid[tlb_replace_idx] <= 1;
        tlb_vpn[tlb_replace_idx] <= update_vpn;
        tlb_ppn[tlb_replace_idx] <= update_ppn;
        tlb_pte[tlb_replace_idx] <= update_pte;
        tlb_level[tlb_replace_idx] <= update_level;
        tlb_replace_idx <= tlb_replace_idx + 1;
      end
    end
  end

endmodule
