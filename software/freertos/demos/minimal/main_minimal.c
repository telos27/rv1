/*
 * FreeRTOS MINIMAL Test for RV1 Core
 *
 * Ultra-simple test with:
 * - One task only (simplest multitasking test)
 * - Very short delays (10 ticks = 10ms @ 1kHz tick)
 * - Minimal output to reduce simulation time
 * - Should complete in < 500K cycles
 *
 * Created: 2025-10-31 (Session 75 debugging)
 */

#include <stdio.h>
#include <string.h>

/* FreeRTOS headers */
#include "FreeRTOS.h"
#include "task.h"

/* Hardware drivers */
#include "uart.h"

/* Task configuration */
#define TASK_PRIORITY (tskIDLE_PRIORITY + 1)
#define TASK_STACK_SIZE (configMINIMAL_STACK_SIZE * 2)
#define NUM_ITERATIONS 5  // Print 5 times then stop

/* Forward declarations */
static void vMinimalTask(void *pvParameters);
void vApplicationMallocFailedHook(void);
void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName);
void vApplicationIdleHook(void);
void vApplicationTickHook(void);
void vApplicationAssertionFailed(void);

/* Global flag to stop simulation after test completes */
volatile uint32_t test_complete = 0;

/*
 * Main entry point
 */
int main(void)
{
    /* Initialize UART */
    uart_init();

    /* Minimal startup banner */
    puts("FreeRTOS Minimal Test");
    puts("1 task, 10 tick delays, 5 iterations");
    puts("");

    /* Create single task */
    if (xTaskCreate(vMinimalTask,
                    "Min",
                    TASK_STACK_SIZE,
                    NULL,
                    TASK_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Task creation failed!");
        while (1);
    }

    puts("Task created, starting scheduler...");

    /* Start scheduler */
    vTaskStartScheduler();

    /* Should never reach here */
    puts("ERROR: Scheduler returned!");
    while (1);

    return 0;
}

/*
 * Minimal task - delays 10 ticks between prints
 */
static void vMinimalTask(void *pvParameters)
{
    (void)pvParameters;
    uint32_t count = 0;

    puts("[Task] Started");

    while (count < NUM_ITERATIONS) {
        /* Print tick number */
        puts("[Task] Tick");
        count++;

        /* Ultra-short delay - 1 tick = 50K cycles @ 50MHz, 1kHz tick rate */
        /* This allows simulation to complete in reasonable time */
        vTaskDelay(1);  // 1 tick delay
    }

    /* Test complete! */
    puts("[Task] Test PASSED - 5 ticks completed");
    test_complete = 1;

    /* Task deletes itself */
    vTaskDelete(NULL);
}

/*
 * FreeRTOS Hook Functions
 */

void vApplicationMallocFailedHook(void)
{
    puts("FATAL: Malloc failed!");
    taskDISABLE_INTERRUPTS();
    while (1);
}

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName)
{
    (void)xTask;
    (void)pcTaskName;
    puts("FATAL: Stack overflow!");
    taskDISABLE_INTERRUPTS();
    while (1);
}

void vApplicationIdleHook(void)
{
    /* Check if test completed */
    if (test_complete) {
        puts("");
        puts("========================================");
        puts("MINIMAL TEST COMPLETE - STOPPING");
        puts("========================================");
        /* Infinite loop to stop simulation cleanly */
        while (1) {
            __asm__ volatile ("wfi");
        }
    }

    /* Otherwise just WFI to save power */
    __asm__ volatile ("wfi");
}

void vApplicationTickHook(void)
{
    /* Nothing needed */
}

void vApplicationAssertionFailed(void)
{
    puts("FATAL: Assertion failed!");
    taskDISABLE_INTERRUPTS();
    while (1);
}

/*
 * Static allocation for idle/timer tasks
 */
#if (configSUPPORT_STATIC_ALLOCATION == 1)

static StaticTask_t xIdleTaskTCB;
static StackType_t uxIdleTaskStack[configMINIMAL_STACK_SIZE];

void vApplicationGetIdleTaskMemory(StaticTask_t **ppxIdleTaskTCBBuffer,
                                   StackType_t **ppxIdleTaskStackBuffer,
                                   uint32_t *pulIdleTaskStackSize)
{
    *ppxIdleTaskTCBBuffer = &xIdleTaskTCB;
    *ppxIdleTaskStackBuffer = uxIdleTaskStack;
    *pulIdleTaskStackSize = configMINIMAL_STACK_SIZE;
}

static StaticTask_t xTimerTaskTCB;
static StackType_t uxTimerTaskStack[configTIMER_TASK_STACK_DEPTH];

void vApplicationGetTimerTaskMemory(StaticTask_t **ppxTimerTaskTCBBuffer,
                                    StackType_t **ppxTimerTaskStackBuffer,
                                    uint32_t *pulTimerTaskStackSize)
{
    *ppxTimerTaskTCBBuffer = &xTimerTaskTCB;
    *ppxTimerTaskStackBuffer = uxTimerTaskStack;
    *pulTimerTaskStackSize = configTIMER_TASK_STACK_DEPTH;
}

#endif
