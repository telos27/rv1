# FPU Bugs - Verilator Compatibility Fixes

**Issue**: Mixed blocking and non-blocking assignments to `next_state` variable
**Severity**: Blocks Verilator compilation
**Files Affected**: 5 FPU modules
**Estimated Fix Time**: 30-60 minutes

---

## The Problem

Verilator error:
```
%Error-BLKANDNBLK: Unsupported: Blocked and non-blocking assignments to same variable: 'next_state'
```

**What's happening**:
```verilog
// WRONG: Same variable used with both = and <=
reg [2:0] next_state;

always @(*) begin
  next_state = IDLE;  // Blocking assignment (=)
  case (state)
    IDLE: next_state = COMPUTE;
    // ...
  endcase
end

always @(posedge clk) begin
  state <= next_state;  // Non-blocking assignment (<=) of same variable
end
```

**Why it's wrong**:
- `next_state` is assigned with `=` (blocking) in combinational block
- Same `next_state` is assigned with `<=` (non-blocking) in sequential block
- Verilator forbids mixing assignment types for same variable
- This is actually a code quality issue - bad practice

---

## The Fix

### Option 1: Make next_state purely combinational (RECOMMENDED)

```verilog
// CORRECT: Use wire and assign for combinational logic
reg [2:0] state;
reg [2:0] next_state_comb;  // Renamed to show it's combinational

always @(*) begin
  next_state_comb = IDLE;
  case (state)
    IDLE: next_state_comb = COMPUTE;
    COMPUTE: next_state_comb = DONE;
    DONE: next_state_comb = IDLE;
  endcase
end

always @(posedge clk or negedge reset_n) begin
  if (!reset_n)
    state <= IDLE;
  else
    state <= next_state_comb;  // Use the combinational value
end
```

### Option 2: Use separate signals

```verilog
// Also correct: Completely separate signals
reg [2:0] state;
wire [2:0] state_next;  // Wire for next state

// Combinational next state logic
assign state_next = (state == IDLE) ? COMPUTE :
                    (state == COMPUTE) ? DONE :
                    IDLE;

// Sequential state update
always @(posedge clk or negedge reset_n) begin
  if (!reset_n)
    state <= IDLE;
  else
    state <= state_next;
end
```

---

## Files to Fix

### 1. fp_adder.v (Line ~48)
**Location**: `rtl/core/fp_adder.v:48`

**Current code**:
```verilog
reg [2:0] next_state;  // Problem: used with both = and <=

always @(*) begin
  next_state = state;  // Blocking =
  // ... case logic
end

always @(posedge clk) begin
  state <= next_state;  // Non-blocking <=
end
```

**Fix**: Rename `next_state` → `next_state_comb` and use only `=`

---

### 2. fp_multiplier.v (Line ~46)
**Location**: `rtl/core/fp_multiplier.v:46`

Same pattern as fp_adder.v

---

### 3. fp_divider.v (Line ~48)
**Location**: `rtl/core/fp_divider.v:48`

Same pattern as fp_adder.v

---

### 4. fp_sqrt.v (Line ~44)
**Location**: `rtl/core/fp_sqrt.v:44`

Same pattern as fp_adder.v

---

### 5. fp_fma.v (Line ~49)
**Location**: `rtl/core/fp_fma.v:49`

Same pattern as fp_adder.v

---

## Quick Fix Script (If All Have Same Pattern)

For each file, the fix is:
1. Rename `next_state` → `next_state_comb` in the combinational always block
2. Keep using `=` (blocking) in combinational always
3. Update the sequential block to use `next_state_comb`

**Search pattern**:
```bash
grep -n "reg.*next_state" rtl/core/fp_*.v
```

**Example fix for fp_adder.v**:

```verilog
// OLD:
reg [2:0] next_state;

always @(*) begin
  next_state = state;
  case (state)
    // ...
  endcase
end

always @(posedge clk or negedge reset_n) begin
  if (!reset_n)
    state <= IDLE;
  else
    state <= next_state;
end

// NEW:
reg [2:0] next_state_comb;  // Renamed, still use blocking =

always @(*) begin
  next_state_comb = state;
  case (state)
    // ...
  endcase
end

always @(posedge clk or negedge reset_n) begin
  if (!reset_n)
    state <= IDLE;
  else
    state <= next_state_comb;  // Use renamed signal
end
```

---

## Verification

After fixing all 5 files, verify:

```bash
cd /home/lei/rv1

# Lint with Verilator
verilator --lint-only \
  -Irtl -DCONFIG_RV32IMC \
  --top-module rv_core_pipelined_wrapper \
  -Wno-PINMISSING -Wno-WIDTH -Wno-SELRANGE \
  tb/verilator/rv_core_wrapper.v \
  rtl/core/*.v rtl/memory/*.v 2>&1 | grep -i error

# Expected: No errors (or errors unrelated to next_state)
```

Then build:

```bash
verilator --cc --exe --build -j 0 \
  -Irtl -DCONFIG_RV32IMC \
  --top-module rv_core_pipelined_wrapper \
  -Wno-PINMISSING -Wno-WIDTH -Wno-SELRANGE \
  tb/verilator/rv_core_wrapper.v \
  rtl/core/*.v rtl/memory/*.v \
  tb/verilator/tb_rvc_verilator.cpp

# Expected: Successful build
```

Then test C extension:

```bash
./obj_dir/Vrv_core_pipelined_wrapper

# Expected: 30 cycles of execution with compressed instructions
```

---

## Notes

- This is a **code quality improvement**, not a functional bug
- The code worked in Icarus Verilog because it's more lenient
- Verilator enforces better coding practices
- The fix makes the code clearer and more maintainable
- After this fix, Verilator will be usable for all future development

---

## Impact

**Before**: Cannot use Verilator (better, faster simulator)
**After**: Full Verilator support enables:
- Faster simulation
- Better error detection
- Industry-standard workflows
- C extension validation

---

**Priority**: HIGH - This unblocks C extension testing
**Difficulty**: LOW - Straightforward pattern fix
**Time**: 30-60 minutes for all 5 files

---

**Let's fix these and prove the C extension works! 🚀**
