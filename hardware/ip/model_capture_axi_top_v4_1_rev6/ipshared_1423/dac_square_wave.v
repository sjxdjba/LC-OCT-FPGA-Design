`timescale 1ns / 1ps

// DAC square-wave generator for camera trigger via CS2.
//
// When enabled and ADC code A exceeds the threshold, this module drives
// alternating HIGH / LOW DAC codes to CS2 through the shared SPI bus,
// producing a ~16.8 us analog square wave (60:40 duty, ~59.5 kHz) at the DAC8830 output.
//
// pulse_count = 0  → continuous (runs until enable deasserted).
// pulse_count = N  → outputs exactly N square-wave cycles, then stops.
//
// SPI arbitration: req asserts when this module needs the bus. The top-level
// mux must grant priority to req over fast_sweep during active sweep.
module dac_square_wave #(
    parameter integer DAC_BITS    = 16
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                enable,            // fast_sweep_active && camera_trig_enable
    input  wire signed [15:0]  adc_code_a,
    input  wire signed [15:0]  threshold,         // runtime-configurable trigger threshold
    input  wire [15:0]         pulse_count,       // 0=continuous, N=exactly N pulses
    input  wire [31:0]         high_cycles,       // wait cycles after HIGH SPI done
    input  wire [31:0]         low_cycles,        // wait cycles after LOW SPI done
    input  wire                spi_busy,
    input  wire                spi_done,          // gated: only fires for camera transactions
    output wire                spi_req,           // asserted when camera needs SPI
    output reg                 spi_start,
    output reg  [DAC_BITS-1:0] spi_data,
    output reg                 active,
    output reg  [15:0]         pulses_done       // number of completed pulses
);

    localparam [DAC_BITS-1:0] HIGH_CODE = {DAC_BITS{1'b1}};
    localparam [DAC_BITS-1:0] LOW_CODE  = {DAC_BITS{1'b0}};

    localparam [2:0] IDLE         = 3'd0,
                     SEND_HIGH    = 3'd1,
                     HIGH_PENDING = 3'd2,
                     WAIT_HIGH    = 3'd3,
                     SEND_LOW     = 3'd4,
                     LOW_PENDING  = 3'd5,
                     WAIT_LOW     = 3'd6;

    reg [2:0]  state;
    reg [31:0] timer;
    reg [15:0] pulse_cnt;

    // spi_req must stay asserted from the moment we want to send until
    // spi_done, so the top-level SPI arbiter keeps target_sel=2'b10
    // and routes our spi_start to the SPI module.
    assign spi_req = (state == SEND_HIGH  || state == HIGH_PENDING ||
                      state == SEND_LOW   || state == LOW_PENDING);

    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= IDLE;
            timer       <= 11'd0;
            spi_start   <= 1'b0;
            spi_data    <= {DAC_BITS{1'b0}};
            active      <= 1'b0;
            pulse_cnt   <= 16'd0;
            pulses_done <= 16'd0;
        end else begin
            spi_start <= 1'b0;

            case (state)
                IDLE: begin
                    active      <= 1'b0;
                    timer       <= 11'd0;
                    pulses_done <= 16'd0;
                    if (enable && adc_code_a > threshold) begin
                        active    <= 1'b1;
                        pulse_cnt <= pulse_count;
                        spi_data  <= HIGH_CODE;
                        state     <= SEND_HIGH;
                    end
                end

                // Wait for SPI bus free, then pulse spi_start.
                // spi_req=1 keeps the top-level mux pointed at us.
                SEND_HIGH: begin
                    active <= 1'b1;
                    if (!spi_busy) begin
                        spi_start <= 1'b1;
                        state     <= HIGH_PENDING;
                    end
                end

                // Wait for our CS2 transaction to complete.
                HIGH_PENDING: begin
                    active <= 1'b1;
                    if (spi_done) begin
                        timer <= 11'd0;
                        state <= WAIT_HIGH;
                    end
                end

                WAIT_HIGH: begin
                    active <= 1'b1;
                    if (timer == high_cycles - 1) begin
                        spi_data <= LOW_CODE;
                        state    <= SEND_LOW;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                SEND_LOW: begin
                    active <= 1'b1;
                    if (!spi_busy) begin
                        spi_start <= 1'b1;
                        state     <= LOW_PENDING;
                    end
                end

                LOW_PENDING: begin
                    active <= 1'b1;
                    if (spi_done) begin
                        timer <= 11'd0;
                        state <= WAIT_LOW;
                    end
                end

                WAIT_LOW: begin
                    if (!enable) begin
                        active <= 1'b0;
                        state  <= IDLE;
                    end else if (timer == low_cycles - 1) begin
                        // One full HIGH+LOW cycle completed
                        pulses_done <= pulses_done + 1'b1;
                        if (pulse_cnt != 16'd0) begin
                            pulse_cnt <= pulse_cnt - 1'b1;
                            if (pulse_cnt == 1) begin
                                active <= 1'b0;
                                state  <= IDLE;
                            end else begin
                                active   <= 1'b1;
                                spi_data <= HIGH_CODE;
                                state    <= SEND_HIGH;
                            end
                        end else begin
                            active   <= 1'b1;
                            spi_data <= HIGH_CODE;
                            state    <= SEND_HIGH;
                        end
                    end else begin
                        active <= 1'b1;
                        timer  <= timer + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
