#ifndef CLOSED11_PLATFORM_HAL_H
#define CLOSED11_PLATFORM_HAL_H

#include <stddef.h>
#include <stdint.h>

void platform_hal_init(void);
uint32_t platform_hal_now_ms(void);
int platform_hal_uart_read_line(char *buffer, size_t buffer_bytes);

#endif /* CLOSED11_PLATFORM_HAL_H */
