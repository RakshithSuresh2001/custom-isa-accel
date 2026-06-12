// MEM Stage: Data Memory Access
`timescale 1ns/1ps
`default_nettype none

module memory_stage (
    input  wire        clk,
    input  wire        rst_n,
    // From EX
    input  wire [31:0] alu_result_in,
    input  wire [31:0] rs2_in,
    input  wire [4:0]  rd_addr_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        reg_write_in,
    input  wire        mem_to_reg_in,
    // Data memory interface
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire        dmem_wr_en,
    input  wire [31:0] dmem_rdata,
    // To WB
    output reg  [31:0] alu_result_out,
    output reg  [31:0] mem_data_out,
    output reg  [4:0]  rd_addr_out,
    output reg         reg_write_out,
    output reg         mem_to_reg_out
);

    assign dmem_addr  = alu_result_in;
    assign dmem_wdata = rs2_in;
    assign dmem_wr_en = mem_write_in;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_out <= 32'b0;
            mem_data_out   <= 32'b0;
            rd_addr_out    <= 5'b0;
            reg_write_out  <= 1'b0;
            mem_to_reg_out <= 1'b0;
        end else begin
            alu_result_out <= alu_result_in;
            mem_data_out   <= dmem_rdata;
            rd_addr_out    <= rd_addr_in;
            reg_write_out  <= reg_write_in;
            mem_to_reg_out <= mem_to_reg_in;
        end
    end

endmodule
`default_nettype wire
