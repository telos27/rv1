/*
 * FreeRTOS Blinky Demo for RV1 Core
 *
 * Simple demonstration of FreeRTOS running on RV32IMAFDC:
 * - Two tasks printing to UART at different rates
 * - Demonstrates task scheduling and context switching
 * - Tests timer interrupt (FreeRTOS tick)
 *
 * Created: 2025-10-27
 */

#include <stdio.h>
#include <string.h>

/* FreeRTOS headers */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "timers.h"

/* Hardware drivers */
#include "uart.h"

/* Task priorities */
#define TASK1_PRIORITY (tskIDLE_PRIORITY + 1)
#define TASK2_PRIORITY (tskIDLE_PRIORITY + 1)

/* Task stack sizes (in words) */
#define TASK1_STACK_SIZE (configMINIMAL_STACK_SIZE * 2)
#define TASK2_STACK_SIZE (configMINIMAL_STACK_SIZE * 2)

/* Forward declarations */
static void vTask1(void *pvParameters);
static void vTask2(void *pvParameters);
void vApplicationMallocFailedHook(void);
void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName);
void vApplicationIdleHook(void);
void vApplicationTickHook(void);
void vApplicationAssertionFailed(void);

/*
 * Main entry point
 * Initializes hardware and starts FreeRTOS scheduler
 */
int main(void)
{
    /* Initialize UART for console output */
    uart_init();

    /* Print startup banner - using puts() to avoid printf() duplication bug */
    puts("");
    puts("========================================");
    puts("  FreeRTOS Blinky Demo");
    puts("  Target: RV1 RV32IMAFDC Core");
    puts("  FreeRTOS Kernel: v11.1.0");
    puts("  CPU Clock: 50000000 Hz");
    puts("  Tick Rate: 1000 Hz");
    puts("========================================");
    puts("");

    /* Create Task 1 */
    if (xTaskCreate(vTask1,                  /* Task function */
                    "Task1",                 /* Task name */
                    TASK1_STACK_SIZE,        /* Stack size */
                    NULL,                    /* Parameters */
                    TASK1_PRIORITY,          /* Priority */
                    NULL) != pdPASS)         /* Task handle */
    {
        puts("ERROR: Failed to create Task1!");
        while (1);
    }

    /* Create Task 2 */
    if (xTaskCreate(vTask2,
                    "Task2",
                    TASK2_STACK_SIZE,
                    NULL,
                    TASK2_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create Task2!");
        while (1);
    }

    puts("Tasks created successfully!");
    puts("Starting FreeRTOS scheduler...");
    puts("");

    /* Start the scheduler - this should never return */
    vTaskStartScheduler();

    /* Should never reach here */
    puts("ERROR: Scheduler returned!");
    while (1);

    return 0;
}

/*
 * Task 1 - Fast blinker (500ms period)
 */
static void vTask1(void *pvParameters)
{
    (void)pvParameters;
    TickType_t xLastWakeTime;
    uint32_t count = 0;

    /* Initialize wake time */
    xLastWakeTime = xTaskGetTickCount();

    puts("[Task1] Started! Running at 2 Hz");

    while (1) {
        /* Print message */
        puts("[Task1] Tick");
        count++;

        /* Delay for 500ms (absolute delay, not relative) */
        vTaskDelayUntil(&xLastWakeTime, pdMS_TO_TICKS(500));
    }
}

/*
 * Task 2 - Slow blinker (1000ms period)
 */
static void vTask2(void *pvParameters)
{
    (void)pvParameters;
    TickType_t xLastWakeTime;
    uint32_t count = 0;

    /* Initialize wake time */
    xLastWakeTime = xTaskGetTickCount();

    puts("[Task2] Started! Running at 1 Hz");

    while (1) {
        /* Print message */
        puts("[Task2] Tick");
        count++;

        /* Delay for 1000ms */
        vTaskDelayUntil(&xLastWakeTime, pdMS_TO_TICKS(1000));
    }
}

/*
 * FreeRTOS Hook Functions
 */

/* Called when malloc() fails */
void vApplicationMallocFailedHook(void)
{
    puts("");
    puts("*** FATAL: Malloc failed! ***");
    taskDISABLE_INTERRUPTS();
    while (1);
}

/* Called when stack overflow detected */
void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName)
{
    (void)xTask;
    (void)pcTaskName;  /* Avoid unused warning - can't print name without printf */
    puts("");
    puts("*** FATAL: Stack overflow detected! ***");
    taskDISABLE_INTERRUPTS();
    while (1);
}

/* Called when idle task runs (optional) */
void vApplicationIdleHook(void)
{
    /* Could put CPU into low-power mode here */
    __asm__ volatile ("wfi");  /* Wait for interrupt */
}

/* Called on every tick (optional) */
void vApplicationTickHook(void)
{
    /* Nothing to do here for now */
}

/* Called when assertion fails */
void vApplicationAssertionFailed(void)
{
    printf("\n*** FATAL: Assertion failed! ***\n");
    taskDISABLE_INTERRUPTS();
    while (1);
}

/*
 * Optional: Override default idle task memory allocation
 * (Not needed if using dynamic allocation)
 */
#if (configSUPPORT_STATIC_ALLOCATION == 1)

/* Idle task control block and stack */
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

/* Timer task control block and stack */
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

#endif /* configSUPPORT_STATIC_ALLOCATION */
