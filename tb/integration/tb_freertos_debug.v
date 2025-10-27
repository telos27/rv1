// tb_freertos_debug.v - Minimal testbench to debug FreeRTOS boot hang at PC 0x14
// Focus: First 100 cycles with detailed PC and instruction trace
// Author: RV1 Project
// Date: 2025-10-27

`timescale 1ns/1ps

module tb_freertos_debug;

  // Parameters
  parameter CLK_PERIOD = 20;          // 50 MHz clock
  parameter MAX_CYCLES = 5000;        // 5000 cycles to let boot sequence complete

  // Memory sizes
  parameter IMEM_SIZE = 65536;        // 64KB
  parameter DMEM_SIZE = 1048576;      // 1MB

  // DUT signals
  reg  clk;
  reg  reset_n;
  wire [31:0] pc;
  wire [31:0] instruction;

  // UART signals (minimal - not important for boot debug)
  wire       uart_tx_valid;
  wire [7:0] uart_tx_data;
  reg        uart_tx_ready;
  reg        uart_rx_valid;
  reg  [7:0] uart_rx_data;
  wire       uart_rx_ready;

  // FreeRTOS binary
  parameter MEM_FILE = "software/freertos/build/freertos-rv1.hex";

  // Instantiate SoC
  rv_soc #(
    .XLEN(32),
    .RESET_VECTOR(32'h00000000),
    .IMEM_SIZE(IMEM_SIZE),
    .DMEM_SIZE(DMEM_SIZE),
    .MEM_FILE(MEM_FILE),
    .NUM_HARTS(1)
  ) DUT (
    .clk(clk),
    .reset_n(reset_n),
    .uart_tx_valid(uart_tx_valid),
    .uart_tx_data(uart_tx_data),
    .uart_tx_ready(uart_tx_ready),
    .uart_rx_valid(uart_rx_valid),
    .uart_rx_data(uart_rx_data),
    .uart_rx_ready(uart_rx_ready),
    .pc_out(pc),
    .instr_out(instruction)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // Cycle counter
  integer cycle_count;
  initial cycle_count = 0;

  // Test sequence
  initial begin
    // VCD for waveform analysis
    $dumpfile("tb_freertos_debug.vcd");
    $dumpvars(0, tb_freertos_debug);

    $display("========================================");
    $display("FreeRTOS Boot Debug Testbench");
    $display("========================================");
    $display("Target: Debug PC stuck at 0x14");
    $display("Binary: %s", MEM_FILE);
    $display("Max cycles: %0d", MAX_CYCLES);
    $display("========================================");
    $display("");

    // Initialize
    reset_n = 0;
    uart_tx_ready = 1;
    uart_rx_valid = 0;
    uart_rx_data = 0;

    // Hold reset for 5 cycles
    repeat (5) @(posedge clk);
    reset_n = 1;

    $display("Released from reset at cycle %0d", cycle_count);
    $display("");
    $display("PC Trace with CSR values (first 20 cycles with details):");
    $display("Cycle | PC       | Instruction | Decoded                  | CSRs");
    $display("------|----------|-------------|--------------------------|--------------------------------");

    // Run for MAX_CYCLES and auto-terminate
    repeat (MAX_CYCLES) @(posedge clk);

    $display("");
    $display("========================================");
    $display("SIMULATION COMPLETE");
    $display("========================================");
    $display("Total cycles: %0d", cycle_count);
    $display("Final PC: 0x%08h", pc);
    $display("========================================");
    $finish;
  end

  // PC trace on every cycle
  reg [31:0] prev_pc;
  initial prev_pc = 32'hFFFFFFFF;

  // Access core CSRs for debugging
  wire [31:0] mstatus_val = DUT.core.csr_file_inst.mstatus_r;
  wire [31:0] mtvec_val = DUT.core.csr_file_inst.mtvec_r;
  wire [31:0] mcause_val = DUT.core.csr_file_inst.mcause_r;
  wire [31:0] mepc_val = DUT.core.csr_file_inst.mepc_r;
  wire trap_taken = DUT.core.csr_file_inst.trap_entry;
  wire illegal_csr = DUT.core.csr_file_inst.illegal_csr;
  wire [11:0] csr_addr_val = DUT.core.csr_file_inst.csr_addr;
  wire [4:0] trap_cause = DUT.core.csr_file_inst.trap_cause;
  wire exception_gated = DUT.core.exception_gated;
  wire sync_exception = DUT.core.sync_exception;
  wire interrupt_pending = DUT.core.interrupt_pending;
  wire [4:0] sync_exception_code = DUT.core.sync_exception_code;
  wire [4:0] interrupt_cause = DUT.core.interrupt_cause;

  // Exception unit internal signals
  wire exc_if_misaligned = DUT.core.exception_unit_inst.if_inst_misaligned;
  wire exc_id_ebreak = DUT.core.exception_unit_inst.id_ebreak_exc;
  wire exc_id_ecall = DUT.core.exception_unit_inst.id_ecall_exc;
  wire exc_id_illegal = DUT.core.exception_unit_inst.id_illegal_combined;
  wire exc_mem_load_mis = DUT.core.exception_unit_inst.mem_load_misaligned;
  wire exc_mem_store_mis = DUT.core.exception_unit_inst.mem_store_misaligned;

  always @(posedge clk) begin
    if (reset_n) begin
      cycle_count = cycle_count + 1;

      // Print every cycle for first 20 with CSR info
      if (cycle_count <= 20) begin
        $display("%5d | %08h | %08h | %-24s | mstatus=%08h mtvec=%08h",
                 cycle_count, pc, instruction, decode_instr(instruction),
                 mstatus_val, mtvec_val);

        // Highlight traps
        if (trap_taken) begin
          $display("      *** TRAP TAKEN: cause=%0d sync_exc=%b (code=%0d) intr=%b (cause=%0d) ***",
                   trap_cause, sync_exception, sync_exception_code,
                   interrupt_pending, interrupt_cause);
          $display("          Exception sources: if_mis=%b ebreak=%b ecall=%b illegal=%b load_mis=%b store_mis=%b",
                   exc_if_misaligned, exc_id_ebreak, exc_id_ecall, exc_id_illegal,
                   exc_mem_load_mis, exc_mem_store_mis);
          $display("          mcause=%08h mepc=%08h mtvec=%08h",
                   mcause_val, mepc_val, mtvec_val);
        end

        // Highlight illegal CSR access
        if (illegal_csr) begin
          $display("      *** ILLEGAL CSR ACCESS: addr=0x%03h ***", csr_addr_val);
        end
      end
      // After cycle 20, only print on PC change or trap
      else if (pc != prev_pc || trap_taken) begin
        $display("%5d | %08h | %08h | %s",
                 cycle_count, pc, instruction, decode_instr(instruction));
        if (trap_taken) begin
          $display("      *** TRAP: mcause=%08h mepc=%08h ***",
                   mcause_val, mepc_val);
        end
      end

      prev_pc = pc;

      // Detect stuck PC
      if (cycle_count > 20 && pc == prev_pc) begin
        $display("");
        $display("*** WARNING: PC stuck at 0x%08h for multiple cycles ***", pc);
      end
    end
  end

  // Simple instruction decoder for readability
  function [200*8-1:0] decode_instr;
    input [31:0] instr;
    reg [6:0] opcode;
    reg [4:0] rd, rs1, rs2;
    reg [2:0] funct3;
    reg [6:0] funct7;
    begin
      opcode = instr[6:0];
      rd = instr[11:7];
      rs1 = instr[19:15];
      rs2 = instr[24:20];
      funct3 = instr[14:12];
      funct7 = instr[31:25];

      case (opcode)
        7'b0110011: begin // R-type
          if (funct7 == 7'b0000000 && funct3 == 3'b000) decode_instr = "ADD";
          else if (funct7 == 7'b0100000 && funct3 == 3'b000) decode_instr = "SUB";
          else if (funct3 == 3'b111) decode_instr = "AND";
          else if (funct3 == 3'b110) decode_instr = "OR";
          else decode_instr = "R-type";
        end
        7'b0010011: begin // I-type (immediate)
          if (funct3 == 3'b000) decode_instr = "ADDI";
          else if (funct3 == 3'b111) decode_instr = "ANDI";
          else if (funct3 == 3'b110) decode_instr = "ORI";
          else decode_instr = "I-type";
        end
        7'b0000011: decode_instr = "LOAD"; // LW/LH/LB
        7'b0100011: decode_instr = "STORE"; // SW/SH/SB
        7'b1100011: decode_instr = "BRANCH"; // BEQ/BNE/etc
        7'b1101111: decode_instr = "JAL";
        7'b1100111: decode_instr = "JALR";
        7'b0110111: decode_instr = "LUI";
        7'b0010111: decode_instr = "AUIPC";
        7'b1110011: begin // SYSTEM
          if (funct3 == 3'b001) decode_instr = "CSRRW";
          else if (funct3 == 3'b010) decode_instr = "CSRRS";
          else if (funct3 == 3'b011) decode_instr = "CSRRC";
          else if (funct3 == 3'b101) decode_instr = "CSRRWI";
          else if (funct3 == 3'b110) decode_instr = "CSRRSI";
          else if (funct3 == 3'b111) decode_instr = "CSRRCI";
          else if (instr[31:20] == 12'h000) decode_instr = "ECALL";
          else if (instr[31:20] == 12'h001) decode_instr = "EBREAK";
          else if (instr[31:20] == 12'h302) decode_instr = "MRET";
          else decode_instr = "SYSTEM";
        end
        default: decode_instr = "UNKNOWN";
      endcase
    end
  endfunction

endmodule
