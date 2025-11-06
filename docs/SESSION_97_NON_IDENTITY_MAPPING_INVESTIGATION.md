# Session 97: Non-Identity Mapping Investigation & MMU Bug Discovery
**Date**: 2025-11-05
**Focus**: Debugging test_vm_non_identity_basic.s and investigating MMU behavior
**Status**: 🔧 **In Progress** - Test design fixed, MMU issue under investigation

## Session Goals
Continue Week 1 VM tests by debugging the non-identity mapping test created in Session 96.

## Investigation Summary

### Initial Problem
`test_vm_non_identity_basic.s` failed immediately with:
- Test appears to fail at stage 1 (x29=1)
- Test marker shows FAIL (x28=0xdeaddead)
- MMU TLB updates observed, suggesting paging was enabled
- Contradictory evidence: stage 1 failure but TLB activity seen

### Deep Debugging Process

#### Phase 1: SATP Investigation
**Initial Theory**: SATP is non-zero at startup, causing immediate test failure.

**Findings**:
- Register dump showed t0=0x80080002 (looks like SATP value!)
- CSR debug revealed SATP was actually **zero at startup**
- Test passed initial SATP check at cycle 3
- SATP written to 0x80080002 at cycle 57 (stage 4, as expected)

**Conclusion**: Initial theory was wrong - test progressed normally through stages 1-4.

#### Phase 2: Understanding x29=1 with TLB Activity
**Observation**: Final x29=1 despite evidence of reaching stage 4+.

**Key Discovery via CSR Debug**:
```
Cycle 3:  Read SATP at PC=0x80000004 (stage 1) ✓
Cycle 57: Write SATP=0x80080002 at PC=0x800000bc (stage 4) ✓
Cycle 60: Read SATP at PC=0x800000c4 (verify SATP) ✓
Cycle 83: Read SATP at PC=0x00000004 (WRONG - trap occurred!) ✗
```

**Root Cause of x29=1**:
1. Test executes normally through stages 1-5
2. Trap occurs after enabling paging
3. CPU jumps to PC=0 (mtvec not configured)
4. Memory masking causes PC=0 to read same physical memory as PC=0x80000000
5. CPU re-executes `li t4, 1` from start of test
6. x29 gets reset to 1!

**Conclusion**: x29=1 is a side effect of the trap, not the original failure point.

#### Phase 3: Root Cause - Test Design Flaw
**Critical Bug Found**: The original test had a fundamental design error.

**Original (Broken) Design**:
```
Code at:       PA 0x80000000-0x80000177
Page table:    VA 0x80000000 → PA 0x80003000 (non-identity)
```

**What Happened**:
1. Code executes from PA 0x80000000
2. Test enables paging with mapping VA 0x80000000 → PA 0x80003000
3. CPU fetches next instruction from VA 0x800000a8
4. MMU translates to PA 0x800030a8 (NO CODE THERE!)
5. Page fault / undefined instruction
6. Trap to PC=0

**The Fix**: Use TWO page table entries:
```
Entry 512: VA 0x80000000 → PA 0x80000000 (identity map for CODE)
Entry 576: VA 0x90000000 → PA 0x80003000 (non-identity map for DATA)
```

**Implementation**:
- Code continues executing from VA 0x80000xxx (identity mapped)
- Test accesses data through VA 0x90000000 (non-identity mapped to PA 0x80003000)
- This properly demonstrates non-identity translation

## Changes Made

### test_vm_non_identity_basic.s
**Updated test design**:
1. Changed VA_DATA from 0x80000000 to 0x90000000
2. Added identity mapping: Entry 512 (VA 0x80000000 → PA 0x80000000)
3. Added non-identity mapping: Entry 576 (VA 0x90000000 → PA 0x80003000)
4. Updated all test logic to access data through VA 0x90000000
5. Updated comments to reflect correct design

**Page Table Calculations**:
```
Entry 512 (Identity map for code):
  VPN[1] = 0x80000000 >> 22 = 0x200 = 512
  PPN = 0x80000000 >> 12 = 0x80000
  PTE = (0x80000 << 10) | 0xCF = 0x200000CF

Entry 576 (Non-identity map for data):
  VPN[1] = 0x90000000 >> 22 = 0x240 = 576
  PPN = 0x80003000 >> 12 = 0x80003
  PTE = (0x80003 << 10) | 0xCF = 0x20000CCF
```

## Current Status

### Test Behavior After Fix
**Good News**:
- MMU TLB updates correctly with VPN=0x00090000 (VA 0x90000000) ✓
- Page table entries verified correct in hex file ✓
- Identity mapping allows code to continue executing ✓

**Remaining Issue**:
- Test still fails with trap after enabling paging
- Same symptoms: trap → PC=0 → x29 reset to 1
- Now occurring when accessing VA 0x90000000 for data load

### Possible Causes Under Investigation
1. **Memory coherency**: SW to page table vs PTW reads
2. **TLB permission checking**: Bug in permission validation
3. **MMU debug print bug**: PPN shows 'X' values (bits [53:10] in RV32)
4. **Data memory access**: PTW reading from wrong memory?

### MMU Debug Output Analysis
```
MMU: TLB[0] updated: VPN=0x00090000, PPN=0xxxxxxX80003, PTE=0xcf
```

**Debug Print Bug Found**:
- Line 490 in mmu.v prints `ptw_pte_data[53:10]` for PPN
- RV32 only has 32-bit PTEs, bits [53:10] don't exist!
- Should print based on XLEN (bits [31:10] for RV32)
- This is a **cosmetic bug only** - actual TLB storage uses correct bits

**Actual TLB Storage** (line 480-483):
```verilog
if (MODE_SV32) begin
  tlb_ppn[tlb_replace_idx] <= {{10{1'b0}}, ptw_pte_data[31:10]};  // Correct!
end else begin
  tlb_ppn[tlb_replace_idx] <= {{20{1'b0}}, ptw_pte_data[53:10]};
end
```

## Test Progress
- **Phase 4 Prep Progress**: 7/44 tests (15.9%)
- **Week 1 Progress**: 7/10 tests (70%)
- **Tests This Session**: 0 new passing tests (debug/investigation only)

## Next Steps
1. **Immediate**: Debug why VA 0x90000000 access causes trap
   - Add detailed MMU/TLB debug output
   - Verify PTW reads correct page table data
   - Check permission validation logic
   - Verify memory coherency (SW → PTW)

2. **Quick Win**: Fix MMU debug print cosmetic bug
   - Change line 490 to print correct PPN bits based on XLEN

3. **Alternative Approach**: Simplify test
   - Create minimal test: identity map + one non-identity load
   - Reduce variables to isolate root cause

## Technical Insights

### Key Learning: Paging and Code Execution
**Critical Requirement**: When enabling paging, the page table MUST include a valid mapping for the **currently executing code location**.

**Why**: After writing SATP, the very next instruction fetch is translated through the MMU. If that VA isn't mapped, immediate page fault occurs.

**Solutions**:
1. Identity map code region before enabling paging
2. Place trap handler at mapped location
3. Jump to mapped location after enabling SATP

### Debugging Techniques Used
1. **CSR Debug Tracing**: Tracked SATP reads/writes through execution
2. **Cycle-by-Cycle Analysis**: Pinpointed exact cycle of trap
3. **Disassembly Cross-Reference**: Verified PC values against code
4. **Hex File Validation**: Confirmed page table data in memory image
5. **Register Archaeology**: Analyzed final register state for clues

## Files Modified
- `tests/asm/test_vm_non_identity_basic.s` - Fixed test design with dual mappings

## Git Status
- **Branch**: main
- **Changes**: Modified test file, investigation ongoing
- **Commit Status**: Pending (test still failing, investigation incomplete)
