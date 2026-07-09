`timescale 1ns / 1ps

module pzt_velocity_controller #(
    parameter integer       GAIN_Q           = 16,
    parameter [15:0]        DAC_MAX          = 16'd65535,
    parameter [15:0]        DAC_MIN          = 16'd0,
    parameter signed [31:0] I_DIFF_MAX       = 32'sd5000,
    parameter signed [31:0] I_POS_MAX        = 32'sd2000,
    parameter signed [31:0] ALIGN_TOL_NM     = 32'sd500,
    parameter [15:0]        ALIGN_HOLD_TICKS = 16'd128
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         enable,
    input  wire         restart,
    input  wire         valid_in,

    input  wire signed [31:0] cfg_kp_vel,
    input  wire signed [31:0] cfg_ki_diff,
    input  wire signed [31:0] cfg_ki_pos,

    input  wire signed [31:0] vel_m1_nm_s,
    input  wire signed [31:0] vel_m2_nm_s,

    input  wire signed [31:0] pos_m1_nm,
    input  wire signed [31:0] pos_m2_nm,
    input  wire signed [31:0] diff_ab_nm,

    input  wire [15:0]        dac_ff_m1,
    input  wire [15:0]        dac_ff_m2,
    input  wire               dac_ff_valid,

    input  wire signed [31:0] v_ref_ext,
    input  wire signed [31:0] pos_ref_ext,
    input  wire signed [31:0] target_pos_ext,
    input  wire               use_ext_ref,

    output reg                spi_start_m1,
    output reg  [15:0]        spi_data_m1,
    output reg                spi_start_m2,
    output reg  [15:0]        spi_data_m2,
    input  wire               spi_busy,
    input  wire               spi_done,

    output wire signed [31:0] debug_dac_p_m1,
    output wire signed [31:0] debug_dac_p_m2,
    output wire signed [31:0] debug_dac_i_diff,
    output wire signed [31:0] debug_dac_i_pos_m1,
    output wire signed [31:0] debug_dac_i_pos_m2,
    output wire signed [31:0] debug_dac_total_m1,
    output wire signed [31:0] debug_dac_total_m2,
    output wire signed [31:0] debug_pos_err_m1,
    output wire signed [31:0] debug_pos_err_m2,
    output wire signed [31:0] debug_vel_err_m1,
    output wire signed [31:0] debug_vel_err_m2,
    output wire [1:0]         debug_state
);

    localparam [1:0] CTRL_IDLE  = 2'd0;
    localparam [1:0] CTRL_ALIGN = 2'd1;
    localparam [1:0] CTRL_RUN   = 2'd2;
    localparam [1:0] CTRL_RETURN = 2'd3;

    localparam [1:0] SPI_IDLE = 2'd0;
    localparam [1:0] SPI_SEND = 2'd1;
    localparam [1:0] SPI_WAIT = 2'd2;

    reg [1:0] ctrl_state;
    reg       enable_d;
    reg [15:0] align_hold_counter;

    reg signed [31:0] vel_m1_s0, vel_m2_s0;
    reg signed [31:0] pos_m1_s0, pos_m2_s0, diff_s0;
    reg signed [31:0] v_ref_s0, pos_ref_s0;
    reg [15:0]        ff_m1_s0, ff_m2_s0;
    reg [1:0]         state_s0;
    reg               v0;

    reg signed [31:0] vel_err_m1_s1, vel_err_m2_s1;
    reg signed [31:0] pos_err_m1_s1, pos_err_m2_s1;
    reg signed [63:0] p_vel_prod_m1_s1, p_vel_prod_m2_s1;
    reg signed [63:0] p_pos_prod_m1_s1, p_pos_prod_m2_s1;
    reg signed [63:0] i_diff_prod_s1;
    reg [15:0]        ff_m1_s1, ff_m2_s1;
    reg [1:0]         state_s1;
    reg               v1;

    reg signed [31:0] dac_p_vel_m1_s2, dac_p_vel_m2_s2;
    reg signed [31:0] dac_p_pos_m1_s2, dac_p_pos_m2_s2;
    reg signed [31:0] dac_i_diff_half_s2;
    reg [15:0]        ff_m1_s2, ff_m2_s2;
    reg [1:0]         state_s2;
    reg               v2;

    reg signed [31:0] i_diff_acc;
    reg signed [31:0] i_diff_next;

    reg [1:0]         spi_state;
    reg signed [31:0] dac_total_m1, dac_total_m2;

    assign debug_dac_p_m1     = dac_p_vel_m1_s2;
    assign debug_dac_p_m2     = dac_p_vel_m2_s2;
    assign debug_dac_i_diff   = i_diff_acc;
    assign debug_dac_i_pos_m1 = dac_p_pos_m1_s2;
    assign debug_dac_i_pos_m2 = dac_p_pos_m2_s2;
    assign debug_dac_total_m1 = dac_total_m1;
    assign debug_dac_total_m2 = dac_total_m2;
    assign debug_pos_err_m1   = pos_err_m1_s1;
    assign debug_pos_err_m2   = pos_err_m2_s1;
    assign debug_vel_err_m1   = vel_err_m1_s1;
    assign debug_vel_err_m2   = vel_err_m2_s1;
    assign debug_state        = ctrl_state;

    function automatic signed [31:0] abs32;
        input signed [31:0] value;
        begin
            abs32 = value[31] ? -value : value;
        end
    endfunction

    function automatic [15:0] saturate_dac;
        input signed [31:0] value;
        begin
            if (value < $signed({1'b0, DAC_MIN})) begin
                saturate_dac = DAC_MIN;
            end else if (value > $signed({1'b0, DAC_MAX})) begin
                saturate_dac = DAC_MAX;
            end else begin
                saturate_dac = value[15:0];
            end
        end
    endfunction

    function automatic target_reached;
        input signed [31:0] v_ref;
        input signed [31:0] target_pos;
        input signed [31:0] pos_m1;
        input signed [31:0] pos_m2;
        begin
            if (target_pos == 32'sd0) begin
                target_reached = 1'b0;
            end else if (v_ref > 32'sd0) begin
                target_reached = (pos_m1 >= target_pos) && (pos_m2 >= target_pos);
            end else if (v_ref < 32'sd0) begin
                target_reached = (pos_m1 <= target_pos) && (pos_m2 <= target_pos);
            end else begin
                target_reached = 1'b0;
            end
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            ctrl_state <= CTRL_IDLE;
            enable_d <= 1'b0;
            align_hold_counter <= 16'd0;

            vel_m1_s0 <= 32'sd0; vel_m2_s0 <= 32'sd0;
            pos_m1_s0 <= 32'sd0; pos_m2_s0 <= 32'sd0; diff_s0 <= 32'sd0;
            v_ref_s0 <= 32'sd0; pos_ref_s0 <= 32'sd0;
            ff_m1_s0 <= 16'd0; ff_m2_s0 <= 16'd0;
            state_s0 <= CTRL_IDLE; v0 <= 1'b0;

            vel_err_m1_s1 <= 32'sd0; vel_err_m2_s1 <= 32'sd0;
            pos_err_m1_s1 <= 32'sd0; pos_err_m2_s1 <= 32'sd0;
            p_vel_prod_m1_s1 <= 64'sd0; p_vel_prod_m2_s1 <= 64'sd0;
            p_pos_prod_m1_s1 <= 64'sd0; p_pos_prod_m2_s1 <= 64'sd0;
            i_diff_prod_s1 <= 64'sd0;
            ff_m1_s1 <= 16'd0; ff_m2_s1 <= 16'd0;
            state_s1 <= CTRL_IDLE; v1 <= 1'b0;

            dac_p_vel_m1_s2 <= 32'sd0; dac_p_vel_m2_s2 <= 32'sd0;
            dac_p_pos_m1_s2 <= 32'sd0; dac_p_pos_m2_s2 <= 32'sd0;
            dac_i_diff_half_s2 <= 32'sd0;
            ff_m1_s2 <= 16'd0; ff_m2_s2 <= 16'd0;
            state_s2 <= CTRL_IDLE; v2 <= 1'b0;

            i_diff_acc <= 32'sd0;
            i_diff_next <= 32'sd0;

            spi_state <= SPI_IDLE;
            spi_start_m1 <= 1'b0; spi_start_m2 <= 1'b0;
            spi_data_m1 <= 16'd0; spi_data_m2 <= 16'd0;
            dac_total_m1 <= 32'sd0; dac_total_m2 <= 32'sd0;
        end else begin
            spi_start_m1 <= 1'b0;
            spi_start_m2 <= 1'b0;
            enable_d <= enable;

            if (!enable) begin
                ctrl_state <= CTRL_IDLE;
                align_hold_counter <= 16'd0;
                i_diff_acc <= 32'sd0;
                dac_i_diff_half_s2 <= 32'sd0;
                v0 <= 1'b0;
                v1 <= 1'b0;
                v2 <= 1'b0;
                spi_state <= SPI_IDLE;
            end else begin
                if (!enable_d || restart) begin
                    ctrl_state <= CTRL_ALIGN;
                    align_hold_counter <= 16'd0;
                    i_diff_acc <= 32'sd0;
                    dac_i_diff_half_s2 <= 32'sd0;
                    v0 <= 1'b0;
                    v1 <= 1'b0;
                    v2 <= 1'b0;
                    spi_state <= SPI_IDLE;
                end else if ((ctrl_state == CTRL_ALIGN) && valid_in && dac_ff_valid) begin
                    if ((abs32(pos_ref_ext - pos_m1_nm) <= ALIGN_TOL_NM) &&
                        (abs32(pos_ref_ext - pos_m2_nm) <= ALIGN_TOL_NM)) begin
                        if (align_hold_counter >= (ALIGN_HOLD_TICKS - 1'b1)) begin
                            ctrl_state <= CTRL_RUN;
                            align_hold_counter <= 16'd0;
                            i_diff_acc <= 32'sd0;
                        end else begin
                            align_hold_counter <= align_hold_counter + 1'b1;
                        end
                    end else begin
                        align_hold_counter <= 16'd0;
                    end
                end else if ((ctrl_state == CTRL_RUN) && valid_in && dac_ff_valid) begin
                    if (target_reached(v_ref_ext, target_pos_ext, pos_m1_nm, pos_m2_nm)) begin
                        ctrl_state <= CTRL_RETURN;
                        align_hold_counter <= 16'd0;
                        i_diff_acc <= 32'sd0;
                    end
                end else if ((ctrl_state == CTRL_RETURN) && valid_in && dac_ff_valid) begin
                    if ((abs32(pos_ref_ext - pos_m1_nm) <= ALIGN_TOL_NM) &&
                        (abs32(pos_ref_ext - pos_m2_nm) <= ALIGN_TOL_NM)) begin
                        if (align_hold_counter < (ALIGN_HOLD_TICKS - 1'b1)) begin
                            align_hold_counter <= align_hold_counter + 1'b1;
                        end
                    end else begin
                        align_hold_counter <= 16'd0;
                    end
                end

                if (enable_d && !restart) begin
                    v0 <= valid_in && dac_ff_valid && (ctrl_state != CTRL_IDLE);
                    if (valid_in && dac_ff_valid && (ctrl_state != CTRL_IDLE)) begin
                        vel_m1_s0 <= vel_m1_nm_s;
                        vel_m2_s0 <= vel_m2_nm_s;
                        pos_m1_s0 <= pos_m1_nm;
                        pos_m2_s0 <= pos_m2_nm;
                        diff_s0   <= diff_ab_nm;
                        v_ref_s0  <= v_ref_ext;
                        pos_ref_s0 <= pos_ref_ext;
                        ff_m1_s0  <= dac_ff_m1;
                        ff_m2_s0  <= dac_ff_m2;
                        state_s0  <= ctrl_state;
                    end

                    v1 <= v0;
                    if (v0) begin
                        vel_err_m1_s1 <= v_ref_s0 - vel_m1_s0;
                        vel_err_m2_s1 <= v_ref_s0 - vel_m2_s0;
                        pos_err_m1_s1 <= pos_ref_s0 - pos_m1_s0;
                        pos_err_m2_s1 <= pos_ref_s0 - pos_m2_s0;

                        p_vel_prod_m1_s1 <= (v_ref_s0 - vel_m1_s0) * cfg_kp_vel;
                        p_vel_prod_m2_s1 <= (v_ref_s0 - vel_m2_s0) * cfg_kp_vel;
                        p_pos_prod_m1_s1 <= (pos_ref_s0 - pos_m1_s0) * cfg_ki_pos;
                        p_pos_prod_m2_s1 <= (pos_ref_s0 - pos_m2_s0) * cfg_ki_pos;
                        i_diff_prod_s1   <= (-diff_s0) * cfg_ki_diff;

                        ff_m1_s1 <= ff_m1_s0;
                        ff_m2_s1 <= ff_m2_s0;
                        state_s1 <= state_s0;
                    end

                    v2 <= v1;
                    if (v1) begin
                        dac_p_vel_m1_s2 <= p_vel_prod_m1_s1 >>> GAIN_Q;
                        dac_p_vel_m2_s2 <= p_vel_prod_m2_s1 >>> GAIN_Q;
                        dac_p_pos_m1_s2 <= p_pos_prod_m1_s1 >>> GAIN_Q;
                        dac_p_pos_m2_s2 <= p_pos_prod_m2_s1 >>> GAIN_Q;

                        if (state_s1 == CTRL_RUN) begin
                            i_diff_next = i_diff_acc + (i_diff_prod_s1 >>> GAIN_Q);
                            if (i_diff_next > I_DIFF_MAX) begin
                                i_diff_next = I_DIFF_MAX;
                            end else if (i_diff_next < -I_DIFF_MAX) begin
                                i_diff_next = -I_DIFF_MAX;
                            end
                            i_diff_acc <= i_diff_next;
                            dac_i_diff_half_s2 <= i_diff_next >>> 1;
                        end else begin
                            i_diff_acc <= 32'sd0;
                            dac_i_diff_half_s2 <= 32'sd0;
                        end

                        ff_m1_s2 <= ff_m1_s1;
                        ff_m2_s2 <= ff_m2_s1;
                        state_s2 <= state_s1;
                    end

                    case (spi_state)
                        SPI_IDLE: begin
                            if (v2 && !spi_busy && (state_s2 != CTRL_IDLE)) begin
                                if ((state_s2 == CTRL_ALIGN) || (state_s2 == CTRL_RETURN)) begin
                                    dac_total_m1 <= $signed({1'b0, ff_m1_s2}) + dac_p_pos_m1_s2;
                                    dac_total_m2 <= $signed({1'b0, ff_m2_s2}) + dac_p_pos_m2_s2;
                                end else begin
                                    dac_total_m1 <= $signed({1'b0, ff_m1_s2})
                                                  + dac_p_vel_m1_s2
                                                  - dac_i_diff_half_s2;
                                    dac_total_m2 <= $signed({1'b0, ff_m2_s2})
                                                  + dac_p_vel_m2_s2
                                                  + dac_i_diff_half_s2;
                                end
                                spi_state <= SPI_SEND;
                            end
                        end

                        SPI_SEND: begin
                            spi_data_m1 <= saturate_dac(dac_total_m1);
                            spi_data_m2 <= saturate_dac(dac_total_m2);
                            spi_start_m1 <= 1'b1;
                            spi_start_m2 <= 1'b1;
                            spi_state <= SPI_WAIT;
                        end

                        SPI_WAIT: begin
                            if (spi_done) begin
                                spi_state <= SPI_IDLE;
                            end
                        end

                        default: begin
                            spi_state <= SPI_IDLE;
                        end
                    endcase
                end
            end
        end
    end

endmodule
