// RV32I 5-Stage Pipeline + Custom ISA Accelerator Extension
`timescale 1ns/1ps
`default_nettype none

module cpu_top (
    input  wire        clk,
    input  wire        rst_n,
    // Instruction memory
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,
    // Data memory
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire        dmem_wr_en,
    input  wire [31:0] dmem_rdata,
    // AXI-Lite master to accelerator
    output wire [31:0] axil_awaddr,
    output wire        axil_awvalid,
    output wire [31:0] axil_wdata,
    output wire        axil_wvalid,
    output wire        axil_araddr,
    output wire        axil_arvalid,
    // Accelerator done
    input  wire        accel_done
);

    // IF outputs
    wire [31:0] if_pc, if_instr;

    // ID outputs
    wire [31:0] id_pc, id_rs1, id_rs2, id_imm;
    wire [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    wire [3:0]  id_alu_op;
    wire        id_alu_src, id_mem_read, id_mem_write;
    wire [2:0]  id_funct3;
    wire        id_jal;
    wire        id_reg_write, id_branch, id_mem_to_reg;
    wire [4:0]  id_rs1_addr_rf, id_rs2_addr_rf;
    wire [31:0] id_rs1_data_rf, id_rs2_data_rf;
    wire        id_accel;
    wire [2:0]  id_accel_op;

    // EX outputs
    wire [31:0] ex_alu_result, ex_rs2;
    wire [4:0]  ex_rd_addr;
    wire        ex_mem_read, ex_mem_write, ex_reg_write, ex_mem_to_reg;
    wire        branch_taken;
    wire [31:0] branch_target;
    wire        accel_stall;

    // MEM outputs
    wire [31:0] mem_alu_result, mem_data;
    wire [4:0]  mem_rd_addr;
    wire        mem_reg_write, mem_mem_to_reg;

    // WB outputs
    wire [31:0] wb_data;
    wire [4:0]  wb_addr;
    wire        wb_en;

    wire        mispredict;
    wire        predict_taken;
    wire [31:0] branch_fallthrough;
    wire [31:0] correct_pc;
    wire        id_predicted_taken;
    wire        id_predicted_taken_fetch;
    wire        stall;
    wire [1:0]  fwd_sel_rs1, fwd_sel_rs2;

    assign correct_pc = branch_taken ? branch_target : branch_fallthrough;

    fetch u_fetch (
        .clk                 (clk),
        .rst_n               (rst_n),
        .stall               (stall),
        .branch_taken        (branch_taken),
        .branch_target       (correct_pc),
        .mispredict          (mispredict),
        .predict_taken       (predict_taken),
        .pc_out              (if_pc),
        .instr_out           (if_instr),
        .predicted_taken_out (id_predicted_taken_fetch),
        .imem_addr           (imem_addr),
        .imem_data           (imem_data)
    );

    bht u_bht (
        .clk          (clk),
        .rst_n        (rst_n),
        .pc_fetch     (imem_addr),
        .predict_taken(predict_taken),
        .update_en    (branch_taken | mispredict),
        .pc_ex        (id_pc),
        .actual_taken (branch_taken)
    );

    decode u_decode (
        .clk                 (clk),
        .rst_n               (rst_n),
        .stall               (stall),
        .flush               (branch_taken | mispredict),
        .pc_in               (if_pc),
        .predicted_taken_in  (id_predicted_taken_fetch),
        .instr_in            (if_instr),
        .rs1_addr            (id_rs1_addr_rf),
        .rs2_addr            (id_rs2_addr_rf),
        .rs1_data            (id_rs1_data_rf),
        .rs2_data            (id_rs2_data_rf),
        .pc_out              (id_pc),
        .rs1_out             (id_rs1),
        .rs2_out             (id_rs2),
        .imm_out             (id_imm),
        .rs1_addr_out        (id_rs1_addr),
        .rs2_addr_out        (id_rs2_addr),
        .rd_addr_out         (id_rd_addr),
        .alu_op_out          (id_alu_op),
        .alu_src_out         (id_alu_src),
        .mem_read_out        (id_mem_read),
        .mem_write_out       (id_mem_write),
        .reg_write_out       (id_reg_write),
        .branch_out          (id_branch),
        .mem_to_reg_out      (id_mem_to_reg),
        .predicted_taken_out (id_predicted_taken),
        .funct3_out          (id_funct3),
        .jal_out             (id_jal),
        .accel_out           (id_accel),
        .accel_op_out        (id_accel_op)
    );

    regfile u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (id_rs1_addr_rf),
        .rs2_addr (id_rs2_addr_rf),
        .rs1_data (id_rs1_data_rf),
        .rs2_data (id_rs2_data_rf),
        .wr_en    (wb_en),
        .rd_addr  (wb_addr),
        .rd_data  (wb_data)
    );

    execute u_execute (
        .clk                 (clk),
        .rst_n               (rst_n),
        .pc_in               (id_pc),
        .rs1_in              (id_rs1),
        .rs2_in              (id_rs2),
        .imm_in              (id_imm),
        .rs1_addr_in         (id_rs1_addr),
        .rs2_addr_in         (id_rs2_addr),
        .rd_addr_in          (id_rd_addr),
        .alu_op_in           (id_alu_op),
        .alu_src_in          (id_alu_src),
        .mem_read_in         (id_mem_read),
        .mem_write_in        (id_mem_write),
        .reg_write_in        (id_reg_write),
        .branch_in           (id_branch),
        .mem_to_reg_in       (id_mem_to_reg),
        .fwd_ex_mem          (ex_alu_result),
        .fwd_mem_wb          (wb_data),
        .fwd_sel_rs1         (fwd_sel_rs1),
        .fwd_sel_rs2         (fwd_sel_rs2),
        .funct3_in           (id_funct3),
        .jal_in              (id_jal),
        .predicted_taken_in  (id_predicted_taken),
        .accel_in            (id_accel),
        .accel_op_in         (id_accel_op),
        .accel_done          (accel_done),
        .axil_awaddr         (axil_awaddr),
        .axil_awvalid        (axil_awvalid),
        .axil_wdata          (axil_wdata),
        .axil_wvalid         (axil_wvalid),
        .axil_araddr         (axil_araddr),
        .axil_arvalid        (axil_arvalid),
        .accel_stall         (accel_stall),
        .alu_result_out      (ex_alu_result),
        .rs2_out             (ex_rs2),
        .rd_addr_out         (ex_rd_addr),
        .mem_read_out        (ex_mem_read),
        .mem_write_out       (ex_mem_write),
        .reg_write_out       (ex_reg_write),
        .mem_to_reg_out      (ex_mem_to_reg),
        .branch_taken        (branch_taken),
        .branch_target       (branch_target),
        .branch_fallthrough  (branch_fallthrough),
        .mispredict          (mispredict)
    );

    memory_stage u_mem (
        .clk            (clk),
        .rst_n          (rst_n),
        .alu_result_in  (ex_alu_result),
        .rs2_in         (ex_rs2),
        .rd_addr_in     (ex_rd_addr),
        .mem_read_in    (ex_mem_read),
        .mem_write_in   (ex_mem_write),
        .reg_write_in   (ex_reg_write),
        .mem_to_reg_in  (ex_mem_to_reg),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .dmem_wr_en     (dmem_wr_en),
        .dmem_rdata     (dmem_rdata),
        .alu_result_out (mem_alu_result),
        .mem_data_out   (mem_data),
        .rd_addr_out    (mem_rd_addr),
        .reg_write_out  (mem_reg_write),
        .mem_to_reg_out (mem_mem_to_reg)
    );

    writeback u_wb (
        .alu_result_in  (mem_alu_result),
        .mem_data_in    (mem_data),
        .rd_addr_in     (mem_rd_addr),
        .reg_write_in   (mem_reg_write),
        .mem_to_reg_in  (mem_mem_to_reg),
        .wb_data        (wb_data),
        .wb_addr        (wb_addr),
        .wb_en          (wb_en)
    );

    hazard u_hazard (
        .id_rs1_addr      (id_rs1_addr),
        .id_rs2_addr      (id_rs2_addr),
        .ex_rd_addr       (ex_rd_addr),
        .ex_mem_read      (ex_mem_read),
        .ex_mem_rd_addr   (ex_rd_addr),
        .ex_mem_reg_write (ex_reg_write),
        .mem_wb_rd_addr   (mem_rd_addr),
        .mem_wb_reg_write (mem_reg_write),
        .accel_stall      (accel_stall),
        .stall            (stall),
        .fwd_sel_rs1      (fwd_sel_rs1),
        .fwd_sel_rs2      (fwd_sel_rs2)
    );

endmodule
`default_nettype wire
