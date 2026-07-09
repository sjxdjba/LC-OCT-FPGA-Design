#ifndef CLOSED11_CLOSED_LOOP_APP_H
#define CLOSED11_CLOSED_LOOP_APP_H

#include <stdint.h>

#include "driver/closed_loop_ctrl.h"

typedef struct {
    uintptr_t capture_base_addr;
} closed_loop_app_config_t;

typedef struct {
    closed_loop_ctrl_t ctrl;
    closed_loop_config_t config;
} closed_loop_app_t;

void closed_loop_app_init(closed_loop_app_t *app,
                          const closed_loop_app_config_t *config);
void closed_loop_app_print_banner(const closed_loop_app_t *app);
void closed_loop_app_run_console(closed_loop_app_t *app);

#endif /* CLOSED11_CLOSED_LOOP_APP_H */
