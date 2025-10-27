/*
 * UART Driver Implementation for RV1 SoC
 * 16550-compatible UART at 0x10000000
 *
 * Created: 2025-10-27
 */

#include <stddef.h>
#include "uart.h"

/* UART register access macros */
#define UART_REG(offset) (*(volatile uint8_t*)(UART_BASE + (offset)))

/*
 * Initialize UART
 * - Disable interrupts
 * - Configure for 8N1 mode (8 data bits, no parity, 1 stop bit)
 * - Enable FIFO
 */
void uart_init(void)
{
    /* Disable all interrupts */
    UART_REG(UART_IER_OFFSET) = 0x00;

    /* Set 8N1 mode: 8 bits, no parity, 1 stop bit */
    UART_REG(UART_LCR_OFFSET) = 0x03;

    /* Enable and clear FIFOs */
    UART_REG(UART_FCR_OFFSET) = 0x07;  /* Enable FIFO, clear RX/TX */

    /* No modem control */
    UART_REG(UART_MCR_OFFSET) = 0x00;
}

/*
 * Transmit a single character
 * Blocks until THR is empty
 */
void uart_putc(char c)
{
    /* Wait for Transmit Holding Register to be empty */
    while ((UART_REG(UART_LSR_OFFSET) & UART_LSR_THRE) == 0) {
        /* Busy wait */
    }

    /* Write character to THR */
    UART_REG(UART_THR_OFFSET) = (uint8_t)c;
}

/*
 * Receive a single character
 * Blocks until data is available
 */
char uart_getc(void)
{
    /* Wait for Data Ready */
    while ((UART_REG(UART_LSR_OFFSET) & UART_LSR_DR) == 0) {
        /* Busy wait */
    }

    /* Read character from RBR */
    return (char)UART_REG(UART_RBR_OFFSET);
}

/*
 * Transmit a null-terminated string
 * Returns number of characters sent
 */
int uart_puts(const char *s)
{
    int count = 0;

    if (s == NULL) {
        return 0;
    }

    while (*s) {
        /* Handle newline */
        if (*s == '\n') {
            uart_putc('\r');  /* Send CR before LF */
        }
        uart_putc(*s++);
        count++;
    }

    return count;
}

/*
 * Check if data is available to read
 * Returns 1 if data available, 0 otherwise
 */
int uart_available(void)
{
    return (UART_REG(UART_LSR_OFFSET) & UART_LSR_DR) ? 1 : 0;
}
