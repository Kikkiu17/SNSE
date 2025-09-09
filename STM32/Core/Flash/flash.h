/*
 * flash.h
 *
 *  Created on: Aug 7, 2025
 *      Author: kikkiu
 */

#ifndef FLASH_FLASH_H_
#define FLASH_FLASH_H_

#include "stm32g0xx_hal.h"
#include "../settings.h"

void FLASH_EraseLastPage();
void FLASH_WriteBuffer(uint8_t* buf, uint32_t size);
void FLASH_WriteSaveData();
void FLASH_ReadSaveData();

#endif /* FLASH_FLASH_H_ */
