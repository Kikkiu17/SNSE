/*
 * esp8266.c
 *
 *  Created on: Apr 6, 2025
 *      Author: Kikkiu
 */

#include "esp8266.h"
#include "stm32g0xx_hal_dma.h"
#include "stm32g0xx_hal_uart.h"
#include "stm32g0xx_hal_uart_ex.h"
#include "stm32g0xx_ll_dma.h"
#include "usart.h"
#include <string.h>
#include <inttypes.h>
#include <stdio.h>
#include <time.h>

#define CWMODE_MAX_SIZE 14
#define CIPMUX_MAX_SIZE 14
#define CIPSERVER_MAX_SIZE 50

#define CIPSTA_IP_OFFSET 12

#define CWSTATE_STATE_OFFSET 9
#define CWSTATE_SSID_OFFSET 12
#define CWSTATE_IP_OFFSET 9
#define CWSTATE_NOAP 0
#define CWSTATE_CONNECTED_WITHOUTIP 1
#define CWSTATE_CONNECTED_WITHIP 2
#define CWSTATE_CONNECTING 3
#define CWSTATE_DISCONNECTED 4

volatile char uart_buffer[UART_BUFFER_SIZE + 1];
bool WIFI_response_sent = false;

void WIFI_Init(WIFI_t* wifi)
{
	if (wifi == NULL)
		return;
	memset(wifi, 0, sizeof(WIFI_t));
}

void CONN_Init(Connection_t* conn)
{
	if (conn == NULL)
		return;
	memset(conn, 0, sizeof(Connection_t));
}

void WIFI_ResetComm(WIFI_t* wifi, Connection_t* conn)
{
	ESP8266_ClearBuffer();
	memset(wifi->buf, 0, WIFI_BUF_MAX_SIZE);
	memset(conn->request, 0, REQUEST_MAX_SIZE);
	memset(conn->response_buffer, 0, RESPONSE_MAX_SIZE);
}

int32_t bufferToInt(char* buf, uint32_t size)
{
	if (buf == NULL) return -1;
	uint32_t n = 0;
	for (uint32_t i = 0; i < size; i++)
	{
		if (buf[i] < '0' || buf[i] > '9') return -1;
		n *= 10;
		n += buf[i] - '0';
	}
	return n;
}

Response_t ESP8266_WaitForStringCNDTROffset(char* str, int32_t offset, uint32_t timeout)
{
	if (str == NULL) return NULVAL;
	for (uint32_t i = 0; i < timeout; i++)
	{
		HAL_Delay(1);

		if (strstr((char*)uart_buffer, "ERR") != NULL)
		{
			ESP8266_ClearBuffer();
			return ERR;
		}

		if (UART_BUFFER_SIZE - UART_DMA_CHANNEL->CNDTR > (offset < 0) ? -offset : offset)
			if (strstr((char*)uart_buffer + (UART_BUFFER_SIZE - UART_DMA_CHANNEL->CNDTR) + offset, str) == NULL)
				continue;

		ESP8266_ClearBuffer();
		return OK;
	}

	if (strstr((char*)uart_buffer, "ERROR")) return ERR;

	return TIMEOUT;
}

Response_t ESP8266_WaitForString(char* str, uint32_t timeout)
{
	if (str == NULL) return NULVAL;
	for (uint32_t i = 0; i < timeout; i++)
	{
		HAL_Delay(1);

		// strstr((char*)uart_buffer, "FAIL") is to handle failed WiFi connections
		if (strstr((char*)uart_buffer, "FAIL"))
		{
			ESP8266_ClearBuffer();
			return FAIL;
		}

		if (strstr((char*)uart_buffer, "ERR"))
		{
			ESP8266_ClearBuffer();
			return ERR;
		}

		if (!strstr((char*)uart_buffer, str)) continue;

		ESP8266_ClearBuffer();
		return OK;
	}

	if (strstr((char*)uart_buffer, "ERROR")) return ERR;

	return TIMEOUT;
}

Response_t ESP8266_WaitKeepString(char* str, uint32_t timeout)
{
	if (str == NULL) return NULVAL;
	for (uint32_t i = 0; i < timeout; i++)
	{
		HAL_Delay(1);
		char* ptr = strstr((char*)uart_buffer, str);
		if (ptr == NULL) continue;

		return OK;
	}

	if (strstr((char*)uart_buffer, "ERROR")) return ERR;

	return TIMEOUT;
}

HAL_StatusTypeDef ESP8266_SendATCommandNoResponse(char* cmd, size_t size, uint32_t timeout)
{
	if (cmd == NULL) return HAL_ERROR;
	return HAL_UART_Transmit(&STM_UART, (uint8_t*)cmd, size, UART_TX_TIMEOUT);
}

Response_t ESP8266_SendATCommandResponse(char* cmd, size_t size, uint32_t timeout)
{
	if (cmd == NULL) return NULVAL;
	ESP8266_ClearBuffer();
	if (HAL_UART_Transmit(&STM_UART, (uint8_t*)cmd, size, UART_TX_TIMEOUT) != HAL_OK)
		return ERR;
	return ESP8266_WaitForString("OK", timeout);
}

Response_t ESP8266_SendATCommandKeepString(char* cmd, size_t size, uint32_t timeout)
{
	if (cmd == NULL) return NULVAL;
	ESP8266_ClearBuffer();
	if (HAL_UART_Transmit(&STM_UART, (uint8_t*)cmd, size, UART_TX_TIMEOUT) != HAL_OK)
		return ERR;
	Response_t resp = ESP8266_WaitKeepString("OK", timeout);
	if (resp != ERR && resp != TIMEOUT)
		return OK;
	return resp;
}

Response_t ESP8266_SendATCommandKeepStringNoResponse(char* cmd, size_t size)
{
	if (cmd == NULL) return NULVAL;
	ESP8266_ClearBuffer();
	if (HAL_UART_Transmit(&STM_UART, (uint8_t*)cmd, size, UART_TX_TIMEOUT) != HAL_OK)
		return ERR;
	return OK;
}

Response_t ESP8266_CheckAT(void)
{
	return ESP8266_SendATCommandResponse("AT\r\n", 4, AT_SHORT_TIMEOUT);
}

Response_t ESP8266_Init(void)
{
	ESP8266_ClearBuffer();
	HAL_UARTEx_ReceiveToIdle_DMA(&STM_UART, (uint8_t*)uart_buffer, UART_BUFFER_SIZE);
	return ESP8266_ResetWaitReady();
}

void ESP8266_ClearBuffer(void)
{
	__HAL_DMA_DISABLE(STM_UART.hdmarx);
	memset((char*)uart_buffer, 0, UART_BUFFER_SIZE + 1 - UART_DMA_CHANNEL->CNDTR);
	UART_DMA_CHANNEL->CNDTR = UART_BUFFER_SIZE;		// reset CNDTR so DMA starts writing from index 0
	__HAL_UART_CLEAR_OREFLAG(&STM_UART);
    __HAL_UART_CLEAR_NEFLAG(&STM_UART);
    __HAL_UART_CLEAR_FEFLAG(&STM_UART);
	__HAL_DMA_ENABLE(STM_UART.hdmarx);
}

char* ESP8266_GetBuffer(void)
{
	return (char*)uart_buffer;
}

void ESP8266_Reset(void)
{
	HAL_GPIO_WritePin(ESP_RST_PORT, ESP_RST_PIN, 0);
	HAL_Delay(5);
	HAL_GPIO_WritePin(ESP_RST_PORT, ESP_RST_PIN, 1);
}

Response_t WIFI_StartServer(WIFI_t* wifi, uint16_t port)
{
	Response_t atstatus = ESP8266_CheckAT();
	if (atstatus != OK) return atstatus;
	/**
	 * if some of the following commands return something other than OK, it could mean that
	 * the server is already set up, so we can continue the boot
	*/
	WIFI_SetCWMODE(1);
	WIFI_SetCIPMUX(1);
	WIFI_SetCIPSERVER(port);
	return atstatus;
}

Response_t ESP8266_ResetWaitReady(void)
{
	uint8_t attempt_number = 0;
	Response_t start_ok = ERR;
	while (start_ok != OK)
	{
		if (START_ATTEMPTS != -1 && attempt_number > START_ATTEMPTS)
			return TIMEOUT;
		attempt_number++;
		ESP8266_SendATCommandKeepString("AT+RST\r\n", 8, AT_SHORT_TIMEOUT);
		// hardware reset
		HAL_GPIO_WritePin(ESPRST_GPIO_Port, ESPRST_Pin, 0);
		HAL_Delay(1);
		HAL_GPIO_WritePin(ESPRST_GPIO_Port, ESPRST_Pin, 1);

		HAL_GPIO_WritePin(STATUS_Port, STATUS_Pin, 1);
		start_ok = ESP8266_WaitForStringCNDTROffset("ready", -7, 5000);
		HAL_GPIO_WritePin(STATUS_Port, STATUS_Pin, 0);
		__HAL_UART_CLEAR_OREFLAG(&huart1);	// clear overrun flag caused by esp reset
		ESP8266_ClearBuffer();
	}

	ESP8266_SendATCommandResponse("AT+SLEEP=0\r\n", 12, AT_SHORT_TIMEOUT);

	return start_ok;
}

Response_t ESP8266_ATReset(void)
{
	Response_t resp = ESP8266_SendATCommandResponse("AT+RST\r\n", 8, AT_SHORT_TIMEOUT);
	ESP8266_ClearBuffer();
	return resp;
}

Response_t ESP8266_Restore(void)
{
	Response_t resp = ESP8266_SendATCommandResponse("AT+RESTORE\r\n", 12, AT_SHORT_TIMEOUT);
	ESP8266_ClearBuffer();
	return resp;
}

Response_t WIFI_GetIP(WIFI_t* wifi)
{
	// get ESP IP
	// response structure:
	// +CIFSR:STAIP,"nnn.nnn.nnn.nnn"\r\n
	// +CIFSR:STAMAC,"nn:nn:nn:nn:nn:nn"\r\n

	ESP8266_ClearBuffer();
	Response_t atstatus = ESP8266_SendATCommandKeepString("AT+CIFSR\r\n", 10, AT_SHORT_TIMEOUT);
	if (atstatus != OK) return atstatus;

	//ptr = strstr((char*)uart_buffer, "+CIFSR:STAIP");
	//				v
	// +CIFSR:STAIP,"nnn.nnn.nnn.nnn"\r\n
	char* ptr = strstr((char*)uart_buffer, "\"");
	if (ptr == NULL) return ERR;

	uint32_t IP_start_index = (ptr + 1) - uart_buffer;

	//								v
	// +CIFSR:STAIP,"nnn.nnn.nnn.nnn"\r\n
	ptr = strstr((char*)uart_buffer, "\"\r\n");
	if (ptr == NULL) return ERR;

	uint32_t IP_end_index = (ptr - 1) - uart_buffer;
	if (IP_end_index < IP_start_index) return ERR;

	uint32_t IP_size = IP_end_index - IP_start_index + 1;
	if (IP_size > WIFI_BUF_MAX_SIZE) return ERR;

	memcpy(wifi->IP, (char*)uart_buffer + IP_start_index, IP_size);
	return OK;
}

Response_t WIFI_GetConnectionInfo(WIFI_t* wifi)
{
	if (wifi == NULL) return NULVAL;
	if (ESP8266_SendATCommandKeepString("AT+CWSTATE?\r\n", 13, AT_SHORT_TIMEOUT) != OK)
		return ERR;
	
	char* ptr = strstr((char*)uart_buffer, "+CWSTATE:");
	if (ptr == NULL) return ERR;	// unknown response

	if (*(ptr + CWSTATE_STATE_OFFSET) - '0' != CWSTATE_CONNECTED_WITHIP)
		return ERR;

	//			   v
	// +CWSTATE:x,"xxxxxxxxxxxx"\r\n
	uint32_t SSID_start_index = (ptr + CWSTATE_SSID_OFFSET) - uart_buffer;

	// get ESP SSID
	// response structure:
	// +CWSTATE:x,"xxxxxxxxxxxx"\r\n

	//					   	   v
	// +CWSTATE:x,"xxxxxxxxxxxx"\r\n
	ptr = strstr((char*)uart_buffer, "\"\r\n");	// ptr -1 is the end index of the SSID
	if (ptr == NULL) return ERR;

	uint32_t SSID_end_index = (ptr - 1) - uart_buffer;
	if (SSID_end_index < SSID_start_index) return ERR;

	uint32_t SSID_size = SSID_end_index - SSID_start_index + 1;
	if (SSID_size > sizeof(wifi->SSID)) return ERR;

	memcpy(wifi->SSID, (char*)uart_buffer + SSID_start_index, SSID_size);

	if (WIFI_GetIP(wifi) != OK) return ERR;

	return WIFI_GetHostname(wifi);
}

Response_t WIFI_Connect(WIFI_t* wifi)
{
	if (wifi == NULL) return NULVAL;
	Response_t result = ERR;
	result = ESP8266_SendATCommandKeepString("AT+CWSTATE?\r\n", 13, 5000);
	if (result != OK) return result;

	// response: AT+CWSTATE?\r\n+CWSTATE:0,""\r\n

	char *ptr = strstr((char*)uart_buffer, "+CWSTATE:");
	if (!ptr) return ERR;

	int state = *(ptr + CWSTATE_IP_OFFSET) - '0';

	// if ESP is still connecting, wait for it
	if (state == CWSTATE_CONNECTING)
	{
		// wait for connection
		if (ESP8266_WaitKeepString("WIFI CONNECTED", 9000) == OK)
		{
			if (ESP8266_WaitForString("WIFI GOT IP", 18000) != OK)
				return FAIL;
			else
				state = CWSTATE_CONNECTED_WITHIP;
		}
		else return FAIL;
	}
	else if (state == CWSTATE_CONNECTED_WITHOUTIP)
	{
		// wait for IP
		if (ESP8266_WaitForString("WIFI GOT IP", 18000) != OK)
			return FAIL;
		else
			state = CWSTATE_CONNECTED_WITHIP;
	}

	if (state == CWSTATE_NOAP || state == CWSTATE_DISCONNECTED)
	{
		// ESP is not connected
		// connect the ESP to WiFi

		ESP8266_SendATCommandResponse("AT+CWAUTOCONN=0\r\n", 17, AT_SHORT_TIMEOUT); 
		ESP8266_SendATCommandResponse("AT+CWQAP\r\n", 10, AT_SHORT_TIMEOUT);

		// set ESP as STATION
		if (WIFI_SetCWMODE(1) != OK) return FAIL;
		// set the hostname
		snprintf(wifi->buf, WIFI_BUF_MAX_SIZE, "AT+CWHOSTNAME=\"%s\"\r\n", ESP_HOSTNAME);
		if (ESP8266_SendATCommandResponse(wifi->buf, strlen(wifi->buf), AT_SHORT_TIMEOUT) != OK) return FAIL;

		snprintf(wifi->buf, WIFI_BUF_MAX_SIZE, "AT+CWJAP=\"%s\",\"%s\"\r\n", wifi->SSID, wifi->pw);
		ESP8266_SendATCommandNoResponse(wifi->buf, strlen(wifi->buf), 15000);

		// wait for WiFi
		if (ESP8266_WaitKeepString("WIFI CONNECTED", 9000) == OK)
		{
			if (ESP8266_WaitForString("WIFI GOT IP", 18000) != OK)
				return FAIL;

			if (WIFI_GetConnectionInfo(wifi) != OK)
				return ERR;
			else
			{
				// set the obtained IP as static
				snprintf(wifi->buf, WIFI_BUF_MAX_SIZE, "AT+CIPSTA=\"%s\"\r\n", wifi->IP);
				return ESP8266_SendATCommandResponse(wifi->buf, strlen(wifi->buf), 5000);
			}
		}
		else return FAIL;
	}
	else if (state == CWSTATE_CONNECTED_WITHIP)
	{
		snprintf(wifi->buf, WIFI_BUF_MAX_SIZE, "AT+CWHOSTNAME=\"%s\"\r\n", ESP_HOSTNAME);
		if (ESP8266_SendATCommandResponse(wifi->buf, strlen(wifi->buf), AT_SHORT_TIMEOUT) != OK) return FAIL;
		return WIFI_GetConnectionInfo(wifi);
	}

	return ERR;
}

Response_t WIFI_SetCWMODE(uint8_t mode)
{
	if (mode > 3) return ERR;

	char cwmode[CWMODE_MAX_SIZE + 1];
	memset(cwmode, 0, CWMODE_MAX_SIZE + 1);
	snprintf(cwmode, CWMODE_MAX_SIZE, "AT+CWMODE=%c\r\n", (char)(mode + '0'));
	return ESP8266_SendATCommandResponse(cwmode, CWMODE_MAX_SIZE, AT_SHORT_TIMEOUT);
}

Response_t WIFI_SetCIPMUX(uint8_t mux)
{
	if (mux > 1) return ERR;

	char cipmux[CIPMUX_MAX_SIZE + 1];
	memset(cipmux, 0, CIPMUX_MAX_SIZE + 1);
	snprintf(cipmux, CIPMUX_MAX_SIZE, "AT+CIPMUX=%c\r\n", (char)(mux + '0'));
	return ESP8266_SendATCommandResponse(cipmux, CIPMUX_MAX_SIZE, AT_SHORT_TIMEOUT);
}

Response_t WIFI_SetCIPSERVER(uint16_t server_port)
{
	// for some reason ESP AT doesn't receive connections if the server port is 80
	if (server_port < 1 || server_port > 65535 || server_port == 80)
		return ERR;

	char cipserver[CIPSERVER_MAX_SIZE + 1];
	memset(cipserver, 0, CIPSERVER_MAX_SIZE + 1);
	snprintf(cipserver, CIPSERVER_MAX_SIZE, "AT+CIPSERVER=1,%d\r\n", server_port);
	return ESP8266_SendATCommandResponse(cipserver, strlen(cipserver), AT_SHORT_TIMEOUT);
}

Response_t WIFI_SetHostname(WIFI_t* wifi, const char* hostname)
{
	if (wifi == NULL || hostname == NULL) return NULVAL;
	uint32_t hostname_size = strnlen(hostname, HOSTNAME_MAX_SIZE);
	char hostnamestr[18 + hostname_size + 1];
	memset(hostnamestr, 0, 18 + hostname_size + 1);
	snprintf(hostnamestr, 18 + hostname_size, "AT+CWHOSTNAME=\"%s\"\r\n", hostname);
	Response_t atstatus = ESP8266_SendATCommandResponse(hostnamestr, 18 + hostname_size, AT_SHORT_TIMEOUT);
	if (atstatus == OK)
	{
		if (hostname_size <= HOSTNAME_MAX_SIZE)
			memcpy(wifi->hostname, hostname, hostname_size);
		else
			memcpy(wifi->hostname, hostname, HOSTNAME_MAX_SIZE);
	}
	return atstatus;
}

Response_t WIFI_GetHostname(WIFI_t* wifi)
{
	if (wifi == NULL) return NULVAL;
	Response_t atstatus = ESP8266_SendATCommandKeepString("AT+CWHOSTNAME?\r\n", 16, AT_SHORT_TIMEOUT);
	if (atstatus != OK) return atstatus;

	// +CWHOSTNAME:ESP-A0ADE6
	char* ptr = strstr((char*)uart_buffer, "+CWHOSTNAME:");
	if (ptr == NULL) return ERR;
	//			   v
	// +CWHOSTNAME:ESP-A0ADE6\r\n
	char* hostname_start_p = ptr + 12;
	ptr = strstr(hostname_start_p, "\r\n");
	if (ptr == NULL) return ERR;
	char* hostname_end_p = ptr - 1;

	uint32_t hostname_size = hostname_end_p - hostname_start_p + 1;
	if (hostname_size > HOSTNAME_MAX_SIZE) return ERR;

	memset(wifi->hostname, 0, HOSTNAME_MAX_SIZE);
	memcpy(wifi->hostname, hostname_start_p, hostname_size);

	ESP8266_ClearBuffer();

	return OK;
}

// also saves the name in FLASH memory
Response_t WIFI_SetName(WIFI_t* wifi, char* name)
{
	if (wifi == NULL) return ERR;
	if (name == NULL) return NULVAL;
	// 32 == '!'; 126 == '~'
	if (name[0] < 32 || name[0] > 126) return ERR;

	uint32_t name_size = strnlen(name, NAME_MAX_SIZE);

	if (name_size != NAME_MAX_SIZE)
		memset(savedata.name + name_size, 0, NAME_MAX_SIZE - name_size);
	strncpy(savedata.name, name, name_size);

	if (name_size != NAME_MAX_SIZE)
		memset(wifi->name + name_size, 0, NAME_MAX_SIZE - name_size);
	strncpy(wifi->name, name, name_size);

	return OK;
}

Response_t WIFI_SetIP(WIFI_t* wifi, char* ip)
{
	if (wifi == NULL || ip == NULL || ip[0] < '0' || ip[0] > '9') return ERR;

	uint32_t ip_length = strlen(ip);
	// 255.255.255.255
	if (ip_length > 15) return ERR;

	memset(wifi->buf, 0, WIFI_BUF_MAX_SIZE);
	snprintf(wifi->buf, WIFI_BUF_MAX_SIZE, "AT+CIPSTA=\"%s\"\r\n", ip);
	Response_t atstatus = ESP8266_SendATCommandResponse(wifi->buf, strlen(wifi->buf), AT_SHORT_TIMEOUT);
	return atstatus;
}

Response_t WIFI_ReceiveRequest(WIFI_t* wifi, Connection_t* conn, uint32_t timeout)
{
	if (wifi == NULL || conn == NULL) return NULVAL;

	conn->wifi = wifi;
	char* ptr = NULL;
	char* ipd_ptr = NULL;

	uint32_t start_time = uwTick;
	while (1)
	{
		if (uwTick - start_time > timeout) return TIMEOUT;

		if (uart_buffer[0] == '\0')
		{
			/**
			 * the buffer could have been cleared after the first DMA read. if this happens,
			 * the first item of the DMA buffer will be 0x00. if this is so, check for an incoming
			 * connection from the second element
			 */
			if ((ipd_ptr = strstr((char*)uart_buffer + 1, "+IPD,")) != NULL) break;
		}
		else
		{
			/**
			 * if the first element of the buffer is not 0x00, check for an incoming connection
			 * from the start
			 */
			if ((ipd_ptr = strstr((char*)uart_buffer, "+IPD,")) != NULL) break;
		}
	}

	/**
	 * wait to receive the connection number n and message size m
	 * 		   v
	 * +IPD,n,m:xxxxxxxxxx
	 */
	start_time = uwTick;
	while ((ptr = strstr(ipd_ptr, ":")) == NULL)
	{
		if (uwTick - start_time > timeout) return TIMEOUT;
		__asm__("nop");
	}

	uint32_t expected_size = 0;
	//		  v-->v
	// +IPD,n,xxxxx:xxxxxxxxxx
	char* expected_size_end_p = ptr;
	uint8_t num_size = expected_size_end_p - (ipd_ptr + 7);
	expected_size = bufferToInt(ipd_ptr + 7, num_size);

	start_time = uwTick;
	uint32_t string_len = 0;
	while (string_len < expected_size)
	{
		// wait until the expected number of bytes m is received
		if (uwTick - start_time > timeout) return TIMEOUT;
		string_len = strlen(ptr + 1);
		if (/*string_len > expected_size || */ptr + 1 - uart_buffer + string_len >= UART_BUFFER_SIZE - 1)
		{
			/**
			 * if more bytes are received than the expected or the buffer is full,
			 * clear the buffer and return an error
			 */
			ESP8266_ClearBuffer();
			return ERR;
		}
	}

	//		v
	// +IPD,n,m:xxxxxxxxxx
	conn->connection_number = *(ipd_ptr + 5) - '0';

	//		   v
	// +IPD,n,m:xxxxxxxxxx
	ptr = strstr((char*)uart_buffer, ":");
	if (ptr == NULL) return ERR;

	//			v
	// +IPD,n,m:GET ?xxxxxxxxxx
	// +IPD,n,m:POST ?xxxxxxxxxx
	conn->request_type = *(ptr + 1);

	//				v
	// +IPD,n,m:GET ?xxxxxxxxxx
	ptr = strstr((char*)uart_buffer, "?");
	if (ptr == NULL)
	{
		//				v
		// +IPD,n,m:GET /xxxxxxxxxx
		ptr = strstr((char*)uart_buffer, "/");
		if (ptr == NULL) return ERR;
	}

	//				 v
	// +IPD,n,m:GET ?xxxxxxxxxx
	uint32_t request_body_start_index = (ptr + 1) - uart_buffer;

	// get the request size
	uint32_t request_size;
	ptr = strstr((char*)uart_buffer, " HTTP");
	if (ptr == NULL)
	{
		// if there is no HTTP/x.x use the message size m (at ptr + 7)
		// +IPD,n,m:GET ?xxxxxxxxxx
		request_size = expected_size;
		uint32_t request_start_index;
		if ((ptr = strstr((char*)uart_buffer, ":")) == NULL) return ERR;
		// this removes the "POST " (or "GET ") part
		// get the size of the message received until "POST ", then remove
		// the size of "+IPD,n,m:" to get the size of "POST "
		request_start_index = ptr - uart_buffer;
		request_size = request_size - (request_body_start_index - request_start_index) + 1 - 2; // the -2 removes \r\n
	}
	else
	{
		// otherwise get this length
		// 				 v -----> v
		// +IPD,n,m:GET ?xxxxxxxxxx HTTP....
		uint32_t request_end_index = (ptr - 1) - uart_buffer;
		if (request_end_index < request_body_start_index) return ERR;
		request_size = request_end_index - request_body_start_index + 1;
	}
	if (request_size > REQUEST_MAX_SIZE) return ERR;
	conn->request_size = request_size;

	memset(conn->request, 0, REQUEST_MAX_SIZE);
	memcpy(conn->request, (char*)uart_buffer + request_body_start_index, request_size);
	ESP8266_ClearBuffer();
	return OK;
}

Response_t WIFI_SendResponse(Connection_t* conn, char* status_code, char* body, uint32_t body_length)
{
    if (conn == NULL || status_code == NULL) return NULVAL;

    // Formato stimato: "STATUS\nBODY\r\n"
    size_t status_len = strlen(status_code);
    
    // total length
    // status + '\n' (1) + body + "\r\n" (2)
    uint32_t total_packet_len = status_len + 1 + body_length + 2;

    if (total_packet_len > RESPONSE_MAX_SIZE) return ERR;

    int cmd_len = snprintf(conn->response_buffer, RESPONSE_MAX_SIZE, 
                           "AT+CIPSEND=%d,%" PRIu32 "\r\n", 
                           conn->connection_number, total_packet_len);
                           
    ESP8266_SendATCommandKeepString(conn->response_buffer, cmd_len, 500);

    if (ESP8266_WaitForString(">", 200) == TIMEOUT) 
    {
        // if no '>' is received, maybe there is no connection or the ESP is busy
		// cannot send data
        return TIMEOUT;
    }

    // copy status code + \n
    memcpy(conn->response_buffer, status_code, status_len);
    conn->response_buffer[status_len] = '\n';
    
    // copy body if it exists
    if (body != NULL && body_length > 0)
        memcpy(conn->response_buffer + status_len + 1, body, body_length);
    
    // add \r\n to the end
    // start + status + \n + body
    uint32_t crlf_pos = status_len + 1 + body_length;
    conn->response_buffer[crlf_pos] = '\r';
    conn->response_buffer[crlf_pos + 1] = '\n';

    HAL_UART_Transmit(&STM_UART, (uint8_t*)conn->response_buffer, total_packet_len, UART_TX_TIMEOUT);

    if (ESP8266_WaitForString("SEND OK", AT_LONG_TIMEOUT) == TIMEOUT)
        return ERR;

    WIFI_response_sent = true;
    return OK;
}

void WIFI_ResetConnectionIfError(WIFI_t* wifi, Connection_t* conn, Response_t wifistatus)
{
	if (!WIFI_response_sent)
	{
		if (wifistatus == WAITING)
			WIFI_ResetComm(wifi, conn);
	}
	else
		WIFI_response_sent = false;
}

static uint8_t getMonth(const char* m)
{
    const char* months = "JanFebMarAprMayJunJulAugSepOctNovDec";
    for (uint8_t i = 0; i < 12; i++)
    {
        if (m[0] == months[i*3] && m[1] == months[i*3+1] && m[2] == months[i*3+2])
            return i + 1;
    }
    return 1;
}

static uint8_t getItalyOffset(uint16_t year, uint8_t month, uint8_t day, uint8_t utc_h)
{
    if (month < 3 || month > 10) return 1;
    if (month > 3 && month < 10) return 2;

    uint8_t lastSunday = 31 - ((5 * year / 4 + 4) - (month == 10 ? 0 : 3)) % 7;

    if (month == 3) // marzo
        return (day > lastSunday || (day == lastSunday && utc_h >= 1)) ? 2 : 1;
    
    if (month == 10) // ottobre
        return (day > lastSunday || (day == lastSunday && utc_h >= 1)) ? 1 : 2;

    return 1;
}

Response_t WIFI_GetTime(WIFI_t* wifi)
{
    if (wifi == NULL) return NULVAL;
    wifi->last_time_read = uwTick;
    
    if (ESP8266_SendATCommandKeepString("AT+CIPSNTPTIME?\r\n", 17, AT_SHORT_TIMEOUT) != OK)
        return ERR;

    if (ESP8266_WaitKeepString("OK\r\n", AT_MEDIUM_TIMEOUT) != OK)
        return ERR;

    char* tag_ptr = strstr((char*)uart_buffer, "+CIPSNTPTIME:");
    if (tag_ptr)
    {
        char* colon = strstr(tag_ptr + 13, ":");
        if (!colon) return ERR;

        uint8_t utc_h = (uint8_t)bufferToInt(colon - 2, 2);
        uint8_t utc_m = (uint8_t)bufferToInt(colon + 1, 2);
        uint8_t utc_s = (uint8_t)bufferToInt(colon + 4, 2);
        
        uint8_t day   = (uint8_t)bufferToInt(colon - 5, 2);
        uint8_t month = getMonth(colon - 9);
        uint16_t year = bufferToInt(colon + 7, 4);

        uint8_t local_h = utc_h + getItalyOffset(year, month, day, utc_h);
        if (local_h >= 24) local_h -= 24;

        snprintf(wifi->time, 9, "%02d:%02d:%02d", 
                 local_h % 24, 
                 utc_m % 60, 
                 utc_s % 60);

        return OK;
    }

    return ERR;
}

int32_t WIFI_GetTimeHour(WIFI_t* wifi)
{
	if (wifi == NULL) return 0;
	if ((int32_t)uwTick - wifi->last_time_read > 1000) WIFI_GetTime(wifi);	// avoids too many slow reads
	return bufferToInt(wifi->time, 2);
}

int32_t WIFI_GetTimeMinutes(WIFI_t* wifi)
{
	if (wifi == NULL) return 0;
	if ((int32_t)uwTick - wifi->last_time_read > 1000) WIFI_GetTime(wifi);	// avoids too many slow reads
	return bufferToInt(wifi->time + 3, 2);
}

int32_t WIFI_GetTimeSeconds(WIFI_t* wifi)
{
	if (wifi == NULL) return 0;
	if ((int32_t)uwTick - wifi->last_time_read > 1000) WIFI_GetTime(wifi);	// avoids too many slow reads
	return bufferToInt(wifi->time + 6, 2);
}

Response_t WIFI_EnableNTPServer(WIFI_t* wifi, int8_t time_offset)
{
	if (wifi == NULL) return NULVAL;

	Response_t atstatus = ERR;
	if ((atstatus = ESP8266_SendATCommandKeepString("AT+CIPSNTPCFG?\r\n", 16, AT_SHORT_TIMEOUT)) != OK) return atstatus;

	char* ptr = NULL;
	if ((ptr = strstr((char*)uart_buffer, "+CIPSNTPCFG:")) != NULL)
	{
		uint8_t ntp_enabled = *(ptr + 12) - '0';
		if (ntp_enabled)
			return OK;

		// enable NTP server
		wifi->last_time_read = -1000;
		snprintf(wifi->buf, WIFI_BUF_MAX_SIZE, "AT+CIPSNTPCFG=1,%d,\"pool.ntp.org\",\"time.nist.gov\"\r\n", time_offset);
		return ESP8266_SendATCommandResponse(wifi->buf, strlen(wifi->buf), AT_SHORT_TIMEOUT);
	}

	return ERR;
}

char* WIFI_RequestHasKey(Connection_t* conn, char* desired_key)
{
    if (conn == NULL || desired_key == NULL) return NULL;

    char* ptr = conn->request;
    size_t key_len = strlen(desired_key);

    while (*ptr != '\0')
    {
        // skips eventual ? and & at the beginning
        if (*ptr == '?' || *ptr == '&') ptr++;
        
        // 2. Controlla se la chiave corrisponde qui
        if (strncmp(ptr, desired_key, key_len) == 0)
        {
            // checks if entire key matches
            char next_char = ptr[key_len];
            
            if (next_char == '=' || next_char == '&' || next_char == '\0')
                return ptr; // key found
        }

        // if no match, go to next parameter
        ptr = strstr(ptr, "&");
        if (ptr == NULL) break; // no other parameters
    }

    return NULL;
}

char* WIFI_RequestKeyHasValue(Connection_t* conn, char* request_key_ptr, char* value)
{
    if (conn == NULL || request_key_ptr == NULL || value == NULL) return NULL;

    // check where the keye ends
    char* cursor = request_key_ptr;
    while (*cursor != '=' && *cursor != '&' && *cursor != ' ' && *cursor != '\0')
        cursor++;

    // key has no value
    if (*cursor != '=') 
        return NULL;

    char* actual_value_start = cursor + 1;
    size_t expected_len = strlen(value);

    if (strncmp(actual_value_start, value, expected_len) == 0)
    {
        char char_after_match = actual_value_start[expected_len];

        if (char_after_match == '&' || char_after_match == ' ' || 
            char_after_match == '\0' || char_after_match == '\r' || char_after_match == '\n')
            return actual_value_start;
    }

    return NULL;
}

char* WIFI_GetKeyValue(Connection_t* conn, char* request_key_ptr, uint32_t* value_size)
{
    if (conn == NULL || request_key_ptr == NULL) return NULL;

    char* cursor = request_key_ptr;
    while (*cursor != '=' && *cursor != '&' && *cursor != ' ' && *cursor != '\0' && *cursor != '\r' && *cursor != '\n')
        cursor++;

    if (*cursor != '=')
        return NULL;

    char* value_start = cursor + 1;

    if (value_size != NULL)
    {
        char* value_end = value_start;
        while (*value_end != '&' && *value_end != ' ' && *value_end != '\0' && 
               *value_end != '\r' && *value_end != '\n')
            value_end++;
        
        *value_size = (uint32_t)(value_end - value_start);
    }

    return value_start;
}
