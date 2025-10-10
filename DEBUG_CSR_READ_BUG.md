# DEBUG GUIDE: CSR Read Bug

**Priority**: 🚨 CRITICAL
**Status**: Not Fixed
**Impact**: Blocks all exception handling, prevents 41/42 compliance

---

## Quick Summary

**Problem**: All CSR reads return 0 instead of actual CSR values

**Example**:
```assembly
csrw mstatus, 0x1888  # Write works
csrr x2, mstatus      # Read fails: x2 = 0 (should be 0x1888)
```

**Verified**:
- ✅ CSR file works correctly (unit test confirmed)
- ❌ Pipeline integration broken

---

## Debugging Steps

### 1. Check CSR File Output in Pipeline
```bash
# Run test with waveform
iverilog -DMEM_FILE="/tmp/test_csr_read.hex" -o sim/test.vvp rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v
vvp sim/test.vvp
gtkwave sim/waves/core_pipelined.vcd

# Look for these signals:
# - ex_csr_rdata (should be 0x1888 after CSR read)
# - exmem_csr_rdata (should latch ex_csr_rdata)
# - memwb_csr_rdata (should latch exmem_csr_rdata)
# - wb_data (should be memwb_csr_rdata when wb_sel==2'b11)
```

### 2. Add Debug Prints
```verilog
// In rv32i_core_pipelined.v, after CSR file instantiation
always @(posedge clk) begin
  if (idex_csr_we)
    $display("CSR op: addr=%h we=%b rdata=%h", idex_csr_addr, idex_csr_we, ex_csr_rdata);
end

// In exmem_register.v
always @(posedge clk) begin
  if (csr_we_in)
    $display("EX/MEM: csr_rdata_in=%h → csr_rdata_out=%h", csr_rdata_in, csr_rdata_out);
end

// In memwb_register.v
always @(posedge clk) begin
  $display("MEM/WB: csr_rdata_in=%h → csr_rdata_out=%h wb_sel=%b",
           csr_rdata_in, csr_rdata_out, wb_sel_in);
end
```

### 3. Check Write-Back Path
```verilog
// In rv32i_core_pipelined.v, near write-back
always @(posedge clk) begin
  if (memwb_reg_write && memwb_valid)
    $display("WB: rd=x%0d wb_sel=%b wb_data=%h csr_rdata=%h",
             memwb_rd_addr, memwb_wb_sel, wb_data, memwb_csr_rdata);
end
```

---

## Likely Causes (Ranked)

### 1. Pipeline Register Not Latching (Most Likely)
**Check**: Do exmem_csr_rdata and memwb_csr_rdata match their inputs?

**Fix**: Verify always block in pipeline registers
```verilog
// In exmem_register.v and memwb_register.v
always @(posedge clk or negedge reset_n) begin
  if (!reset_n)
    csr_rdata_out <= 32'h0;
  else
    csr_rdata_out <= csr_rdata_in;  // Check this line exists!
end
```

### 2. Valid Flag Clearing Data
**Check**: Is CSR data cleared when valid=0?

**Fix**: Ensure CSR data passes through regardless of valid flag
```verilog
// Data should be latched even if instruction is invalid
// Valid flag only affects write enables, not data path
```

### 3. CSR Write Enable Confusion
**Check**: Is `csr_we` being confused with register write enable?

**Note**:
- `csr_we=1` → Write to CSR
- `csr_we=0` → Read from CSR (still needs register write!)
- Register write should always happen for CSR instructions

### 4. Write-Back Mux Priority
**Check**: Is wb_sel actually 2'b11 for CSR reads?

**Fix**: Verify control unit sets wb_sel=2'b11 for all CSR instructions
```verilog
// In control.v, SYSTEM opcode section
if (is_csr) begin
  reg_write = 1'b1;        // Must write to register
  wb_sel = 2'b11;          // Select CSR data
  csr_we = (funct3[1:0] == 2'b01) ? 1'b1 : ...;  // CSR write logic
end
```

### 5. Timing Issue
**Check**: Does CSR read complete in time for EX stage latch?

**Note**: CSR file read is combinational, should be instant
- Input: csr_addr (from ID/EX register)
- Output: csr_rdata (combinational)
- Should be ready before clock edge

---

## Test Cases

### Minimal Test (Use This First)
```assembly
# /tmp/test_csr_read.s
li   x1, 0x1888
csrw mstatus, x1    # Write
csrr x2, mstatus    # Read
li   x3, 0x1888     # Expected
beq  x2, x3, pass   # Compare

fail:
li   x10, 0
j    end

pass:
li   x10, 1

end:
j    end
```

**Expected**: x10 = 1 (pass)
**Current**: x10 = 0 (fail) because x2 = 0

### After Fix
```bash
# Compile and run
riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 -o /tmp/test.o /tmp/test_csr_read.s
riscv64-unknown-elf-ld -m elf32lriscv -T tests/linker.ld -o /tmp/test.elf /tmp/test.o
riscv64-unknown-elf-objcopy -O verilog /tmp/test.elf /tmp/test.hex

iverilog -DMEM_FILE="/tmp/test.hex" -o sim/test.vvp rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v
vvp sim/test.vvp | grep "x10"

# Should show: x10 (a0) = 0x00000001 (return value)
```

---

## Success Criteria

Fix is complete when:
1. ✅ Simple CSR read test passes (x10 = 1)
2. ✅ CSR basic test progresses beyond first read
3. ✅ Misaligned exception test reads mcause correctly
4. ✅ Compliance: `ma_data` passes → 41/42 (97%)

---

## Related Files

- `rtl/core/rv32i_core_pipelined.v` - Main pipeline, CSR integration
- `rtl/core/exmem_register.v` - EX/MEM pipeline register
- `rtl/core/memwb_register.v` - MEM/WB pipeline register
- `rtl/core/csr_file.v` - CSR file (works correctly)
- `rtl/core/control.v` - Control signals for CSR instructions

---

## Quick Commands

```bash
# 1. Test CSR read
./tools/test_csr_read.sh  # (create this script)

# 2. View waveform
gtkwave sim/waves/core_pipelined.vcd &

# 3. Run compliance after fix
./tools/run_compliance_pipelined.sh

# 4. Check for 41/42
grep "Passed:" sim/compliance/*.log
```

---

**Start here next session!** 🎯
