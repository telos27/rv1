# Session 98: Non-Identity Mapping - MMU Megapage Alignment Understanding & 2-Level Page Table Fix
**Date**: 2025-11-05
**Focus**: Debugging test_vm_non_identity_basic, understanding MMU megapage behavior, implementing 2-level page tables
**Status**: 🔧 **In Progress** - MMU working correctly, test has memory aliasing issue to debug

## Session Goals
Continue from Session 97 non-identity mapping investigation and fix the root cause of test failure.

## Major Discovery: MMU Was NOT Buggy!

### The Revelation
Session 97 concluded that the MMU had a bug where translation was enabled when it shouldn't be. However, detailed analysis in Session 98 revealed:

**The MMU was working PERFECTLY** - it was correctly enforcing RISC-V specification requirements for superpage alignment!

### Root Cause Analysis

**Original Test Design (BROKEN)**:
```assembly
# Attempted mapping: VA 0x90000000 → PA 0x80003000 (4MB megapage, level 1)
.word 0x20000CCF    # PTE with PPN=0x80003
```

**What Actually Happened**:
1. Test created a **level 1 (megapage)** PTE for VA 0x90000000
2. Megapages in Sv32 are **4MB** in size (0x400000 bytes)
3. RISC-V spec requires megapage PA to be **4MB-aligned**
4. PA 0x80003000 is **NOT** 4MB-aligned (only 12KB into a 4MB region)
5. MMU correctly used only the aligned portion: PPN[1] (bits [19:10])
6. Result: VA 0x90000000 → PA **0x80000000** (correctly aligned to 4MB boundary)

**Debug Evidence**:
```
MMU: TLB HIT - VA=0x90000000 -> PA=0x80000000 (PPN=0x00080003, level=1)
```

The MMU was doing **exactly** what it should - aligning the megapage to 4MB!

### The construct_pa() Function (CORRECT)

```verilog
// Line 283 in mmu.v - Level 1 (4MB megapage)
1: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:10], vaddr[PAGE_SHIFT+9:0]};
```

For XLEN=32, PAGE_SHIFT=12:
- `ppn[19:10]` = PPN[1] = top 10 bits (4MB-aligned portion)
- `vaddr[21:0]` = VA offset within 4MB page

This is **correct** according to RISC-V spec! Lower bits of PPN are ignored for superpages.

## The Solution: 2-Level Page Tables

To map VA 0x90000000 to an arbitrary PA (not 4MB-aligned), we need **4KB granularity**, which requires a **2-level page table walk**.

### New Page Table Structure

```
L1 Entry 512: VA 0x80000000 → PA 0x80000000 (megapage, identity map for code)
  - Leaf PTE (R|W|X set)
  - PPN = 0x80000
  - Flags = 0xCF

L1 Entry 576: Pointer to L2 page table (for VA 0x90000000-0x903FFFFF)
  - Non-leaf PTE (only V bit set)
  - PPN = page_table_l2 >> 12
  - Flags = 0x01

L2 Entry 0: VA 0x90000000 → PA test_data_area (4KB page, level 0)
  - Leaf PTE (R|W|X set)
  - PPN = test_data_area >> 12
  - Flags = 0xCF
```

### Page Table Calculations

**L1 Entry 512 (Identity megapage for code)**:
```
VPN[1] = 0x80000000 >> 22 = 0x200 = 512
PPN = 0x80000000 >> 12 = 0x80000
PTE = (0x80000 << 10) | 0xCF = 0x200000CF
```

**L1 Entry 576 (Pointer to L2)**:
```
VPN[1] = 0x90000000 >> 22 = 0x240 = 576
PPN = page_table_l2 >> 12 (dynamic)
PTE = (PPN << 10) | 0x01
```

**L2 Entry 0 (4KB leaf page)**:
```
VPN[0] = (0x90000000 >> 12) & 0x3FF = 0x000 = 0
PPN = test_data_area >> 12 (dynamic)
PTE = (PPN << 10) | 0xCF
```

## Implementation Changes

### 1. Test Code Changes (test_vm_non_identity_basic.s)

**Dynamic Address Calculation**:
```assembly
# OLD (broken): Hardcoded physical address
.equ PA_DATA, 0x80003000

# NEW (correct): Dynamic address calculation
la      t0, test_data_area   # Get actual PA
la      s1, test_data_area   # Save for later use
```

**2-Level Page Table Setup**:
```assembly
# L1 Entry 512: Identity megapage for code
li      t1, 0x200000CF
li      t2, 2048
add     t2, t0, t2
sw      t1, 0(t2)

# L1 Entry 576: Pointer to L2 table
srli    t4, t3, 12           # PPN of L2 table
slli    t1, t4, 10
ori     t1, t1, 0x01         # Only V bit (non-leaf)
li      t2, 2304
add     t2, t0, t2
sw      t1, 0(t2)

# L2 Entry 0: Fine-grained 4KB mapping
srli    t4, s1, 12           # PPN of test_data_area
slli    t1, t4, 10
ori     t1, t1, 0xCF         # RWX flags (leaf)
sw      t1, 0(t3)
```

**Data Section**:
```assembly
.align 12
page_table_l1:
    .fill 1024, 4, 0x00000000   # 4KB L1 table

page_table_l2:
    .fill 16, 4, 0x00000000     # 64 bytes L2 table (minimal)

.align 12
test_data_area:
    .word 0x00000000            # Test data
    .word 0x00000000
```

### 2. Linker Script Changes (tests/linker.ld)

```diff
- DMEM (rw)  : ORIGIN = 0x00001000, LENGTH = 4K
+ DMEM (rw)  : ORIGIN = 0x00001000, LENGTH = 12K
```

**Reason**: Need space for:
- L1 page table: 4KB
- L2 page table: 64 bytes
- Test data: aligned to 4KB
- Total: ~8KB

### 3. RTL Changes (rtl/core/mmu.v)

**Added debug output (temporary, removed at end of session)**:
- Translation enabled signal monitoring
- TLB hit address translation verification
- Confirmed MMU was working correctly all along!

## Verification Results

### MMU Translation: ✅ WORKING PERFECTLY

```
MMU: TLB[0] updated: VPN=0x00090000, PPN=0xxxxxxX80003, PTE=0xcf
MMU: TLB HIT - VA=0x90000000 -> PA=0x80003000 (PPN=0x00080003, level=0)
MMU: TLB HIT - VA=0x90000004 -> PA=0x80003004 (PPN=0x00080003, level=0)
```

**Perfect!** VA 0x90000000 now translates to PA 0x80003000 with 4KB granularity (level=0).

### Test Execution

**Cycle Count**: 100 cycles
**Instructions**: 81
**CPI**: 1.235

**Register Values**:
```
s0 = 0x80080001  (SATP value)
s1 = 0x80003000  (PA of test_data_area)
t1 = 0xcafebabe  (read from VA 0x90000000)
t2 = 0xcafebabe  (should be 0xdeadc0de from VA 0x90000004!)
x29 = 1          (stage marker - indicates failure)
x28 = 0xdeaddead (failure marker)
```

## Current Issue: Memory Aliasing Bug 🐛

### Problem
Reading from offset +4 returns the same value as offset +0:

```
Write PA 0x80003000+0: 0xCAFEBABE ✓
Write PA 0x80003000+4: 0xDEADC0DE (supposedly)
Read  VA 0x90000000+0 → PA 0x80003000: 0xCAFEBABE ✓
Read  VA 0x90000004+4 → PA 0x80003004: 0xCAFEBABE ✗ (should be 0xDEADC0DE)
```

### MMU is Correct
The MMU correctly translates:
- VA 0x90000000 → PA 0x80003000
- VA 0x90000004 → PA 0x80003004

### Possible Causes
1. **Memory write failure**: SW to PA+4 didn't execute correctly
2. **Memory aliasing**: Data memory has addressing bug that aliases +4 to +0
3. **Test data overlap**: test_data_area overlaps with page tables or other data
4. **Bus adapter issue**: dmem_bus_adapter has offset calculation bug

### Next Session Actions
1. Add memory write/read debug to data_memory.v
2. Verify test_data_area doesn't overlap with page tables
3. Check if offset +4 writes are actually reaching memory
4. Examine dmem_bus_adapter address calculation
5. Try writing different test patterns to isolate the issue

## Technical Insights

### RISC-V Superpage Alignment Requirements

**Key Learning**: RISC-V superpages MUST be aligned to their size:
- 4KB pages (level 0): No alignment restriction beyond 4KB
- 4MB megapages (Sv32 level 1): **Must be 4MB-aligned**
- 2MB megapages (Sv39 level 1): **Must be 2MB-aligned**
- 1GB gigapages (Sv39 level 2): **Must be 1GB-aligned**

The MMU hardware enforces this by:
1. Ignoring lower bits of PPN for superpages
2. Using VA offset bits to reconstruct the full PA
3. Automatically aligning to the correct boundary

### When to Use 2-Level vs 1-Level Page Tables

**1-Level (Megapages only)**:
- ✅ Simple, fast single-level lookup
- ✅ Works for large aligned regions (code, heap)
- ❌ Cannot map arbitrary addresses
- ❌ 4MB granularity only

**2-Level (4KB pages)**:
- ✅ Can map any 4KB-aligned address
- ✅ Fine-grained control
- ❌ Slower (two memory accesses for PTW)
- ❌ More memory overhead

### Test Design Best Practices

**Always Use Dynamic Addresses**:
```assembly
# BAD: Hardcoded absolute address
.equ PA_DATA, 0x80003000
li t0, PA_DATA

# GOOD: Dynamic address calculation
la t0, test_data_area
```

**Why**: Tests may run at different base addresses (0x00000000 vs 0x80000000), and linker may place data sections at different offsets.

## Progress Update

### Week 1 Status: 7/10 Tests (70%)

**Passing Tests** (unchanged):
1. ✅ test_satp_reset
2. ✅ test_smode_entry_minimal
3. ✅ test_vm_sum_simple
4. ✅ test_vm_identity_basic
5. ✅ test_vm_identity_multi
6. ✅ test_mxr_basic
7. ✅ test_sum_mxr_csr

**Blocked**:
8. ⚠️ test_vm_non_identity_basic - **Memory aliasing bug blocks progress**

**Remaining**:
9-10. TBD (pending non-identity test fix)

### Overall Phase 4 Prep: 7/44 Tests (15.9%)
**Status**: Blocked by memory aliasing issue in test_vm_non_identity_basic

## Files Modified

### Test Files
- `tests/asm/test_vm_non_identity_basic.s` - Complete rewrite with 2-level page tables and dynamic addressing

### Build Infrastructure
- `tests/linker.ld` - Increased DMEM from 4KB to 12KB for page table space

### RTL (Temporary Debug)
- `rtl/core/mmu.v` - Added then removed debug output

## Git Status
- **Branch**: main
- **Changes**: Test redesign complete, linker script updated, debug output removed
- **Commit Status**: Ready to commit (test failing due to separate memory issue)

## Key Learnings

1. **Always Verify Assumptions**: The "MMU bug" was actually correct behavior enforcing RISC-V spec
2. **Understand Superpage Alignment**: Megapages must be aligned to their size
3. **Use 2-Level Page Tables for Fine Control**: 4KB pages allow arbitrary address mapping
4. **Dynamic > Static Addresses**: Tests should use `la` not hardcoded addresses
5. **Debug Output is Essential**: Without MMU debug, would never have understood alignment behavior

## Next Session Priorities

1. **Fix memory aliasing bug** - Highest priority blocker
2. **Complete test_vm_non_identity_basic** - Verify non-identity mapping works
3. **Continue Week 1 tests** - Move to remaining 2 tests after fix
4. **Document megapage alignment** - Add to architecture docs for future reference

## Conclusion

This session revealed a fundamental misunderstanding from Session 97. The MMU was never buggy - it was correctly implementing RISC-V superpage alignment. The real issue was the test design using megapages for non-aligned addresses.

The fix (2-level page tables with 4KB granularity) is the correct solution and demonstrates proper OS-level page table management. The MMU translation now works perfectly.

The remaining memory aliasing issue is unrelated to the MMU and will be debugged in the next session. This is likely a simple bug in the test or memory subsystem, not a fundamental design flaw.

**Major Win**: Deep understanding of RISC-V superpage alignment and proper 2-level page table implementation! 🚀
