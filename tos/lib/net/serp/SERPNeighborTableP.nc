#include <serp_messages.h>
#include <iprouting.h>
#include <lib6lowpan/ip.h>
#include "blip_printf.h"

module SERPNeighborTableP {
    provides interface SERPNeighborTable;
} implementation {
    serp_neighbor_t neighbor_table[MAX_SERP_NEIGHBOR_COUNT];

    command error_t SERPNeighborTable.addNeighbor(struct in6_addr *addr, uint8_t hop_count, serp_power_type power_profile) {
        int i;
        serp_neighbor_t *entry;
        serp_neighbor_t *neighbor;
        error_t err;

        printf("\033[31;0mAdding SERP neighbor table with IP ");
        printf_in6addr(addr);
        printf("\n\033[0m");

        memcpy(&neighbor->ip, addr, sizeof(struct in6_addr));
        neighbor->hop_count = hop_count;
        neighbor->power_profile = power_profile;
        neighbor->valid = 1;

        // zero out top 64 bits
        neighbor->ip.s6_addr32[0] = 0;
        neighbor->ip.s6_addr32[1] = 0;

        for (i=0; i < MAX_SERP_NEIGHBOR_COUNT; i++) {
            entry = &neighbor_table[i];
            // test for duplicate entry
            if (entry != NULL && (memcmp(&neighbor->ip, &entry->ip, 16) == 0)) {
                printf(" >> duplicate entry\n");
                return SUCCESS;
            }
        }

        // here, we know that we haven't added the entry yet

                printf(" >> full? \n");
        // the table is full
        if (neighbor_table[MAX_SERP_NEIGHBOR_COUNT-1].valid) return FAIL;
                printf(" >> not full \n");

        // iterate through the table until we find an empty or invalid entry
        for (i = 0; i < MAX_SERP_NEIGHBOR_COUNT; i++) {
            if (!neighbor_table[i].valid) break;
        }
        // add ourselves to this entry
        memcpy(&neighbor_table[i].ip, &neighbor->ip, sizeof(struct in6_addr));
        neighbor_table[i].hop_count = neighbor->hop_count;
        neighbor_table[i].power_profile = neighbor->power_profile;
        neighbor_table[i].valid = 1;
        printf("\033[31;0mAdding SERP neighbor table with IP ");
        printf_in6addr(&neighbor_table[i].ip);
        printf("\n\033[0m");
        return SUCCESS;
    }

    command serp_neighbor_t* SERPNeighborTable.getNeighbor(int index) {
        return &neighbor_table[index];
    }

    command bool SERPNeighborTable.isNeighbor(struct in6_addr *addr) {
        int i;
        serp_neighbor_t *entry;

        for (i=0; i < MAX_SERP_NEIGHBOR_COUNT; i++) {
            entry = &neighbor_table[i];
            if ((memcmp(&addr->s6_addr, &entry->ip.s6_addr, 16) == 0) ||
                (memcmp(&addr->s6_addr32[1], &entry->ip.s6_addr32[1], 8) == 0)) {
                return TRUE;
            }
        }
        return FALSE;
    }

    command serp_neighbor_t* SERPNeighborTable.getLowestHopCount() {
        int i;
        serp_neighbor_t *entry;
        uint8_t hop_count = 0xFF;
        int lowest_index = MAX_SERP_NEIGHBOR_COUNT;

        for (i=0; i < MAX_SERP_NEIGHBOR_COUNT; i++) {
            entry = &neighbor_table[i];
            if (entry->valid && (entry->hop_count < hop_count)) {
                hop_count = entry->hop_count;
                lowest_index = i;
            }
        }

        // we want to fail if:
        if ((hop_count == 0xFF) || // if the hop count is still infinity
            (lowest_index == MAX_SERP_NEIGHBOR_COUNT)) { // or if we didn't find anything
            return NULL;
        }
        // return the found entry
        return &neighbor_table[lowest_index];
    }

    command serp_neighbor_t* SERPNeighborTable.getLowestHopCountWithPower() {
        return NULL;
    }
}
