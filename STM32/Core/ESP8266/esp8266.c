/*
 * esp8266.c
 *
 *  Created on: Apr 6, 2025
 *      Author: Kikkiu
 */

#include "esp8266.h"
#include <string.h>
#include <inttypes.h>
#include <stdio.h>
#include <time.h>

char uart_buffer[UART_BUFFER_SIZE];
bool WIFI_response_sent = false;

void WIFI_ResetComm(WIFI_t* wifi, Connection_t* conn)
{
	ESP8266_ClearBuffer();
	memset(wifi->buf, 0, WIFI_BUF_MAX_SIZE);
	memset(conn->request, 0, REQUEST_MAX_SIZE);
	memset(conn->response_buffer, 0, RESPONSE_MAX_SIZE);
}

int32_t bufferToInt(char* buf, uint32_t size)
{
	if (buf == NULL) return 0;
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

		if (strstr(uart_buffer, "ERR") != NULL)
		{
			ESP8266_ClearBuffer();
			return ERR;
		}

		if (strstr(uart_buffer + (UART_BUFFER_SIZE - UART_DMA_CHANNEL->CNDTR) + offset, str) == NULL) continue;

		ESP8266_ClearBuffer();
		return OK;
	}

	if (strstr(uart_buffer, "ERROR")) return ERR;

	return TIMEOUT;
}

Response_t ESP8266_WaitForString(char* str, uint32_t timeout)
{
	if (str == NULL) return NULVAL;
	for (uint32_t i = 0; i < timeout; i++)
	{
		HAL_Delay(1);

		if (strstr(uart_buffer, "ERR") != NULL)
		{
			ESP8266_ClearBuffer();
			return ERR;
		}

		if (strstr(uart_buffer, str) == NULL) continue;

		ESP8266_ClearBuffer();
		return OK;
	}

	if (strstr(uart_buffer, "ERROR")) return ERR;

	return TIMEOUT;
}

Response_t ESP8266_WaitKeepString(char* str, uint32_t timeout)
{
	if (str == NULL) return NULVAL;
	for (uint32_t i = 0; i < timeout; i++)
	{
		HAL_Delay(1);
		char* ptr = strstr(uart_buffer, str);
		if (ptr == NULL) continue;

		// add string terminator so we can use strlen later
		if (ptr - uart_buffer + 4 < UART_BUFFER_SIZE)
			*(ptr + 4) = '\0';
		return OK;
	}

	if (strstr(uart_buffer, "ERROR")) return ERR;

	return TIMEOUT;
}

HAL_StatusTypeDef ESP8266_SendATCommandNoResponse(char* cmd, size_t size, uint32_t timeout)
{
	if (cmd == NULL) return NULVAL;
	return HAL_UART_Transmit(&STM_UART, (uint8_t*)cmd, size, UART_TX_TIMEOUT);
}

Response_t ESP8266_SendATCommandResponse(char* cmd, size_t size, uint32_t timeout)
{
	if (cmd == NULL) return NULVAL;
	ESP8266_ClearBuffer();
	if (HAL_UART_Transmit(&STM_UART, (uint8_t*)cmd, size, UART_TX_TIMEOUT) != HAL_OK)
		return ERR;
	Response_t resp = ESP8266_WaitForString("OK", timeout);
	if (resp != ERR && resp != TIMEOUT)
		return OK;
	return resp;
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

HAL_StatusTypeDef ESP8266_SendATCommandKeepStringNoResponse(char* cmd, size_t size)
{
	if (cmd == NULL) return NULVAL;
	ESP8266_ClearBuffer();
	if (HAL_UART_Transmit(&STM_UART, (uint8_t*)cmd, size, UART_TX_TIMEOUT) != HAL_OK)
		return ERR;
	return HAL_OK;
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
	UART_DMA_CHANNEL->CCR &= 0x7FFE;				// disable DMA
	UART_DMA_CHANNEL->CNDTR = UART_BUFFER_SIZE;	// reset CNDTR so DMA starts writing from index 0
	UART_DMA_CHANNEL->CCR |= 0x01;					// enable DMA
	// initalize buffer to 255 so if there is a string in the buffer with a certain offset from
	// the start of the buffer, and there are some bytes 0 at the beginning, strstr can find
	// the desired string (doesn't return a pointer to the first item)
	// buf = {0, 0, 's', 't, 'r,' 'i', 'n', 'g'} -> strstr(buf, "string") would return buf[0]
	memset(uart_buffer, 0, UART_BUFFER_SIZE);
}

char* ESP8266_GetBuffer(void)
{
	return uart_buffer;
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
		// hardware reset
		HAL_GPIO_WritePin(ESPRST_GPIO_Port, ESPRST_Pin, 0);
		HAL_Delay(1);
		HAL_GPIO_WritePin(ESPRST_GPIO_Port, ESPRST_Pin, 1);

		HAL_GPIO_TogglePin(STATUS_Port, STATUS_Pin);
		start_ok = ESP8266_WaitForStringCNDTROffset("ready", -10, 5000);
		HAL_GPIO_TogglePin(STATUS_Port, STATUS_Pin);
		__HAL_UART_CLEAR_OREFLAG(&huart1);	// clear overrun flag caused by esp reset
		ESP8266_ClearBuffer();
	}

	HAL_GPIO_TogglePin(STATUS_Port, STATUS_Pin);
	// wait for WiFi
	if (ESP8266_WaitForStringCNDTROffset("WIFI CONNECTED", -20, 6000) == OK)
		ESP8266_WaitForStringCNDTROffset("WIFI GOT IP", -15, 18000);
	HAL_GPIO_TogglePin(STATUS_Port, STATUS_Pin);

	return start_ok;
}

Response_t ESP8266_ATReset(void)
{
	Response_t resp = ESP8266_SendATCommandResponse("AT+RST\r\n", 8, AT_SHORT_TIMEOUT);
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

	//ptr = strstr(uart_buffer, "+CIFSR:STAIP");
	//				v
	// +CIFSR:STAIP,"nnn.nnn.nnn.nnn"\r\n
	char* ptr = strstr(uart_buffer, "\"");
	if (ptr == NULL) return ERR;

	uint32_t IP_start_index = (ptr + 1) - uart_buffer;

	//								v
	// +CIFSR:STAIP,"nnn.nnn.nnn.nnn"\r\n
	ptr = strstr(uart_buffer, "\"\r\n");
	if (ptr == NULL) return ERR;

	uint32_t IP_end_index = (ptr - 1) - uart_buffer;
	if (IP_end_index < IP_start_index) return ERR;

	uint32_t IP_size = IP_end_index - IP_start_index + 1;
	if (IP_size > WIFI_BUF_MAX_SIZE) return ERR;

	memcpy(wifi->IP, uart_buffer + IP_start_index, IP_size);
	return OK;
}

Response_t WIFI_GetConnectionInfo(WIFI_t* wifi)
{
	if (wifi == NULL) return NULVAL;
	char* ptr = strstr(uart_buffer, "+CWJAP:");
	if (ptr == NULL) return ERR;	// unknown response

	// ESP is already connected do WiFi
	// get WiFi SSID

	//		   v
	// +CWJAP:"xxxxxxxxxxxx","xx:xx:xx:xx:xx:xx",x,-x,x
	uint32_t SSID_start_index = (ptr + 8) - uart_buffer;

	// get ESP SSID
	// response structure:
	// +CWJAP:"xxxxxxxxxxxx","xx:xx:xx:xx:xx:xx",x,-x,x

	//					   v
	// +CWJAP:"xxxxxxxxxxxx","xx:xx:xx:xx:xx:xx",x,-x,x
	ptr = strstr(uart_buffer, "\",\"");	// ptr -1 is the end index of the SSID
	if (ptr == NULL) return ERR;

	uint32_t SSID_end_index = (ptr - 1) - uart_buffer;
	if (SSID_end_index < SSID_start_index) return ERR;

	uint32_t SSID_size = SSID_end_index - SSID_start_index + 1;
	if (SSID_size > sizeof(wifi->SSID)) return ERR;

	memcpy(wifi->SSID, uart_buffer + SSID_start_index, SSID_size);

	if (WIFI_GetIP(wifi) != OK) return ERR;

	return WIFI_GetHostname(wifi);
}

Response_t WIFI_Connect(WIFI_t* wifi)
{
	if (wifi == NULL) return NULVAL;
	Response_t result = ERR;
	result = ESP8266_SendATCommandKeepString("AT+CWJAP?\r\n", 11, AT_SHORT_TIMEOUT);

	if (result != OK) return result;

	// check if the ESP is already connected to WiFi
	if (strstr(uart_buffer, "No AP") != NULL)
	{
		// ESP is not connected
		// connect the ESP to WiFi

		sprintf(wifi->buf, "AT+CWJAP=\"%s\",\"%s\"\r\n", wifi->SSID, wifi->pw);
		return ESP8266_SendATCommandResponse(wifi->buf, strlen(wifi->buf), 15000);
	}
	else
		return WIFI_GetConnectionInfo(wifi);

	return result;	// ERR
}

Response_t WIFI_SetCWMODE(uint8_t mode)
{
	if (mode > 3) return ERR;

	char cwmode[14];
	sprintf(cwmode, "AT+CWMODE=%d\r\n", mode);
	return ESP8266_SendATCommandResponse(cwmode, 13, AT_SHORT_TIMEOUT);
}

Response_t WIFI_SetCIPMUX(uint8_t mux)
{
	if (mux > 1) return ERR;

	char cipmux[14];
	sprintf(cipmux, "AT+CIPMUX=%d\r\n", mux);
	return ESP8266_SendATCommandResponse(cipmux, 13, AT_SHORT_TIMEOUT);
}

Response_t WIFI_SetCIPSERVER(uint16_t server_port)
{
	// for some reason ESP AT doesn't receive connections if the server port is 80
	if (server_port < 1 || server_port > 65535 || server_port == 80)
		return ERR;

	char cipserver[50];
	sprintf(cipserver, "AT+CIPSERVER=1,%d\r\n", server_port);
	return ESP8266_SendATCommandResponse(cipserver, strlen(cipserver), AT_SHORT_TIMEOUT);
}

Response_t WIFI_SetHostname(WIFI_t* wifi, char* hostname)
{
	if (wifi == NULL || hostname == NULL) return NULVAL;
	uint32_t hostname_size = strlen(hostname);
	char hostnamestr[18 + hostname_size];
	sprintf(hostnamestr, "AT+CWHOSTNAME=\"%s\"\r\n", hostname);
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
	char* ptr = strstr(uart_buffer, "+CWHOSTNAME:");
	if (ptr == NULL) return ERR;
	//			   v
	// +CWHOSTNAME:ESP-A0ADE6\r\n
	char* hostname_start_p = ptr + 12;
	ptr = strstr(hostname_start_p, "\r\n");
	if (ptr == NULL) return ERR;
	char* hostname_end_p = ptr - 1;

	uint32_t hostname_size = hostname_end_p - hostname_start_p;
	if (hostname_size > HOSTNAME_MAX_SIZE) return ERR;

	memset(wifi->hostname, 0, HOSTNAME_MAX_SIZE);
	memcpy(wifi->hostname, hostname_start_p, hostname_size);

	return OK;
}

// also saves the name in FLASH memory
Response_t WIFI_SetName(WIFI_t* wifi, char* name)
{
	if (wifi == NULL) return ERR;
	if (name == NULL) return NULVAL;
	if (name[0] == 0) return ERR;

	uint32_t name_size = strlen(name);
	if (name_size > NAME_MAX_SIZE)
		name_size = NAME_MAX_SIZE;
	else
	{
		memset(wifi->name + name_size, 0, NAME_MAX_SIZE);
		memset(savedata.name + name_size, 0, NAME_MAX_SIZE);
	}

	memcpy(savedata.name, name, name_size);
	memcpy(wifi->name, name, name_size);

	return OK;
}

Response_t WIFI_SetIP(WIFI_t* wifi, char* ip)
{
	if (wifi == NULL || ip == NULL) return ERR;

	uint32_t ip_length = strlen(ip);
	// 255.255.255.255
	if (ip_length > 15) return ERR;

	memset(wifi->buf, 0, WIFI_BUF_MAX_SIZE);
	sprintf(wifi->buf, "AT+CIPSTA=\"%s\"\r\n", ip);
	Response_t atstatus = ESP8266_SendATCommandResponse(wifi->buf, strlen(wifi->buf), AT_SHORT_TIMEOUT);
	if (atstatus != OK) return atstatus;
	HAL_GPIO_WritePin(STATUS_Port, STATUS_Pin, 1);
	return WIFI_GetIP(wifi); // get the IP of the ESP to verify its change
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
			if ((ipd_ptr = strstr(uart_buffer + 1, "+IPD,")) != NULL) break;
		}
		else
		{
			/**
			 * if the first element of the buffer is not 0x00, check for an incoming connection
			 * from the start
			 */
			if ((ipd_ptr = strstr(uart_buffer, "+IPD,")) != NULL) break;
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
	ptr = strstr(uart_buffer, ":");
	if (ptr == NULL) return ERR;

	//			v
	// +IPD,n,m:GET ?xxxxxxxxxx
	// +IPD,n,m:POST ?xxxxxxxxxx
	conn->request_type = *(ptr + 1);

	//				v
	// +IPD,n,m:GET ?xxxxxxxxxx
	ptr = strstr(uart_buffer, "?");
	if (ptr == NULL)
	{
		//				v
		// +IPD,n,m:GET /xxxxxxxxxx
		ptr = strstr(uart_buffer, "/");
		if (ptr == NULL) return ERR;
	}

	//				 v
	// +IPD,n,m:GET ?xxxxxxxxxx
	uint32_t request_body_start_index = (ptr + 1) - uart_buffer;

	// get the request size
	uint32_t request_size;
	ptr = strstr(uart_buffer, " HTTP");
	if (ptr == NULL)
	{
		// if there is no HTTP/x.x use the message size m (at ptr + 7)
		// +IPD,n,m:GET ?xxxxxxxxxx
		request_size = expected_size;
		uint32_t request_start_index;
		if ((ptr = strstr(uart_buffer, ":")) == NULL) return ERR;
		// this removes the "POST " (or "GET ") part
		// get the size of the message received until "POST ", then remove
		// the size of "+IPD,n,m:" to get the size of "POST "
		request_start_index = ptr - uart_buffer;
		request_size = request_size - (request_body_start_index - request_start_index) + 1;
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
	memcpy(conn->request, uart_buffer + request_body_start_index, request_size);
	ESP8266_ClearBuffer();
	return OK;
}

Response_t WIFI_SendResponse(Connection_t* conn, char* status_code, char* body, uint32_t body_length)
{
	if (conn == NULL || status_code == NULL || body == NULL) return NULVAL;
	if (body_length > RESPONSE_MAX_SIZE) return ERR;
	Response_t atstatus = ERR;

	// calculate width in characters of the body length and connection number
	memset(conn->response_buffer, 0, RESPONSE_MAX_SIZE);
	sprintf(conn->response_buffer, "%d", conn->connection_number);
	uint32_t connection_number_width = strlen(conn->response_buffer);
	uint32_t status_code_width = strlen(status_code);

	// get length of the entire TCP packet
	uint32_t total_response_length = 1 + status_code_width + body_length + 2;	// the last 2 are \r\n as delimiter for the response
	if (total_response_length > RESPONSE_MAX_SIZE) return ERR;

	// get width in characters of the response length
	memset(conn->response_buffer, 0, RESPONSE_MAX_SIZE);
	sprintf(conn->response_buffer, "%" PRIu32, total_response_length);
	uint32_t total_response_length_width = strlen(conn->response_buffer);

	// get length of the AT command
	uint32_t cipsend_length = 14 + connection_number_width + total_response_length_width;
	if (cipsend_length > RESPONSE_MAX_SIZE) return ERR;

	sprintf(conn->response_buffer, "AT+CIPSEND=%d,%" PRIu32 "\r\n", conn->connection_number, total_response_length);
	ESP8266_SendATCommandKeepStringNoResponse(conn->response_buffer, cipsend_length);

	if (ESP8266_WaitForString("busy", 6) == OK)
	{
		if (ESP8266_WaitForString("SEND OK", 100) == TIMEOUT) return ERR;
		if (ESP8266_WaitForString(">", 100) == TIMEOUT) return ERR;
	}

	if (body_length < RESPONSE_MAX_SIZE)
		body[body_length] = '\0';

	memset(conn->response_buffer, 0, RESPONSE_MAX_SIZE);
	sprintf(conn->response_buffer, "%s\n%s\r\n", status_code, body);
	HAL_UART_Transmit(&STM_UART, (uint8_t*)conn->response_buffer, total_response_length, UART_TX_TIMEOUT);

	if (ESP8266_WaitForString("Recv", AT_SHORT_TIMEOUT) == TIMEOUT)
	{
		// retry
		HAL_UART_Transmit(&STM_UART, (uint8_t*)conn->response_buffer, total_response_length, UART_TX_TIMEOUT);
	}

	WIFI_response_sent = true;

	return atstatus;
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

Response_t WIFI_GetTime(WIFI_t* wifi)
{
	if (wifi == NULL) return NULVAL;

	Response_t atstatus = ERR;
	atstatus = ESP8266_SendATCommandKeepString("AT+CIPSNTPTIME?\r\n", 18, AT_SHORT_TIMEOUT);
	if (atstatus != OK) return atstatus;

	char* start_ptr = NULL;
	if ((start_ptr = strstr(uart_buffer, "+CIPSNTPTIME:")) != NULL)
	{
		// +CIPSNTPTIME:Fri Apr 11 21:52:47 2025\r\nOK

		//						v v
		// +CIPSNTPTIME:Fri Apr 11 21:52:47 2025\r\nOK
		char* time_start_ptr = strstr(start_ptr + 21, " ");
		if (time_start_ptr == NULL) return ERR;
		time_start_ptr += 1;

		memcpy(wifi->time, time_start_ptr, 8);
		wifi->last_time_read = uwTick;
	}
	else return ERR;

	return atstatus;
}

uint32_t WIFI_GetTimeHour(WIFI_t* wifi)
{
	if (wifi == NULL) return 0;
	if (uwTick - wifi->last_time_read > 1000) WIFI_GetTime(wifi);	// avoids too many slow reads
	return bufferToInt(wifi->time, 2);
}

uint32_t WIFI_GetTimeMinutes(WIFI_t* wifi)
{
	if (wifi == NULL) return 0;
	if (uwTick - wifi->last_time_read > 1000) WIFI_GetTime(wifi);	// avoids too many slow reads
	return bufferToInt(wifi->time + 3, 2);
}

uint32_t WIFI_GetTimeSeconds(WIFI_t* wifi)
{
	if (wifi == NULL) return 0;
	if (uwTick - wifi->last_time_read > 1000) WIFI_GetTime(wifi);	// avoids too many slow reads
	return bufferToInt(wifi->time + 6, 2);
}

Response_t WIFI_EnableNTPServer(WIFI_t* wifi, int8_t time_offset)
{
	if (wifi == NULL) return NULVAL;

	Response_t atstatus = ERR;
	if ((atstatus = ESP8266_SendATCommandKeepString("AT+CIPSNTPCFG?\r\n", 17, AT_SHORT_TIMEOUT)) != OK) return atstatus;

	char* ptr = NULL;
	if ((ptr = strstr(uart_buffer, "+CIPSNTPCFG:")) != NULL)
	{
		uint8_t ntp_enabled = *(ptr + 12) - '0';
		if (ntp_enabled)
			return OK;

		// enable NTP server
		sprintf(wifi->buf, "AT+CIPSNTPCFG=1,%d\r\n", time_offset);
		uint8_t tsize = (time_offset < 0) ? 2 : 1;
		return ESP8266_SendATCommandResponse(wifi->buf, 19 + tsize, AT_SHORT_TIMEOUT);
	}

	return ERR;
}

char* WIFI_RequestHasKey(Connection_t* conn, char* desired_key)
{
	if (conn == NULL || desired_key == NULL) return NULL;

	char* parameter_end_ptr = strstr(conn->request, "&");
	/**
	 * example:
	 * key_start:	  v
	 * request: POST ?name=custom_name
	 */
	char* key_start = conn->request;

	if (parameter_end_ptr == NULL)
	{
		// there could be only one key

		// check if there is a value
		char* key_end_ptr = strstr(conn->request, "=");
		if (key_end_ptr == NULL)
		{
			// if there is no value, only the key is present or not
			char* desired_key_ptr = strstr(conn->request, desired_key);
			// if the key is ?xxxkey, it shouldn't return; it should only return cases like ?key
			if (desired_key_ptr == key_start)
				return desired_key_ptr;
		}
		else
		{
			// there is a value
			*key_end_ptr = '\0';	// limits the search to the key before the value
			char* desired_key_ptr = strstr(conn->request, desired_key);
			*key_end_ptr = '=';
			// if the key is ?xxxkey, it shouldn't return; it should only return cases like ?key
			if (desired_key_ptr == key_start)
				return desired_key_ptr;
		}
	}
	else
	{
		// there are multiple keys
		while (key_start != NULL)
		{
			if (parameter_end_ptr != NULL)
				*parameter_end_ptr = '\0';	// limits the search to the first parameter
			char* key_end_ptr = strstr(key_start, "=");	// checks if there is a value
			if (key_end_ptr == NULL)
			{
				// there is no value
				char* desired_key_ptr = strstr(key_start, desired_key);
				if (parameter_end_ptr != NULL)
					*parameter_end_ptr = '&';
				if (desired_key_ptr != NULL)
				{
					// key is found
					if (desired_key_ptr == key_start)
						return desired_key_ptr;
					return desired_key_ptr;
				}
			}
			else
			{
				// there is a value
				*key_end_ptr = '\0';	// limits the search to the key before the value
				char* desired_key_ptr = strstr(key_start, desired_key);
				*key_end_ptr = '=';
				if (parameter_end_ptr != NULL)
					*parameter_end_ptr = '&';
				if (desired_key_ptr != NULL)
				{
					// key is found
					if (desired_key_ptr == key_start)
						return desired_key_ptr;
					return desired_key_ptr;
				}
			}

			// parameter_end_ptr has already been set to '&', no need to do it again
			if (parameter_end_ptr != NULL)
				key_start = parameter_end_ptr + 1;
			else
				key_start = NULL;
			// no key is found in this parameter, go to the next one
			parameter_end_ptr = strstr(parameter_end_ptr + 1, "&");	// begin search from current parameter
		}
	}

	// no key is found
	return NULL;
}

char* WIFI_RequestKeyHasValue(Connection_t* conn, char* request_key_ptr, char* value)
{
	if (conn == NULL || request_key_ptr == NULL || value == NULL) return NULL;

	char* parameter_end_ptr = strstr(request_key_ptr, "&");
	if (parameter_end_ptr != NULL)
		*parameter_end_ptr = '\0';

	char* key_end_ptr = strstr(request_key_ptr, "=");

	if (parameter_end_ptr != NULL)
		*parameter_end_ptr = '&';

	if (key_end_ptr == NULL)
	{
		// there is no value
		return NULL;
	}
	else
	{
		if (key_end_ptr - conn->request >= RESPONSE_MAX_SIZE - 2) return NULL;
		char* value_ptr = strstr(request_key_ptr, value);
		if (value_ptr != NULL)
		{
			// rules out non-exact matches
			if (parameter_end_ptr != NULL)
			{
				if (parameter_end_ptr - value_ptr > strlen(value))
					return NULL;
			}
			else
			{
				if (strlen(request_key_ptr) - (key_end_ptr + 1 - request_key_ptr + 1) + 1 > strlen(value))
					return NULL;
			}
		}

		return value_ptr;
	}
}

char* WIFI_GetKeyValue(Connection_t* conn, char* request_key_ptr, uint32_t* value_size)
{
	if (conn == NULL || request_key_ptr == NULL) return NULL;

	char* parameter_end_ptr = strstr(request_key_ptr, "&");
	if (parameter_end_ptr != NULL)
		*parameter_end_ptr = '\0';

	char* key_end_ptr = strstr(request_key_ptr, "=");

	if (parameter_end_ptr != NULL)
		*parameter_end_ptr = '&';

	if (key_end_ptr == NULL)
	{
		// there is no value
		return NULL;
	}
	else
	{
		if (key_end_ptr - conn->request >= RESPONSE_MAX_SIZE - 2) return NULL;

		if (value_size != NULL)
		{
			if (parameter_end_ptr != NULL)
				*value_size = parameter_end_ptr - (key_end_ptr + 1);
			else
			{
				uint32_t str_len = strlen(request_key_ptr);
				if (str_len)
					*value_size = str_len - (key_end_ptr + 1 - request_key_ptr);
				else
					*value_size = 0;
			}
		}

		return key_end_ptr + 1;
	}
}
