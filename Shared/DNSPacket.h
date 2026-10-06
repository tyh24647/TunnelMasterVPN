#ifndef DNSPacket_h
#define DNSPacket_h
#include <stddef.h>
#include <stdint.h>
/* Decode a complete, unfragmented IPv4/IPv6 UDP datagram destined for port 53. */
int td_dns_extract(const uint8_t *packet, size_t size, size_t *offset, size_t *length);
int td_dns_question(const uint8_t *dns, size_t size, char *hostname, size_t capacity);
int td_dns_answer(const uint8_t *query, size_t size, const char *sink, int servfail, uint8_t *output, size_t capacity);
int td_dns_wrap(const uint8_t *packet, size_t size, const uint8_t *dns, size_t dns_size, uint8_t *output, size_t capacity);
#endif
