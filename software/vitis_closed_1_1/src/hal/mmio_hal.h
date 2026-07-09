#ifndef CLOSED11_MMIO_HAL_H
#define CLOSED11_MMIO_HAL_H

#include <stdint.h>

static inline void mmio_write32(uintptr_t base_addr, uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(base_addr + (uintptr_t)offset) = value;
}

static inline uint32_t mmio_read32(uintptr_t base_addr, uint32_t offset)
{
    return *(volatile const uint32_t *)(base_addr + (uintptr_t)offset);
}

#endif /* CLOSED11_MMIO_HAL_H */
