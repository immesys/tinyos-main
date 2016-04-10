#include <lib6lowpan/ip_malloc.h>
#include <lib6lowpan/in_cksum.h>
#include <lib6lowpan/ip.h>
#include "neighbor_discovery.h"
#include <serp_messages.h>

module SERPRoutingEngineP {
    provides {
        interface StdControl;
        interface RootControl;
    }
    uses {
        interface IP as IP_RA;
        interface IP as IP_RS;
        interface Random;
        interface IPAddress;
        interface Ieee154Address;
        interface NeighborDiscovery;
        interface SERPNeighborTable;
        interface ForwardingTable;
    }
} implementation {

#define ADD_SECTION(SRC, LEN) ip_memcpy(cur, (uint8_t *)(SRC), LEN);\
  cur += (LEN); length += (LEN);

  // SERP Routing values

  // current hop count. Start at 0xff == infinity
  uint8_t hop_count = 0xff;
  // whether or not we are part of a mesh. This should be set to TRUE if we are a root node
  bool part_of_mesh = FALSE;

  /**** Global Vars ***/
  // whether or not the routing protocol is running
  bool running = FALSE;

  // if this node is root
  bool I_AM_ROOT = FALSE;

  // this is where we store the LL address of the node
  // who sent us a broadcast RS. We need to unicast an RA
  // back to them.
  struct in6_addr unicast_ra_destination;

  // initial period becomes 2 << (10 - 1) == 512 milliseconds
  uint32_t tx_interval_min = 10;

  task void init() {
    if (I_AM_ROOT) {
        // we don't actually advertise the mesh. It is driven entirely
        // by clients that want to join
        //post startMeshAdvertising();
    } else {
    }
  }

  // Returns the length of the added option
  uint8_t add_sllao (uint8_t* data) {
    struct nd_option_slla_t sllao;

    sllao.type = ND6_OPT_SLLAO;
    sllao.option_length = 2; // length in multiples of 8 octets, need 10 bytes
                             // so we must round up to 16.
    sllao.ll_addr = call Ieee154Address.getExtAddr();

    ip_memcpy(data, (uint8_t*) &sllao, sizeof(struct nd_option_slla_t));
    memset(data+sizeof(struct nd_option_slla_t), 0,
      16-sizeof(struct nd_option_slla_t));
    return 16;
  }

/*
 What's the logic for handling an incoming RA? When we receive an RA and we are *not* part of a mesh, we need
 to become part of the mesh. The received RA contains:
 - prefix for the mesh (and the prefix length)
 - hop count of the sender
 - power profile of the sender
 What we need is a table of "neighbors" that indexes this heard information. Currently, we only send the mesh
 info RA if we are part of a mesh, but if we change so we always send an RA, we can tell if a RA sender is part
 of the mesh or not by what their hop count is (0xff == no, else yes).

 Table is: serp_neighbor_t neighbors[MAX_NEIGHBOR_COUNT];
 MAX_NEIGHBOR_COUNT needs to be calculated: we want the control message overhead to be below a certain
 percentage, so MAX_NEIGHBOR_COUNT should be the maximum number of neighbors with whom the exchange of
 control traffic is expected to be below a given amount. 
 For now, lets just go with 10.

 The neighbor table should support the following methods:
 - find neighbor with lowest hop count
 - find neighbor w/ lowest hop count, using power profile (see note below)
 - remove neighbor
 - add neighbor
**/

  /***** Handle Incoming RA *****/
  event void IP_RA.recv(struct ip6_hdr *hdr,
                        void *packet,
                        size_t len,
                        struct ip6_metadata *meta) {

    struct nd_router_advertisement_t* ra;
    uint8_t* cur = (uint8_t*) packet;
    uint8_t type;
    uint8_t olen;

    printf("received an RA in SERP from ");
    printf_in6addr(&hdr->ip6_src);
    printf("\n");

    //TODO: what's the right behavior if it has a different prefix than ours?

    if (len < sizeof(struct nd_router_advertisement_t)) return;
    ra = (struct nd_router_advertisement_t*) packet;

    // skip the base of the packet
    cur += sizeof(struct nd_router_advertisement_t);
    len -= sizeof(struct nd_router_advertisement_t);

    // Iterate through all of the SERP-specific options
    while (TRUE) {
      if (len < 2) break;
      // Get the type byte of the first option
      type = *cur;
      olen = *(cur+1) << 3;

      if (len < olen) return;
      switch (type) {
      case ND6_SERP_MESH_INFO:
        {
            struct nd_option_serp_mesh_info_t* meshinfo;
            serp_neighbor_t nn;
            serp_neighbor_t *chosen_parent;

            meshinfo = (struct nd_option_serp_mesh_info_t*) cur;
            printf("Received a SERP Mesh Info message with pfx len: %d, power: %d and prefix ", meshinfo->prefix_length, meshinfo->powered);
            printf_in6addr(&meshinfo->prefix);
            printf("\n");

            if (meshinfo->prefix_length > 0) {
              call NeighborDiscovery.setPrefix(&meshinfo->prefix, meshinfo->prefix_length, 0xFF, 0xFF);
            }

            // populate a neighbor table entry
            memcpy(&nn.ip, &hdr->ip6_src, sizeof(struct in6_addr));
            nn.hop_count = meshinfo->sender_hop_count;
            nn.power_profile = meshinfo->powered;
            call SERPNeighborTable.addNeighbor(&nn);

            // get the neighbor table entry with the lowest hop count
            chosen_parent = call SERPNeighborTable.getLowestHopCount();
            // we set our hop count to be one greater than the hop count of the parent we've chosen
            hop_count = chosen_parent->hop_count + 1;

            break;
        }
      default:
        break;
      }
      cur += olen;
      len -= olen;
    }
  }

  /***** Send Router Advertisement *****/
  // This is the RA that we send to a new mote that
  // probably hasn't joined the mesh yet. This is sent as a
  // unicast in response to a received RS
  // Most of this implementation is taken from IPNeighborDiscoveryP
  task void send_mesh_info_RA() {
    struct nd_router_advertisement_t ra;

    struct ip6_packet pkt;
    struct ip_iovec   v[1];


    uint8_t sllao_len;
    uint8_t data[100];
    uint8_t* cur = data;
    uint16_t length = 0;

    // if we don't have prefix, we aren't part of mesh and
    // shouldn't respond to this
    if (!call NeighborDiscovery.havePrefix()) {
        return;
    }

    ra.icmpv6.type = ICMP_TYPE_ROUTER_ADV;
    ra.icmpv6.code = ICMPV6_CODE_RA;
    ra.icmpv6.checksum = 0;
    ra.hop_limit = 16;
    ra.flags_reserved = 0;
    ra.flags_reserved |= RA_FLAG_MANAGED_ADDR_CONF << ND6_ADV_M_SHIFT;
    ra.flags_reserved |= RA_FLAG_OTHER_CONF << ND6_ADV_O_SHIFT;
    ra.router_lifetime = RTR_LIFETIME;
    ra.reachable_time = 0; // unspecified at this point...
    ra.retransmit_time = 0; // unspecified at this point...
    ADD_SECTION(&ra, sizeof(struct nd_router_advertisement_t));

    sllao_len = add_sllao(cur);
    cur += sllao_len;
    length += sllao_len;

    if (call NeighborDiscovery.havePrefix()) {
        struct nd_option_serp_mesh_info_t option;
        option.type = ND6_SERP_MESH_INFO;
        option.option_length = 3;
        option.reserved1 = 0;
        option.reserved2 = 0;
        // add prefix length
        option.prefix_length = call NeighborDiscovery.getPrefixLength();
        // add prefix
        ip_memcpy((uint8_t*) &option.prefix, (uint8_t*)call NeighborDiscovery.getPrefix(), sizeof(struct in6_addr));
        // treat all nodes as powered for now
        // TODO: fix this!
        option.powered = SERP_MAINS_POWERED;
        option.sender_hop_count = hop_count;
        ADD_SECTION(&option, sizeof(struct nd_option_serp_mesh_info_t));
    }

    v[0].iov_base = data;
    v[0].iov_len = length;
    v[0].iov_next = NULL;

    pkt.ip6_hdr.ip6_nxt = IANA_ICMP;
    pkt.ip6_hdr.ip6_plen = htons(length);

    pkt.ip6_data = &v[0];

    // Send unicast RA to the link local address
    memcpy(&pkt.ip6_hdr.ip6_dst, &unicast_ra_destination, 16);

    // set the src address to our link layer address
    call IPAddress.getLLAddr(&pkt.ip6_hdr.ip6_src);
    call IP_RA.send(&pkt);
  }

  /***** Handle Incoming RS *****/
  // When we receive an RS
  event void IP_RS.recv(struct ip6_hdr *hdr,
                        void *packet,
                        size_t len,
                        struct ip6_metadata *meta) {
    printf("received an RS in SERP from ");
    printf_in6addr(&hdr->ip6_src);
    printf("\n");
    memcpy(&unicast_ra_destination, &(hdr->ip6_src), sizeof(struct in6_addr));

    // send our unicast reply with the mesh info
    if (part_of_mesh) {
        post send_mesh_info_RA();
    } else {
        //TODO: send the normal RA to populate the neighbor table?
    }
  }

  /***** StdControl *****/
  command error_t StdControl.start() {
    if (!running) {
        post init();
        running = TRUE;
    }
    return SUCCESS;
  }

  command error_t StdControl.stop() {
      running = FALSE;
      return SUCCESS;
  }

  /***** RootControl *****/
  command error_t RootControl.setRoot() {
    I_AM_ROOT = TRUE;
    part_of_mesh = TRUE;
    hop_count = 0;
    //call RPLRankInfo.declareRoot();
    return SUCCESS;
  }

  command error_t RootControl.unsetRoot() {
    I_AM_ROOT = FALSE;
    //call RPLRankInfo.cancelRoot();
    return SUCCESS;
  }

  command bool RootControl.isRoot() {
    return I_AM_ROOT;
  }

  event void Ieee154Address.changed() {}
  event void IPAddress.changed(bool global_valid) {}
}