/*
 * flash.c
 *
 *  Created on: Aug 7, 2025
 *      Author: kikkiu
 */

#include "flash.h"
#include <string.h>

SaveData_t savedata;

void FLASH_EraseLastPage()
{
	FLASH_EraseInitTypeDef erase_structure;
	erase_structure.TypeErase = FLASH_TYPEERASE_PAGES;
	erase_structure.Banks = FLASH_BANK_1;
	erase_structure.Page = FLASH_PAGE_NB - 1;	// last page
	erase_structure.NbPages = 1;
	uint32_t page_error = 0;
	HAL_FLASHEx_Erase(&erase_structure, &page_error);
}

void FLASH_WriteBuffer(uint8_t* buf, uint32_t size)
{
	uint32_t total_flash_data_blocks = size / FLASH_DATASIZE;
	if (size % FLASH_DATASIZE != 0)
		total_flash_data_blocks++;

	uint8_t flash_data[FLASH_DATASIZE];	// can be half word, word, double word (2, 4, 8 bytes)

	for (uint32_t flash_data_i = 0; flash_data_i < total_flash_data_blocks; flash_data_i++)
	{
		for (uint8_t byte_i = flash_data_i * FLASH_DATASIZE; byte_i < flash_data_i * FLASH_DATASIZE + FLASH_DATASIZE; byte_i++)
			flash_data[byte_i % FLASH_DATASIZE] = (byte_i < size) ? *(buf + byte_i) : 0x00;

		FLASH_DATATYPE serialized_flash_data = *((FLASH_DATATYPE*)flash_data);
		HAL_FLASH_Program(FLASH_TYPEPROGRAM_DOUBLEWORD, LAST_PAGE_ADDRESS + flash_data_i * FLASH_DATASIZE, serialized_flash_data);
	}
}

void FLASH_WriteSaveData()
{
	HAL_StatusTypeDef unlocked = HAL_FLASH_Unlock();
	FLASH_EraseLastPage();
	FLASH_WriteBuffer((uint8_t*)&savedata, sizeof(SaveData_t));
	HAL_StatusTypeDef locked = HAL_FLASH_Lock();
	unlocked = locked;
}

void FLASH_ReadSaveData()
{
	uint32_t read_addr = LAST_PAGE_ADDRESS;
	memcpy(&savedata, ((SaveData_t*)read_addr), sizeof(SaveData_t));
}

