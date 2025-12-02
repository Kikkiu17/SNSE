/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2025 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "dma.h"
#include "usart.h"
#include "gpio.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include "../ESP8266/esp8266.h"
#include "../Flash/flash.h"
#include "../wifihandler/wifihandler.h"
#include "../wifihandler/userhandlers.h"
#include "../credentials.h"
#include <string.h>
#include <stdio.h>
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

/* USER CODE BEGIN PV */
WIFI_t wifi;
Connection_t conn;
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{

  /* USER CODE BEGIN 1 */

  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_DMA_Init();
  MX_USART1_UART_Init();
  /* USER CODE BEGIN 2 */
  if (ESP8266_Init() == TIMEOUT)
  {
	  while (1)
		  __asm__("nop");
  }

#ifdef ENABLE_SAVE_TO_FLASH
  FLASH_ReadSaveData();
  WIFI_SetName(&wifi, savedata.name);

  if (savedata.ip[0] >= '0' && savedata.ip[0] <= '9')
    WIFI_SetIP(&wifi, savedata.ip); // Set previously assigned IP
#endif

  memcpy(wifi.SSID, ssid, strlen(ssid));
  memcpy(wifi.pw, password, strlen(password));
  WIFI_Connect(&wifi);
  WIFI_SetName(&wifi, (char*)ESP_NAME);
  WIFI_EnableNTPServer(&wifi, 2);

  WIFI_StartServer(&wifi, SERVER_PORT);

  // Save current IP (to make it "static")
  strncpy(savedata.ip, wifi.IP, 15);
  FLASH_WriteSaveData();

  SWITCH_Init(&(switches[RELAY_SWITCH]), false, GPIOA, 0);
  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
	  Response_t status = WIFI_ReceiveRequest(&wifi, &conn, AT_SHORT_TIMEOUT);
	  if (status == OK)
	  {
		  char* key_ptr = NULL;

      if ((key_ptr = WIFI_RequestHasKey(&conn, "wifi")))
			  WIFIHANDLER_HandleWiFiRequest(&conn, key_ptr);
      else if ((key_ptr = WIFI_RequestHasKey(&conn, "switch")))
			  WIFIHANDLER_HandleSwitchRequest(&conn, key_ptr);

		  if ((key_ptr = WIFI_RequestHasKey(&conn, "time")))
		  {
			  if (WIFI_RequestKeyHasValue(&conn, key_ptr, "now"))
			  {
				  int32_t hours = WIFI_GetTimeHour(&wifi);
				  int32_t minutes = WIFI_GetTimeMinutes(&wifi);
				  int32_t seconds = WIFI_GetTimeSeconds(&wifi);
				  sprintf(wifi.buf, "%ld:%ld:%ld", hours, minutes, seconds);
				  WIFI_SendResponse(&conn, "200 OK", wifi.buf, strlen(wifi.buf));
			  }
		  }
	  }
	  // OPTIONAL
	  else if (status != TIMEOUT)
	  {
		  sprintf(wifi.buf, "Status: %d", status);
		  WIFI_ResetComm(&wifi, &conn);
		  WIFI_SendResponse(&conn, "500 Internal server error", wifi.buf, strlen(wifi.buf));
	  }

	  // OPTIONAL
	  WIFI_ResetConnectionIfError(&wifi, &conn, status);
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
  }
  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  /** Configure the main internal regulator output voltage
  */
  HAL_PWREx_ControlVoltageScaling(PWR_REGULATOR_VOLTAGE_SCALE1);

  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSI;
  RCC_OscInitStruct.HSIState = RCC_HSI_ON;
  RCC_OscInitStruct.HSIDiv = RCC_HSI_DIV1;
  RCC_OscInitStruct.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSI;
  RCC_OscInitStruct.PLL.PLLM = RCC_PLLM_DIV1;
  RCC_OscInitStruct.PLL.PLLN = 8;
  RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV2;
  RCC_OscInitStruct.PLL.PLLR = RCC_PLLR_DIV2;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  /** Initializes the CPU, AHB and APB buses clocks
  */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV1;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_2) != HAL_OK)
  {
    Error_Handler();
  }
}

/* USER CODE BEGIN 4 */

/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
  }
  /* USER CODE END Error_Handler_Debug */
}
#ifdef USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  /* User can add his own implementation to report the file name and line number,
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
