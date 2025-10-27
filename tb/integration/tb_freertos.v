// tb_freertos.v - Testbench for FreeRTOS on RV1 SoC
// Tests FreeRTOS multitasking with UART output monitoring
// Author: RV1 Project
// Date: 2025-10-27

`timescale 1ns/1ps

module tb_freertos;

  // Parameters - FreeRTOS needs more memory and time
  parameter CLK_PERIOD = 20;          // 50 MHz clock (matches FreeRTOS config)
  parameter TIMEOUT_CYCLES = 50000;   // 50k cycles = 1ms @ 50MHz (start with shorter timeout for debugging)

  // Memory sizes for FreeRTOS (from linker script)
  parameter IMEM_SIZE = 65536;  // 64KB for code
  parameter DMEM_SIZE = 1048576; // 1MB for data/BSS/heap/stack

  // DUT signals
  reg  clk;
  reg  reset_n;
  wire [31:0] pc;
  wire [31:0] instruction;

  // UART signals
  wire       uart_tx_valid;
  wire [7:0] uart_tx_data;
  reg        uart_tx_ready;
  reg        uart_rx_valid;
  reg  [7:0] uart_rx_data;
  wire       uart_rx_ready;

  // FreeRTOS binary
  parameter MEM_FILE = "software/freertos/build/freertos-rv1.hex";

  // Instantiate SoC with FreeRTOS memory configuration
  rv_soc #(
    .XLEN(32),
    .RESET_VECTOR(32'h00000000),  // FreeRTOS starts at 0x0 (start.S)
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

  // Clock generation - 50 MHz
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // Test sequence
  initial begin
    // Initialize
    reset_n = 0;
    uart_tx_ready = 1;  // UART TX consumer always ready
    uart_rx_valid = 0;
    uart_rx_data = 0;

    // Hold reset for 10 cycles
    repeat (10) @(posedge clk);
    reset_n = 1;

    $display("FreeRTOS released from reset at cycle %0d", cycle_count);

    // Let FreeRTOS boot and run
    repeat (TIMEOUT_CYCLES) @(posedge clk);

    $display("");
    $display("========================================");
    $display("SIMULATION TIMEOUT");
    $display("========================================");
    $display("  Cycles: %0d", cycle_count);
    $display("  Time: %0d ms", (cycle_count * CLK_PERIOD) / 1000000);
    $display("  Last PC: 0x%08h", pc);
    $display("========================================");
    $finish;
  end

  // Cycle counter
  integer cycle_count;
  initial cycle_count = 0;
  always @(posedge clk) begin
    if (reset_n) begin
      cycle_count = cycle_count + 1;
      if (cycle_count == 1 || cycle_count == 2 || cycle_count == 10) begin
        $display("[COUNTER] Cycle %0d", cycle_count);
      end
    end
  end

  // Simulation control
  initial begin
    $dumpfile("tb_freertos.vcd");
    $dumpvars(0, tb_freertos);

    $display("========================================");
    $display("RV1 FreeRTOS Testbench");
    $display("========================================");
    $display("Clock: %0d MHz", 1000 / CLK_PERIOD);
    $display("IMEM: %0d KB", IMEM_SIZE / 1024);
    $display("DMEM: %0d KB", DMEM_SIZE / 1024);
    $display("Binary: %s", MEM_FILE);
    $display("Timeout: %0d cycles (~%0d ms)", TIMEOUT_CYCLES, (TIMEOUT_CYCLES * CLK_PERIOD) / 1000000);
    $display("========================================");
    $display("");
    $display("--- FreeRTOS Boot Log ---");
  end

  // UART TX monitor - FreeRTOS will print messages
  integer uart_char_count;
  initial uart_char_count = 0;

  always @(posedge clk) begin
    if (reset_n && uart_tx_valid && uart_tx_ready) begin
      uart_char_count = uart_char_count + 1;

      // Display characters directly (FreeRTOS uses printf)
      if (uart_tx_data >= 8'h20 && uart_tx_data <= 8'h7E) begin
        $write("%c", uart_tx_data);  // Printable ASCII
      end else if (uart_tx_data == 8'h0A) begin
        $write("\n");                // Newline
      end else if (uart_tx_data == 8'h0D) begin
        // Carriage return - ignore
      end else if (uart_tx_data == 8'h09) begin
        $write("    ");              // Tab -> 4 spaces
      end else begin
        $write("[0x%02h]", uart_tx_data);  // Non-printable
      end
      $fflush();  // Flush output immediately
    end
  end

  // Progress indicator - print every 1k cycles
  always @(posedge clk) begin
    if (reset_n) begin
      if (cycle_count ==1 || cycle_count == 10 || cycle_count == 100) begin
        $display("[DEBUG] Cycle %0d, PC: 0x%08h, Instr: 0x%08h",
                 cycle_count, pc, instruction);
      end
      if ((cycle_count % 1000 == 0) && cycle_count > 0) begin
        $display("[INFO] Cycle %0d, PC: 0x%08h, Instr: 0x%08h, UART chars: %0d",
                 cycle_count, pc, instruction, uart_char_count);
      end
    end
  end

  // Detect infinite loops (PC stuck)
  reg [31:0] prev_pc;
  integer stuck_count;
  initial stuck_count = 0;

  always @(posedge clk) begin
    if (reset_n) begin
      if (pc == prev_pc) begin
        stuck_count = stuck_count + 1;
        if (stuck_count == 100) begin  // Detect early - 100 cycles stuck
          $display("");
          $display("========================================");
          $display("ERROR: PC STUCK AT 0x%08h", pc);
          $display("========================================");
          $display("  Cycles stuck: %0d", stuck_count);
          $display("  Total cycles: %0d", cycle_count);
          $display("  Instruction: 0x%08h", instruction);
          $display("========================================");
          $finish;
        end
      end else begin
        stuck_count = 0;
      end
      prev_pc = pc;
    end
  end

  // Optional: Detect EBREAK for early termination (debug builds)
  always @(posedge clk) begin
    if (reset_n && instruction == 32'h00100073) begin
      $display("");
      $display("========================================");
      $display("EBREAK DETECTED");
      $display("========================================");
      $display("  PC: 0x%08h", pc);
      $display("  Cycles: %0d", cycle_count);
      $display("  UART chars: %0d", uart_char_count);
      $display("========================================");
      $finish;
    end
  end

endmodule
