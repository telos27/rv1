// tb_freertos.v - Testbench for FreeRTOS on RV1 SoC
// Tests FreeRTOS multitasking with UART output monitoring
// Author: RV1 Project
// Date: 2025-10-27

`timescale 1ns/1ps

module tb_freertos;

  // Parameters - FreeRTOS needs more memory and time
  parameter CLK_PERIOD = 20;          // 50 MHz clock (matches FreeRTOS config)
  parameter TIMEOUT_CYCLES = 5000000;  // 5M cycles = 100ms @ 50MHz (enough for minimal test)

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
  // Session 59: Unified Debug Trace Infrastructure
  // ========================================
  debug_trace #(
    .XLEN(32),
    .PC_HISTORY_DEPTH(128),
    .MAX_WATCHPOINTS(16)
  ) debug (
    .clk(clk),
    .rst_n(reset_n),

    // CPU state
    .pc(pc),
    .pc_next(DUT.core.pc_next),
    .instruction(instruction),
    .valid_instruction(DUT.core.memwb_valid),

    // Register file access
    .x1_ra(DUT.core.regfile.registers[1]),
    .x2_sp(DUT.core.regfile.registers[2]),
    .x10_a0(DUT.core.regfile.registers[10]),
    .x11_a1(DUT.core.regfile.registers[11]),
    .x12_a2(DUT.core.regfile.registers[12]),
    .x13_a3(DUT.core.regfile.registers[13]),
    .x14_a4(DUT.core.regfile.registers[14]),
    .x15_a5(DUT.core.regfile.registers[15]),
    .x16_a6(DUT.core.regfile.registers[16]),
    .x17_a7(DUT.core.regfile.registers[17]),

    // Memory access monitoring
    .mem_valid(DUT.core.exmem_valid && (DUT.core.exmem_mem_read || DUT.core.exmem_mem_write)),
    .mem_write(DUT.core.exmem_mem_write),
    .mem_addr(DUT.core.exmem_alu_result),
    .mem_wdata(DUT.core.exmem_mem_write_data),
    .mem_rdata(DUT.core.mem_read_data),
    .mem_wstrb(4'b1111),  // Full word for now

    // Exception/interrupt info
    .trap_taken(DUT.core.csr_file_inst.mcause_r != prev_mcause),
    .trap_pc(pc),
    .trap_cause(DUT.core.csr_file_inst.mcause_r),

    // Control
    .enable_trace(1'b0),    // Disabled for speed - enable for debugging
    .trace_start_pc(32'h0),  // Trace from start
    .trace_end_pc(32'h0)     // Never stop
  );

  // Configure debug watchpoints for queue debugging
  initial begin
    #100;  // Wait for reset
    // Watchpoint on queue structure at 0x800004b8 (where queueLength gets corrupted)
    debug.set_watchpoint(0, 32'h800004b8, 1);  // Watch writes to queue address
    debug.set_watchpoint(1, 32'h800004c8, 1);  // Watch writes to queueLength field (offset +60)
    $display("[DEBUG-INIT] Watchpoints configured:");
    $display("  WP0: 0x800004b8 (queue base, WRITE)");
    $display("  WP1: 0x800004c8 (queueLength field, WRITE)");
  end

  // Helper tasks to display debug info on demand
  task display_debug_state;
    begin
      debug.display_registers();
      debug.display_call_stack();
      debug.display_pc_history(20);
    end
  endtask

  // ========================================
  // Session 25: UART Debug Instrumentation
  // ========================================
  // Monitor UART writes, function calls, and exceptions

  // UART bus monitor - Track bus-level UART writes with PC
  reg prev_uart_bus_write;
  initial prev_uart_bus_write = 0;

  always @(posedge clk) begin
    if (reset_n) begin
      // Detect UART write to THR (offset 0)
      if (DUT.uart_req_valid && DUT.uart_req_we && DUT.uart_req_addr == 8'h00 && !prev_uart_bus_write) begin
        // Display character and PC
        if (DUT.uart_req_wdata >= 8'h20 && DUT.uart_req_wdata <= 8'h7E) begin
          $display("[UART-BUS-WRITE] Cycle %0d: PC=0x%08h data=0x%02h '%c'",
                   cycle_count, DUT.core.exmem_pc, DUT.uart_req_wdata, DUT.uart_req_wdata);
        end else if (DUT.uart_req_wdata == 8'h0A) begin
          $display("[UART-BUS-WRITE] Cycle %0d: PC=0x%08h data=0x%02h <LF>",
                   cycle_count, DUT.core.exmem_pc, DUT.uart_req_wdata);
        end else if (DUT.uart_req_wdata == 8'h0D) begin
          $display("[UART-BUS-WRITE] Cycle %0d: PC=0x%08h data=0x%02h <CR>",
                   cycle_count, DUT.core.exmem_pc, DUT.uart_req_wdata);
        end else begin
          $display("[UART-BUS-WRITE] Cycle %0d: PC=0x%08h data=0x%02h",
                   cycle_count, DUT.core.exmem_pc, DUT.uart_req_wdata);
        end
      end
      prev_uart_bus_write = DUT.uart_req_valid && DUT.uart_req_we && DUT.uart_req_addr == 8'h00;
    end
  end

  // Memory write watchpoint - Track writes to Task B's stack (sp=0x80000864)
  // Watch ra location: sp+4 = 0x80000868
  always @(posedge clk) begin
    if (reset_n && DUT.core.exmem_mem_write && DUT.core.exmem_valid) begin
      // Check if writing to address range 0x80000860-0x80000880 (Task B stack)
      if (DUT.core.exmem_alu_result >= 32'h80000860 && DUT.core.exmem_alu_result <= 32'h80000880) begin
        $display("[STACK-WRITE] Cycle %0d: PC=0x%08h writes 0x%08h to addr=0x%08h",
                 cycle_count, DUT.core.exmem_pc, DUT.core.exmem_mem_write_data, DUT.core.exmem_alu_result);
      end
    end
  end

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

  // RA register write monitoring - Session 64
  // DISABLED for performance - Session 75 minimal test
  /*
  always @(posedge clk) begin
    if (reset_n && cycle_count >= 39420 && cycle_count <= 39432) begin
      // Monitor all writes to ra (x1)
      if (DUT.core.memwb_reg_write && DUT.core.memwb_rd_addr == 5'd1) begin
        $display("[RA-WRITE-ATTEMPT] Cycle %0d: Trying to write ra=0x%08h", cycle_count, DUT.core.wb_data);
        $display("       memwb_valid   = %b (comes from exmem_valid && !exception_from_mem && !hold_exmem)", DUT.core.memwb_valid);
        $display("       int_reg_write_en = %b", DUT.core.int_reg_write_enable);
        $display("       --- Checking why memwb_valid=0 ---");
        $display("       exmem_valid      = %b (was JAL valid in MEM stage?)", DUT.core.exmem_valid);
        $display("       exception_from_mem = %b (did JAL cause exception?)", DUT.core.exception_from_mem);
        $display("       hold_exmem       = %b (was EXMEM held?)", DUT.core.hold_exmem);
        if (DUT.core.int_reg_write_enable) begin
          $display("       ✅ WRITE ENABLED - ra will be updated");
        end else begin
          $display("       ❌ WRITE BLOCKED - ra will NOT be updated!");
        end
      end
      // Monitor forwarding when reading ra
      if (DUT.core.idex_valid && DUT.core.idex_rs1_addr == 5'd1) begin
        $display("[RA-FORWARD] Cycle %0d: IDEX reading rs1=x1 (ra)", cycle_count);
        $display("       idex_PC       = 0x%08h", DUT.core.idex_pc);
        $display("       idex_instr    = 0x%08h", DUT.core.idex_instruction);
        $display("       idex_rs1_data = 0x%08h (from IDEX pipe reg)", DUT.core.idex_rs1_data);
        $display("       forward_a     = %b", DUT.core.forward_a);
        $display("       memwb_rd      = x%0d", DUT.core.memwb_rd_addr);
        $display("       memwb_reg_wr  = %b", DUT.core.memwb_reg_write);
        $display("       memwb_valid   = %b", DUT.core.memwb_valid);
        $display("       wb_data       = 0x%08h", DUT.core.wb_data);
        $display("       ex_alu_op_a_fwd = 0x%08h (after forward)", DUT.core.ex_alu_operand_a_forwarded);
        $display("");
      end
      // Monitor IDEX pipeline register every cycle
      $display("[IDEX-STATE] Cycle %0d: PC=0x%08h idex_PC=0x%08h idex_instr=0x%08h idex_valid=%b idex_rs1=%0d",
               cycle_count, DUT.core.pc_current, DUT.core.idex_pc, DUT.core.idex_instruction,
               DUT.core.idex_valid, DUT.core.idex_rs1_addr);
      // Monitor flush signals
      if (DUT.core.flush_idex || DUT.core.ex_take_branch) begin
        $display("       [FLUSH] flush_idex=%b ex_take_branch=%b trap_flush=%b",
                 DUT.core.flush_idex, DUT.core.ex_take_branch, DUT.core.trap_flush);
      end
      // Monitor ra value in register file every cycle
      $display("[RA-VALUE] Cycle %0d: ra=0x%08h",
               cycle_count, DUT.core.regfile.registers[1]);
    end
  end
  */

  // JALR debug monitoring - Session 64
  // DISABLED for performance - Session 75 minimal test
  /*
  always @(posedge clk) begin
    if (reset_n && cycle_count >= 39480 && cycle_count <= 39495) begin
      // Monitor JALR instruction in ID/EX stage
      if (DUT.core.idex_valid && DUT.core.idex_jump && DUT.core.idex_opcode == 7'b1100111) begin
        $display("[JALR-DEBUG] Cycle %0d: JALR detected in IDEX", cycle_count);
        $display("       IDEX PC         = 0x%08h", DUT.core.idex_pc);
        $display("       IDEX instr      = 0x%08h", DUT.core.idex_instruction);
        $display("       idex_jump       = %b", DUT.core.idex_jump);
        $display("       idex_branch     = %b", DUT.core.idex_branch);
        $display("       idex_rs1        = x%0d", DUT.core.idex_rs1_addr);
        $display("       idex_rs1_data   = 0x%08h", DUT.core.idex_rs1_data);
        $display("       idex_imm        = 0x%08h", DUT.core.idex_imm);
        $display("       ex_alu_op_a_fwd = 0x%08h (forwarded rs1)", DUT.core.ex_alu_operand_a_forwarded);
        $display("       ex_jump_target  = 0x%08h (rs1+imm)", DUT.core.ex_jump_target);
        $display("       ex_take_branch  = %b", DUT.core.ex_take_branch);
        $display("       pc_next         = 0x%08h", DUT.core.pc_next);
        $display("       trap_flush      = %b", DUT.core.trap_flush);
        $display("       mret_flush      = %b", DUT.core.mret_flush);
        $display("       stall_pc        = %b", DUT.core.stall_pc);
        $display("");
      end
    end
  end
  */

  // Enhanced exception monitoring - capture state BEFORE pipeline flush
  reg exception_detected_prev;
  initial exception_detected_prev = 0;

  always @(posedge clk) begin
    if (reset_n) begin
      // Detect exception at the moment it occurs (before CSR update and pipeline flush)
      if (DUT.core.exception_gated && !exception_detected_prev) begin
        $display("");
        $display("[EXCEPTION-DETECTION] *** Exception detected at cycle %0d (BEFORE flush) ***", cycle_count);
        $display("       PC (current)      = 0x%08h", DUT.core.pc_current);
        $display("       IFID PC           = 0x%08h", DUT.core.ifid_pc);
        $display("       IFID instruction  = 0x%08h (raw in IFID)", DUT.core.ifid_instruction);
        $display("       IDEX PC           = 0x%08h", DUT.core.idex_pc);
        $display("       IDEX instruction  = 0x%08h (in IDEX - used for mtval)", DUT.core.idex_instruction);
        $display("       IDEX valid        = %b", DUT.core.idex_valid);
        $display("       IDEX illegal_inst = %b", DUT.core.idex_illegal_inst);
        $display("       Exception code    = %0d", DUT.core.exception_code);
        $display("       Exception PC      = 0x%08h", DUT.core.exception_pc);
        $display("       Exception val     = 0x%08h", DUT.core.exception_val);
        $display("       MSTATUS           = 0x%08h", DUT.core.csr_file_inst.mstatus_r);
        $display("       MSTATUS.FS        = %b (00=Off, 01=Initial, 10=Clean, 11=Dirty)",
                 DUT.core.csr_file_inst.mstatus_r[14:13]);
        $display("       Control illegal   = %b", DUT.core.id_illegal_inst);
        $display("       Flush signals     = ifid:%b idex:%b", DUT.core.flush_ifid, DUT.core.flush_idex);

        // Decode IDEX instruction for better understanding
        if (DUT.core.idex_instruction[1:0] == 2'b11) begin
          $display("       Instruction type  = 32-bit (non-compressed)");
          $display("       Opcode            = 0b%07b", DUT.core.idex_instruction[6:0]);
        end else begin
          $display("       Instruction type  = 16-bit compressed (bits [1:0] = %b)",
                   DUT.core.idex_instruction[1:0]);
        end
      end
      exception_detected_prev = DUT.core.exception_gated;
    end
  end

  // Exception/trap monitoring (after CSR update)
  reg [63:0] prev_mcause;
  reg [31:0] prev_mepc;
  initial prev_mcause = 0;
  initial prev_mepc = 0;

  always @(posedge clk) begin
    if (reset_n) begin
      // Monitor CSRs for trap entry
      if (DUT.core.csr_file_inst.mcause_r != prev_mcause || DUT.core.csr_file_inst.mepc_r != prev_mepc) begin
        if (DUT.core.csr_file_inst.mcause_r != 0) begin
          $display("");
          $display("[TRAP-CSR-UPDATE] Exception CSRs updated at cycle %0d (AFTER flush)", cycle_count);
          $display("       mcause = 0x%016h (interrupt=%b, code=%0d)",
                   DUT.core.csr_file_inst.mcause_r,
                   DUT.core.csr_file_inst.mcause_r[63],
                   DUT.core.csr_file_inst.mcause_r[3:0]);
          $display("       mepc   = 0x%08h", DUT.core.csr_file_inst.mepc_r);
          $display("       mtval  = 0x%08h (captured instruction)", DUT.core.csr_file_inst.mtval_r);
          $display("       PC     = 0x%08h (trap handler)", pc);
          $display("       ifid_instruction = 0x%08h (ID stage NOW)", DUT.core.ifid_instruction);
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
  reg invalid_pc_warned;
  initial main_reached = 0;
  initial scheduler_reached = 0;
  initial invalid_pc_warned = 0;

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

      // Detect main() reached (address 0x1b6e)
      if (!main_reached && pc == 32'h00001b6e) begin
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

      // Session 63: Track PC progression - sample frequently after cycle 39420
      if (cycle_count == 39500 || cycle_count == 40000 || cycle_count == 41000 ||
          cycle_count == 42000 || cycle_count == 43000 || cycle_count == 44000 ||
          cycle_count == 45000 || cycle_count == 50000 || cycle_count == 60000) begin
        $display("[PC-TRACK] cycle=%0d PC=0x%08h instruction=0x%08h", cycle_count, pc, instruction);
      end

      // Also detect when PC goes outside valid ranges
      if (pc > 32'h90000000 && !invalid_pc_warned) begin
        invalid_pc_warned = 1;
        $display("");
        $display("========================================");
        $display("[PC-INVALID] PC entered invalid memory at cycle %0d", cycle_count);
        $display("  PC = 0x%08h (outside all valid memory ranges!)", pc);
        $display("  Instruction = 0x%08h", instruction);
        $display("  Previous PC samples:");
        $display("========================================");
      end

      // Session 63: Track init_array_loop execution (PC 0xa8-0xc8)
      if (pc >= 32'h000000a8 && pc <= 32'h000000c8) begin
        $display("[INIT-ARRAY] cycle=%0d PC=%h instruction=%h",
                 cycle_count, pc, instruction);
        $display("             t0(x5)=%h t1(x6)=%h t2(x7)=%h",
                 DUT.core.regfile.registers[5], DUT.core.regfile.registers[6], DUT.core.regfile.registers[7]);
      end

      // Session 63: Track sp changes - detect when sp != 0x80040a90
      // DISABLED for performance - Session 75 minimal test
      /*
      if (cycle_count >= 39171 && cycle_count <= 39400) begin
        if (DUT.core.regfile.registers[2] != 32'h80040a90 && DUT.core.regfile.registers[2] != 32'h80040a10) begin
          $display("[SP-CHANGE] cycle=%0d PC=%h sp=%h (changed from 0x80040a90!)",
                   cycle_count, pc, DUT.core.regfile.registers[2]);
        end
      end
      */

      // Session 61/62/63: Track MRET execution and PC corruption (39,370-39,500)
      // DISABLED for performance - Session 75 minimal test
      /*
      if (cycle_count >= 39370 && cycle_count <= 39500) begin
        $display("[MRET-TRACE] cycle=%0d PC=%h ifid_PC=%h idex_PC=%h exmem_PC=%h",
                 cycle_count, pc, DUT.core.ifid_pc, DUT.core.idex_pc, DUT.core.exmem_pc);
        $display("             idex_inst=%h exmem_inst=%h",
                 DUT.core.idex_instruction, DUT.core.exmem_instruction);
        $display("             idex_is_mret=%b exmem_is_mret=%b mret_flush=%b",
                 DUT.core.idex_is_mret, DUT.core.exmem_is_mret, DUT.core.mret_flush);
        $display("             mepc=%h pc_next=%h exception=%b",
                 DUT.core.mepc, DUT.core.pc_next, DUT.core.exception);
      end
      */

      // Monitor .rodata copy loop (PC 0x56-0x68) - Session 33 debug
      if (pc >= 32'h00000056 && pc <= 32'h00000068) begin
        // Show register values during rodata copy - FIRST ITERATION ONLY
        if (pc == 32'h00000056 && cycle_count == 41) begin
          $display("[RODATA-COPY] Cycle %0d: rodata_copy_loop FIRST ITERATION - t0(src)=0x%08h, t1(dst)=0x%08h, t2(end)=0x%08h",
                   cycle_count, DUT.core.regfile.registers[5], DUT.core.regfile.registers[6], DUT.core.regfile.registers[7]);
          // Check what's in IMEM at .rodata addresses (including where strings are!)
          $display("[RODATA-COPY]   CORE IMEM[0x3de8] = 0x%02h%02h%02h%02h (.rodata start - mostly zeros)",
                   DUT.core.imem.mem[32'h3deb], DUT.core.imem.mem[32'h3dea], DUT.core.imem.mem[32'h3de9], DUT.core.imem.mem[32'h3de8]);
          $display("[RODATA-COPY]   CORE IMEM[0x42b8] = 0x%02h%02h%02h%02h (should be '[Task' = 0x5B 54 61 73)",
                   DUT.core.imem.mem[32'h42bb], DUT.core.imem.mem[32'h42ba], DUT.core.imem.mem[32'h42b9], DUT.core.imem.mem[32'h42b8]);
          $display("[RODATA-COPY]   DATA PORT IMEM[0x42b8] = 0x%02h%02h%02h%02h",
                   DUT.imem_data_port.mem[32'h42bb], DUT.imem_data_port.mem[32'h42ba], DUT.imem_data_port.mem[32'h42b9], DUT.imem_data_port.mem[32'h42b8]);
        end
        // Monitor loads from IMEM during rodata copy - FIRST FEW ITERATIONS
        if (DUT.core.exmem_mem_read && DUT.core.exmem_valid && cycle_count <= 100) begin
          $display("[RODATA-COPY] Cycle %0d: LW from addr=0x%08h, data=0x%08h",
                   cycle_count, DUT.core.exmem_alu_result, DUT.core.mem_read_data);
          $display("[RODATA-COPY]   IMEM_DATA_PORT: addr=0x%08h, instruction=0x%08h",
                   DUT.imem_req_addr, DUT.imem_data_port_instruction);
          $display("[RODATA-COPY]   Bus: imem_req_valid=%b, imem_req_ready=%b",
                   DUT.imem_req_valid, DUT.imem_req_ready);
        end
        // Monitor stores to DMEM during rodata copy - FIRST FEW ITERATIONS
        if (DUT.core.exmem_mem_write && DUT.core.exmem_valid && cycle_count <= 100) begin
          $display("[RODATA-COPY] Cycle %0d: SW to addr=0x%08h, data=0x%08h",
                   cycle_count, DUT.core.exmem_alu_result, DUT.core.exmem_mem_write_data);
        end
        if (pc == 32'h00000068 && cycle_count < 2000) begin
          $display("[RODATA-COPY] Cycle %0d: rodata_copy_done - copied %0d bytes",
                   cycle_count, (DUT.core.regfile.registers[6] - 32'h80000000));
        end
      end

      // Monitor printf calls - Session 33 debug
      if (pc == 32'h000026ea) begin  // printf entry point
        $display("[PRINTF] Cycle %0d: printf() called with format string at a0=0x%08h",
                 cycle_count, DUT.core.regfile.registers[10]);
        // Read first 4 bytes of format string from DMEM
        if (DUT.core.regfile.registers[10] >= 32'h80000000 && DUT.core.regfile.registers[10] < 32'h80100000) begin
          $display("[PRINTF]   Format string in DMEM range (good!)");
        end else begin
          $display("[PRINTF]   WARNING: Format string NOT in DMEM range!");
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

  // Session 75: PC monitoring to debug early termination
  integer pc_trace_count;
  initial pc_trace_count = 0;

  always @(posedge clk) begin
    if (reset_n && cycle_count >= 27000) begin
      pc_trace_count = pc_trace_count + 1;

      // Simplified PC trace - only show every 10000 cycles to reduce log spam
      if (pc_trace_count % 10000 == 0) begin
        $display("[PC-TRACE] Cycle %0d: PC=0x%08h", cycle_count, pc);
      end
    end
  end

  // Session 75: Monitor CLINT timer setup
  always @(posedge clk) begin
    if (reset_n) begin
      // Monitor vPortSetupTimerInterrupt execution (PC 0x1b8e - 0x1bf2)
      if (pc >= 32'h00001b8e && pc <= 32'h00001bf2) begin
        // Show stores to MTIMECMP at PC 0x1bd4 and 0x1be2
        if (pc == 32'h00001bd4 || pc == 32'h00001be2) begin
          $display("[TIMER-SETUP] Cycle %0d: PC=0x%08h STORE instruction", cycle_count, pc);
        end
      end

      // Monitor ALL memory writes during timer setup
      if (DUT.core.exmem_mem_write && DUT.core.exmem_valid &&
          DUT.core.exmem_pc >= 32'h00001b8e && DUT.core.exmem_pc <= 32'h00001bf2) begin
        $display("[TIMER-STORE] Cycle %0d: PC=0x%08h writes 0x%08h to addr 0x%08h",
                 cycle_count, DUT.core.exmem_pc, DUT.core.exmem_mem_write_data, DUT.core.exmem_alu_result);
      end

      // Monitor ALL bus requests to CLINT address range
      if (DUT.bus.master_req_valid &&
          DUT.bus.master_req_addr >= 32'h02000000 && DUT.bus.master_req_addr <= 32'h0200FFFF) begin
        $display("[BUS-CLINT] Cycle %0d: Bus request to CLINT addr=0x%08h we=%b sel_clint=%b clint_req_valid=%b clint_req_ready=%b",
                 cycle_count, DUT.bus.master_req_addr, DUT.bus.master_req_we, DUT.bus.sel_clint,
                 DUT.clint_req_valid, DUT.clint_req_ready);
      end

      // Monitor CLINT register accesses (address range 0x0200_0000 - 0x0200_FFFF)
      if (DUT.clint_req_valid && DUT.clint_req_ready) begin
        if (DUT.clint_req_we) begin
          $display("[CLINT-WRITE] Cycle %0d: PC=0x%08h writes 0x%08h to CLINT addr 0x%08h",
                   cycle_count, DUT.core.exmem_pc, DUT.clint_req_wdata, DUT.clint_req_addr);
        end else begin
          $display("[CLINT-READ] Cycle %0d: PC=0x%08h reads from CLINT addr 0x%08h",
                   cycle_count, DUT.core.exmem_pc, DUT.clint_req_addr);
        end
      end

      // Monitor MIE CSR - just show when PC is at the CSRS instruction
      if (pc == 32'h00001c0c) begin
        $display("[CSR-MIE] Cycle %0d: PC=0x%08h executing CSRS MIE instruction", cycle_count, pc);
      end

      // Monitor MTIP (timer interrupt pending signal from CLINT)
      if (DUT.mtip_vec[0]) begin
        $display("[MTIP] Cycle %0d: Timer interrupt pending! mtip=%b", cycle_count, DUT.mtip_vec[0]);
      end
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

  // ========================================
  // Session 44: Assertion Tracking
  // ========================================
  // Track PC around assertion time to find where assertion is called from

  always @(posedge clk) begin
    if (reset_n) begin
      // Check for vApplicationAssertionFailed entry at ANY time
      // Session 67: Fixed address - was 0x1c8c (wrong!), now 0x23e8 (correct)
      if (pc == 32'h000023e8) begin
        $display("");
        $display("========================================");
        $display("[ASSERTION] *** vApplicationAssertionFailed() called at cycle %0d ***", cycle_count);
        $display("========================================");
        $display("[ASSERTION] Return address (ra) = 0x%08h", DUT.core.regfile.registers[1]);

        // Decode which assertion based on ra
        if (DUT.core.regfile.registers[1] == 32'h00001238) begin
          $display("[ASSERTION] Called from xQueueGenericCreateStatic -> xQueueGenericReset");
          $display("[ASSERTION] Checking which assert in xQueueGenericReset...");
          $display("[ASSERTION] Possible: 0x11c8 (queue==NULL) or 0x11cc (size check)");
        end

        // Display complete debug state
        $display("");
        display_debug_state();
        $display("========================================");

        // Stop simulation after assertion
        #100;
        $finish;
      end

      // Track entry to xQueueGenericReset to see parameters (address 0x1114)
      if (pc == 32'h00001114) begin
        $display("[QUEUE-RESET] xQueueGenericReset called at cycle %0d", cycle_count);
        $display("[QUEUE-RESET] a0 (queue ptr) = 0x%08h", DUT.core.regfile.registers[10]);
        $display("[QUEUE-RESET] a1 (reset type) = 0x%08h", DUT.core.regfile.registers[11]);
      end

      // Track a0 corruption in xQueueGenericCreateStatic (0x11ba - 0x11e2)
      if (pc >= 32'h000011ba && pc <= 32'h000011e2) begin
        if (pc == 32'h000011ba || pc == 32'h000011c4 || pc == 32'h000011ce ||
            pc == 32'h000011da || pc == 32'h000011de || pc == 32'h000011e2) begin
          $display("[A0-TRACE] PC=0x%08h: a0 (x10) = 0x%08h", pc, DUT.core.regfile.registers[10]);
        end
      end

      // Track store at 0x11e2 that corrupts queueLength
      if (pc == 32'h000011e2) begin
        $display("[STORE-DEBUG] PC=0x11e2: sw a0,60(s0)");
        $display("[STORE-DEBUG]   a0 (x10) = 0x%08h (value to store)", DUT.core.regfile.registers[10]);
        $display("[STORE-DEBUG]   s0 (x8) = 0x%08h (base pointer)", DUT.core.regfile.registers[8]);
        $display("[STORE-DEBUG]   Target address = 0x%08h", DUT.core.regfile.registers[8] + 60);
      end

      // Track check at 0x1122 (beqz a5,1182) - checks if queueLength is zero
      if (pc == 32'h00001122) begin
        $display("[QUEUE-CHECK] PC=0x1122: queueLength (a5) = 0x%08h", DUT.core.regfile.registers[15]);
        if (DUT.core.regfile.registers[15] == 0) begin
          $display("[QUEUE-CHECK] *** ASSERTION WILL FAIL: queueLength is ZERO! ***");
        end
      end

      // Track where a5 gets loaded from memory at 0x111e
      if (pc == 32'h0000111e) begin
        $display("[LOAD-CHECK] PC=0x111e: Loading queueLength from offset 60");
        $display("[LOAD-CHECK]   a0 (base ptr) = 0x%08h", DUT.core.regfile.registers[10]);
        $display("[LOAD-CHECK]   Will load from addr = 0x%08h", DUT.core.regfile.registers[10] + 60);
      end

      // Track multiplication inputs at 0x1126 (mulhu a5,a5,a4)
      if (pc == 32'h00001126) begin
        $display("[QUEUE-CHECK] PC=0x1126: About to execute MULHU:");
        $display("[QUEUE-CHECK]   a5 (queueLength) = %0d (0x%08h)",
                 DUT.core.regfile.registers[15], DUT.core.regfile.registers[15]);
        $display("[QUEUE-CHECK]   a4 (itemSize) = %0d (0x%08h)",
                 DUT.core.regfile.registers[14], DUT.core.regfile.registers[14]);
        $display("[QUEUE-CHECK]   Expected product (a5*a4) = %0d",
                 DUT.core.regfile.registers[15] * DUT.core.regfile.registers[14]);
      end

      // Track check at 0x112a (bnez a5,1182) - checks if multiplication overflows
      if (pc == 32'h0000112a) begin
        $display("[QUEUE-CHECK] PC=0x112a: mulhu result (a5) = 0x%08h", DUT.core.regfile.registers[15]);
        if (DUT.core.regfile.registers[15] != 0) begin
          $display("[QUEUE-CHECK] *** ASSERTION WILL FAIL: queueLength * itemSize OVERFLOWS! ***");
        end
      end
    end
  end

  // ========================================
  // Register Trace at Store PCs - Session 45 Debug
  // ========================================
  always @(posedge clk) begin
    if (reset_n) begin
      // Track registers at PC 0x122c (sw a0,60(s0))
      if (pc == 32'h0000122c && cycle_count >= 31700) begin
        $display("========================================");
        $display("[REG-TRACE] Cycle %0d: At PC 0x122c (sw a0,60(s0))", cycle_count);
        $display("[REG-TRACE]   a0 (x10) = 0x%08h (will be stored as queueLength)", DUT.core.regfile.registers[10]);
        $display("[REG-TRACE]   a1 (x11) = 0x%08h (will be stored as itemSize)", DUT.core.regfile.registers[11]);
        $display("[REG-TRACE]   s0 (x8)  = 0x%08h (base pointer)", DUT.core.regfile.registers[8]);
        $display("[REG-TRACE]   Target addr = 0x%08h", DUT.core.regfile.registers[8] + 60);
      end
    end
  end

  // ========================================
  // Memory Write Trace - Session 45 Debug
  // ========================================
  // Track stores to the corrupted memory addresses
  always @(posedge clk) begin
    if (reset_n) begin
      // Track stores to address 0x800004c8 (queueLength - corrupted to 10)
      if (DUT.core.exmem_valid && DUT.core.exmem_mem_write) begin
        if (DUT.core.exmem_alu_result == 32'h800004c8 ||
            (DUT.core.exmem_alu_result >= 32'h800004c4 && DUT.core.exmem_alu_result <= 32'h800004cc)) begin
          $display("========================================");
          $display("[MEM-WRITE] Cycle %0d: Store to queue structure!", cycle_count);
          $display("[MEM-WRITE]   PC = 0x%08h", DUT.core.exmem_pc);
          $display("[MEM-WRITE]   Address = 0x%08h", DUT.core.exmem_alu_result);
          $display("[MEM-WRITE]   Data = 0x%08h", DUT.core.exmem_mem_write_data);
          $display("[MEM-WRITE]   funct3 = %b", DUT.core.exmem_funct3);
          if (DUT.core.exmem_alu_result == 32'h800004c8) begin
            $display("[MEM-WRITE]   *** This is address 0x800004c8 (queueLength field)! ***");
          end
        end
      end
    end
  end

  // ========================================
  // Load Instruction Trace - Session 45 Debug
  // ========================================
  // Track the load at PC 0x1168 that should load itemSize (84)
  always @(posedge clk) begin
    if (reset_n) begin
      // Track load in ID stage
      if (DUT.core.ifid_valid && DUT.core.ifid_pc == 32'h00001168) begin
        $display("========================================");
        $display("[LOAD-ID] Cycle %0d: Load at PC 0x1168 in ID stage", cycle_count);
        $display("[LOAD-ID]   Instruction = 0x%08h", DUT.core.ifid_instruction);
        $display("[LOAD-ID]   rs1 = x%0d, rd = x%0d", DUT.core.id_rs1, DUT.core.id_rd);
        $display("[LOAD-ID]   RegFile rs1 (base) = 0x%08h", DUT.core.regfile.registers[DUT.core.id_rs1]);
        $display("[LOAD-ID]   Immediate offset = 0x%08h", DUT.core.id_immediate);
        $display("[LOAD-ID]   Target address = 0x%08h",
                 DUT.core.regfile.registers[DUT.core.id_rs1] + DUT.core.id_immediate);
      end

      // Track load in EX stage
      if (DUT.core.idex_valid && DUT.core.idex_pc == 32'h00001168) begin
        $display("========================================");
        $display("[LOAD-EX] Cycle %0d: Load at PC 0x1168 in EX stage", cycle_count);
        $display("[LOAD-EX]   ALU result (address) = 0x%08h", DUT.core.ex_alu_result);
        $display("[LOAD-EX]   rs1_data = 0x%08h", DUT.core.idex_rs1_data);
        $display("[LOAD-EX]   immediate = 0x%08h", DUT.core.idex_imm);
        $display("[LOAD-EX]   rd = x%0d", DUT.core.idex_rd_addr);
      end

      // Track load in MEM stage
      if (DUT.core.exmem_valid && DUT.core.exmem_pc == 32'h00001168) begin
        $display("========================================");
        $display("[LOAD-MEM] Cycle %0d: Load at PC 0x1168 in MEM stage", cycle_count);
        $display("[LOAD-MEM]   Memory address = 0x%08h", DUT.core.exmem_alu_result);
        $display("[LOAD-MEM]   mem_read = %b", DUT.core.exmem_mem_read);
        $display("[LOAD-MEM]   mem_read_data = 0x%08h", DUT.core.mem_read_data);
        $display("[LOAD-MEM]   rd = x%0d", DUT.core.exmem_rd_addr);
        $display("[LOAD-MEM]   wb_sel = %b", DUT.core.exmem_wb_sel);
      end

      // Track ALL WB stage activity around the critical cycles (detect load by rd=x14)
      if (cycle_count >= 31720 && cycle_count <= 31735 && DUT.core.memwb_valid && DUT.core.memwb_reg_write) begin
        $display("[WB-TRACE] Cycle %0d: WB writing x%0d <= 0x%08h (wb_sel=%b, mem_data=0x%08h)",
                 cycle_count, DUT.core.memwb_rd_addr, DUT.core.wb_data, DUT.core.memwb_wb_sel,
                 DUT.core.memwb_mem_read_data);
        if (DUT.core.memwb_rd_addr == 5'd14) begin  // x14 = a4 (itemSize)
          $display("[WB-TRACE] *** This is the load of itemSize into a4! ***");
        end
      end
    end
  end

  // ========================================
  // Session 55: PC/Stack/Return Address Crash Tracing
  // ========================================
  // Detailed tracing to identify crash location

  `ifdef DEBUG_PC_TRACE
  // Trace ALL PC changes with instruction info
  reg [31:0] prev_pc_trace;
  initial prev_pc_trace = 0;

  always @(posedge clk) begin
    if (reset_n) begin
      if (pc != prev_pc_trace) begin
        $display("[PC-TRACE] Cycle %0d: PC = 0x%08h, instr = 0x%08h",
                 cycle_count, pc, instruction);
      end
      prev_pc_trace = pc;
    end
  end
  `endif

  `ifdef DEBUG_STACK_TRACE
  // Monitor stack pointer (x2/sp) changes
  reg [31:0] prev_sp_trace;
  initial prev_sp_trace = 0;

  always @(posedge clk) begin
    if (reset_n) begin
      if (DUT.core.regfile.registers[2] != prev_sp_trace) begin
        $display("[SP-TRACE] Cycle %0d: SP changed from 0x%08h to 0x%08h (delta: %0d), PC = 0x%08h",
                 cycle_count, prev_sp_trace, DUT.core.regfile.registers[2],
                 $signed(DUT.core.regfile.registers[2] - prev_sp_trace), pc);
      end
      prev_sp_trace = DUT.core.regfile.registers[2];
    end
  end
  `endif

  `ifdef DEBUG_RA_TRACE
  // Monitor return address (x1/ra) changes
  reg [31:0] prev_ra_trace;
  initial prev_ra_trace = 0;

  always @(posedge clk) begin
    if (reset_n) begin
      if (DUT.core.regfile.registers[1] != prev_ra_trace) begin
        $display("[RA-TRACE] Cycle %0d: RA changed from 0x%08h to 0x%08h, PC = 0x%08h",
                 cycle_count, prev_ra_trace, DUT.core.regfile.registers[1], pc);
      end
      prev_ra_trace = DUT.core.regfile.registers[1];
    end
  end
  `endif

  `ifdef DEBUG_FUNC_CALLS
  // Track key function calls/returns based on PC
  always @(posedge clk) begin
    if (reset_n) begin
      // main() entry at 0x22d4
      if (pc == 32'h000022d4) begin
        $display("========================================");
        $display("[FUNC-CALL] main() ENTERED at cycle %0d", cycle_count);
        $display("[FUNC-CALL]   SP = 0x%08h", DUT.core.regfile.registers[2]);
        $display("========================================");
      end

      // uart_init() at 0x2434
      if (pc == 32'h00002434) begin
        $display("[FUNC-CALL] uart_init() at cycle %0d, RA = 0x%08h",
                 cycle_count, DUT.core.regfile.registers[1]);
      end

      // puts() at 0x2462
      if (pc == 32'h00002462) begin
        $display("[FUNC-CALL] puts() at cycle %0d, arg a0 = 0x%08h, RA = 0x%08h",
                 cycle_count, DUT.core.regfile.registers[10], DUT.core.regfile.registers[1]);
      end

      // printf() at 0x26ea
      if (pc == 32'h000026ea) begin
        $display("[FUNC-CALL] printf() at cycle %0d, RA = 0x%08h",
                 cycle_count, DUT.core.regfile.registers[1]);
      end

      // xTaskCreate() at 0xf88
      if (pc == 32'h00000f88) begin
        $display("[FUNC-CALL] xTaskCreate() at cycle %0d, RA = 0x%08h",
                 cycle_count, DUT.core.regfile.registers[1]);
      end

      // Detect JALR with invalid target (crash indicator)
      if (DUT.core.memwb_valid && instruction[6:0] == 7'b1100111) begin  // JALR
        if (pc > 32'h00010000 || (pc >= 32'h00004000 && pc < 32'h80000000)) begin
          $display("========================================");
          $display("ERROR: JALR to INVALID ADDRESS!");
          $display("  Cycle: %0d", cycle_count);
          $display("  PC: 0x%08h (likely garbage)", pc);
          $display("  Instruction: 0x%08h", instruction);
          $display("  RA (x1): 0x%08h", DUT.core.regfile.registers[1]);
          $display("  SP (x2): 0x%08h", DUT.core.regfile.registers[2]);
          $display("========================================");
        end
      end
    end
  end
  `endif

  `ifdef DEBUG_CRASH_DETECT
  // Detect potential crash patterns
  reg [31:0] stuck_pc_count;
  reg [31:0] last_stuck_pc;
  initial stuck_pc_count = 0;
  initial last_stuck_pc = 0;

  always @(posedge clk) begin
    if (reset_n) begin
      // Detect PC stuck in tight loop (potential hang)
      if (pc == last_stuck_pc) begin
        stuck_pc_count = stuck_pc_count + 1;
        if (stuck_pc_count == 100) begin
          $display("========================================");
          $display("WARNING: PC STUCK AT 0x%08h for 100 cycles", pc);
          $display("  Instruction: 0x%08h", instruction);
          $display("  SP: 0x%08h", DUT.core.regfile.registers[2]);
          $display("  RA: 0x%08h", DUT.core.regfile.registers[1]);
          $display("========================================");
        end
      end else begin
        stuck_pc_count = 0;
        last_stuck_pc = pc;
      end

      // Detect stack overflow (SP below stack bottom 0x800C1850)
      // NOTE: FreeRTOS tasks have their own stacks allocated from heap
      // Main/ISR stack: 0x800C1850-0x800C2850
      // Task stacks are in heap region (0x80000980-0x80040980)
      // Only flag if SP is completely out of valid ranges
      if (DUT.core.regfile.registers[2] < 32'h80000000 ||
          DUT.core.regfile.registers[2] > 32'h80100000) begin
        $display("========================================");
        $display("ERROR: STACK POINTER OUT OF DMEM!");
        $display("  Cycle: %0d", cycle_count);
        $display("  SP: 0x%08h (outside DMEM 0x80000000-0x80100000)", DUT.core.regfile.registers[2]);
        $display("  PC: 0x%08h", pc);
        $display("========================================");
      end

      // Detect stack over-growth (SP above stack top 0x800C2850)
      if (DUT.core.regfile.registers[2] > 32'h800C2850) begin
        $display("========================================");
        $display("WARNING: SP ABOVE INITIAL STACK TOP");
        $display("  Cycle: %0d", cycle_count);
        $display("  SP: 0x%08h (above initial top 0x800C2850)", DUT.core.regfile.registers[2]);
        $display("  PC: 0x%08h", pc);
        $display("========================================");
      end
    end
  end
  `endif

  // ========================================
  // MULHU Pipeline Trace - Session 45 Debug
  // ========================================
  // Detailed trace of MULHU instruction through all pipeline stages
  // Tracks operand values, forwarding, and latching
  // DISABLED - causes massive spam, only enable for MUL/DIV debugging
  `ifdef NEVER_DEFINED
  always @(posedge clk) begin
    if (reset_n) begin
      // Track MULHU in ID stage
      if (DUT.core.ifid_valid && DUT.core.id_is_mul_div_dec &&
          DUT.core.id_mul_div_op_dec == 4'b0011) begin  // MULHU opcode
        $display("========================================");
        $display("[MULHU-ID] Cycle %0d: MULHU detected in ID stage", cycle_count);
        $display("[MULHU-ID]   PC: 0x%08h", DUT.core.ifid_pc);
        $display("[MULHU-ID]   rs1 = x%0d, rs2 = x%0d, rd = x%0d",
                 DUT.core.id_rs1, DUT.core.id_rs2, DUT.core.id_rd);
        $display("[MULHU-ID]   RegFile rs1 (x%0d) = 0x%08h",
                 DUT.core.id_rs1, DUT.core.regfile.registers[DUT.core.id_rs1]);
        $display("[MULHU-ID]   RegFile rs2 (x%0d) = 0x%08h",
                 DUT.core.id_rs2, DUT.core.regfile.registers[DUT.core.id_rs2]);
        $display("[MULHU-ID]   Load-use hazard = %b", DUT.core.hazard_unit.load_use_hazard);
        $display("[MULHU-ID]   M extension stall = %b", DUT.core.hazard_unit.m_extension_stall);
        $display("[MULHU-ID]   Stall PC = %b", DUT.core.stall_pc);
      end

      // Track MULHU in EX stage
      if (DUT.core.idex_valid && DUT.core.idex_is_mul_div &&
          DUT.core.idex_mul_div_op == 4'b0011) begin  // MULHU opcode
        $display("========================================");
        $display("[MULHU-EX] Cycle %0d: MULHU in EX stage", cycle_count);
        $display("[MULHU-EX]   PC: 0x%08h", DUT.core.idex_pc);
        $display("[MULHU-EX]   rs1 = x%0d, rs2 = x%0d, rd = x%0d",
                 DUT.core.idex_rs1_addr, DUT.core.idex_rs2_addr, DUT.core.idex_rd_addr);
        $display("[MULHU-EX]   IDEX rs1_data = 0x%08h", DUT.core.idex_rs1_data);
        $display("[MULHU-EX]   IDEX rs2_data = 0x%08h", DUT.core.idex_rs2_data);
        $display("[MULHU-EX]   Forward_a = %b, Forward_b = %b",
                 DUT.core.forward_a, DUT.core.forward_b);
        $display("[MULHU-EX]   EXMEM forward_data = 0x%08h", DUT.core.exmem_forward_data);
        $display("[MULHU-EX]   EXMEM alu_result = 0x%08h", DUT.core.exmem_alu_result);
        $display("[MULHU-EX]   MEM read_data = 0x%08h", DUT.core.mem_read_data);
        $display("[MULHU-EX]   EXMEM wb_sel = %b", DUT.core.exmem_wb_sel);
        $display("[MULHU-EX]   WB data = 0x%08h", DUT.core.wb_data);
        $display("[MULHU-EX]   Forwarded operand_a = 0x%08h", DUT.core.ex_alu_operand_a_forwarded);
        $display("[MULHU-EX]   Forwarded operand_b (rs2) = 0x%08h", DUT.core.ex_rs2_data_forwarded);
        $display("[MULHU-EX]   M operands valid = %b", DUT.core.m_operands_valid);
        $display("[MULHU-EX]   M operand_a_latched = 0x%08h", DUT.core.m_operand_a_latched);
        $display("[MULHU-EX]   M operand_b_latched = 0x%08h", DUT.core.m_operand_b_latched);
        $display("[MULHU-EX]   M final operand_a = 0x%08h", DUT.core.m_final_operand_a);
        $display("[MULHU-EX]   M final operand_b = 0x%08h", DUT.core.m_final_operand_b);
        $display("[MULHU-EX]   M unit busy = %b", DUT.core.ex_mul_div_busy);
        $display("[MULHU-EX]   M unit start = %b", DUT.core.m_unit_start);
      end

      // Track MULHU result ready
      if (DUT.core.idex_valid && DUT.core.idex_is_mul_div &&
          DUT.core.idex_mul_div_op == 4'b0011 && DUT.core.ex_mul_div_ready) begin
        $display("========================================");
        $display("[MULHU-DONE] Cycle %0d: MULHU completed", cycle_count);
        $display("[MULHU-DONE]   PC: 0x%08h", DUT.core.idex_pc);
        $display("[MULHU-DONE]   Result = 0x%08h", DUT.core.ex_mul_div_result);
        $display("[MULHU-DONE]   Expected high word of %0d * %0d",
                 DUT.core.m_operand_a_latched, DUT.core.m_operand_b_latched);
        $display("========================================");
      end
    end
  end
  `endif  // NEVER_DEFINED

endmodule
