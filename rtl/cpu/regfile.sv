// RV32I Register File
// 32 x 32-bit registers, x0 hardwired to 0
// Two read ports, one write port
`timescale 1ns/1ps
`default_nettype none

module regfile (
    input  wire        clk,
    input  wire        rst_n,
    // Read ports
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,
    // Write port
    input  wire        wr_en,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data
);

    reg [31:0] regs [1:31];

    // Synchronous write
    always_ff @(posedge clk) begin
        if (wr_en && rd_addr != 5'b0)
            regs[rd_addr] <= rd_data;
    end

    // Asynchronous read with write-first bypass (WB->ID forward)
    assign rs1_data = (rs1_addr == 5'b0)                    ? 32'b0      :
                      (wr_en && rd_addr == rs1_addr)         ? rd_data    :
                      regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'b0)                    ? 32'b0      :
                      (wr_en && rd_addr == rs2_addr)         ? rd_data    :
                      regs[rs2_addr];

endmodule
`default_nettype wire
