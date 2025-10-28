// tb_freertos.v - Testbench for FreeRTOS on RV1 SoC
// Tests FreeRTOS multitasking with UART output monitoring
// Author: RV1 Project
// Date: 2025-10-27

`timescale 1ns/1ps

module tb_freertos;

  // Parameters - FreeRTOS needs more memory and time
  parameter CLK_PERIOD = 20;          // 50 MHz clock (matches FreeRTOS config)
  parameter TIMEOUT_CYCLES = 500000;  // 500k cycles = 10ms @ 50MHz (enough for boot + task switching)

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
    $display("  UART chars transmitted: %0d", uart_char_count);
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

      if (uart_char_count == 1) begin
        $display("[UART] First character transmitted at cycle %0d", cycle_count);
        $display("========================================");
        $display("UART OUTPUT:");
        $display("========================================");
      end

      // Log each character with details
      if (uart_tx_data >= 8'h20 && uart_tx_data <= 8'h7E) begin
        $display("[UART-CHAR] Cycle %0d: 0x%02h '%c'", cycle_count, uart_tx_data, uart_tx_data);
      end else if (uart_tx_data == 8'h0A) begin
        $display("[UART-CHAR] Cycle %0d: 0x%02h <LF>", cycle_count, uart_tx_data);
      end else if (uart_tx_data == 8'h0D) begin
        $display("[UART-CHAR] Cycle %0d: 0x%02h <CR>", cycle_count, uart_tx_data);
      end else if (uart_tx_data == 8'h09) begin
        $display("[UART-CHAR] Cycle %0d: 0x%02h <TAB>", cycle_count, uart_tx_data);
      end else begin
        $display("[UART-CHAR] Cycle %0d: 0x%02h <non-printable>", cycle_count, uart_tx_data);
      end
    end
  end

  // ========================================
  // Session 25: UART Debug Instrumentation
  // ========================================
  // Monitor UART writes, function calls, and exceptions

  // UART bus monitor - COMMENTED OUT FOR SPEED
  //always @(posedge clk) begin
  //  if (reset_n && DUT.uart_req_valid) begin
  //    if (DUT.uart_req_we) begin
  //      // UART write detected
  //      $display("[UART-BUS] Write to offset 0x%01h = 0x%02h at cycle %0d (PC: 0x%08h)",
  //               DUT.uart_req_addr, DUT.uart_req_wdata, cycle_count, pc);
  //    end else begin
  //      // UART read detected
  //      $display("[UART-BUS] Read from offset 0x%01h = 0x%02h at cycle %0d (PC: 0x%08h)",
  //               DUT.uart_req_addr, DUT.uart_req_rdata, cycle_count, pc);
  //    end
  //  end
  //end

  // Function entry tracking - DISABLED FOR SPEED
  //reg uart_init_entered;
  //reg printf_entered;
  //reg puts_entered;
  //initial uart_init_entered = 0;
  //initial printf_entered = 0;
  //initial puts_entered = 0;
  //
  //always @(posedge clk) begin
  //  if (reset_n) begin
  //    // uart_init() entry: 0x23d6
  //    if (!uart_init_entered && pc == 32'h000023d6) begin
  //      uart_init_entered = 1;
  //      $display("[FUNC-ENTRY] uart_init() entered at cycle %0d", cycle_count);
  //    end
  //
  //    // puts() entry: 0x2610
  //    if (pc == 32'h00002610) begin
  //      if (!puts_entered) begin
  //        puts_entered = 1;
  //        $display("[FUNC-ENTRY] puts() FIRST CALL at cycle %0d", cycle_count);
  //      end
  //      $display("[FUNC-CALL] puts() called at cycle %0d", cycle_count);
  //    end
  //
  //    // printf() entry: 0x25ea
  //    if (pc == 32'h000025ea) begin
  //      if (!printf_entered) begin
  //        printf_entered = 1;
  //        $display("[FUNC-ENTRY] printf() FIRST CALL at cycle %0d", cycle_count);
  //      end
  //      $display("[FUNC-CALL] printf() called at cycle %0d", cycle_count);
  //    end
  //
  //    // Track key milestones in main()
  //    if (pc == 32'h000022a4) begin
  //      $display("[MAIN] Returned from uart_init() at cycle %0d", cycle_count);
  //    end
  //  end
  //end

  // Memory write monitoring (cycles 120-155) - Session 27 debug - DISABLED FOR SPEED
  //always @(posedge clk) begin
  //  if (reset_n && cycle_count >= 120 && cycle_count <= 155) begin
  //    // Monitor DMEM writes (stack operations)
  //    if (DUT.core.exmem_mem_write && DUT.core.exmem_valid) begin
  //      $display("[MEM-WRITE] Cycle %0d: addr=0x%08h, data=0x%08h, PC=0x%08h",
  //               cycle_count, DUT.core.exmem_alu_result, DUT.core.exmem_mem_write_data, DUT.core.exmem_pc);
  //    end
  //    // Monitor DMEM reads (stack loads)
  //    if (DUT.core.exmem_mem_read && DUT.core.exmem_valid) begin
  //      $display("[MEM-READ] Cycle %0d: addr=0x%08h, PC=0x%08h",
  //               cycle_count, DUT.core.exmem_alu_result, DUT.core.exmem_pc);
  //    end
  //    // Monitor WB stage loads to x1 (ra)
  //    if (DUT.core.memwb_reg_write && DUT.core.memwb_rd_addr == 5'd1 && DUT.core.memwb_wb_sel == 3'b001) begin
  //      $display("[LOAD-RA] Cycle %0d: loaded ra=0x%08h from memory",
  //               cycle_count, DUT.core.wb_data);
  //    end
  //  end
  //end

  // Exception/trap monitoring
  reg [63:0] prev_mcause;
  reg [31:0] prev_mepc;
  initial prev_mcause = 0;
  initial prev_mepc = 0;

  always @(posedge clk) begin
    if (reset_n) begin
      // Monitor CSRs for trap entry
      if (DUT.core.csr_file_inst.mcause_r != prev_mcause || DUT.core.csr_file_inst.mepc_r != prev_mepc) begin
        if (DUT.core.csr_file_inst.mcause_r != 0) begin
          $display("[TRAP] Exception/Interrupt detected at cycle %0d", cycle_count);
          $display("       mcause = 0x%016h (interrupt=%b, code=%0d)",
                   DUT.core.csr_file_inst.mcause_r,
                   DUT.core.csr_file_inst.mcause_r[63],
                   DUT.core.csr_file_inst.mcause_r[3:0]);
          $display("       mepc   = 0x%08h", DUT.core.csr_file_inst.mepc_r);
          $display("       mtval  = 0x%08h (from ifid_instruction)", DUT.core.csr_file_inst.mtval_r);
          $display("       PC     = 0x%08h (trap handler)", pc);
          $display("       ifid_instruction = 0x%08h (ID stage)", DUT.core.ifid_instruction);
          $display("       if_instruction_raw = 0x%08h (IF stage raw)", DUT.core.if_instruction_raw);
          $display("       if_instruction = 0x%08h (IF stage final)", DUT.core.if_instruction);
        end
        prev_mcause = DUT.core.csr_file_inst.mcause_r;
        prev_mepc = DUT.core.csr_file_inst.mepc_r;
      end
    end
  end

  // Progress indicator - print every 10k cycles and track key milestones
  reg main_reached;
  reg scheduler_reached;
  initial main_reached = 0;
  initial scheduler_reached = 0;

  always @(posedge clk) begin
    if (reset_n) begin
      // Print every 1000 cycles to track progress
      if (cycle_count % 1000 == 0) begin
        $display("[COUNTER] Cycle %0d, PC: 0x%08h", cycle_count, pc);
      end

      if (cycle_count ==1 || cycle_count == 10 || cycle_count == 100) begin
        $display("[DEBUG] Cycle %0d, PC: 0x%08h, Instr: 0x%08h",
                 cycle_count, pc, instruction);
      end

      // Detailed trace around expected trap cycles (600-650 per Session 28) - DISABLED FOR SPEED
      //if (cycle_count >= 600 && cycle_count <= 650) begin
      //  $display("[PC-TRACE] Cycle %0d: PC=0x%08h, Instr=0x%08h",
      //           cycle_count, pc, instruction);
      //end

      // Super detailed pipeline trace around cycle 605-610 - DISABLED FOR SPEED
      if (0 && cycle_count >= 603 && cycle_count <= 612) begin
        $display("[PIPELINE] Cycle %0d:", cycle_count);
        $display("  IF: PC=0x%08h, raw=0x%08h, final=0x%08h, compressed=%b",
                 DUT.core.pc_current, DUT.core.if_instruction_raw,
                 DUT.core.if_instruction, DUT.core.if_is_compressed);
        $display("  ID: instruction=0x%08h, valid=%b",
                 DUT.core.ifid_instruction, DUT.core.ifid_valid);
        $display("  EX: instruction=0x%08h, valid=%b",
                 DUT.core.idex_instruction, DUT.core.idex_valid);
        $display("  Exception: code=%0d, gated=%b",
                 DUT.core.exception_code, DUT.core.exception_gated);
      end

      // Detailed trace around puts() call (cycles 117-125) - COMMENTED OUT FOR SPEED
      //if (cycle_count >= 117 && cycle_count <= 125) begin
      //  $display("[PC-TRACE] Cycle %0d: PC=0x%08h, Instr=0x%08h",
      //           cycle_count, pc, instruction);
      //end

      // Trace link register writes - COMMENTED OUT FOR SPEED
      //if (cycle_count >= 117 && cycle_count <= 160) begin
      //  if (DUT.core.int_reg_write_enable && DUT.core.memwb_rd_addr == 5'd1) begin
      //    $display("[LINK-REG] Cycle %0d: Writing ra(x1) = 0x%08h (wb_sel=%b, wen=%b, valid=%b)",
      //             cycle_count, DUT.core.wb_data, DUT.core.memwb_wb_sel,
      //             DUT.core.int_reg_write_enable, DUT.core.memwb_valid);
      //  end
      //end

      // Trace register x1 (ra) value changes - COMMENTED OUT FOR SPEED
      //if (cycle_count >= 120 && cycle_count <= 130) begin
      //  $display("[REG-ra] Cycle %0d: ra(x1) value = 0x%08h",
      //           cycle_count, DUT.core.regfile.registers[1]);
      //end

      // Detect main() reached (address 0x229C)
      if (!main_reached && pc == 32'h0000229c) begin
        main_reached = 1;
        $display("[MILESTONE] main() reached at cycle %0d", cycle_count);
      end

      // Detect vTaskStartScheduler() (would need to know address - using approximate)
      if (!scheduler_reached && pc >= 32'h00002000 && pc < 32'h00003000 && main_reached) begin
        if (cycle_count > 1000) begin  // Make sure we're past early boot
          scheduler_reached = 1;
          $display("[MILESTONE] Scheduler starting around cycle %0d", cycle_count);
        end
      end

      if ((cycle_count % 10000 == 0) && cycle_count > 0) begin
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

  // ========================================
  // BSS Fast-Clear Accelerator (Simulation Only)
  // ========================================
  // Detects the BSS zero loop pattern and accelerates memory clearing
  // Pattern from start.S:
  //   bss_zero_loop:
  //     bge t0, t1, bss_zero_done
  //     sw zero, 0(t0)
  //     addi t0, t0, 4
  //     j bss_zero_loop
  //
  // This is purely a simulation optimization - the hardware is not modified

  `ifdef ENABLE_BSS_FAST_CLEAR

  // BSS loop detection state
  reg bss_loop_active;
  reg [31:0] bss_start_addr;
  reg [31:0] bss_end_addr;
  integer bss_cleared_bytes;

  initial begin
    bss_loop_active = 0;
    bss_start_addr = 0;
    bss_end_addr = 0;
    bss_cleared_bytes = 0;
  end

  // Detect entry to BSS loop (PC = 0x32 for FreeRTOS)
  // Look for: bge t0, t1, <skip> at PC 0x32
  always @(posedge clk) begin
    if (reset_n && !bss_loop_active) begin
      // Detect BSS loop entry: PC=0x32, instruction is BGE
      if (pc == 32'h00000032 && instruction[6:0] == 7'b1100011 && instruction[14:12] == 3'b101) begin
        // Extract register numbers: t0=x5, t1=x6 from BGE instruction
        // BGE rs1, rs2, offset: imm[12|10:5] rs2 rs1 101 imm[4:1|11] 1100011

        // Read t0 (x5) and t1 (x6) from core registers
        // Hierarchy: DUT.core.regfile.registers (not regs)
        bss_start_addr = DUT.core.regfile.registers[5];  // t0 = start address
        bss_end_addr = DUT.core.regfile.registers[6];    // t1 = end address

        // Validate addresses (BSS should be in DMEM: 0x8000_0000 - 0x8010_0000)
        if (bss_start_addr >= 32'h80000000 && bss_start_addr < 32'h80100000 &&
            bss_end_addr >= 32'h80000000 && bss_end_addr < 32'h80100000 &&
            bss_end_addr > bss_start_addr) begin

          bss_loop_active = 1;
          bss_cleared_bytes = bss_end_addr - bss_start_addr;

          $display("");
          $display("========================================");
          $display("BSS FAST-CLEAR ACCELERATOR ACTIVATED");
          $display("========================================");
          $display("  Start address: 0x%08h", bss_start_addr);
          $display("  End address:   0x%08h", bss_end_addr);
          $display("  Size:          %0d KB (%0d bytes)", bss_cleared_bytes / 1024, bss_cleared_bytes);
          $display("  Normal cycles: ~%0d", bss_cleared_bytes / 4 * 3);  // ~3 cycles per store
          $display("  Fast-clear:    1 cycle");
          $display("========================================");
          $display("");
        end
      end
    end
  end

  // Execute fast BSS clear in one cycle
  integer bss_addr;
  integer bss_mem_idx;

  always @(posedge clk) begin
    if (reset_n && bss_loop_active) begin
      // Clear entire BSS region in one cycle
      // Memory is byte-addressable: DUT.dmem_adapter.dmem.mem[byte_index]
      for (bss_addr = bss_start_addr; bss_addr < bss_end_addr; bss_addr = bss_addr + 4) begin
        bss_mem_idx = (bss_addr - 32'h80000000);  // Convert to DMEM-relative address
        DUT.dmem_adapter.dmem.mem[bss_mem_idx]     = 8'h00;
        DUT.dmem_adapter.dmem.mem[bss_mem_idx + 1] = 8'h00;
        DUT.dmem_adapter.dmem.mem[bss_mem_idx + 2] = 8'h00;
        DUT.dmem_adapter.dmem.mem[bss_mem_idx + 3] = 8'h00;
      end

      // Update t0 register to point past BSS (simulates loop completion)
      DUT.core.regfile.registers[5] = bss_end_addr;

      // Force PC to jump to bss_zero_done (address 0x3e)
      // Hierarchy: DUT.core.pc_inst.pc_current
      force DUT.core.pc_inst.pc_current = 32'h0000003e;
      #1;  // Hold for 1 time unit
      release DUT.core.pc_inst.pc_current;

      $display("[BSS-ACCEL] Cleared %0d KB in 1 cycle (saved ~%0d cycles)",
               bss_cleared_bytes / 1024, (bss_cleared_bytes / 4 * 3) - 1);

      bss_loop_active = 0;  // One-shot acceleration
    end
  end

  `endif // ENABLE_BSS_FAST_CLEAR

endmodule
