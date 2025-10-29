`timescale 1ns / 1ps

// debug_trace.v - Comprehensive debugging infrastructure for RISC-V CPU
// Provides call stack tracing, register monitoring, memory watchpoints, and symbol resolution

module debug_trace #(
  parameter XLEN = 32,
  parameter PC_HISTORY_DEPTH = 128,  // Track last 128 PCs
  parameter MAX_WATCHPOINTS = 16,
  parameter SYMBOL_FILE = ""  // Optional symbol file for function name lookup
) (
  input wire clk,
  input wire rst_n,

  // CPU state
  input wire [XLEN-1:0] pc,
  input wire [XLEN-1:0] pc_next,
  input wire [31:0] instruction,
  input wire valid_instruction,  // Only trace when instruction is valid

  // Register file access
  input wire [XLEN-1:0] x1_ra,   // Return address
  input wire [XLEN-1:0] x2_sp,   // Stack pointer
  input wire [XLEN-1:0] x10_a0,  // Function arguments
  input wire [XLEN-1:0] x11_a1,
  input wire [XLEN-1:0] x12_a2,
  input wire [XLEN-1:0] x13_a3,
  input wire [XLEN-1:0] x14_a4,
  input wire [XLEN-1:0] x15_a5,
  input wire [XLEN-1:0] x16_a6,
  input wire [XLEN-1:0] x17_a7,

  // Memory access monitoring
  input wire mem_valid,
  input wire mem_write,
  input wire [XLEN-1:0] mem_addr,
  input wire [XLEN-1:0] mem_wdata,
  input wire [XLEN-1:0] mem_rdata,
  input wire [(XLEN/8)-1:0] mem_wstrb,

  // Exception/interrupt info
  input wire trap_taken,
  input wire [XLEN-1:0] trap_pc,
  input wire [XLEN-1:0] trap_cause,

  // Control
  input wire enable_trace,
  input wire [XLEN-1:0] trace_start_pc,  // Start tracing from this PC (0=always)
  input wire [XLEN-1:0] trace_end_pc     // Stop tracing at this PC (0=never)
);

  // PC History Buffer (circular)
  reg [XLEN-1:0] pc_history [0:PC_HISTORY_DEPTH-1];
  reg [7:0] pc_history_idx = 0;
  reg [7:0] pc_history_count = 0;

  // Call stack tracking
  reg [XLEN-1:0] call_stack [0:63];  // Track up to 64 nested calls
  reg [5:0] call_depth = 0;

  // Watchpoints
  reg [XLEN-1:0] watchpoint_addr [0:MAX_WATCHPOINTS-1];
  reg [MAX_WATCHPOINTS-1:0] watchpoint_enabled = 0;
  reg [MAX_WATCHPOINTS-1:0] watchpoint_on_write = 0;  // 1=write, 0=read

  // Tracing state
  reg tracing_active = 0;
  integer cycle_count = 0;

  // Decode instruction type
  wire [6:0] opcode = instruction[6:0];
  wire [2:0] funct3 = instruction[14:12];
  wire [4:0] rd = instruction[11:7];
  wire [4:0] rs1 = instruction[19:15];
  wire [11:0] imm_i = instruction[31:20];
  wire [19:0] imm_j = {instruction[31], instruction[19:12], instruction[20], instruction[30:21]};

  // Detect JAL/JALR (function calls)
  wire is_jal = (opcode == 7'b1101111);
  wire is_jalr = (opcode == 7'b1100111) && (funct3 == 3'b000);
  wire is_call = (is_jal || is_jalr) && (rd == 5'd1 || rd == 5'd5);  // rd=ra or t0
  wire is_ret = is_jalr && (rs1 == 5'd1) && (rd == 5'd0);  // ret = jalr x0, ra, 0

  // Detect tail calls (JAL/JALR with rd=x0)
  wire is_tail_call = (is_jal || is_jalr) && (rd == 5'd0);

  // Compressed instruction detection
  wire is_compressed = (instruction[1:0] != 2'b11);

  // Initialize watchpoints (can be set via parameter or during simulation)
  initial begin
    integer i;
    for (i = 0; i < MAX_WATCHPOINTS; i = i + 1) begin
      watchpoint_addr[i] = 0;
    end
  end

  // Tracing control
  always @(posedge clk) begin
    if (!rst_n) begin
      tracing_active <= (trace_start_pc == 0) ? 1 : 0;
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;

      // Start/stop tracing based on PC
      if (valid_instruction) begin
        if (trace_start_pc != 0 && pc == trace_start_pc)
          tracing_active <= 1;
        if (trace_end_pc != 0 && pc == trace_end_pc)
          tracing_active <= 0;
      end
    end
  end

  // PC History tracking
  always @(posedge clk) begin
    if (!rst_n) begin
      pc_history_idx <= 0;
      pc_history_count <= 0;
    end else if (enable_trace && tracing_active && valid_instruction) begin
      pc_history[pc_history_idx] <= pc;
      pc_history_idx <= pc_history_idx + 1;
      if (pc_history_count < PC_HISTORY_DEPTH)
        pc_history_count <= pc_history_count + 1;
    end
  end

  // Call stack tracking
  always @(posedge clk) begin
    if (!rst_n) begin
      call_depth <= 0;
    end else if (enable_trace && tracing_active && valid_instruction) begin
      // Track function calls
      if (is_call && call_depth < 63) begin
        call_stack[call_depth] <= pc + (is_compressed ? 2 : 4);  // Return address
        call_depth <= call_depth + 1;
      end
      // Track function returns
      else if (is_ret && call_depth > 0) begin
        call_depth <= call_depth - 1;
      end
    end
  end

  // Memory watchpoint monitoring
  always @(posedge clk) begin
    if (enable_trace && tracing_active && mem_valid) begin
      integer i;
      for (i = 0; i < MAX_WATCHPOINTS; i = i + 1) begin
        if (watchpoint_enabled[i]) begin
          // Check if this access matches the watchpoint
          if (mem_addr >= watchpoint_addr[i] && mem_addr < watchpoint_addr[i] + (XLEN/8)) begin
            // Check if access type matches
            if ((mem_write && watchpoint_on_write[i]) || (!mem_write && !watchpoint_on_write[i])) begin
              $display("[WATCH %0d] Cycle %0d: %s addr=0x%h data=0x%h",
                i, cycle_count, mem_write ? "WRITE" : "READ", mem_addr,
                mem_write ? mem_wdata : mem_rdata);
            end
          end
        end
      end
    end
  end

  // Main instruction trace
  always @(posedge clk) begin
    if (enable_trace && tracing_active && valid_instruction) begin
      // Function call
      if (is_call) begin
        $display("[%0d] %s0x%h: CALL -> 0x%h (ra=0x%h, sp=0x%h, depth=%0d)",
          cycle_count, indent_str(call_depth), pc, pc_next, x1_ra, x2_sp, call_depth);
        $display("       Args: a0=0x%h a1=0x%h a2=0x%h a3=0x%h",
          x10_a0, x11_a1, x12_a2, x13_a3);
      end
      // Function return
      else if (is_ret) begin
        $display("[%0d] %s0x%h: RET -> 0x%h (a0=0x%h, depth=%0d)",
          cycle_count, indent_str(call_depth-1), pc, x1_ra, x10_a0, call_depth-1);
      end
    end
  end

  // Trap/exception monitoring
  always @(posedge clk) begin
    if (enable_trace && tracing_active && trap_taken) begin
      $display("[%0d] *** TRAP *** pc=0x%h cause=0x%h handler=0x%h",
        cycle_count, pc, trap_cause, trap_pc);
      $display("       State: ra=0x%h sp=0x%h a0=0x%h", x1_ra, x2_sp, x10_a0);
      display_call_stack();
    end
  end

  // Helper function to create indentation based on call depth
  function [639:0] indent_str;
    input integer depth;
    integer i;
    begin
      indent_str = "";
      for (i = 0; i < depth && i < 20; i = i + 1)
        indent_str = {indent_str, "  "};
    end
  endfunction

  // Task to display current call stack
  task display_call_stack;
    integer i;
    begin
      $display("       === Call Stack (depth=%0d) ===", call_depth);
      for (i = call_depth - 1; i >= 0; i = i - 1) begin
        $display("       [%0d] Return to: 0x%h", call_depth - i, call_stack[i]);
      end
    end
  endtask

  // Task to display PC history
  task display_pc_history;
    input integer count;  // How many entries to display
    integer i, idx;
    begin
      $display("=== PC History (last %0d) ===", count);
      for (i = 0; i < count && i < pc_history_count; i = i + 1) begin
        idx = (pc_history_idx - 1 - i + PC_HISTORY_DEPTH) % PC_HISTORY_DEPTH;
        $display("[-%0d] 0x%h", i, pc_history[idx]);
      end
    end
  endtask

  // Task to set a watchpoint
  task set_watchpoint;
    input integer id;
    input [XLEN-1:0] addr;
    input on_write;  // 1=watch writes, 0=watch reads
    begin
      if (id < MAX_WATCHPOINTS) begin
        watchpoint_addr[id] = addr;
        watchpoint_enabled[id] = 1;
        watchpoint_on_write[id] = on_write;
        $display("[DEBUG] Watchpoint %0d set: addr=0x%h type=%s",
          id, addr, on_write ? "WRITE" : "READ");
      end else begin
        $display("[DEBUG] ERROR: Watchpoint ID %0d out of range (max=%0d)",
          id, MAX_WATCHPOINTS-1);
      end
    end
  endtask

  // Task to clear a watchpoint
  task clear_watchpoint;
    input integer id;
    begin
      if (id < MAX_WATCHPOINTS) begin
        watchpoint_enabled[id] = 0;
        $display("[DEBUG] Watchpoint %0d cleared", id);
      end
    end
  endtask

  // Task to display register state
  task display_registers;
    begin
      $display("=== Register State (Cycle %0d, PC=0x%h) ===", cycle_count, pc);
      $display("  ra (x1)  = 0x%h", x1_ra);
      $display("  sp (x2)  = 0x%h", x2_sp);
      $display("  a0 (x10) = 0x%h  a1 (x11) = 0x%h", x10_a0, x11_a1);
      $display("  a2 (x12) = 0x%h  a3 (x13) = 0x%h", x12_a2, x13_a3);
      $display("  a4 (x14) = 0x%h  a5 (x15) = 0x%h", x14_a4, x15_a5);
      $display("  a6 (x16) = 0x%h  a7 (x17) = 0x%h", x16_a6, x17_a7);
    end
  endtask

endmodule
