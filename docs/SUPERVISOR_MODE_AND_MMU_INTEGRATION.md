# Supervisor Mode and MMU Integration Design Document

## Executive Summary

This document outlines the design for adding **Supervisor (S) mode** privilege level and integrating the existing **MMU module** into the RV1 processor pipeline. This will enable the processor to run operating systems with proper memory protection and privilege separation.

**Current Status:**
- ✅ MMU module implemented (standalone, not integrated)
- ✅ SATP CSR implemented in csr_file.v
- ✅ MSTATUS.SUM and MSTATUS.MXR bits implemented
- ❌ Processor only supports Machine mode (no privilege tracking)
- ❌ MMU not connected to pipeline
- ❌ No Supervisor-mode CSRs
- ❌ No SRET instruction
- ❌ No privilege-based exception handling

**Target:**
- Full 3-privilege-mode system: User (U), Supervisor (S), Machine (M)
- MMU integrated into MEM stage
- Page fault exceptions
- Supervisor-mode CSRs
- SRET instruction
- Proper trap delegation

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Current State Analysis](#current-state-analysis)
3. [Privilege Mode Design](#privilege-mode-design)
4. [Supervisor CSRs](#supervisor-csrs)
5. [MMU Integration](#mmu-integration)
6. [Exception Handling Updates](#exception-handling-updates)
7. [Pipeline Modifications](#pipeline-modifications)
8. [Implementation Plan](#implementation-plan)
9. [Testing Strategy](#testing-strategy)
10. [Performance Considerations](#performance-considerations)

---

## 1. Architecture Overview

### 1.1 RISC-V Privilege Levels

```
┌─────────────────────────────────────────────────────┐
│  Privilege Level Encoding                           │
├─────────────────────────────────────────────────────┤
│  00 = User (U)         - Applications               │
│  01 = Supervisor (S)   - Operating System           │
│  10 = Reserved         - (Not used in RISC-V)       │
│  11 = Machine (M)      - Firmware/Bootloader        │
└─────────────────────────────────────────────────────┘
```

### 1.2 System Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                     Machine Mode (M)                           │
│  - Highest privilege                                           │
│  - Handles all traps by default                                │
│  - Can delegate traps to S-mode                                │
│  - Full access to all system resources                         │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│                   Supervisor Mode (S)                          │
│  - Operating system privilege                                  │
│  - Controls virtual memory (MMU)                               │
│  - Handles delegated exceptions from M-mode                    │
│  - Can access S-mode and some M-mode CSRs                      │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│                      User Mode (U)                             │
│  - Lowest privilege                                            │
│  - Application code                                            │
│  - Virtual memory enabled (if SATP configured)                 │
│  - Limited CSR access                                          │
└────────────────────────────────────────────────────────────────┘
```

### 1.3 Memory Access with MMU

```
Virtual Address (User/Supervisor)
         │
         ▼
    ┌────────┐
    │  MMU   │ ◄─── SATP (page table base)
    │  TLB   │ ◄─── privilege_mode
    └────┬───┘ ◄─── MSTATUS.SUM, MSTATUS.MXR
         │
         ├─► TLB Hit? ──Yes──► Permission OK? ──Yes──► Physical Address
         │      │                    │
         │      No                   No
         │      │                    │
         ▼      ▼                    ▼
    Page Table Walk           Page Fault Exception
```

---

## 2. Current State Analysis

### 2.1 Existing CSR File (csr_file.v)

**Current Implementation:**
- ✅ **Machine-mode CSRs**: mstatus, mie, mtvec, mscratch, mepc, mcause, mtval, mip
- ✅ **SATP register**: Already implemented (address 0x180)
- ✅ **MSTATUS.SUM**: Bit 18 (Supervisor User Memory access)
- ✅ **MSTATUS.MXR**: Bit 19 (Make eXecutable Readable)
- ✅ **MSTATUS.MPP**: Bits [12:11] (Machine Previous Privilege)
- ❌ **No privilege mode tracking**: No current_priv register
- ❌ **No MSTATUS.SPP**: Supervisor Previous Privilege (bit 8)
- ❌ **No MSTATUS.SIE/SPIE**: Supervisor interrupt enable bits
- ❌ **No Supervisor CSRs**: sstatus, sie, stvec, sscratch, sepc, scause, stval, sip
- ❌ **No delegation CSRs**: medeleg, mideleg

### 2.2 Existing MMU Module (mmu.v)

**Current Implementation:**
- ✅ **Fully functional**: TLB, page table walker, permission checking
- ✅ **Sv32/Sv39 support**: Both RV32 and RV64 translation modes
- ✅ **CSR inputs**: satp, privilege_mode, mstatus_sum, mstatus_mxr
- ✅ **Exception outputs**: req_page_fault, req_fault_vaddr
- ❌ **Not integrated**: Not instantiated in rv32i_core_pipelined.v
- ❌ **No memory interface**: ptw_* ports not connected to data memory

### 2.3 Existing Exception Unit (exception_unit.v)

**Current Implementation:**
- ✅ **Exception codes**: Defined for all standard exceptions
- ✅ **ECALL detection**: Hardcoded to CAUSE_ECALL_FROM_M_MODE (code 11)
- ❌ **No privilege-aware ECALL**: Doesn't distinguish U/S/M mode
- ❌ **No page fault exceptions**: Codes 12, 13, 15 not generated
- ❌ **No privilege tracking**: No input for current privilege mode

### 2.4 Missing Components

1. **Privilege mode register**: 2-bit register to track current privilege (U/S/M)
2. **Supervisor CSRs**: 8 new S-mode CSRs
3. **SRET instruction**: Return from supervisor trap
4. **Trap delegation**: medeleg/mideleg CSRs
5. **MMU integration**: Connect MMU to MEM stage
6. **Page fault exceptions**: Integration with exception_unit.v
7. **Privilege-aware CSR access**: Check privilege on CSR read/write

---

## 3. Privilege Mode Design

### 3.1 Privilege Mode Register

Add a 2-bit register to track current privilege level:

```verilog
// In rv32i_core_pipelined.v
reg [1:0] current_priv;  // 00=U, 01=S, 11=M

always @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    current_priv <= 2'b11;  // Start in Machine mode
  end else begin
    if (trap_entry) begin
      // On trap entry, update to target privilege
      current_priv <= trap_target_priv;
    end else if (mret || sret) begin
      // On trap return, restore previous privilege
      current_priv <= return_priv;
    end
  end
end
```

### 3.2 Privilege Transitions

```
┌─────────────────────────────────────────────────────────────┐
│                  Privilege State Machine                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   Machine Mode (11) ◄──┐                                    │
│        │               │                                    │
│        │ MRET          │ Exception                          │
│        │               │                                    │
│        ▼               │                                    │
│   [MPP value] ─────────┘                                    │
│                                                             │
│   Supervisor Mode (01) ◄──┐                                 │
│        │                   │                                │
│        │ SRET              │ Exception                      │
│        │                   │                                │
│        ▼                   │                                │
│   [SPP value] ─────────────┘                                │
│                                                             │
│   User Mode (00)                                            │
│        │                                                    │
│        │ Exception/ECALL                                    │
│        │                                                    │
│        └───────────► S or M mode (based on delegation)     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 MSTATUS Updates

Add new fields to MSTATUS:

```
RV32 MSTATUS Layout (32 bits):
┌────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│ 31 │  19 │  18 │  12 │   8 │   7 │   5 │   3 │   0 │
├────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│ SD │ MXR │ SUM │ MPP │ SPP │MPIE │SPIE │ MIE │ SIE │
└────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘

New fields to add:
- [8]     SPP  - Supervisor Previous Privilege (0=U, 1=S)
- [5]     SPIE - Supervisor Previous Interrupt Enable
- [1]     SIE  - Supervisor Interrupt Enable
- [31]    SD   - State Dirty (for FP/vector state - read-only)
```

**Implementation:**
```verilog
// Add to csr_file.v
reg        mstatus_sie_r;   // [1] - Supervisor Interrupt Enable
reg        mstatus_spie_r;  // [5] - Supervisor Previous Interrupt Enable
reg        mstatus_spp_r;   // [8] - Supervisor Previous Privilege
```

---

## 4. Supervisor CSRs

### 4.1 Required S-mode CSRs

| CSR Name | Address | Description | Implementation |
|----------|---------|-------------|----------------|
| **sstatus** | 0x100 | Supervisor status (subset of mstatus) | Read-only view of mstatus |
| **sie** | 0x104 | Supervisor interrupt enable | Subset of mie |
| **stvec** | 0x105 | Supervisor trap vector | Full 32/64-bit register |
| **sscratch** | 0x140 | Supervisor scratch register | Full 32/64-bit register |
| **sepc** | 0x141 | Supervisor exception PC | Full 32/64-bit register |
| **scause** | 0x142 | Supervisor exception cause | Full 32/64-bit register |
| **stval** | 0x143 | Supervisor trap value | Full 32/64-bit register |
| **sip** | 0x144 | Supervisor interrupt pending | Subset of mip |

### 4.2 SSTATUS Read-Only View

SSTATUS provides a restricted view of MSTATUS:

```verilog
// Read-only subset of mstatus visible to S-mode
wire [XLEN-1:0] sstatus_value = {
  mstatus_value[31],      // SD
  {(XLEN-32){1'b0}},      // Reserved (RV64)
  mstatus_value[19:18],   // MXR, SUM
  5'b0,                   // Reserved
  2'b00,                  // UXL (hardwired to 00 for RV32)
  4'b0,                   // Reserved
  mstatus_value[8],       // SPP
  3'b0,                   // Reserved
  mstatus_value[5],       // SPIE
  2'b0,                   // Reserved (UPIE, UIE not implemented)
  mstatus_value[1],       // SIE
  1'b0                    // Reserved
};
```

### 4.3 New CSR Registers

```verilog
// Add to csr_file.v

// Supervisor Trap Handling CSRs
reg [XLEN-1:0] stvec_r;      // Supervisor trap vector
reg [XLEN-1:0] sscratch_r;   // Supervisor scratch register
reg [XLEN-1:0] sepc_r;       // Supervisor exception PC
reg [XLEN-1:0] scause_r;     // Supervisor exception cause
reg [XLEN-1:0] stval_r;      // Supervisor trap value

// Note: sie and sip are subsets of mie/mip
// We can implement them as bit-masked views rather than separate registers
```

### 4.4 Trap Delegation CSRs

```verilog
// Machine-mode trap delegation
reg [XLEN-1:0] medeleg_r;    // Machine exception delegation
reg [XLEN-1:0] mideleg_r;    // Machine interrupt delegation

// Bit N set in medeleg = delegate exception N to S-mode
// Bit N set in mideleg = delegate interrupt N to S-mode
```

---

## 5. MMU Integration

### 5.1 Integration Point: MEM Stage

The MMU will be integrated in the **MEM stage** where memory accesses occur:

```
┌──────────────────────────────────────────────────────────────┐
│                      MEM Stage (Current)                     │
│                                                              │
│  EXMEM Reg ──► Address ──► Data Memory ──► Data ──► MEMWB   │
│                                                              │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                     MEM Stage (With MMU)                     │
│                                                              │
│  EXMEM Reg ──► Virtual Addr ──┐                             │
│                                ▼                             │
│                            ┌───────┐                         │
│                            │  MMU  │◄─── CSRs               │
│                            │  TLB  │     (satp, priv_mode)  │
│                            └───┬───┘                         │
│                                │                             │
│                ┌───────────────┼──────────────┐             │
│                │               │              │             │
│          TLB Hit/Pass    TLB Miss       Page Fault          │
│                │               │              │             │
│                ▼               ▼              ▼             │
│         Physical Addr   Wait (stall)   Exception           │
│                │                              │             │
│                ▼                              │             │
│          Data Memory ──► Data ──► MEMWB      │             │
│                                               │             │
│                                               └──► Flush    │
└──────────────────────────────────────────────────────────────┘
```

### 5.2 MMU Instantiation

```verilog
// In rv32i_core_pipelined.v, add after EXMEM register

// MMU for data accesses
wire            mmu_req_valid;
wire [XLEN-1:0] mmu_req_vaddr;
wire            mmu_req_is_store;
wire            mmu_req_is_fetch;
wire [2:0]      mmu_req_size;
wire            mmu_req_ready;
wire [XLEN-1:0] mmu_req_paddr;
wire            mmu_req_page_fault;
wire [XLEN-1:0] mmu_req_fault_vaddr;

// MMU memory interface (page table walk)
wire            mmu_ptw_req_valid;
wire [XLEN-1:0] mmu_ptw_req_addr;
wire            mmu_ptw_req_ready;
wire [XLEN-1:0] mmu_ptw_resp_data;
wire            mmu_ptw_resp_valid;

// TLB control
wire            tlb_flush_all;
wire            tlb_flush_vaddr;
wire [XLEN-1:0] tlb_flush_addr;

mmu #(
  .XLEN(XLEN),
  .TLB_ENTRIES(16)
) u_mmu (
  .clk(clk),
  .reset_n(reset_n),

  // Translation request
  .req_valid(mmu_req_valid),
  .req_vaddr(mmu_req_vaddr),
  .req_is_store(mmu_req_is_store),
  .req_is_fetch(mmu_req_is_fetch),
  .req_size(mmu_req_size),
  .req_ready(mmu_req_ready),
  .req_paddr(mmu_req_paddr),
  .req_page_fault(mmu_req_page_fault),
  .req_fault_vaddr(mmu_req_fault_vaddr),

  // Memory interface for page table walks
  .ptw_req_valid(mmu_ptw_req_valid),
  .ptw_req_addr(mmu_ptw_req_addr),
  .ptw_req_ready(mmu_ptw_req_ready),
  .ptw_resp_data(mmu_ptw_resp_data),
  .ptw_resp_valid(mmu_ptw_resp_valid),

  // CSR interface
  .satp(csr_satp),
  .privilege_mode(current_priv),
  .mstatus_sum(csr_mstatus_sum),
  .mstatus_mxr(csr_mstatus_mxr),

  // TLB flush control
  .tlb_flush_all(tlb_flush_all),
  .tlb_flush_vaddr(tlb_flush_vaddr),
  .tlb_flush_addr(tlb_flush_addr)
);
```

### 5.3 Memory Access Flow

```verilog
// MMU request signals
assign mmu_req_valid = exmem_valid && (exmem_mem_read || exmem_mem_write);
assign mmu_req_vaddr = exmem_alu_result;  // Virtual address from ALU
assign mmu_req_is_store = exmem_mem_write;
assign mmu_req_is_fetch = 1'b0;  // Data access (not instruction fetch)
assign mmu_req_size = exmem_funct3[1:0];  // Size from funct3

// Use physical address if translation succeeds, else stall
wire [XLEN-1:0] mem_physical_addr = mmu_req_ready ? mmu_req_paddr : exmem_alu_result;

// Stall pipeline if MMU is busy (page table walk in progress)
wire mmu_busy = mmu_req_valid && !mmu_req_ready && !mmu_req_page_fault;
assign stall_pc = stall_pc_orig || mmu_busy;
assign stall_ifid = stall_ifid_orig || mmu_busy;
```

### 5.4 Instruction Fetch MMU (Optional - Phase 2)

For complete virtual memory support, instruction fetches should also go through the MMU:

```verilog
// Separate MMU instance for instruction fetch (optional optimization)
// Or share the same MMU with arbiter logic

// For Phase 1, we can keep instruction memory in physical space
// OS kernel code runs with paging disabled (M-mode)
```

**Recommendation**: Start with **data MMU only**, add instruction MMU later.

---

## 6. Exception Handling Updates

### 6.1 New Exception Codes

Add page fault exception codes to exception_unit.v:

```verilog
// Add to exception_unit.v
localparam CAUSE_INST_PAGE_FAULT   = 5'd12;
localparam CAUSE_LOAD_PAGE_FAULT   = 5'd13;
localparam CAUSE_STORE_PAGE_FAULT  = 5'd15;
```

### 6.2 Exception Unit Modifications

```verilog
// Add to exception_unit.v module ports
input  wire [1:0]      current_priv,      // Current privilege mode
input  wire            mem_page_fault,     // Page fault from MMU
input  wire [XLEN-1:0] mem_fault_vaddr,   // Faulting virtual address

// Update ECALL handling to be privilege-aware
wire id_ecall_exc_code = id_valid && id_ecall ?
  (current_priv == 2'b00 ? CAUSE_ECALL_FROM_U_MODE :
   current_priv == 2'b01 ? CAUSE_ECALL_FROM_S_MODE :
                           CAUSE_ECALL_FROM_M_MODE) : 5'd0;

// Add page fault detection
wire mem_page_fault_load = mem_page_fault && mem_read && !mem_write;
wire mem_page_fault_store = mem_page_fault && mem_write;
```

### 6.3 Trap Routing Logic

```verilog
// Add to csr_file.v

// Determine trap target privilege based on delegation
function [1:0] get_trap_target_priv;
  input [4:0] cause;
  input [1:0] current_priv;
  input [XLEN-1:0] medeleg;
  begin
    // M-mode traps always go to M-mode
    if (current_priv == 2'b11) begin
      get_trap_target_priv = 2'b11;
    end
    // Check if exception is delegated to S-mode
    else if (medeleg[cause] && current_priv <= 2'b01) begin
      get_trap_target_priv = 2'b01;  // S-mode
    end
    else begin
      get_trap_target_priv = 2'b11;  // M-mode (default)
    end
  end
endfunction

// Trap entry logic
wire [1:0] trap_target_priv = get_trap_target_priv(trap_cause, current_priv, medeleg_r);

always @(posedge clk or negedge reset_n) begin
  if (trap_entry) begin
    if (trap_target_priv == 2'b11) begin
      // Machine-mode trap
      mepc_r  <= trap_pc;
      mcause_r <= trap_cause;
      mtval_r  <= trap_val;
      mstatus_mpie_r <= mstatus_mie_r;
      mstatus_mie_r  <= 1'b0;
      mstatus_mpp_r  <= current_priv;
    end else if (trap_target_priv == 2'b01) begin
      // Supervisor-mode trap
      sepc_r  <= trap_pc;
      scause_r <= trap_cause;
      stval_r  <= trap_val;
      mstatus_spie_r <= mstatus_sie_r;
      mstatus_sie_r  <= 1'b0;
      mstatus_spp_r  <= current_priv[0];  // 0=U, 1=S
    end
  end
end
```

### 6.4 SRET Instruction

Add SRET (Supervisor Return) instruction support:

```verilog
// Add to decoder.v
wire is_sret = (instruction == 32'h10200073);  // SRET encoding

// Add to control.v
wire sret = is_sret_dec;

// Add to csr_file.v
input wire sret,
output wire [XLEN-1:0] sepc_out,

always @(posedge clk or negedge reset_n) begin
  if (sret) begin
    mstatus_sie_r <= mstatus_spie_r;
    mstatus_spie_r <= 1'b1;
    mstatus_spp_r <= 1'b0;  // Return to U-mode
  end
end

assign sepc_out = sepc_r;
```

---

## 7. Pipeline Modifications

### 7.1 Files to Modify

| File | Changes Required |
|------|------------------|
| **rtl/core/rv32i_core_pipelined.v** | Add MMU instance, privilege tracking, stall logic |
| **rtl/core/csr_file.v** | Add S-mode CSRs, delegation CSRs, trap routing |
| **rtl/core/decoder.v** | Add SRET detection |
| **rtl/core/control.v** | Add SRET control signal, CSR privilege checks |
| **rtl/core/exception_unit.v** | Add page fault exceptions, privilege-aware ECALL |
| **rtl/memory/data_memory.v** | Add MMU interface for PTW |
| **rtl/memory/instruction_memory.v** | (Optional) Add MMU interface for instruction fetch |

### 7.2 New Signals

```verilog
// In rv32i_core_pipelined.v

// Privilege tracking
reg  [1:0] current_priv;           // Current privilege mode
wire [1:0] trap_target_priv;       // Target privilege for trap
wire [1:0] return_priv;            // Return privilege for MRET/SRET

// MMU control
wire       mmu_busy;               // MMU page table walk in progress
wire       tlb_flush_all;          // Flush TLB (SFENCE.VMA)
wire       tlb_flush_vaddr;        // Flush specific TLB entry
wire [XLEN-1:0] tlb_flush_addr;    // Address for selective flush

// SRET handling
wire       is_sret;                // SRET instruction detected
wire       sret_flush;             // Flush pipeline on SRET
wire [XLEN-1:0] sepc_out;          // SEPC for return

// New exception signals
wire       page_fault;             // Page fault from MMU
wire [4:0] page_fault_cause;       // 12/13/15 for I/L/S page fault
```

### 7.3 Control Flow Changes

```verilog
// PC next logic (add SRET case)
assign pc_next = trap_entry ? trap_vector :
                 mret       ? mepc_out :
                 sret       ? sepc_out :
                 ex_take_branch ? ex_branch_target :
                 idex_jump  ? ex_jump_target :
                 pc_increment;

// Pipeline flush logic (add SRET and page fault)
assign flush_ifid = (ex_take_branch || idex_jump || trap_entry || mret || sret);
assign flush_idex = (ex_take_branch || trap_entry || mret || sret);

// Stall logic (add MMU busy)
assign stall_pc = load_use_hazard || mul_div_busy || fpu_busy || atomic_busy || mmu_busy;
assign stall_ifid = stall_pc;
```

---

## 8. Implementation Plan

### Phase 1: Privilege Mode Infrastructure (Week 1)

**Goal**: Add privilege tracking without full S-mode

#### Tasks:
1. **Add privilege register** to rv32i_core_pipelined.v
   - [ ] Add `current_priv` register (2 bits)
   - [ ] Initialize to M-mode (2'b11) on reset
   - [ ] Add privilege transition logic on MRET

2. **Update MSTATUS** in csr_file.v
   - [ ] Add SIE, SPIE, SPP fields
   - [ ] Update mstatus read/write logic
   - [ ] Update trap entry to save SPP

3. **Update exception_unit.v**
   - [ ] Add current_priv input
   - [ ] Make ECALL privilege-aware (codes 8/9/11)
   - [ ] Add page fault exception codes (12/13/15)

4. **Testing**
   - [ ] Verify MRET restores MPP correctly
   - [ ] Verify ECALL generates correct code based on privilege
   - [ ] Run existing tests to ensure no regression

**Success Criteria:**
- All existing tests pass
- Privilege mode tracked correctly
- ECALL exception code depends on current privilege

---

### Phase 2: Supervisor CSRs (Week 1-2)

**Goal**: Add all S-mode CSRs and SRET instruction

#### Tasks:
1. **Add S-mode CSRs** to csr_file.v
   - [ ] Add stvec, sscratch, sepc, scause, stval registers
   - [ ] Implement sstatus as mstatus subset (read-only view)
   - [ ] Implement sie/sip as mie/mip subsets
   - [ ] Add CSR address cases for all S-mode CSRs

2. **Add trap delegation** to csr_file.v
   - [ ] Add medeleg and mideleg registers
   - [ ] Implement `get_trap_target_priv()` function
   - [ ] Update trap entry to route to S-mode or M-mode
   - [ ] Update trap_vector output to use stvec or mtvec

3. **Add SRET instruction**
   - [ ] Update decoder.v to detect SRET (0x10200073)
   - [ ] Update control.v to generate SRET signal
   - [ ] Add SRET handling in csr_file.v (restore SPP, SPIE)
   - [ ] Add SRET to PC mux and flush logic in pipeline

4. **CSR privilege checking**
   - [ ] Add illegal CSR access detection based on privilege
   - [ ] S-mode can't access M-mode-only CSRs
   - [ ] U-mode can only access U-mode CSRs

5. **Testing**
   - [ ] Test S-mode CSR read/write
   - [ ] Test trap delegation (M-mode → S-mode)
   - [ ] Test SRET returning to U-mode
   - [ ] Test illegal CSR access from wrong privilege

**Success Criteria:**
- All S-mode CSRs functional
- Trap delegation working
- SRET returns to correct privilege
- CSR privilege checks enforce security

---

### Phase 3: MMU Integration - Data Access (Week 2-3)

**Goal**: Integrate MMU for data memory accesses

#### Tasks:
1. **Instantiate MMU** in rv32i_core_pipelined.v
   - [ ] Add MMU instance after EXMEM register
   - [ ] Connect CSR signals (satp, privilege_mode, sum, mxr)
   - [ ] Connect virtual address from EXMEM
   - [ ] Connect page fault outputs to exception unit

2. **Add MMU-memory arbiter**
   - [ ] Create arbiter for data memory access
   - [ ] Route CPU requests and PTW requests to data memory
   - [ ] Handle PTW responses back to MMU
   - [ ] Priority: PTW requests can preempt CPU requests

3. **Add stall logic**
   - [ ] Detect MMU busy (page table walk in progress)
   - [ ] Stall pipeline during PTW
   - [ ] Resume when MMU ready or page fault

4. **Handle page faults**
   - [ ] Route MMU page fault to exception unit
   - [ ] Distinguish I/L/S page fault (cause 12/13/15)
   - [ ] Save faulting virtual address to mtval/stval
   - [ ] Flush pipeline on page fault

5. **Add SFENCE.VMA** (TLB flush instruction)
   - [ ] Decode SFENCE.VMA (0x12000073 + variants)
   - [ ] Generate TLB flush signals
   - [ ] Full flush or address-specific flush

6. **Testing**
   - [ ] Test bare mode (SATP=0, direct mapping)
   - [ ] Test Sv32 translation with identity mapping
   - [ ] Test TLB hits and misses
   - [ ] Test page faults (invalid PTE, permission denied)
   - [ ] Test SFENCE.VMA TLB flushing

**Success Criteria:**
- Data accesses go through MMU
- TLB hit rate > 90% for typical access patterns
- Page table walk completes in 2-3 cycles (Sv32)
- Page faults generate correct exceptions

---

### Phase 4: MMU Integration - Instruction Fetch (Week 3-4)

**Goal**: Add MMU for instruction fetch (optional)

#### Tasks:
1. **Add IF-stage MMU** (optional - separate instance)
   - [ ] Instantiate second MMU for instruction fetch
   - [ ] Connect to instruction memory
   - [ ] Handle instruction page faults (cause 12)

2. **Alternative: Shared MMU** (simpler, lower performance)
   - [ ] Add arbiter for IF and MEM stage requests
   - [ ] Prioritize MEM stage (avoid deadlock)
   - [ ] Stall IF stage when MEM stage using MMU

3. **Testing**
   - [ ] Test instruction fetch through virtual memory
   - [ ] Test instruction page faults
   - [ ] Verify no performance degradation

**Success Criteria:**
- Both data and instruction accesses translated
- No pipeline deadlocks
- CPI increase < 10% with MMU enabled

---

### Phase 5: Testing and Validation (Week 4)

**Goal**: Comprehensive testing of complete S-mode system

#### Tasks:
1. **Unit tests**
   - [ ] CSR read/write from different privilege levels
   - [ ] Privilege transitions (U→S→M→S→U)
   - [ ] TLB hit/miss scenarios
   - [ ] Page fault handling

2. **Integration tests**
   - [ ] Simple OS kernel (trap handlers in S-mode)
   - [ ] User-mode application (with syscalls)
   - [ ] Page table setup and translation
   - [ ] Context switching simulation

3. **Stress tests**
   - [ ] Random TLB thrashing
   - [ ] Concurrent page faults
   - [ ] Deep page table walks

4. **Performance analysis**
   - [ ] Measure TLB hit rate
   - [ ] Measure PTW latency
   - [ ] Measure CPI with MMU enabled
   - [ ] Compare bare mode vs. virtual memory

**Success Criteria:**
- All unit tests pass
- Simple OS can boot and handle traps
- User programs can run with virtual memory
- Performance acceptable (CPI < 1.5)

---

## 9. Testing Strategy

### 9.1 Unit Test Scenarios

| Test | Description | Expected Result |
|------|-------------|-----------------|
| **priv_mode_transitions** | Test U→S→M→S→U transitions | Privilege changes correctly |
| **ecall_from_u** | ECALL from U-mode | Trap to S-mode (if delegated) or M-mode |
| **ecall_from_s** | ECALL from S-mode | Trap to M-mode (cause 9) |
| **sret_to_u** | SRET returns to U-mode | Privilege restored, SPP=0 |
| **csr_privilege** | Access M-CSR from S-mode | Illegal instruction exception |
| **tlb_hit** | Access page twice | Second access hits TLB |
| **tlb_miss** | Access new page | Page table walk, TLB updated |
| **page_fault_invalid** | Access invalid PTE | Page fault exception (cause 13) |
| **page_fault_permission** | Write to RO page | Page fault exception (cause 15) |
| **sfence_vma** | SFENCE.VMA, then access | TLB miss, page table walk |

### 9.2 Integration Test: Simple OS

Create a minimal OS kernel test:

```assembly
# os_kernel.s - Minimal S-mode OS kernel

.section .text.kernel
.global _start

_start:
    # Initialize kernel (M-mode)
    # 1. Set up page tables
    # 2. Set SATP to enable paging
    # 3. Delegate exceptions to S-mode (medeleg)
    # 4. Set stvec to S-mode trap handler
    # 5. Drop to S-mode via MRET

    # ...

s_mode_entry:
    # S-mode kernel running
    # - Handle system calls from U-mode
    # - Manage virtual memory
    # - Schedule user programs

    # Load user program and enter U-mode
    # ...
    SRET  # Enter U-mode

s_trap_handler:
    # S-mode trap handler
    # Check scause to determine trap type
    # - ECALL from U-mode: handle syscall
    # - Page fault: allocate page
    # - Illegal instruction: kill process

    SRET  # Return to U-mode

.section .text.user
user_program:
    # U-mode user program
    li a0, 42
    ECALL  # Syscall to S-mode
    EBREAK # End program
```

### 9.3 Virtual Memory Test

```c
// test_vm.c - Virtual memory test program

// Set up simple page table
uint32_t page_table[1024] __attribute__((aligned(4096)));

void setup_page_table() {
    // Identity map first 4MB
    for (int i = 0; i < 1024; i++) {
        page_table[i] = (i << 10) | 0xCF;  // PPN | flags (V,R,W,X,U,A,D)
    }

    // Set SATP to enable Sv32
    uint32_t satp = (1 << 31) | ((uint32_t)page_table >> 12);
    write_csr(CSR_SATP, satp);

    // Flush TLB
    asm volatile("sfence.vma");
}

int main() {
    setup_page_table();

    // Test virtual memory access
    volatile int *ptr = (int *)0x80001000;
    *ptr = 42;
    assert(*ptr == 42);

    // Test page fault
    volatile int *invalid = (int *)0xFFFFFFFF;
    *invalid = 0;  // Should trigger page fault

    return 0;
}
```

---

## 10. Performance Considerations

### 10.1 TLB Performance

**TLB Hit Rate:**
- Target: > 95% for typical workloads
- 16-entry TLB should be sufficient for small programs
- Larger workloads may benefit from 32-64 entries

**TLB Miss Penalty:**
- Sv32: 2 memory accesses (2-6 cycles each) = 4-12 cycles
- Sv39: 3 memory accesses (2-6 cycles each) = 6-18 cycles

**Optimization:**
- Larger TLB (increase TLB_ENTRIES parameter)
- Superpage support (reduce TLB pressure)
- Page table caching

### 10.2 Pipeline Impact

**Additional Stalls:**
- Page table walk: 4-18 cycles per TLB miss
- MMU arbiter conflicts: 1-2 cycles (if shared between IF and MEM)

**CPI Increase Estimate:**
- Bare mode (no MMU): CPI ≈ 1.2
- With MMU (95% TLB hit): CPI ≈ 1.25 (+4%)
- With MMU (90% TLB hit): CPI ≈ 1.35 (+12%)

### 10.3 Memory Bandwidth

**Instruction Fetch:**
- Current: 1 memory access per instruction
- With MMU: +0.05 accesses per instruction (5% TLB miss rate)

**Data Access:**
- Current: 0.3 memory accesses per instruction (30% load/store)
- With MMU: +0.015 accesses per instruction (5% TLB miss on 30% accesses)

**Total Increase:** ~6.5% more memory bandwidth

---

## 11. Debugging Support

### 11.1 Debug Outputs

Add debug CSRs for monitoring:

```verilog
// In csr_file.v, add debug-only CSRs (0x7XX range)

localparam CSR_DEBUG_PRIV     = 12'h7C0;  // Current privilege mode
localparam CSR_DEBUG_TLB_HITS = 12'h7C1;  // TLB hit counter
localparam CSR_DEBUG_TLB_MISS = 12'h7C2;  // TLB miss counter
localparam CSR_DEBUG_PF_COUNT = 12'h7C3;  // Page fault counter

// Debug counters (not in spec, for testing only)
reg [31:0] tlb_hit_count;
reg [31:0] tlb_miss_count;
reg [31:0] page_fault_count;

// Read logic
case (csr_addr)
    CSR_DEBUG_PRIV:     csr_rdata = {30'b0, current_priv};
    CSR_DEBUG_TLB_HITS: csr_rdata = tlb_hit_count;
    CSR_DEBUG_TLB_MISS: csr_rdata = tlb_miss_count;
    CSR_DEBUG_PF_COUNT: csr_rdata = page_fault_count;
    // ...
endcase
```

### 11.2 Waveform Debugging

Key signals to monitor:

```
- current_priv           (privilege mode)
- mmu_req_valid          (MMU request)
- mmu_req_vaddr          (virtual address)
- mmu_req_paddr          (physical address)
- mmu_req_ready          (translation complete)
- mmu_req_page_fault     (page fault)
- tlb_hit                (TLB hit signal)
- ptw_state              (page table walk state)
- trap_entry             (trap occurred)
- trap_target_priv       (trap target privilege)
```

---

## 12. References

### 12.1 RISC-V Specifications

- **RISC-V Privileged Architecture** (Volume II)
  - Chapter 3: Machine-Level ISA
  - Chapter 4: Supervisor-Level ISA
  - Chapter 4.3: Sv32 Virtual Memory
  - Chapter 4.4: Sv39 Virtual Memory

### 12.2 Relevant CSRs

| CSR | Address | Purpose |
|-----|---------|---------|
| mstatus | 0x300 | Machine status register |
| medeleg | 0x302 | Machine exception delegation |
| mideleg | 0x303 | Machine interrupt delegation |
| mtvec | 0x305 | Machine trap vector |
| mepc | 0x341 | Machine exception PC |
| sstatus | 0x100 | Supervisor status register |
| stvec | 0x105 | Supervisor trap vector |
| sepc | 0x141 | Supervisor exception PC |
| satp | 0x180 | Supervisor address translation |

### 12.3 Instruction Encodings

```
MRET:  0011 0000 0010 0000 0000 0000 0111 0011  (0x30200073)
SRET:  0001 0000 0010 0000 0000 0000 0111 0011  (0x10200073)
SFENCE.VMA: 0001 001 rs2 rs1 000 00000 1110011  (0x12000073 base)
```

---

## 13. Summary and Next Steps

### 13.1 Implementation Phases

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| **Phase 1** | Week 1 | Privilege mode tracking, MSTATUS.SPP |
| **Phase 2** | Week 1-2 | S-mode CSRs, SRET, trap delegation |
| **Phase 3** | Week 2-3 | MMU integration (data access) |
| **Phase 4** | Week 3-4 | MMU integration (instruction fetch - optional) |
| **Phase 5** | Week 4 | Testing and validation |

**Total Estimated Time:** 3-4 weeks

### 13.2 Risk Mitigation

**Technical Risks:**
1. **MMU-memory interface complexity**: Start with data-only MMU
2. **Pipeline stalls**: Add performance counters early
3. **Deadlock scenarios**: Careful arbiter design, priority scheme

**Testing Risks:**
1. **Complex state space**: Incremental testing per phase
2. **Timing issues**: Use waveform debugging extensively
3. **Edge cases**: Create comprehensive test suite

### 13.3 Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Functional** | All tests pass | Unit + integration tests |
| **Performance** | CPI < 1.5 | Benchmark programs |
| **TLB Hit Rate** | > 95% | Hardware counters |
| **Code Coverage** | > 90% | Testbench coverage |

---

## Appendix A: File Modification Checklist

### Core Pipeline
- [ ] `rtl/core/rv32i_core_pipelined.v` - Add privilege register, MMU instance
- [ ] `rtl/core/csr_file.v` - Add S-mode CSRs, delegation
- [ ] `rtl/core/decoder.v` - Add SRET, SFENCE.VMA decoding
- [ ] `rtl/core/control.v` - Add SRET control signal
- [ ] `rtl/core/exception_unit.v` - Add page faults, privilege-aware ECALL

### Memory System
- [ ] `rtl/memory/data_memory.v` - Add MMU-PTW interface
- [ ] `rtl/memory/instruction_memory.v` - (Optional) Add MMU interface

### MMU (Already Implemented)
- [x] `rtl/core/mmu.v` - Standalone module ready to integrate

### Testing
- [ ] `tb/integration/tb_privilege_modes.v` - New testbench
- [ ] `tests/asm/test_supervisor.s` - S-mode test program
- [ ] `tests/asm/test_virtual_memory.s` - MMU test program

---

**Document Version:** 1.0
**Date:** 2025-10-12
**Author:** RV1 Project
**Status:** Design Complete - Ready for Implementation
