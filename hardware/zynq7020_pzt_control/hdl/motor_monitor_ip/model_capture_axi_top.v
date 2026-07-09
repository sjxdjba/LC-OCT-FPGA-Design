`timescale 1ns / 1ps

// Integrated AD/DA modeling top with AXI interfaces.
//
// AXI usage:
// - AXI4-Lite slave: control and status registers from PS.
// - AXI4-Stream master: sampled records to AXI DMA / PS memory.
//
// AXI-Lite control register (0x00) bit definitions:
// - bit[0]: run_enable. Start or stop a capture sweep (capture_manager).
// - bit[1]: clear_done_req. Pulse high for one write to clear record count.
// - bit[2]: step_ack. In single-step mode, pulse high after PS finishes
//           processing the current DA/AD point and PL may advance.
// - bit[3]: single_step_mode. 1 = wait for step_ack after each record.
// - bit[4]: ramp_start. Pulse high to start DAC ramp (takes over SPI).
// - bit[5]: fast_sweep_start. Pulse high to start fast DAC sweep + ADC capture.
//           Takes over SPI and ADC. Records streamed via AXI Stream.
// - bit[6]: camera_trig_enable. During fast sweep, when ADC raw code A
//           exceeds the threshold in REG_CAMERA_TRIG_THRESHOLD (default
//           13000), SPI sends alternating HIGH/LOW DAC codes to CS2
//           producing a ~16.8 us analog square wave (60:40 duty, ~59.5 kHz)
//           at the DAC output until this bit is cleared or fast sweep ends.
//
// Camera trigger threshold register (0x3C): signed 16-bit ADC code A
// threshold for triggering the CS2 square wave (default: 13000).
//
// Ramp/Sweep target register (0x2C): write DAC target code (bits [15:0]).
// Fast sweep cycles register (0x30): number of 0..full-scale..home iterations.
// Fast sweep zero-hold register (0x34): home hold time in fabric clock cycles.
// Fast sweep speed register (0x38): speed profile selector for DAC scan rate.
// With a 100 MHz fabric clock and integer SPI dividers, 625 kHz is exact while
// the "800 kHz" preset maps to the nearest faster practical divider.
//
// Internal flow:
// 1. capture_manager steps DAC code and waits for settling.
// 2. spi_for_8830 sends DAC code to the DAC module.
// 3. ad7616 performs one conversion for each requested sample.
// 4. capture_manager averages ADC data per DAC code.
// 5. One record is packed into AXI4-Stream and sent to PS.
//
// Stream packet format (64-bit, 2 beats per record):
// Beat 0:
// [15:0]   dac_code
// [16]     ramp_up
// [31:17]  reserved
// [63:32]  adc_a_uv
// Beat 1:
// [31:0]   adc_b_uv
// [47:32]  sample_count
// [63:48]  hold_index
// Normal capture asserts tlast on every record. Fast sweep asserts tlast only
// on the final record so one whole sweep becomes one AXIS packet.
module model_capture_axi_top #(
    parameter integer AXI_ADDR_WIDTH           = 7,
    parameter integer AXI_DATA_WIDTH           = 32,
    parameter integer AXIS_DATA_WIDTH          = 64,
    parameter integer DAC_BITS                 = 16,
    parameter integer DEFAULT_SETTLE_CYCLES    = 100000,
    parameter integer DEFAULT_SAMPLES_PER_CODE = 8,
    parameter integer DEFAULT_STEP_SIZE        = 1,
    parameter integer SPI_HALF_PERIOD_CYCLES   = 5,
    parameter [1:0]  DAC_TARGET_SEL            = 2'b01
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI:M_AXIS, ASSOCIATED_RESET s_axi_aresetn" *)
    input  wire                         s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                         s_axi_aresetn,

    // DAC pins (primary SPI, shared CS1/CS2)
    output wire                         dac_cs1,
    output wire                         dac_cs2,
    output wire                         dac_sclk,
    output wire                         dac_sdi,

    // DAC2 mirror pins (independent SPI, mirrors CS1 only)
    output wire                         dac2_cs1,
    output wire                         dac2_sclk,
    output wire                         dac2_sdi,

    // ADC pins
    input  wire                         adc_busy,
    input  wire [15:0]                  adc_data_bus_i,
    output wire [15:0]                  adc_data_bus_o,
    output wire                         adc_data_bus_t,
    output wire                         adc_convst,
    output wire                         adc_cs_n,
    output wire                         adc_rd_n,
    output wire                         adc_reset_n,
    output wire [2:0]                   adc_chsel,
    output wire [1:0]                   adc_hw_rngsel,
    output wire                         adc_burst,
    output wire                         adc_ser_par,

    // AXI4-Lite slave
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]                   s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                         s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output reg                          s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                         s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output reg                          s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output reg  [1:0]                   s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output reg                          s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                         s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]                   s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                         s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output reg                          s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output reg [AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output reg [1:0]                    s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output reg                          s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                         s_axi_rready,

    // AXI4-Stream master
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output reg  [AXIS_DATA_WIDTH-1:0]   m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *)
    output reg  [(AXIS_DATA_WIDTH/8)-1:0] m_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output reg                          m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire                         m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output reg                          m_axis_tlast,

    // Interrupt output to PS7 IRQ_F2P
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 intr intr" *)
    (* X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *)
    output wire                         intr
);

    wire clk;
    wire rst_n;
    assign clk   = s_axi_aclk;
    assign rst_n = s_axi_aresetn;

    localparam [AXI_ADDR_WIDTH-1:0] REG_CONTROL               = 7'h00;
    localparam [AXI_ADDR_WIDTH-1:0] REG_STATUS                = 7'h04;
    localparam [AXI_ADDR_WIDTH-1:0] REG_COUNT                 = 7'h08;
    localparam [AXI_ADDR_WIDTH-1:0] REG_LAST0                 = 7'h0C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_LAST1                 = 7'h10;
    localparam [AXI_ADDR_WIDTH-1:0] REG_DEBUG0                = 7'h14;
    localparam [AXI_ADDR_WIDTH-1:0] REG_DEBUG1                = 7'h18;
    localparam [AXI_ADDR_WIDTH-1:0] REG_DEBUG2                = 7'h1C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_DEBUG3                = 7'h20;
    localparam [AXI_ADDR_WIDTH-1:0] REG_DEBUG4                = 7'h24;
    localparam [AXI_ADDR_WIDTH-1:0] REG_DEBUG5                = 7'h28;
    localparam [AXI_ADDR_WIDTH-1:0] REG_RAMP_TARGET           = 7'h2C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_FAST_SWEEP_CYCLES     = 7'h30;
    localparam [AXI_ADDR_WIDTH-1:0] REG_FAST_SWEEP_HOLD       = 7'h34;
    localparam [AXI_ADDR_WIDTH-1:0] REG_FAST_SWEEP_SPEED      = 7'h38;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAMERA_TRIG_THRESHOLD = 7'h3C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAMERA_PULSE_COUNT    = 7'h40;
    localparam [AXI_ADDR_WIDTH-1:0] REG_INTR_STATUS           = 7'h44;
    localparam [AXI_ADDR_WIDTH-1:0] REG_FWD_PAD_CYCLES        = 7'h48;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CS2_HIGH_CYCLES       = 7'h4C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CS2_LOW_CYCLES        = 7'h50;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_SCAN_MIN      = 7'h54;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_SCAN_MAX      = 7'h58;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_SETTLE_CYCLES = 7'h5C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_SAMPLES       = 7'h60;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_STEP_SIZE     = 7'h64;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_HOLD_COUNT    = 7'h68;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_HOLD_INTERVAL = 7'h6C;

    localparam [1:0]
        STREAM_IDLE  = 2'd0,
        STREAM_BEAT0 = 2'd1,
        STREAM_BEAT1 = 2'd2;

    reg run_enable;
    reg single_step_mode;
    reg clear_done_req;
    reg step_ack_req;
    reg camera_trig_enable;
    reg signed [15:0] camera_trig_threshold;
    reg [15:0] camera_pulse_count;

    // Interrupt latches (set on event, write-1-to-clear)
    reg intr_capture_done_latch;
    reg intr_fast_sweep_done_latch;
    reg intr_camera_done_latch;
    reg capture_done_d1;
    reg fast_sweep_done_d1;
    reg camera_active_d1;

    assign intr = intr_capture_done_latch | intr_fast_sweep_done_latch |
                  intr_camera_done_latch;
    reg ctrl_aw_en;

    reg ramp_start_req;
    reg ramp_active;
    reg [DAC_BITS-1:0] ramp_target_code;
    reg [31:0] fast_sweep_cycles_cfg;
    reg [31:0] fast_sweep_hold_cycles_cfg;
    reg [15:0] fwd_spi_half_period_reg;
    reg [31:0] fwd_pad_cycles_reg;
    reg [31:0] cs2_high_cycles_reg;
    reg [31:0] cs2_low_cycles_reg;
    reg [DAC_BITS-1:0] capture_scan_min_code_reg;
    reg [DAC_BITS-1:0] capture_scan_max_code_reg;
    reg [31:0] capture_settle_cycles_reg;
    reg [15:0] capture_samples_per_code_reg;
    reg [DAC_BITS-1:0] capture_step_size_reg;
    reg [15:0] capture_hold_count_reg;
    reg [31:0] capture_hold_interval_cycles_reg;

    reg fast_sweep_start_req;
    reg fast_sweep_active;

    reg [31:0] record_counter;
    reg [31:0] last_record_word0;
    reg [31:0] last_record_word1;
    reg [31:0] adc_valid_counter;
    reg [31:0] adc_last_raw_codes;

    wire capture_busy;
    wire capture_done;
    wire capture_spi_start;
    wire [DAC_BITS-1:0] capture_spi_data;
    wire capture_adc_start;
    wire capture_record_valid;
    wire capture_record_ramp_up;
    wire [DAC_BITS-1:0] capture_record_dac_code;
    wire signed [31:0] capture_record_adc_a_uv;
    wire signed [31:0] capture_record_adc_b_uv;
    wire [15:0] capture_record_hold_index;
    wire [15:0] capture_record_sample_count;
    wire capture_wait_for_ack;
    wire capture_current_ramp_up;
    wire [DAC_BITS-1:0] capture_current_dac_code;
    wire [15:0] capture_current_hold_index;
    wire [3:0] capture_debug_state;
    wire [31:0] capture_debug_settle_count;
    wire [15:0] capture_debug_sample_count;

    wire camera_spi_req;
    wire camera_spi_start;
    wire [DAC_BITS-1:0] camera_spi_data;
    wire camera_active;
    wire [15:0] camera_pulses_done;

    // CS2 camera pulse-done detect
    wire camera_pulse_done_event;
    assign camera_pulse_done_event = camera_active_d1 && !camera_active &&
                                     (camera_pulse_count != 16'd0);

    wire ramp_spi_start;
    wire [DAC_BITS-1:0] ramp_spi_data;
    wire ramp_busy;
    wire ramp_done;

    wire fast_sweep_spi_start;
    wire [DAC_BITS-1:0] fast_sweep_spi_data;
    wire fast_sweep_adc_start;
    wire fast_sweep_busy;
    wire fast_sweep_done;
    wire fast_sweep_record_valid;
    wire fast_sweep_record_last;
    wire fast_sweep_record_ramp_up;
    wire [DAC_BITS-1:0] fast_sweep_record_dac_code;
    wire signed [31:0] fast_sweep_record_adc_a_uv;
    wire signed [31:0] fast_sweep_record_adc_b_uv;
    wire fast_sweep_rev_mode;

    // Queue one pending request per source so one-cycle start pulses are not
    // lost when camera CS2 traffic preempts the sweep/capture SPI path.
    reg spi_start_arb;
    reg mirror_spi_start;
    reg [1:0] spi_target_sel_arb;
    reg [DAC_BITS-1:0] spi_data_arb;
    reg [15:0] spi_half_period_cycles_arb;
    reg spi_issue_inflight;
    reg spi_owner;
    reg normal_spi_pending;
    reg [DAC_BITS-1:0] normal_spi_data_pending;
    reg [15:0] normal_spi_half_period_pending;
    reg camera_spi_pending;
    reg [DAC_BITS-1:0] camera_spi_data_pending;
    reg [15:0] camera_spi_half_period_pending;

    wire spi_busy;
    wire spi_done;
    wire spi_done_norm;
    wire spi_done_cam;
    assign spi_done_norm = spi_done && !spi_owner;
    assign spi_done_cam  = spi_done && spi_owner;

    // SPI source mux: fast_sweep > dac_ramp > capture_manager
    wire normal_spi_start;
    wire [DAC_BITS-1:0] normal_spi_data;
    wire spi_start_mux;
    wire [DAC_BITS-1:0] spi_data_mux;
    wire [15:0] spi_half_period_cycles_mux;
    assign normal_spi_start = ramp_active ? ramp_spi_start : capture_spi_start;
    assign normal_spi_data  = ramp_active ? ramp_spi_data  : capture_spi_data;
    assign spi_start_mux = fast_sweep_active ? fast_sweep_spi_start : normal_spi_start;
    assign spi_data_mux  = fast_sweep_active ? fast_sweep_spi_data  : normal_spi_data;
    assign spi_half_period_cycles_mux = fast_sweep_active ?
        (fast_sweep_rev_mode ? 16'd1 : fwd_spi_half_period_reg) :  // rev=1, fwd=register
        SPI_HALF_PERIOD_CYCLES;

    // ADC enable mux: fast_sweep or capture_manager
    wire adc_enable;
    assign adc_enable = fast_sweep_active ? fast_sweep_adc_start : capture_adc_start;

    // When ramp or fast_sweep is active, disable capture_manager to prevent conflict
    wire capture_run_enable = run_enable && !ramp_active && !fast_sweep_active;

    // Record source mux: fast_sweep or capture_manager
    wire mux_record_valid;
    wire mux_record_last;
    wire [DAC_BITS-1:0] mux_record_dac_code;
    wire [15:0] mux_record_ramp_up;
    wire signed [31:0] mux_record_adc_a_uv;
    wire signed [31:0] mux_record_adc_b_uv;
    wire [15:0] mux_record_hold_index;
    wire [15:0] mux_record_sample_count;
    assign mux_record_valid    = fast_sweep_active ? fast_sweep_record_valid    : capture_record_valid;
    assign mux_record_last     = fast_sweep_active ? fast_sweep_record_last     : 1'b1;
    assign mux_record_dac_code = fast_sweep_active ? fast_sweep_record_dac_code : capture_record_dac_code;
    assign mux_record_ramp_up  = fast_sweep_active ? {15'd0, fast_sweep_record_ramp_up} : {15'd0, capture_record_ramp_up};
    assign mux_record_adc_a_uv = fast_sweep_active ? fast_sweep_record_adc_a_uv : capture_record_adc_a_uv;
    assign mux_record_adc_b_uv = fast_sweep_active ? fast_sweep_record_adc_b_uv : capture_record_adc_b_uv;
    assign mux_record_hold_index = fast_sweep_active ? 16'd0 : capture_record_hold_index;
    assign mux_record_sample_count = fast_sweep_active ? 16'd1 : capture_record_sample_count;

    wire adc_init_done;
    wire adc_data_valid;
    wire signed [15:0] adc_code_a;
    wire signed [15:0] adc_code_b;
    wire signed [31:0] adc_voltage_a_uv;
    wire signed [31:0] adc_voltage_b_uv;
    wire [3:0] adc_debug_state;
    wire [31:0] adc_debug_counter;
    wire [15:0] adc_debug_data_bus_in;
    wire adc_debug_data_bus_t;
    wire signed [15:0] adc_debug_sample_a;

    reg [1:0]                 stream_state;
    reg                       stream_last_buf;
    reg [63:0]                stream_beat0_buf;
    reg [63:0]                stream_beat1_buf;
    reg [63:0]                stream_fifo_beat0 [0:3];
    reg [63:0]                stream_fifo_beat1 [0:3];
    reg                       stream_fifo_last  [0:3];
    reg [1:0]                 stream_fifo_wr_ptr;
    reg [1:0]                 stream_fifo_rd_ptr;
    reg [2:0]                 stream_fifo_count;
    reg                       stream_fifo_overflow;
    wire                      stream_fifo_pop;
    wire                      stream_fifo_push;
    wire                      stream_pending_status;

    wire unused_awprot;
    wire unused_arprot;
    assign unused_awprot = ^s_axi_awprot;
    assign unused_arprot = ^s_axi_arprot;
    assign stream_fifo_pop = (stream_state == STREAM_IDLE) &&
                             (stream_fifo_count != 3'd0);
    assign stream_fifo_push = mux_record_valid &&
                              ((stream_fifo_count < 3'd4) || stream_fifo_pop);
    assign stream_pending_status = (stream_fifo_count != 3'd0) ||
                                   (stream_state != STREAM_IDLE);

    // Behavioral tri-state: let Vivado infer the correct buffer at the BD top level.
    // Do NOT use explicit IOBUF here — Vivado inserts BIBUF at the BD boundary
    // for the inout port, and cascading IOBUF below BIBUF breaks the input path.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready  <= 1'b0;
            s_axi_wready   <= 1'b0;
            s_axi_bvalid   <= 1'b0;
            s_axi_bresp    <= 2'b00;
            ctrl_aw_en     <= 1'b1;
            run_enable     <= 1'b0;
            single_step_mode <= 1'b0;
            clear_done_req <= 1'b0;
            step_ack_req   <= 1'b0;
            camera_trig_enable <= 1'b0;
            camera_trig_threshold <= 16'sd13000;
            camera_pulse_count    <= 16'd0;
            ramp_start_req <= 1'b0;
            fast_sweep_start_req <= 1'b0;
            ramp_target_code <= {DAC_BITS{1'b0}};
            fast_sweep_cycles_cfg <= 32'd10;
            fast_sweep_hold_cycles_cfg <= 32'd1000000;
            fwd_spi_half_period_reg <= 16'd2;
            fwd_pad_cycles_reg      <= 32'd19;
            cs2_high_cycles_reg     <= 32'd944;
            cs2_low_cycles_reg      <= 32'd608;
            capture_scan_min_code_reg <= {DAC_BITS{1'b0}};
            capture_scan_max_code_reg <= {DAC_BITS{1'b1}};
            capture_settle_cycles_reg <= DEFAULT_SETTLE_CYCLES;
            capture_samples_per_code_reg <= DEFAULT_SAMPLES_PER_CODE;
            capture_step_size_reg <= DEFAULT_STEP_SIZE;
            capture_hold_count_reg <= 16'd1;
            capture_hold_interval_cycles_reg <= 32'd0;
        end else begin
            clear_done_req <= 1'b0;
            step_ack_req         <= 1'b0;
            ramp_start_req       <= 1'b0;
            fast_sweep_start_req <= 1'b0;

            if (!s_axi_awready && s_axi_awvalid && s_axi_wvalid && ctrl_aw_en) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                ctrl_aw_en    <= 1'b0;
            end else begin
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
            end

            if (!s_axi_bvalid && s_axi_awready && s_axi_awvalid && s_axi_wready && s_axi_wvalid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;

                case (s_axi_awaddr)
                    REG_CONTROL: begin
                        if (s_axi_wstrb[0]) begin
                            run_enable         <= s_axi_wdata[0];
                            clear_done_req     <= s_axi_wdata[1];
                            step_ack_req       <= s_axi_wdata[2];
                            single_step_mode   <= s_axi_wdata[3];
                            ramp_start_req     <= s_axi_wdata[4];
                            fast_sweep_start_req <= s_axi_wdata[5];
                            camera_trig_enable <= s_axi_wdata[6];
                        end
                    end
                    REG_RAMP_TARGET: begin
                        if (s_axi_wstrb[0]) begin
                            ramp_target_code <= s_axi_wdata[DAC_BITS-1:0];
                        end
                    end
                    REG_FAST_SWEEP_CYCLES: begin
                        if (&s_axi_wstrb) begin
                            fast_sweep_cycles_cfg <= s_axi_wdata;
                        end
                    end
                    REG_FAST_SWEEP_HOLD: begin
                        if (&s_axi_wstrb) begin
                            fast_sweep_hold_cycles_cfg <= s_axi_wdata;
                        end
                    end
                    REG_FAST_SWEEP_SPEED: begin
                        if (s_axi_wstrb[0]) fwd_spi_half_period_reg <= s_axi_wdata[15:0];
                    end
                    REG_CAMERA_TRIG_THRESHOLD: begin
                        if (s_axi_wstrb[0]) begin
                            camera_trig_threshold <= s_axi_wdata[15:0];
                        end
                    end
                    REG_CAMERA_PULSE_COUNT: begin
                        if (s_axi_wstrb[0]) begin
                            camera_pulse_count <= s_axi_wdata[15:0];
                        end
                    end
                    REG_INTR_STATUS: begin
                        if (s_axi_wstrb[0]) begin
                            if (s_axi_wdata[0]) intr_capture_done_latch   <= 1'b0;
                            if (s_axi_wdata[1]) intr_fast_sweep_done_latch <= 1'b0;
                            if (s_axi_wdata[2]) intr_camera_done_latch    <= 1'b0;
                        end
                    end
                    REG_FWD_PAD_CYCLES: begin
                        if (&s_axi_wstrb) fwd_pad_cycles_reg <= s_axi_wdata;
                    end
                    REG_CS2_HIGH_CYCLES: begin
                        if (&s_axi_wstrb) cs2_high_cycles_reg <= s_axi_wdata;
                    end
                    REG_CS2_LOW_CYCLES: begin
                        if (&s_axi_wstrb) cs2_low_cycles_reg <= s_axi_wdata;
                    end
                    REG_CAPTURE_SCAN_MIN: begin
                        if (s_axi_wstrb[0]) capture_scan_min_code_reg <= s_axi_wdata[DAC_BITS-1:0];
                    end
                    REG_CAPTURE_SCAN_MAX: begin
                        if (s_axi_wstrb[0]) capture_scan_max_code_reg <= s_axi_wdata[DAC_BITS-1:0];
                    end
                    REG_CAPTURE_SETTLE_CYCLES: begin
                        if (&s_axi_wstrb) capture_settle_cycles_reg <= s_axi_wdata;
                    end
                    REG_CAPTURE_SAMPLES: begin
                        if (s_axi_wstrb[0]) capture_samples_per_code_reg <= s_axi_wdata[15:0];
                    end
                    REG_CAPTURE_STEP_SIZE: begin
                        if (s_axi_wstrb[0]) capture_step_size_reg <= s_axi_wdata[DAC_BITS-1:0];
                    end
                    REG_CAPTURE_HOLD_COUNT: begin
                        if (s_axi_wstrb[0]) capture_hold_count_reg <= s_axi_wdata[15:0];
                    end
                    REG_CAPTURE_HOLD_INTERVAL: begin
                        if (&s_axi_wstrb) capture_hold_interval_cycles_reg <= s_axi_wdata;
                    end
                    default: begin
                    end
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
                ctrl_aw_en   <= 1'b1;
            end
        end

        // Ramp active: set when ramp_start_req pulsed, cleared when ramp finishes
        if (!rst_n) begin
            ramp_active <= 1'b0;
        end else begin
            if (ramp_start_req) begin
                ramp_active <= 1'b1;
            end else if (ramp_done) begin
                ramp_active <= 1'b0;
            end
        end

        // Fast sweep active: set when fast_sweep_start_req pulsed, cleared when done
        if (!rst_n) begin
            fast_sweep_active <= 1'b0;
        end else begin
            if (fast_sweep_start_req) begin
                fast_sweep_active <= 1'b1;
            end else if (fast_sweep_done) begin
                fast_sweep_active <= 1'b0;
            end
        end

        // Interrupt edge-detect and latch
        if (!rst_n) begin
            intr_capture_done_latch   <= 1'b0;
            intr_fast_sweep_done_latch <= 1'b0;
            intr_camera_done_latch    <= 1'b0;
            capture_done_d1           <= 1'b0;
            fast_sweep_done_d1        <= 1'b0;
            camera_active_d1          <= 1'b0;
        end else begin
            capture_done_d1    <= capture_done;
            fast_sweep_done_d1 <= fast_sweep_done;
            camera_active_d1   <= camera_active;

            if (capture_done && !capture_done_d1)
                intr_capture_done_latch <= 1'b1;
            if (fast_sweep_done && !fast_sweep_done_d1)
                intr_fast_sweep_done_latch <= 1'b1;
            if (camera_pulse_done_event)
                intr_camera_done_latch <= 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_start_arb                <= 1'b0;
            mirror_spi_start             <= 1'b0;
            spi_target_sel_arb           <= 2'b00;
            spi_data_arb                 <= {DAC_BITS{1'b0}};
            spi_half_period_cycles_arb   <= SPI_HALF_PERIOD_CYCLES;
            spi_issue_inflight           <= 1'b0;
            spi_owner                    <= 1'b0;
            normal_spi_pending           <= 1'b0;
            normal_spi_data_pending      <= {DAC_BITS{1'b0}};
            normal_spi_half_period_pending <= SPI_HALF_PERIOD_CYCLES;
            camera_spi_pending           <= 1'b0;
            camera_spi_data_pending      <= {DAC_BITS{1'b0}};
            camera_spi_half_period_pending <= SPI_HALF_PERIOD_CYCLES;
        end else begin
            spi_start_arb    <= 1'b0;
            mirror_spi_start <= 1'b0;

            if (spi_done) begin
                spi_owner <= 1'b0;
            end

            if (spi_start_mux) begin
                normal_spi_pending             <= 1'b1;
                normal_spi_data_pending        <= spi_data_mux;
                normal_spi_half_period_pending <= spi_half_period_cycles_mux;
            end

            if (camera_spi_start) begin
                camera_spi_pending             <= 1'b1;
                camera_spi_data_pending        <= camera_spi_data;
                camera_spi_half_period_pending <= spi_half_period_cycles_mux;
            end

            if (spi_issue_inflight && spi_busy) begin
                spi_issue_inflight <= 1'b0;
            end

            if (!spi_issue_inflight && !spi_busy) begin
                if (camera_spi_pending) begin
                    spi_start_arb              <= 1'b1;
                    spi_target_sel_arb         <= 2'b10;
                    spi_data_arb               <= camera_spi_data_pending;
                    spi_half_period_cycles_arb <= camera_spi_half_period_pending;
                    spi_issue_inflight         <= 1'b1;
                    spi_owner                  <= 1'b1;
                    camera_spi_pending         <= 1'b0;
                end else if (normal_spi_pending) begin
                    spi_start_arb              <= 1'b1;
                    mirror_spi_start           <= 1'b1;
                    spi_target_sel_arb         <= DAC_TARGET_SEL;
                    spi_data_arb               <= normal_spi_data_pending;
                    spi_half_period_cycles_arb <= normal_spi_half_period_pending;
                    spi_issue_inflight         <= 1'b1;
                    spi_owner                  <= 1'b0;
                    normal_spi_pending         <= 1'b0;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= {AXI_DATA_WIDTH{1'b0}};
        end else begin
            if (!s_axi_arready && s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
            end else begin
                s_axi_arready <= 1'b0;
            end

            if (s_axi_arready && s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;

                case (s_axi_araddr)
                    REG_CONTROL: s_axi_rdata <= {25'd0, camera_active, fast_sweep_active, ramp_active, single_step_mode, 1'b0, 1'b0, run_enable};
                    REG_STATUS: begin
                        s_axi_rdata <= {
                            19'd0,
                            camera_active,
                            fast_sweep_busy,
                            ramp_busy,
                            stream_pending_status,
                            capture_wait_for_ack,
                            capture_current_ramp_up,
                            adc_init_done,
                            spi_busy,
                            capture_done,
                            capture_busy,
                            run_enable
                        };
                    end
                    REG_COUNT: s_axi_rdata <= record_counter;
                    REG_LAST0: s_axi_rdata <= last_record_word0;
                    REG_LAST1: s_axi_rdata <= last_record_word1;
                    REG_DEBUG0: begin
                        s_axi_rdata <= {
                            adc_debug_data_bus_in[14:0],
                            adc_debug_data_bus_t,
                            adc_data_valid,
                            adc_busy,
                            capture_adc_start,
                            spi_done,
                            spi_busy,
                            adc_init_done,
                            capture_wait_for_ack,
                            capture_busy,
                            capture_debug_state,
                            adc_debug_state
                        };
                    end
                    REG_DEBUG1: s_axi_rdata <= adc_debug_counter;
                    REG_DEBUG2: s_axi_rdata <= capture_debug_settle_count;
                    REG_DEBUG3: begin
                        s_axi_rdata <= {
                            capture_debug_sample_count,
                            adc_debug_sample_a
                        };
                    end
                    REG_DEBUG4: s_axi_rdata <= adc_valid_counter;
                    REG_DEBUG5: s_axi_rdata <= adc_last_raw_codes;
                    REG_RAMP_TARGET: begin
                        s_axi_rdata <= {16'd0, ramp_target_code};
                    end
                    REG_FAST_SWEEP_CYCLES: begin
                        s_axi_rdata <= fast_sweep_cycles_cfg;
                    end
                    REG_FAST_SWEEP_HOLD: begin
                        s_axi_rdata <= fast_sweep_hold_cycles_cfg;
                    end
                    REG_FAST_SWEEP_SPEED: begin
                        s_axi_rdata <= {16'd0, fwd_spi_half_period_reg};
                    end
                    REG_FWD_PAD_CYCLES: begin
                        s_axi_rdata <= fwd_pad_cycles_reg;
                    end
                    REG_CS2_HIGH_CYCLES: begin
                        s_axi_rdata <= cs2_high_cycles_reg;
                    end
                    REG_CS2_LOW_CYCLES: begin
                        s_axi_rdata <= cs2_low_cycles_reg;
                    end
                    REG_CAPTURE_SCAN_MIN: begin
                        s_axi_rdata <= {16'd0, capture_scan_min_code_reg};
                    end
                    REG_CAPTURE_SCAN_MAX: begin
                        s_axi_rdata <= {16'd0, capture_scan_max_code_reg};
                    end
                    REG_CAPTURE_SETTLE_CYCLES: begin
                        s_axi_rdata <= capture_settle_cycles_reg;
                    end
                    REG_CAPTURE_SAMPLES: begin
                        s_axi_rdata <= {16'd0, capture_samples_per_code_reg};
                    end
                    REG_CAPTURE_STEP_SIZE: begin
                        s_axi_rdata <= {16'd0, capture_step_size_reg};
                    end
                    REG_CAPTURE_HOLD_COUNT: begin
                        s_axi_rdata <= {16'd0, capture_hold_count_reg};
                    end
                    REG_CAPTURE_HOLD_INTERVAL: begin
                        s_axi_rdata <= capture_hold_interval_cycles_reg;
                    end
                    REG_CAMERA_TRIG_THRESHOLD: begin
                        s_axi_rdata <= {16'd0, camera_trig_threshold};
                    end
                    REG_CAMERA_PULSE_COUNT: begin
                        s_axi_rdata <= {camera_pulses_done, camera_pulse_count};
                    end
                    REG_INTR_STATUS: begin
                        s_axi_rdata <= {29'd0, intr_camera_done_latch,
                                        intr_fast_sweep_done_latch,
                                        intr_capture_done_latch};
                    end
                    default:   s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            record_counter    <= 32'd0;
            last_record_word0 <= 32'd0;
            last_record_word1 <= 32'd0;
            adc_valid_counter <= 32'd0;
            adc_last_raw_codes<= 32'd0;
        end else begin
            if (clear_done_req) begin
                record_counter <= 32'd0;
            end

            if (adc_data_valid) begin
                adc_valid_counter  <= adc_valid_counter + 1'b1;
                adc_last_raw_codes <= {adc_code_b[15:0], adc_code_a[15:0]};
            end

            if (mux_record_valid) begin
                record_counter    <= record_counter + 1'b1;
                last_record_word0 <= {15'd0, mux_record_ramp_up[0], mux_record_dac_code};
                last_record_word1 <= mux_record_adc_a_uv;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stream_state    <= STREAM_IDLE;
            stream_last_buf <= 1'b0;
            stream_beat0_buf<= 64'd0;
            stream_beat1_buf<= 64'd0;
            stream_fifo_wr_ptr <= 2'd0;
            stream_fifo_rd_ptr <= 2'd0;
            stream_fifo_count  <= 3'd0;
            stream_fifo_overflow <= 1'b0;
            m_axis_tdata    <= 64'd0;
            m_axis_tkeep    <= 8'd0;
            m_axis_tvalid   <= 1'b0;
            m_axis_tlast    <= 1'b0;
        end else begin
            if (stream_fifo_push) begin
                stream_fifo_beat0[stream_fifo_wr_ptr] <= {
                    mux_record_adc_a_uv,
                    15'd0,
                    mux_record_ramp_up[0],
                    mux_record_dac_code
                };
                stream_fifo_beat1[stream_fifo_wr_ptr] <= {
                    mux_record_hold_index,
                    mux_record_sample_count,
                    mux_record_adc_b_uv
                };
                stream_fifo_last[stream_fifo_wr_ptr] <= mux_record_last;
                stream_fifo_wr_ptr <= stream_fifo_wr_ptr + 1'b1;
            end else if (mux_record_valid) begin
                stream_fifo_overflow <= 1'b1;
            end

            case ({stream_fifo_push, stream_fifo_pop})
                2'b10: stream_fifo_count <= stream_fifo_count + 1'b1;
                2'b01: stream_fifo_count <= stream_fifo_count - 1'b1;
                default: begin
                end
            endcase

            case (stream_state)
                STREAM_IDLE: begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                    m_axis_tkeep  <= 8'h00;
                    if (stream_fifo_count != 3'd0) begin
                        stream_beat0_buf <= stream_fifo_beat0[stream_fifo_rd_ptr];
                        stream_beat1_buf <= stream_fifo_beat1[stream_fifo_rd_ptr];
                        stream_last_buf  <= stream_fifo_last[stream_fifo_rd_ptr];
                        m_axis_tdata  <= stream_fifo_beat0[stream_fifo_rd_ptr];
                        m_axis_tkeep  <= 8'hFF;
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast  <= 1'b0;
                        stream_state  <= STREAM_BEAT0;
                        stream_fifo_rd_ptr <= stream_fifo_rd_ptr + 1'b1;
                    end
                end

                STREAM_BEAT0: begin
                    if (m_axis_tvalid && m_axis_tready) begin
                        m_axis_tdata  <= stream_beat1_buf;
                        m_axis_tkeep  <= 8'hFF;
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast  <= stream_last_buf;
                        stream_state  <= STREAM_BEAT1;
                    end
                end

                STREAM_BEAT1: begin
                    if (m_axis_tvalid && m_axis_tready) begin
                        m_axis_tvalid  <= 1'b0;
                        m_axis_tlast   <= 1'b0;
                        m_axis_tkeep   <= 8'h00;
                        stream_state   <= STREAM_IDLE;
                    end
                end

                default: begin
                    stream_state <= STREAM_IDLE;
                end
            endcase
        end
    end

    capture_manager #(
        .DAC_BITS(DAC_BITS),
        .DEFAULT_SETTLE_CYCLES(DEFAULT_SETTLE_CYCLES),
        .DEFAULT_SAMPLES_PER_CODE(DEFAULT_SAMPLES_PER_CODE),
        .DEFAULT_STEP_SIZE(DEFAULT_STEP_SIZE),
        .DEFAULT_HOLD_SAMPLE_COUNT(1),
        .DEFAULT_HOLD_INTERVAL_CYCLES(0)
    ) u_capture_manager (
        .clk(clk),
        .rst_n(rst_n),
        .enable(capture_run_enable),
        .single_step_mode(single_step_mode),
        .step_ack(step_ack_req),
        .scan_min_code(capture_scan_min_code_reg),
        .scan_max_code(capture_scan_max_code_reg),
        .settle_cycles_cfg(capture_settle_cycles_reg),
        .samples_per_code_cfg(capture_samples_per_code_reg),
        .step_size_cfg(capture_step_size_reg),
        .hold_sample_count_cfg(capture_hold_count_reg),
        .hold_interval_cycles_cfg(capture_hold_interval_cycles_reg),
        .spi_busy(spi_busy),
        .spi_done(spi_done_norm),
        .spi_start(capture_spi_start),
        .spi_data(capture_spi_data),
        .adc_valid(adc_data_valid),
        .adc_a_uv(adc_voltage_a_uv),
        .adc_b_uv(adc_voltage_b_uv),
        .adc_start(capture_adc_start),
        .record_valid(capture_record_valid),
        .record_ramp_up(capture_record_ramp_up),
        .record_dac_code(capture_record_dac_code),
        .record_adc_a_uv(capture_record_adc_a_uv),
        .record_adc_b_uv(capture_record_adc_b_uv),
        .record_hold_index(capture_record_hold_index),
        .record_sample_count(capture_record_sample_count),
        .busy(capture_busy),
        .done(capture_done),
        .wait_for_ack(capture_wait_for_ack),
        .current_ramp_up(capture_current_ramp_up),
        .current_dac_code(capture_current_dac_code),
        .current_hold_index(capture_current_hold_index),
        .debug_state(capture_debug_state),
        .debug_settle_count(capture_debug_settle_count),
        .debug_sample_count(capture_debug_sample_count)
    );

    spi_for_8830 #(
        .DATA_BITS(DAC_BITS),
        .SPI_HALF_PERIOD_CYCLES(SPI_HALF_PERIOD_CYCLES)
    ) u_spi_for_8830 (
        .clk(clk),
        .rst_n(rst_n),
        .start(spi_start_arb),
        .data_in(spi_data_arb),
        .target_sel(spi_target_sel_arb),
        .half_period_cycles(spi_half_period_cycles_arb),
        .busy(spi_busy),
        .done(spi_done),
        .cs1(dac_cs1),
        .cs2(dac_cs2),
        .sclk(dac_sclk),
        .sdi(dac_sdi)
    );

    // Mirror SPI: independent pins, mirrors CS1 sweep data only (ignores CS2 camera)
    spi_for_8830 #(
        .DATA_BITS(DAC_BITS),
        .SPI_HALF_PERIOD_CYCLES(SPI_HALF_PERIOD_CYCLES)
    ) u_spi_mirror (
        .clk(clk),
        .rst_n(rst_n),
        .start(mirror_spi_start),
        .data_in(spi_data_arb),
        .target_sel(2'b01),                 /* always CS1 */
        .half_period_cycles(spi_half_period_cycles_arb),
        .busy(),                             /* unused */
        .done(),                             /* unused */
        .cs1(dac2_cs1),
        .cs2(),                              /* unused */
        .sclk(dac2_sclk),
        .sdi(dac2_sdi)
    );

    dac_square_wave #(
        .DAC_BITS(DAC_BITS)
    ) u_dac_square_wave (
        .clk(clk),
        .rst_n(rst_n),
        .enable(camera_trig_enable && fast_sweep_active),
        .adc_code_a(adc_code_a),
        .threshold(camera_trig_threshold),
        .pulse_count(camera_pulse_count),
        .high_cycles(cs2_high_cycles_reg),
        .low_cycles(cs2_low_cycles_reg),
        .spi_busy(spi_busy),
        .spi_done(spi_done_cam),
        .spi_req(camera_spi_req),
        .spi_start(camera_spi_start),
        .spi_data(camera_spi_data),
        .active(camera_active),
        .pulses_done(camera_pulses_done)
    );

    dac_ramp #(
        .DAC_BITS(DAC_BITS)
    ) u_dac_ramp (
        .clk(clk),
        .rst_n(rst_n),
        .start(ramp_start_req),
        .target_code(ramp_target_code),
        .spi_done(spi_done_norm),
        .spi_start(ramp_spi_start),
        .spi_data(ramp_spi_data),
        .busy(ramp_busy),
        .done(ramp_done)
    );

    fast_sweep #(
        .DAC_BITS(DAC_BITS)
    ) u_fast_sweep (
        .clk(clk),
        .rst_n(rst_n),
        .start(fast_sweep_start_req),
        .target_code(ramp_target_code),
        .sweep_cycles(fast_sweep_cycles_cfg),
        .zero_hold_cycles(fast_sweep_hold_cycles_cfg),
        .fwd_pad_cycles(fwd_pad_cycles_reg),
        .spi_done(spi_done_norm),
        .spi_start(fast_sweep_spi_start),
        .spi_data(fast_sweep_spi_data),
        .adc_valid(adc_data_valid),
        .adc_a_uv(adc_voltage_a_uv),
        .adc_b_uv(adc_voltage_b_uv),
        .adc_start(fast_sweep_adc_start),
        .record_valid(fast_sweep_record_valid),
        .record_last(fast_sweep_record_last),
        .record_ramp_up(fast_sweep_record_ramp_up),
        .record_dac_code(fast_sweep_record_dac_code),
        .record_adc_a_uv(fast_sweep_record_adc_a_uv),
        .record_adc_b_uv(fast_sweep_record_adc_b_uv),
        .rev_mode(fast_sweep_rev_mode),
        .busy(fast_sweep_busy),
        .done(fast_sweep_done)
    );

    ad7616 u_ad7616 (
        .clk(clk),
        .rst_n(rst_n),
        .enable(adc_enable),
        .busy(adc_busy),
        .data_bus_in(adc_data_bus_i),
        .data_bus_out(adc_data_bus_o),
        .data_bus_t(adc_data_bus_t),
        .init_done(adc_init_done),
        .data_valid(adc_data_valid),
        .code_a(adc_code_a),
        .code_b(adc_code_b),
        .voltage_a_uv(adc_voltage_a_uv),
        .voltage_b_uv(adc_voltage_b_uv),
        .debug_state(adc_debug_state),
        .debug_counter(adc_debug_counter),
        .debug_data_bus_in(adc_debug_data_bus_in),
        .debug_data_bus_t(adc_debug_data_bus_t),
        .debug_sample_a(adc_debug_sample_a),
        .convst(adc_convst),
        .cs_n(adc_cs_n),
        .rd_n(adc_rd_n),
        .reset_n_adc(adc_reset_n),
        .chsel(adc_chsel),
        .hw_rngsel(adc_hw_rngsel),
        .burst(adc_burst),
        .ser_par(adc_ser_par)
    );

endmodule
