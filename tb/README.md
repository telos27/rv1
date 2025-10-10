# Testbench Directory

This directory contains all testbenches for verifying the RV1 processor.

## Subdirectories

### unit/
Unit-level testbenches for individual modules:
- `tb_alu.v` - ALU testbench
- `tb_register_file.v` - Register file testbench
- `tb_decoder.v` - Decoder testbench
- `tb_control.v` - Control unit testbench
- `tb_branch_unit.v` - Branch unit testbench
- `tb_imm_gen.v` - Immediate generator testbench

Each testbench:
- Tests all functions of the module
- Includes corner cases
- Provides clear pass/fail indication
- Generates waveforms for debug

### integration/
System-level testbenches:
- `tb_core.v` - Full processor testbench
- `tb_pipeline.v` - Pipeline-specific tests (Phase 3)
- `tb_hazards.v` - Hazard scenario tests
- `tb_compliance.v` - RISC-V compliance test runner

## Testbench Structure

### Standard Testbench Template
```verilog
`timescale 1ns/1ps

module tb_module_name;

// Parameters
parameter CLK_PERIOD = 10;  // 100MHz

// Signals
reg         clk;
reg         reset_n;
reg  [31:0] input_data;
wire [31:0] output_data;

// DUT instantiation
module_name DUT (
    .clk(clk),
    .reset_n(reset_n),
    .input_data(input_data),
    .output_data(output_data)
);

// Clock generation
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// Test stimulus
initial begin
    // Initialize
    reset_n = 0;
    input_data = 32'h0;

    // Waveform dump
    $dumpfile("waves/module_name.vcd");
    $dumpvars(0, tb_module_name);

    // Release reset
    #(CLK_PERIOD*2);
    reset_n = 1;
    #(CLK_PERIOD);

    // Test cases
    test_case_1();
    test_case_2();
    // ...

    // Finish
    #(CLK_PERIOD*10);
    $display("All tests passed!");
    $finish;
end

// Test case tasks
task test_case_1;
    begin
        $display("Test Case 1: ...");
        input_data = 32'h12345678;
        #(CLK_PERIOD);
        if (output_data !== 32'hXXXXXXXX) begin
            $display("PASS");
        end else begin
            $display("FAIL");
            $finish;
        end
    end
endtask

endmodule
```

### Integration Testbench Template
```verilog
`timescale 1ns/1ps

module tb_core;

parameter CLK_PERIOD = 10;
parameter MEM_FILE = "../tests/vectors/test_program.hex";

reg         clk;
reg         reset_n;
wire [31:0] pc;
wire [31:0] instruction;

// Instantiate core
rv32i_core #(
    .MEM_FILE(MEM_FILE)
) DUT (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(pc),
    .instr_out(instruction)
);

// Clock
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// Simulation
initial begin
    $dumpfile("waves/core.vcd");
    $dumpvars(0, tb_core);

    reset_n = 0;
    #(CLK_PERIOD*5);
    reset_n = 1;

    // Run for N cycles
    #(CLK_PERIOD*1000);

    // Check results
    if (DUT.register_file.registers[10] == 32'd55) begin  // x10 = result
        $display("Test PASSED: Result = %d", DUT.register_file.registers[10]);
    end else begin
        $display("Test FAILED: Expected 55, got %d", DUT.register_file.registers[10]);
    end

    $finish;
end

// Monitor
initial begin
    $monitor("Time=%0t PC=%h Instr=%h", $time, pc, instruction);
end

endmodule
```

## Running Tests

### Using Icarus Verilog
```bash
# Compile and run unit test
iverilog -o sim/tb_alu.vvp tb/unit/tb_alu.v rtl/core/alu.v
vvp sim/tb_alu.vvp

# View waveform
gtkwave sim/waves/alu.vcd
```

### Using Verilator
```bash
# Compile and run
verilator --cc --exe --build tb/unit/tb_alu.cpp rtl/core/alu.v
./obj_dir/Valu
```

### Using Makefile
```bash
# Run all unit tests
make test-unit

# Run integration test
make test-core

# Run specific test
make test TEST=alu
```

## Test Coverage

Track coverage for:
1. **Statement coverage**: All lines executed
2. **Branch coverage**: All branches taken
3. **Functional coverage**: All instructions tested
4. **Corner cases**: Edge conditions

### Coverage Goals
- Unit tests: 100% statement coverage
- Integration: All instructions executed
- Compliance: Pass all RV32I tests

## Verification Checklist

### Per Module
- [ ] All functions tested
- [ ] Corner cases covered
- [ ] Reset behavior verified
- [ ] Timing violations checked
- [ ] Waveforms reviewed

### Full Core
- [ ] All instructions work
- [ ] Branch/jump behavior correct
- [ ] Memory access verified
- [ ] Register file operations correct
- [ ] Edge cases pass
- [ ] Long programs execute correctly

## Debug Tips

1. **Use VCD waveforms**: Visual inspection catches many bugs
2. **Add debug signals**: Expose internal states
3. **Use $display**: Print key values
4. **Single-step**: Run one instruction at a time
5. **Compare**: Check against golden model (Spike/QEMU)
6. **Assertions**: Add runtime checks with $assert
