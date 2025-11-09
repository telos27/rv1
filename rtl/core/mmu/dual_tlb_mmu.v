// dual_tlb_mmu.v - Dual TLB MMU (I-TLB + D-TLB with shared PTW)
// Implements RISC-V Sv32 (RV32) and Sv39 (RV64) virtual memory translation
// Separate TLBs for instruction fetch (I-TLB) and data access (D-TLB)
// Eliminates structural hazard from unified TLB arbiter
// Author: RV1 Project
// Date: 2025-11-08 (Session 125)

`include "config/rv_config.vh"

module dual_tlb_mmu #(
  parameter XLEN = `XLEN,
  parameter ITLB_ENTRIES = 8,   // I-TLB entries
  parameter DTLB_ENTRIES = 16   // D-TLB entries (data accesses more frequent)
) (
  input  wire             clk,
  input  wire             reset_n,

  // Instruction fetch translation (I-TLB)
  input  wire             if_req_valid,
  input  wire [XLEN-1:0]  if_req_vaddr,
  output wire             if_req_ready,
  output wire [XLEN-1:0]  if_req_paddr,
  output wire             if_req_page_fault,
  output wire [XLEN-1:0]  if_req_fault_vaddr,

  // Data access translation (D-TLB)
  input  wire             ex_req_valid,
  input  wire [XLEN-1:0]  ex_req_vaddr,
  input  wire             ex_req_is_store,
  output wire             ex_req_ready,
  output wire [XLEN-1:0]  ex_req_paddr,
  output wire             ex_req_page_fault,
  output wire [XLEN-1:0]  ex_req_fault_vaddr,

  // Memory interface for page table walks (shared PTW)
  output wire             ptw_req_valid,
  output wire [XLEN-1:0]  ptw_req_addr,
  input  wire             ptw_req_ready,
  input  wire [XLEN-1:0]  ptw_resp_data,
  input  wire             ptw_resp_valid,

  // CSR interface
  input  wire [XLEN-1:0]  satp,
  input  wire [1:0]       privilege_mode,
  input  wire             mstatus_sum,
  input  wire             mstatus_mxr,

  // TLB flush control
  input  wire             tlb_flush_all,
  input  wire             tlb_flush_vaddr,
  input  wire [XLEN-1:0]  tlb_flush_addr
);

  // =========================================================================
  // Translation Enable Detection
  // =========================================================================

  wire satp_mode_enabled;
  wire translation_enabled;

  generate
    if (XLEN == 32) begin : gen_mode_sv32
      assign satp_mode_enabled = (satp[31:31] == 1'b1);
    end else begin : gen_mode_sv39
      assign satp_mode_enabled = (satp[63:60] == 4'h8);
    end
  endgenerate

  assign translation_enabled = satp_mode_enabled && (privilege_mode != 2'b11);

  // =========================================================================
  // I-TLB (Instruction TLB)
  // =========================================================================

  wire itlb_hit;
  wire [XLEN-1:0] itlb_paddr;
  wire itlb_page_fault;
  wire itlb_update_valid;
  wire [XLEN-1:0] itlb_update_vpn;
  wire [XLEN-1:0] itlb_update_ppn;
  wire [7:0] itlb_update_pte;
  wire [XLEN-1:0] itlb_update_level;

  tlb #(
    .XLEN(XLEN),
    .TLB_ENTRIES(ITLB_ENTRIES)
  ) itlb_inst (
    .clk(clk),
    .reset_n(reset_n),
    // Lookup
    .lookup_valid(if_req_valid),
    .lookup_vaddr(if_req_vaddr),
    .lookup_is_store(1'b0),      // Instruction fetch is never a store
    .lookup_is_fetch(1'b1),      // Always fetch
    .lookup_hit(itlb_hit),
    .lookup_paddr(itlb_paddr),
    .lookup_page_fault(itlb_page_fault),
    // Update from PTW
    .update_valid(itlb_update_valid),
    .update_vpn(itlb_update_vpn),
    .update_ppn(itlb_update_ppn),
    .update_pte(itlb_update_pte),
    .update_level(itlb_update_level),
    // CSR
    .privilege_mode(privilege_mode),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr),
    .translation_enabled(translation_enabled),
    // Flush
    .flush_all(tlb_flush_all),
    .flush_vaddr(tlb_flush_vaddr),
    .flush_addr(tlb_flush_addr)
  );

  // =========================================================================
  // D-TLB (Data TLB)
  // =========================================================================

  wire dtlb_hit;
  wire [XLEN-1:0] dtlb_paddr;
  wire dtlb_page_fault;
  wire dtlb_update_valid;
  wire [XLEN-1:0] dtlb_update_vpn;
  wire [XLEN-1:0] dtlb_update_ppn;
  wire [7:0] dtlb_update_pte;
  wire [XLEN-1:0] dtlb_update_level;

  tlb #(
    .XLEN(XLEN),
    .TLB_ENTRIES(DTLB_ENTRIES)
  ) dtlb_inst (
    .clk(clk),
    .reset_n(reset_n),
    // Lookup
    .lookup_valid(ex_req_valid),
    .lookup_vaddr(ex_req_vaddr),
    .lookup_is_store(ex_req_is_store),
    .lookup_is_fetch(1'b0),
    .lookup_hit(dtlb_hit),
    .lookup_paddr(dtlb_paddr),
    .lookup_page_fault(dtlb_page_fault),
    // Update from PTW
    .update_valid(dtlb_update_valid),
    .update_vpn(dtlb_update_vpn),
    .update_ppn(dtlb_update_ppn),
    .update_pte(dtlb_update_pte),
    .update_level(dtlb_update_level),
    // CSR
    .privilege_mode(privilege_mode),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr),
    .translation_enabled(translation_enabled),
    // Flush
    .flush_all(tlb_flush_all),
    .flush_vaddr(tlb_flush_vaddr),
    .flush_addr(tlb_flush_addr)
  );

  // =========================================================================
  // Shared PTW Arbiter
  // =========================================================================
  // Priority: D-TLB > I-TLB (data misses block pipeline more)
  // PTW conflicts are rare (TLB misses infrequent after warmup)

  wire if_needs_ptw = if_req_valid && !itlb_hit && translation_enabled;
  wire ex_needs_ptw = ex_req_valid && !dtlb_hit && translation_enabled;

  // PTW request arbitration
  wire ptw_grant_to_if = if_needs_ptw && !ex_needs_ptw;
  wire ptw_grant_to_ex = ex_needs_ptw;  // EX has priority

  // Multiplex PTW requests
  wire ptw_req_valid_internal;
  wire [XLEN-1:0] ptw_req_vaddr;
  wire ptw_req_is_store;
  wire ptw_req_is_fetch;

  // Forward declare ptw_busy_r (defined below)
  reg ptw_busy_r;

  // Only generate PTW request if not already busy (prevents duplicate walks)
  assign ptw_req_valid_internal = (if_needs_ptw || ex_needs_ptw) && !ptw_busy_r;

  // Debug: Detailed MMU operation tracing
  always @(posedge clk) begin
    // PTW requests
    if (ptw_req_valid_internal && reset_n) begin
      $display("[DUAL_MMU] PTW req: VA=0x%h grant_if=%b grant_ex=%b fetch=%b store=%b satp=0x%h",
               ptw_req_vaddr, ptw_grant_to_if, ptw_grant_to_ex, ptw_req_is_fetch, ptw_req_is_store, satp);
    end

    // PTW completions and TLB updates
    if (ptw_result_valid && reset_n) begin
      $display("[DUAL_MMU] PTW result: VPN=0x%h PPN=0x%h route_to=%s pte=0x%02h for_itlb=%b",
               ptw_result_vpn, ptw_result_ppn, ptw_for_itlb ? "I-TLB" : "D-TLB", ptw_result_pte, ptw_for_itlb);
    end

    // TLB updates
    if (itlb_update_valid && reset_n) begin
      $display("[DUAL_MMU] I-TLB update: VPN=0x%h -> PPN=0x%h", itlb_update_vpn, itlb_update_ppn);
    end
    if (dtlb_update_valid && reset_n) begin
      $display("[DUAL_MMU] D-TLB update: VPN=0x%h -> PPN=0x%h", dtlb_update_vpn, dtlb_update_ppn);
    end
  end
  assign ptw_req_vaddr = ptw_grant_to_ex ? ex_req_vaddr : if_req_vaddr;
  assign ptw_req_is_store = ptw_grant_to_ex ? ex_req_is_store : 1'b0;
  assign ptw_req_is_fetch = ptw_grant_to_if;

  // =========================================================================
  // Shared PTW
  // =========================================================================

  wire ptw_ready;
  wire ptw_page_fault;
  wire [XLEN-1:0] ptw_fault_vaddr;
  wire ptw_result_valid;
  wire [XLEN-1:0] ptw_result_vpn;
  wire [XLEN-1:0] ptw_result_ppn;
  wire [7:0] ptw_result_pte;
  wire [XLEN-1:0] ptw_result_level;

  ptw #(
    .XLEN(XLEN)
  ) ptw_inst (
    .clk(clk),
    .reset_n(reset_n),
    // Request
    .req_valid(ptw_req_valid_internal),
    .req_vaddr(ptw_req_vaddr),
    .req_is_store(ptw_req_is_store),
    .req_is_fetch(ptw_req_is_fetch),
    .req_ready(ptw_ready),
    .req_page_fault(ptw_page_fault),
    .req_fault_vaddr(ptw_fault_vaddr),
    // Result for TLB update
    .result_valid(ptw_result_valid),
    .result_vpn(ptw_result_vpn),
    .result_ppn(ptw_result_ppn),
    .result_pte(ptw_result_pte),
    .result_level(ptw_result_level),
    // Memory interface
    .mem_req_valid(ptw_req_valid),
    .mem_req_addr(ptw_req_addr),
    .mem_req_ready(ptw_req_ready),
    .mem_resp_data(ptw_resp_data),
    .mem_resp_valid(ptw_resp_valid),
    // CSR
    .satp(satp),
    .privilege_mode(privilege_mode),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr)
  );

  // Track which TLB initiated the PTW (to route result back)
  // Latch only on the FIRST cycle of PTW (when PTW transitions from idle to busy)
  reg ptw_for_itlb;
  // Note: ptw_busy_r declared earlier (line 179)

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      ptw_for_itlb <= 0;
      ptw_busy_r <= 0;
    end else begin
      // Update busy status
      if (ptw_req_valid_internal && !ptw_ready) begin
        ptw_busy_r <= 1;  // PTW is now busy
      end else if (ptw_ready || !ptw_req_valid_internal) begin
        ptw_busy_r <= 0;  // PTW is idle
      end

      // Latch grant ONLY when PTW starts (transition from idle to busy)
      if (ptw_req_valid_internal && !ptw_busy_r) begin
        ptw_for_itlb <= ptw_grant_to_if;
      end
    end
  end

  // Route PTW result to correct TLB
  assign itlb_update_valid = ptw_result_valid && ptw_for_itlb;
  assign itlb_update_vpn = ptw_result_vpn;
  assign itlb_update_ppn = ptw_result_ppn;
  assign itlb_update_pte = ptw_result_pte;
  assign itlb_update_level = ptw_result_level;

  assign dtlb_update_valid = ptw_result_valid && !ptw_for_itlb;
  assign dtlb_update_vpn = ptw_result_vpn;
  assign dtlb_update_ppn = ptw_result_ppn;
  assign dtlb_update_pte = ptw_result_pte;
  assign dtlb_update_level = ptw_result_level;

  // =========================================================================
  // I-TLB Response
  // =========================================================================

  // Bare mode (translation disabled): immediate response with VA=PA
  wire if_bare_mode = !translation_enabled;

  // IF ready when: (1) bare mode, (2) TLB hit, or (3) PTW complete for IF
  assign if_req_ready = if_bare_mode ||
                        (if_req_valid && itlb_hit) ||
                        (ptw_ready && ptw_grant_to_if);

  // IF physical address: bare mode→VA, TLB hit→TLB result, PTW miss→0 (stalled)
  assign if_req_paddr = if_bare_mode ? if_req_vaddr :
                        itlb_hit ? itlb_paddr :
                        {XLEN{1'b0}};  // PTW in progress, stalled

  // IF page fault: TLB hit with permission fault, or PTW fault for IF
  assign if_req_page_fault = (if_req_valid && itlb_hit && itlb_page_fault) ||
                             (ptw_page_fault && ptw_grant_to_if);

  assign if_req_fault_vaddr = ptw_fault_vaddr;

  // =========================================================================
  // D-TLB Response
  // =========================================================================

  wire ex_bare_mode = !translation_enabled;

  assign ex_req_ready = ex_bare_mode ||
                        (ex_req_valid && dtlb_hit) ||
                        (ptw_ready && ptw_grant_to_ex);

  assign ex_req_paddr = ex_bare_mode ? ex_req_vaddr :
                        dtlb_hit ? dtlb_paddr :
                        {XLEN{1'b0}};

  assign ex_req_page_fault = (ex_req_valid && dtlb_hit && dtlb_page_fault) ||
                             (ptw_page_fault && ptw_grant_to_ex);

  assign ex_req_fault_vaddr = ptw_fault_vaddr;

endmodule
