`timescale 1ns / 1ps

// Capture manager for DAC-step-based modeling.
//
// Purpose:
// - Drive the DAC one step at a time.
// - Wait for DAC transfer to finish.
// - Wait for analog settling time.
// - Trigger one ADC conversion or multiple conversions.
// - Average ADC results for each DAC code.
// - Output one record per DAC code for software-side storage.
//
// Recommended use:
// - Connect spi_start/spi_data to spi_for_8830.
// - Connect adc_start to ad7616.enable.
// - Save record_* outputs in PS, UART, FIFO, or DDR.
//
// Notes:
// - This module is for modeling mode, not continuous scan mode.
// - It is designed for the existing ad7616 module and keeps adc_start asserted
//   until one sample pair is completed and data_valid is observed.
module capture_manager #(
    parameter integer DAC_BITS                    = 16,
    parameter integer DEFAULT_SETTLE_CYCLES      = 100000,
    parameter integer DEFAULT_SAMPLES_PER_CODE   = 8,
    parameter integer DEFAULT_STEP_SIZE          = 1,
    parameter integer DEFAULT_HOLD_SAMPLE_COUNT  = 1,
    parameter integer DEFAULT_HOLD_INTERVAL_CYCLES = 0,
    parameter integer ACC_WIDTH                  = 48,
    parameter integer LOOP_ENABLE                = 0
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       enable,
    input  wire                       single_step_mode,
    input  wire                       step_ack,

    // Scan/capture configuration
    input  wire [DAC_BITS-1:0]        scan_min_code,
    input  wire [DAC_BITS-1:0]        scan_max_code,
    input  wire [31:0]                settle_cycles_cfg,
    input  wire [15:0]                samples_per_code_cfg,
    input  wire [DAC_BITS-1:0]        step_size_cfg,
    input  wire [15:0]                hold_sample_count_cfg,
    input  wire [31:0]                hold_interval_cycles_cfg,

    // SPI side
    input  wire                       spi_busy,
    input  wire                       spi_done,
    output reg                        spi_start,
    output reg  [DAC_BITS-1:0]        spi_data,

    // ADC side
    input  wire                       adc_valid,
    input  wire signed [31:0]         adc_a_uv,
    input  wire signed [31:0]         adc_b_uv,
    output reg                        adc_start,

    // Per-code output record
    output reg                        record_valid,
    output reg                        record_ramp_up,
    output reg  [DAC_BITS-1:0]        record_dac_code,
    output reg  signed [31:0]         record_adc_a_uv,
    output reg  signed [31:0]         record_adc_b_uv,
    output reg  [15:0]                record_hold_index,
    output reg  [15:0]                record_sample_count,

    // Status
    output reg                        busy,
    output reg                        done,
    output wire                       wait_for_ack,
    output reg                        current_ramp_up,
    output reg  [DAC_BITS-1:0]        current_dac_code,
    output reg  [15:0]                current_hold_index,
    output wire [3:0]                 debug_state,
    output wire [31:0]                debug_settle_count,
    output wire [15:0]                debug_sample_count
);

    localparam [3:0]
        ST_IDLE        = 4'd0,
        ST_SPI_START   = 4'd1,
        ST_WAIT_SPI    = 4'd2,
        ST_SETTLE      = 4'd3,
        ST_ADC_START   = 4'd4,
        ST_WAIT_ADC    = 4'd5,
        ST_RECORD_OUT  = 4'd6,
        ST_AVG         = 4'd7,
        ST_NEXT_CODE   = 4'd8,
        ST_WAIT_ACK    = 4'd9,
        ST_HOLD_WAIT   = 4'd10,
        ST_DONE        = 4'd11;

    localparam [15:0]         DEFAULT_SAMPLES_PER_CODE_U   = DEFAULT_SAMPLES_PER_CODE;
    localparam [DAC_BITS-1:0] DEFAULT_STEP_SIZE_U          = DEFAULT_STEP_SIZE;
    localparam [15:0]         DEFAULT_HOLD_SAMPLE_COUNT_U  = DEFAULT_HOLD_SAMPLE_COUNT;

    reg [3:0]                 state;
    reg [31:0]                settle_count;
    reg [15:0]                sample_count;
    reg signed [ACC_WIDTH-1:0] sum_a_uv;
    reg signed [ACC_WIDTH-1:0] sum_b_uv;
    reg signed [ACC_WIDTH-1:0] avg_sum_a_uv;
    reg signed [ACC_WIDTH-1:0] avg_sum_b_uv;
    reg [4:0]                 avg_shift;

    wire [DAC_BITS-1:0] scan_low_code;
    wire [DAC_BITS-1:0] scan_high_code;
    wire [31:0]         settle_cycles_eff;
    wire [15:0]         samples_per_code_req;
    wire [15:0]         samples_per_code_eff;
    wire [4:0]          sample_shift_eff;
    wire [DAC_BITS-1:0] step_code_eff;
    wire [15:0]         hold_sample_count_eff;
    wire [31:0]         hold_interval_cycles_eff;
    wire [DAC_BITS:0]   current_plus_step;
    wire [DAC_BITS:0]   low_plus_step;
    wire                more_hold_points;
    wire signed [ACC_WIDTH-1:0] adc_a_uv_ext;
    wire signed [ACC_WIDTH-1:0] adc_b_uv_ext;

    function automatic [15:0] round_up_pow2_samples;
        input [15:0] value;
        begin
            if (value <= 16'd1)       round_up_pow2_samples = 16'd1;
            else if (value <= 16'd2)  round_up_pow2_samples = 16'd2;
            else if (value <= 16'd4)  round_up_pow2_samples = 16'd4;
            else if (value <= 16'd8)  round_up_pow2_samples = 16'd8;
            else if (value <= 16'd16) round_up_pow2_samples = 16'd16;
            else if (value <= 16'd32) round_up_pow2_samples = 16'd32;
            else if (value <= 16'd64) round_up_pow2_samples = 16'd64;
            else if (value <= 16'd128) round_up_pow2_samples = 16'd128;
            else if (value <= 16'd256) round_up_pow2_samples = 16'd256;
            else if (value <= 16'd512) round_up_pow2_samples = 16'd512;
            else if (value <= 16'd1024) round_up_pow2_samples = 16'd1024;
            else if (value <= 16'd2048) round_up_pow2_samples = 16'd2048;
            else if (value <= 16'd4096) round_up_pow2_samples = 16'd4096;
            else if (value <= 16'd8192) round_up_pow2_samples = 16'd8192;
            else if (value <= 16'd16384) round_up_pow2_samples = 16'd16384;
            else                        round_up_pow2_samples = 16'd32768;
        end
    endfunction

    function automatic [4:0] sample_shift;
        input [15:0] value;
        begin
            case (value)
                16'd1:     sample_shift = 5'd0;
                16'd2:     sample_shift = 5'd1;
                16'd4:     sample_shift = 5'd2;
                16'd8:     sample_shift = 5'd3;
                16'd16:    sample_shift = 5'd4;
                16'd32:    sample_shift = 5'd5;
                16'd64:    sample_shift = 5'd6;
                16'd128:   sample_shift = 5'd7;
                16'd256:   sample_shift = 5'd8;
                16'd512:   sample_shift = 5'd9;
                16'd1024:  sample_shift = 5'd10;
                16'd2048:  sample_shift = 5'd11;
                16'd4096:  sample_shift = 5'd12;
                16'd8192:  sample_shift = 5'd13;
                16'd16384: sample_shift = 5'd14;
                default:   sample_shift = 5'd15;
            endcase
        end
    endfunction

    assign scan_low_code = (scan_min_code <= scan_max_code) ? scan_min_code : scan_max_code;
    assign scan_high_code = (scan_min_code <= scan_max_code) ? scan_max_code : scan_min_code;
    assign settle_cycles_eff = settle_cycles_cfg;
    assign samples_per_code_req = (samples_per_code_cfg != 16'd0) ?
                                  samples_per_code_cfg : DEFAULT_SAMPLES_PER_CODE_U;
    assign samples_per_code_eff = round_up_pow2_samples(samples_per_code_req);
    assign sample_shift_eff = sample_shift(samples_per_code_eff);
    assign step_code_eff = (step_size_cfg != {DAC_BITS{1'b0}}) ?
                           step_size_cfg : DEFAULT_STEP_SIZE_U;
    assign hold_sample_count_eff = (hold_sample_count_cfg != 16'd0) ?
                                   hold_sample_count_cfg : DEFAULT_HOLD_SAMPLE_COUNT_U;
    assign hold_interval_cycles_eff = hold_interval_cycles_cfg;
    assign current_plus_step = {1'b0, current_dac_code} + {1'b0, step_code_eff};
    assign low_plus_step = {1'b0, scan_low_code} + {1'b0, step_code_eff};
    assign more_hold_points = ({1'b0, current_hold_index} + 17'd1) <
                              {1'b0, hold_sample_count_eff};
    assign adc_a_uv_ext = {{(ACC_WIDTH-32){adc_a_uv[31]}}, adc_a_uv};
    assign adc_b_uv_ext = {{(ACC_WIDTH-32){adc_b_uv[31]}}, adc_b_uv};
    assign wait_for_ack = (state == ST_WAIT_ACK);
    assign debug_state = state;
    assign debug_settle_count = settle_count;
    assign debug_sample_count = sample_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            state               <= ST_IDLE;
            settle_count        <= 32'd0;
            sample_count        <= 16'd0;
            sum_a_uv            <= {ACC_WIDTH{1'b0}};
            sum_b_uv            <= {ACC_WIDTH{1'b0}};
            avg_sum_a_uv        <= {ACC_WIDTH{1'b0}};
            avg_sum_b_uv        <= {ACC_WIDTH{1'b0}};
            avg_shift           <= 5'd0;
            spi_start           <= 1'b0;
            spi_data            <= {DAC_BITS{1'b0}};
            adc_start           <= 1'b0;
            record_valid        <= 1'b0;
            record_ramp_up      <= 1'b1;
            record_dac_code     <= {DAC_BITS{1'b0}};
            record_adc_a_uv     <= 32'sd0;
            record_adc_b_uv     <= 32'sd0;
            record_hold_index   <= 16'd0;
            record_sample_count <= 16'd0;
            busy                <= 1'b0;
            done                <= 1'b0;
            current_ramp_up     <= 1'b1;
            current_dac_code    <= {DAC_BITS{1'b0}};
            current_hold_index  <= 16'd0;
        end else begin
            spi_start    <= 1'b0;
            adc_start    <= 1'b0;
            record_valid <= 1'b0;
            done         <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (enable) begin
                        busy             <= 1'b1;
                        current_ramp_up  <= 1'b1;
                        current_dac_code <= scan_low_code;
                        current_hold_index <= 16'd0;
                        spi_data         <= scan_low_code;
                        sample_count     <= 16'd0;
                        sum_a_uv         <= {ACC_WIDTH{1'b0}};
                        sum_b_uv         <= {ACC_WIDTH{1'b0}};
                        state            <= ST_SPI_START;
                    end
                end

                ST_SPI_START: begin
                    if (!spi_busy) begin
                        spi_data <= current_dac_code;
                        spi_start <= 1'b1;
                        state <= ST_WAIT_SPI;
                    end
                end

                ST_WAIT_SPI: begin
                    if (spi_done) begin
                        settle_count <= 32'd0;
                        current_hold_index <= 16'd0;
                        state <= ST_SETTLE;
                    end
                end

                ST_SETTLE: begin
                    if ((settle_cycles_eff == 32'd0) ||
                        (settle_count >= (settle_cycles_eff - 1'b1))) begin
                        sample_count <= 16'd0;
                        sum_a_uv     <= {ACC_WIDTH{1'b0}};
                        sum_b_uv     <= {ACC_WIDTH{1'b0}};
                        state        <= ST_ADC_START;
                    end else begin
                        settle_count <= settle_count + 1'b1;
                    end
                end

                ST_ADC_START: begin
                    adc_start <= 1'b1;
                    state <= ST_WAIT_ADC;
                end

                ST_WAIT_ADC: begin
                    adc_start <= 1'b1;
                    if (adc_valid) begin
                        sum_a_uv <= sum_a_uv + adc_a_uv_ext;
                        sum_b_uv <= sum_b_uv + adc_b_uv_ext;

                        if (sample_count >= (samples_per_code_eff - 1'b1)) begin
                            avg_sum_a_uv        <= sum_a_uv + adc_a_uv_ext;
                            avg_sum_b_uv        <= sum_b_uv + adc_b_uv_ext;
                            avg_shift           <= sample_shift_eff;
                            record_ramp_up      <= current_ramp_up;
                            record_dac_code     <= current_dac_code;
                            record_hold_index   <= current_hold_index;
                            record_sample_count <= samples_per_code_eff;
                            state               <= ST_AVG;
                        end else begin
                            sample_count <= sample_count + 1'b1;
                            state        <= ST_ADC_START;
                        end
                    end
                end

                ST_AVG: begin
                    record_valid    <= 1'b1;
                    record_adc_a_uv <= avg_sum_a_uv >>> avg_shift;
                    record_adc_b_uv <= avg_sum_b_uv >>> avg_shift;
                    state           <= ST_RECORD_OUT;
                end

                ST_RECORD_OUT: begin
                    if (single_step_mode) begin
                        state <= ST_WAIT_ACK;
                    end else if (more_hold_points) begin
                        current_hold_index <= current_hold_index + 1'b1;
                        settle_count <= 32'd0;
                        state <= ST_HOLD_WAIT;
                    end else begin
                        state <= ST_NEXT_CODE;
                    end
                end

                ST_WAIT_ACK: begin
                    busy <= 1'b1;
                    if (!enable) begin
                        busy  <= 1'b0;
                        state <= ST_IDLE;
                    end else if (step_ack) begin
                        if (more_hold_points) begin
                            current_hold_index <= current_hold_index + 1'b1;
                            settle_count <= 32'd0;
                            state <= ST_HOLD_WAIT;
                        end else begin
                            state <= ST_NEXT_CODE;
                        end
                    end
                end

                ST_HOLD_WAIT: begin
                    if ((hold_interval_cycles_eff == 32'd0) ||
                        (settle_count >= (hold_interval_cycles_eff - 1'b1))) begin
                        sample_count <= 16'd0;
                        sum_a_uv     <= {ACC_WIDTH{1'b0}};
                        sum_b_uv     <= {ACC_WIDTH{1'b0}};
                        state        <= ST_ADC_START;
                    end else begin
                        settle_count <= settle_count + 1'b1;
                    end
                end

                ST_NEXT_CODE: begin
                    if (scan_low_code == scan_high_code) begin
                        if (LOOP_ENABLE != 0 && enable) begin
                            current_ramp_up   <= 1'b1;
                            current_dac_code  <= scan_low_code;
                            current_hold_index <= 16'd0;
                            state             <= ST_SPI_START;
                        end else begin
                            state <= ST_DONE;
                        end
                    end else if (current_ramp_up) begin
                        if (current_dac_code >= scan_high_code) begin
                            current_ramp_up <= 1'b0;
                            current_dac_code <= scan_high_code;
                            current_hold_index <= 16'd0;
                            state <= ST_SPI_START;
                        end else if (current_plus_step >= {1'b0, scan_high_code}) begin
                            current_dac_code <= scan_high_code;
                            current_hold_index <= 16'd0;
                            state <= ST_SPI_START;
                        end else begin
                            current_dac_code <= current_dac_code + step_code_eff;
                            current_hold_index <= 16'd0;
                            state <= ST_SPI_START;
                        end
                    end else begin
                        if (current_dac_code <= scan_low_code) begin
                            if (LOOP_ENABLE != 0 && enable) begin
                                current_ramp_up  <= 1'b1;
                                current_dac_code <= scan_low_code;
                                current_hold_index <= 16'd0;
                                state            <= ST_SPI_START;
                            end else begin
                                state <= ST_DONE;
                            end
                        end else if ({1'b0, current_dac_code} <= low_plus_step) begin
                            current_dac_code <= scan_low_code;
                            current_hold_index <= 16'd0;
                            state <= ST_SPI_START;
                        end else begin
                            current_dac_code <= current_dac_code - step_code_eff;
                            current_hold_index <= 16'd0;
                            state <= ST_SPI_START;
                        end
                    end
                end

                ST_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    if (!enable) begin
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
