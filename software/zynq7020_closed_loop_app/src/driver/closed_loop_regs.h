#ifndef CLOSED11_CLOSED_LOOP_REGS_H
#define CLOSED11_CLOSED_LOOP_REGS_H

#include <stdint.h>

#define CLOSED_REG_STATUS                  0x04U
#define CLOSED_REG_COUNT                   0x08U
#define CLOSED_REG_LAST0                   0x0CU
#define CLOSED_REG_LAST1                   0x10U
#define CLOSED_REG_DEBUG0                  0x14U
#define CLOSED_REG_DEBUG1                  0x18U
#define CLOSED_REG_DEBUG4                  0x24U
#define CLOSED_REG_DEBUG5                  0x28U

#define CLOSED_REG_VEL_CTRL                0x70U
#define CLOSED_REG_VEL_KP                  0x74U
#define CLOSED_REG_VEL_KI_DIFF             0x78U
#define CLOSED_REG_VEL_KI_POS              0x7CU
#define CLOSED_REG_VEL_REF_VEL             0x80U
#define CLOSED_REG_VEL_REF_POS             0x84U
#define CLOSED_REG_VEL_DEBUG0              0x88U
#define CLOSED_REG_VEL_DEBUG1              0x8CU
#define CLOSED_REG_VEL_CTRL_RATE           0x90U
#define CLOSED_REG_VEL_TARGET_POS          0x94U
#define CLOSED_REG_VEL_POS_M1              0x98U
#define CLOSED_REG_VEL_POS_M2              0x9CU
#define CLOSED_REG_VEL_DAC_TOTAL_M1        0xA0U
#define CLOSED_REG_VEL_DAC_TOTAL_M2        0xA4U
#define CLOSED_REG_VEL_DAC_FF_M1           0xA8U
#define CLOSED_REG_VEL_DAC_FF_M2           0xACU
#define CLOSED_REG_VEL_DAC_P_M1            0xB0U
#define CLOSED_REG_VEL_DAC_P_M2            0xB4U
#define CLOSED_REG_VEL_POS_ERR_M1          0xB8U
#define CLOSED_REG_VEL_POS_ERR_M2          0xBCU
#define CLOSED_REG_VEL_VEL_ERR_M1          0xC0U
#define CLOSED_REG_VEL_VEL_ERR_M2          0xC4U

#define CLOSED_VEL_CTRL_ENABLE             (1U << 0)
#define CLOSED_VEL_CTRL_RESTART            (1U << 3)
#define CLOSED_VEL_CTRL_SENSE              (1U << 4)
#define CLOSED_VEL_CTRL_STATE_SHIFT        1U
#define CLOSED_VEL_CTRL_STATE_MASK         (3U << CLOSED_VEL_CTRL_STATE_SHIFT)

typedef enum {
    CLOSED_CTRL_STATE_IDLE = 0,
    CLOSED_CTRL_STATE_ALIGN = 1,
    CLOSED_CTRL_STATE_RUN = 2,
    CLOSED_CTRL_STATE_RETURN = 3
} closed_ctrl_state_t;

#endif /* CLOSED11_CLOSED_LOOP_REGS_H */
