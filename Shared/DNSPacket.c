#include "DNSPacket.h"
#include <string.h>
#include <arpa/inet.h>

static uint16_t get16(const uint8_t *p) {
    return (uint16_t)((p[0] << 8) | p[1]);
}
static void put16(uint8_t *p, uint16_t n) {
    p[0] = n >> 8;
    p[1] = n & 255;
}
static uint32_t sum16(const uint8_t *p, size_t n) {
    uint32_t s = 0;
    while (n >= 2) {
        s += get16(p);
        p += 2;
        n -= 2;
    }
    if (n) {
        s += *p << 8;
    }
    return s;
}
static uint16_t checksum(uint32_t sum) {
    while (sum >> 16) {
        sum = (sum & 65535) + (sum >> 16);
    }
    return (uint16_t)~sum;
}
int td_dns_extract(const uint8_t *p, size_t n, size_t *offset, size_t *length) {
    if (n < 28) {
        return 0;
    }
    size_t h;
    size_t total;
    int version = p[0] >> 4;
    if (version == 4) {
        h = (p[0] & 15) * 4;
        total = get16(p + 2);
        if (h < 20 || total > n || total < h + 8 || p[9] != 17 || (get16(p + 6) & 0x3fff)) {
            return 0;
        }
    } else if (version == 6) {
        h = 40;
        if (n < 48 || p[6] != 17) {
            return 0;
        }
        total = 40 + get16(p + 4);
        if (total > n || total < 48) {
            return 0;
        }
    } else {
        return 0;
    }
    size_t udp = get16(p + h + 4);
    if (get16(p + h + 2) != 53 || udp < 20 || h + udp > total) {
        return 0;
    }
    *offset = h + 8;
    *length = udp - 8;
    return version;
}
int td_dns_question(const uint8_t *d, size_t n, char *host, size_t capacity) {
    if (n < 17 || (d[2] & 0xf8) || get16(d + 4) != 1 || capacity < 2) {
        return 0;
    }
    size_t i = 12;
    size_t out = 0;
    while (i < n && d[i]) {
        unsigned len = d[i++];
        if (len > 63 || i + len >= n || out + len + 1 >= capacity || out + len > 253) {
            return 0;
        }
        if (out) {
            host[out++] = '.';
        }
        for (unsigned j = 0; j < len; j++) {
            unsigned char c = d[i++];
            if (c < 33 || c > 126 || c == '.') {
                return 0;
            }
            host[out++] = (char)c;
        }
    }
    if (i + 5 > n || !out || get16(d + i + 3) != 1) {
        return 0;
    }
    host[out] = 0;
    return (int)(i + 5);
}
int td_dns_answer(const uint8_t *q, size_t n, const char *sink, int servfail, uint8_t *out, size_t capacity) {
    char host[256];
    int end = td_dns_question(q, n, host, sizeof(host));
    if (!end || capacity < (size_t)end + 16) {
        return 0;
    }
    uint8_t address[4];
    if (inet_pton(AF_INET, sink, address) != 1) {
        return 0;
    }
    memcpy(out, q, end);
    out[2] = 0x80 | (q[2] & 1);
    out[3] = 0x80 | (servfail ? 2 : 0);
    memset(out + 6, 0, 6);
    if (!servfail && get16(q + end - 4) == 1) {
        put16(out + 6, 1);
        uint8_t answer[16] = {0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 30, 0, 4, 0, 0, 0, 0};
        memcpy(answer + 12, address, 4);
        memcpy(out + end, answer, sizeof(answer));
        return end + 16;
    }
    /* AAAA, HTTPS/SVCB and other blocked types return NODATA, preventing IPv6/alias bypass. */
    return end;
}
int td_dns_wrap(const uint8_t *p, size_t n, const uint8_t *dns, size_t dn, uint8_t *out, size_t cap) {
    size_t offset, length;
    int version = td_dns_extract(p, n, &offset, &length);
    size_t h = version == 4 ? 20 : 40;
    size_t total = h + 8 + dn;
    if (!version || dn > 1232 || cap < total) {
        return 0;
    }
    memset(out, 0, total);
    if (version == 4) {
        out[0] = 0x45;
        put16(out + 2, total);
        out[8] = 64;
        out[9] = 17;
        memcpy(out + 12, p + 16, 4);
        memcpy(out + 16, p + 12, 4);
        put16(out + 10, checksum(sum16(out, h)));
    } else {
        out[0] = 0x60;
        put16(out + 4, dn + 8);
        out[6] = 17;
        out[7] = 64;
        memcpy(out + 8, p + 24, 16);
        memcpy(out + 24, p + 8, 16);
    }
    memcpy(out + h, p + offset - 6, 2);
    memcpy(out + h + 2, p + offset - 8, 2);
    put16(out + h + 4, dn + 8);
    memcpy(out + h + 8, dns, dn);
    uint32_t sum = sum16(out + h, dn + 8) + 17 + (uint32_t)dn + 8;
    sum += version == 4 ? sum16(out + 12, 8) : sum16(out + 8, 32);
    uint16_t check = checksum(sum);
    put16(out + h + 6, check ? check : 65535);
    return (int)total;
}
