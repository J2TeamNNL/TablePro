#ifndef CHana_h
#define CHana_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/*
 * Input buffers are borrowed until the function returns. Connection handles are
 * owned by the caller and must be released once. Result JSON and error strings
 * are allocated by the bridge and must be released with tp_hana_free_string.
 * tp_hana_cancel may run concurrently with one execute call.
 */
uint64_t tp_hana_connect(
    const uint8_t *config_json,
    size_t config_json_length,
    char **error_out
);
void tp_hana_disconnect(uint64_t connection);
char *tp_hana_execute(
    uint64_t connection,
    const uint8_t *sql,
    size_t sql_length,
    uint64_t row_cap,
    char **error_out
);
bool tp_hana_ping(uint64_t connection, char **error_out);
void tp_hana_cancel(uint64_t connection);
void tp_hana_free_string(char *value);

#endif
