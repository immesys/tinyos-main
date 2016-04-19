#include <lib6lowpan/ip.h>

configuration SERPRoutingEngineC {
    provides {
        interface RootControl;
        interface StdControl as SERPControl;
        //interface SERPRoutingEngine;
    } uses {
        interface NeighborDiscovery;
    }
}

implementation {
    components MainC;
    components RandomC;
    components IPStackC;
    components new TimerMilliC() as TrickleTimer;
    components new TimerMilliC() as PrintTimer;
    components new TimerMilliC() as RouterAdvMeshAnnTimer;
    components IPAddressC, Ieee154AddressC;
    components IPNeighborDiscoveryC;

   // components new ICMPCodeDispatchC(ICMP_TYPE_SERP_CONTROL) as ICMP_RS;
    components new ICMPCodeDispatchC(ICMP_TYPE_ROUTER_SOL) as ICMP_RS;
    components new ICMPCodeDispatchC(ICMP_TYPE_ROUTER_ADV) as ICMP_RA;

    components new TrickleTimerMilliC(1, 1024, 1, 1);

    components SERPNeighborTableP;
    SERPNeighborTableP.Init <- MainC.SoftwareInit;

    components SERPRoutingEngineP as Routing;
    Routing.RootControl = RootControl;
    Routing.RSTrickleTimer -> TrickleTimer;
    Routing.Random -> RandomC;
    Routing.IP_RA -> ICMP_RA.IP[ICMPV6_CODE_RA];
    Routing.IP_RS -> ICMP_RS.IP[ICMPV6_CODE_RS];
    Routing.IPAddress -> IPAddressC;
    Routing.Ieee154Address -> Ieee154AddressC.Ieee154Address;
    Routing.NeighborDiscovery = NeighborDiscovery;
    Routing.SERPNeighborTable -> SERPNeighborTableP;
    Routing.ForwardingTable -> IPStackC;
    Routing.RouterAdvMeshAnnTimer -> RouterAdvMeshAnnTimer;
    Routing.PrintTimer -> PrintTimer;
    Routing.IPForward -> IPNeighborDiscoveryC.IPForward;
    SERPControl = Routing;
}
