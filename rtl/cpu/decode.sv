// ID Stage: Decode + Register Read
// Extended with custom-0 (7'b0001011) accelerator instructions
`timescale 1ns/1ps
`default_nettype none

module decode (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    // From IF
    input  wire [31:0] pc_in,
    input  wire [31:0] instr_in,
    input  wire        predicted_taken_in,
    // Register file
    output wire [4:0]  rs1_addr,
    output wire [4:0]  rs2_addr,
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    // To EX
    output reg  [31:0] pc_out,
    output reg  [31:0] rs1_out,
    output reg  [31:0] rs2_out,
    output reg  [31:0] imm_out,
    output reg  [4:0]  rs1_addr_out,
    output reg  [4:0]  rs2_addr_out,
    output reg  [4:0]  rd_addr_out,
    output reg  [3:0]  alu_op_out,
    output reg         alu_src_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg         reg_write_out,
    output reg         branch_out,
    output reg         mem_to_reg_out,
    output reg         predicted_taken_out,
    output reg  [2:0]  funct3_out,
    output reg         jal_out,
    output reg         accel_out,
    output reg  [2:0]  accel_op_out
);

    // Instruction fields
    wire [6:0] opcode = instr_in[6:0];
    wire [4:0] rd     = instr_in[11:7];
    wire [2:0] funct3 = instr_in[14:12];
    wire [4:0] rs1    = instr_in[19:15];
    wire [4:0] rs2    = instr_in[24:20];
    wire [6:0] funct7 = instr_in[31:25];

    assign rs1_addr = rs1;
    assign rs2_addr = rs2;

    // Immediate generation
    wire [31:0] imm_i = {{20{instr_in[31]}}, instr_in[31:20]};
    wire [31:0] imm_s = {{20{instr_in[31]}}, instr_in[31:25], instr_in[11:7]};
    wire [31:0] imm_b = {{19{instr_in[31]}}, instr_in[31], instr_in[7],
                          instr_in[30:25], instr_in[11:8], 1'b0};
    wire [31:0] imm_u = {instr_in[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr_in[31]}}, instr_in[31], instr_in[19:12],
                          instr_in[20], instr_in[30:21], 1'b0};

    // ALU ops
    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_AND  = 4'd2;
    localparam ALU_OR   = 4'd3;
    localparam ALU_XOR  = 4'd4;
    localparam ALU_SLL  = 4'd5;
    localparam ALU_SRL  = 4'd6;
    localparam ALU_SRA  = 4'd7;
    localparam ALU_SLT  = 4'd8;
    localparam ALU_SLTU = 4'd9;
    localparam ALU_LUI  = 4'd10;
    localparam ALU_AUIPC= 4'd11;

    // Accelerator instruction types (custom-0 opcode = 7'b0001011)
    localparam ACCEL_MLOAD  = 3'b000;
    localparam ACCEL_MMUL   = 3'b001;
    localparam ACCEL_MSTORE = 3'b010;

    // Decode signals
    reg [31:0] imm;
    reg [3:0]  alu_op;
    reg        alu_src, mem_read, mem_write, reg_write, branch, mem_to_reg;
    reg        accel;
    reg [2:0]  accel_op;

    always_comb begin
        imm        = 32'b0;
        alu_op     = ALU_ADD;
        alu_src    = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        reg_write  = 1'b0;
        branch     = 1'b0;
        mem_to_reg = 1'b0;
        accel      = 1'b0;
        accel_op   = 3'b0;

        case (opcode)
            7'b0110011: begin // R-type
                reg_write = 1'b1;
                case ({funct7, funct3})
                    10'b0000000_000: alu_op = ALU_ADD;
                    10'b0100000_000: alu_op = ALU_SUB;
                    10'b0000000_111: alu_op = ALU_AND;
                    10'b0000000_110: alu_op = ALU_OR;
                    10'b0000000_100: alu_op = ALU_XOR;
                    10'b0000000_001: alu_op = ALU_SLL;
                    10'b0000000_101: alu_op = ALU_SRL;
                    10'b0100000_101: alu_op = ALU_SRA;
                    10'b0000000_010: alu_op = ALU_SLT;
                    10'b0000000_011: alu_op = ALU_SLTU;
                    default:         alu_op = ALU_ADD;
                endcase
            end
            7'b0010011: begin // I-type ALU
                alu_src   = 1'b1;
                reg_write = 1'b1;
                imm       = imm_i;
                case (funct3)
                    3'b000: alu_op = ALU_ADD;
                    3'b111: alu_op = ALU_AND;
                    3'b110: alu_op = ALU_OR;
                    3'b100: alu_op = ALU_XOR;
                    3'b001: alu_op = ALU_SLL;
                    3'b101: alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    default: alu_op = ALU_ADD;
                endcase
            end
            7'b0000011: begin // Load
                alu_src    = 1'b1;
                mem_read   = 1'b1;
                reg_write  = 1'b1;
                mem_to_reg = 1'b1;
                imm        = imm_i;
            end
            7'b0100011: begin // Store
                alu_src   = 1'b1;
                mem_write = 1'b1;
                imm       = imm_s;
            end
            7'b1100011: begin // Branch
                branch = 1'b1;
                imm    = imm_b;
            end
            7'b0110111: begin // LUI
                alu_src   = 1'b1;
                reg_write = 1'b1;
                alu_op    = ALU_LUI;
                imm       = imm_u;
            end
            7'b0010111: begin // AUIPC
                alu_src   = 1'b1;
                reg_write = 1'b1;
                alu_op    = ALU_AUIPC;
                imm       = imm_u;
            end
            7'b1101111: begin // JAL
                reg_write = 1'b1;
                branch    = 1'b1;
                alu_src   = 1'b1;
                imm       = imm_j;
            end
            7'b0001011: begin // custom-0: accelerator instructions
                case (funct3)
                    ACCEL_MLOAD: begin
                        accel    = 1'b1;
                        accel_op = ACCEL_MLOAD;
                        alu_src  = 1'b0;
                    end
                    ACCEL_MMUL: begin
                        accel    = 1'b1;
                        accel_op = ACCEL_MMUL;
                    end
                    ACCEL_MSTORE: begin
                        accel    = 1'b1;
                        accel_op = ACCEL_MSTORE;
                        alu_src  = 1'b0;
                    end
                    default: begin end
                endcase
            end
            default: begin end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            pc_out              <= 32'b0;
            rs1_out             <= 32'b0;
            rs2_out             <= 32'b0;
            imm_out             <= 32'b0;
            rs1_addr_out        <= 5'b0;
            rs2_addr_out        <= 5'b0;
            rd_addr_out         <= 5'b0;
            alu_op_out          <= 4'b0;
            alu_src_out         <= 1'b0;
            mem_read_out        <= 1'b0;
            mem_write_out       <= 1'b0;
            reg_write_out       <= 1'b0;
            branch_out          <= 1'b0;
            mem_to_reg_out      <= 1'b0;
            predicted_taken_out <= 1'b0;
            funct3_out          <= 3'b0;
            jal_out             <= 1'b0;
            accel_out           <= 1'b0;
            accel_op_out        <= 3'b0;
        end else if (!stall) begin
            pc_out              <= pc_in;
            rs1_out             <= rs1_data;
            rs2_out             <= rs2_data;
            imm_out             <= imm;
            rs1_addr_out        <= rs1;
            rs2_addr_out        <= rs2;
            rd_addr_out         <= rd;
            alu_op_out          <= alu_op;
            alu_src_out         <= alu_src;
            mem_read_out        <= mem_read;
            mem_write_out       <= mem_write;
            reg_write_out       <= reg_write;
            branch_out          <= branch;
            mem_to_reg_out      <= mem_to_reg;
            predicted_taken_out <= predicted_taken_in;
            funct3_out          <= funct3;
            jal_out             <= (opcode == 7'b1101111);
            accel_out           <= accel;
            accel_op_out        <= accel_op;
        end
    end

endmodule
`default_nettype wire
