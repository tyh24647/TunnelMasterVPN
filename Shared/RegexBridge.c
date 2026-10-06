#include "RegexBridge.h"
#include <stdio.h>
#include <string.h>
#if __has_include("pcre2.h")
#define PCRE2_CODE_UNIT_WIDTH 8
#include "pcre2.h"
int td_regex_available(void) {
    return 1;
}
int td_regex_match(const char *pattern, const char *subject, char *error, size_t capacity) {
    if (strlen(pattern) > 4096 || strlen(subject) > 253) {
        snprintf(error, capacity, "Pattern or hostname exceeds the size limit.");
        return -1;
    }
    int code;
    PCRE2_SIZE offset;
    pcre2_code *compiled = pcre2_compile((PCRE2_SPTR)pattern, PCRE2_ZERO_TERMINATED,
        PCRE2_CASELESS | PCRE2_UTF | PCRE2_UCP, &code, &offset, NULL);
    if (!compiled) {
        PCRE2_UCHAR detail[180];
        pcre2_get_error_message(code, detail, sizeof(detail));
        snprintf(error, capacity, "At byte %zu: %s", offset, detail);
        return -1;
    }
    pcre2_match_context *context = pcre2_match_context_create(NULL);
    pcre2_match_data *data = pcre2_match_data_create_from_pattern(compiled, NULL);
    if (!context || !data) {
        pcre2_match_context_free(context);
        pcre2_match_data_free(data);
        pcre2_code_free(compiled);
        snprintf(error, capacity, "Regex allocation failed.");
        return -2;
    }
    /* Interpreter only: supports lookaround, backreferences and recursion without JIT. */
    pcre2_set_match_limit(context, 100000);
    pcre2_set_depth_limit(context, 200);
    pcre2_set_heap_limit(context, 1024);
    int result = pcre2_match(compiled, (PCRE2_SPTR)subject, strlen(subject), 0, 0, data, context);
    pcre2_match_data_free(data);
    pcre2_match_context_free(context);
    pcre2_code_free(compiled);
    if (result >= 0) {
        return 1;
    }
    if (result == PCRE2_ERROR_NOMATCH) {
        return 0;
    }
    snprintf(error, capacity, "Regex evaluation stopped (%d). Simplify the pattern.", result);
    return -2;
}
#else
int td_regex_available(void) {
    return 0;
}
int td_regex_match(const char *pattern, const char *subject, char *error, size_t capacity) {
    (void)pattern;
    (void)subject;
    snprintf(error, capacity, "PCRE2 is not bundled. Follow Docs/Protocol-Engines.md.");
    return -3;
}
#endif
