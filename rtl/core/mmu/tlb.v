// tlb.v - 翻译后备缓冲区 (TLB)
// 可复用的 TLB 模块，同时用于 I-TLB 和 D-TLB
// 提供快速虚拟地址到物理地址的翻译，并进行权限检查
// 作者：RV1 项目组
// 日期：2025-11-08 (Session 125)

`include "config/rv_config.vh"

module tlb #(
  parameter XLEN = `XLEN,
  parameter TLB_ENTRIES = 8  // TLB 项目数
) (
  input  wire             clk,
  input  wire             reset_n,

  // 查表请求
  input  wire             lookup_valid,      // 查表请求有效
  input  wire [XLEN-1:0]  lookup_vaddr,      // 需要翻译的虚拟地址
  input  wire             lookup_is_store,   // 1=写存储(store)，0=读(load)
  input  wire             lookup_is_fetch,   // 1=取指(fetch)，0=数据访问
  output wire             lookup_hit,        // TLB 命中
  output wire [XLEN-1:0]  lookup_paddr,      // 物理地址（命中时）
  output wire             lookup_page_fault, // 页错误（命中但权限不允许时）

  // 来自 PTW 的 TLB 更新
  input  wire             update_valid,      // 更新 TLB 项
  input  wire [XLEN-1:0]  update_vpn,        // 虚拟页号 VPN
  input  wire [XLEN-1:0]  update_ppn,        // 物理页号 PPN
  input  wire [7:0]       update_pte,        // PTE 标志位 (V,R,W,X,U,G,A,D)
  input  wire [XLEN-1:0]  update_level,      // 页级别 (0=4KB, 1=2/4MB, 2=1GB)

  // 用于权限检查的 CSR 接口
  input  wire [1:0]       privilege_mode,    // 当前特权级 (0=U, 1=S, 3=M)
  input  wire             mstatus_sum,       // Supervisor User Memory 访问允许
  input  wire             mstatus_mxr,       // Make eXecutable Readable
  input  wire             translation_enabled, // 启用地址翻译 (satp.MODE != 0)

  // TLB 刷新控制
  input  wire             flush_all,         // 刷新整张 TLB
  input  wire             flush_vaddr,       // 按虚拟地址刷新
  input  wire [XLEN-1:0]  flush_addr         // 要刷新的虚拟地址（当 flush_vaddr=1 时有效）
);

  // =========================================================================
  // RISC-V 虚拟内存参数
  // =========================================================================

  localparam PAGE_SHIFT = 12;  // 4KB 页

  // PTE (页表项) 位编码
  localparam PTE_V = 0;  // 是否有效
  localparam PTE_R = 1;  // 可读
  localparam PTE_W = 2;  // 可写
  localparam PTE_X = 3;  // 可执行
  localparam PTE_U = 4;  // 用户可访问
  localparam PTE_G = 5;  // 全局映射
  localparam PTE_A = 6;  // 访问标记
  localparam PTE_D = 7;  // 脏页标记

  // =========================================================================
  // TLB 存储结构
  // =========================================================================

  reg                   tlb_valid [0:TLB_ENTRIES-1];
  reg [XLEN-1:0]        tlb_vpn   [0:TLB_ENTRIES-1];  // 虚拟页号 VPN
  reg [XLEN-1:0]        tlb_ppn   [0:TLB_ENTRIES-1];  // 物理页号 PPN
  reg [7:0]             tlb_pte   [0:TLB_ENTRIES-1];  // PTE 标志位
  reg [XLEN-1:0]        tlb_level [0:TLB_ENTRIES-1];  // 页级别

  // TLB 替换策略：简单轮询 (round-robin)
  reg [$clog2(TLB_ENTRIES)-1:0] tlb_replace_idx;

  // =========================================================================
  // VPN 提取
  // =========================================================================

  function [XLEN-1:0] get_full_vpn;
    input [XLEN-1:0] vaddr;
    begin
      if (XLEN == 32) begin
        // Sv32: VPN = bits[31:12] (20 位)
        get_full_vpn = {{(XLEN-20){1'b0}}, vaddr[31:12]};
      end else begin
        // Sv39: VPN = bits[38:12] (27 位)
        get_full_vpn = {{(XLEN-27){1'b0}}, vaddr[38:12]};
      end
    end
  endfunction

  // =========================================================================
  // TLB 查表逻辑（组合逻辑）
  // =========================================================================

  reg tlb_hit_found;
  reg [$clog2(TLB_ENTRIES)-1:0] tlb_hit_idx;
  reg [XLEN-1:0] tlb_ppn_out;
  reg [7:0] tlb_pte_out;
  reg [XLEN-1:0] tlb_level_out;

  integer i;
  always @(*) begin
    tlb_hit_found = 0;
    tlb_hit_idx = 0;
    tlb_ppn_out = 0;
    tlb_pte_out = 0;
    tlb_level_out = 0;

    if (translation_enabled && lookup_valid) begin
      for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
        if (tlb_valid[i] && (tlb_vpn[i] == get_full_vpn(lookup_vaddr))) begin
          tlb_hit_found = 1;
          tlb_hit_idx = i[$clog2(TLB_ENTRIES)-1:0];
          tlb_ppn_out = tlb_ppn[i];
          tlb_pte_out = tlb_pte[i];
          tlb_level_out = tlb_level[i];
        end
      end
    end
  end

  // 调试：打印 TLB 查表信息
  always @(posedge clk) begin
    if (lookup_valid && translation_enabled && reset_n) begin
      $display("[TLB_LOOKUP] VA=0x%h VPN=0x%h hit=%b fetch=%b",
               lookup_vaddr, get_full_vpn(lookup_vaddr), lookup_hit, lookup_is_fetch);
      for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
        if (tlb_valid[i]) begin
          $display("[TLB_LOOKUP]   Entry[%0d]: VPN=0x%h match=%b",
                   i, tlb_vpn[i], (tlb_vpn[i] == get_full_vpn(lookup_vaddr)));
        end
      end
    end
  end

  assign lookup_hit = tlb_hit_found;

  // =========================================================================
  // 权限检查（组合逻辑）
  // =========================================================================

  function check_permission;
    input [7:0] pte_flags;
    input is_store;
    input is_fetch;
    input [1:0] priv_mode;
    input sum;
    input mxr;
    begin
      check_permission = 1;

      // 检查有效位
      if (!pte_flags[PTE_V]) begin
        check_permission = 0;
      end
      // 检查是否为叶子 PTE（至少 R 或 X 之一为 1）
      else if (!pte_flags[PTE_R] && !pte_flags[PTE_W] && !pte_flags[PTE_X]) begin
        check_permission = 0;  // 非叶子 PTE
      end
      // 检查写权限（W=1 要求 R=1）
      else if (pte_flags[PTE_W] && !pte_flags[PTE_R]) begin
        check_permission = 0;
      end
      // 用户态访问检查
      else if (priv_mode == 2'b00) begin  // 用户态（User mode）
        if (!pte_flags[PTE_U]) begin
          check_permission = 0;  // 用户访问 S 态页
        end
      end
      else if (priv_mode == 2'b01) begin  // 监督者态 (Supervisor mode)
        if (pte_flags[PTE_U] && !sum) begin
          check_permission = 0;  // S 态访问 U 态页且 SUM=0
        end
      end

      // 按访问类型检查权限
      if (check_permission) begin
        if (is_fetch) begin
          check_permission = pte_flags[PTE_X];
        end else if (is_store) begin
          check_permission = pte_flags[PTE_W];
        end else begin
          // load：需要 R，或 (X 且 MXR=1)
          check_permission = pte_flags[PTE_R] || (pte_flags[PTE_X] && mxr);
        end
      end
    end
  endfunction

  // 查表访问的权限检查
  wire perm_ok = check_permission(tlb_pte_out, lookup_is_store, lookup_is_fetch,
                                  privilege_mode, mstatus_sum, mstatus_mxr);

  assign lookup_page_fault = tlb_hit_found && !perm_ok;

  // =========================================================================
  // 物理地址构造（组合逻辑）
  // =========================================================================

  // 根据页级别，从 PPN 和虚拟地址构造物理地址
  function [XLEN-1:0] construct_pa;
    input [XLEN-1:0] ppn;    // PTE 中的完整 PPN
    input [XLEN-1:0] vaddr;  // 虚拟地址
    input [XLEN-1:0] level;  // 页表级别
    begin
      if (XLEN == 32) begin
        // Sv32
        case (level)
          0: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};     // 4KB
          1: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:10], vaddr[PAGE_SHIFT+9:0]};    // 4MB
          default: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};
        endcase
      end else begin
        // Sv39
        case (level)
          0: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};     // 4KB
          1: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:9], vaddr[PAGE_SHIFT+8:0]};     // 2MB
          2: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:18], vaddr[PAGE_SHIFT+17:0]};   // 1GB
          default: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};
        endcase
      end
    end
  endfunction

  assign lookup_paddr = construct_pa(tlb_ppn_out, lookup_vaddr, tlb_level_out);

  // =========================================================================
  // TLB 更新与刷新逻辑（时序逻辑）
  // =========================================================================

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      tlb_replace_idx <= 0;
      for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
        tlb_valid[i] <= 0;
        tlb_vpn[i] <= 0;
        tlb_ppn[i] <= 0;
        tlb_pte[i] <= 0;
        tlb_level[i] <= 0;
      end
    end else begin
      // TLB 刷新逻辑
      if (flush_all) begin
        for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
          tlb_valid[i] <= 0;
        end
      end else if (flush_vaddr) begin
        for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
          if (tlb_vpn[i] == get_full_vpn(flush_addr)) begin
            tlb_valid[i] <= 0;
          end
        end
      end

      // 来自 PTW 的 TLB 更新
      if (update_valid) begin
        tlb_valid[tlb_replace_idx] <= 1;
        tlb_vpn[tlb_replace_idx] <= update_vpn;
        tlb_ppn[tlb_replace_idx] <= update_ppn;
        tlb_pte[tlb_replace_idx] <= update_pte;
        tlb_level[tlb_replace_idx] <= update_level;
        tlb_replace_idx <= tlb_replace_idx + 1;
        $display("[TLB] 更新条目[%0d]: VPN=0x%h PPN=0x%h pte=0x%02h level=%0d fetch=%b",
                 tlb_replace_idx, update_vpn, update_ppn, update_pte, update_level, lookup_is_fetch);
      end
    end
  end

endmodule
