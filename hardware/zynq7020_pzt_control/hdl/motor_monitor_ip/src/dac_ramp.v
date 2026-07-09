`timescale 1ns / 1ps

// DAC ramp generator: steps DAC code from 0 to target_code at maximum rate.
// At SPI_HALF_PERIOD_CYCLES=5 and 100 MHz clk, each step takes ~161 cycles
// = 1.61 us → ~621 kHz (close to 625 kHz target).
module dac_ramp #(
    parameter integer DAC_BITS = 16
) (
    input  wire                clk,
    input  wire                rst_n,

    input  wire                start,          // pulse high to begin ramp
    input  wire [DAC_BITS-1:0] target_code,    // stop when current_code >= target
    input  wire                spi_done,       // SPI transfer complete pulse
    output reg                 spi_start,      // to SPI driver
    output reg  [DAC_BITS-1:0] spi_data,       // DAC code to SPI
    output reg                 busy,           // ramping in progress
    output reg                 done            // reached target (one-shot pulse)
);

    localparam [1:0] IDLE = 2'd0,
                     RAMP = 2'd1,
                     DONE = 2'd2;

    reg [1:0]           state;
    reg [DAC_BITS-1:0]  current_code;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            spi_start    <= 1'b0;
            spi_data     <= {DAC_BITS{1'b0}};
            busy         <= 1'b0;
            done         <= 1'b0;
            current_code <= {DAC_BITS{1'b0}};
        end else begin
            spi_start <= 1'b0;
            done      <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        busy         <= 1'b1;
                        current_code <= {DAC_BITS{1'b0}};
                        spi_data     <= {DAC_BITS{1'b0}};
                        spi_start    <= 1'b1;
                        state        <= RAMP;
                    end
                end

                RAMP: begin
                    if (spi_done) begin
                        if (current_code >= target_code) begin
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            state <= DONE;
                        end else begin
                            current_code <= current_code + 1'b1;
                            spi_data     <= current_code + 1'b1;
                            spi_start    <= 1'b1;
                        end
                    end
                end

                DONE: begin
                    if (!start) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
