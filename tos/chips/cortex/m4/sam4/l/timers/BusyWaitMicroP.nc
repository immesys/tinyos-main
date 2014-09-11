
module BusyWaitMicroP
{
    provides interface BusyWait<TMicro, uint16_t>;
    uses interface HplSam4Clock;
}
implementation
{
    async command void BusyWait.wait(uint16_t m)
    {
        uint32_t then = call HplSam4Clock.getSysTicks();
        uint32_t req_ticks = m;
        int32_t tgt;
        //multiply required microseconds by number of ticks per ms
        req_ticks *= call HplSam4Clock.getMainClockSpeed();
        //but we want ticks per microsecond
        req_ticks /= 1000;
        tgt = (int32_t)then - req_ticks;
        if (tgt < 0)
        {
            tgt += 0xFFFFFF;
            while(call HplSam4Clock.getSysTicks() >= 0);
        }
        while(call HplSam4Clock.getSysTicks() > tgt);
    }

    async event void HplSam4Clock.mainClockChanged() {}
}