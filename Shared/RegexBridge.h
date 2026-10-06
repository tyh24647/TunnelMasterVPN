#ifndef RegexBridge_h
#define RegexBridge_h
#include <stddef.h>
int td_regex_available(void);
/* 1 match, 0 no match, -1 invalid, -2 budget exceeded, -3 engine absent. */
int td_regex_match(const char *pattern, const char *subject, char *error, size_t capacity);
#endif
