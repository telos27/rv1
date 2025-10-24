# MMU (Memory Management Unit) Design Document

## Overview

The MMU module implements RISC-V virtual memory translation with TLB caching. It supports:
- **Sv32** (RV32): 2-level page table, 4KB pages
- **Sv39** (RV64): 3-level page table, 4KB pages
- Hardware TLB with configurable size
- Page fault detection
- Permission checking (R/W/X, U/S mode)

## Features

### Supported Translation Modes
- **Bare mode**: No translation (physical = virtual)
- **Sv32**: 32-bit virtual addresses, 34-bit physical addresses
- **Sv39**: 39-bit virtual addresses, 56-bit physical addresses

### TLB (Translation Lookaside Buffer)
- Configurable number of entries (default: 16)
- Fully associative
- Round-robin replacement policy
- Support for TLB flush (all entries or specific address)
- Caches VPN, PPN, and PTE flags

### Page Table Walk
- Hardware page table walker
- Multi-cycle operation (3 cycles for Sv39, 2 cycles for Sv32)
- Automatic PTE fetching from memory
- Validates PTE structure and permissions
- Updates TLB on successful translation

### Permission Checking
- Read/Write/Execute permissions
- User/Supervisor mode access control
- Support for MSTATUS.SUM (Supervisor User Memory access)
- Support for MSTATUS.MXR (Make eXecutable Readable)
- Page fault generation on permission violations

## Architecture

### Block Diagram

```
                    ┌─────────────────────────────────┐
                    │         MMU Module              │
                    │                                 │
  Virtual Address   │  ┌──────────┐   ┌───────────┐  │  Physical Address
  ────────────────────►│   TLB    │──►│ Permission│──┼────────────────►
                    │  │  Lookup  │   │   Check   │  │
  CSR (SATP, etc)   │  └──────────┘   └───────────┘  │
  ────────────────────►       │              │        │
                    │         │ miss         │ fault  │  Page Fault
                    │         ▼              ▼        ├────────────────►
                    │  ┌──────────────────────────┐  │
                    │  │  Page Table Walker (PTW) │  │
                    │  │  - State Machine         │  │
                    │  │  - PTE Fetch Logic       │  │
                    │  │  - Level Tracking        │  │
                    │  └──────────┬───────────────┘  │
                    │             │                   │
                    │             │ Memory Request    │
                    │             ▼                   │
                    └─────────────┼───────────────────┘
                                  │
                                  ▼
                            Memory Interface
```

### State Machine

The MMU operates with the following states:

1. **PTW_IDLE**: Waiting for translation request
2. **PTW_LEVEL_2**: Fetching level 2 PTE (Sv39 only)
3. **PTW_LEVEL_1**: Fetching level 1 PTE
4. **PTW_LEVEL_0**: Fetching level 0 PTE
5. **PTW_UPDATE_TLB**: Update TLB with new translation
6. **PTW_FAULT**: Page fault detected

### Translation Process

```
Start
  │
  ├─► Bare Mode? ──Yes──► Direct Mapping ──► Done
  │      │
  │      No
  │      │
  ├─► TLB Hit? ──Yes──► Check Permissions ──► Pass? ──Yes──► Done
  │      │                     │                  │
  │      No                    │                  No
  │      │                     │                  │
  │      ▼                     ▼                  ▼
  ├─► Start PTW          Page Fault         Page Fault
  │      │
  │      ├─► Fetch PTE at each level
  │      │    (Level 2 → 1 → 0 for Sv39)
  │      │    (Level 1 → 0 for Sv32)
  │      │
  │      ├─► Leaf PTE found?
  │      │         │
  │      │         ├─Yes──► Check Permissions ──► Pass?
  │      │         │              │                  │
  │      │         │              │                Yes
  │      │         │              │                  │
  │      │         │              │                  ▼
  │      │         │              │            Update TLB ──► Done
  │      │         │              │
  │      │         │              No
  │      │         │              │
  │      │         │              ▼
  │      │         │         Page Fault
  │      │         │
  │      │         └─No──► Non-leaf at Level 0? ──Yes──► Page Fault
  │      │                        │
  │      │                        No
  │      │                        │
  │      └────────────────────────┴─► Next Level
  │
Done
```

## Interface

### Parameters
- `XLEN`: Register width (32 or 64)
- `TLB_ENTRIES`: Number of TLB entries (default: 16)

### Ports

#### Translation Request Interface
| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `req_valid` | Input | 1 | Translation request valid |
| `req_vaddr` | Input | XLEN | Virtual address to translate |
| `req_is_store` | Input | 1 | 1=store, 0=load |
| `req_is_fetch` | Input | 1 | 1=instruction fetch, 0=data access |
| `req_size` | Input | 3 | Access size (0=byte, 1=half, 2=word, 3=double) |
| `req_ready` | Output | 1 | Translation complete |
| `req_paddr` | Output | XLEN | Physical address (translated) |
| `req_page_fault` | Output | 1 | Page fault exception |
| `req_fault_vaddr` | Output | XLEN | Faulting virtual address |

#### Memory Interface (Page Table Walk)
| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `ptw_req_valid` | Output | 1 | Page table walk memory request |
| `ptw_req_addr` | Output | XLEN | Physical address for PTW |
| `ptw_req_ready` | Input | 1 | Memory ready |
| `ptw_resp_data` | Input | XLEN | Page table entry data |
| `ptw_resp_valid` | Input | 1 | Response valid |

#### CSR Interface
| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `satp` | Input | XLEN | SATP register (page table base + mode) |
| `privilege_mode` | Input | 2 | Current privilege mode (0=U, 1=S, 3=M) |
| `mstatus_sum` | Input | 1 | Supervisor User Memory access |
| `mstatus_mxr` | Input | 1 | Make eXecutable Readable |

#### TLB Control
| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `tlb_flush_all` | Input | 1 | Flush entire TLB |
| `tlb_flush_vaddr` | Input | 1 | Flush specific virtual address |
| `tlb_flush_addr` | Input | XLEN | Address to flush (if tlb_flush_vaddr) |

## RISC-V Virtual Memory Specification

### SATP Register Format

#### Sv32 (RV32)
```
[31]      MODE (1 bit): 0=Bare, 1=Sv32
[30:22]   ASID (9 bits): Address Space ID (not implemented)
[21:0]    PPN (22 bits): Physical Page Number of root page table
```

#### Sv39 (RV64)
```
[63:60]   MODE (4 bits): 0=Bare, 8=Sv39
[59:44]   ASID (16 bits): Address Space ID (not implemented)
[43:0]    PPN (44 bits): Physical Page Number of root page table
```

### Page Table Entry (PTE) Format

```
[XLEN-1:10]  PPN: Physical Page Number
[9:8]        RSW: Reserved for software (ignored)
[7]          D: Dirty (written by hardware)
[6]          A: Accessed (written by hardware)
[5]          G: Global mapping
[4]          U: User accessible
[3]          X: Executable
[2]          W: Writable
[1]          R: Readable
[0]          V: Valid
```

### Virtual Address Format

#### Sv32 (32-bit VA)
```
[31:22]  VPN[1] (10 bits): Level 1 page table index
[21:12]  VPN[0] (10 bits): Level 0 page table index
[11:0]   Offset (12 bits): Page offset (4KB page)
```

#### Sv39 (39-bit VA)
```
[38:30]  VPN[2] (9 bits): Level 2 page table index
[29:21]  VPN[1] (9 bits): Level 1 page table index
[20:12]  VPN[0] (9 bits): Level 0 page table index
[11:0]   Offset (12 bits): Page offset (4KB page)
```

### Permission Checking Rules

1. **Valid bit (V)**: Must be 1, otherwise page fault
2. **Leaf PTE**: At least one of R, W, X must be set
3. **Write permission**: W=1 requires R=1, otherwise page fault
4. **User mode access**:
   - If U=0 and privilege=User, page fault
   - If U=1 and privilege=Supervisor and SUM=0, page fault
5. **Access type**:
   - Instruction fetch: Requires X=1
   - Load: Requires R=1 or (X=1 and MXR=1)
   - Store: Requires W=1

## Integration with CPU Core

### Connection to Pipeline

The MMU should be integrated in the **Memory (MEM)** stage of the pipeline:

```
┌──────────────────────────────────────────────────────┐
│                   Pipeline Stages                    │
│                                                      │
│  IF  ──► ID ──► EX ──► MEM ──► WB                  │
│                         │                            │
│                         ▼                            │
│                   ┌──────────┐                       │
│                   │   MMU    │                       │
│                   └────┬─────┘                       │
│                        │                             │
│                        ▼                             │
│                  Memory System                       │
└──────────────────────────────────────────────────────┘
```

### CSR Integration

The MMU requires access to:
- **SATP** (0x180): Supervisor address translation and protection
- **MSTATUS.SUM** (bit 18): Supervisor User Memory access
- **MSTATUS.MXR** (bit 19): Make eXecutable Readable

### Exception Handling

Page faults should trigger exceptions:
- **Instruction Page Fault** (cause = 12): `req_is_fetch=1`
- **Load Page Fault** (cause = 13): `req_is_store=0, req_is_fetch=0`
- **Store Page Fault** (cause = 15): `req_is_store=1`

The faulting virtual address should be saved to MTVAL.

## Performance Considerations

### TLB Hit Rate
- Typical hit rate: 95-99% for most workloads
- 16-entry TLB provides good balance between size and performance
- Larger TLB (32-64 entries) may improve performance for large working sets

### Page Table Walk Latency
- **Sv32**: 2 memory accesses (levels 1, 0)
- **Sv39**: 3 memory accesses (levels 2, 1, 0)
- Each memory access: depends on memory system (typically 1-10 cycles)

### Optimization Opportunities
1. **Larger TLB**: Increase TLB_ENTRIES parameter
2. **Superpage support**: Implement large page support (2MB, 1GB)
3. **Page table caching**: Cache intermediate PTEs
4. **Hardware page table walker**: Parallelize PTE fetches

## Testing

### Test Scenarios

1. **Bare Mode**: Verify direct mapping
2. **TLB Hit**: Verify cached translations
3. **TLB Miss**: Verify page table walk
4. **Page Fault**: Verify invalid PTE detection
5. **Permission Check**: Verify R/W/X/U permissions
6. **TLB Flush**: Verify flush operations
7. **Privilege Modes**: Verify user/supervisor access

### Testbench

See `tb/tb_mmu.v` for a comprehensive testbench covering all scenarios.

## Future Enhancements

### Planned Features
1. **ASID Support**: Address Space Identifier for TLB
2. **Superpage Support**: 2MB and 1GB pages
3. **Sv48 Support**: 4-level page tables for RV64
4. **Hardware A/D Bits**: Automatic Accessed/Dirty bit updates
5. **Page Table Caching**: Cache intermediate page table entries

### Performance Improvements
1. **Prefetching**: Prefetch adjacent page table entries
2. **Parallel Walks**: Support multiple concurrent translations
3. **Write Combining**: Combine multiple TLB updates

## References

- RISC-V Privileged Architecture Specification (Chapter 4: Supervisor-Level ISA)
- RISC-V Instruction Set Manual Volume II: Privileged Architecture
- https://riscv.org/technical/specifications/

## Revision History

| Version | Date | Author | Description |
|---------|------|--------|-------------|
| 1.0 | 2025-10-11 | RV1 Project | Initial MMU design |
