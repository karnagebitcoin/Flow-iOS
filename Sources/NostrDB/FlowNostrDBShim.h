#ifndef FLOW_NOSTRDB_SHIM_H
#define FLOW_NOSTRDB_SHIM_H

#include <stddef.h>
#include <stdint.h>

#define FLOW_NDB_FLAG_NO_FULLTEXT (1 << 2)
#define FLOW_NDB_FLAG_NO_NOTE_BLOCKS (1 << 3)
#define FLOW_NDB_FLAG_NO_STATS (1 << 4)

void *flow_ndb_open(const char *dbdir, int ingest_threads, size_t mapsize, int writer_scratch_buffer_size, int flags);
const char *flow_ndb_last_open_error(void);
void flow_ndb_close(void *handle);

int flow_ndb_ingest_note_json(void *handle, const char *json, int len);
char *flow_ndb_copy_note_json(void *handle, const unsigned char *id, int *out_len);
char *flow_ndb_copy_note_json_by_key(void *handle, uint64_t note_key, int *out_len);
char *flow_ndb_copy_note_json_array_for_filter_json(void *handle, const char *filter_json, int filter_json_len, int *out_len);
char *flow_ndb_copy_latest_note_json_for_pubkey_kind(void *handle, const unsigned char *pubkey, uint32_t kind, int *out_len);
char *flow_ndb_copy_profile_json(void *handle, const unsigned char *pubkey, int *out_len);
char *flow_ndb_copy_profile_search_json(void *handle, const char *query, int limit, int *out_len);
uint64_t flow_ndb_profile_note_key(void *handle, const unsigned char *pubkey);
uint64_t flow_ndb_note_count(void *handle);
uint64_t flow_ndb_profile_count(void *handle);

void flow_ndb_free_string(char *value);

#endif
