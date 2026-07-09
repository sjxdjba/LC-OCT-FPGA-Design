`timescale 1ns / 1ps

// ┌──────────────────────────────────────────────────────────────┐
// │  Sensor uV -> Position (nm)  +  Differential                 │
// │                                                              │
// │  5-segment piecewise-linear calibration:                     │
// │    pos_nm = GAIN_i * sensor_uv + OFFSET_i                    │
// │                                                              │
// │  GAIN_i  : scaled by 2^20 (fixed-point Q12.20)               │
// │  OFFSET_i: integer nm                                        │
// │                                                              │
// │  Input:  4 x 32-bit signed uV   (A/B active, C/D optional)   │
// │  Output: 4 x 32-bit signed nm   (position)                   │
// │          2 x 32-bit signed nm   (diff_ab active, diff_cd opt)│
// │                                                              │
// │  Pipeline: 3 cycles                                          │
// │    Stage 0: segment selection (comparators)                   │
// │    Stage 1: multiply (gain * uv)                              │
// │    Stage 2: add offset + compute differential                  │
// └──────────────────────────────────────────────────────────────┘

module sensor_uv_to_position_nm (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         valid_in,       // data valid strobe

    // 4 sensor channels (uV, signed)
    input  wire signed [31:0] sensor_a_uv,   // M1 sensor
    input  wire signed [31:0] sensor_b_uv,   // M2 sensor
    input  wire signed [31:0] sensor_c_uv,   // optional / reserved
    input  wire signed [31:0] sensor_d_uv,   // optional / reserved

    // 4 position outputs (nm, signed)
    output reg  signed [31:0] pos_a_nm,
    output reg  signed [31:0] pos_b_nm,
    output reg  signed [31:0] pos_c_nm,
    output reg  signed [31:0] pos_d_nm,

    // 2 differential outputs (nm, signed)
    output reg  signed [31:0] diff_ab_nm,    // pos_a - pos_b (M1 - M2)
    output reg  signed [31:0] diff_cd_nm,    // pos_c - pos_d

    output reg          valid_out
);

    // ── Calibration coefficients (Q12.20 fixed-point gain, integer offset in nm) ──

    // Gain = slope_mm_per_V * 2^20  (since 1 mm/V == 1 nm/uV)
    //   seg0: 0.079249062 * 2^20 = 83124
    //   seg1: 0.079788585 * 2^20 = 83689
    //   seg2: 0.080766152 * 2^20 = 84711
    //   seg3: 0.082221190 * 2^20 = 86238
    //   seg4: 0.083483736 * 2^20 = 87563
    localparam signed [31:0] GAIN_Q20_0 =  83124;
    localparam signed [31:0] GAIN_Q20_1 =  83689;
    localparam signed [31:0] GAIN_Q20_2 =  84711;
    localparam signed [31:0] GAIN_Q20_3 =  86238;
    localparam signed [31:0] GAIN_Q20_4 =  87563;

    localparam signed [31:0] OFFSET_NM_0 = -2464;
    localparam signed [31:0] OFFSET_NM_1 = -3706;
    localparam signed [31:0] OFFSET_NM_2 = -7675;
    localparam signed [31:0] OFFSET_NM_3 = -15692;
    localparam signed [31:0] OFFSET_NM_4 = -24940;

    // Voltage thresholds in uV (integer comparison — no scaling needed)
    //   seg0: [  11000, 2285000)
    //   seg1: [2285000, 3942000)
    //   seg2: [3942000, 5599000)
    //   seg3: [5599000, 7256000)
    //   seg4: [7256000, 9111000)
    localparam signed [31:0] THR_LO = 32'sd11000;       // below this → invalid (0)
    localparam signed [31:0] THR_01 = 32'sd2285000;
    localparam signed [31:0] THR_12 = 32'sd3942000;
    localparam signed [31:0] THR_23 = 32'sd5599000;
    localparam signed [31:0] THR_34 = 32'sd7256000;
    localparam signed [31:0] THR_HI = 32'sd9111000;     // above this → clamp to seg4

    // Pipeline registers
    // Stage 0 → Stage 1
    reg signed [31:0]  uv_a_s1, uv_b_s1, uv_c_s1, uv_d_s1;
    reg signed [31:0]  gain_a_s1, gain_b_s1, gain_c_s1, gain_d_s1;
    reg signed [31:0]  off_a_s1,  off_b_s1,  off_c_s1,  off_d_s1;
    reg                valid_s1;

    // Stage 1 → Stage 2
    reg signed [63:0]  prod_a_s2, prod_b_s2, prod_c_s2, prod_d_s2;
    reg signed [31:0]  off_a_s2,  off_b_s2,  off_c_s2,  off_d_s2;
    reg                valid_s2;

    // ── Helper functions: segment selection + coefficient lookup ─
    function automatic [2:0] select_segment;
        input signed [31:0] uv;
        begin
            if (uv < THR_LO || uv >= THR_HI)
                select_segment = 3'd4;
            else if (uv < THR_01)
                select_segment = 3'd0;
            else if (uv < THR_12)
                select_segment = 3'd1;
            else if (uv < THR_23)
                select_segment = 3'd2;
            else if (uv < THR_34)
                select_segment = 3'd3;
            else
                select_segment = 3'd4;
        end
    endfunction

    function automatic signed [31:0] get_gain;
        input [2:0] seg;
        begin
            case (seg)
                3'd0: get_gain = GAIN_Q20_0;
                3'd1: get_gain = GAIN_Q20_1;
                3'd2: get_gain = GAIN_Q20_2;
                3'd3: get_gain = GAIN_Q20_3;
                default: get_gain = GAIN_Q20_4;
            endcase
        end
    endfunction

    function automatic signed [31:0] get_offset;
        input [2:0] seg;
        begin
            case (seg)
                3'd0: get_offset = OFFSET_NM_0;
                3'd1: get_offset = OFFSET_NM_1;
                3'd2: get_offset = OFFSET_NM_2;
                3'd3: get_offset = OFFSET_NM_3;
                default: get_offset = OFFSET_NM_4;
            endcase
        end
    endfunction

    // ── Pipeline ─────────────────────────────────────────────────

    always @(posedge clk) begin
        if (!rst_n) begin
            uv_a_s1  <= 32'sd0; uv_b_s1  <= 32'sd0;
            uv_c_s1  <= 32'sd0; uv_d_s1  <= 32'sd0;
            gain_a_s1 <= 32'sd0; gain_b_s1 <= 32'sd0;
            gain_c_s1 <= 32'sd0; gain_d_s1 <= 32'sd0;
            off_a_s1  <= 32'sd0; off_b_s1  <= 32'sd0;
            off_c_s1  <= 32'sd0; off_d_s1  <= 32'sd0;
            valid_s1  <= 1'b0;

            prod_a_s2 <= 64'sd0; prod_b_s2 <= 64'sd0;
            prod_c_s2 <= 64'sd0; prod_d_s2 <= 64'sd0;
            off_a_s2  <= 32'sd0; off_b_s2  <= 32'sd0;
            off_c_s2  <= 32'sd0; off_d_s2  <= 32'sd0;
            valid_s2  <= 1'b0;

            pos_a_nm  <= 32'sd0; pos_b_nm  <= 32'sd0;
            pos_c_nm  <= 32'sd0; pos_d_nm  <= 32'sd0;
            diff_ab_nm <= 32'sd0; diff_cd_nm <= 32'sd0;
            valid_out <= 1'b0;

        end else begin

            // ── Stage 0: segment selection ────────────────────────

            valid_s1 <= valid_in;

            if (valid_in) begin
                uv_a_s1   <= sensor_a_uv;
                uv_b_s1   <= sensor_b_uv;
                uv_c_s1   <= sensor_c_uv;
                uv_d_s1   <= sensor_d_uv;
                gain_a_s1 <= get_gain(select_segment(sensor_a_uv));
                gain_b_s1 <= get_gain(select_segment(sensor_b_uv));
                gain_c_s1 <= get_gain(select_segment(sensor_c_uv));
                gain_d_s1 <= get_gain(select_segment(sensor_d_uv));
                off_a_s1  <= get_offset(select_segment(sensor_a_uv));
                off_b_s1  <= get_offset(select_segment(sensor_b_uv));
                off_c_s1  <= get_offset(select_segment(sensor_c_uv));
                off_d_s1  <= get_offset(select_segment(sensor_d_uv));
            end

            // ── Stage 1: multiply (gain * sensor_uv) ──────────────

            valid_s2 <= valid_s1;
            if (valid_s1) begin
                prod_a_s2 <= uv_a_s1 * gain_a_s1;
                prod_b_s2 <= uv_b_s1 * gain_b_s1;
                prod_c_s2 <= uv_c_s1 * gain_c_s1;
                prod_d_s2 <= uv_d_s1 * gain_d_s1;
                off_a_s2  <= off_a_s1;
                off_b_s2  <= off_b_s1;
                off_c_s2  <= off_c_s1;
                off_d_s2  <= off_d_s1;
            end

            // ── Stage 2: shift + offset + differential ────────────

            valid_out <= valid_s2;
            if (valid_s2) begin
                // prod is Q(32+20).52, need Q32.0 (nm).
                // pos = (prod >> 20) + offset
                pos_a_nm   <= (prod_a_s2 >>> 20) + off_a_s2;
                pos_b_nm   <= (prod_b_s2 >>> 20) + off_b_s2;
                pos_c_nm   <= (prod_c_s2 >>> 20) + off_c_s2;
                pos_d_nm   <= (prod_d_s2 >>> 20) + off_d_s2;

                // Differential
                diff_ab_nm <= (prod_a_s2 >>> 20) + off_a_s2
                            - (prod_b_s2 >>> 20) - off_b_s2;
                diff_cd_nm <= (prod_c_s2 >>> 20) + off_c_s2
                            - (prod_d_s2 >>> 20) - off_d_s2;
            end
        end
    end

endmodule
