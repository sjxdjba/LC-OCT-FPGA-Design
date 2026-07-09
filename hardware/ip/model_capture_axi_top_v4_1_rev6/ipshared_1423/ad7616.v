`timescale 1ns / 1ps

// AD7616 parallel software-mode controller.
//
// Single-ended acquisition mode:
// - One CHANNEL_REG setting is used.
// - Each conversion reads the A-side and B-side samples for that channel.
// - code_a/voltage_a_uv and code_b/voltage_b_uv are the two motor sensor inputs.
// - code_c/code_d are kept for top-level compatibility and held at zero.
module ad7616 #(
    parameter integer RESET_LOW_CYCLES   = 200,
    parameter integer RESET_WAIT_CYCLES  = 1500000,
    parameter integer WR_LOW_CYCLES      = 3,
    parameter integer WR_HIGH_CYCLES     = 2,
    parameter integer CONVST_HIGH_CYCLES = 5,
    parameter integer CS_SETUP_CYCLES    = 2,
    parameter integer RD_LOW_CYCLES      = 3,
    parameter integer RD_HIGH_CYCLES     = 2,
    parameter integer QUIET_CYCLES       = 5,
    parameter integer FIXED_CHANNEL      = 7,
    parameter [2:0]   OSR_MODE           = 3'b000,
    parameter [1:0]   INPUT_RANGE_MODE   = 2'b11
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,
    input  wire               busy,
    input  wire [15:0]        data_bus_in,
    output wire [15:0]        data_bus_out,
    output wire               data_bus_t,

    output wire               init_done,
    output reg                data_valid,

    output reg  signed [15:0] code_a,
    output reg  signed [15:0] code_b,
    output reg  signed [15:0] code_c,
    output reg  signed [15:0] code_d,
    output reg  signed [31:0] voltage_a_uv,
    output reg  signed [31:0] voltage_b_uv,
    output reg  signed [31:0] voltage_c_uv,
    output reg  signed [31:0] voltage_d_uv,

    output wire [3:0]         debug_state,
    output wire [31:0]        debug_counter,
    output wire [15:0]        debug_data_bus_in,
    output wire               debug_data_bus_t,
    output wire signed [15:0] debug_sample_a,

    output reg                convst,
    output reg                cs_n,
    output reg                rd_n,
    output reg                reset_n_adc,
    output wire [2:0]         chsel,
    output wire [1:0]         hw_rngsel,
    output reg                burst,
    output wire               ser_par
);

    localparam [4:0]
        ST_RESET_ASSERT    = 5'd0,
        ST_RESET_WAIT      = 5'd1,
        ST_CFG_LOAD        = 5'd2,
        ST_CFG_CS_LOW      = 5'd3,
        ST_CFG_WR_LOW      = 5'd4,
        ST_CFG_WR_HIGH     = 5'd5,
        ST_CFG_CS_HIGH     = 5'd6,
        ST_IDLE            = 5'd7,
        ST_PRE_CONV        = 5'd8,
        ST_CONV_HIGH       = 5'd9,
        ST_WAIT_BUSY_HIGH  = 5'd10,
        ST_WAIT_BUSY_LOW   = 5'd11,
        ST_CS_SETUP        = 5'd12,
        ST_READ_A_LOW      = 5'd13,
        ST_READ_A_HIGH     = 5'd14,
        ST_READ_B_LOW      = 5'd15,
        ST_READ_B_HIGH     = 5'd16,
        ST_QUIET           = 5'd17;

    localparam signed [31:0] FULL_SCALE_UV = 32'sd10000000;

    localparam [4:0] REG_CONFIG   = 5'h02;
    localparam [4:0] REG_CHANNEL  = 5'h03;
    localparam [4:0] REG_RANGE_A1 = 5'h04;
    localparam [4:0] REG_RANGE_A2 = 5'h05;
    localparam [4:0] REG_RANGE_B1 = 5'h06;
    localparam [4:0] REG_RANGE_B2 = 5'h07;

    localparam [15:0] RANGE_A1_DATA = {1'b1, 1'b0, REG_RANGE_A1, 1'b0,
                                       INPUT_RANGE_MODE, INPUT_RANGE_MODE,
                                       INPUT_RANGE_MODE, INPUT_RANGE_MODE};
    localparam [15:0] RANGE_A2_DATA = {1'b1, 1'b0, REG_RANGE_A2, 1'b0,
                                       INPUT_RANGE_MODE, INPUT_RANGE_MODE,
                                       INPUT_RANGE_MODE, INPUT_RANGE_MODE};
    localparam [15:0] RANGE_B1_DATA = {1'b1, 1'b0, REG_RANGE_B1, 1'b0,
                                       INPUT_RANGE_MODE, INPUT_RANGE_MODE,
                                       INPUT_RANGE_MODE, INPUT_RANGE_MODE};
    localparam [15:0] RANGE_B2_DATA = {1'b1, 1'b0, REG_RANGE_B2, 1'b0,
                                       INPUT_RANGE_MODE, INPUT_RANGE_MODE,
                                       INPUT_RANGE_MODE, INPUT_RANGE_MODE};
    localparam [15:0] CONFIG_DATA   = {1'b1, 1'b0, REG_CONFIG, 1'b0, 5'b00000, OSR_MODE};
    localparam [15:0] CHANNEL_DATA  = {1'b1, 1'b0, REG_CHANNEL, 1'b0,
                                       FIXED_CHANNEL[3:0], FIXED_CHANNEL[3:0]};

    reg [4:0]         state;
    reg [31:0]        counter;
    reg [2:0]         cfg_index;
    reg [15:0]        data_bus_out_reg;
    reg               data_bus_t_reg;
    reg               busy_sync_1;
    reg               busy_sync_2;
    reg signed [15:0] sample_a;
    reg signed [15:0] sample_b;

    assign data_bus_out = data_bus_out_reg;
    assign data_bus_t   = data_bus_t_reg;

    function automatic signed [31:0] code_to_uv;
        input signed [15:0] code;
        reg   signed [47:0] product;
        begin
            product    = code * FULL_SCALE_UV;
            code_to_uv = product >>> 15;
        end
    endfunction

    function automatic [15:0] cfg_data_for_index;
        input [2:0] index;
        begin
            case (index)
                3'd0: cfg_data_for_index = RANGE_A1_DATA;
                3'd1: cfg_data_for_index = RANGE_A2_DATA;
                3'd2: cfg_data_for_index = RANGE_B1_DATA;
                3'd3: cfg_data_for_index = RANGE_B2_DATA;
                3'd4: cfg_data_for_index = CONFIG_DATA;
                3'd5: cfg_data_for_index = CHANNEL_DATA;
                default: cfg_data_for_index = CHANNEL_DATA;
            endcase
        end
    endfunction

    assign init_done         = (state >= ST_IDLE);
    assign chsel             = 3'b000;
    assign hw_rngsel         = INPUT_RANGE_MODE;
    assign ser_par           = 1'b0;
    assign debug_state       = state[3:0];
    assign debug_counter     = counter;
    assign debug_data_bus_in = data_bus_in;
    assign debug_data_bus_t  = ~data_bus_t_reg;
    assign debug_sample_a    = sample_a;

    always @(posedge clk) begin
        if (!rst_n) begin
            state            <= ST_RESET_ASSERT;
            counter          <= 32'd0;
            cfg_index        <= 3'd0;
            data_bus_out_reg <= 16'd0;
            data_bus_t_reg   <= 1'b1;
            busy_sync_1      <= 1'b0;
            busy_sync_2      <= 1'b0;
            sample_a         <= 16'sd0;
            sample_b         <= 16'sd0;
            code_a           <= 16'sd0;
            code_b           <= 16'sd0;
            code_c           <= 16'sd0;
            code_d           <= 16'sd0;
            voltage_a_uv     <= 32'sd0;
            voltage_b_uv     <= 32'sd0;
            voltage_c_uv     <= 32'sd0;
            voltage_d_uv     <= 32'sd0;
            data_valid       <= 1'b0;
            convst           <= 1'b0;
            cs_n             <= 1'b1;
            rd_n             <= 1'b1;
            reset_n_adc      <= 1'b1;
            burst            <= 1'b1;
        end else begin
            data_valid  <= 1'b0;
            busy_sync_1 <= busy;
            busy_sync_2 <= busy_sync_1;

            case (state)
                ST_RESET_ASSERT: begin
                    reset_n_adc    <= 1'b0;
                    convst         <= 1'b0;
                    cs_n           <= 1'b1;
                    rd_n           <= 1'b1;
                    burst          <= 1'b1;
                    data_bus_t_reg <= 1'b1;
                    if (counter == RESET_LOW_CYCLES - 1) begin
                        counter     <= 32'd0;
                        reset_n_adc <= 1'b1;
                        state       <= ST_RESET_WAIT;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                ST_RESET_WAIT: begin
                    reset_n_adc    <= 1'b1;
                    convst         <= 1'b0;
                    cs_n           <= 1'b1;
                    rd_n           <= 1'b1;
                    burst          <= 1'b1;
                    data_bus_t_reg <= 1'b1;
                    if (counter == RESET_WAIT_CYCLES - 1) begin
                        counter   <= 32'd0;
                        cfg_index <= 3'd0;
                        state     <= ST_CFG_LOAD;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                ST_CFG_LOAD: begin
                    data_bus_out_reg <= cfg_data_for_index(cfg_index);
                    data_bus_t_reg   <= 1'b0;
                    cs_n             <= 1'b0;
                    rd_n             <= 1'b1;
                    burst            <= 1'b1;
                    counter          <= 32'd0;
                    state            <= ST_CFG_CS_LOW;
                end

                ST_CFG_CS_LOW: begin
                    if (counter == WR_HIGH_CYCLES - 1) begin
                        counter <= 32'd0;
                        burst   <= 1'b0;
                        state   <= ST_CFG_WR_LOW;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                ST_CFG_WR_LOW: begin
                    if (counter == WR_LOW_CYCLES - 1) begin
                        counter <= 32'd0;
                        burst   <= 1'b1;
                        state   <= ST_CFG_WR_HIGH;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                ST_CFG_WR_HIGH: begin
                    if (counter == WR_HIGH_CYCLES - 1) begin
                        counter <= 32'd0;
                        cs_n    <= 1'b1;
                        state   <= ST_CFG_CS_HIGH;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                ST_CFG_CS_HIGH: begin
                    if (counter == QUIET_CYCLES - 1) begin
                        counter <= 32'd0;
                        if (cfg_index == 3'd5) begin
                            data_bus_t_reg <= 1'b1;
                            state          <= ST_IDLE;
                        end else begin
                            cfg_index <= cfg_index + 1'b1;
                            state     <= ST_CFG_LOAD;
                        end
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                ST_IDLE: begin
                    convst         <= 1'b0;
                    cs_n           <= 1'b1;
                    rd_n           <= 1'b1;
                    burst          <= 1'b1;
                    data_bus_t_reg <= 1'b1;
                    counter        <= 32'd0;
                    if (enable) begin
                        state <= ST_PRE_CONV;
                    end
                end

                ST_PRE_CONV: begin
                    data_bus_t_reg <= 1'b1;
                    cs_n           <= 1'b1;
                    rd_n           <= 1'b1;
                    burst          <= 1'b1;
                    if (counter == QUIET_CYCLES - 1) begin
                        counter <= 32'd0;
                        convst  <= 1'b1;
                        state   <= ST_CONV_HIGH;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                ST_CONV_HIGH: begin
                    if (counter == CONVST_HIGH_CYCLES - 1) begin
                        counter <= 32'd0;
                        convst  <= 1'b0;
                        state   <= ST_WAIT_BUSY_HIGH;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                ST_WAIT_BUSY_HIGH: begin
                    if (busy_sync_2) begin
                        state <= ST_WAIT_BUSY_LOW;
                    end
                end

                ST_WAIT_BUSY_LOW: begin
                    if (!busy_sync_2) begin
                        counter <= 32'd0;
                        cs_n    <= 1'b0;
                        state   <= ST_CS_SETUP;
                    end
                end

                ST_CS_SETUP: begin
                    cs_n <= 1'b0;
                    rd_n <= 1'b1;
                    if (counter == CS_SETUP_CYCLES - 1) begin
                        counter <= 32'd0;
                        rd_n    <= 1'b0;
                        state   <= ST_READ_A_LOW;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                ST_READ_A_LOW: begin
                    if (counter == RD_LOW_CYCLES - 1) begin
                        sample_a <= $signed(data_bus_in);
                        counter  <= 32'd0;
                        rd_n     <= 1'b1;
                        state    <= ST_READ_A_HIGH;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                ST_READ_A_HIGH: begin
                    if (counter == RD_HIGH_CYCLES - 1) begin
                        counter <= 32'd0;
                        rd_n    <= 1'b0;
                        state   <= ST_READ_B_LOW;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                ST_READ_B_LOW: begin
                    cs_n <= 1'b0;
                    if (counter == RD_LOW_CYCLES - 1) begin
                        sample_b <= $signed(data_bus_in);
                        counter  <= 32'd0;
                        rd_n     <= 1'b1;
                        state    <= ST_READ_B_HIGH;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                ST_READ_B_HIGH: begin
                    if (counter == RD_HIGH_CYCLES - 1) begin
                        code_a       <= sample_a;
                        code_b       <= sample_b;
                        code_c       <= 16'sd0;
                        code_d       <= 16'sd0;
                        voltage_a_uv <= code_to_uv(sample_a);
                        voltage_b_uv <= code_to_uv(sample_b);
                        voltage_c_uv <= 32'sd0;
                        voltage_d_uv <= 32'sd0;
                        data_valid   <= 1'b1;
                        counter      <= 32'd0;
                        cs_n         <= 1'b1;
                        state        <= ST_QUIET;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                ST_QUIET: begin
                    if (counter == QUIET_CYCLES - 1) begin
                        counter <= 32'd0;
                        if (enable) begin
                            state <= ST_PRE_CONV;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                default: begin
                    state <= ST_RESET_ASSERT;
                end
            endcase
        end
    end

endmodule
