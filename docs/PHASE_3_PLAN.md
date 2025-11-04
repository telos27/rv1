# Phase 3 Implementation Plan: RV64 Upgrade

**Status**: ✅ **RV64I COMPLETE** (In Progress)
**Start Date**: 2025-11-03
**Estimated Duration**: 2-3 weeks
**Goal**: Upgrade CPU from RV32IMAFDC to RV64IMAFDC with Sv39 MMU
**Progress**: RV64I instruction set 98.1% complete (53/54 tests passing)

---

## Table of Contents
1. [Overview](#overview)
2. [Scope & Objectives](#scope--objectives)
3. [Architecture Changes](#architecture-changes)
4. [Implementation Tasks](#implementation-tasks)
5. [Testing Strategy](#testing-strategy)
6. [Risk Assessment](#risk-assessment)
7. [Success Criteria](#success-criteria)

---

## Overview

### Current State (RV32)
- **XLEN**: 32 bits
- **ISA**: RV32IMAFDC (I, M, A, F, D, C extensions)
- **MMU**: Sv32 (2-level page tables, 4GB virtual address space)
- **TLB**: 16 entries, 2-level translation
- **Memory**: 64KB IMEM, 64KB DMEM
- **Compliance**: 80/81 RV32 tests passing (98.8%)
- **OS Support**: FreeRTOS fully operational

### Target State (RV64)
- **XLEN**: 64 bits
- **ISA**: RV64IMAFDC (all extensions upgraded to 64-bit)
- **MMU**: Sv39 (3-level page tables, 512GB virtual address space)
- **TLB**: 16 entries, 3-level translation
- **Memory**: 1MB IMEM, 4MB DMEM (expanded for xv6/Linux)
- **Compliance**: 87/87 RV64 tests passing (100% target)
- **OS Support**: FreeRTOS on RV64, ready for xv6-riscv

### Why RV64?
1. **Industry Standard**: Most modern RISC-V systems use 64-bit
2. **OS Requirements**: xv6 and Linux expect 64-bit architecture
3. **Address Space**: Larger memory space for complex applications
4. **Future-Proof**: Better long-term compatibility

---

## Scope & Objectives

### In Scope
✅ **Core Changes**:
- 64-bit datapath (ALU, registers, CSRs)
- RV64I instructions (ADDW, SUBW, LD, SD, etc.)
- RV64M instructions (MULW, DIVW, REMW, etc.)
- RV64A instructions (64-bit atomics)
- RV64F/D (already 64-bit, minor updates)
- RV64C (compressed 64-bit variants)

✅ **MMU Changes**:
- Sv39 page table walker (3-level vs 2-level)
- Extended VPN/PPN fields (39-bit VA, 56-bit PA)
- TLB updates for Sv39 format
- SATP register mode field (mode=8 for Sv39)

✅ **Memory Changes**:
- Expand IMEM: 64KB → 1MB
- Expand DMEM: 64KB → 4MB
- Update memory modules for 64-bit addressing

✅ **Testing**:
- Run 87 RV64 official compliance tests
- Validate FreeRTOS on RV64
- Create custom RV64-specific tests

### Out of Scope (Future Work)
❌ **RV128**: Not implementing 128-bit support
❌ **Sv48/Sv57**: Only Sv39 MMU (not higher levels)
❌ **Performance**: No microarchitecture optimization yet
❌ **New Extensions**: No B/V/K extensions (future phases)

---

## Architecture Changes

### 1. Datapath (32-bit → 64-bit)

#### Registers
**Current (RV32)**:
```verilog
reg [31:0] x_reg [0:31];  // Integer registers
reg [63:0] f_reg [0:31];  // FP registers (already 64-bit)
```

**Target (RV64)**:
```verilog
reg [63:0] x_reg [0:31];  // Integer registers (64-bit)
reg [63:0] f_reg [0:31];  // FP registers (unchanged)
```

#### ALU
**Changes**:
- Widen all arithmetic operations to 64-bit
- Add 32-bit "W" variants (ADDW, SUBW, etc.)
  - Operate on lower 32 bits
  - Sign-extend result to 64 bits
- Shift operations: support SHAMT[0:5] (6 bits for 64-bit shifts)

#### Pipeline Registers
**All pipeline stages need widening**:
```verilog
// IF/ID
reg [63:0] ifid_pc;
reg [31:0] ifid_instruction;  // Instructions still 32-bit

// ID/EX
reg [63:0] idex_pc;
reg [63:0] idex_rs1_data;
reg [63:0] idex_rs2_data;
reg [63:0] idex_imm;

// EX/MEM
reg [63:0] exmem_alu_result;
reg [63:0] exmem_rs2_data;
reg [63:0] exmem_pc;

// MEM/WB
reg [63:0] memwb_alu_result;
reg [63:0] memwb_mem_data;
```

### 2. Instruction Decode

#### New RV64I Instructions (12 new instructions)
| Instruction | Opcode | Description |
|-------------|--------|-------------|
| **LWU** | 0000011 | Load word unsigned (zero-extend) |
| **LD** | 0000011 | Load doubleword |
| **SD** | 0100011 | Store doubleword |
| **ADDIW** | 0011011 | Add immediate word (32-bit + sign-extend) |
| **SLLIW** | 0011011 | Shift left logical immediate word |
| **SRLIW** | 0011011 | Shift right logical immediate word |
| **SRAIW** | 0011011 | Shift right arithmetic immediate word |
| **ADDW** | 0111011 | Add word |
| **SUBW** | 0111011 | Subtract word |
| **SLLW** | 0111011 | Shift left logical word |
| **SRLW** | 0111011 | Shift right logical word |
| **SRAW** | 0111011 | Shift right arithmetic word |

**Decoding Updates**:
```verilog
wire is_rv64i_op = (opcode == 7'b0111011);  // R-type word ops
wire is_rv64i_imm = (opcode == 7'b0011011); // I-type word ops
wire is_ld = (opcode == 7'b0000011) && (funct3 == 3'b011);
wire is_sd = (opcode == 7'b0100011) && (funct3 == 3'b011);
wire is_lwu = (opcode == 7'b0000011) && (funct3 == 3'b110);
```

#### RV64M Instructions (5 new instructions)
| Instruction | Opcode | Description |
|-------------|--------|-------------|
| **MULW** | 0111011 | Multiply word |
| **DIVW** | 0111011 | Divide word (signed) |
| **DIVUW** | 0111011 | Divide word (unsigned) |
| **REMW** | 0111011 | Remainder word (signed) |
| **REMUW** | 0111011 | Remainder word (unsigned) |

**Implementation**:
- Use existing multiplier/divider
- Truncate inputs to 32 bits
- Sign-extend output to 64 bits

### 3. Memory System

#### Load/Store Unit
**Current (RV32)**:
- LB, LH, LW, LBU, LHU (5 load types)
- SB, SH, SW (3 store types)

**Target (RV64)**:
- LB, LH, LW, LD, LBU, LHU, LWU (7 load types)
- SB, SH, SW, SD (4 store types)

**Changes**:
```verilog
// Load data extraction (MEM stage)
always @(*) begin
  case (funct3)
    3'b000: load_data = {{56{mem_rdata[7]}}, mem_rdata[7:0]};    // LB
    3'b001: load_data = {{48{mem_rdata[15]}}, mem_rdata[15:0]};  // LH
    3'b010: load_data = {{32{mem_rdata[31]}}, mem_rdata[31:0]};  // LW
    3'b011: load_data = mem_rdata[63:0];                         // LD (new)
    3'b100: load_data = {56'b0, mem_rdata[7:0]};                 // LBU
    3'b101: load_data = {48'b0, mem_rdata[15:0]};                // LHU
    3'b110: load_data = {32'b0, mem_rdata[31:0]};                // LWU (new)
    default: load_data = 64'b0;
  endcase
end
```

#### Memory Modules
**IMEM Expansion** (64KB → 1MB):
```verilog
module imem #(
  parameter ADDR_WIDTH = 20,  // 2^20 = 1MB (was 16 for 64KB)
  parameter DATA_WIDTH = 64
) (
  input  wire                  clk,
  input  wire [ADDR_WIDTH-1:0] addr,
  output reg  [DATA_WIDTH-1:0] data
);
  reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
endmodule
```

**DMEM Expansion** (64KB → 4MB):
```verilog
module dmem #(
  parameter ADDR_WIDTH = 22,  // 2^22 = 4MB (was 16 for 64KB)
  parameter DATA_WIDTH = 64
) (
  // ... similar expansion
);
```

### 4. MMU: Sv32 → Sv39

#### Address Translation

**Sv32 (Current)**:
```
Virtual Address (32 bits):
  VPN[1] (10 bits) | VPN[0] (10 bits) | Offset (12 bits)

Physical Address (34 bits):
  PPN[1] (12 bits) | PPN[0] (10 bits) | Offset (12 bits)

Page Table Entry (32 bits):
  PPN[1] PPN[0] | RSW | D A G U X W R V
```

**Sv39 (Target)**:
```
Virtual Address (39 bits):
  VPN[2] (9 bits) | VPN[1] (9 bits) | VPN[0] (9 bits) | Offset (12 bits)

Physical Address (56 bits):
  PPN[2] (26 bits) | PPN[1] (9 bits) | PPN[0] (9 bits) | Offset (12 bits)

Page Table Entry (64 bits):
  Reserved (10 bits) | PPN[2] PPN[1] PPN[0] (44 bits) | RSW | D A G U X W R V
```

#### Page Table Walker

**State Machine** (add LEVEL2 state):
```verilog
typedef enum logic [2:0] {
  IDLE,
  LEVEL2,      // New state for Sv39
  LEVEL1,
  LEVEL0,
  CHECK_PTE,
  PAGE_FAULT,
  TRANSLATE_DONE
} ptw_state_t;
```

**VPN Extraction**:
```verilog
wire [8:0] vpn2 = vaddr[38:30];  // New for Sv39
wire [8:0] vpn1 = vaddr[29:21];
wire [8:0] vpn0 = vaddr[20:12];
```

**PTE Address Calculation**:
```verilog
// Level 2 (new)
wire [63:0] pte_addr_L2 = {satp_ppn, 12'b0} + {vpn2, 3'b0};

// Level 1
wire [63:0] pte_addr_L1 = {pte_ppn, 12'b0} + {vpn1, 3'b0};

// Level 0
wire [63:0] pte_addr_L0 = {pte_ppn, 12'b0} + {vpn0, 3'b0};
```

#### TLB Updates

**TLB Entry Format** (expand PPN):
```verilog
typedef struct packed {
  logic        valid;
  logic [26:0] asid;      // ASID from SATP
  logic [26:0] vpn;       // VPN[2:0] = 27 bits (was 20 bits)
  logic [43:0] ppn;       // PPN[2:0] = 44 bits (was 22 bits)
  logic        d;         // Dirty
  logic        a;         // Accessed
  logic        u;         // User
  logic        x;         // Execute
  logic        w;         // Write
  logic        r;         // Read
} tlb_entry_t;
```

#### SATP Register

**Format Change**:
```verilog
// RV32 SATP (32 bits):
//   MODE[31] | ASID[30:22] | PPN[21:0]

// RV64 SATP (64 bits):
//   MODE[63:60] | ASID[59:44] | PPN[43:0]
//
// MODE values:
//   0 = Bare (no translation)
//   8 = Sv39
//   9 = Sv48 (not implemented)
```

**Mode Check**:
```verilog
wire sv39_enabled = (satp[63:60] == 4'd8);
wire translation_enabled = privilege_mode != M_MODE && sv39_enabled;
```

### 5. CSRs

#### Width Changes
**All CSRs become 64-bit**:
```verilog
// Machine-mode CSRs
reg [63:0] mstatus;
reg [63:0] misa;
reg [63:0] medeleg;
reg [63:0] mideleg;
reg [63:0] mie;
reg [63:0] mtvec;
reg [63:0] mcounteren;
reg [63:0] mscratch;
reg [63:0] mepc;
reg [63:0] mcause;
reg [63:0] mtval;
reg [63:0] mip;

// Supervisor-mode CSRs
reg [63:0] sstatus;
reg [63:0] sie;
reg [63:0] stvec;
reg [63:0] scounteren;
reg [63:0] sscratch;
reg [63:0] sepc;
reg [63:0] scause;
reg [63:0] stval;
reg [63:0] sip;
reg [63:0] satp;
```

#### MISA Updates
```verilog
// RV64 MISA encoding:
//   MXL[63:62] = 2 (64-bit)
//   Extensions[25:0] = installed extensions
assign misa = {
  2'b10,          // MXL=2 (RV64)
  36'b0,          // Reserved
  26'b00000000000101000100101101  // IMAFDCU extensions
};
```

---

## Implementation Tasks

### Task Breakdown (Estimated 15-20 days)

#### Week 1: Core & Decode (5-7 days) ✅ **COMPLETE**

**Day 1-2: Configuration & Parameters** ✅
- [x] Update `rv_config.vh`: Set XLEN=64 (Session 77)
- [x] Create `rv64_config.vh` for RV64-specific parameters (Session 77)
- [x] Update all module parameters to use XLEN (Session 77)
- [x] Update compile-time defines for RV64 (Session 77)

**Day 3-4: Register File & Datapath** ✅
- [x] Widen register file to 64 bits (Session 77)
- [x] Update pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB) (Session 77)
- [x] Widen ALU to 64 bits (Session 77)
- [x] Implement 32-bit "W" instructions (ADDW, SUBW, etc.) (Session 78)

**Day 5-7: Instruction Decode** ✅
- [x] Add RV64I instruction decoding (LD, SD, LWU, ADDIW, etc.) (Session 78-79)
- [ ] Add RV64M instruction decoding (MULW, DIVW, etc.) - DEFERRED
- [x] Update immediate generation for 64-bit (Session 78)
- [x] Update shift amount handling (6-bit for 64-bit shifts) (Session 81)
- [x] Test: Basic RV64I instruction tests (Session 80-81) - **53/54 passing (98.1%)**

#### Week 2: Memory & MMU (5-7 days)

**Day 8-9: Memory System**
- [ ] Expand IMEM to 1MB (update addressing, initialization)
- [ ] Expand DMEM to 4MB
- [ ] Update load/store unit for LD/SD/LWU
- [ ] Update byte lane selection logic for 64-bit
- [ ] Test: Memory access tests (LD, SD, LWU)

**Day 10-12: Sv39 MMU**
- [ ] Update SATP register format (64-bit, MODE field)
- [ ] Add VPN[2] extraction and Level 2 page table walk
- [ ] Update PTE format parsing (64-bit PTEs, 44-bit PPN)
- [ ] Expand TLB entries to Sv39 format
- [ ] Update physical address generation (56-bit PA)
- [ ] Test: Page table walk tests (3-level)

**Day 13-14: CSRs**
- [ ] Widen all CSR registers to 64 bits
- [ ] Update MISA (MXL=2 for RV64)
- [ ] Update CSR read/write logic for 64-bit
- [ ] Update trap value registers (mtval, stval) for 64-bit addresses
- [ ] Test: CSR access tests

#### Week 3: Integration & Testing (3-5 days)

**Day 15-16: Integration**
- [ ] Integrate all changes (core, memory, MMU, CSRs)
- [ ] Fix compilation errors
- [ ] Fix synthesis warnings
- [ ] Update testbenches for 64-bit
- [ ] Update build system (Makefiles, scripts)

**Day 17-18: Official Compliance Testing**
- [ ] Run RV64I tests (48 tests)
- [ ] Run RV64M tests (8 tests)
- [ ] Run RV64A tests (10 tests)
- [ ] Run RV64F tests (11 tests)
- [ ] Run RV64D tests (9 tests)
- [ ] Run RV64C tests (1 test)
- [ ] Debug failures, iterate

**Day 19-20: Application Testing**
- [ ] Run FreeRTOS on RV64 (rebuild for RV64)
- [ ] Verify multitasking still works
- [ ] Run quick regression suite
- [ ] Create RV64-specific custom tests
- [ ] Update documentation

---

## Testing Strategy

### 1. Official RISC-V Compliance Tests

**RV64 Test Suite** (87 tests total):
```bash
# RV64I (48 tests)
env XLEN=64 ./tools/run_official_tests.sh rv64ui

# RV64M (8 tests)
env XLEN=64 ./tools/run_official_tests.sh rv64um

# RV64A (10 tests)
env XLEN=64 ./tools/run_official_tests.sh rv64ua

# RV64F (11 tests)
env XLEN=64 ./tools/run_official_tests.sh rv64uf

# RV64D (9 tests)
env XLEN=64 ./tools/run_official_tests.sh rv64ud

# RV64C (1 test)
env XLEN=64 ./tools/run_official_tests.sh rv64uc

# All tests
env XLEN=64 make test-all-official
```

**Expected Results**:
- RV64I: 48/48 (100%)
- RV64M: 8/8 (100%)
- RV64A: 10/10 (100%)
- RV64F: 11/11 (100%)
- RV64D: 9/9 (100%)
- RV64C: 1/1 (100%)
- **Total: 87/87 (100%)**

### 2. Custom Tests

**Create RV64-Specific Tests**:

**Test: `test_rv64_arithmetic.s`**
```assembly
# Test 64-bit arithmetic
li   a0, 0x123456789ABCDEF0
li   a1, 0x0FEDCBA987654321
add  a2, a0, a1              # 64-bit add
sub  a3, a0, a1              # 64-bit sub

# Test W instructions (32-bit with sign-extend)
li   a0, 0xFFFFFFFF80000000  # -2^31
li   a1, 0x0000000000000001
addw a2, a0, a1              # Should be 0xFFFFFFFF80000001
```

**Test: `test_rv64_memory.s`**
```assembly
# Test LD/SD/LWU
la   a0, test_data
ld   a1, 0(a0)               # Load doubleword
sd   a1, 8(a0)               # Store doubleword
lwu  a2, 0(a0)               # Load word unsigned (zero-extend)
```

**Test: `test_sv39_translation.s`**
```assembly
# Test 3-level page table walk
# Setup page tables for Sv39
# Enable paging (SATP.MODE = 8)
# Access virtual addresses
# Verify correct physical translation
```

### 3. Regression Testing

**Maintain RV32 Compatibility** (optional):
- Keep RV32 configuration option
- Run RV32 tests to ensure no regression
- Use XLEN parameter to switch between 32/64

**Quick Regression**:
```bash
env XLEN=64 make test-quick
```

### 4. FreeRTOS Validation

**Rebuild FreeRTOS for RV64**:
```bash
cd software/freertos
make clean
make XLEN=64 ARCH=rv64imafdc
```

**Run Tests**:
```bash
env XLEN=64 ./tools/test_freertos.sh
```

**Expected Behavior**:
- Tasks create and run
- Timer interrupts fire
- Context switching works
- UART output correct
- No crashes or corruption

---

## Risk Assessment

### High Risk

**1. Datapath Width Bugs**
- **Risk**: Missed 32-bit signals causing truncation
- **Mitigation**:
  - Systematic grep for all width specifications
  - Compile-time width checking with parameters
  - Test with large values (> 32-bit range)

**2. MMU Complexity**
- **Risk**: Sv39 3-level walk has more states, higher chance of bugs
- **Mitigation**:
  - Create detailed state diagrams before coding
  - Unit test each level separately
  - VCD waveform analysis for page walks

**3. Memory Expansion Simulation Time**
- **Risk**: 4MB DMEM may be too slow to simulate
- **Mitigation**:
  - Use sparse memory models (only allocate used blocks)
  - Optimize testbenches (reduce unnecessary cycles)
  - Consider hex file initialization instead of programmatic

### Medium Risk

**4. CSR Compatibility**
- **Risk**: Subtle CSR behavior differences between RV32/RV64
- **Mitigation**:
  - Carefully read RISC-V privileged spec sections
  - Test all CSR read/write combinations
  - Verify trap values, exception codes

**5. Tool Chain**
- **Risk**: Toolchain may not support RV64 well
- **Mitigation**:
  - Verify `riscv64-unknown-elf-gcc` works
  - Test compilation with RV64 target
  - Have fallback to build custom toolchain if needed

### Low Risk

**6. FreeRTOS Port**
- **Risk**: FreeRTOS may not support RV64
- **Mitigation**:
  - Official FreeRTOS has RV64 port
  - Minimal changes needed (recompile with XLEN=64)
  - Can fallback to RV32 if needed

---

## Success Criteria

### Must Have (Phase 3 Complete)
- ✅ **Compliance**: 87/87 RV64 official tests passing (100%)
- ✅ **Boot**: FreeRTOS boots on RV64 without errors
- ✅ **Multitasking**: Tasks run and switch correctly
- ✅ **MMU**: Sv39 page table walks successful
- ✅ **Memory**: LD/SD/LWU instructions work correctly
- ✅ **Regression**: No regressions in existing functionality

### Should Have
- ✅ **Performance**: Similar cycle count to RV32 (no major slowdown)
- ✅ **Documentation**: Updated architecture docs for RV64
- ✅ **Tests**: Custom RV64 test suite created
- ✅ **Clean Code**: No synthesis warnings, readable comments

### Nice to Have
- ⭐ **RV32/RV64 Dual Mode**: Configurable via parameter
- ⭐ **Stress Tests**: Large address space tests (> 4GB virtual)
- ⭐ **Benchmarks**: Performance comparison RV32 vs RV64

---

## Next Steps

### Immediate (This Session)
1. Review this plan with user
2. Get approval to proceed
3. Start Day 1 tasks (configuration & parameters)

### Short-Term (Week 1)
1. Complete core & decode changes
2. Run initial RV64I instruction tests
3. Debug and iterate

### Medium-Term (Week 2-3)
1. Complete memory & MMU changes
2. Run full compliance suite
3. Validate FreeRTOS on RV64

### Completion
1. Create `PHASE_3_COMPLETE.md` summary
2. Git commit and tag `phase-3-complete`
3. Update roadmap for Phase 4 (xv6-riscv)

---

**Ready to start Phase 3!** 🚀
