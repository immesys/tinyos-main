/* 
 * Copyright (c) 2014, The Regents of the University of California.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 * - Neither the name of the copyright holders nor the names of its
 *   contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
 * OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
 * WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

/**
 * Generic module representing a peripheral clock.
 *
 * @author Michael Andersen <m.andersen@cs.berkeley.edu>
 */

#include "sam4lpmhardware.h"

generic module HplSam4PeripheralClockP (uint32_t offset, uint8_t bit) @safe()
{
    provides
    {
        interface HplSam4PeripheralClockCntl as Cntl;
    }
}

implementation
{
    async command void Cntl.enable()
    {
        uint32_t shadow = *((uint32_t volatile *)((void volatile *)PM + offset));
        shadow |= 1<<bit;
        PM->unlock = PM_UNLOCK_KEY | offset;
        *((uint32_t volatile *)((void volatile *)PM + offset)) = shadow;
    }

    async command void Cntl.disable()
    {
        uint32_t shadow = *((uint32_t volatile *)((void volatile *)PM + offset));
        shadow &= ~(1<<bit);
        PM->unlock = PM_UNLOCK_KEY | offset;
        *((uint32_t volatile *)((void volatile *)PM + offset)) = shadow;
    }

    async command bool Cntl.status()
    {
        if ( *((uint32_t volatile *)((void volatile *)PM + offset)) & (1<<bit) )
            return TRUE;
        else
            return FALSE;
    }
}
