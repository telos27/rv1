# Phase 10: Supervisor Mode and MMU Integration - Implementation Checklist

**Status:** Ready to Begin
**Estimated Duration:** 3-4 weeks
**Target Completion:** 2025-11-12

---

## Overview

This checklist tracks the implementation of Supervisor mode privilege level and MMU integration into the RV1 processor. Follow the phases sequentially, marking items as completed.

**Design Document:** `docs/SUPERVISOR_MODE_AND_MMU_INTEGRATION.md`

---

## Phase 1: Privilege Mode Infrastructure (Week 1)

**Goal:** Add privilege tracking without full S-mode

### 1.1 Add Privilege Register (rv32i_core_pipelined.v)

- [ ] **Add `current_priv` register**
  - File: `rtl/core/rv32i_core_pipelined.v`
  - Add: `reg [1:0] current_priv;  // 00=U, 01=S, 11=M`
  - Location: After pipeline control signals section
  - Initial value: `2'b11` (Machine mode)

- [ ] **Add privilege transition logic**
  ```verilog
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      current_priv <= 2'b11;  // Start in M-mode
    end else begin
      if (trap_entry) begin
        current_priv <= trap_target_priv;
      end else if (mret) begin
        current_priv <= csr_mpp;  // From MSTATUS.MPP
      end else if (sret) begin
        current_priv <= {1'b0, csr_spp};  // From MSTATUS.SPP
      end
    end
  end
  ```

- [ ] **Wire current_priv to CSR file**
  - Add `current_priv` input to csr_file module instantiation

### 1.2 Update MSTATUS (csr_file.v)

- [ ] **Add new MSTATUS fields**
  - File: `rtl/core/csr_file.v`
  - Add: `reg mstatus_sie_r;   // [1] Supervisor Interrupt Enable`
  - Add: `reg mstatus_spie_r;  // [5] Supervisor Previous IE`
  - Add: `reg mstatus_spp_r;   // [8] Supervisor Previous Privilege`

- [ ] **Update mstatus read logic**
  - Modify `gen_mstatus_rv32.mstatus_value` to include new fields
  - Bit [8]: SPP
  - Bit [5]: SPIE
  - Bit [1]: SIE

- [ ] **Update mstatus write logic**
  - Add write logic for SPP, SPIE, SIE in CSR_MSTATUS case

- [ ] **Update trap entry logic**
  - Save SPP on S-mode trap entry: `mstatus_spp_r <= current_priv[0]`

- [ ] **Add output ports**
  - Add: `output wire [1:0] mpp_out`
  - Add: `output wire spp_out`
  - Connect to internal registers

### 1.3 Update Exception Unit (exception_unit.v)

- [ ] **Add current_priv input**
  - File: `rtl/core/exception_unit.v`
  - Add port: `input wire [1:0] current_priv`

- [ ] **Make ECALL privilege-aware**
  ```verilog
  wire [4:0] ecall_cause = (current_priv == 2'b00) ? CAUSE_ECALL_FROM_U_MODE :
                           (current_priv == 2'b01) ? CAUSE_ECALL_FROM_S_MODE :
                                                     CAUSE_ECALL_FROM_M_MODE;
  ```

- [ ] **Add page fault exception codes**
  - Add: `localparam CAUSE_INST_PAGE_FAULT = 5'd12;`
  - Add: `localparam CAUSE_LOAD_PAGE_FAULT = 5'd13;`
  - Add: `localparam CAUSE_STORE_PAGE_FAULT = 5'd15;`

- [ ] **Add page fault detection inputs**
  - Add port: `input wire mem_page_fault`
  - Add port: `input wire [XLEN-1:0] mem_fault_vaddr`
  - Add to priority encoder

### 1.4 Testing Phase 1

- [ ] **Create test: privilege_mode_basic.s**
  - Test M-mode operation (current state)
  - Read MSTATUS.MPP after trap
  - Verify MPP = 11 (M-mode)

- [ ] **Create test: ecall_privilege.s**
  - ECALL from M-mode
  - Check MCAUSE = 11 (ECALL from M-mode)

- [ ] **Run regression tests**
  - All existing tests must still pass
  - Check waveforms for current_priv signal

**Phase 1 Sign-off:** ☐ All tasks complete, tests passing

---

## Phase 2: Supervisor CSRs (Week 1-2)

**Goal:** Add all S-mode CSRs and SRET instruction

### 2.1 Add S-mode CSR Registers (csr_file.v)

- [ ] **Add S-mode trap handling registers**
  ```verilog
  reg [XLEN-1:0] stvec_r;      // Supervisor trap vector
  reg [XLEN-1:0] sscratch_r;   // Supervisor scratch
  reg [XLEN-1:0] sepc_r;       // Supervisor exception PC
  reg [XLEN-1:0] scause_r;     // Supervisor cause
  reg [XLEN-1:0] stval_r;      // Supervisor trap value
  ```

- [ ] **Add CSR address definitions**
  ```verilog
  localparam CSR_SSTATUS  = 12'h100;
  localparam CSR_SIE      = 12'h104;
  localparam CSR_STVEC    = 12'h105;
  localparam CSR_SSCRATCH = 12'h140;
  localparam CSR_SEPC     = 12'h141;
  localparam CSR_SCAUSE   = 12'h142;
  localparam CSR_STVAL    = 12'h143;
  localparam CSR_SIP      = 12'h144;
  ```

- [ ] **Implement SSTATUS read (subset of MSTATUS)**
  ```verilog
  wire [XLEN-1:0] sstatus_value = {
    mstatus_value[31],      // SD (State Dirty)
    {(XLEN-32){1'b0}},      // Reserved
    mstatus_value[19:18],   // MXR, SUM
    13'b0,                  // Reserved
    mstatus_value[8],       // SPP
    3'b0,                   // Reserved
    mstatus_value[5],       // SPIE
    2'b0,                   // Reserved
    mstatus_value[1],       // SIE
    1'b0                    // Reserved
  };
  ```

- [ ] **Implement SIE/SIP read (subset of MIE/MIP)**
  ```verilog
  wire [XLEN-1:0] sie_value = mie_r & 12'h222;  // SSIE, STIE, SEIE
  wire [XLEN-1:0] sip_value = mip_r & 12'h222;  // SSIP, STIP, SEIP
  ```

- [ ] **Add S-mode CSRs to read multiplexer**
  - Add cases for all 8 S-mode CSRs

- [ ] **Add S-mode CSRs to write logic**
  - Reset values (all zeros)
  - Normal CSR write handling
  - SSTATUS write updates MSTATUS fields

### 2.2 Add Trap Delegation (csr_file.v)

- [ ] **Add delegation registers**
  ```verilog
  reg [XLEN-1:0] medeleg_r;  // Machine exception delegation
  reg [XLEN-1:0] mideleg_r;  // Machine interrupt delegation
  ```

- [ ] **Add CSR addresses**
  ```verilog
  localparam CSR_MEDELEG = 12'h302;
  localparam CSR_MIDELEG = 12'h303;
  ```

- [ ] **Implement trap target selection**
  ```verilog
  function [1:0] get_trap_target_priv;
    input [4:0] cause;
    input [1:0] current_priv;
    begin
      if (current_priv == 2'b11) begin
        get_trap_target_priv = 2'b11;  // M-mode traps to M-mode
      end else if (medeleg_r[cause]) begin
        get_trap_target_priv = 2'b01;  // Delegated to S-mode
      end else begin
        get_trap_target_priv = 2'b11;  // Default to M-mode
      end
    end
  endfunction
  ```

- [ ] **Add trap_target_priv output**
  - Add: `output wire [1:0] trap_target_priv`
  - Wire to function result

- [ ] **Update trap entry logic**
  ```verilog
  if (trap_entry) begin
    if (trap_target_priv == 2'b11) begin
      // M-mode trap
      mepc_r <= trap_pc;
      mcause_r <= trap_cause;
      mtval_r <= trap_val;
      mstatus_mpie_r <= mstatus_mie_r;
      mstatus_mie_r <= 1'b0;
      mstatus_mpp_r <= current_priv;
    end else if (trap_target_priv == 2'b01) begin
      // S-mode trap
      sepc_r <= trap_pc;
      scause_r <= trap_cause;
      stval_r <= trap_val;
      mstatus_spie_r <= mstatus_sie_r;
      mstatus_sie_r <= 1'b0;
      mstatus_spp_r <= current_priv[0];
    end
  end
  ```

- [ ] **Update trap vector output**
  ```verilog
  assign trap_vector = (trap_target_priv == 2'b11) ? mtvec_r : stvec_r;
  ```

### 2.3 Add SRET Instruction

- [ ] **Update decoder (decoder.v)**
  - Add SRET detection: `wire is_sret = (instruction == 32'h10200073);`
  - Add output: `output wire is_sret_dec`

- [ ] **Update control unit (control.v)**
  - Add input: `input wire is_sret_dec`
  - Add output: `output wire sret`
  - Wire: `assign sret = is_sret_dec;`

- [ ] **Add SRET handling (csr_file.v)**
  - Add input: `input wire sret`
  - Add output: `output wire [XLEN-1:0] sepc_out`
  - Add SRET logic in always block:
  ```verilog
  if (sret) begin
    mstatus_sie_r <= mstatus_spie_r;
    mstatus_spie_r <= 1'b1;
    mstatus_spp_r <= 1'b0;  // Return to U-mode
  end
  ```
  - Connect: `assign sepc_out = sepc_r;`

- [ ] **Update pipeline PC logic (rv32i_core_pipelined.v)**
  - Add to PC mux: `sret ? sepc_out : ...`
  - Add to flush logic: `flush_ifid = ... || sret`

### 2.4 CSR Privilege Checking

- [ ] **Add privilege checking function (csr_file.v)**
  ```verilog
  function is_csr_accessible;
    input [11:0] addr;
    input [1:0] priv;
    begin
      // CSR[11:10] = minimum privilege level
      case (addr[11:10])
        2'b00: is_csr_accessible = 1'b1;       // U-mode CSRs
        2'b01: is_csr_accessible = (priv >= 2'b01);  // S-mode CSRs
        2'b11: is_csr_accessible = (priv == 2'b11);  // M-mode CSRs
        default: is_csr_accessible = 1'b0;
      endcase
    end
  endfunction
  ```

- [ ] **Update illegal_csr output**
  ```verilog
  assign illegal_csr = csr_we && (!csr_valid || csr_read_only ||
                                   !is_csr_accessible(csr_addr, current_priv));
  ```

### 2.5 Testing Phase 2

- [ ] **Test: s_mode_csrs.s**
  - Write/read all S-mode CSRs
  - Verify SSTATUS is subset of MSTATUS

- [ ] **Test: trap_delegation.s**
  - Set medeleg[8] = 1 (delegate U-mode ECALL)
  - ECALL from U-mode (simulated)
  - Verify trap goes to S-mode (SEPC set, not MEPC)

- [ ] **Test: sret_test.s**
  - Set SEPC, SPP, SPIE
  - Execute SRET
  - Verify privilege restored, PC = SEPC

- [ ] **Test: csr_privilege.s**
  - Try to access M-mode CSR from S-mode
  - Verify illegal instruction exception

- [ ] **Run regression tests**

**Phase 2 Sign-off:** ☐ All tasks complete, tests passing

---

## Phase 3: MMU Integration - Data Access (Week 2-3)

**Goal:** Integrate MMU for data memory accesses

### 3.1 Instantiate MMU (rv32i_core_pipelined.v)

- [ ] **Add MMU signal declarations**
  ```verilog
  // MMU signals
  wire            mmu_req_valid;
  wire [XLEN-1:0] mmu_req_vaddr;
  wire            mmu_req_is_store;
  wire            mmu_req_is_fetch;
  wire [2:0]      mmu_req_size;
  wire            mmu_req_ready;
  wire [XLEN-1:0] mmu_req_paddr;
  wire            mmu_req_page_fault;
  wire [XLEN-1:0] mmu_req_fault_vaddr;

  // MMU page table walk interface
  wire            mmu_ptw_req_valid;
  wire [XLEN-1:0] mmu_ptw_req_addr;
  wire            mmu_ptw_req_ready;
  wire [XLEN-1:0] mmu_ptw_resp_data;
  wire            mmu_ptw_resp_valid;

  // TLB control
  wire            tlb_flush_all;
  wire            tlb_flush_vaddr;
  wire [XLEN-1:0] tlb_flush_addr;
  ```

- [ ] **Instantiate MMU module**
  ```verilog
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
    // Memory interface
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
    // TLB control
    .tlb_flush_all(tlb_flush_all),
    .tlb_flush_vaddr(tlb_flush_vaddr),
    .tlb_flush_addr(tlb_flush_addr)
  );
  ```

- [ ] **Connect MMU request signals**
  ```verilog
  assign mmu_req_valid = exmem_valid && (exmem_mem_read || exmem_mem_write);
  assign mmu_req_vaddr = exmem_alu_result;
  assign mmu_req_is_store = exmem_mem_write;
  assign mmu_req_is_fetch = 1'b0;  // Data access
  assign mmu_req_size = {1'b0, exmem_funct3[1:0]};
  ```

### 3.2 Add Memory Arbiter (data_memory.v)

- [ ] **Add MMU PTW interface ports**
  ```verilog
  // Add to data_memory.v module ports
  input  wire             ptw_req_valid,
  input  wire [XLEN-1:0]  ptw_req_addr,
  output wire             ptw_req_ready,
  output wire [XLEN-1:0]  ptw_resp_data,
  output wire             ptw_resp_valid
  ```

- [ ] **Implement arbiter logic**
  ```verilog
  // Priority: PTW requests have higher priority to avoid deadlock
  wire use_ptw = ptw_req_valid;

  // Mux address
  wire [XLEN-1:0] mem_addr_mux = use_ptw ? ptw_req_addr : addr;
  wire mem_read_mux = use_ptw ? 1'b1 : read_enable;
  wire mem_write_mux = use_ptw ? 1'b0 : write_enable;

  // Route responses
  assign ptw_req_ready = use_ptw;
  assign ptw_resp_data = mem_data_read;
  assign ptw_resp_valid = use_ptw;
  ```

- [ ] **Update memory access logic**
  - Use `mem_addr_mux` instead of `addr`
  - PTW accesses are always word-sized reads

### 3.3 Add Pipeline Stall Logic

- [ ] **Detect MMU busy (rv32i_core_pipelined.v)**
  ```verilog
  wire mmu_busy = mmu_req_valid && !mmu_req_ready && !mmu_req_page_fault;
  ```

- [ ] **Update stall signals**
  ```verilog
  assign stall_pc = load_use_hazard || mul_div_busy || fpu_busy ||
                    atomic_busy || mmu_busy;
  assign stall_ifid = stall_pc;
  ```

- [ ] **Use translated physical address**
  ```verilog
  wire [XLEN-1:0] mem_physical_addr = mmu_req_ready ? mmu_req_paddr :
                                                       exmem_alu_result;
  ```

- [ ] **Connect physical address to data memory**
  - Replace `exmem_alu_result` with `mem_physical_addr` in data memory instantiation

### 3.4 Handle Page Faults

- [ ] **Connect page fault to exception unit**
  - Wire `mmu_req_page_fault` to exception_unit `mem_page_fault` input
  - Wire `mmu_req_fault_vaddr` to exception_unit `mem_fault_vaddr` input

- [ ] **Update exception unit (exception_unit.v)**
  ```verilog
  // Page fault detection
  wire mem_inst_page_fault = mem_page_fault && mem_fetch;
  wire mem_load_page_fault = mem_page_fault && mem_read && !mem_write;
  wire mem_store_page_fault = mem_page_fault && mem_write;
  ```

- [ ] **Add to exception priority encoder**
  - Add page fault cases with correct priorities

- [ ] **Save fault address to mtval/stval**
  - Update trap entry logic to save `mem_fault_vaddr`

### 3.5 Add SFENCE.VMA Instruction

- [ ] **Update decoder (decoder.v)**
  ```verilog
  // SFENCE.VMA: 0001001 rs2 rs1 000 00000 1110011
  wire is_sfence_vma = (instruction[31:25] == 7'b0001001) &&
                       (instruction[14:12] == 3'b000) &&
                       (instruction[11:7] == 5'b00000) &&
                       (instruction[6:0] == 7'b1110011);
  output wire is_sfence_vma_dec;
  output wire [4:0] sfence_rs1;  // Virtual address (if rs1 != 0)
  output wire [4:0] sfence_rs2;  // ASID (not implemented yet)
  ```

- [ ] **Update control unit (control.v)**
  - Add input: `input wire is_sfence_vma_dec`
  - Add output: `output wire sfence_vma`

- [ ] **Connect SFENCE.VMA to TLB flush (rv32i_core_pipelined.v)**
  ```verilog
  // TLB flush logic
  wire sfence_vma_ex = idex_valid && idex_sfence_vma;
  assign tlb_flush_all = sfence_vma_ex && (idex_rs1_addr == 5'b0);
  assign tlb_flush_vaddr = sfence_vma_ex && (idex_rs1_addr != 5'b0);
  assign tlb_flush_addr = idex_rs1_data;  // Virtual address from rs1
  ```

### 3.6 Testing Phase 3

- [ ] **Test: bare_mode.s**
  - SATP = 0 (bare mode)
  - Access memory
  - Verify VA = PA (direct mapping)

- [ ] **Test: identity_mapping.s**
  - Set up identity page table (VA = PA)
  - Enable Sv32 (SATP.MODE = 1)
  - Access memory
  - Verify translation works

- [ ] **Test: tlb_hit_miss.s**
  - Access same page twice
  - First access: TLB miss (waveform shows page table walk)
  - Second access: TLB hit (waveform shows immediate ready)

- [ ] **Test: page_fault_invalid.s**
  - Set up page table with invalid PTE (V=0)
  - Access invalid page
  - Verify load page fault exception (cause = 13)

- [ ] **Test: page_fault_permission.s**
  - Set up RO page (R=1, W=0)
  - Try to write to page
  - Verify store page fault exception (cause = 15)

- [ ] **Test: sfence_vma.s**
  - Access page (TLB hit)
  - Execute SFENCE.VMA
  - Access same page (TLB miss, page table walk)

- [ ] **Performance test: TLB hit rate**
  - Create test with loop accessing multiple pages
  - Measure TLB hit rate using debug CSRs
  - Target: > 95% hit rate

**Phase 3 Sign-off:** ☐ All tasks complete, tests passing

---

## Phase 4: MMU Integration - Instruction Fetch (Week 3-4) [OPTIONAL]

**Goal:** Add MMU for instruction fetch (optional enhancement)

### Option A: Dual MMU (Better Performance)

- [ ] **Instantiate second MMU for IF stage**
  - Separate TLB for instructions
  - Connect to instruction memory
  - Add instruction page fault handling

### Option B: Shared MMU (Simpler)

- [ ] **Add IF/MEM arbiter**
  - Prioritize MEM stage (avoid deadlock)
  - Stall IF when MEM using MMU
  - Add state machine for arbitration

### Testing Phase 4

- [ ] **Test: instruction_page_fault.s**
  - Jump to invalid page
  - Verify instruction page fault (cause = 12)

- [ ] **Performance test**
  - Measure CPI with instruction MMU
  - Ensure CPI increase < 10%

**Phase 4 Sign-off:** ☐ All tasks complete, tests passing

---

## Phase 5: Testing and Validation (Week 4)

**Goal:** Comprehensive testing of complete S-mode system

### 5.1 Unit Tests

- [ ] **Test: privilege_transitions.s**
  - Test U→S→M→S→U transitions
  - Verify privilege restored correctly

- [ ] **Test: csr_privilege_all.s**
  - Test CSR access from all privilege levels
  - Verify illegal instruction exceptions

- [ ] **Test: nested_traps.s**
  - Trap in S-mode handler (goes to M-mode)
  - MRET returns to S-mode
  - SRET returns to U-mode

### 5.2 Integration Tests

- [ ] **Test: mini_os.s**
  - Simple OS kernel running in S-mode
  - User program in U-mode
  - Syscall via ECALL (U→S)
  - Return via SRET (S→U)

- [ ] **Test: page_table_walk.s**
  - Set up 2-level page table (Sv32)
  - Access pages at different levels
  - Verify correct translation

- [ ] **Test: context_switch.s**
  - Simulate OS context switch
  - Save/restore SATP
  - Flush TLB with SFENCE.VMA

### 5.3 Stress Tests

- [ ] **Test: tlb_thrashing.s**
  - Access more pages than TLB entries
  - Measure performance degradation

- [ ] **Test: random_access.s**
  - Random memory access pattern
  - Verify all accesses translated correctly

### 5.4 Performance Analysis

- [ ] **Measure TLB hit rate**
  - Use debug CSRs
  - Target: > 95%

- [ ] **Measure PTW latency**
  - Waveform analysis
  - Sv32: 4-12 cycles expected

- [ ] **Measure CPI with MMU**
  - Bare mode vs. virtual memory
  - Target: CPI < 1.5

- [ ] **Measure memory bandwidth**
  - Count total memory accesses
  - Expected: +5-10% with MMU

### 5.5 Documentation

- [ ] **Update README.md**
  - Add Supervisor mode to features
  - Update supported privilege levels

- [ ] **Update PHASES.md**
  - Mark Phase 10 complete
  - Document achievements

- [ ] **Create PHASE10_SUMMARY.md**
  - Implementation summary
  - Performance results
  - Lessons learned

**Phase 5 Sign-off:** ☐ All tasks complete, tests passing

---

## Final Verification

### Regression Testing
- [ ] All Phase 1-9 tests still pass
- [ ] No performance degradation in bare mode
- [ ] All 42 RV32I compliance tests pass
- [ ] M extension tests pass
- [ ] A extension tests pass
- [ ] F/D extension tests pass
- [ ] C extension tests pass

### Code Quality
- [ ] All files compile without warnings
- [ ] Code follows naming conventions
- [ ] Comments updated
- [ ] No TODO markers left in code
- [ ] Git commits are clean and descriptive

### Documentation
- [ ] All design documents accurate
- [ ] Test reports complete
- [ ] Performance analysis documented
- [ ] Known issues documented

---

## Success Criteria

| Criterion | Target | Result |
|-----------|--------|--------|
| **Functional** | All tests pass | ☐ |
| **Privilege Modes** | U/S/M working | ☐ |
| **MMU Integration** | Data access via MMU | ☐ |
| **TLB Hit Rate** | > 95% | ☐ |
| **CPI** | < 1.5 | ☐ |
| **Page Table Walk** | 4-12 cycles (Sv32) | ☐ |
| **Regression** | No existing tests broken | ☐ |

---

## Notes and Issues

### Implementation Notes
- Date started: ___________
- Unexpected issues: ___________
- Design changes: ___________

### Performance Results
- TLB hit rate: _____%
- Average PTW latency: _____ cycles
- CPI with MMU: _____
- CPI without MMU: _____

### Future Enhancements
- [ ] Instruction fetch MMU (if not in Phase 4)
- [ ] Superpage support (2MB, 1GB pages)
- [ ] ASID support in TLB
- [ ] Sv39 support (RV64)
- [ ] Hardware A/D bit updates

---

**Checklist Version:** 1.0
**Last Updated:** 2025-10-12
**Status:** Ready to Begin
