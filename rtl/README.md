# RTL Directory

This directory contains all Verilog RTL source files for the RV1 processor.

## Subdirectories

### core/
Core CPU modules:
- `rv32i_core.v` - Top-level processor module
- `pc.v` - Program Counter
- `register_file.v` - 32-register register file
- `alu.v` - Arithmetic Logic Unit
- `decoder.v` - Instruction decoder
- `control.v` - Control unit
- `imm_gen.v` - Immediate generator
- `branch_unit.v` - Branch condition evaluator

Phase 2 additions:
- `fsm_control.v` - FSM-based multi-cycle control

Phase 3 additions:
- `pipeline_regs.v` - Pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB)
- `forwarding_unit.v` - Data forwarding logic
- `hazard_unit.v` - Hazard detection

Phase 4 additions:
- `mul_div.v` - M extension multiply/divide unit
- `csr_file.v` - Control and Status Registers
- `trap_unit.v` - Exception and interrupt handling

### memory/
Memory subsystem:
- `instruction_memory.v` - Instruction memory (ROM)
- `data_memory.v` - Data memory (RAM)
- `memory_arbiter.v` - Arbiter for shared memory (Phase 2+)

Phase 4 additions:
- `icache.v` - Instruction cache
- `dcache.v` - Data cache
- `cache_controller.v` - Cache control logic

### peripherals/
I/O and peripheral modules (future):
- `uart.v` - UART controller
- `gpio.v` - General-purpose I/O
- `timer.v` - Timer/counter

## Coding Style

### File Organization
```verilog
// Header comment with module description
// Author, date, purpose

// Module definition
module module_name #(
    parameter PARAM1 = 32,
    parameter PARAM2 = 8
) (
    // Inputs (grouped by function)
    input  wire        clk,
    input  wire        reset_n,
    input  wire [31:0] data_in,

    // Outputs
    output wire [31:0] data_out
);

// Internal signals
wire [31:0] internal_sig;
reg  [31:0] registered_sig;

// Logic blocks (combinational then sequential)
always @(*) begin
    // Combinational logic
end

always @(posedge clk or negedge reset_n) begin
    // Sequential logic
end

endmodule
```

### Naming Conventions
- Modules: `snake_case.v`
- Parameters: `UPPER_CASE`
- Signals: `snake_case`
- Active-low: `_n` suffix
- Registered: `_r` suffix (optional)
- Next state: `_next` suffix

### Best Practices
1. Use 2-space indentation
2. Keep lines under 100 characters
3. Group related signals
4. Comment complex logic
5. Use meaningful names
6. Avoid magic numbers (use parameters)
7. Initialize all registers
8. No latches (always specify all cases)
9. No combinational loops
10. Synchronous resets preferred (or async active-low)
