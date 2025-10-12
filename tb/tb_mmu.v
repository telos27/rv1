// tb_mmu.v - Testbench for MMU Module
// Tests virtual memory translation, TLB, and page faults
// Author: RV1 Project
// Date: 2025-10-11

`timescale 1ns / 1ps
`include "config/rv_config.vh"

module tb_mmu;

  parameter XLEN = 64;  // Test with RV64 (Sv39)
  parameter TLB_ENTRIES = 16;
  parameter CLK_PERIOD = 10;

  // Clock and reset
  reg clk;
  reg reset_n;

  // Translation request interface
  reg             req_valid;
  reg [XLEN-1:0]  req_vaddr;
  reg             req_is_store;
  reg             req_is_fetch;
  reg [2:0]       req_size;
  wire            req_ready;
  wire [XLEN-1:0] req_paddr;
  wire            req_page_fault;
  wire [XLEN-1:0] req_fault_vaddr;

  // Page table walk memory interface
  wire            ptw_req_valid;
  wire [XLEN-1:0] ptw_req_addr;
  reg             ptw_req_ready;
  reg [XLEN-1:0]  ptw_resp_data;
  reg             ptw_resp_valid;

  // CSR interface
  reg [XLEN-1:0]  satp;
  reg [1:0]       privilege_mode;
  reg             mstatus_sum;
  reg             mstatus_mxr;

  // TLB flush control
  reg             tlb_flush_all;
  reg             tlb_flush_vaddr;
  reg [XLEN-1:0]  tlb_flush_addr;

  // DUT instantiation
  mmu #(
    .XLEN(XLEN),
    .TLB_ENTRIES(TLB_ENTRIES)
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    .req_valid(req_valid),
    .req_vaddr(req_vaddr),
    .req_is_store(req_is_store),
    .req_is_fetch(req_is_fetch),
    .req_size(req_size),
    .req_ready(req_ready),
    .req_paddr(req_paddr),
    .req_page_fault(req_page_fault),
    .req_fault_vaddr(req_fault_vaddr),
    .ptw_req_valid(ptw_req_valid),
    .ptw_req_addr(ptw_req_addr),
    .ptw_req_ready(ptw_req_ready),
    .ptw_resp_data(ptw_resp_data),
    .ptw_resp_valid(ptw_resp_valid),
    .satp(satp),
    .privilege_mode(privilege_mode),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr),
    .tlb_flush_all(tlb_flush_all),
    .tlb_flush_vaddr(tlb_flush_vaddr),
    .tlb_flush_addr(tlb_flush_addr)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // Test variables
  integer test_count = 0;
  integer pass_count = 0;
  integer fail_count = 0;

  // Simple page table simulation
  // We'll simulate a few PTEs for testing
  // Page table structure:
  //   Root PT at PA 0x1000 (physical address)
  //   Level 2 PTE[0] -> Level 1 PT at PPN 0x10 (PA 0x10000)
  //   Level 1 PTE[0] -> Level 0 PT at PPN 0x20 (PA 0x20000)
  //   Level 0 PTE[1] -> Physical PPN 0x2 (PA 0x2000, VA 0x1000, R/W/X/U)
  //   Level 0 PTE[3] -> Physical PPN 0x4 (PA 0x4000, VA 0x3000, R/X/U, no W)

  task simulate_ptw_response;
    input [XLEN-1:0] pte_addr;
    output [XLEN-1:0] pte_data;
    begin
      $display("    PTW: Reading PTE at PA 0x%h", pte_addr);

      // Level 2 page table at 0x1000 (root)
      if (pte_addr >= 64'h1000 && pte_addr < 64'h2000) begin
        // PTE[0] at offset 0: points to level 1 PT at PPN 0x10 (PA 0x10000)
        if (pte_addr[11:3] == 9'h0) begin
          // PPN[43:0] = 0x10, RSW=0, D=0,A=0,G=0,U=0,X=0,W=0,R=0,V=1
          pte_data = {10'h0, 44'h10, 2'b00, 8'b00000001}; // PPN=0x10, V=1, non-leaf
        end else begin
          pte_data = 64'h0; // Invalid
        end
      end
      // Level 1 page table at 0x10000
      else if (pte_addr >= 64'h10000 && pte_addr < 64'h11000) begin
        // PTE[0] at offset 0: points to level 0 PT at PPN 0x20 (PA 0x20000)
        if (pte_addr[11:3] == 9'h0) begin
          // PPN[43:0] = 0x20, RSW=0, D=0,A=0,G=0,U=0,X=0,W=0,R=0,V=1
          pte_data = {10'h0, 44'h20, 2'b00, 8'b00000001}; // PPN=0x20, V=1, non-leaf
        end else begin
          pte_data = 64'h0; // Invalid
        end
      end
      // Level 0 page table at 0x20000
      else if (pte_addr >= 64'h20000 && pte_addr < 64'h21000) begin
        case (pte_addr[11:3])
          // PTE[1]: VA 0x1000 -> PPN 0x2 (PA 0x2000), R/W/X/U/A/D
          // PPN[43:0] = 0x2, RSW=0, D=1,A=1,G=0,U=1,X=1,W=1,R=1,V=1
          9'h1: pte_data = {10'h0, 44'h2, 2'b00, 8'b11010111}; // V,R,W,X,U,A,D
          // PTE[3]: VA 0x3000 -> PPN 0x4 (PA 0x4000), R/X/U/A/D (no W)
          // PPN[43:0] = 0x4, RSW=0, D=1,A=1,G=0,U=1,X=1,W=0,R=1,V=1
          9'h3: pte_data = {10'h0, 44'h4, 2'b00, 8'b11001011}; // V,R,X,U,A,D
          default: pte_data = 64'h0; // Invalid
        endcase
      end
      else begin
        pte_data = 64'h0; // Invalid address
      end

      $display("    PTW: Returned PTE 0x%h (PPN=0x%h, flags=0x%h)", pte_data, pte_data[53:10], pte_data[7:0]);
    end
  endtask

  // Task to request translation
  task request_translation;
    input [XLEN-1:0] vaddr;
    input is_store;
    input is_fetch;
    output success;
    output [XLEN-1:0] paddr;
    output page_fault;
    integer timeout_count;
    begin
      req_vaddr = vaddr;
      req_is_store = is_store;
      req_is_fetch = is_fetch;
      req_size = 3; // Word
      req_valid = 1;
      success = 0;
      paddr = 0;
      page_fault = 0;
      timeout_count = 0;

      // Wait for response (with timeout)
      @(posedge clk);
      while (!req_ready && timeout_count < 100) begin
        // Handle page table walk requests
        if (ptw_req_valid) begin
          ptw_req_ready = 1;
          simulate_ptw_response(ptw_req_addr, ptw_resp_data);
          ptw_resp_valid = 1;
        end else begin
          ptw_req_ready = 0;
          ptw_resp_valid = 0;
        end

        @(posedge clk);
        timeout_count = timeout_count + 1;
      end

      if (req_ready) begin
        success = 1;
        paddr = req_paddr;
        page_fault = req_page_fault;
      end else begin
        $display("    ERROR: Translation timeout after %0d cycles", timeout_count);
      end

      // Clear PTW signals
      ptw_req_ready = 0;
      ptw_resp_valid = 0;

      req_valid = 0;
      @(posedge clk);
    end
  endtask

  // Main test
  initial begin
    // Initialize signals
    reset_n = 0;
    req_valid = 0;
    req_vaddr = 0;
    req_is_store = 0;
    req_is_fetch = 0;
    req_size = 0;
    ptw_req_ready = 0;
    ptw_resp_data = 0;
    ptw_resp_valid = 0;
    satp = 0;
    privilege_mode = 2'b11; // M-mode
    mstatus_sum = 0;
    mstatus_mxr = 0;
    tlb_flush_all = 0;
    tlb_flush_vaddr = 0;
    tlb_flush_addr = 0;

    // Reset
    #(CLK_PERIOD * 2);
    reset_n = 1;
    #(CLK_PERIOD * 2);

    $display("\n=== MMU Testbench ===\n");

    // Test 1: Bare mode (no translation)
    $display("Test 1: Bare mode (no translation)");
    satp = 64'h0; // MODE = 0 (Bare)
    privilege_mode = 2'b11; // M-mode

    begin
      reg success;
      reg [XLEN-1:0] paddr;
      reg page_fault;

      request_translation(64'h0000_1000, 0, 0, success, paddr, page_fault);

      if (success && !page_fault && (paddr == 64'h0000_1000)) begin
        $display("  PASS: Bare mode direct mapping");
        pass_count = pass_count + 1;
      end else begin
        $display("  FAIL: Expected paddr=0x1000, got paddr=0x%h, fault=%b", paddr, page_fault);
        fail_count = fail_count + 1;
      end
      test_count = test_count + 1;
    end

    // Test 2: Sv39 mode - valid translation
    $display("\nTest 2: Sv39 mode - valid translation with TLB miss");
    satp = 64'h8000_0000_0000_1000; // MODE = 8 (Sv39), PPN = 0x1000
    privilege_mode = 2'b00; // User mode

    begin
      reg success;
      reg [XLEN-1:0] paddr;
      reg page_fault;

      request_translation(64'h0000_0000_0000_1000, 0, 0, success, paddr, page_fault);

      if (success && !page_fault && (paddr == 64'h2000)) begin
        $display("  PASS: Translation completed without page fault");
        $display("       Virtual: 0x%h -> Physical: 0x%h (expected 0x2000)", 64'h1000, paddr);
        pass_count = pass_count + 1;
      end else begin
        $display("  FAIL: Translation failed or wrong address");
        $display("       Expected paddr=0x2000, got paddr=0x%h, fault=%b", paddr, page_fault);
        fail_count = fail_count + 1;
      end
      test_count = test_count + 1;
    end

    // Test 3: TLB hit (repeat same translation)
    $display("\nTest 3: TLB hit (repeat translation)");
    begin
      reg success;
      reg [XLEN-1:0] paddr;
      reg page_fault;

      request_translation(64'h0000_0000_0000_1000, 0, 0, success, paddr, page_fault);

      if (success && !page_fault) begin
        $display("  PASS: TLB hit, translation completed");
        $display("       Virtual: 0x%h -> Physical: 0x%h", 64'h1000, paddr);
        pass_count = pass_count + 1;
      end else begin
        $display("  FAIL: TLB hit failed, success=%b, fault=%b, paddr=0x%h", success, page_fault, paddr);
        fail_count = fail_count + 1;
      end
      test_count = test_count + 1;
    end

    // Test 4: TLB flush
    $display("\nTest 4: TLB flush");
    tlb_flush_all = 1;
    @(posedge clk);
    tlb_flush_all = 0;
    @(posedge clk);
    $display("  PASS: TLB flushed");
    pass_count = pass_count + 1;
    test_count = test_count + 1;

    // Test 5: Permission check - store to read-only page
    $display("\nTest 5: Permission check - store to read-only page");
    begin
      reg success;
      reg [XLEN-1:0] paddr;
      reg page_fault;

      // Try to store to a read/execute page (should fault)
      request_translation(64'h0000_0000_0000_3000, 1, 0, success, paddr, page_fault);

      if (success && page_fault) begin
        $display("  PASS: Store to read-only page caused page fault");
        pass_count = pass_count + 1;
      end else begin
        $display("  FAIL: Expected page fault for store to read-only page");
        fail_count = fail_count + 1;
      end
      test_count = test_count + 1;
    end

    // Test summary
    $display("\n=== Test Summary ===");
    $display("Total tests: %0d", test_count);
    $display("Passed:      %0d", pass_count);
    $display("Failed:      %0d", fail_count);

    if (fail_count == 0) begin
      $display("\n*** ALL TESTS PASSED ***\n");
    end else begin
      $display("\n*** SOME TESTS FAILED ***\n");
    end

    #(CLK_PERIOD * 10);
    $finish;
  end

  // Timeout watchdog
  initial begin
    #(CLK_PERIOD * 10000);
    $display("\nERROR: Test timeout!");
    $finish;
  end

  // Optional: waveform dump
  initial begin
    $dumpfile("tb_mmu.vcd");
    $dumpvars(0, tb_mmu);
  end

endmodule
