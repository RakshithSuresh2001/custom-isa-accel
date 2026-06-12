// WB Stage: Register Writeback
`timescale 1ns/1ps
`default_nettype none

module writeback (
    input  wire [31:0] alu_result_in,
    input  wire [31:0] mem_data_in,
    input  wire [4:0]  rd_addr_in,
    input  wire        reg_write_in,
    input  wire        mem_to_reg_in,
    output wire [31:0] wb_data,
    output wire [4:0]  wb_addr,
    output wire        wb_en
);

    assign wb_data = mem_to_reg_in ? mem_data_in : alu_result_in;
    assign wb_addr = rd_addr_in;
    assign wb_en   = reg_write_in;

endmodule
`default_nettype wire

