/*
 * features.h
 *
 *  Created on: Aug 6, 2025
 *      Author: kikkiu
 */

#ifndef SETTINGS_H_
#define SETTINGS_H_

#include <inttypes.h>
#include "stm32g0xx.h"

typedef uint8_t bool;
#define true 1
#define false 0

// CHANGE THESE SETTINGS ACCORDING TO YOUR SETUP!!!
#define STM_UART huart1
#define UART_DMA_CHANNEL DMA1_Channel1
#define ESP_RST_PORT ESPRST_GPIO_Port
#define ESP_RST_PIN ESPRST_Pin

#define STATUS_Port STATUS_LED_GPIO_Port
#define STATUS_Pin STATUS_LED_Pin

// ==========================================================================================
// 											FLASH
// ==========================================================================================
/**
 *				!!!THE LAST PAGE OF THE FLASH MEMORY HAS TO BE BLANK!!!
 * 						!!!CHECK PROGRAM SIZE BEFORE UPLOADING!!!
 */
#define ENABLE_SAVE_TO_FLASH

#ifdef ENABLE_SAVE_TO_FLASH
// check your datasheet for the permitted datatype! STM32G030 can write DWORD on FLASH
typedef uint64_t FLASH_DATATYPE;
#define FLASH_DATASIZE sizeof(FLASH_DATATYPE)
#define LAST_PAGE_ADDRESS 0x08000000 + ((FLASH_PAGE_NB - 1) * FLASH_PAGE_SIZE)
//#define LAST_PAGE_ADDRESS 0x08000000 + FLASH_BANK_SIZE - FLASH_PAGE_SIZE
//#define LAST_PAGE_ADDRESS 0x8007800	// check your datasheet!!!
#endif

// ==========================================================================================
// 									NETWORK (esp8266.h)
// ==========================================================================================
static const char ESP_NAME[] = "SNSE device";
#define SERVER_PORT 34677

// NOT SUPPORTED:
//static const char ESP_HOSTNAME[] = "ESPDEVICE002"; // template: ESPDEVICExxx
//static const char ESP_IP[] = "192.168.1.38";

#define AT_SHORT_TIMEOUT 250
#define AT_MEDIUM_TIMEOUT 500
#define AT_LONG_TIMEOUT 1250

// BUFFERS SIZES (in RAM)

/**
 * RESPONSE_MAX_SIZE
 *
 * this buffer will contain the data to be sent FROM THIS device to the connected device
 * this could correspond to sizeof(FEATURES_TEMPLATE), because it's usually the biggest response
 * this device will send. set this according to your needs
 */
#define RESPONSE_MAX_SIZE 512

/**
 * REQUEST_MAX_SIZE
 *
 * if you don't expect big requests from the remote device, this buffer can be small (usually 128 bytes or less)
 */
#define REQUEST_MAX_SIZE 64

/**
 * WIFI_BUF_MAX_SIZE
 *
 * contains short commands to be sent to the ESP, for example to connect it to WiFi, to get the current IP...
 * (check esp8266.c)
 * if you don't use it directly, it can be left at the default value.
 * NOTE: this can contain the network SSID and PASSWORD, so if those strings are larger than this buffer,
 * the network name and/or its password will be truncated, resulting in no WiFi connection!
 */
#define WIFI_BUF_MAX_SIZE 128

/**
 * UART_BUFFER_SIZE
 *
 * if you have to retrieve large amounts of data (i.e. from an API), set this to the minimum size of the response
 * otherwise, it can be smaller.
 * if you don't have these requirements, you can set it to a minimum of
 * REQUEST_MAX_SIZE + some headroom to avoid receiving only partial messages
 * if you encounter weird behaviors at runtime, try increasing this buffer size
 */
#define UART_BUFFER_SIZE 128

#define HOSTNAME_MAX_SIZE 32		// ESPDEVICExxx
#define NAME_MAX_SIZE 32			// human-readable name

#define UART_TX_TIMEOUT 500			// ms
#define UART_RX_IDLE_TIMEOUT 3000	// ms

typedef struct notif
{
	char* text;
	uint8_t size;
} Notification_t;

extern Notification_t notification;

// ==========================================================================================
// 										SAVE DATA
// ==========================================================================================
/**
 * The save data will be written to the last page of the memory bank
 * 					!!!See FLASH section at the top of the file!!!
 */

#ifdef ENABLE_SAVE_TO_FLASH
typedef struct sdata
{
	char name[NAME_MAX_SIZE];
} SaveData_t;

extern SaveData_t savedata;
#endif

// ==========================================================================================
// 											OTHER
// ==========================================================================================

#define START_ATTEMPTS -1

typedef struct
{
	bool pressed;
	bool inverted;
	GPIO_TypeDef* port;
	uint16_t pin;
	bool manual;
} Switch_t;

#define NUMBER_OF_SWITCHES 1

#define RELAY_SWITCH 0

extern Switch_t switches[1];

// ==========================================================================================
// 										COMM TEMPLATE
// ==========================================================================================

/**
 * template:
 * type1$Name:data;
 * type2$Name,additional_feature$feature_Name$data,additional_feature$feature_name$data...;
 *
 * every type must have a numerical ID (typeX - X being the ID).
 * every type must have a name.
 * a type can have additional features, that must be put on the same line of the main feature,
 * preceded by a comma ",".
 * a semicolon ";" must be put at the end of each feature (line).
 *
 * example:
 * switch1$Switch number one,sensor$Switch status$%d;
 * switch2$Switch number two,sensor$Switch status$%d,sensor$Time$%d;
 * timestamp1$Uptime$%d;
 * sensor1$Battery voltage$%d;
 *
 * FEATURE				SYNTAX												OPTIONAL SYNTAX
 * sensor				sensorX$text$%d text
 * switch				switchX$text,status$%d								switchX$switch_name,status$%d,sensor$sensor_name$%d
 * textinut				textinputX$default_text								textinputX$txt_name,button$btn_name$send<command> (without a space)
 * 		text inside the textinput field will be appended at the end of the command to be sent
 * timepicker			timepicker$%s (time data, should be hh:mm-hh:mm)	timepicker$%s,button$btn_name$send<command>
 * timestamp			timestampX$text$d text
 * external				externalX$id
 * 		external features have an ID, read by the android app, which identifies a feature that will be retrieved from
 * 		a server specified on the android app. the server will return the feature itself that will be displayed
 * 		on the device page on the app.
 *
 * 		external features:
 * 		1 = GRAPH
 *
 * 		NOTE: external features will only be updated ONCE, every time the device is loaded in the app.
 */

typedef struct bat
{
	uint16_t voltage_mv;
	uint16_t voltage_integer;
	uint16_t voltage_decimal;

} Battery_t;

extern Battery_t bat;

static const char FEATURES_TEMPLATE[] =
{
		"switch1$Luce,status$%d;"
		"sensor1$Tensione alimentazione$%d,%dV;"
};

#endif /* SETTINGS_H_ */
