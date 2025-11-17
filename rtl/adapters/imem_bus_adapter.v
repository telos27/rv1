// imem_bus_adapter.v - IMEM 总线适配器
// 将指令存储器适配为总线访问（只读）
// 作者: RV1 项目组
// 日期: 2025-10-27（Session 33）
//
// 目的：允许从 IMEM 进行数据加载，用于 .rodata 段拷贝
// 这使得在哈佛结构系统中，启动代码可以将只读数据从 IMEM 拷贝到 DMEM。

`include "config/rv_config.vh"

module imem_bus_adapter (
  input  wire             clk,
  input  wire             reset_n,

  // 总线从设备接口（只读）
  input  wire             req_valid,
  input  wire [31:0]      req_addr,
  output wire             req_ready,
  output wire [31:0]      req_rdata,

  // 指令存储器接口
  output wire [31:0]      imem_addr,
  input  wire [31:0]      imem_rdata
);

  // 简单直通——IMEM 已经是组合读
  assign imem_addr  = req_addr;
  assign req_rdata  = imem_rdata;
  assign req_ready  = req_valid;  // 读请求总是立即 ready

endmodule
