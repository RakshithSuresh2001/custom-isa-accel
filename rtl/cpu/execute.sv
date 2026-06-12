// EX Stage: ALU + Branch Resolution + Forwarding + Accelerator Dispatch
`timescale 1ns/1ps
`default_nettype none

module execute (
    input  wire        clk,
    input  wire        rst_n,
    // From ID
    input  wire [31:0] pc_in,
    input  wire [31:0] rs1_in,
    input  wire [31:0] rs2_in,
    input  wire [31:0] imm_in,
    input  wire [4:0]  rs1_addr_in,
    input  wire [4:0]  rs2_addr_in,
    input  wire [4:0]  rd_addr_in,
    input  wire [3:0]  alu_op_in,
    input  wire        alu_src_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        reg_write_in,
    input  wire        branch_in,
    input  wire [2:0]  funct3_in,
    input  wire        jal_in,
    input  wire        predicted_taken_in,
    input  wire        mem_to_reg_in,
    // Accelerator signals from ID
    input  wire        accel_in,
    input  wire [2:0]  accel_op_in,
    // Forwarding inputs
    input  wire [31:0] fwd_ex_mem,
    input  wire [31:0] fwd_mem_wb,
    input  wire [1:0]  fwd_sel_rs1,
    input  wire [1:0]  fwd_sel_rs2,
    // Accelerator done signal
    input  wire        accel_done,
    // AXI-Lite master outputs to accelerator
    output reg  [31:0] axil_awaddr,
    output reg         axil_awvalid,
    output reg  [31:0] axil_wdata,
    output reg         axil_wvalid,
    output reg         axil_araddr,
    output reg         axil_arvalid,
    // Stall to hazard unit
    output wire        accel_stall,
    // Standard outputs
    output reg  [31:0] alu_result_out,
    output reg  [31:0] rs2_out,
    output reg  [4:0]  rd_addr_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg         reg_write_out,
    output reg         mem_to_reg_out,
    output wire        branch_taken,
    output wire [31:0] branch_target,
    output wire [31:0] branch_fallthrough,
    output wire        mispredict
);

    // Forwarding mux
    wire [31:0] rs1_fwd = (fwd_sel_rs1 == 2'b10) ? fwd_ex_mem :
                          (fwd_sel_rs1 == 2'b01) ? fwd_mem_wb : rs1_in;
    wire [31:0] rs2_fwd = (fwd_sel_rs2 == 2'b10) ? fwd_ex_mem :
                          (fwd_sel_rs2 == 2'b01) ? fwd_mem_wb : rs2_in;

    wire [31:0] alu_b = alu_src_in ? imm_in : rs2_fwd;

    // ALU
    reg [31:0] alu_result;
    always_comb begin
        case (alu_op_in)
            4'd0:  alu_result = rs1_fwd + alu_b;
            4'd1:  alu_result = rs1_fwd - alu_b;
            4'd2:  alu_result = rs1_fwd & alu_b;
            4'd3:  alu_result = rs1_fwd | alu_b;
            4'd4:  alu_result = rs1_fwd ^ alu_b;
            4'd5:  alu_result = rs1_fwd << alu_b[4:0];
            4'd6:  alu_result = rs1_fwd >> alu_b[4:0];
            4'd7:  alu_result = $signed(rs1_fwd) >>> alu_b[4:0];
            4'd8:  alu_result = ($signed(rs1_fwd) < $signed(alu_b)) ? 1 : 0;
            4'd9:  alu_result = (rs1_fwd < alu_b) ? 1 : 0;
            4'd10: alu_result = alu_b;
            4'd11: alu_result = pc_in + alu_b;
            default: alu_result = 32'b0;
        endcase
    end

    // Branch resolution
    reg branch_cond;
    always_comb begin
        case (funct3_in)
            3'b000: branch_cond = (rs1_fwd == rs2_fwd);
            3'b001: branch_cond = (rs1_fwd != rs2_fwd);
            3'b100: branch_cond = ($signed(rs1_fwd) < $signed(rs2_fwd));
            3'b101: branch_cond = ($signed(rs1_fwd) >= $signed(rs2_fwd));
            3'b110: branch_cond = (rs1_fwd < rs2_fwd);
            3'b111: branch_cond = (rs1_fwd >= rs2_fwd);
            default: branch_cond = 1'b0;
        endcase
    end

    assign branch_taken       = branch_in & (branch_cond | jal_in);
    assign branch_target      = pc_in + imm_in;
    assign branch_fallthrough = pc_in + 4;
    assign mispredict         = branch_in & ((branch_cond | jal_in) ^ predicted_taken_in);

    wire [31:0] alu_result_final = jal_in ? (pc_in + 4) : alu_result;

    // Accelerator FSM
    // Stalls pipeline on MMUL until accel_done pulses
    localparam ACCEL_MLOAD  = 3'b000;
    localparam ACCEL_MMUL   = 3'b001;
    localparam ACCEL_MSTORE = 3'b010;

    // AXI-Lite base addresses — update these once you finalize the memory map
    localparam [31:0] AXIL_MLOAD_ADDR  = 32'hA000_0000;  // write base_addr + matrix_id
    localparam [31:0] AXIL_MMUL_KICK   = 32'hA000_0004;  // write 1 to kick
    localparam [31:0] AXIL_MSTORE_ADDR = 32'hA000_0008;  // write dest base_addr

    reg accel_busy;
    assign accel_stall = accel_in & (accel_op_in == ACCEL_MMUL) & accel_busy;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accel_busy   <= 1'b0;
            axil_awaddr  <= 32'b0;
            axil_awvalid <= 1'b0;
            axil_wdata   <= 32'b0;
            axil_wvalid  <= 1'b0;
            axil_araddr  <= 1'b0;
            axil_arvalid <= 1'b0;
        end else begin
            // Default: deassert valids each cycle
            axil_awvalid <= 1'b0;
            axil_wvalid  <= 1'b0;
            axil_arvalid <= 1'b0;

            if (accel_in && !accel_busy) begin
                case (accel_op_in)
                    ACCEL_MLOAD: begin
                        // rs1 = base_addr, rs2 = matrix_id
                        axil_awaddr  <= AXIL_MLOAD_ADDR;
                        axil_awvalid <= 1'b1;
                        axil_wdata   <= {rs2_fwd[0], rs1_fwd[30:0]}; // pack matrix_id + addr
                        axil_wvalid  <= 1'b1;
                    end
                    ACCEL_MMUL: begin
                        // Kick and wait
                        axil_awaddr  <= AXIL_MMUL_KICK;
                        axil_awvalid <= 1'b1;
                        axil_wdata   <= 32'h1;
                        axil_wvalid  <= 1'b1;
                        accel_busy   <= 1'b1;
                    end
                    ACCEL_MSTORE: begin
                        // rs1 = destination base addr
                        axil_awaddr  <= AXIL_MSTORE_ADDR;
                        axil_awvalid <= 1'b1;
                        axil_wdata   <= rs1_fwd;
                        axil_wvalid  <= 1'b1;
                    end
                    default: begin end
                endcase
            end

            // Clear busy when accelerator signals done
            if (accel_busy && accel_done) begin
                accel_busy <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_out <= 32'b0;
            rs2_out        <= 32'b0;
            rd_addr_out    <= 5'b0;
            mem_read_out   <= 1'b0;
            mem_write_out  <= 1'b0;
            reg_write_out  <= 1'b0;
            mem_to_reg_out <= 1'b0;
        end else begin
            alu_result_out <= alu_result_final;
            rs2_out        <= rs2_fwd;
            rd_addr_out    <= rd_addr_in;
            mem_read_out   <= mem_read_in;
            mem_write_out  <= mem_write_in;
            reg_write_out  <= reg_write_in;
            mem_to_reg_out <= mem_to_reg_in;
        end
    end

endmodule
`default_nettype wire
