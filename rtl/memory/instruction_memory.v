// instruction_memory.v - RISC-V 指令存储器
// 用于程序存储的存储器（可写，以支持 FENCE.I 自修改代码）
// 作者: RV1 项目组
// 日期: 2025-10-09
// 更新: 2025-10-10 - 参数化 XLEN（支持 32/64 位地址）
// 更新: 2025-10-11 - 为符合 FENCE.I 增加写能力
// 更新: 2025-10-11 - 增加对 C 扩展（16 位对齐访问）的支持

`include "config/rv_config.vh"

module instruction_memory #(
  parameter XLEN     = `XLEN,     // 地址宽度：32 或 64 位
  parameter MEM_SIZE = 65536,     // 内存大小（字节），默认 64KB
  parameter MEM_FILE = "",        // 用于初始化内存的 hex 文件
  parameter DATA_PORT = 0         // 1 = 数据端口（字节级访问），0 = 指令端口（半字对齐）
) (
  input  wire             clk,          // 写操作时钟
  input  wire [XLEN-1:0]  addr,         // 读操作的字节地址
  output wire [31:0]      instruction,  // 指令输出（基础 ISA 始终为 32 位）

  // 为 FENCE.I 支持的写接口（自修改代码）
  input  wire             mem_write,    // 写使能
  input  wire [XLEN-1:0]  write_addr,   // 写地址
  input  wire [XLEN-1:0]  write_data,   // 要写入的数据
  input  wire [2:0]       funct3        // 存储操作类型（SB/SH/SW/SD）
);

  // 内存阵列（按字节寻址，便于加载 hex 文件）
  reg [7:0] mem [0:MEM_SIZE-1];

  // 初始化内存
  initial begin
    integer i;

    // 初始化为 NOP（ADDI x0, x0, 0）= 0x00000013，以小端字节序存放
    for (i = 0; i < MEM_SIZE; i = i + 4) begin
      mem[i]   = 8'h13;  // NOP 字节 0
      mem[i+1] = 8'h00;  // NOP 字节 1
      mem[i+2] = 8'h00;  // NOP 字节 2
      mem[i+3] = 8'h00;  // NOP 字节 3
    end

    // 如果指定了文件则从文件加载
    // 使用 "objcopy -O verilog" 生成的 hex 文件格式为以空格分隔的十六进制字节
    // $readmemh 会将每个由空格分隔的值视为一个字节
    if (MEM_FILE != "") begin
      $readmemh(MEM_FILE, mem);

      // 调试：打印加载的前几条指令
      $display("=== Instruction Memory Loaded ===");
      $display("MEM_FILE: %s", MEM_FILE);
      $display("First 4 instructions:");
      $display("  [0x00] = 0x%02h%02h%02h%02h", mem[3], mem[2], mem[1], mem[0]);
      $display("  [0x04] = 0x%02h%02h%02h%02h", mem[7], mem[6], mem[5], mem[4]);
      $display("  [0x08] = 0x%02h%02h%02h%02h", mem[11], mem[10], mem[9], mem[8]);
      $display("  [0x0C] = 0x%02h%02h%02h%02h", mem[15], mem[14], mem[13], mem[12]);
      $display("Instructions around 0x210c:");
      $display("  [0x2108] = 0x%02h%02h%02h%02h", mem[32'h210b], mem[32'h210a], mem[32'h2109], mem[32'h2108]);
      $display("  [0x210c] = 0x%02h%02h%02h%02h", mem[32'h210f], mem[32'h210e], mem[32'h210d], mem[32'h210c]);
      $display("  [0x2110] = 0x%02h%02h%02h%02h", mem[32'h2113], mem[32'h2112], mem[32'h2111], mem[32'h2110]);
      $display("=================================");
    end
  end

  // 读取指令（支持 16 位和 32 位对齐，适配 C 扩展）
  // 从给定地址开始抓取 32 位（地址可以按 2 字节对齐）
  // 这样可以在任意半字边界抓取压缩（16 位）指令
  // 对地址进行掩码以限制在存储器大小内（支持不同基地址）
  wire [XLEN-1:0] masked_addr = addr & (MEM_SIZE - 1);  // 按内存大小掩码

  // 指令端口：对齐到半字边界（支持 C 扩展）
  // 数据端口：使用字对齐地址（字节提取在外部完成）
  wire [XLEN-1:0] halfword_addr = {masked_addr[XLEN-1:1], 1'b0};  // 对齐到半字边界
  wire [XLEN-1:0] word_addr = {masked_addr[XLEN-1:2], 2'b00};     // 对齐到字边界
  wire [XLEN-1:0] read_addr = DATA_PORT ? word_addr : halfword_addr;

  // 抓取从对齐地址开始的 32 位（4 字节）
  // 指令端口：可读取一个完整 32 位指令或两个 16 位压缩指令
  // 数据端口：返回字对齐的 32 位数据（字节/半字提取由总线适配器完成）
  assign instruction = {mem[read_addr+3], mem[read_addr+2],
                        mem[read_addr+1], mem[read_addr]};

  // 调试：监控问题地址上的取指（在时钟上升沿打印以避免刷屏）
  reg [XLEN-1:0] prev_addr;
  always @(posedge clk) begin
    if (addr >= 32'h2100 && addr <= 32'h2120 && addr != prev_addr) begin
      if (DATA_PORT)
        $display("[IMEM-DATA] addr=0x%08h, word_addr=0x%08h, data=0x%08h",
                 addr, word_addr, instruction);
      else
        $display("[IMEM-FETCH] addr=0x%08h, hw_addr=0x%08h, instr=0x%08h",
                 addr, halfword_addr, instruction);
    end
    prev_addr <= addr;
  end

  // 写操作（通过 FENCE.I 实现自修改代码）
  // 允许数据存储指令修改指令存储器
  wire [XLEN-1:0] write_masked_addr;
  wire [XLEN-1:0] write_word_addr;
  wire [XLEN-1:0] write_dword_addr;

  assign write_masked_addr = write_addr & (MEM_SIZE - 1);  // 对写地址做掩码
  assign write_word_addr = {write_masked_addr[XLEN-1:2], 2'b00};
  assign write_dword_addr = {write_masked_addr[XLEN-1:3], 3'b000};

  always @(posedge clk) begin
    if (mem_write) begin
      // 调试：监控问题地址范围内的写操作
      if (write_addr >= 32'h2100 && write_addr <= 32'h2120) begin
        $display("[IMEM-WRITE] cycle=%0t, addr=0x%08h, data=0x%016h, funct3=%0d",
                 $time/20, write_addr, write_data, funct3);
      end

      case (funct3)
        3'b000: begin  // SB（存储字节）
          mem[write_masked_addr] <= write_data[7:0];
        end
        3'b001: begin  // SH（存储半字）
          mem[write_masked_addr]     <= write_data[7:0];
          mem[write_masked_addr + 1] <= write_data[15:8];
        end
        3'b010: begin  // SW（存储字）
          mem[write_word_addr]     <= write_data[7:0];
          mem[write_word_addr + 1] <= write_data[15:8];
          mem[write_word_addr + 2] <= write_data[23:16];
          mem[write_word_addr + 3] <= write_data[31:24];
        end
        3'b011: begin  // SD（存储双字 - 仅 RV64）
          if (XLEN == 64) begin
            mem[write_dword_addr]     <= write_data[7:0];
            mem[write_dword_addr + 1] <= write_data[15:8];
            mem[write_dword_addr + 2] <= write_data[23:16];
            mem[write_dword_addr + 3] <= write_data[31:24];
            mem[write_dword_addr + 4] <= write_data[39:32];
            mem[write_dword_addr + 5] <= write_data[47:40];
            mem[write_dword_addr + 6] <= write_data[55:48];
            mem[write_dword_addr + 7] <= write_data[63:56];
          end
        end
      endcase
    end
  end

endmodule
