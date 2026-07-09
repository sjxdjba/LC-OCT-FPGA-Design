#include "driver/closed_loop_ctrl.h"

#include <stddef.h>

#include "hal/mmio_hal.h"

static int32_t read_s32(uintptr_t base_addr, uint32_t offset)
{
    return (int32_t)mmio_read32(base_addr, offset);
}

static void write_s32(uintptr_t base_addr, uint32_t offset, int32_t value)
{
    mmio_write32(base_addr, offset, (uint32_t)value);
}

void closed_loop_ctrl_init(closed_loop_ctrl_t *dev, uintptr_t base_addr)
{
    if (dev == NULL) {
        return;
    }

    dev->base_addr = base_addr;
}

void closed_loop_ctrl_apply_config(const closed_loop_ctrl_t *dev,
                                   const closed_loop_config_t *config)
{
    if ((dev == NULL) || (config == NULL)) {
        return;
    }

    write_s32(dev->base_addr, CLOSED_REG_VEL_KP, config->kp_q16);
    write_s32(dev->base_addr, CLOSED_REG_VEL_KI_DIFF, config->ki_diff_q16);
    write_s32(dev->base_addr, CLOSED_REG_VEL_KI_POS, config->ki_pos_q16);
    write_s32(dev->base_addr, CLOSED_REG_VEL_REF_VEL, config->ref_velocity_nm_s);
    write_s32(dev->base_addr, CLOSED_REG_VEL_REF_POS, config->standby_pos_nm);
    write_s32(dev->base_addr, CLOSED_REG_VEL_TARGET_POS, config->target_pos_nm);
    mmio_write32(dev->base_addr, CLOSED_REG_VEL_CTRL_RATE, config->ctrl_rate_cycles);
}

void closed_loop_ctrl_read_config(const closed_loop_ctrl_t *dev,
                                  closed_loop_config_t *config)
{
    if ((dev == NULL) || (config == NULL)) {
        return;
    }

    config->kp_q16 = read_s32(dev->base_addr, CLOSED_REG_VEL_KP);
    config->ki_diff_q16 = read_s32(dev->base_addr, CLOSED_REG_VEL_KI_DIFF);
    config->ki_pos_q16 = read_s32(dev->base_addr, CLOSED_REG_VEL_KI_POS);
    config->ref_velocity_nm_s = read_s32(dev->base_addr, CLOSED_REG_VEL_REF_VEL);
    config->standby_pos_nm = read_s32(dev->base_addr, CLOSED_REG_VEL_REF_POS);
    config->target_pos_nm = read_s32(dev->base_addr, CLOSED_REG_VEL_TARGET_POS);
    config->ctrl_rate_cycles = mmio_read32(dev->base_addr, CLOSED_REG_VEL_CTRL_RATE);
}

void closed_loop_ctrl_start(const closed_loop_ctrl_t *dev)
{
    if (dev == NULL) {
        return;
    }

    mmio_write32(dev->base_addr, CLOSED_REG_VEL_CTRL, CLOSED_VEL_CTRL_ENABLE);
}

void closed_loop_ctrl_stop(const closed_loop_ctrl_t *dev)
{
    if (dev == NULL) {
        return;
    }

    mmio_write32(dev->base_addr, CLOSED_REG_VEL_CTRL, 0U);
}

void closed_loop_ctrl_sense_on(const closed_loop_ctrl_t *dev)
{
    if (dev == NULL) {
        return;
    }

    mmio_write32(dev->base_addr, CLOSED_REG_VEL_CTRL, CLOSED_VEL_CTRL_SENSE);
}

void closed_loop_ctrl_sense_off(const closed_loop_ctrl_t *dev)
{
    if (dev == NULL) {
        return;
    }

    mmio_write32(dev->base_addr, CLOSED_REG_VEL_CTRL, 0U);
}

void closed_loop_ctrl_restart(const closed_loop_ctrl_t *dev, int keep_enable)
{
    uint32_t value = CLOSED_VEL_CTRL_RESTART;

    if (dev == NULL) {
        return;
    }

    if (keep_enable != 0) {
        value |= CLOSED_VEL_CTRL_ENABLE;
    }

    mmio_write32(dev->base_addr, CLOSED_REG_VEL_CTRL, value);
}

void closed_loop_ctrl_read_status(const closed_loop_ctrl_t *dev,
                                  closed_loop_status_t *status)
{
    uint32_t raw_ctrl = 0U;

    if ((dev == NULL) || (status == NULL)) {
        return;
    }

    raw_ctrl = mmio_read32(dev->base_addr, CLOSED_REG_VEL_CTRL);
    status->raw_ctrl = raw_ctrl;
    status->state = (closed_ctrl_state_t)((raw_ctrl & CLOSED_VEL_CTRL_STATE_MASK) >>
                                          CLOSED_VEL_CTRL_STATE_SHIFT);
    status->enabled = raw_ctrl & CLOSED_VEL_CTRL_ENABLE;
    status->sense_enabled = raw_ctrl & CLOSED_VEL_CTRL_SENSE;
    status->record_count = mmio_read32(dev->base_addr, CLOSED_REG_COUNT);
    status->status = mmio_read32(dev->base_addr, CLOSED_REG_STATUS);
    status->debug0 = mmio_read32(dev->base_addr, CLOSED_REG_DEBUG0);
    status->debug1 = mmio_read32(dev->base_addr, CLOSED_REG_DEBUG1);
    status->adc_valid_count = mmio_read32(dev->base_addr, CLOSED_REG_DEBUG4);
    status->adc_raw_codes = mmio_read32(dev->base_addr, CLOSED_REG_DEBUG5);
    status->last0 = mmio_read32(dev->base_addr, CLOSED_REG_LAST0);
    status->last1 = mmio_read32(dev->base_addr, CLOSED_REG_LAST1);
    status->vel_m1_nm_s = read_s32(dev->base_addr, CLOSED_REG_VEL_DEBUG0);
    status->diff_ab_nm = read_s32(dev->base_addr, CLOSED_REG_VEL_DEBUG1);
    status->pos_m1_nm = read_s32(dev->base_addr, CLOSED_REG_VEL_POS_M1);
    status->pos_m2_nm = read_s32(dev->base_addr, CLOSED_REG_VEL_POS_M2);
    status->dac_total_m1 = read_s32(dev->base_addr, CLOSED_REG_VEL_DAC_TOTAL_M1);
    status->dac_total_m2 = read_s32(dev->base_addr, CLOSED_REG_VEL_DAC_TOTAL_M2);
    status->dac_ff_m1 = mmio_read32(dev->base_addr, CLOSED_REG_VEL_DAC_FF_M1);
    status->dac_ff_m2 = mmio_read32(dev->base_addr, CLOSED_REG_VEL_DAC_FF_M2);
    status->dac_p_m1 = read_s32(dev->base_addr, CLOSED_REG_VEL_DAC_P_M1);
    status->dac_p_m2 = read_s32(dev->base_addr, CLOSED_REG_VEL_DAC_P_M2);
    status->pos_err_m1 = read_s32(dev->base_addr, CLOSED_REG_VEL_POS_ERR_M1);
    status->pos_err_m2 = read_s32(dev->base_addr, CLOSED_REG_VEL_POS_ERR_M2);
    status->vel_err_m1 = read_s32(dev->base_addr, CLOSED_REG_VEL_VEL_ERR_M1);
    status->vel_err_m2 = read_s32(dev->base_addr, CLOSED_REG_VEL_VEL_ERR_M2);
}

const char *closed_loop_ctrl_state_name(closed_ctrl_state_t state)
{
    switch (state) {
    case CLOSED_CTRL_STATE_IDLE:
        return "IDLE";
    case CLOSED_CTRL_STATE_ALIGN:
        return "ALIGN";
    case CLOSED_CTRL_STATE_RUN:
        return "RUN";
    case CLOSED_CTRL_STATE_RETURN:
        return "RETURN";
    default:
        return "UNKNOWN";
    }
}
