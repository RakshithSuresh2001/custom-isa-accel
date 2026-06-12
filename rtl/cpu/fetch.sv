// IF Stage: PC + Instruction Fetch + Branch Prediction
`timescale 1ns/1ps
`default_nettype none
module fetch (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    // Branch resolution from EX
    input  wire        branch_taken,
    input  wire [31:0] branch_target,
    input  wire        mispredict,       // EX says prediction was wrong
    // BHT predict interface
    input  wire        predict_taken,
    output reg  [31:0] pc_out,
    output reg  [31:0] instr_out,
    output reg         predicted_taken_out, // pass to decode→EX for comparison
    // Instruction memory interface
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data
);
    reg [31:0] pc;
    assign imem_addr = pc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc                  <= 32'h0000_0000;
            pc_out              <= 32'h0000_0000;
            instr_out           <= 32'h0000_0013;
            predicted_taken_out <= 1'b0;
        end else if (stall) begin
            // Hold
        end else if (branch_taken | mispredict) begin
            // Flush and redirect to correct target
            pc                  <= branch_target;
            pc_out              <= branch_target;
            instr_out           <= 32'h0000_0013;
            predicted_taken_out <= 1'b0;
        end else if (predict_taken) begin
            // Speculative taken — need branch_target from decode (not yet available)
            // For now: predict taken but still advance PC+4 (will fix with BTB later)
            pc                  <= pc + 4;
            pc_out              <= pc;
            instr_out           <= imem_data;
            predicted_taken_out <= 1'b1;
        end else begin
            pc                  <= pc + 4;
            pc_out              <= pc;
            instr_out           <= imem_data;
            predicted_taken_out <= 1'b0;
        end
    end
endmodule
`default_nettype wire
