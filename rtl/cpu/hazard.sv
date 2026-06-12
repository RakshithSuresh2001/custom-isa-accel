// Hazard Detection + Forwarding Unit
`timescale 1ns/1ps
`default_nettype none

module hazard (
    // ID/EX pipeline registers
    input  wire [4:0]  id_rs1_addr,
    input  wire [4:0]  id_rs2_addr,
    input  wire [4:0]  ex_rd_addr,
    input  wire        ex_mem_read,
    // EX/MEM pipeline registers
    input  wire [4:0]  ex_mem_rd_addr,
    input  wire        ex_mem_reg_write,
    // MEM/WB pipeline registers
    input  wire [4:0]  mem_wb_rd_addr,
    input  wire        mem_wb_reg_write,
    // Accelerator stall from execute
    input  wire        accel_stall,
    // Outputs
    output wire        stall,
    output wire [1:0]  fwd_sel_rs1,
    output wire [1:0]  fwd_sel_rs2
);

    // Load-use hazard stall OR accelerator busy stall
    wire load_use_stall = ex_mem_read &&
                          ((ex_rd_addr == id_rs1_addr) ||
                           (ex_rd_addr == id_rs2_addr));

    assign stall = load_use_stall | accel_stall;

    // Forwarding: EX/MEM takes priority over MEM/WB
    assign fwd_sel_rs1 =
        (ex_mem_reg_write && ex_mem_rd_addr != 0 &&
         ex_mem_rd_addr == id_rs1_addr) ? 2'b10 :
        (mem_wb_reg_write && mem_wb_rd_addr != 0 &&
         mem_wb_rd_addr == id_rs1_addr) ? 2'b01 : 2'b00;

    assign fwd_sel_rs2 =
        (ex_mem_reg_write && ex_mem_rd_addr != 0 &&
         ex_mem_rd_addr == id_rs2_addr) ? 2'b10 :
        (mem_wb_reg_write && mem_wb_rd_addr != 0 &&
         mem_wb_rd_addr == id_rs2_addr) ? 2'b01 : 2'b00;

endmodule
`default_nettype wire
