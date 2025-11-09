// ptw.v - Page Table Walker (PTW)
// Shared page table walker for both I-TLB and D-TLB
// Implements RISC-V Sv32 (RV32) and Sv39 (RV64) page table walks
// Author: RV1 Project
// Date: 2025-11-08 (Session 125)

`include "config/rv_config.vh"

module ptw #(
  parameter XLEN = `XLEN
) (
  input  wire             clk,
  input  wire             reset_n,

  // PTW request from TLB
  input  wire             req_valid,         // PTW request valid
  input  wire [XLEN-1:0]  req_vaddr,         // Virtual address
  input  wire             req_is_store,      // 1=store, 0=load
  input  wire             req_is_fetch,      // 1=instruction fetch, 0=data access
  output reg              req_ready,         // PTW complete
  output reg              req_page_fault,    // Page fault
  output reg  [XLEN-1:0]  req_fault_vaddr,   // Faulting virtual address

  // PTW result for TLB update
  output reg              result_valid,      // Result valid (update TLB)
  output reg  [XLEN-1:0]  result_vpn,        // Virtual page number
  output reg  [XLEN-1:0]  result_ppn,        // Physical page number
  output reg  [7:0]       result_pte,        // PTE flags
  output reg  [XLEN-1:0]  result_level,      // Page level

  // Memory interface for page table walks
  output reg              mem_req_valid,     // Memory request
  output reg  [XLEN-1:0]  mem_req_addr,      // Physical address
  input  wire             mem_req_ready,     // Memory ready
  input  wire [XLEN-1:0]  mem_resp_data,     // PTE data
  input  wire             mem_resp_valid,    // Response valid

  // CSR interface
  input  wire [XLEN-1:0]  satp,              // SATP register
  input  wire [1:0]       privilege_mode,    // Current privilege mode
  input  wire             mstatus_sum,       // SUM bit
  input  wire             mstatus_mxr        // MXR bit
);

  // =========================================================================
  // RISC-V Virtual Memory Parameters
  // =========================================================================

  localparam PAGE_SHIFT = 12;  // 4KB pages

  // For Sv32 (RV32)
  localparam SV32_LEVELS = 2;

  // For Sv39 (RV64)
  localparam SV39_LEVELS = 3;

  // PTE bit fields
  localparam PTE_V = 0;
  localparam PTE_R = 1;
  localparam PTE_W = 2;
  localparam PTE_X = 3;
  localparam PTE_U = 4;
  localparam PTE_G = 5;
  localparam PTE_A = 6;
  localparam PTE_D = 7;

  // =========================================================================
  // SATP Decoding
  // =========================================================================

  wire [XLEN-1:0] satp_ppn;

  generate
    if (XLEN == 32) begin : gen_satp_sv32
      assign satp_ppn = {{10{1'b0}}, satp[21:0]};  // 22-bit PPN
    end else begin : gen_satp_sv39
      assign satp_ppn = {{20{1'b0}}, satp[43:0]};  // 44-bit PPN
    end
  endgenerate

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
        get_full_vpn = {{(XLEN-20){1'b0}}, vaddr[31:12]};
      end else begin
        get_full_vpn = {{(XLEN-27){1'b0}}, vaddr[38:12]};
      end
    end
  endfunction

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

      if (!pte_flags[PTE_V]) begin
        check_permission = 0;
      end
      else if (!pte_flags[PTE_R] && !pte_flags[PTE_W] && !pte_flags[PTE_X]) begin
        check_permission = 0;
      end
      else if (pte_flags[PTE_W] && !pte_flags[PTE_R]) begin
        check_permission = 0;
      end
      else if (priv_mode == 2'b00) begin
        if (!pte_flags[PTE_U]) begin
          check_permission = 0;
        end
      end
      else if (priv_mode == 2'b01) begin
        if (pte_flags[PTE_U] && !sum) begin
          check_permission = 0;
        end
      end

      if (check_permission) begin
        if (is_fetch) begin
          check_permission = pte_flags[PTE_X];
        end else if (is_store) begin
          check_permission = pte_flags[PTE_W];
        end else begin
          check_permission = pte_flags[PTE_R] || (pte_flags[PTE_X] && mxr);
        end
      end
    end
  endfunction

  // =========================================================================
  // PTW State Machine
  // =========================================================================

  localparam PTW_IDLE       = 3'b000;
  localparam PTW_LEVEL_0    = 3'b001;
  localparam PTW_LEVEL_1    = 3'b010;
  localparam PTW_LEVEL_2    = 3'b011;
  localparam PTW_UPDATE_TLB = 3'b100;
  localparam PTW_FAULT      = 3'b101;

  reg [2:0] ptw_state;
  reg [2:0] ptw_level;
  reg [XLEN-1:0] ptw_pte_addr;
  reg [XLEN-1:0] ptw_pte_data;
  reg [XLEN-1:0] ptw_vpn_save;
  reg [XLEN-1:0] ptw_vaddr_save;
  reg ptw_is_store_save;
  reg ptw_is_fetch_save;
  reg [1:0] ptw_priv_save;
  reg ptw_sum_save;
  reg ptw_mxr_save;

  wire [XLEN-1:0] max_levels = (XLEN == 32) ? SV32_LEVELS : SV39_LEVELS;

  integer i;
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
      mem_req_valid <= 0;
      mem_req_addr <= 0;
      req_ready <= 0;
      req_page_fault <= 0;
      req_fault_vaddr <= 0;
      result_valid <= 0;
      result_vpn <= 0;
      result_ppn <= 0;
      result_pte <= 0;
      result_level <= 0;
    end else begin
      // Default: clear single-cycle outputs
      req_ready <= 0;
      req_page_fault <= 0;
      result_valid <= 0;

      case (ptw_state)
        PTW_IDLE: begin
          if (req_valid) begin
            // Start page table walk
            $display("PTW: Starting walk for VA=0x%h (fetch=%b store=%b)",
                     req_vaddr, req_is_fetch, req_is_store);
            ptw_vpn_save <= get_full_vpn(req_vaddr);
            ptw_vaddr_save <= req_vaddr;
            ptw_is_store_save <= req_is_store;
            ptw_is_fetch_save <= req_is_fetch;
            ptw_priv_save <= privilege_mode;
            ptw_sum_save <= mstatus_sum;
            ptw_mxr_save <= mstatus_mxr;
            ptw_level <= max_levels - 1;

            // Calculate first PTE address
            if (XLEN == 32) begin
              ptw_pte_addr <= (satp_ppn << PAGE_SHIFT) +
                              (extract_vpn(req_vaddr, max_levels - 1) << 2);
            end else begin
              ptw_pte_addr <= (satp_ppn << PAGE_SHIFT) +
                              (extract_vpn(req_vaddr, max_levels - 1) << 3);
            end

            // Go to appropriate level state
            case (max_levels - 1)
              2: ptw_state <= PTW_LEVEL_2;
              1: ptw_state <= PTW_LEVEL_1;
              default: ptw_state <= PTW_LEVEL_0;
            endcase
          end
        end

        PTW_LEVEL_0, PTW_LEVEL_1, PTW_LEVEL_2: begin
          // Issue memory request for PTE
          if (!mem_req_valid) begin
            $display("PTW: Level %0d - reading PTE addr=0x%h", ptw_level, ptw_pte_addr);
            mem_req_valid <= 1;
            mem_req_addr <= ptw_pte_addr;
          end else if (mem_req_ready && mem_resp_valid) begin
            // Got PTE response
            $display("PTW: Level %0d - got PTE=0x%h V=%b R=%b W=%b X=%b U=%b",
                     ptw_level, mem_resp_data, mem_resp_data[PTE_V],
                     mem_resp_data[PTE_R], mem_resp_data[PTE_W],
                     mem_resp_data[PTE_X], mem_resp_data[PTE_U]);
            ptw_pte_data <= mem_resp_data;
            mem_req_valid <= 0;

            // Check if PTE is valid
            if (!mem_resp_data[PTE_V]) begin
              $display("PTW: FAULT - Invalid PTE (V=0)");
              ptw_state <= PTW_FAULT;
            end
            // Check if leaf PTE
            else if (mem_resp_data[PTE_R] || mem_resp_data[PTE_X]) begin
              // Leaf PTE - check permissions
              if (check_permission(mem_resp_data[7:0], ptw_is_store_save, ptw_is_fetch_save,
                                   ptw_priv_save, ptw_sum_save, ptw_mxr_save)) begin
                $display("PTW: Leaf PTE found, permission OK");
                ptw_state <= PTW_UPDATE_TLB;
              end else begin
                $display("PTW: FAULT - Permission denied");
                ptw_state <= PTW_FAULT;
              end
            end
            // Non-leaf at level 0
            else if (ptw_level == 0) begin
              $display("PTW: FAULT - Non-leaf at level 0");
              ptw_state <= PTW_FAULT;
            end
            // Non-leaf - go to next level
            else begin
              $display("PTW: Non-leaf PTE, descending to level %0d", ptw_level - 1);
              ptw_level <= ptw_level - 1;

              // Calculate next PTE address
              if (XLEN == 32) begin
                ptw_pte_addr <= (mem_resp_data[31:10] << PAGE_SHIFT) +
                                (extract_vpn(ptw_vaddr_save, ptw_level - 1) << 2);
              end else begin
                ptw_pte_addr <= (mem_resp_data[53:10] << PAGE_SHIFT) +
                                (extract_vpn(ptw_vaddr_save, ptw_level - 1) << 3);
              end

              // Next state
              case (ptw_level)
                2: ptw_state <= PTW_LEVEL_1;
                1: ptw_state <= PTW_LEVEL_0;
                default: ptw_state <= PTW_FAULT;
              endcase
            end
          end else begin
            // Wait for response
            mem_req_valid <= 1;
          end
        end

        PTW_UPDATE_TLB: begin
          // Send result to TLB for update
          result_valid <= 1;
          result_vpn <= ptw_vpn_save;
          if (XLEN == 32) begin
            result_ppn <= {{10{1'b0}}, ptw_pte_data[31:10]};
          end else begin
            result_ppn <= {{20{1'b0}}, ptw_pte_data[53:10]};
          end
          result_pte <= ptw_pte_data[7:0];
          result_level <= ptw_level;

          // Check permissions again for current access
          if (check_permission(ptw_pte_data[7:0], ptw_is_store_save, ptw_is_fetch_save,
                               ptw_priv_save, ptw_sum_save, ptw_mxr_save)) begin
            $display("PTW: Complete - VA=0x%h translated successfully", ptw_vaddr_save);
            req_ready <= 1;
          end else begin
            $display("PTW: Complete - Permission denied for VA=0x%h", ptw_vaddr_save);
            req_page_fault <= 1;
            req_fault_vaddr <= ptw_vaddr_save;
            req_ready <= 1;
          end

          ptw_state <= PTW_IDLE;
        end

        PTW_FAULT: begin
          // Page fault - but still update TLB to cache faulting translation
          if (ptw_pte_data[PTE_V]) begin
            result_valid <= 1;
            result_vpn <= ptw_vpn_save;
            if (XLEN == 32) begin
              result_ppn <= {{10{1'b0}}, ptw_pte_data[31:10]};
            end else begin
              result_ppn <= {{20{1'b0}}, ptw_pte_data[53:10]};
            end
            result_pte <= ptw_pte_data[7:0];
            result_level <= ptw_level;
          end

          req_page_fault <= 1;
          req_fault_vaddr <= ptw_vaddr_save;
          req_ready <= 1;
          ptw_state <= PTW_IDLE;
        end

        default: ptw_state <= PTW_IDLE;
      endcase
    end
  end

endmodule
