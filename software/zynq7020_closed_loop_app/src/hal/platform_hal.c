#include "hal/platform_hal.h"

#include <string.h>

#include "xil_io.h"
#include "xparameters.h"

#define GTIMER_COUNT_LOW_OFFSET    0x00U
#define GTIMER_COUNT_HIGH_OFFSET   0x04U
#define GTIMER_CONTROL_OFFSET      0x08U
#define GTIMER_CONTROL_ENABLE      (1U << 0)

static int is_auto_submit_command(const char *buffer)
{
    return (strcmp(buffer, "status") == 0) ||
           (strcmp(buffer, "diag") == 0) ||
           (strcmp(buffer, "safe") == 0) ||
           (strcmp(buffer, "stop") == 0) ||
           (strcmp(buffer, "help") == 0) ||
           (strcmp(buffer, "show") == 0) ||
           (strcmp(buffer, "config") == 0) ||
           (strcmp(buffer, "?") == 0);
}

static uint64_t platform_hal_read_global_timer(void)
{
    uint32_t hi_a = 0U;
    uint32_t lo = 0U;
    uint32_t hi_b = 0U;

    do {
        hi_a = Xil_In32(XPAR_PS7_GLOBALTIMER_0_BASEADDR + GTIMER_COUNT_HIGH_OFFSET);
        lo = Xil_In32(XPAR_PS7_GLOBALTIMER_0_BASEADDR + GTIMER_COUNT_LOW_OFFSET);
        hi_b = Xil_In32(XPAR_PS7_GLOBALTIMER_0_BASEADDR + GTIMER_COUNT_HIGH_OFFSET);
    } while (hi_a != hi_b);

    return (((uint64_t)hi_a) << 32) | (uint64_t)lo;
}

void platform_hal_init(void)
{
    const uint32_t ctrl_addr = XPAR_PS7_GLOBALTIMER_0_BASEADDR + GTIMER_CONTROL_OFFSET;
    const uint32_t ctrl = Xil_In32(ctrl_addr);

    if ((ctrl & GTIMER_CONTROL_ENABLE) == 0U) {
        Xil_Out32(ctrl_addr, ctrl | GTIMER_CONTROL_ENABLE);
    }
}

uint32_t platform_hal_now_ms(void)
{
    const uint64_t ticks = platform_hal_read_global_timer();
    const uint64_t counts_per_ms = ((uint64_t)XPAR_CPU_CORE_CLOCK_FREQ_HZ / 2ULL) / 1000ULL;

    if (counts_per_ms == 0ULL) {
        return 0U;
    }

    return (uint32_t)(ticks / counts_per_ms);
}

int platform_hal_uart_read_line(char *buffer, size_t buffer_bytes)
{
    static int ignore_next_lf = 0;
    static int discard_leading_eol = 0;
    size_t index = 0U;

    if ((buffer == NULL) || (buffer_bytes < 2U)) {
        return -1;
    }

    while (index < (buffer_bytes - 1U)) {
        const char ch = inbyte();

        if (discard_leading_eol != 0) {
            if ((ch == '\r') || (ch == '\n')) {
                ignore_next_lf = (ch == '\r') ? 1 : 0;
                continue;
            }
            discard_leading_eol = 0;
        }

        if (ignore_next_lf != 0) {
            ignore_next_lf = 0;
            if (ch == '\n') {
                continue;
            }
        }

        if (ch == '\0') {
            continue;
        }

        if (ch == '\r') {
            ignore_next_lf = 1;
            break;
        }

        if (ch == '\n') {
            break;
        }

        if ((ch == 'n') || (ch == 'r')) {
            if ((index > 0U) &&
                ((buffer[index - 1U] == '\\') || (buffer[index - 1U] == '/'))) {
                --index;
                break;
            }
        }

        buffer[index++] = ch;
        outbyte(ch);

        buffer[index] = '\0';
        if (is_auto_submit_command(buffer) != 0) {
            discard_leading_eol = 1;
            break;
        }
    }

    buffer[index] = '\0';
    outbyte('\r');
    outbyte('\n');
    return (int)index;
}
