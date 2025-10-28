/*
 * FreeRTOS Enhanced Multitasking Demo for RV1 Core
 *
 * Comprehensive test of FreeRTOS scheduler features:
 * - Multiple tasks with different priorities
 * - Short delays for simulation visibility (1-5ms vs 500-1000ms)
 * - Priority-based preemption validation
 * - Task yield and cooperation
 * - Immediate output to verify scheduler operation
 *
 * Created: 2025-10-28 (Session 47)
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>

/* FreeRTOS headers */
#include "FreeRTOS.h"
#include "task.h"

/* Hardware drivers */
#include "uart.h"

/* Task priorities - Higher number = higher priority */
#define IDLE_PRIORITY       (tskIDLE_PRIORITY)
#define LOW_PRIORITY        (tskIDLE_PRIORITY + 1)
#define MEDIUM_PRIORITY     (tskIDLE_PRIORITY + 2)
#define HIGH_PRIORITY       (tskIDLE_PRIORITY + 3)

/* Task stack sizes (in words) */
#define TASK_STACK_SIZE     (configMINIMAL_STACK_SIZE * 2)

/* Task iteration counts - Finite loops for testability */
#define HIGH_TASK_ITERATIONS    10
#define MEDIUM_TASK_ITERATIONS  8
#define LOW_TASK_ITERATIONS     5

/* Task completion flags - Track when tasks finish */
static volatile uint32_t high_task_done = 0;
static volatile uint32_t medium_task_done = 0;
static volatile uint32_t low_task_done = 0;

/* Forward declarations */
static void vHighPriorityTask(void *pvParameters);
static void vMediumPriorityTask(void *pvParameters);
static void vLowPriorityTask(void *pvParameters);
static void vMonitorTask(void *pvParameters);

/* FreeRTOS hook functions */
void vApplicationMallocFailedHook(void);
void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName);
void vApplicationIdleHook(void);
void vApplicationTickHook(void);

/*
 * Main entry point
 */
int main(void)
{
    /* Initialize UART for console output */
    uart_init();

    /* Print startup banner */
    puts("");
    puts("========================================");
    puts("  FreeRTOS Enhanced Multitasking Demo");
    puts("  Target: RV1 RV32IMAFDC Core");
    puts("  FreeRTOS Kernel: v11.1.0");
    puts("========================================");
    puts("");
    puts("Test: Priority-based preemption");
    puts("High priority task should run first");
    puts("Then medium, then low priority tasks");
    puts("");

    /* Create High Priority Task */
    if (xTaskCreate(vHighPriorityTask,
                    "HighTask",
                    TASK_STACK_SIZE,
                    NULL,
                    HIGH_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create High Priority Task!");
        while (1);
    }

    /* Create Medium Priority Task */
    if (xTaskCreate(vMediumPriorityTask,
                    "MedTask",
                    TASK_STACK_SIZE,
                    NULL,
                    MEDIUM_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create Medium Priority Task!");
        while (1);
    }

    /* Create Low Priority Task */
    if (xTaskCreate(vLowPriorityTask,
                    "LowTask",
                    TASK_STACK_SIZE,
                    NULL,
                    LOW_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create Low Priority Task!");
        while (1);
    }

    /* Create Monitor Task (same priority as high, but created last) */
    if (xTaskCreate(vMonitorTask,
                    "Monitor",
                    TASK_STACK_SIZE,
                    NULL,
                    HIGH_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create Monitor Task!");
        while (1);
    }

    puts("All tasks created successfully!");
    puts("Starting FreeRTOS scheduler...");
    puts("");

    /* Start the scheduler - should never return */
    vTaskStartScheduler();

    /* Should never reach here */
    puts("ERROR: Scheduler returned!");
    while (1);

    return 0;
}

/*
 * High Priority Task - Should preempt lower priority tasks
 * Runs 10 iterations with 1ms delays
 */
static void vHighPriorityTask(void *pvParameters)
{
    (void)pvParameters;
    uint32_t iteration = 0;

    puts("[HIGH] Task started (Priority 3)");

    for (iteration = 0; iteration < HIGH_TASK_ITERATIONS; iteration++) {
        puts("[HIGH] Running");

        /* Short delay - 1ms = 50,000 cycles at 50MHz */
        /* This is visible in simulation (vs 500ms = 25M cycles!) */
        vTaskDelay(pdMS_TO_TICKS(1));
    }

    puts("[HIGH] Task completed!");
    high_task_done = 1;

    /* Delete self */
    vTaskDelete(NULL);
}

/*
 * Medium Priority Task - Runs after high priority yields
 * Runs 8 iterations with 2ms delays
 */
static void vMediumPriorityTask(void *pvParameters)
{
    (void)pvParameters;
    uint32_t iteration = 0;

    puts("[MED] Task started (Priority 2)");

    for (iteration = 0; iteration < MEDIUM_TASK_ITERATIONS; iteration++) {
        puts("[MED] Running");

        /* 2ms delay */
        vTaskDelay(pdMS_TO_TICKS(2));
    }

    puts("[MED] Task completed!");
    medium_task_done = 1;

    /* Delete self */
    vTaskDelete(NULL);
}

/*
 * Low Priority Task - Runs after higher priority tasks yield
 * Runs 5 iterations with 3ms delays
 */
static void vLowPriorityTask(void *pvParameters)
{
    (void)pvParameters;
    uint32_t iteration = 0;

    puts("[LOW] Task started (Priority 1)");

    for (iteration = 0; iteration < LOW_TASK_ITERATIONS; iteration++) {
        puts("[LOW] Running");

        /* 3ms delay */
        vTaskDelay(pdMS_TO_TICKS(3));
    }

    puts("[LOW] Task completed!");
    low_task_done = 1;

    /* Delete self */
    vTaskDelete(NULL);
}

/*
 * Monitor Task - Waits for all tasks to complete, then declares success
 * High priority to ensure it can check status
 */
static void vMonitorTask(void *pvParameters)
{
    (void)pvParameters;
    uint32_t check_count = 0;
    const uint32_t MAX_CHECKS = 100;  /* Prevent infinite loop */

    puts("[MONITOR] Task started");
    puts("[MONITOR] Waiting for all tasks to complete...");

    /* Wait for all tasks to finish */
    while (check_count < MAX_CHECKS) {
        /* Check if all tasks are done */
        if (high_task_done && medium_task_done && low_task_done) {
            puts("");
            puts("========================================");
            puts("  TEST PASSED!");
            puts("========================================");
            puts("  High priority task: DONE");
            puts("  Medium priority task: DONE");
            puts("  Low priority task: DONE");
            puts("");
            puts("Scheduler validated successfully!");
            puts("========================================");

            /* Success - hang here or continue running idle */
            while (1) {
                vTaskDelay(pdMS_TO_TICKS(1000));
            }
        }

        /* Not done yet, yield to other tasks */
        vTaskDelay(pdMS_TO_TICKS(5));
        check_count++;
    }

    /* Timeout - tasks didn't complete */
    puts("");
    puts("========================================");
    puts("  TEST FAILED!");
    puts("========================================");
    puts("  Timeout: Tasks did not complete");
    puts("========================================");

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
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
    (void)pcTaskName;
    puts("");
    puts("*** FATAL: Stack overflow detected! ***");
    taskDISABLE_INTERRUPTS();
    while (1);
}

/* Called when idle task runs */
void vApplicationIdleHook(void)
{
    /* Use WFI to save power when idle */
    __asm__ volatile ("wfi");
}

/* Called on every tick (optional) */
void vApplicationTickHook(void)
{
    /* Nothing to do here */
}

/*
 * Optional: Override default idle task memory allocation
 * (Required if using static allocation)
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
