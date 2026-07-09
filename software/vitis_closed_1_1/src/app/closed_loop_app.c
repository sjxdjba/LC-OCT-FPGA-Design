#include "app/closed_loop_app.h"

#include <ctype.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "hal/platform_hal.h"
#include "xil_printf.h"

#define APP_UART_LINE_BYTES 256U
#define APP_FABRIC_CLOCK_HZ 100000000U

#define SAFE_KP_Q16              65536
#define SAFE_KI_DIFF_Q16         0
#define SAFE_KI_POS_Q16          10
#define SAFE_VELOCITY_NM_S       500000
#define SAFE_STANDBY_POS_NM      2000
#define SAFE_TARGET_POS_NM       20000
#define SAFE_CTRL_RATE_CYCLES    25000U

static int parse_s32(const char *text, int32_t *value);
static int parse_u32(const char *text, uint32_t *value);
static void trim_line(char *text);
static void strip_literal_newline_suffix(char *text);
static void fold_repeated_simple_command(char **cmd);
static void print_help(void);
static void print_config(const closed_loop_config_t *config);
static void print_status(const closed_loop_app_t *app, int verbose);
static void print_direction_hint(const closed_loop_status_t *status);
static void load_safe_config(closed_loop_config_t *config);
static int apply_key_value(closed_loop_config_t *config,
                           const char *key,
                           const char *value);
static int apply_pairs(closed_loop_config_t *config,
                       char *save_ptr,
                       int *changed);
static void handle_sense_command(closed_loop_app_t *app, char *save_ptr);
static void handle_command(closed_loop_app_t *app, char *line);

static int parse_s32(const char *text, int32_t *value)
{
    char *end = NULL;
    long parsed = 0L;

    if ((text == NULL) || (value == NULL)) {
        return -1;
    }

    parsed = strtol(text, &end, 0);
    if ((end == text) || (*end != '\0')) {
        return -1;
    }

    *value = (int32_t)parsed;
    return 0;
}

static int parse_u32(const char *text, uint32_t *value)
{
    char *end = NULL;
    unsigned long parsed = 0UL;

    if ((text == NULL) || (value == NULL)) {
        return -1;
    }

    parsed = strtoul(text, &end, 0);
    if ((end == text) || (*end != '\0')) {
        return -1;
    }

    *value = (uint32_t)parsed;
    return 0;
}

static void trim_line(char *text)
{
    size_t length = 0U;

    if (text == NULL) {
        return;
    }

    while (isspace((unsigned char)*text)) {
        memmove(text, text + 1, strlen(text));
    }

    length = strlen(text);
    while ((length > 0U) && isspace((unsigned char)text[length - 1U])) {
        text[length - 1U] = '\0';
        --length;
    }
}

static void strip_literal_newline_suffix(char *text)
{
    size_t length = 0U;

    if (text == NULL) {
        return;
    }

    length = strlen(text);
    if (length >= 2U) {
        if (((text[length - 2U] == '\\') || (text[length - 2U] == '/')) &&
            ((text[length - 1U] == 'n') || (text[length - 1U] == 'r'))) {
            text[length - 2U] = '\0';
        }
    }
}

static void fold_repeated_simple_command(char **cmd)
{
    static const char *const simple_cmds[] = {
        "status",
        "diag",
        "safe",
        "stop",
        "help",
        "show",
        "config",
        NULL
    };
    int i = 0;

    if ((cmd == NULL) || (*cmd == NULL)) {
        return;
    }

    for (i = 0; simple_cmds[i] != NULL; ++i) {
        const char *simple = simple_cmds[i];
        const size_t simple_len = strlen(simple);
        const size_t cmd_len = strlen(*cmd);

        if ((cmd_len == (simple_len * 2U)) &&
            (strncmp(*cmd, simple, simple_len) == 0) &&
            (strcmp(*cmd + simple_len, simple) == 0)) {
            (*cmd)[simple_len] = '\0';
            return;
        }
    }
}

static void print_help(void)
{
    xil_printf("commands:\r\n");
    xil_printf("  help\r\n");
    xil_printf("  show | config\r\n");
    xil_printf("  status          compact state + position\r\n");
    xil_printf("  diag            full debug registers\r\n");
    xil_printf("  sense on        ADC/position monitor only, no DAC output\r\n");
    xil_printf("  sense off\r\n");
    xil_printf("  safe            low-gain safe config, controller stopped\r\n");
    xil_printf("  hold [standby <nm>] [ki_pos <q16>] [kp <q16>]\r\n");
    xil_printf("  set [standby <nm>] [target <nm>] [vel <nm/s>] [rate <cycles>] [kp <q16>] [ki_diff <q16>] [ki_pos <q16>]\r\n");
    xil_printf("  start [same key/value args]\r\n");
    xil_printf("  restart [same key/value args]\r\n");
    xil_printf("  stop\r\n");
    xil_printf("examples:\r\n");
    xil_printf("  sense on\r\n");
    xil_printf("  diag\r\n");
    xil_printf("  sense off\r\n");
    xil_printf("  safe\r\n");
    xil_printf("  hold standby 200000 ki_pos 10\r\n");
}

static void print_config(const closed_loop_config_t *config)
{
    uint32_t rate_hz = 0U;

    if (config == NULL) {
        return;
    }

    rate_hz = (config->ctrl_rate_cycles == 0U) ?
        (APP_FABRIC_CLOCK_HZ / SAFE_CTRL_RATE_CYCLES) :
        (APP_FABRIC_CLOCK_HZ / config->ctrl_rate_cycles);

    xil_printf("config:\r\n");
    xil_printf("  standby=%d nm target=%d nm vel=%d nm/s\r\n",
               (int)config->standby_pos_nm,
               (int)config->target_pos_nm,
               (int)config->ref_velocity_nm_s);
    xil_printf("  rate=%u cycles (%u Hz @100MHz)\r\n",
               (unsigned int)config->ctrl_rate_cycles,
               (unsigned int)rate_hz);
    xil_printf("  kp=%d ki_diff=%d ki_pos=%d (Q16)\r\n",
               (int)config->kp_q16,
               (int)config->ki_diff_q16,
               (int)config->ki_pos_q16);
}

static void print_direction_hint(const closed_loop_status_t *status)
{
    if (status == NULL) {
        return;
    }

    if (status->enabled == 0U) {
        return;
    }

    if ((status->state == CLOSED_CTRL_STATE_ALIGN) ||
        (status->state == CLOSED_CTRL_STATE_RETURN)) {
        if ((status->pos_err_m1 > 0) && (status->dac_total_m1 < (int32_t)status->dac_ff_m1)) {
            xil_printf("WARN: M1 pos_err>0 but total_dac<ff_dac, check M1 sign/path.\r\n");
        }
        if ((status->pos_err_m1 < 0) && (status->dac_total_m1 > (int32_t)status->dac_ff_m1)) {
            xil_printf("WARN: M1 pos_err<0 but total_dac>ff_dac, check M1 sign/path.\r\n");
        }
        if ((status->pos_err_m2 > 0) && (status->dac_total_m2 < (int32_t)status->dac_ff_m2)) {
            xil_printf("WARN: M2 pos_err>0 but total_dac<ff_dac, check M2 sign/path.\r\n");
        }
        if ((status->pos_err_m2 < 0) && (status->dac_total_m2 > (int32_t)status->dac_ff_m2)) {
            xil_printf("WARN: M2 pos_err<0 but total_dac>ff_dac, check M2 sign/path.\r\n");
        }
    }
}

static void print_status(const closed_loop_app_t *app, int verbose)
{
    closed_loop_status_t status = {0};
    closed_loop_config_t hw_config = {0};

    if (app == NULL) {
        return;
    }

    closed_loop_ctrl_read_status(&app->ctrl, &status);
    closed_loop_ctrl_read_config(&app->ctrl, &hw_config);

    xil_printf("status: enable=%u sense=%u state=%s raw=0x%08x records=%u\r\n",
               (unsigned int)(status.enabled != 0U),
               (unsigned int)(status.sense_enabled != 0U),
               closed_loop_ctrl_state_name(status.state),
               (unsigned int)status.raw_ctrl,
               (unsigned int)status.record_count);
    xil_printf("  pos_m1=%d nm pos_m2=%d nm diff_ab=%d nm vel_m1=%d nm/s\r\n",
               (int)status.pos_m1_nm,
               (int)status.pos_m2_nm,
               (int)status.diff_ab_nm,
               (int)status.vel_m1_nm_s);
    xil_printf("  err_pos: m1=%d nm m2=%d nm, err_vel: m1=%d m2=%d nm/s\r\n",
               (int)status.pos_err_m1,
               (int)status.pos_err_m2,
               (int)status.vel_err_m1,
               (int)status.vel_err_m2);
    xil_printf("  dac: ff_m1=%u ff_m2=%u total_m1=%d total_m2=%d\r\n",
               (unsigned int)status.dac_ff_m1,
               (unsigned int)status.dac_ff_m2,
               (int)status.dac_total_m1,
               (int)status.dac_total_m2);

    if (verbose != 0) {
        xil_printf("  dac_p_vel: m1=%d m2=%d\r\n",
                   (int)status.dac_p_m1,
                   (int)status.dac_p_m2);
        xil_printf("  hw_status=0x%08x dbg0=0x%08x dbg1=%u adc_valid=%u adc_raw=0x%08x\r\n",
                   (unsigned int)status.status,
                   (unsigned int)status.debug0,
                   (unsigned int)status.debug1,
                   (unsigned int)status.adc_valid_count,
                   (unsigned int)status.adc_raw_codes);
        xil_printf("  last0=0x%08x last1=0x%08x\r\n",
                   (unsigned int)status.last0,
                   (unsigned int)status.last1);
        if (status.sense_enabled != 0U) {
            xil_printf("NOTE: sense mode only monitors ADC/position; DAC outputs are not driven by closed loop.\r\n");
        }
        print_direction_hint(&status);
    }

    print_config(&hw_config);
}

static void load_safe_config(closed_loop_config_t *config)
{
    if (config == NULL) {
        return;
    }

    config->kp_q16 = SAFE_KP_Q16;
    config->ki_diff_q16 = SAFE_KI_DIFF_Q16;
    config->ki_pos_q16 = SAFE_KI_POS_Q16;
    config->ref_velocity_nm_s = SAFE_VELOCITY_NM_S;
    config->standby_pos_nm = SAFE_STANDBY_POS_NM;
    config->target_pos_nm = SAFE_TARGET_POS_NM;
    config->ctrl_rate_cycles = SAFE_CTRL_RATE_CYCLES;
}

static int apply_key_value(closed_loop_config_t *config,
                           const char *key,
                           const char *value)
{
    int32_t s32_value = 0;
    uint32_t u32_value = 0U;

    if ((config == NULL) || (key == NULL) || (value == NULL)) {
        return -1;
    }

    if ((strcmp(key, "standby") == 0) || (strcmp(key, "pos") == 0)) {
        if (parse_s32(value, &s32_value) != 0) return -1;
        config->standby_pos_nm = s32_value;
    } else if (strcmp(key, "target") == 0) {
        if (parse_s32(value, &s32_value) != 0) return -1;
        config->target_pos_nm = s32_value;
    } else if ((strcmp(key, "vel") == 0) || (strcmp(key, "velocity") == 0)) {
        if (parse_s32(value, &s32_value) != 0) return -1;
        config->ref_velocity_nm_s = s32_value;
    } else if (strcmp(key, "rate") == 0) {
        if (parse_u32(value, &u32_value) != 0) return -1;
        config->ctrl_rate_cycles = u32_value;
    } else if (strcmp(key, "kp") == 0) {
        if (parse_s32(value, &s32_value) != 0) return -1;
        config->kp_q16 = s32_value;
    } else if (strcmp(key, "ki_diff") == 0) {
        if (parse_s32(value, &s32_value) != 0) return -1;
        config->ki_diff_q16 = s32_value;
    } else if (strcmp(key, "ki_pos") == 0) {
        if (parse_s32(value, &s32_value) != 0) return -1;
        config->ki_pos_q16 = s32_value;
    } else {
        xil_printf("ERR: unknown key '%s'\r\n", key);
        return -2;
    }

    return 0;
}

static int apply_pairs(closed_loop_config_t *config,
                       char *save_ptr,
                       int *changed)
{
    char *key = NULL;

    if ((config == NULL) || (changed == NULL)) {
        return -1;
    }

    *changed = 0;
    while ((key = strtok_r(NULL, " \t", &save_ptr)) != NULL) {
        char *value = strtok_r(NULL, " \t", &save_ptr);

        if (value == NULL) {
            xil_printf("ERR: missing value for '%s'\r\n", key);
            return -1;
        }

        strip_literal_newline_suffix(value);
        if (apply_key_value(config, key, value) != 0) {
            xil_printf("ERR: invalid value '%s' for '%s'\r\n", value, key);
            return -1;
        }

        *changed = 1;
    }

    return 0;
}

static void handle_sense_command(closed_loop_app_t *app, char *save_ptr)
{
    char *arg = NULL;

    if (app == NULL) {
        return;
    }

    arg = strtok_r(NULL, " \t", &save_ptr);
    if (arg == NULL) {
        xil_printf("ERR: use 'sense on' or 'sense off'\r\n");
        return;
    }

    strip_literal_newline_suffix(arg);
    if (strcmp(arg, "on") == 0) {
        closed_loop_ctrl_sense_on(&app->ctrl);
        xil_printf("sense on: ADC/position monitor enabled, closed-loop DAC disabled\r\n");
        print_status(app, 1);
    } else if (strcmp(arg, "off") == 0) {
        closed_loop_ctrl_sense_off(&app->ctrl);
        xil_printf("sense off\r\n");
        print_status(app, 1);
    } else {
        xil_printf("ERR: use 'sense on' or 'sense off'\r\n");
    }
}

static void handle_command(closed_loop_app_t *app, char *line)
{
    char *save_ptr = NULL;
    char *cmd = NULL;
    int changed = 0;

    if ((app == NULL) || (line == NULL)) {
        return;
    }

    trim_line(line);
    if (line[0] == '\0') {
        return;
    }

    cmd = strtok_r(line, " \t", &save_ptr);
    if (cmd == NULL) {
        return;
    }
    fold_repeated_simple_command(&cmd);

    if ((strcmp(cmd, "help") == 0) || (strcmp(cmd, "?") == 0)) {
        print_help();
    } else if ((strcmp(cmd, "show") == 0) || (strcmp(cmd, "config") == 0)) {
        closed_loop_ctrl_read_config(&app->ctrl, &app->config);
        print_config(&app->config);
    } else if (strcmp(cmd, "status") == 0) {
        print_status(app, 0);
    } else if (strcmp(cmd, "diag") == 0) {
        print_status(app, 1);
    } else if (strcmp(cmd, "sense") == 0) {
        handle_sense_command(app, save_ptr);
    } else if (strcmp(cmd, "safe") == 0) {
        load_safe_config(&app->config);
        closed_loop_ctrl_stop(&app->ctrl);
        closed_loop_ctrl_apply_config(&app->ctrl, &app->config);
        xil_printf("safe config applied, controller stopped\r\n");
        print_config(&app->config);
    } else if (strcmp(cmd, "hold") == 0) {
        if (apply_pairs(&app->config, save_ptr, &changed) == 0) {
            app->config.target_pos_nm = 0;
            app->config.ref_velocity_nm_s = 0;
            closed_loop_ctrl_apply_config(&app->ctrl, &app->config);
            closed_loop_ctrl_start(&app->ctrl);
            xil_printf("hold start: target=0 vel=0, position-align only\r\n");
            print_status(app, 1);
        }
    } else if (strcmp(cmd, "set") == 0) {
        if (apply_pairs(&app->config, save_ptr, &changed) == 0) {
            closed_loop_ctrl_apply_config(&app->ctrl, &app->config);
            xil_printf("set ok\r\n");
            print_config(&app->config);
        }
    } else if (strcmp(cmd, "start") == 0) {
        if (apply_pairs(&app->config, save_ptr, &changed) == 0) {
            closed_loop_ctrl_apply_config(&app->ctrl, &app->config);
            closed_loop_ctrl_start(&app->ctrl);
            xil_printf("start ok\r\n");
            print_status(app, 1);
        }
    } else if (strcmp(cmd, "restart") == 0) {
        if (apply_pairs(&app->config, save_ptr, &changed) == 0) {
            if (changed != 0) {
                closed_loop_ctrl_apply_config(&app->ctrl, &app->config);
            }
            closed_loop_ctrl_restart(&app->ctrl, 1);
            xil_printf("restart ok\r\n");
            print_status(app, 1);
        }
    } else if (strcmp(cmd, "stop") == 0) {
        closed_loop_ctrl_stop(&app->ctrl);
        xil_printf("stop ok\r\n");
        print_status(app, 1);
    } else {
        xil_printf("ERR: unknown command '%s'\r\n", cmd);
        print_help();
    }
}

void closed_loop_app_init(closed_loop_app_t *app,
                          const closed_loop_app_config_t *config)
{
    if ((app == NULL) || (config == NULL)) {
        return;
    }

    platform_hal_init();
    closed_loop_ctrl_init(&app->ctrl, config->capture_base_addr);
    load_safe_config(&app->config);
    closed_loop_ctrl_apply_config(&app->ctrl, &app->config);
    closed_loop_ctrl_stop(&app->ctrl);
}

void closed_loop_app_print_banner(const closed_loop_app_t *app)
{
    xil_printf("\r\n========================================\r\n");
    xil_printf("  Dual PZT Closed Loop Control App 1.1\r\n");
    xil_printf("========================================\r\n");
    if (app != NULL) {
        xil_printf("capture_base=0x%08x\r\n", (unsigned int)app->ctrl.base_addr);
    }
    xil_printf("flow: SENSE monitor | ALIGN standby -> RUN velocity -> RETURN standby\r\n");
    xil_printf("branch fix: ALIGN/RETURN use position-error LUT branch\r\n");
    xil_printf("UART: type 'help' for commands\r\n");
    print_config((app == NULL) ? NULL : &app->config);
}

void closed_loop_app_run_console(closed_loop_app_t *app)
{
    char line[APP_UART_LINE_BYTES];

    if (app == NULL) {
        return;
    }

    for (;;) {
        xil_printf("cmd> ");
        if (platform_hal_uart_read_line(line, sizeof(line)) < 0) {
            xil_printf("ERR: uart read failed\r\n");
            continue;
        }
        handle_command(app, line);
    }
}
