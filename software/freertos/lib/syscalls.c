/*
 * Newlib Syscalls for FreeRTOS on RV1
 *
 * Provides minimal syscall implementations for newlib:
 * - _write: Output to UART
 * - _read: Input from UART
 * - _sbrk: Heap allocation (not used - FreeRTOS manages heap)
 * - Other syscalls: Stubbed
 *
 * Created: 2025-10-27
 */

#include <sys/stat.h>
#include <errno.h>
#include <stdio.h>
#include "uart.h"

/* Define stdin, stdout, stderr as required by picolibc */
FILE *const stdin = (FILE *)0;
FILE *const stdout = (FILE *)1;
FILE *const stderr = (FILE *)2;

/*
 * Custom puts() implementation
 * Override picolibc's puts() to avoid FILE pointer dereference issues
 */
int puts(const char *s)
{
    /* Write string to UART */
    while (*s) {
        uart_putc(*s++);
    }
    /* Add newline */
    uart_putc('\n');
    return 1;  /* Success */
}

/* Forward declarations */
int _close(int file);
int _fstat(int file, struct stat *st);
int _isatty(int file);
int _lseek(int file, int ptr, int dir);
int _open(const char *name, int flags, int mode);
int _read(int file, char *ptr, int len);
void *_sbrk(int incr);
int _write(int file, char *ptr, int len);

/*
 * Close a file
 * Not supported - return error
 */
int _close(int file)
{
    (void)file;
    errno = EBADF;
    return -1;
}

/*
 * Status of an open file
 * For stdin/stdout/stderr, report as character device
 */
int _fstat(int file, struct stat *st)
{
    if (file >= 0 && file <= 2) {
        /* stdin, stdout, stderr are character devices */
        st->st_mode = S_IFCHR;
        return 0;
    }

    errno = EBADF;
    return -1;
}

/*
 * Check if file descriptor is a terminal
 * stdin/stdout/stderr are terminals (UART)
 */
int _isatty(int file)
{
    if (file >= 0 && file <= 2) {
        return 1;  /* Yes, it's a terminal */
    }

    errno = EBADF;
    return 0;
}

/*
 * Seek within a file
 * Not supported - return error
 */
int _lseek(int file, int ptr, int dir)
{
    (void)file;
    (void)ptr;
    (void)dir;
    errno = ESPIPE;  /* Illegal seek */
    return -1;
}

/*
 * Open a file
 * Not supported - return error
 */
int _open(const char *name, int flags, int mode)
{
    (void)name;
    (void)flags;
    (void)mode;
    errno = ENOENT;
    return -1;
}

/*
 * Read from a file
 * For stdin (0), read from UART
 * Other files not supported
 */
int _read(int file, char *ptr, int len)
{
    int i;

    if (file != 0) {
        errno = EBADF;
        return -1;
    }

    /* Read from UART */
    for (i = 0; i < len; i++) {
        ptr[i] = uart_getc();

        /* Echo character back */
        uart_putc(ptr[i]);

        /* Handle newline */
        if (ptr[i] == '\r') {
            ptr[i] = '\n';
            uart_putc('\n');
            break;
        }
    }

    return i + 1;
}

/*
 * Increase heap size
 * Not used - FreeRTOS manages its own heap via pvPortMalloc
 * Return error if called
 */
void *_sbrk(int incr)
{
    (void)incr;
    errno = ENOMEM;
    return (void *)-1;
}

/*
 * Write to a file
 * For stdout (1) and stderr (2), write to UART
 * Other files not supported
 */
int _write(int file, char *ptr, int len)
{
    int i;

    if (file != 1 && file != 2) {
        errno = EBADF;
        return -1;
    }

    /* Write to UART */
    for (i = 0; i < len; i++) {
        uart_putc(ptr[i]);
    }

    return len;
}

/*
 * Exit program
 * No OS to return to - just halt
 */
void _exit(int status)
{
    (void)status;

    /* Halt CPU with WFI loop */
    while (1) {
        __asm__ volatile ("wfi");
    }
}

/*
 * Kill process
 * Not supported in bare-metal environment
 */
int _kill(int pid, int sig)
{
    (void)pid;
    (void)sig;
    errno = EINVAL;
    return -1;
}

/*
 * Get process ID
 * Single process system - always return 1
 */
int _getpid(void)
{
    return 1;
}
