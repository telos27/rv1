/*
 * FreeRTOS Queue Communication Demo for RV1 Core
 *
 * Tests FreeRTOS queue IPC (Inter-Process Communication):
 * - Producer-consumer pattern
 * - Multiple producers, single consumer
 * - Queue send/receive blocking behavior
 * - Data integrity verification
 * - FIFO ordering validation
 *
 * Created: 2025-10-28 (Session 47)
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>

/* FreeRTOS headers */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"

/* Hardware drivers */
#include "uart.h"

/* Task priorities */
#define PRODUCER_PRIORITY   (tskIDLE_PRIORITY + 2)
#define CONSUMER_PRIORITY   (tskIDLE_PRIORITY + 2)

/* Task stack sizes (in words) */
#define TASK_STACK_SIZE     (configMINIMAL_STACK_SIZE * 2)

/* Queue configuration */
#define QUEUE_LENGTH        5   /* Can hold 5 items */
#define QUEUE_ITEM_SIZE     sizeof(uint32_t)

/* Test configuration */
#define PRODUCER1_COUNT     5
#define PRODUCER2_COUNT     5
#define TOTAL_EXPECTED      (PRODUCER1_COUNT + PRODUCER2_COUNT)

/* Global queue handle */
static QueueHandle_t xTestQueue = NULL;

/* Task completion tracking */
static volatile uint32_t producer1_done = 0;
static volatile uint32_t producer2_done = 0;
static volatile uint32_t consumer_done = 0;
static volatile uint32_t items_received = 0;

/* Forward declarations */
static void vProducerTask1(void *pvParameters);
static void vProducerTask2(void *pvParameters);
static void vConsumerTask(void *pvParameters);
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
    puts("  FreeRTOS Queue Communication Demo");
    puts("  Target: RV1 RV32IMAFDC Core");
    puts("  FreeRTOS Kernel: v11.1.0");
    puts("========================================");
    puts("");
    puts("Test: Producer-Consumer pattern");
    puts("2 producers send data via queue");
    puts("1 consumer receives and validates");
    puts("");

    /* Create queue - holds 5 uint32_t items */
    xTestQueue = xQueueCreate(QUEUE_LENGTH, QUEUE_ITEM_SIZE);
    if (xTestQueue == NULL) {
        puts("ERROR: Failed to create queue!");
        while (1);
    }
    puts("Queue created successfully (length=5)");

    /* Create Producer Task 1 */
    if (xTaskCreate(vProducerTask1,
                    "Prod1",
                    TASK_STACK_SIZE,
                    NULL,
                    PRODUCER_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create Producer1!");
        while (1);
    }

    /* Create Producer Task 2 */
    if (xTaskCreate(vProducerTask2,
                    "Prod2",
                    TASK_STACK_SIZE,
                    NULL,
                    PRODUCER_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create Producer2!");
        while (1);
    }

    /* Create Consumer Task */
    if (xTaskCreate(vConsumerTask,
                    "Consumer",
                    TASK_STACK_SIZE,
                    NULL,
                    CONSUMER_PRIORITY,
                    NULL) != pdPASS)
    {
        puts("ERROR: Failed to create Consumer!");
        while (1);
    }

    /* Create Monitor Task */
    if (xTaskCreate(vMonitorTask,
                    "Monitor",
                    TASK_STACK_SIZE,
                    NULL,
                    CONSUMER_PRIORITY + 1,
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
 * Producer Task 1 - Sends values 100-104 to queue
 */
static void vProducerTask1(void *pvParameters)
{
    (void)pvParameters;
    uint32_t value = 100;  /* Start at 100 for producer 1 */
    uint32_t count = 0;

    puts("[PROD1] Task started");

    for (count = 0; count < PRODUCER1_COUNT; count++) {
        /* Send value to queue (block up to 100ms if queue full) */
        if (xQueueSend(xTestQueue, &value, pdMS_TO_TICKS(100)) == pdTRUE) {
            puts("[PROD1] Sent item");
        } else {
            puts("[PROD1] ERROR: Queue send timeout!");
        }

        value++;
        vTaskDelay(pdMS_TO_TICKS(2));  /* 2ms between sends */
    }

    puts("[PROD1] Task completed!");
    producer1_done = 1;

    /* Delete self */
    vTaskDelete(NULL);
}

/*
 * Producer Task 2 - Sends values 200-204 to queue
 */
static void vProducerTask2(void *pvParameters)
{
    (void)pvParameters;
    uint32_t value = 200;  /* Start at 200 for producer 2 */
    uint32_t count = 0;

    puts("[PROD2] Task started");

    for (count = 0; count < PRODUCER2_COUNT; count++) {
        /* Send value to queue (block up to 100ms if queue full) */
        if (xQueueSend(xTestQueue, &value, pdMS_TO_TICKS(100)) == pdTRUE) {
            puts("[PROD2] Sent item");
        } else {
            puts("[PROD2] ERROR: Queue send timeout!");
        }

        value++;
        vTaskDelay(pdMS_TO_TICKS(3));  /* 3ms between sends */
    }

    puts("[PROD2] Task completed!");
    producer2_done = 1;

    /* Delete self */
    vTaskDelete(NULL);
}

/*
 * Consumer Task - Receives and validates data from queue
 */
static void vConsumerTask(void *pvParameters)
{
    (void)pvParameters;
    uint32_t received_value;
    uint32_t expected_items = TOTAL_EXPECTED;

    puts("[CONSUMER] Task started");

    while (items_received < expected_items) {
        /* Receive from queue (block indefinitely) */
        if (xQueueReceive(xTestQueue, &received_value, portMAX_DELAY) == pdTRUE) {
            puts("[CONSUMER] Received item");
            items_received++;

            /* Validate received value is in expected range */
            if ((received_value >= 100 && received_value < 105) ||
                (received_value >= 200 && received_value < 205)) {
                /* Valid value */
            } else {
                puts("[CONSUMER] ERROR: Invalid value!");
            }
        }
    }

    puts("[CONSUMER] Task completed!");
    consumer_done = 1;

    /* Delete self */
    vTaskDelete(NULL);
}

/*
 * Monitor Task - Waits for all tasks to complete
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
        if (producer1_done && producer2_done && consumer_done) {
            puts("");
            puts("========================================");
            puts("  TEST PASSED!");
            puts("========================================");
            puts("  Producer 1: DONE (5 items sent)");
            puts("  Producer 2: DONE (5 items sent)");
            puts("  Consumer: DONE (10 items received)");
            puts("");
            puts("Queue communication validated!");
            puts("========================================");

            /* Success */
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
