#include "app/closed_loop_app.h"
#include "xparameters.h"

int main(void)
{
    closed_loop_app_t app = {0};
    const closed_loop_app_config_t config = {
        .capture_base_addr = XPAR_MODEL_CAPTURE_AXI_TOP_0_BASEADDR
    };

    closed_loop_app_init(&app, &config);
    closed_loop_app_print_banner(&app);
    closed_loop_app_run_console(&app);

    return 0;
}
