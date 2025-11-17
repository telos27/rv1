// rv_soc.v - RV1 片上系统
// 完整 SoC，包含 CPU 内核、总线互连和外设
// 阶段 1.4：带存储器映射外设的完整 SoC 集成
// 作者: RV1 项目
// 日期: 2025-10-27

`include "config/rv_config.vh"

module rv_soc #(
  parameter XLEN = `XLEN,
  parameter RESET_VECTOR = {XLEN{1'b0}},
  parameter IMEM_SIZE = 16384,      // 16KB 指令存储器
  parameter DMEM_SIZE = 16384,      // 16KB 数据存储器
  parameter MEM_FILE = "",
  parameter NUM_HARTS = 1           // 硬件线程（hart）数量
) (
  input  wire             clk,
  input  wire             reset_n,

  // UART 串口接口
  output wire             uart_tx_valid,
  output wire [7:0]       uart_tx_data,
  input  wire             uart_tx_ready,
  input  wire             uart_rx_valid,
  input  wire [7:0]       uart_rx_data,
  output wire             uart_rx_ready,

  // 调试输出
  output wire [XLEN-1:0]  pc_out,
  output wire [31:0]      instr_out
);

  //==========================================================================
  // 内部信号
  //==========================================================================

  // 中断信号（来自外设）
  wire [NUM_HARTS-1:0] mtip_vec;      // 机器定时器中断向量（来自 CLINT）
  wire [NUM_HARTS-1:0] msip_vec;      // 机器软件中断向量（来自 CLINT）
  wire             mtip;              // hart 0 的机器定时器中断
  wire             msip;              // hart 0 的机器软件中断
  wire             meip;              // 机器外部中断（来自 PLIC）
  wire             seip;              // 监督者外部中断（来自 PLIC）

  // 从向量中提取 hart 0 的中断
  assign mtip = mtip_vec[0];
  assign msip = msip_vec[0];
  wire             uart_irq;          // UART 中断

  // 总线信号 - 主设备（内核）
  wire             bus_master_req_valid;
  wire [XLEN-1:0]  bus_master_req_addr;
  wire [63:0]      bus_master_req_wdata;
  wire             bus_master_req_we;
  wire [2:0]       bus_master_req_size;
  wire             bus_master_req_ready;
  wire [63:0]      bus_master_req_rdata;

  // 总线信号 - 从设备 0（CLINT）
  wire             clint_req_valid;
  wire [15:0]      clint_req_addr;
  wire [63:0]      clint_req_wdata;
  wire             clint_req_we;
  wire [2:0]       clint_req_size;
  wire             clint_req_ready;
  wire [63:0]      clint_req_rdata;

  // 总线信号 - 从设备 1（UART）
  wire             uart_req_valid;
  wire [2:0]       uart_req_addr;
  wire [7:0]       uart_req_wdata;
  wire             uart_req_we;
  wire             uart_req_ready;
  wire [7:0]       uart_req_rdata;

  // 总线信号 - 从设备 2（DMEM）
  wire             dmem_req_valid;
  wire [XLEN-1:0]  dmem_req_addr;
  wire [63:0]      dmem_req_wdata;
  wire             dmem_req_we;
  wire [2:0]       dmem_req_size;
  wire             dmem_req_ready;
  wire [63:0]      dmem_req_rdata;

  // 总线信号 - 从设备 3（PLIC）
  wire             plic_req_valid;
  wire [XLEN-1:0]  plic_req_addr;        // 来自总线（完整地址）
  wire [23:0]      plic_req_addr_offset; // 送给 PLIC 的 24 位偏移地址
  wire [31:0]      plic_req_wdata;
  wire             plic_req_we;
  wire             plic_req_ready;
  wire [31:0]      plic_req_rdata;

  // 总线信号 - 从设备 4（IMEM） - 用于 .rodata 拷贝
  wire             imem_req_valid;
  wire [XLEN-1:0]  imem_req_addr;
  wire             imem_req_ready;
  wire [31:0]      imem_req_rdata;

  //==========================================================================
  // CPU 内核
  //==========================================================================

  rv_core_pipelined #(
    .XLEN(XLEN),
    .RESET_VECTOR(RESET_VECTOR),
    .IMEM_SIZE(IMEM_SIZE),
    .DMEM_SIZE(DMEM_SIZE),
    .MEM_FILE(MEM_FILE)
  ) core (
    .clk(clk),
    .reset_n(reset_n),
    // 中断
    .mtip_in(mtip),
    .msip_in(msip),
    .meip_in(meip),
    .seip_in(seip),
    // 总线主设备接口
    .bus_req_valid(bus_master_req_valid),
    .bus_req_addr(bus_master_req_addr),
    .bus_req_wdata(bus_master_req_wdata),
    .bus_req_we(bus_master_req_we),
    .bus_req_size(bus_master_req_size),
    .bus_req_ready(bus_master_req_ready),
    .bus_req_rdata(bus_master_req_rdata),
    // 调试
    .pc_out(pc_out),
    .instr_out(instr_out)
  );

  //==========================================================================
  // 总线互连
  //==========================================================================

  simple_bus #(
    .XLEN(XLEN)
  ) bus (
    .clk(clk),
    .reset_n(reset_n),
    // 主设备接口（来自内核）
    .master_req_valid(bus_master_req_valid),
    .master_req_addr(bus_master_req_addr),
    .master_req_wdata(bus_master_req_wdata),
    .master_req_we(bus_master_req_we),
    .master_req_size(bus_master_req_size),
    .master_req_ready(bus_master_req_ready),
    .master_req_rdata(bus_master_req_rdata),
    // 从设备 0: CLINT
    .clint_req_valid(clint_req_valid),
    .clint_req_addr(clint_req_addr),
    .clint_req_wdata(clint_req_wdata),
    .clint_req_we(clint_req_we),
    .clint_req_size(clint_req_size),
    .clint_req_ready(clint_req_ready),
    .clint_req_rdata(clint_req_rdata),
    // 从设备 1: UART
    .uart_req_valid(uart_req_valid),
    .uart_req_addr(uart_req_addr),
    .uart_req_wdata(uart_req_wdata),
    .uart_req_we(uart_req_we),
    .uart_req_ready(uart_req_ready),
    .uart_req_rdata(uart_req_rdata),
    // 从设备 2: DMEM
    .dmem_req_valid(dmem_req_valid),
    .dmem_req_addr(dmem_req_addr),
    .dmem_req_wdata(dmem_req_wdata),
    .dmem_req_we(dmem_req_we),
    .dmem_req_size(dmem_req_size),
    .dmem_req_ready(dmem_req_ready),
    .dmem_req_rdata(dmem_req_rdata),
    // 从设备 3: PLIC
    .plic_req_valid(plic_req_valid),
    .plic_req_addr(plic_req_addr),
    .plic_req_wdata(plic_req_wdata),
    .plic_req_we(plic_req_we),
    .plic_req_ready(plic_req_ready),
    .plic_req_rdata(plic_req_rdata),
    // 从设备 4: IMEM
    .imem_req_valid(imem_req_valid),
    .imem_req_addr(imem_req_addr),
    .imem_req_ready(imem_req_ready),
    .imem_req_rdata(imem_req_rdata)
  );

  //==========================================================================
  // CLINT（核本地中断控制器）
  //==========================================================================

  clint #(
    .NUM_HARTS(NUM_HARTS),
    .BASE_ADDR(32'h0200_0000)
  ) clint_inst (
    .clk(clk),
    .reset_n(reset_n),
    // 存储器映射接口（通过总线连接）
    .req_valid(clint_req_valid),
    .req_addr(clint_req_addr),
    .req_wdata(clint_req_wdata),
    .req_we(clint_req_we),
    .req_size(clint_req_size),
    .req_ready(clint_req_ready),
    .req_rdata(clint_req_rdata),
    // 中断输出（所有 hart）
    .mti_o(mtip_vec),  // 机器定时器中断向量
    .msi_o(msip_vec)   // 机器软件中断向量
  );

  //==========================================================================
  // UART（16550 兼容串口控制台）
  //==========================================================================

  uart_16550 #(
    .BASE_ADDR(32'h1000_0000)
  ) uart_inst (
    .clk(clk),
    .reset_n(reset_n),
    // 存储器映射接口（通过总线连接）
    .req_valid(uart_req_valid),
    .req_addr(uart_req_addr),
    .req_wdata(uart_req_wdata),
    .req_we(uart_req_we),
    .req_ready(uart_req_ready),
    .req_rdata(uart_req_rdata),
    // 串行接口（在 SoC 顶层暴露）
    .tx_valid(uart_tx_valid),
    .tx_data(uart_tx_data),
    .tx_ready(uart_tx_ready),
    .rx_valid(uart_rx_valid),
    .rx_data(uart_rx_data),
    .rx_ready(uart_rx_ready),
    // 中断输出
    .irq_o(uart_irq)
  );

  //==========================================================================
  // PLIC（平台级中断控制器）
  //==========================================================================

  // 从完整地址中提取 24 位偏移地址供 PLIC 使用
  assign plic_req_addr_offset = plic_req_addr[23:0];

  plic #(
    .NUM_SOURCES(32),
    .NUM_HARTS(NUM_HARTS)
  ) plic_inst (
    .clk(clk),
    .reset_n(reset_n),
    // 存储器映射接口（通过总线连接）
    .req_valid(plic_req_valid),
    .req_addr(plic_req_addr_offset),
    .req_wdata(plic_req_wdata),
    .req_we(plic_req_we),
    .req_ready(plic_req_ready),
    .req_rdata(plic_req_rdata),
    // 中断源（32 个源，目前只连接 UART）
    .irq_sources({31'b0, uart_irq}),  // 源 1 = UART
    // 发往内核的中断输出
    .mei_o(meip),  // 机器外部中断
    .sei_o(seip)   // 监督者外部中断
  );

  //==========================================================================
  // 指令存储器（总线适配器 - 只读，用于 .rodata 拷贝）
  //==========================================================================

  // IMEM 总线适配器允许从指令存储器进行数据读
  // 这在启动阶段拷贝 .rodata 段时是必须的
  // 我们通过再实例化一个 instruction_memory 来创建第二个读端口
  // 两个端口共享同一个 hex 文件（只读，因此没有一致性问题）

  wire [31:0] imem_data_port_instruction;

  instruction_memory #(
    .XLEN(XLEN),
    .MEM_SIZE(IMEM_SIZE),
    .MEM_FILE(MEM_FILE),
    .DATA_PORT(1)              // 为 .rodata 拷贝启用按字节访问
  ) imem_data_port (
    .clk(clk),
    .addr(imem_req_addr),
    .instruction(imem_data_port_instruction),
    // 写接口未使用（只读端口）
    .mem_write(1'b0),
    .write_addr({XLEN{1'b0}}),
    .write_data({XLEN{1'b0}}),
    .funct3(3'b0)
  );

  // 调试：检查 IMEM 数据端口中 .rodata 地址上的内容
  initial begin
    #1;  // 等待存储器加载完成
    $display("[SOC-IMEM-DATA-PORT] 检查 IMEM 数据端口中的 .rodata 段:");
    $display("  [0x3de8] = 0x%02h%02h%02h%02h", imem_data_port.mem[32'h3deb], imem_data_port.mem[32'h3dea],
             imem_data_port.mem[32'h3de9], imem_data_port.mem[32'h3de8]);
    $display("  [0x42b8] = 0x%02h%02h%02h%02h", imem_data_port.mem[32'h42bb], imem_data_port.mem[32'h42ba],
             imem_data_port.mem[32'h42b9], imem_data_port.mem[32'h42b8]);
  end

  // 带字节/半字提取的 IMEM 适配器
  // 问题：为了支持 RVC，instruction_memory 会将地址对齐到半字边界，
  // 但数据加载指令（LB/LBU/LH/LHU）需要精确的字节地址。
  //
  // 解决方案：根据 addr[1:0] 从 32 位字中提取正确的字节/半字。
  //
  // 例子：从地址 0x4241 做 LB（应该读到字节 'a'）
  //   - IMEM 对齐到 0x4240，返回 32 位字：[byte3][byte2][byte1][byte0]
  //   - addr[1:0] = 2'b01，因此选择 byte1
  //
  // 注意：我们假设小端字节序

  assign imem_req_ready = imem_req_valid;

  // 基于 address[1:0] 的字节选择
  wire [7:0] imem_byte_select;
  assign imem_byte_select = (imem_req_addr[1:0] == 2'b00) ? imem_data_port_instruction[7:0] :
                            (imem_req_addr[1:0] == 2'b01) ? imem_data_port_instruction[15:8] :
                            (imem_req_addr[1:0] == 2'b10) ? imem_data_port_instruction[23:16] :
                                                             imem_data_port_instruction[31:24];

  // 基于 address[1] 的半字选择
  wire [15:0] imem_halfword_select;
  assign imem_halfword_select = (imem_req_addr[1] == 1'b0) ? imem_data_port_instruction[15:0] :
                                                              imem_data_port_instruction[31:16];

  // 返回带正确字节/半字提取的数据
  // 对于字访问（LW），返回完整 32 位字（IMEM 已经对齐）
  // 对于字节访问（LB/LBU），返回选中的字节并零扩展到 32 位
  // 对于半字访问（LH/LHU），返回选中的半字并零扩展到 32 位
  //
  // 注意：内核会根据 funct3 为 LB/LH 做符号扩展
  // 这里我们始终返回零扩展值
  assign imem_req_rdata = (imem_req_addr[1:0] == 2'b00) ? imem_data_port_instruction :  // 按字对齐，返回完整字
                                                           {24'h0, imem_byte_select};    // 字节访问，返回选中字节

  //==========================================================================
  // 数据存储器（总线适配器）
  //==========================================================================

  dmem_bus_adapter #(
    .XLEN(XLEN),
    .FLEN(`FLEN),
    .MEM_SIZE(DMEM_SIZE),
    .MEM_FILE("")  // DMEM 不应从 hex 文件加载（统一存储器修复）
  ) dmem_adapter (
    .clk(clk),
    .reset_n(reset_n),
    // 总线从设备接口
    .req_valid(dmem_req_valid),
    .req_addr(dmem_req_addr),
    .req_wdata(dmem_req_wdata),
    .req_we(dmem_req_we),
    .req_size(dmem_req_size),
    .req_ready(dmem_req_ready),
    .req_rdata(dmem_req_rdata)
  );

  //===========================================================================
  // 调试监控
  //===========================================================================
  `ifdef DEBUG_CLINT
  always @(posedge clk) begin
    if (mtip_vec[0] || mtip) begin
      $display("[SOC] mtip_vec=%b mtip=%b msip_vec=%b msip=%b", mtip_vec, mtip, msip_vec, msip);
    end
  end
  `endif

  `ifdef DEBUG_UART_BUS
  always @(posedge clk) begin
    if (uart_req_valid && uart_req_we) begin
      $display("[BUS-UART-WR] Cycle %0d: bus_req_valid=%b bus_req_we=%b addr=0x%08h data=0x%02h '%c' uart_req_ready=%b",
               $time/10, uart_req_valid, uart_req_we, {uart_req_addr, 3'b000}, uart_req_wdata, uart_req_wdata, uart_req_ready);
    end
  end
  `endif

endmodule
