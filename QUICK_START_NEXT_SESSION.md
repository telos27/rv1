# Quick Start Guide - Next Session

**Last Session**: 2025-10-10 (Session 8 - Parameterization Part 1)
**Status**: 70% Complete - Core datapath and pipeline parameterized
**Next Tasks**: CSR file, exception unit, top-level integration

---

## ⚡ 30-Second Context

You started parameterizing the RV1 RISC-V processor to support RV32/RV64 and multiple configurations. **11 out of 15 modules are done** (ALU, register file, decoder, memories, pipeline registers, PC, branch unit). Still need: CSR file, exception unit, control unit, and top-level integration.

---

## 🎯 What to Do Next

### Priority Order:
1. **CSR file** (`rtl/core/csr_file.v`) - 1-2 hours
2. **Exception unit** (`rtl/core/exception_unit.v`) - 30-60 min
3. **Top-level core** (`rtl/core/rv32i_core_pipelined.v`) - 2-3 hours
4. **Build system** (Makefile) - 1 hour
5. **Test** (regression) - 2-3 hours

**Total estimated**: 7-12 hours to complete

---

## 📖 Key Documents to Read

1. **NEXT_SESSION_PARAMETERIZATION.md** - Detailed task breakdown
2. **docs/PARAMETERIZATION_GUIDE.md** - Usage patterns and examples
3. **PARAMETERIZATION_PROGRESS.md** - What's been completed

---

## 🔧 CSR File Parameterization (Start Here)

### What to Change:
```verilog
// Before:
reg [31:0] mepc;
reg [31:0] mtval;
reg [31:0] mtvec;

// After:
`include "config/rv_config.vh"

module csr_file #(
  parameter XLEN = `XLEN
) (
  // ... ports
);

reg [XLEN-1:0] mepc;
reg [XLEN-1:0] mtval;
reg [XLEN-1:0] mtvec;
```

### CSRs to Parameterize (XLEN-wide):
- `mepc` - Exception PC
- `mtval` - Trap value
- `mtvec` - Trap vector
- `mscratch` - Scratch register
- `mstatus` - Status (special handling for RV64)
- `mcause` - Cause (XLEN-wide per spec)

### CSRs that Stay 32-bit:
- `mvendorid`, `marchid`, `mimpid` - Identification

---

## 🚀 Quick Commands

### Check Current State
```bash
cd /home/lei/rv1
git status
git log --oneline -3
```

### List Parameterized Files
```bash
grep -l "parameter XLEN" rtl/core/*.v rtl/memory/*.v
```

### Verify Configuration File
```bash
cat rtl/config/rv_config.vh | head -30
```

### Test Compilation (when ready)
```bash
iverilog -g2012 -I rtl/config -o sim/test.vvp rtl/core/alu.v
```

---

## ✅ Completed Modules

1. ✅ Configuration system (`rtl/config/rv_config.vh`)
2. ✅ ALU
3. ✅ Register File
4. ✅ Decoder
5. ✅ Data Memory (+ RV64 LD/SD/LWU)
6. ✅ Instruction Memory
7. ✅ IF/ID Pipeline Register
8. ✅ ID/EX Pipeline Register
9. ✅ EX/MEM Pipeline Register
10. ✅ MEM/WB Pipeline Register
11. ✅ PC
12. ✅ Branch Unit

## ⏳ Remaining Modules

1. ⏳ CSR File (`rtl/core/csr_file.v`)
2. ⏳ Exception Unit (`rtl/core/exception_unit.v`)
3. ⏳ Control Unit (`rtl/core/control.v`) - minimal changes
4. ⏳ Top-Level Core (`rtl/core/rv32i_core_pipelined.v`)

---

## 🎓 Key Patterns

### 1. Always Use XLEN
```verilog
wire [XLEN-1:0] data;  // NOT [31:0]
```

### 2. Zero Initialization
```verilog
result = {XLEN{1'b0}};  // NOT 32'h0
```

### 3. Sign Extension
```verilog
{{(XLEN-N){sign_bit}}, data}
```

### 4. Module Header
```verilog
`include "config/rv_config.vh"

module my_module #(
  parameter XLEN = `XLEN
) (
  input  wire [XLEN-1:0] in,
  output wire [XLEN-1:0] out
);
```

---

## 📚 Reference: Configuration Presets

```bash
# RV32I (default)
-DCONFIG_RV32I

# RV32IM (with multiply)
-DCONFIG_RV32IM

# RV64I (64-bit)
-DCONFIG_RV64I

# Custom
-DXLEN=64 -DENABLE_M_EXT=1
```

---

## 🎯 Success Criteria

Session complete when:
- [ ] CSR file compiles with XLEN parameter
- [ ] Exception unit compiles with XLEN parameter
- [ ] Top-level core integrated and compiles
- [ ] Makefile created with rv32i target
- [ ] `make rv32i && make run-rv32i` works
- [ ] RV32I compliance tests pass (40/42)

---

## 🚨 Watch Out For

1. **CSR width differences** - Some CSRs differ between RV32/RV64
2. **Sign-extension** - Must extend to XLEN, not hardcoded 32
3. **Module instantiation** - Must pass `.XLEN(XLEN)` parameter
4. **Testbenches** - May need updates for XLEN

---

## 💡 Pro Tips

1. Compile after each module to catch errors early
2. Check RISC-V privilege spec for CSR definitions
3. Use existing parameterized modules as templates
4. grep for `[31:0]` to find hardcoded widths
5. Test with RV32I first before trying RV64I

---

**Ready to continue! Start with CSR file parameterization. Good luck! 🚀**
