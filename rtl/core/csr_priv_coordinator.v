// csr_priv_coordinator.v - CSR and Privilege Mode Coordination
// Handles CSR forwarding (MRET/SRET) and privilege mode tracking
// Extracted from rv32i_core_pipelined.v for better modularity
// Author: RV1 Project
// Date: 2025-10-26

`include "config/rv_config.vh"
`include "config/rv_csr_defines.vh"

module csr_priv_coordinator #(
  parameter XLEN = `XLEN
) (
  input  wire             clk,
  input  wire             reset_n,

  // Trap/xRET control inputs
  input  wire             trap_flush,
  input  wire [1:0]       trap_target_priv,
  input  wire             mret_flush,
  input  wire             sret_flush,

  // MSTATUS bits from CSR file
  input  wire [1:0]       mpp,
  input  wire             spp,
  input  wire             mstatus_mie,
  input  wire             mstatus_sie,
  input  wire             mstatus_mpie,
  input  wire             mstatus_spie,
  input  wire             mstatus_mxr,
  input  wire             mstatus_sum,

  // Pipeline stage signals for CSR forwarding
  input  wire             exmem_is_mret,
  input  wire             exmem_is_sret,
  input  wire             exmem_valid,
  input  wire             idex_is_csr,
  input  wire             idex_valid,
  input  wire [11:0]      idex_csr_addr,
  input  wire             exception,
  input  wire [XLEN-1:0]  ex_csr_rdata,

  // Outputs
  output wire [1:0]       current_priv,       // Current privilege mode
  output wire [1:0]       effective_priv,     // Forwarded privilege mode (for CSR checks)
  output wire [XLEN-1:0]  ex_csr_rdata_forwarded  // Forwarded CSR read data
);

  //==========================================================================
  // Privilege Mode Tracking
  //==========================================================================
  // Privilege mode state machine: updates on trap entry and xRET
  reg [1:0] current_priv_r;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      current_priv_r <= 2'b11;  // Start in Machine mode on reset
    end else begin
      if (trap_flush) begin
        // On trap entry, move to target privilege level
        current_priv_r <= trap_target_priv;
        `ifdef DEBUG_PRIV
        $display("[PRIV] Time=%0t TRAP: priv %b -> %b", $time, current_priv_r, trap_target_priv);
        `endif
      end else if (mret_flush) begin
        // On MRET, restore privilege from MSTATUS.MPP
        current_priv_r <= mpp;
        `ifdef DEBUG_PRIV
        $display("[PRIV] Time=%0t MRET: priv %b -> %b (from MPP)", $time, current_priv_r, mpp);
        `endif
      end else if (sret_flush) begin
        // On SRET, restore privilege from MSTATUS.SPP
        current_priv_r <= {1'b0, spp};  // SPP: 0=U, 1=S -> {1'b0, spp} = 00 or 01
        `ifdef DEBUG_PRIV
        $display("[PRIV] Time=%0t SRET: priv %b -> %b (from SPP=%b)", $time, current_priv_r, {1'b0, spp}, spp);
        `endif
      end
    end
  end

  assign current_priv = current_priv_r;

  //==========================================================================
  // CSR MRET/SRET Forwarding
  //==========================================================================
  // When MRET/SRET is in MEM stage, it updates mstatus at the end of the cycle.
  // If a CSR read of mstatus/sstatus is in EX stage, it needs the updated value.
  // Forward the "next" mstatus value to avoid reading stale data.

  // Compute the "next" mstatus value after MRET
  function [XLEN-1:0] compute_mstatus_after_mret;
    input [XLEN-1:0] current_mstatus;
    input mpie_val;
    reg [XLEN-1:0] next_mstatus;
    begin
      next_mstatus = current_mstatus;
      // MIE ← MPIE
      next_mstatus[MSTATUS_MIE_BIT] = mpie_val;
      // MPIE ← 1
      next_mstatus[MSTATUS_MPIE_BIT] = 1'b1;
      // MPP ← U (2'b00)
      next_mstatus[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] = 2'b00;
      compute_mstatus_after_mret = next_mstatus;
    end
  endfunction

  // Compute the "next" mstatus value after SRET
  function [XLEN-1:0] compute_mstatus_after_sret;
    input [XLEN-1:0] current_mstatus;
    input spie_val;
    reg [XLEN-1:0] next_mstatus;
    begin
      next_mstatus = current_mstatus;
      // SIE ← SPIE
      next_mstatus[MSTATUS_SIE_BIT] = spie_val;
      // SPIE ← 1
      next_mstatus[MSTATUS_SPIE_BIT] = 1'b1;
      // SPP ← U (1'b0)
      next_mstatus[MSTATUS_SPP_BIT] = 1'b0;
      compute_mstatus_after_sret = next_mstatus;
    end
  endfunction

  // Construct current mstatus from individual bits (matching csr_file.v format)
  wire [XLEN-1:0] current_mstatus_reconstructed;
  assign current_mstatus_reconstructed = {
    {(XLEN-32){1'b0}},           // Upper bits (if XLEN > 32)
    12'b0,                        // Reserved bits [31:20]
    mstatus_mxr,                  // MXR [19]
    mstatus_sum,                  // SUM [18]
    5'b0,                         // Reserved bits [17:13]
    mpp,                          // MPP [12:11]
    2'b0,                         // Reserved [10:9]
    spp,                          // SPP [8]
    mstatus_mpie,                 // MPIE [7]
    1'b0,                         // Reserved [6]
    mstatus_spie,                 // SPIE [5]
    1'b0,                         // Reserved [4]
    mstatus_mie,                  // MIE [3]
    1'b0,                         // Reserved [2]
    mstatus_sie,                  // SIE [1]
    1'b0                          // Reserved [0]
  };

  // Track MRET/SRET from previous cycle (for forwarding after hazard stall)
  // These flags must stay set until the CSR read that caused the hazard actually executes
  reg exmem_is_mret_r;
  reg exmem_is_sret_r;
  reg exmem_valid_r;

  // Detect when a CSR instruction consumes the forwarding
  // Only consume if the CSR read will actually complete (not invalidated by exception)
  wire mret_forward_consumed = exmem_is_mret_r && idex_is_csr && idex_valid && !exception &&
                                ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));
  wire sret_forward_consumed = exmem_is_sret_r && idex_is_csr && idex_valid && !exception &&
                                ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      exmem_is_mret_r <= 1'b0;
      exmem_is_sret_r <= 1'b0;
      exmem_valid_r <= 1'b0;
    end else begin
      // Set when MRET/SRET is in MEM, clear when CSR read consumes it
      if (mret_forward_consumed) begin
        exmem_is_mret_r <= 1'b0;  // Clear when forwarding is consumed
      end else if (exmem_is_mret && exmem_valid && !exception) begin
        exmem_is_mret_r <= 1'b1;  // Set when MRET enters MEM
      end
      // Else: hold current value (stays set during stall)

      if (sret_forward_consumed) begin
        exmem_is_sret_r <= 1'b0;  // Clear when forwarding is consumed
      end else if (exmem_is_sret && exmem_valid && !exception) begin
        exmem_is_sret_r <= 1'b1;  // Set when SRET enters MEM
      end
      // Else: hold current value (stays set during stall)

      exmem_valid_r <= exmem_valid;

      `ifdef DEBUG_CSR_FORWARD
      if (exmem_is_mret && exmem_valid) begin
        $display("[CSR_FORWARD] MRET in MEM: setting mret_r");
      end
      if (mret_forward_consumed) begin
        $display("[CSR_FORWARD] CSR read consumed MRET forwarding: clearing mret_r");
      end
      if (exmem_is_mret_r && !mret_forward_consumed) begin
        $display("[CSR_FORWARD] Holding mret_r: waiting for CSR read in EX");
      end
      `endif
    end
  end

  // Forward mstatus if:
  // Case 1: MRET is in MEM stage NOW (same cycle - no stall occurred)
  // Case 2: MRET was in MEM stage LAST cycle (CSR stalled, now advancing)
  // CSR being read must be mstatus or sstatus
  wire forward_mret_mstatus = ((exmem_is_mret && exmem_valid && !exception) || exmem_is_mret_r) &&
                              (idex_is_csr && idex_valid) &&
                              ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));

  wire forward_sret_mstatus = ((exmem_is_sret && exmem_valid && !exception) || exmem_is_sret_r) &&
                              (idex_is_csr && idex_valid) &&
                              ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));

  // If MRET/SRET was last cycle, mstatus is already updated - just use current value
  // If MRET/SRET is this cycle, compute what it will be
  wire [XLEN-1:0] mstatus_after_mret = exmem_is_mret_r ? current_mstatus_reconstructed :
                                        compute_mstatus_after_mret(current_mstatus_reconstructed, mstatus_mpie);
  wire [XLEN-1:0] mstatus_after_sret = exmem_is_sret_r ? current_mstatus_reconstructed :
                                        compute_mstatus_after_sret(current_mstatus_reconstructed, mstatus_spie);

  assign ex_csr_rdata_forwarded = forward_mret_mstatus ? mstatus_after_mret :
                                  forward_sret_mstatus ? mstatus_after_sret :
                                  ex_csr_rdata;  // Normal case: no forwarding needed

  `ifdef DEBUG_CSR_FORWARD
  always @(posedge clk) begin
    if (forward_mret_mstatus || forward_sret_mstatus) begin
      $display("[CSR_FORWARD] Time=%0t forward_mret=%b forward_sret=%b", $time, forward_mret_mstatus, forward_sret_mstatus);
      $display("[CSR_FORWARD]   current_mstatus=%h forwarded_mstatus=%h", current_mstatus_reconstructed, ex_csr_rdata_forwarded);
      $display("[CSR_FORWARD]   exmem_is_mret=%b exmem_is_sret=%b exmem_valid=%b", exmem_is_mret, exmem_is_sret, exmem_valid);
      $display("[CSR_FORWARD]   idex_is_csr=%b idex_valid=%b idex_csr_addr=%h", idex_is_csr, idex_valid, idex_csr_addr);
    end
    if (idex_is_csr && idex_valid && ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS))) begin
      $display("[CSR_FORWARD] CSR read: addr=%h rdata=%h (forwarded=%h)", idex_csr_addr, ex_csr_rdata, ex_csr_rdata_forwarded);
      $display("[CSR_FORWARD]   Conditions: exmem_mret=%b exmem_mret_r=%b exmem_valid=%b exc=%b",
               exmem_is_mret, exmem_is_mret_r, exmem_valid, exception);
      $display("[CSR_FORWARD]   forward_mret=%b forward_sret=%b", forward_mret_mstatus, forward_sret_mstatus);
    end
  end
  `endif

  //==========================================================================
  // Privilege Mode Forwarding
  //==========================================================================
  // When MRET/SRET is in MEM stage, it updates current_priv at the end of the cycle.
  // However, instructions already in earlier pipeline stages (IF/ID/EX) use the OLD
  // current_priv for CSR privilege checks and exception delegation decisions.
  //
  // This causes incorrect behavior when a CSR access immediately follows MRET/SRET:
  // - Example: MRET changes M→S, next instruction accesses CSR
  // - CSR check sees old priv=M instead of new priv=S
  // - Delegation decision is wrong (M-mode traps never delegate)
  //
  // Solution: Forward the new privilege mode from MEM stage to earlier stages.

  // Compute new privilege mode from MRET/SRET in MEM stage
  wire [1:0] mret_new_priv = mpp;              // MRET restores from MPP
  wire [1:0] sret_new_priv = {1'b0, spp};      // SRET restores from SPP (0=U, 1=S)

  // Forward privilege mode when MRET/SRET is in MEM stage
  wire forward_priv_mode = (exmem_is_mret || exmem_is_sret) && exmem_valid && !exception;

  // Effective privilege mode for EX stage (used for CSR checks and delegation)
  assign effective_priv = forward_priv_mode ?
                          (exmem_is_mret ? mret_new_priv : sret_new_priv) :
                          current_priv_r;

  `ifdef DEBUG_PRIV
  always @(posedge clk) begin
    if (forward_priv_mode) begin
      $display("[PRIV_FORWARD] Time=%0t Forwarding privilege: %s in MEM, current_priv=%b -> effective_priv=%b",
               $time, exmem_is_mret ? "MRET" : "SRET", current_priv_r, effective_priv);
      if (idex_is_csr && idex_valid) begin
        $display("[PRIV_FORWARD]   CSR access in EX: addr=0x%03x will use effective_priv=%b",
                 idex_csr_addr, effective_priv);
      end
    end
  end
  `endif

endmodule
