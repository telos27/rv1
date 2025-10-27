/*
 * UART Driver for RV1 SoC
 * 16550-compatible UART at 0x10000000
 *
 * Created: 2025-10-27
 */

#ifndef UART_H
#define UART_H

#include <stdint.h>

/* UART base address (see MEMORY_MAP.md) */
#define UART_BASE 0x10000000UL

/* UART register offsets */
#define UART_RBR_OFFSET 0  /* Receive Buffer Register (R) */
#define UART_THR_OFFSET 0  /* Transmit Holding Register (W) */
#define UART_IER_OFFSET 1  /* Interrupt Enable Register */
#define UART_IIR_OFFSET 2  /* Interrupt Identification Register (R) */
#define UART_FCR_OFFSET 2  /* FIFO Control Register (W) */
#define UART_LCR_OFFSET 3  /* Line Control Register */
#define UART_MCR_OFFSET 4  /* Modem Control Register */
#define UART_LSR_OFFSET 5  /* Line Status Register */
#define UART_MSR_OFFSET 6  /* Modem Status Register */
#define UART_SCR_OFFSET 7  /* Scratch Register */

/* Line Status Register bits */
#define UART_LSR_DR   (1 << 0)  /* Data Ready */
#define UART_LSR_OE   (1 << 1)  /* Overrun Error */
#define UART_LSR_PE   (1 << 2)  /* Parity Error */
#define UART_LSR_FE   (1 << 3)  /* Framing Error */
#define UART_LSR_BI   (1 << 4)  /* Break Interrupt */
#define UART_LSR_THRE (1 << 5)  /* Transmit Holding Register Empty */
#define UART_LSR_TEMT (1 << 6)  /* Transmitter Empty */
#define UART_LSR_FIFOERR (1 << 7)  /* Error in FIFO */

/* Function prototypes */
void uart_init(void);
void uart_putc(char c);
char uart_getc(void);
int uart_puts(const char *s);
int uart_available(void);

#endif /* UART_H */
