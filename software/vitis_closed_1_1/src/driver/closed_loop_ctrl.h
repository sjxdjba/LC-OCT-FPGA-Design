#ifndef CLOSED11_CLOSED_LOOP_CTRL_H
#define CLOSED11_CLOSED_LOOP_CTRL_H

#include <stdint.h>

#include "driver/closed_loop_regs.h"

typedef struct {
    uintptr_t base_addr;
} closed_loop_ctrl_t;

typedef struct {
    int32_t kp_q16;
    int32_t ki_diff_q16;
    int32_t ki_pos_q16;
    int32_t ref_velocity_nm_s;
    int32_t standby_pos_nm;
    int32_t target_pos_nm;
    uint32_t ctrl_rate_cycles;
} closed_loop_config_t;

typedef struct {
    uint32_t raw_ctrl;
    closed_ctrl_state_t state;
    uint32_t enabled;
    uint32_t sense_enabled;
    uint32_t record_count;
    uint32_t status;
    uint32_t debug0;
    uint32_t debug1;
    uint32_t adc_valid_count;
    uint32_t adc_raw_codes;
    uint32_t last0;
    uint32_t last1;
    int32_t vel_m1_nm_s;
    int32_t diff_ab_nm;
    int32_t pos_m1_nm;
    int32_t pos_m2_nm;
    int32_t dac_total_m1;
    int32_t dac_total_m2;
    uint32_t dac_ff_m1;
    uint32_t dac_ff_m2;
    int32_t dac_p_m1;
    int32_t dac_p_m2;
    int32_t pos_err_m1;
    int32_t pos_err_m2;
    int32_t vel_err_m1;
    int32_t vel_err_m2;
} closed_loop_status_t;

void closed_loop_ctrl_init(closed_loop_ctrl_t *dev, uintptr_t base_addr);
void closed_loop_ctrl_apply_config(const closed_loop_ctrl_t *dev,
                                   const closed_loop_config_t *config);
void closed_loop_ctrl_read_config(const closed_loop_ctrl_t *dev,
                                  closed_loop_config_t *config);
void closed_loop_ctrl_start(const closed_loop_ctrl_t *dev);
void closed_loop_ctrl_stop(const closed_loop_ctrl_t *dev);
void closed_loop_ctrl_sense_on(const closed_loop_ctrl_t *dev);
void closed_loop_ctrl_sense_off(const closed_loop_ctrl_t *dev);
void closed_loop_ctrl_restart(const closed_loop_ctrl_t *dev, int keep_enable);
void closed_loop_ctrl_read_status(const closed_loop_ctrl_t *dev,
                                  closed_loop_status_t *status);
const char *closed_loop_ctrl_state_name(closed_ctrl_state_t state);

#endif /* CLOSED11_CLOSED_LOOP_CTRL_H */
