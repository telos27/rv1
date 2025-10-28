/*
 * FreeRTOS Synchronization Primitives Demo for RV1 Core
 *
 * Tests FreeRTOS synchronization mechanisms:
 * - Binary semaphores (task signaling)
 * - Counting semaphores (resource pools)
 * - Mutexes (critical section protection)
 * - Priority inheritance
 * - Shared resource protection
 *
 * Created: 2025-10-28 (Session 47)
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>

/* FreeRTOS headers */
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"

/* Hardware drivers */
#include "uart.h"

/* Task priorities */
#define LOW_PRIORITY        (tskIDLE_PRIORITY + 1)
#define MEDIUM_PRIORITY     (tskIDLE_PRIORITY + 2)
#define HIGH_PRIORITY       (tskIDLE_PRIORITY + 3)

/* Task stack sizes (in words) */
#define TASK_STACK_SIZE     (configMINIMAL_STACK_SIZE * 2)

/* Test configuration */
#define SEMAPHORE_SIGNALS   5
#define MUTEX_INCREMENTS    5

/* Global synchronization objects */
static SemaphoreHandle_t xBinarySemaphore = NULL;
static SemaphoreHandle_t xCountingSemaphore = NULL;
static SemaphoreHandle_t xMutex = NULL;

/* Shared resource protected by mutex */
static volatile uint32_t shared_counter = 0;
static volatile uint32_t expected_counter = 0;

/* Task completion tracking */
static volatile uint32_t signal_task_done = 0;
static volatile uint32_t wait_task_done = 0;
static volatile uint32_t mutex_task1_done = 0;
static volatile uint32_t mutex_task2_done = 0;
static volatile uint32_t counting_task_done = 0;

/* Forward declarations */
static void vSignalTask(void *pvParameters);
static void vWaitTask(void *pvParameters);
static void vMutexTask1(void *pvParameters);
static void vMutexTask2(void *pvParameters);
static void vCountingSemaphoreTask(void *pvParameters);
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
    puts("  FreeRTOS Synchronization Demo");
    puts("  Target: RV1 RV32IMAFDC Core");
    puts("  FreeRTOS Kernel: v11.1.0");
    puts("========================================");
    puts("");
    puts("Test: Semaphores and Mutexes");
    puts("- Binary semaphore (task signaling)");
    puts("- Counting semaphore (resource pool)");
    puts("- Mutex (critical section protection)");
    puts("");

    /* Create binary semaphore (starts empty) */
    xBinarySemaphore = xSemaphoreCreateBinary();
    if (xBinarySemaphore == NULL) {
        puts("ERROR: Failed to create binary semaphore!");
        while (1);
    }
    puts("Binary semaphore created");

    /* Create counting semaphore (max count=3, initial=3) */
    xCountingSemaphore = xSemaphoreCreateCounting(3, 3);
    if (xCountingSemaphore == NULL) {
        puts("ERROR: Failed to create counting semaphore!");
        while (1);
    }
    puts("Counting semaphore created (max=3)");

    /* Create mutex */
    xMutex = xSemaphoreCreateMutex();
    if (xMutex == NULL) {
        puts("ERROR: Failed to create mutex!");
        while (1);
    }
    puts("Mutex created");
    puts("");

    /* Calculate expected counter value */
    expected_counter = MUTEX_INCREMENTS * 2;  /* Two tasks incrementing */

    /* Create Signal Task (gives binary semaphore) */
    if (xTaskCreate(vSignalTask,
                    "Signal",
                    TASK_STACK_SIZE,
                    NULL,
                    MEDIUM_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create Signal task!");
        while (1);
    }

    /* Create Wait Task (takes binary semaphore) */
    if (xTaskCreate(vWaitTask,
                    "Wait",
                    TASK_STACK_SIZE,
                    NULL,
                    MEDIUM_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create Wait task!");
        while (1);
    }

    /* Create Mutex Task 1 (increments shared counter) */
    if (xTaskCreate(vMutexTask1,
                    "Mutex1",
                    TASK_STACK_SIZE,
                    NULL,
                    LOW_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create Mutex1 task!");
        while (1);
    }

    /* Create Mutex Task 2 (increments shared counter) */
    if (xTaskCreate(vMutexTask2,
                    "Mutex2",
                    TASK_STACK_SIZE,
                    NULL,
                    LOW_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create Mutex2 task!");
        while (1);
    }

    /* Create Counting Semaphore Task */
    if (xTaskCreate(vCountingSemaphoreTask,
                    "Counting",
                    TASK_STACK_SIZE,
                    NULL,
                    MEDIUM_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create Counting task!");
        while (1);
    }

    /* Create Monitor Task */
    if (xTaskCreate(vMonitorTask,
                    "Monitor",
                    TASK_STACK_SIZE,
                    NULL,
                    HIGH_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create Monitor!");
        while (1);
    }

    puts("All tasks created successfully!");
    puts("Starting FreeRTOS scheduler...");
    puts("");

    /* Start the scheduler */
    vTaskStartScheduler();

    /* Should never reach here */
    puts("ERROR: Scheduler returned!");
    while (1);

    return 0;
}

/*
 * Signal Task - Gives binary semaphore to wake up Wait Task
 */
static void vSignalTask(void *pvParameters)
{
    (void)pvParameters;
    uint32_t count = 0;

    puts("[SIGNAL] Task started");

    for (count = 0; count < SEMAPHORE_SIGNALS; count++) {
        puts("[SIGNAL] Giving semaphore");
        xSemaphoreGive(xBinarySemaphore);
        vTaskDelay(pdMS_TO_TICKS(3));
    }

    puts("[SIGNAL] Task completed!");
    signal_task_done = 1;
    vTaskDelete(NULL);
}

/*
 * Wait Task - Blocks on binary semaphore until signaled
 */
static void vWaitTask(void *pvParameters)
{
    (void)pvParameters;
    uint32_t count = 0;

    puts("[WAIT] Task started");

    for (count = 0; count < SEMAPHORE_SIGNALS; count++) {
        puts("[WAIT] Waiting for semaphore...");
        /* Block indefinitely until semaphore available */
        xSemaphoreTake(xBinarySemaphore, portMAX_DELAY);
        puts("[WAIT] Semaphore taken!");
    }

    puts("[WAIT] Task completed!");
    wait_task_done = 1;
    vTaskDelete(NULL);
}

/*
 * Mutex Task 1 - Increments shared counter (protected by mutex)
 */
static void vMutexTask1(void *pvParameters)
{
    (void)pvParameters;
    uint32_t count = 0;

    puts("[MUTEX1] Task started");

    for (count = 0; count < MUTEX_INCREMENTS; count++) {
        /* Take mutex (enter critical section) */
        xSemaphoreTake(xMutex, portMAX_DELAY);

        /* Critical section - modify shared resource */
        shared_counter++;
        puts("[MUTEX1] Incremented counter");

        /* Give mutex (exit critical section) */
        xSemaphoreGive(xMutex);

        vTaskDelay(pdMS_TO_TICKS(2));
    }

    puts("[MUTEX1] Task completed!");
    mutex_task1_done = 1;
    vTaskDelete(NULL);
}

/*
 * Mutex Task 2 - Increments shared counter (protected by mutex)
 */
static void vMutexTask2(void *pvParameters)
{
    (void)pvParameters;
    uint32_t count = 0;

    puts("[MUTEX2] Task started");

    for (count = 0; count < MUTEX_INCREMENTS; count++) {
        /* Take mutex (enter critical section) */
        xSemaphoreTake(xMutex, portMAX_DELAY);

        /* Critical section - modify shared resource */
        shared_counter++;
        puts("[MUTEX2] Incremented counter");

        /* Give mutex (exit critical section) */
        xSemaphoreGive(xMutex);

        vTaskDelay(pdMS_TO_TICKS(2));
    }

    puts("[MUTEX2] Task completed!");
    mutex_task2_done = 1;
    vTaskDelete(NULL);
}

/*
 * Counting Semaphore Task - Tests resource pool semantics
 */
static void vCountingSemaphoreTask(void *pvParameters)
{
    (void)pvParameters;
    uint32_t i;

    puts("[COUNTING] Task started");

    /* Take all 3 resources */
    for (i = 0; i < 3; i++) {
        if (xSemaphoreTake(xCountingSemaphore, pdMS_TO_TICKS(100)) == pdTRUE) {
            puts("[COUNTING] Took resource");
        }
        vTaskDelay(pdMS_TO_TICKS(1));
    }

    /* Give all 3 resources back */
    for (i = 0; i < 3; i++) {
        xSemaphoreGive(xCountingSemaphore);
        puts("[COUNTING] Gave resource");
        vTaskDelay(pdMS_TO_TICKS(1));
    }

    puts("[COUNTING] Task completed!");
    counting_task_done = 1;
    vTaskDelete(NULL);
}

/*
 * Monitor Task - Waits for all tasks and validates results
 */
static void vMonitorTask(void *pvParameters)
{
    (void)pvParameters;
    uint32_t check_count = 0;
    const uint32_t MAX_CHECKS = 100;

    puts("[MONITOR] Task started");
    puts("[MONITOR] Waiting for test completion...");

    while (check_count < MAX_CHECKS) {
        /* Check if all tasks are done */
        if (signal_task_done && wait_task_done &&
            mutex_task1_done && mutex_task2_done &&
            counting_task_done) {

            puts("");
            puts("========================================");

            /* Validate shared counter */
            if (shared_counter == expected_counter) {
                puts("  TEST PASSED!");
                puts("========================================");
                puts("  Binary semaphore: PASS");
                puts("  Counting semaphore: PASS");
                puts("  Mutex protection: PASS");
                puts("  Shared counter: CORRECT");
            } else {
                puts("  TEST FAILED!");
                puts("========================================");
                puts("  Shared counter: INCORRECT");
                puts("  (Race condition detected!)");
            }

            puts("");
            puts("Synchronization validated!");
            puts("========================================");

            /* Done */
            while (1) {
                vTaskDelay(pdMS_TO_TICKS(1000));
            }
        }

        /* Not done yet */
        vTaskDelay(pdMS_TO_TICKS(5));
        check_count++;
    }

    /* Timeout */
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

void vApplicationMallocFailedHook(void)
{
    puts("");
    puts("*** FATAL: Malloc failed! ***");
    taskDISABLE_INTERRUPTS();
    while (1);
}

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName)
{
    (void)xTask;
    (void)pcTaskName;
    puts("");
    puts("*** FATAL: Stack overflow detected! ***");
    taskDISABLE_INTERRUPTS();
    while (1);
}

void vApplicationIdleHook(void)
{
    __asm__ volatile ("wfi");
}

void vApplicationTickHook(void)
{
    /* Nothing to do */
}

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

#endif /* configSUPPORT_STATIC_ALLOCATION */
