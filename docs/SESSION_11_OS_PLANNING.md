# Session 11: OS Integration Planning - Complete Roadmap

**Date**: 2025-10-26
**Focus**: Planning FreeRTOS → xv6 → Linux progression
**Status**: ✅ Planning Complete, Ready for Implementation

---

## Session Summary

This session established a comprehensive plan for taking the RV1 CPU from 100% ISA compliance to running full-featured operating systems. The plan spans 16-24 weeks and includes 5 major phases.

---

## Deliverables Created

### 1. OS Integration Plan (`docs/OS_INTEGRATION_PLAN.md`)
**Size**: ~1100 lines
**Content**:
- Complete 5-phase roadmap (FreeRTOS → xv6 → Linux)
- Detailed implementation plans for each phase
- Hardware specifications (CLINT, UART, PLIC, block storage)
- Software integration guides (OpenSBI, U-Boot, kernel configs)
- Testing & validation strategies
- Timeline estimates (16-24 weeks total)

**Key Sections**:
- Phase 1: RV32 Interrupt Infrastructure (CLINT + UART)
- Phase 2: FreeRTOS on RV32
- Phase 3: RV64 Upgrade (Sv39 MMU)
- Phase 4: xv6-riscv (Unix-like OS)
- Phase 5a: Linux nommu (optional, embedded)
- Phase 5b: Linux with MMU (full-featured)

### 2. Memory Map Documentation (`docs/MEMORY_MAP.md`)
**Size**: ~700 lines
**Content**:
- Complete SoC memory map (current + future)
- Detailed register maps for all peripherals
- CLINT specification (MTIME, MTIMECMP, MSIP)
- UART 16550 register descriptions
- PLIC specification (for Phase 4+)
- Address decode logic
- Memory access permissions (M/S/U modes)
- QEMU/SiFive compatibility notes

**Memory Map Summary**:
```
0x0000_0000: Instruction RAM (64KB)      [Phase 1]
0x0200_0000: CLINT (64KB)                [Phase 1 - To implement]
0x0C00_0000: PLIC (64MB)                 [Phase 4]
0x1000_0000: UART (4KB)                  [Phase 1 - To implement]
0x8000_0000: System RAM (5MB)            [Phase 3 - Expand]
0x8800_0000: Block Device (16MB)         [Phase 4]
0x9000_0000: Ethernet (optional)         [Phase 5]
0x9100_0000: GPIO (optional)             [Phase 5]
```

### 3. Project Structure Created
**New Directories**:
```
rtl/peripherals/       - Hardware peripheral modules
software/freertos/     - FreeRTOS port
software/device-tree/  - Device tree sources
docs/os-integration/   - OS-specific documentation
```

### 4. Updated Main Documentation
**File**: `CLAUDE.md`
- Added OS Integration Roadmap section
- Updated "Current Status" with Session 11 work
- Updated "Future Enhancements" to prioritize OS work
- Reflected "Next Phase" as interrupt infrastructure

---

## Strategic Decisions Made

### 1. Architecture Progression
**Decision**: Start RV32, upgrade to RV64 for xv6/Linux
**Rationale**:
- RV32 sufficient for FreeRTOS and nommu Linux
- Educational value in supporting both architectures
- RV64 required for standard xv6-riscv and modern Linux
- Demonstrates CPU configurability (XLEN parameter)

### 2. Peripheral Strategy
**Decision**: Minimal peripherals, add incrementally
**Rationale**:
- Start with CLINT + UART (required for all OSes)
- Add PLIC only when needed (Phase 4 - xv6)
- Defer storage decision (RAM disk initially, SD later if needed)
- Optional peripherals (Ethernet, GPIO) only if time permits

### 3. Boot Flow
**Decision**: OpenSBI + U-Boot (industry standard)
**Rationale**:
- OpenSBI provides standard SBI interface for S-mode OS
- U-Boot enables flexible boot configurations
- Both are production-ready, well-documented
- Maximum compatibility with standard Linux distributions

### 4. Linux Approach
**Decision**: Optional nommu (RV32), focus on MMU version (RV64)
**Rationale**:
- nommu Linux educational but not essential
- MMU-based Linux is the main goal
- nommu can be revisited if embedded use cases emerge

---

## Technical Architecture

### Phase 1: Interrupt Infrastructure (Critical Path)

**Problem**: Current CPU has no interrupt injection mechanism
- CSRs (`mip`, `mie`, `mtvec`) exist but no external interrupts
- Privilege Phase 3 tests (6 tests) are skipped for this reason
- Blocks all OS work (context switching requires timer interrupts)

**Solution**: Implement CLINT + UART

#### CLINT (Core-Local Interruptor)
**Functionality**:
- **MTIME**: 64-bit counter, increments every cycle
- **MTIMECMP**: 64-bit compare, triggers timer interrupt when MTIME ≥ MTIMECMP
- **MSIP**: Software interrupt bit (for IPI in multi-core)

**Memory Map**:
```
0x0200_0000: MSIP (Machine Software Interrupt Pending)
0x0200_4000: MTIMECMP (64-bit compare value)
0x0200_BFF8: MTIME (64-bit time counter)
```

**Integration**:
- Connect `mti_o` → core `mip[7]` (machine timer interrupt)
- Connect `msi_o` → core `mip[3]` (machine software interrupt)
- Memory-mapped via SoC address decoder

#### UART (16550-Compatible)
**Functionality**:
- TX/RX with 16-byte FIFOs (or 1-byte to start)
- Line status register (data ready, TX empty)
- Interrupt generation (RX data available, TX empty)

**Memory Map**:
```
0x1000_0000: RBR/THR (Receive/Transmit buffer)
0x1000_0001: IER (Interrupt Enable Register)
0x1000_0005: LSR (Line Status Register)
...
```

**Configuration**:
- 115200 baud, 8N1 (8 data, no parity, 1 stop)
- Fixed baud (no divisor latch for simplicity)

#### SoC Integration Module
**Module**: `rtl/rv_soc.v`
**Purpose**: Top-level integration of core + memory + peripherals

**Components**:
1. Core instance (`rv_core_pipelined`)
2. Instruction RAM (64KB)
3. Data RAM (64KB)
4. CLINT instance
5. UART instance
6. Address decoder (routes memory requests to devices)
7. Interrupt aggregator (collects device IRQs to core)

---

## Phase Milestones

### Phase 1 Milestone ✅
- [ ] CLINT implemented and tested
- [ ] UART implemented and tested
- [ ] SoC integration complete
- [ ] 6 interrupt tests written and passing
- [ ] All 34/34 privilege tests passing (100%)
- [ ] No regressions (208 total tests still pass)

### Phase 2 Milestone ✅
- [ ] FreeRTOS ported to RV32IMAFDC
- [ ] Context switch working (timer ISR → scheduler)
- [ ] Multiple tasks running concurrently
- [ ] Queue/semaphore IPC working
- [ ] Stable operation (1+ hours without hang)

### Phase 3 Milestone ✅
- [ ] XLEN changed to 64 bits
- [ ] RV64IMAFDC compliance (87/87 tests passing)
- [ ] MMU upgraded to Sv39 (3-level page tables)
- [ ] Memory expanded (1MB IMEM, 4MB DMEM)
- [ ] FreeRTOS still works on RV64

### Phase 4 Milestone ✅
- [ ] PLIC implemented and tested
- [ ] Block storage working (RAM disk)
- [ ] OpenSBI firmware integrated
- [ ] xv6 kernel boots
- [ ] Shell prompt appears: `$ `
- [ ] User programs run (`ls`, `cat`, `grep`)
- [ ] `usertests` passes (20+ tests)

### Phase 5a Milestone ✅ (Optional)
- [ ] Linux nommu kernel builds
- [ ] Buildroot rootfs created
- [ ] Kernel boots to shell
- [ ] Basic commands work

### Phase 5b Milestone ✅
- [ ] Linux kernel with MMU builds
- [ ] Device tree compiled
- [ ] U-Boot integrated
- [ ] Full boot chain works (OpenSBI → U-Boot → Linux)
- [ ] Login prompt or shell
- [ ] Filesystem persistent (ext2 on RAM disk)
- [ ] Stress tests pass (CPU, memory, I/O)

---

## Implementation Plan for Phase 1

### Week 1: CLINT Implementation
**Days 1-2**: Design & implement CLINT module
- Define register interface
- Implement MTIME counter (64-bit, increments every cycle)
- Implement MTIMECMP comparator (trigger interrupt when MTIME ≥ MTIMECMP)
- Implement MSIP register (software interrupt)
- Create memory-mapped interface

**Days 3-4**: CLINT testbench
- Unit test: Write testbench `tb/peripherals/tb_clint.v`
- Test MTIME increments
- Test MTIMECMP triggers MTI
- Test MSIP triggers MSI
- Waveform verification

**Day 5**: CLINT documentation
- Register map in MEMORY_MAP.md (already done ✅)
- Integration guide
- Example assembly code

### Week 2: UART Implementation
**Days 1-3**: Design & implement UART module
- 16550-compatible register set
- TX shift register + baud rate generator
- RX shift register + data sampling
- Line status register (DR, THRE, TEMT)
- Interrupt generation logic

**Days 4-5**: UART testbench
- Unit test: `tb/peripherals/tb_uart.v`
- TX test: Write byte, observe serial output
- RX test: Send serial input, read byte
- Timing verification (115200 baud)
- Echo test (RX → TX loopback)

### Week 3: SoC Integration & Testing
**Days 1-2**: SoC module
- Create `rtl/rv_soc.v`
- Instantiate core, CLINT, UART, RAMs
- Implement address decoder
- Wire interrupt signals

**Days 3-5**: Integration testing
- Assembly program: Timer interrupt test
- Assembly program: UART print test
- Combined test: Timer fires, prints via UART

### Week 3-4: Privilege Phase 3 Tests
**6 tests to implement**:
1. `test_interrupt_enable_disable.s` - MIE/SIE control
2. `test_interrupt_delegation.s` - mideleg M→S
3. `test_interrupt_pending.s` - mip/sip registers
4. `test_timer_interrupt.s` - Basic timer delivery
5. `test_nested_interrupts.s` - Interrupt during ISR
6. `test_interrupt_priority.s` - Exception vs interrupt priority

**Validation**:
- Run `make test-quick` → should still pass (14/14)
- Run full privilege test suite → should be 34/34 ✅
- Run full compliance → should still be 208/208 ✅

---

## Questions Answered During Planning

### Q1: RV32 or RV64?
**Answer**: Both - start RV32, upgrade to RV64
- RV32 for FreeRTOS and nommu Linux (simpler, smaller memory)
- RV64 for xv6 and MMU Linux (required for standard tools)
- Demonstrates CPU flexibility

### Q2: Which peripherals?
**Answer**: Start minimal (CLINT + UART), add as needed
- CLINT + UART: Phase 1 (required)
- PLIC + Block: Phase 4 (for xv6)
- Ethernet/GPIO: Phase 5 (optional)

### Q3: nommu Linux priority?
**Answer**: Optional - main focus is MMU version
- nommu educational but not critical
- Time better spent on xv6 → Linux MMU path
- Can revisit if embedded use cases emerge

### Q4: Boot flow?
**Answer**: OpenSBI + U-Boot (industry standard)
- Maximum compatibility
- Standard SBI interface
- Flexible boot options
- Well-documented

### Q5: Block storage?
**Answer**: Defer decision - start RAM disk
- RAM disk sufficient for initial bringup
- Simple (50 lines of Verilog)
- Can migrate to SD card later if persistence needed

---

## Risk Assessment

### Technical Risks

**Risk 1**: Interrupt timing issues
- **Likelihood**: Medium
- **Impact**: High (blocks all OS work)
- **Mitigation**: Thorough testbenches, waveform analysis, privilege tests
- **Fallback**: Consult RISC-V spec, review other implementations

**Risk 2**: MMU Sv39 complexity
- **Likelihood**: Medium
- **Impact**: Medium (blocks xv6/Linux)
- **Mitigation**: Start with unit tests, incremental implementation
- **Fallback**: Extensive documentation, QEMU reference

**Risk 3**: OS porting issues (xv6, Linux)
- **Likelihood**: High (expected)
- **Impact**: Medium (time delays)
- **Mitigation**: Use standard memory map (QEMU-compatible), start with OpenSBI
- **Fallback**: Community support, extensive Linux/xv6 documentation

### Schedule Risks

**Risk 4**: Phase 1 takes longer than expected
- **Likelihood**: Medium
- **Impact**: Medium (delays all subsequent phases)
- **Mitigation**: Conservative estimates (2-3 weeks), can parallelize CLINT/UART
- **Fallback**: Focus on CLINT first (most critical)

**Risk 5**: Scope creep (additional peripherals)
- **Likelihood**: High
- **Impact**: Medium (timeline extension)
- **Mitigation**: Strict prioritization, defer optional features
- **Fallback**: Define MVP for each phase, skip non-essentials

---

## Success Metrics

### Quantitative Metrics
1. **Test Coverage**: 34/34 privilege tests passing (Phase 1)
2. **Compliance**: 208/208 total tests passing (no regressions)
3. **Performance**: FreeRTOS context switch < 50 cycles
4. **Stability**: OS runs 24+ hours without crash
5. **Boot Time**: Linux boots in < 10 seconds (simulation time)

### Qualitative Metrics
1. **Completeness**: Can run unmodified xv6, Linux
2. **Compatibility**: Device tree matches QEMU virt machine
3. **Documentation**: Complete peripheral specs, memory maps
4. **Reusability**: Peripherals reusable in other projects
5. **Learning**: Demonstrated understanding of OS internals

---

## Next Steps (Immediate)

### This Week
1. ✅ Planning complete
2. ✅ Documentation written
3. ✅ Directories created
4. ⏭️ **Implement CLINT module** (next task)
5. ⏭️ Create CLINT testbench

### Next Week
- Complete CLINT testing
- Begin UART implementation
- UART testbench

### Week 3
- SoC integration
- First interrupt test (timer)
- UART print test

### Week 4
- Write 6 privilege interrupt tests
- Full validation
- Phase 1 complete ✅

---

## References Created

### Documentation
- `docs/OS_INTEGRATION_PLAN.md` - Complete roadmap (1100+ lines)
- `docs/MEMORY_MAP.md` - SoC memory map (700+ lines)
- `docs/SESSION_11_OS_PLANNING.md` - This document
- Updated `CLAUDE.md` - Added OS Integration Roadmap section

### Resources
- RISC-V Privileged Spec v1.12 (for CLINT, PLIC specs)
- RISC-V SBI Specification (for OpenSBI interface)
- 16550 UART datasheet (for register compatibility)
- QEMU virt machine source (for memory map reference)
- xv6-riscv repository (target OS)
- FreeRTOS RISC-V port (reference implementation)

---

## Lessons Learned

### Planning Process
1. **Incremental approach works**: Starting simple (FreeRTOS) before complex (Linux)
2. **Standard compatibility matters**: Using QEMU memory map reduces friction
3. **Documentation up-front saves time**: Clear specs before implementation
4. **Flexibility important**: Optional phases (nommu) allow schedule adjustment

### Architecture Decisions
1. **Parameterization pays off**: XLEN parameter enables RV32/RV64 dual support
2. **Minimal viable product**: CLINT + UART sufficient for FreeRTOS
3. **Defer non-critical decisions**: Block storage choice can wait
4. **Standard boot flow**: OpenSBI + U-Boot maximizes compatibility

---

## Conclusion

Session 11 established a comprehensive, realistic plan for OS integration. The plan is:

✅ **Well-structured**: Clear phases with milestones
✅ **Incremental**: Each phase builds on previous success
✅ **Realistic**: Conservative timeline estimates (16-24 weeks)
✅ **Flexible**: Optional phases allow adaptation
✅ **Documented**: Extensive documentation for future reference

**Next**: Begin Phase 1 implementation - CLINT module! 🚀

---

## Change Log

| Date | Activity | Status |
|------|----------|--------|
| 2025-10-26 | Planning session | ✅ Complete |
| 2025-10-26 | Documentation created | ✅ Complete |
| 2025-10-26 | Session summary written | ✅ Complete |
| TBD | Phase 1 implementation | ⏭️ Next |

---

**Status**: 📋 Planning Complete, Ready for Implementation
**Next Session**: Phase 1 - CLINT Implementation
