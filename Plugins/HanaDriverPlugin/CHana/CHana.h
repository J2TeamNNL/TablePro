#ifndef CHana_h
#define CHana_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/*
 * Every buffer passed in is borrowed until the call returns. Every string the bridge returns,
 * results and errors alike, is JSON owned by the caller and released with tp_hana_free_string.
 *
 * A session id is never reused. An id that was closed or never issued is answered with a
 * "closed" error, so a call racing tp_hana_close cannot touch freed state.
 *
 * Operation ids are issued by the caller, increase monotonically per session, and name one
 * blocking call. tp_hana_cancel may be called from any thread at any time and never blocks.
 * Operation 0 cancels whatever is running on the session.
 */
uint64_t tp_hana_open(const uint8_t *config_json, size_t config_json_length, char **error_out);
bool tp_hana_connect(uint64_t session, uint64_t operation, char **result_out, char **error_out);
char *tp_hana_execute(
    uint64_t session,
    uint64_t operation,
    const uint8_t *request_json,
    size_t request_json_length,
    char **error_out
);
char *tp_hana_explain(
    uint64_t session,
    uint64_t operation,
    const uint8_t *request_json,
    size_t request_json_length,
    char **error_out
);
bool tp_hana_ping(uint64_t session, uint64_t operation, char **error_out);
void tp_hana_cancel(uint64_t session, uint64_t operation);
void tp_hana_close(uint64_t session);
void tp_hana_free_string(char *value);

#endif
