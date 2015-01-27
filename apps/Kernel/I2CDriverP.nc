#include "driver.h"
module I2CDriverP
{
    provides interface Driver;
    provides interface Init;
    uses interface HplSam4lTWIM[uint8_t id];
}
implementation
{

    enum {
        FLAG_DOSTART = 0x01,
        FLAG_DORSTART = 0x01,
        FLAG_ACKLAST = 0x02,
        FLAG_DOSTOP = 0x04
    };

    simple_callback_t callback[2];
    uint8_t done[2];

    command error_t Init.init()
    {
        return SUCCESS;
    }
    //address byte 1 is the I2C channel, can be 1 (ex i2c) or 2 (internal)
    async command syscall_rv_t Driver.syscall_ex(
        uint32_t number, uint32_t arg0,
        uint32_t arg1, uint32_t arg2,
        uint32_t *argx)
    {
        switch(number & 0xFF)
        {
                       //      ar0   arg1    arg2     arx[0], argx[1]   argx[2]
            case 0x01: //read(addr, flags, destbuffer,   len, callback, r)
            {
                error_t rv;
                uint8_t chan = arg0>>8;
                if (chan < 1 || chan > 2)
                    return -1;
                if (callback[chan-1].addr != 0)
                    return -1;
                callback[chan-1].addr = argx[1];
                callback[chan-1].r = (void*)argx[2];
                rv = call HplSam4lTWIM.read[chan] (arg1, arg0 & 0xFF, (uint8_t*)arg2, argx[0]);
                if (rv != SUCCESS)
                {
                    callback[chan-1].addr = 0;
                    return -1;
                }
                return 0;
            }
            break;
            case 0x02: //write(addr, flags, srcbuffer,   len, callback, r)
            {
                error_t rv;
                uint8_t chan = arg0>>8;
                if (chan < 1 || chan > 2)
                    return -1;
                if (callback[chan-1].addr != 0)
                    return -1;
                callback[chan-1].addr = argx[1];
                callback[chan-1].r = (void*) argx[2];
                rv = call HplSam4lTWIM.write[chan] (arg1, arg0 & 0xFF, (uint8_t*)arg2, argx[0]);
                if (rv != SUCCESS)
                {
                    callback[chan-1].addr = 0;
                    return -1;
                }
                return 0;
            }
            break;
        }
    }
    int seekidx;
    command driver_callback_t Driver.peek_callback()
    {
        for (seekidx=0;seekidx<2;seekidx++)
        {
            if (done[seekidx]) return &callback[seekidx];
        }
    }
    command void Driver.pop_callback()
    {
        done[seekidx] = 0;
        callback[seekidx].addr = 0;
    }

    async event void HplSam4lTWIM.writeDone[uint8_t id](error_t stats, uint8_t *buf)
    {
        done[id-1] = 1;
    }
    async event void HplSam4lTWIM.readDone[uint8_t id](error_t stat, uint8_t *buf)
    {
        done[id-1] = 1;
    }
}