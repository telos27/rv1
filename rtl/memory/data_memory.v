// data_memory.v - RISC-V 数据存储器
// 按字节寻址的存储器，支持字节/半字/字/双字访问
// 作者: RV1 项目组
// 日期: 2025-10-09
// 更新: 2025-10-10 - 参数化 XLEN（支持 32/64 位）
// 更新: 2025-10-22 - 增加 FLEN 参数以支持 RV32D（32 位 CPU 上的 64 位浮点）

`include "config/rv_config.vh"

module data_memory #(
  parameter XLEN     = `XLEN,     // 整数数据宽度：32 或 64 位
  parameter FLEN     = `FLEN,     // 浮点数据宽度：0（无 FPU）、32（仅 F）、或 64（F+D）
  parameter MEM_SIZE = 65536,     // 内存大小（字节），默认 64KB
  parameter MEM_FILE = ""         // 初始化内存用的 hex 文件（用于一致性测试）
) (
  input  wire             clk,         // 时钟
  input  wire [XLEN-1:0]  addr,        // 字节地址
  input  wire [63:0]      write_data,  // 要写入的数据（最大 64 位，适配 RV32D/RV64D）
  input  wire             mem_read,    // 读使能
  input  wire             mem_write,   // 写使能
  input  wire [2:0]       funct3,      // size/符号 的 funct3 编码
  output reg  [63:0]      read_data    // 从内存读出的数据（最大 64 位，适配 RV32D/RV64D）
);

  // 内存阵列（按字节寻址）
  reg [7:0] mem [0:MEM_SIZE-1];

  // 内部信号
  wire [XLEN-1:0] masked_addr;
  wire [XLEN-1:0] word_addr;
  wire [XLEN-1:0] dword_addr;  // RV64 双字访问
  wire [2:0]      byte_offset;
  wire [7:0]      byte_data;
  wire [15:0]     halfword_data;
  wire [31:0]     word_data;
  wire [63:0]     dword_data;  // RV64

  // 对地址进行掩码以限制在存储器大小之内（支持不同基地址）
  assign masked_addr = addr & (MEM_SIZE - 1);
  assign word_addr = {masked_addr[XLEN-1:2], 2'b00};    // 字对齐地址
  assign dword_addr = {masked_addr[XLEN-1:3], 3'b000}; // 双字对齐地址（RV64）
  assign byte_offset = masked_addr[2:0];

  // 从内存中读取数据（小端）
  // 使用 masked_addr 直接读取以支持非对齐访问
  assign byte_data = mem[masked_addr];
  assign halfword_data = {mem[masked_addr + 1], mem[masked_addr]};
  assign word_data = {mem[masked_addr + 3], mem[masked_addr + 2],
                      mem[masked_addr + 1], mem[masked_addr]};

  // RV64 双字数据
  assign dword_data = {mem[masked_addr + 7], mem[masked_addr + 6],
                       mem[masked_addr + 5], mem[masked_addr + 4],
                       mem[masked_addr + 3], mem[masked_addr + 2],
                       mem[masked_addr + 1], mem[masked_addr]};

  // 写操作
  always @(posedge clk) begin
    if (mem_write) begin
      `ifdef DEBUG_ATOMIC
      if (addr >= 32'h80002000 && addr < 32'h80002010)
        $display("[DMEM] WRITE @ 0x%08h = 0x%08h (funct3=%b)", addr, write_data, funct3);
      `endif
      case (funct3)
        3'b000: begin  // SB（存储字节）
          mem[masked_addr] <= write_data[7:0];
        end
        3'b001: begin  // SH（存储半字）
          mem[masked_addr]     <= write_data[7:0];
          mem[masked_addr + 1] <= write_data[15:8];
        end
        3'b010: begin  // SW（存储字）- 支持非对齐访问
          mem[masked_addr]     <= write_data[7:0];
          mem[masked_addr + 1] <= write_data[15:8];
          mem[masked_addr + 2] <= write_data[23:16];
          mem[masked_addr + 3] <= write_data[31:24];
        end
        3'b011: begin  // SD/FSD（存储双字）- 支持 RV64 和 RV32D（FSD）
          // 写入完整 64 位——既支持 RV64 SD 也支持 RV32D FSD
          mem[masked_addr]     <= write_data[7:0];
          mem[masked_addr + 1] <= write_data[15:8];
          mem[masked_addr + 2] <= write_data[23:16];
          mem[masked_addr + 3] <= write_data[31:24];
          mem[masked_addr + 4] <= write_data[39:32];
          mem[masked_addr + 5] <= write_data[47:40];
          mem[masked_addr + 6] <= write_data[55:48];
          mem[masked_addr + 7] <= write_data[63:56];
        end
      endcase
    end
  end

  // 读操作（同步，带输出寄存器）
  // 这与 FPGA BRAM 和 ASIC 编译 SRAM 的行为匹配：
  // - 地址在输入端寄存
  // - 数据在输出端寄存
  // - 总体：1 个周期的读延迟
  // 好处：
  // - 消除仿真中的组合毛刺
  // - 匹配综合硬件行为（BRAM/SRAM 通常都有输出寄存器）
  // - 改善时序收敛（打断长组合路径）
  // - 降低功耗（数据总线无毛刺）
  //
  // 重要：当 mem_read 为低时，输出寄存器保持原值
  // - 这与 FPGA BRAM 行为一致（输出保持有效直到下一次读）
  // - 允许流水线读，不需要一直保持 mem_read 为高
  always @(posedge clk) begin
    if (mem_read) begin
      case (funct3)
        3'b000: begin  // LB（有符号字节加载）
          read_data <= {{56{byte_data[7]}}, byte_data};
        end
        3'b001: begin  // LH（有符号半字加载）
          read_data <= {{48{halfword_data[15]}}, halfword_data};
        end
        3'b010: begin  // LW（字加载，在 RV64 中符号扩展，在 FLW 中零扩展）
          // 对于 RV64 的 LD 进行符号扩展，但对 FLW 上层位会被忽略
          read_data <= {{32{word_data[31]}}, word_data};
        end
        3'b011: begin  // LD/FLD（双字加载）- 支持 RV64 与 RV32D
          // 返回完整 64 位——同时适用于 RV64 LD 和 RV32D FLD
          read_data <= dword_data;
        end
        3'b100: begin  // LBU（无符号字节加载）
          read_data <= {56'h0, byte_data};
        end
        3'b101: begin  // LHU（无符号半字加载）
          read_data <= {48'h0, halfword_data};
        end
        3'b110: begin  // LWU（无符号字加载 - 仅 RV64）
          read_data <= {32'h0, word_data};
        end
        default: begin
          read_data <= 64'h0;
        end
      endcase
    end
    // 注意：没有 'else'——当 mem_read 为低时，输出寄存器保持原值
  end

  // 初始化内存
  initial begin
    integer i;

    // 初始化输出寄存器为 0
    read_data = 64'h0;

    // 将内存数组初始化为 0
    for (i = 0; i < MEM_SIZE; i = i + 1) begin
      mem[i] = 8'h0;
    end

    // 如果指定了文件，则从文件加载（用于带嵌入数据的一致性测试）
    // 使用 "objcopy -O verilog" 生成的 hex 文件为以空格分隔的十六进制字节
    // $readmemh 会将每个以空格分隔的值视为一个字节
    // 注意：hex 文件中的地址可能超出本模块的地址范围，这没关系，
    // 因为我们使用地址掩码将访问映射回本内存空间
    if (MEM_FILE != "") begin
      $readmemh(MEM_FILE, mem);
    end
  end

endmodule
