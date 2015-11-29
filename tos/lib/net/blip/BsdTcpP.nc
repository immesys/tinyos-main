#define NUMBSDTCPSOCKETS 1

module BsdTcpP {

    provides {
        interface BSDTCPActiveSocket[uint8_t asockid];
        interface BSDTCPPassiveSocket[uint8_t psockid];
    } uses {
        interface Boot;
        interface IP;
        interface IPAddress;
        interface Timer<TMilli>[uint8_t timerid];
        interface Timer<TMilli> as TickTimer;
    }
    
} implementation {
#include <bsdtcp/cbuf.h>
#include <bsdtcp/tcp_var.h>

    uint32_t get_ticks();
    void send_message(struct tcpcb* tp, struct ip6_packet* msg, struct tcphdr* th, uint32_t tlen);
    void set_timer(struct tcpcb* tcb, uint8_t timer_id, uint32_t delay);
    
#include <bsdtcp/tcp_subr.c>
#include <bsdtcp/tcp_output.c>
#include <bsdtcp/tcp_input.c>
#include <bsdtcp/tcp_timer.c>
#include <bsdtcp/tcp_timewait.c>
#include <bsdtcp/tcp_usrreq.c>
#include <bsdtcp/checksum.c>
    
    struct tcpcb tcbs[1];
    uint32_t ticks = 0;
    
    event void Boot.booted() {
        tcp_init();
        initialize_tcb(&tcbs[0]);
        tcbs[0].index = 0;
        call TickTimer.startPeriodic(500);
    }
    
    event void TickTimer.fired() {
        ticks++;
    }
    
    event void Timer.fired[uint8_t timer_id]() {
        struct tcpcb* tp;
        if (call Timer.isRunning[timer_id]()) {
            // In case the timer was rescheduled after this was posted but before this runs
            return;
        }
        printf("Timer %d fired!\n", timer_id);
        
        tp = &tcbs[timer_id >> 2];
        timer_id &= 0x3;
        
        switch(timer_id) {
        case TOS_REXMT:
            printf("Retransmit\n");
		    tcp_timer_rexmt(tp);
		    break;
	    case TOS_PERSIST:
	        printf("Persist\n");
	        tcp_timer_persist(tp);
		    break;
	    case TOS_KEEP:
	        printf("Keep\n");
	        tcp_timer_keep(tp);
		    break;
	    case TOS_2MSL:
	        printf("2MSL\n");
	        tcp_timer_2msl(tp);
		    break;
        }
    }
    
    event void IP.recv(struct ip6_hdr* iph, void* packet, size_t len,
                       struct ip6_metadata* meta) {
        // This is only being called if the IP address matches mine.
        // Match this to a TCP socket
        int i;
        struct tcphdr* th;
        uint16_t port;
        struct tcpcb* tcb;
        th = (struct tcphdr*) packet;
        port = ntohs(th->th_dport);
        for (i = 0; i < NUMBSDTCPSOCKETS; i++) {
            tcb = &tcbs[i];
            if (tcb->t_state != TCP6S_CLOSED && port == ntohs(tcb->lport)) {
                // Matches this socket
                if (get_checksum(&iph->ip6_src, &iph->ip6_dst, th, len)) {
                    printf("Dropping packet: bad checksum\n");
                } else {
                    tcp_input(iph, (struct tcphdr*) packet, &tcbs[i]);
                }
                break;
            }
        }
    }
    
    event void IPAddress.changed(bool valid) {
    }
    
    command int BSDTCPActiveSocket.getID[uint8_t asockid]() {
        return tcbs[asockid].index;
    }
    
    command error_t BSDTCPActiveSocket.bind[uint8_t asockid](uint16_t port) {
        tcbs[asockid].lport = htons(port);
        return SUCCESS;
    }
    
    command error_t BSDTCPPassiveSocket.bind[uint8_t psockid](uint16_t port) {
        return SUCCESS;
    }
    
    command void BSDTCPPassiveSocket.listen[uint8_t psockid]() {
    }
    
    command error_t BSDTCPPassiveSocket.accept[uint8_t psockid](struct sockaddr_in6* addr, int activesockid) {
        return SUCCESS;
    }
    
    command error_t BSDTCPActiveSocket.connect[uint8_t asockid](struct sockaddr_in6* addr) {
        struct tcpcb* tp = &tcbs[asockid];
        return tcp6_usr_connect(tp, addr);
    }
    
    command error_t BSDTCPActiveSocket.send[uint8_t asockid](uint8_t* data, uint8_t length) {
        return SUCCESS;
    }
    
    command uint8_t BSDTCPActiveSocket.receive[uint8_t asockid](uint8_t* buffer, uint8_t len) {
        return 0;
    }
    
    command error_t BSDTCPActiveSocket.close[uint8_t asockid]() {
    	return SUCCESS;
    }
    
    command error_t BSDTCPPassiveSocket.close[uint8_t psockid]() {
        return SUCCESS;
    }
    
    command error_t BSDTCPActiveSocket.abort[uint8_t asockid]() {
        return SUCCESS;
    }

    /* Wrapper for underlying C code. */
    void send_message(struct tcpcb* tp, struct ip6_packet* msg, struct tcphdr* th, uint32_t tlen) {
        call IPAddress.setSource(&msg->ip6_hdr);
        th->th_sum = get_checksum(&msg->ip6_hdr.ip6_src, &msg->ip6_hdr.ip6_dst, th, tlen);
        call IP.send(msg);
    }
    
    uint32_t get_ticks() {
        return ticks;
    }
    
    void set_timer(struct tcpcb* tcb, uint8_t timer_id, uint32_t delay) {
        uint8_t tcb_index = (uint8_t) tcb->index;
        uint8_t timer_index = (tcb_index << 2) & timer_id;
        if (timer_index > 0x3) {
            printf("WARNING: setting out of bounds timer!\n");
        }
        call Timer.startOneShot[timer_index](delay);
    }
}