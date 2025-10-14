// tb_core_pipelined.v - Integration testbench for pipelined RV32I core
// Tests the complete 5-stage pipelined processor with test programs
// Author: RV1 Project
// Date: 2025-10-10
// Updated: 2025-10-12 - Added performance metrics and improved EBREAK detection

`timescale 1ns/1ps

module tb_core_pipelined;

  // Clock parameters
  parameter CLK_PERIOD = 10;          // 100MHz
  parameter TIMEOUT = 50000;          // Maximum cycles

  // Debug level (can be overridden with -D)
  `ifdef DEBUG_LEVEL
    parameter DEBUG = `DEBUG_LEVEL;
  `else
    parameter DEBUG = 0;              // 0=none, 1=basic, 2=detailed, 3=verbose
  `endif

  // Memory file (can be overridden with -D)
  `ifdef MEM_FILE
    parameter MEM_INIT_FILE = `MEM_FILE;
  `else
    parameter MEM_INIT_FILE = "";
  `endif

  // Testbench signals
  reg         clk;
  reg         reset_n;
  wire [31:0] pc;
  wire [31:0] instruction;

  // Cycle counter and performance metrics
  integer cycle_count;
  integer total_instructions;
  integer stall_cycles;
  integer flush_cycles;
  integer load_use_stalls;
  integer branch_flushes;

  // RISC-V compliance tests start at 0x80000000
  `ifdef COMPLIANCE_TEST
    parameter RESET_VEC = 32'h80000000;
  `else
    parameter RESET_VEC = 32'h00000000;
  `endif

  // Instantiate DUT (pipelined core)
  rv_core_pipelined #(
    .RESET_VECTOR(RESET_VEC),
    .IMEM_SIZE(16384),  // 16KB instruction memory
    .DMEM_SIZE(16384),  // 16KB data memory
    .MEM_FILE(MEM_INIT_FILE)
  ) DUT (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(pc),
    .instr_out(instruction)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // Test sequence
  initial begin
    $display("========================================");
    $display("RV32I Pipelined Core Integration Test");
    $display("========================================");
    if (MEM_INIT_FILE != "") begin
      $display("Loading program from: %s", MEM_INIT_FILE);
    end else begin
      $display("No program loaded (using NOPs)");
    end
    `ifdef COMPLIANCE_TEST
      $display("Mode: RISC-V Compliance Test");
    `endif
    if (DEBUG > 0) begin
      $display("Debug level: %0d", DEBUG);
    end
    $display("");

    // Dump waveforms
    $dumpfile("sim/waves/core_pipelined.vcd");
    $dumpvars(0, tb_core_pipelined);

    // Initialize counters
    reset_n = 0;
    cycle_count = 0;
    total_instructions = 0;
    stall_cycles = 0;
    flush_cycles = 0;
    load_use_stalls = 0;
    branch_flushes = 0;

    // Hold reset for a few cycles
    repeat(5) @(posedge clk);
    reset_n = 1;
    $display("Reset released at time %0t", $time);
    $display("");

    // Run for specified cycles or until EBREAK/ECALL
    repeat(TIMEOUT) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;

      // Performance monitoring
      if (DUT.idex_valid && !DUT.flush_idex) begin
        total_instructions = total_instructions + 1;
      end
      if (DUT.stall_pc) begin
        stall_cycles = stall_cycles + 1;
        // Check if it's a load-use stall
        if (DUT.hazard_unit.load_use_hazard) begin
          load_use_stalls = load_use_stalls + 1;
        end
      end
      if (DUT.flush_idex) begin
        flush_cycles = flush_cycles + 1;
        // Check if it's a branch flush
        if (DUT.ex_take_branch) begin
          branch_flushes = branch_flushes + 1;
        end
      end

      // Debug output (controlled by DEBUG parameter)
      if (DEBUG >= 3) begin
        $display("[%0d] IF: PC=%h | ID: PC=%h | EX: PC=%h rd=x%0d | MEM: PC=%h | WB: rd=x%0d wen=%b",
                 cycle_count, pc, DUT.ifid_pc, DUT.idex_pc, DUT.idex_rd_addr,
                 DUT.exmem_pc, DUT.memwb_rd_addr, DUT.memwb_reg_write);
        if (DEBUG >= 4) begin
          $display("       Forwarding: id_fwd_a=%b id_fwd_b=%b ex_fwd_a=%b ex_fwd_b=%b",
                   DUT.id_forward_a, DUT.id_forward_b, DUT.forward_a, DUT.forward_b);
          $display("       Hazards: stall=%b flush=%b | Data: rs1=%h rs2=%h",
                   DUT.stall_pc, DUT.flush_idex, DUT.id_rs1_data, DUT.id_rs2_data);
        end
      end

      // PC trace for debugging CSR-FPU hazard
      `ifdef DEBUG_HAZARD
      $display("[%0d] PC=%08h stall_pc=%b stall_ifid=%b flush=%b | fpu_busy=%b idex_fp_alu=%b csr_fpu_stall=%b",
               cycle_count, pc, DUT.stall_pc, DUT.stall_ifid, DUT.flush_idex,
               DUT.ex_fpu_busy, DUT.idex_fp_alu_en, DUT.hazard_unit.csr_fpu_dependency_stall);
      $display("       IF: PC=%08h | ID: PC=%08h valid=%b | EX: PC=%08h valid=%b | MEM: PC=%08h valid=%b | WB: valid=%b",
               pc, DUT.ifid_pc, DUT.ifid_valid, DUT.idex_pc, DUT.idex_valid,
               DUT.exmem_pc, DUT.exmem_valid, DUT.memwb_valid);
      if (DUT.hazard_unit.csr_accesses_fp_flags) begin
        $display("       >>> CSR accesses FP flags: csr_addr=%03h csr_we=%b",
                 DUT.hazard_unit.id_csr_addr, DUT.hazard_unit.id_csr_we);
      end
      `endif

      // FPU debug output - log FP instructions completing in WB stage
      `ifdef DEBUG_FPU
      if (DUT.memwb_fp_reg_write && DUT.memwb_valid) begin
        $display("[%0d] FPU WB: fd=f%0d | result=%h | fflags=%05b (NV=%b DZ=%b OF=%b UF=%b NX=%b)",
                 cycle_count, DUT.memwb_fp_rd_addr,
                 DUT.memwb_fp_result,
                 {DUT.memwb_fp_flag_nv, DUT.memwb_fp_flag_dz, DUT.memwb_fp_flag_of, DUT.memwb_fp_flag_uf, DUT.memwb_fp_flag_nx},
                 DUT.memwb_fp_flag_nv, DUT.memwb_fp_flag_dz, DUT.memwb_fp_flag_of, DUT.memwb_fp_flag_uf, DUT.memwb_fp_flag_nx);
        $display("       wb_sel=%03b mem_data=%h wb_fp_data=%h",
                 DUT.memwb_wb_sel, DUT.memwb_mem_read_data, DUT.wb_fp_data);
        $display("       FCSR fflags=%05b (accumulated)", DUT.csr_fflags);
      end
      `endif

      // Check for EBREAK (0x00100073) in IF stage
      // We'll wait for it to reach WB stage before checking results
      if (instruction == 32'h00100073) begin
        // Wait for pipeline to complete and EBREAK to reach WB stage (10 cycles)
        // This ensures all preceding instructions complete their WB
        repeat(10) @(posedge clk);
        cycle_count = cycle_count + 10;

        $display("EBREAK encountered at cycle %0d", cycle_count);
        $display("Final PC: 0x%08h", pc);
        $display("");
        print_results();
        $display("");

        // Check x28 register for test result markers
        // Common success markers: 0xFEEDFACE, 0xDEADBEEF, 0xC0FFEE00, 0x00000001
        // Common failure markers: 0xDEADDEAD, 0xBADC0DE, 0x00000000
        case (DUT.regfile.registers[28])
          32'hFEEDFACE,
          32'hDEADBEEF,
          32'hC0FFEE00,
          32'h0000BEEF,
          32'h00000001: begin
            $display("========================================");
            $display("TEST PASSED");
            $display("========================================");
            $display("  Success marker (x28): 0x%08h", DUT.regfile.registers[28]);
            $display("  Cycles: %0d", cycle_count);
          end
          32'hDEADDEAD,
          32'h0BADC0DE: begin
            $display("========================================");
            $display("TEST FAILED");
            $display("========================================");
            $display("  Failure marker (x28): 0x%08h", DUT.regfile.registers[28]);
            $display("  Cycles: %0d", cycle_count);
          end
          default: begin
            $display("========================================");
            $display("TEST PASSED (EBREAK with no marker)");
            $display("========================================");
            $display("  Note: x28 = 0x%08h (no standard marker)", DUT.regfile.registers[28]);
            $display("  Cycles: %0d", cycle_count);
          end
        endcase
        $finish;
      end

      `ifdef COMPLIANCE_TEST
      // Check for ECALL (0x00000073) - used by RISC-V compliance tests
      if (instruction == 32'h00000073) begin
        // Wait for pipeline to complete (5 cycles)
        repeat(5) @(posedge clk);
        cycle_count = cycle_count + 5;

        $display("ECALL encountered at cycle %0d", cycle_count);
        $display("Final PC: 0x%08h", pc);
        $display("");

        // Check gp (x3) register for pass/fail
        if (DUT.regfile.registers[3] == 1) begin
          $display("========================================");
          $display("RISC-V COMPLIANCE TEST PASSED");
          $display("========================================");
          $display("  Test result (gp/x3): %0d", DUT.regfile.registers[3]);
          $display("  Cycles: %0d", cycle_count);
          $finish;
        end else begin
          $display("========================================");
          $display("RISC-V COMPLIANCE TEST FAILED");
          $display("========================================");
          $display("  Failed at test number: %0d", DUT.regfile.registers[3]);
          $display("  Final PC: 0x%08h", pc);
          $display("  Cycles: %0d", cycle_count);
          print_results();
          $finish;
        end
      end
      `endif

      // Timeout check
      if (cycle_count >= TIMEOUT - 1) begin
        $display("WARNING: Timeout reached (%0d cycles)", TIMEOUT);
        $display("Final PC: 0x%08h", pc);
        $display("Last instruction: 0x%08h", instruction);
        print_results();
        $display("");
        $display("Test TIMEOUT (may need more cycles or infinite loop)");
        $finish;
      end
    end
  end

  // Task to print register file contents
  task print_results;
    integer i;
    real cpi;
    real stall_rate;
    real flush_rate;
    begin
      $display("=== Final Register File Contents ===");
      $display("x0  (zero) = 0x%08h", DUT.regfile.registers[0]);
      $display("x1  (ra)   = 0x%08h", DUT.regfile.registers[1]);
      $display("x2  (sp)   = 0x%08h", DUT.regfile.registers[2]);
      $display("x3  (gp)   = 0x%08h", DUT.regfile.registers[3]);
      $display("x4  (tp)   = 0x%08h", DUT.regfile.registers[4]);
      $display("x5  (t0)   = 0x%08h", DUT.regfile.registers[5]);
      $display("x6  (t1)   = 0x%08h", DUT.regfile.registers[6]);
      $display("x7  (t2)   = 0x%08h", DUT.regfile.registers[7]);
      $display("x8  (s0)   = 0x%08h", DUT.regfile.registers[8]);
      $display("x9  (s1)   = 0x%08h", DUT.regfile.registers[9]);
      $display("x10 (a0)   = 0x%08h (return value)", DUT.regfile.registers[10]);
      $display("x11 (a1)   = 0x%08h", DUT.regfile.registers[11]);
      $display("x12 (a2)   = 0x%08h", DUT.regfile.registers[12]);
      $display("x13 (a3)   = 0x%08h", DUT.regfile.registers[13]);
      $display("x14 (a4)   = 0x%08h", DUT.regfile.registers[14]);
      $display("x15 (a5)   = 0x%08h", DUT.regfile.registers[15]);
      $display("x16 (a6)   = 0x%08h", DUT.regfile.registers[16]);
      $display("x17 (a7)   = 0x%08h", DUT.regfile.registers[17]);
      $display("x18 (s2)   = 0x%08h", DUT.regfile.registers[18]);
      $display("x19 (s3)   = 0x%08h", DUT.regfile.registers[19]);
      $display("x20 (s4)   = 0x%08h", DUT.regfile.registers[20]);
      $display("x21 (s5)   = 0x%08h", DUT.regfile.registers[21]);
      $display("x22 (s6)   = 0x%08h", DUT.regfile.registers[22]);
      $display("x23 (s7)   = 0x%08h", DUT.regfile.registers[23]);
      $display("x24 (s8)   = 0x%08h", DUT.regfile.registers[24]);
      $display("x25 (s9)   = 0x%08h", DUT.regfile.registers[25]);
      $display("x26 (s10)  = 0x%08h", DUT.regfile.registers[26]);
      $display("x27 (s11)  = 0x%08h", DUT.regfile.registers[27]);
      $display("x28 (t3)   = 0x%08h", DUT.regfile.registers[28]);
      $display("x29 (t4)   = 0x%08h", DUT.regfile.registers[29]);
      $display("x30 (t5)   = 0x%08h", DUT.regfile.registers[30]);
      $display("x31 (t6)   = 0x%08h", DUT.regfile.registers[31]);
      $display("");

      // Performance metrics
      if (DEBUG >= 1 || total_instructions > 0) begin
        $display("=== Performance Metrics ===");
        $display("Total cycles:        %0d", cycle_count);
        $display("Total instructions:  %0d", total_instructions);
        if (total_instructions > 0) begin
          cpi = cycle_count * 1.0 / total_instructions;
          $display("CPI (Cycles/Instr):  %0.3f", cpi);
        end else begin
          $display("CPI (Cycles/Instr):  N/A (no instructions)");
        end

        if (cycle_count > 0) begin
          stall_rate = stall_cycles * 100.0 / cycle_count;
          flush_rate = flush_cycles * 100.0 / cycle_count;
          $display("Stall cycles:        %0d (%0.1f%%)", stall_cycles, stall_rate);
          $display("  Load-use stalls:   %0d", load_use_stalls);
          $display("Flush cycles:        %0d (%0.1f%%)", flush_cycles, flush_rate);
          $display("  Branch flushes:    %0d", branch_flushes);
        end
        $display("");
      end
    end
  endtask

  // Pipeline stage monitoring (controlled by DEBUG level)
  // Use -DDEBUG_LEVEL=3 or -DDEBUG_LEVEL=4 for detailed pipeline tracing
  // DEBUG=0: No debug output
  // DEBUG=1: Performance metrics only
  // DEBUG=2: Basic execution info
  // DEBUG=3: Detailed pipeline stages
  // DEBUG=4: Very verbose (includes forwarding and hazards)

endmodule
