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
    parameter integer AXI_ADDR_WIDTH           = 8,
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

    // DAC pins — Motor 1 (independent SPI)
    output wire                         dac_m1_cs,
    output wire                         dac_m1_sclk,
    output wire                         dac_m1_sdi,

    // DAC pins — Motor 2 (independent SPI)
    output wire                         dac_m2_cs,
    output wire                         dac_m2_sclk,
    output wire                         dac_m2_sdi,

    // DAC pins — Camera trigger (independent SPI)
    output wire                         dac_cam_cs,
    output wire                         dac_cam_sclk,
    output wire                         dac_cam_sdi,

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

    localparam [AXI_ADDR_WIDTH-1:0] REG_CONTROL               = 8'h00;
    localparam [AXI_ADDR_WIDTH-1:0] REG_STATUS                = 8'h04;
    localparam [AXI_ADDR_WIDTH-1:0] REG_COUNT                 = 8'h08;
    localparam [AXI_ADDR_WIDTH-1:0] REG_LAST0                 = 8'h0C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_LAST1                 = 8'h10;
    localparam [AXI_ADDR_WIDTH-1:0] REG_DEBUG0                = 8'h14;
    localparam [AXI_ADDR_WIDTH-1:0] REG_DEBUG1                = 8'h18;
    localparam [AXI_ADDR_WIDTH-1:0] REG_DEBUG2                = 8'h1C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_DEBUG3                = 8'h20;
    localparam [AXI_ADDR_WIDTH-1:0] REG_DEBUG4                = 8'h24;
    localparam [AXI_ADDR_WIDTH-1:0] REG_DEBUG5                = 8'h28;
    localparam [AXI_ADDR_WIDTH-1:0] REG_RAMP_TARGET           = 8'h2C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_FAST_SWEEP_CYCLES     = 8'h30;
    localparam [AXI_ADDR_WIDTH-1:0] REG_FAST_SWEEP_HOLD       = 8'h34;
    localparam [AXI_ADDR_WIDTH-1:0] REG_FAST_SWEEP_SPEED      = 8'h38;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAMERA_TRIG_THRESHOLD = 8'h3C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAMERA_PULSE_COUNT    = 8'h40;
    localparam [AXI_ADDR_WIDTH-1:0] REG_INTR_STATUS           = 8'h44;
    localparam [AXI_ADDR_WIDTH-1:0] REG_FWD_PAD_CYCLES        = 8'h48;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CS2_HIGH_CYCLES       = 8'h4C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CS2_LOW_CYCLES        = 8'h50;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_SCAN_MIN      = 8'h54;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_SCAN_MAX      = 8'h58;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_SETTLE_CYCLES = 8'h5C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_SAMPLES       = 8'h60;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_STEP_SIZE     = 8'h64;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_HOLD_COUNT    = 8'h68;
    localparam [AXI_ADDR_WIDTH-1:0] REG_CAPTURE_HOLD_INTERVAL = 8'h6C;
    // ── Velocity control registers ──
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_CTRL              = 8'h70;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_KP                = 8'h74;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_KI_DIFF           = 8'h78;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_KI_POS            = 8'h7C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_REF_VEL           = 8'h80;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_REF_POS           = 8'h84;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_DEBUG0            = 8'h88;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_DEBUG1            = 8'h8C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_CTRL_RATE         = 8'h90;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_TARGET_POS        = 8'h94;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_POS_M1            = 8'h98;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_POS_M2            = 8'h9C;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_DAC_TOTAL_M1      = 8'hA0;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_DAC_TOTAL_M2      = 8'hA4;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_DAC_FF_M1         = 8'hA8;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_DAC_FF_M2         = 8'hAC;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_DAC_P_M1          = 8'hB0;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_DAC_P_M2          = 8'hB4;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_POS_ERR_M1        = 8'hB8;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_POS_ERR_M2        = 8'hBC;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_VEL_ERR_M1        = 8'hC0;
    localparam [AXI_ADDR_WIDTH-1:0] REG_VEL_VEL_ERR_M2        = 8'hC4;

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

    // ── Velocity control registers ──
    reg                 vel_ctrl_enable;
    reg                 vel_sense_enable;
    reg                 vel_ctrl_restart_req;
    reg signed [31:0]   vel_kp_reg;
    reg signed [31:0]   vel_ki_diff_reg;
    reg signed [31:0]   vel_ki_pos_reg;
    reg signed [31:0]   vel_ref_vel_reg;
    reg signed [31:0]   vel_ref_pos_reg;
    reg signed [31:0]   vel_target_pos_reg;
    reg [31:0]          vel_ctrl_rate_reg;   // control period in clk cycles

    // ── Control tick generator (4 kHz from 100 MHz) ──
    // 100,000,000 / 4,000 = 25,000 cycles per tick
    reg [31:0] ctrl_timer;
    reg        ctrl_tick;
    localparam [31:0] CTRL_RATE_DEFAULT = 32'd25000;  // 4 kHz

    reg fast_sweep_start_req;
    reg fast_sweep_active;

    reg [31:0] record_counter;
    reg [31:0] last_record_word0;
    reg [31:0] last_record_word1;
    reg [31:0] adc_valid_counter;
    reg [31:0] adc_last_raw_codes;

    // ── Velocity control wires ──
    wire                vel_pos_valid;
    wire signed [31:0]  vel_pos_a_nm, vel_pos_b_nm, vel_pos_c_nm, vel_pos_d_nm;
    wire signed [31:0]  vel_diff_ab_nm, vel_diff_cd_nm;
    wire                vel_td_valid_m1, vel_td_valid_m2;
    wire signed [31:0]  vel_est_m1_nm_s, vel_est_m2_nm_s;
    wire signed [31:0]  vel_pos_est_m1_nm, vel_pos_est_m2_nm;
    wire [15:0]         vel_dac_ff_m1, vel_dac_ff_m2;
    wire                vel_dac_ff_valid;
    wire                vel_ctrl_spi_start_m1, vel_ctrl_spi_start_m2;
    wire [15:0]         vel_ctrl_spi_data_m1, vel_ctrl_spi_data_m2;
    wire signed [31:0]  vel_debug_p_m1, vel_debug_p_m2;
    wire signed [31:0]  vel_debug_i_diff;
    wire signed [31:0]  vel_debug_i_pos_m1, vel_debug_i_pos_m2;
    wire signed [31:0]  vel_debug_dac_total_m1, vel_debug_dac_total_m2;
    wire signed [31:0]  vel_debug_pos_err_m1, vel_debug_pos_err_m2;
    wire signed [31:0]  vel_debug_vel_err_m1, vel_debug_vel_err_m2;
    wire [1:0]          vel_ctrl_state_dbg;

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

    // SPI arbitration: only normal sources compete (camera has its own bus now)
    reg spi_start_arb;
    reg mirror_spi_start;
    reg [1:0] spi_target_sel_arb;
    reg [DAC_BITS-1:0] spi_data_arb;
    reg [15:0] spi_half_period_cycles_arb;
    reg spi_issue_inflight;
    reg normal_spi_pending;
    reg [DAC_BITS-1:0] normal_spi_data_pending;
    reg [15:0] normal_spi_half_period_pending;

    wire spi_busy;
    wire spi_done;
    wire spi_done_norm;
    assign spi_done_norm = spi_done;

    // SPI source mux (M1 bus): fast_sweep > vel_ctrl > dac_ramp > capture_manager
    wire normal_spi_start;
    wire [DAC_BITS-1:0] normal_spi_data;
    wire spi_start_mux;
    wire [DAC_BITS-1:0] spi_data_mux;
    wire [15:0] spi_half_period_cycles_mux;
    assign normal_spi_start = vel_ctrl_enable  ? vel_ctrl_spi_start_m1 :
                              ramp_active      ? ramp_spi_start : capture_spi_start;
    assign normal_spi_data  = vel_ctrl_enable  ? vel_ctrl_spi_data_m1 :
                              ramp_active      ? ramp_spi_data  : capture_spi_data;
    assign spi_start_mux = fast_sweep_active ? fast_sweep_spi_start : normal_spi_start;
    assign spi_data_mux  = fast_sweep_active ? fast_sweep_spi_data  : normal_spi_data;
    assign spi_half_period_cycles_mux = fast_sweep_active ?
        (fast_sweep_rev_mode ? 16'd1 : fwd_spi_half_period_reg) : SPI_HALF_PERIOD_CYCLES;

    // M2 SPI data: independent when vel_ctrl active, else mirrors M1
    wire mirror_spi_start_int;
    wire [DAC_BITS-1:0] mirror_spi_data_int;
    assign mirror_spi_start_int = vel_ctrl_enable ? vel_ctrl_spi_start_m2 : mirror_spi_start;
    assign mirror_spi_data_int  = vel_ctrl_enable ? vel_ctrl_spi_data_m2  : spi_data_arb;

    // CS2 camera SPI: direct connection, no arbitration
    wire camera_spi_start_w;
    wire [DAC_BITS-1:0] camera_spi_data_w;
    wire camera_spi_busy_w;
    wire camera_spi_done_w;

    // ADC enable mux: continuous when velocity control active
    wire adc_enable;
    wire vel_pipeline_enable = vel_ctrl_enable | vel_sense_enable;
    assign adc_enable = vel_pipeline_enable ? 1'b1 :
                        fast_sweep_active ? fast_sweep_adc_start : capture_adc_start;

    // When ramp or fast_sweep or vel_ctrl is active, disable capture_manager
    wire capture_run_enable = run_enable && !ramp_active && !fast_sweep_active && !vel_pipeline_enable;

    // Record source mux
    wire mux_record_valid;
    wire mux_record_last;
    wire [DAC_BITS-1:0] mux_record_dac_code;
    wire [15:0] mux_record_ramp_up;
    wire signed [31:0] mux_record_adc_a_uv;
    wire signed [31:0] mux_record_adc_b_uv;
    wire [15:0] mux_record_hold_index;
    wire [15:0] mux_record_sample_count;
    assign mux_record_valid    = vel_ctrl_enable ? vel_pos_valid :
                                 fast_sweep_active ? fast_sweep_record_valid : capture_record_valid;
    assign mux_record_last     = fast_sweep_active ? fast_sweep_record_last : 1'b1;
    assign mux_record_dac_code = fast_sweep_active ? fast_sweep_record_dac_code : capture_record_dac_code;
    assign mux_record_ramp_up  = vel_ctrl_enable ? {15'd0, 1'b1} :
                                 fast_sweep_active ? {15'd0, fast_sweep_record_ramp_up} : {15'd0, capture_record_ramp_up};
    assign mux_record_adc_a_uv = vel_ctrl_enable ? vel_pos_a_nm[31:0] :
                                 fast_sweep_active ? fast_sweep_record_adc_a_uv : capture_record_adc_a_uv;
    assign mux_record_adc_b_uv = vel_ctrl_enable ? vel_pos_b_nm[31:0] :
                                 fast_sweep_active ? fast_sweep_record_adc_b_uv : capture_record_adc_b_uv;
    assign mux_record_hold_index = fast_sweep_active ? 16'd0 : capture_record_hold_index;
    assign mux_record_sample_count = vel_ctrl_enable ? 16'd1 :
                                     fast_sweep_active ? 16'd1 : capture_record_sample_count;

    wire adc_init_done;
    wire adc_data_valid;
    wire signed [15:0] adc_code_a;
    wire signed [15:0] adc_code_b;
    wire signed [15:0] adc_code_c;
    wire signed [15:0] adc_code_d;
    wire signed [31:0] adc_voltage_a_uv;
    wire signed [31:0] adc_voltage_b_uv;
    wire signed [31:0] adc_voltage_c_uv;
    wire signed [31:0] adc_voltage_d_uv;
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
    always @(posedge clk) begin
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
            vel_ctrl_enable   <= 1'b0;
            vel_sense_enable  <= 1'b0;
            vel_ctrl_restart_req <= 1'b0;
            vel_kp_reg        <= 32'sd3932160;    // Kp=60.0 * 2^16 (for 4kHz+notch)
            vel_ki_diff_reg   <= 32'sd524288000;  // Ki_diff=8000.0 * 2^16
            vel_ki_pos_reg    <= 32'sd6554;       // position align Kp ~= 0.1 DAC/nm
            vel_ref_vel_reg   <= 32'sd8000000;    // 8 mm/s
            vel_ref_pos_reg   <= 32'sd2000;       // 2 um alignment target
            vel_target_pos_reg<= 32'sd0;          // 0 disables auto-return target
            vel_ctrl_rate_reg <= CTRL_RATE_DEFAULT;
        end else begin
            clear_done_req <= 1'b0;
            step_ack_req         <= 1'b0;
            ramp_start_req       <= 1'b0;
            fast_sweep_start_req <= 1'b0;
            vel_ctrl_restart_req <= 1'b0;

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
                    REG_VEL_CTRL: begin
                        if (s_axi_wstrb[0]) begin
                            vel_ctrl_restart_req <= s_axi_wdata[3];
                            vel_sense_enable <= s_axi_wdata[4];
                            if (s_axi_wdata[3]) begin
                                if (s_axi_wdata[0]) vel_ctrl_enable <= 1'b1;
                            end else begin
                                vel_ctrl_enable <= s_axi_wdata[0];
                            end
                        end
                    end
                    REG_VEL_KP: begin
                        if (&s_axi_wstrb) vel_kp_reg <= s_axi_wdata;
                    end
                    REG_VEL_KI_DIFF: begin
                        if (&s_axi_wstrb) vel_ki_diff_reg <= s_axi_wdata;
                    end
                    REG_VEL_KI_POS: begin
                        if (&s_axi_wstrb) vel_ki_pos_reg <= s_axi_wdata;
                    end
                    REG_VEL_REF_VEL: begin
                        if (&s_axi_wstrb) vel_ref_vel_reg <= s_axi_wdata;
                    end
                    REG_VEL_REF_POS: begin
                        if (&s_axi_wstrb) vel_ref_pos_reg <= s_axi_wdata;
                    end
                    REG_VEL_CTRL_RATE: begin
                        if (&s_axi_wstrb) vel_ctrl_rate_reg <= s_axi_wdata;
                    end
                    REG_VEL_TARGET_POS: begin
                        if (&s_axi_wstrb) vel_target_pos_reg <= s_axi_wdata;
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

    // ── Control tick generator ────────────────────────────────────
    // Generates a pulse at the configured control rate (default 4 kHz)
    always @(posedge clk) begin
        if (!rst_n) begin
            ctrl_timer <= 32'd0;
            ctrl_tick  <= 1'b0;
        end else begin
            ctrl_tick <= 1'b0;
            if (vel_pipeline_enable) begin
                if (ctrl_timer >= ((vel_ctrl_rate_reg == 32'd0) ? CTRL_RATE_DEFAULT : vel_ctrl_rate_reg) - 1'b1) begin
                    ctrl_timer <= 32'd0;
                    ctrl_tick  <= 1'b1;
                end else begin
                    ctrl_timer <= ctrl_timer + 1'b1;
                end
            end else begin
                ctrl_timer <= 32'd0;
            end
        end
    end

    // Simplified SPI arbitration (camera has its own bus now)
    always @(posedge clk) begin
        if (!rst_n) begin
            spi_start_arb              <= 1'b0;
            mirror_spi_start           <= 1'b0;
            spi_target_sel_arb         <= 2'b00;
            spi_data_arb               <= {DAC_BITS{1'b0}};
            spi_half_period_cycles_arb <= SPI_HALF_PERIOD_CYCLES;
            spi_issue_inflight         <= 1'b0;
            normal_spi_pending         <= 1'b0;
            normal_spi_data_pending    <= {DAC_BITS{1'b0}};
            normal_spi_half_period_pending <= SPI_HALF_PERIOD_CYCLES;
        end else begin
            spi_start_arb    <= 1'b0;
            mirror_spi_start <= 1'b0;

            if (spi_start_mux) begin
                normal_spi_pending             <= 1'b1;
                normal_spi_data_pending        <= spi_data_mux;
                normal_spi_half_period_pending <= spi_half_period_cycles_mux;
            end

            if (spi_issue_inflight && spi_busy) begin
                spi_issue_inflight <= 1'b0;
            end

            if (!spi_issue_inflight && !spi_busy) begin
                if (normal_spi_pending) begin
                    spi_start_arb              <= 1'b1;
                    mirror_spi_start           <= 1'b1;
                    spi_target_sel_arb         <= DAC_TARGET_SEL;
                    spi_data_arb               <= normal_spi_data_pending;
                    spi_half_period_cycles_arb <= normal_spi_half_period_pending;
                    spi_issue_inflight         <= 1'b1;
                    normal_spi_pending         <= 1'b0;
                end
            end
        end
    end

    always @(posedge clk) begin
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
                    REG_VEL_CTRL:    s_axi_rdata <= {27'd0, vel_sense_enable, 1'b0,
                                                      vel_ctrl_state_dbg, vel_ctrl_enable};
                    REG_VEL_KP:      s_axi_rdata <= vel_kp_reg;
                    REG_VEL_KI_DIFF: s_axi_rdata <= vel_ki_diff_reg;
                    REG_VEL_KI_POS:  s_axi_rdata <= vel_ki_pos_reg;
                    REG_VEL_REF_VEL: s_axi_rdata <= vel_ref_vel_reg;
                    REG_VEL_REF_POS: s_axi_rdata <= vel_ref_pos_reg;
                    REG_VEL_DEBUG0:  s_axi_rdata <= vel_est_m1_nm_s;
                    REG_VEL_DEBUG1:  s_axi_rdata <= vel_diff_ab_nm;
                    REG_VEL_CTRL_RATE: s_axi_rdata <= vel_ctrl_rate_reg;
                    REG_VEL_TARGET_POS: s_axi_rdata <= vel_target_pos_reg;
                    REG_VEL_POS_M1:  s_axi_rdata <= vel_pos_est_m1_nm;
                    REG_VEL_POS_M2:  s_axi_rdata <= vel_pos_est_m2_nm;
                    REG_VEL_DAC_TOTAL_M1: s_axi_rdata <= vel_debug_dac_total_m1;
                    REG_VEL_DAC_TOTAL_M2: s_axi_rdata <= vel_debug_dac_total_m2;
                    REG_VEL_DAC_FF_M1: s_axi_rdata <= {16'd0, vel_dac_ff_m1};
                    REG_VEL_DAC_FF_M2: s_axi_rdata <= {16'd0, vel_dac_ff_m2};
                    REG_VEL_DAC_P_M1: s_axi_rdata <= vel_debug_p_m1;
                    REG_VEL_DAC_P_M2: s_axi_rdata <= vel_debug_p_m2;
                    REG_VEL_POS_ERR_M1: s_axi_rdata <= vel_debug_pos_err_m1;
                    REG_VEL_POS_ERR_M2: s_axi_rdata <= vel_debug_pos_err_m2;
                    REG_VEL_VEL_ERR_M1: s_axi_rdata <= vel_debug_vel_err_m1;
                    REG_VEL_VEL_ERR_M2: s_axi_rdata <= vel_debug_vel_err_m2;
                    default:   s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
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

    always @(posedge clk) begin
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

    // ── M1 SPI (CS1 only) ─────────────────────────────────────────
    spi_for_8830 #(
        .DATA_BITS(DAC_BITS),
        .SPI_HALF_PERIOD_CYCLES(SPI_HALF_PERIOD_CYCLES)
    ) u_spi_m1 (
        .clk(clk),
        .rst_n(rst_n),
        .start(spi_start_arb),
        .data_in(spi_data_arb),
        .target_sel(spi_target_sel_arb),
        .half_period_cycles(spi_half_period_cycles_arb),
        .busy(spi_busy),
        .done(spi_done),
        .cs1(dac_m1_cs),
        .cs2(),
        .sclk(dac_m1_sclk),
        .sdi(dac_m1_sdi)
    );

    // ── M2 SPI (independent data for Motor 2) ─────────────────────
    spi_for_8830 #(
        .DATA_BITS(DAC_BITS),
        .SPI_HALF_PERIOD_CYCLES(SPI_HALF_PERIOD_CYCLES)
    ) u_spi_m2 (
        .clk(clk),
        .rst_n(rst_n),
        .start(mirror_spi_start_int),
        .data_in(mirror_spi_data_int),
        .target_sel(2'b01),
        .half_period_cycles(spi_half_period_cycles_arb),
        .busy(),
        .done(),
        .cs1(dac_m2_cs),
        .cs2(),
        .sclk(dac_m2_sclk),
        .sdi(dac_m2_sdi)
    );

    // ── Camera SPI (dedicated bus, independent pins) ──────────────
    spi_for_8830 #(
        .DATA_BITS(DAC_BITS),
        .SPI_HALF_PERIOD_CYCLES(SPI_HALF_PERIOD_CYCLES)
    ) u_spi_cam (
        .clk(clk),
        .rst_n(rst_n),
        .start(camera_spi_start_w),
        .data_in(camera_spi_data_w),
        .target_sel(2'b01),
        .half_period_cycles(SPI_HALF_PERIOD_CYCLES),
        .busy(camera_spi_busy_w),
        .done(camera_spi_done_w),
        .cs1(dac_cam_cs),
        .cs2(),
        .sclk(dac_cam_sclk),
        .sdi(dac_cam_sdi)
    );

    // ── Camera trigger (direct to CS2 SPI, no arbitration) ────────
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
        .spi_busy(camera_spi_busy_w),
        .spi_done(camera_spi_done_w),
        .spi_req(),                         // unused — dedicated bus, no preemption needed
        .spi_start(camera_spi_start_w),
        .spi_data(camera_spi_data_w),
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

    ad7616 #(
        .FIXED_CHANNEL(7)
    ) u_ad7616 (
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
        .code_c(adc_code_c),
        .code_d(adc_code_d),
        .voltage_a_uv(adc_voltage_a_uv),
        .voltage_b_uv(adc_voltage_b_uv),
        .voltage_c_uv(adc_voltage_c_uv),
        .voltage_d_uv(adc_voltage_d_uv),
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

    // ── Velocity Control Pipeline ─────────────────────────────────

    // Stage 1: uV → nm calibration + differential
    sensor_uv_to_position_nm u_calib (
        .clk          (clk),
        .rst_n        (rst_n),
        .valid_in     (adc_data_valid),
        .sensor_a_uv  (adc_voltage_a_uv),
        .sensor_b_uv  (adc_voltage_b_uv),
        .sensor_c_uv  (adc_voltage_c_uv),
        .sensor_d_uv  (adc_voltage_d_uv),
        .pos_a_nm     (vel_pos_a_nm),
        .pos_b_nm     (vel_pos_b_nm),
        .pos_c_nm     (vel_pos_c_nm),
        .pos_d_nm     (vel_pos_d_nm),
        .diff_ab_nm   (vel_diff_ab_nm),
        .diff_cd_nm   (vel_diff_cd_nm),
        .valid_out    (vel_pos_valid)
    );

    // Stage 2: Tracking Differentiator (Motor 1) — 4 kHz, r0=400
    tracking_differentiator #(
        .TD_B0( 76087), .TD_B2(-76087),
        .TD_C1( 30358771), .TD_C2(-13733730),
        .TS_NS(250000)
    ) u_td_m1 (
        .clk(clk), .rst_n(rst_n),
        .valid_in(ctrl_tick),
        .pos_in_nm(vel_pos_a_nm),
        .pos_est_nm(vel_pos_est_m1_nm),
        .vel_est_nm_s(vel_est_m1_nm_s),
        .valid_out(vel_td_valid_m1)
    );

    // Stage 2: Tracking Differentiator (Motor 2) — 4 kHz, r0=400
    tracking_differentiator #(
        .TD_B0( 76087), .TD_B2(-76087),
        .TD_C1( 30358771), .TD_C2(-13733730),
        .TS_NS(250000)
    ) u_td_m2 (
        .clk(clk), .rst_n(rst_n),
        .valid_in(ctrl_tick),
        .pos_in_nm(vel_pos_b_nm),
        .pos_est_nm(vel_pos_est_m2_nm),
        .vel_est_nm_s(vel_est_m2_nm_s),
        .valid_out(vel_td_valid_m2)
    );

    // Stage 3: 79 Hz notch on velocity (suppress PZT mechanical resonance)
    wire                vel_notch_valid_m1, vel_notch_valid_m2;
    wire signed [31:0]  vel_notch_m1_nm_s, vel_notch_m2_nm_s;

    iir_notch #(
        .N_B0(16777216), .N_B1(-33295103), .N_B2(16777216),
        .N_A1(-33216654), .N_A2(16698248)
    ) u_notch_m1 (
        .clk(clk), .rst_n(rst_n),
        .valid_in(vel_td_valid_m1),
        .data_in(vel_est_m1_nm_s),
        .data_out(vel_notch_m1_nm_s),
        .valid_out(vel_notch_valid_m1)
    );

    iir_notch #(
        .N_B0(16777216), .N_B1(-33295103), .N_B2(16777216),
        .N_A1(-33216654), .N_A2(16698248)
    ) u_notch_m2 (
        .clk(clk), .rst_n(rst_n),
        .valid_in(vel_td_valid_m2),
        .data_in(vel_est_m2_nm_s),
        .data_out(vel_notch_m2_nm_s),
        .valid_out(vel_notch_valid_m2)
    );

    // Stage 4: Feedforward LUT (BRAM)
    // ALIGN/RETURN use position error direction; RUN uses velocity sign.
    wire vel_align_or_return = (vel_ctrl_state_dbg == 2'd1) || (vel_ctrl_state_dbg == 2'd3);
    wire branch_m1 = vel_align_or_return ? (vel_ref_pos_reg >= vel_pos_est_m1_nm) :
                                           (vel_notch_m1_nm_s >= 0);
    wire branch_m2 = vel_align_or_return ? (vel_ref_pos_reg >= vel_pos_est_m2_nm) :
                                           (vel_notch_m2_nm_s >= 0);
    wire signed [31:0] ff_pos_m1_nm = vel_align_or_return ? vel_ref_pos_reg :
                                                            vel_pos_est_m1_nm;
    wire signed [31:0] ff_pos_m2_nm = vel_align_or_return ? vel_ref_pos_reg :
                                                            vel_pos_est_m2_nm;

    pzt_ff_lut u_ff_lut (
        .clk(clk), .rst_n(rst_n),
        .valid_in(vel_notch_valid_m2),
        .pos_m1_nm(ff_pos_m1_nm),
        .branch_m1(branch_m1),
        .dac_ff_m1(vel_dac_ff_m1),
        .dac_ff_m1_valid(vel_dac_ff_valid),
        .pos_m2_nm(ff_pos_m2_nm),
        .branch_m2(branch_m2),
        .dac_ff_m2(vel_dac_ff_m2),
        .dac_ff_m2_valid()
    );

    // Stage 5: Velocity Controller (P + I)
    pzt_velocity_controller u_vel_ctrl (
        .clk(clk), .rst_n(rst_n),
        .enable(vel_ctrl_enable),
        .restart(vel_ctrl_restart_req),
        .valid_in(vel_dac_ff_valid),
        .cfg_kp_vel(vel_kp_reg),
        .cfg_ki_diff(vel_ki_diff_reg),
        .cfg_ki_pos(vel_ki_pos_reg),
        .vel_m1_nm_s(vel_notch_m1_nm_s),
        .vel_m2_nm_s(vel_notch_m2_nm_s),
        .pos_m1_nm(vel_pos_est_m1_nm),
        .pos_m2_nm(vel_pos_est_m2_nm),
        .diff_ab_nm(vel_diff_ab_nm),
        .dac_ff_m1(vel_dac_ff_m1),
        .dac_ff_m2(vel_dac_ff_m2),
        .dac_ff_valid(vel_dac_ff_valid),
        .v_ref_ext(vel_ref_vel_reg),
        .pos_ref_ext(vel_ref_pos_reg),
        .target_pos_ext(vel_target_pos_reg),
        .use_ext_ref(vel_ref_pos_reg != 0),
        .spi_start_m1(vel_ctrl_spi_start_m1),
        .spi_data_m1(vel_ctrl_spi_data_m1),
        .spi_start_m2(vel_ctrl_spi_start_m2),
        .spi_data_m2(vel_ctrl_spi_data_m2),
        .spi_busy(spi_busy),
        .spi_done(spi_done_norm),
        .debug_dac_p_m1(vel_debug_p_m1),
        .debug_dac_p_m2(vel_debug_p_m2),
        .debug_dac_i_diff(vel_debug_i_diff),
        .debug_dac_i_pos_m1(vel_debug_i_pos_m1),
        .debug_dac_i_pos_m2(vel_debug_i_pos_m2),
        .debug_dac_total_m1(vel_debug_dac_total_m1),
        .debug_dac_total_m2(vel_debug_dac_total_m2),
        .debug_pos_err_m1(vel_debug_pos_err_m1),
        .debug_pos_err_m2(vel_debug_pos_err_m2),
        .debug_vel_err_m1(vel_debug_vel_err_m1),
        .debug_vel_err_m2(vel_debug_vel_err_m2),
        .debug_state(vel_ctrl_state_dbg)
    );

endmodule
