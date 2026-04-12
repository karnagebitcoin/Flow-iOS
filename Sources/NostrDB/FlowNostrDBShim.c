#include "FlowNostrDBShim.h"

#include "nostrdb.h"
#include "bindings/c/profile_reader.h"

#include <ctype.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FLOW_NDB_JSON_INITIAL_CAPACITY 4096
#define FLOW_NDB_JSON_MAX_CAPACITY (4 * 1024 * 1024)
#define FLOW_NDB_QUERY_RESULT_CAPACITY 2048
#define FLOW_NDB_PROFILE_SEARCH_KEY_SIZE 24

static int flow_ndb_grow_buffer(char **buffer, int *capacity, int required)
{
	int next_capacity;
	char *resized;

	if (required <= *capacity) {
		return 1;
	}

	next_capacity = *capacity;
	while (next_capacity < required) {
		if (next_capacity >= FLOW_NDB_JSON_MAX_CAPACITY / 2) {
			next_capacity = FLOW_NDB_JSON_MAX_CAPACITY;
		} else {
			next_capacity *= 2;
		}

		if (next_capacity >= required) {
			break;
		}
	}

	if (next_capacity < required || next_capacity > FLOW_NDB_JSON_MAX_CAPACITY) {
		return 0;
	}

	resized = realloc(*buffer, (size_t)next_capacity + 1);
	if (resized == NULL) {
		return 0;
	}

	*buffer = resized;
	*capacity = next_capacity;
	return 1;
}

static char *flow_ndb_copy_note_json_inner(struct ndb *ndb, struct ndb_note *note, int *out_len)
{
	int capacity;
	int written;
	char *buffer;

	if (ndb == NULL || note == NULL) {
		return NULL;
	}

	capacity = (int)ndb_note_content_length(note) * 2 + FLOW_NDB_JSON_INITIAL_CAPACITY;
	if (capacity < FLOW_NDB_JSON_INITIAL_CAPACITY) {
		capacity = FLOW_NDB_JSON_INITIAL_CAPACITY;
	}

	buffer = NULL;
	while (capacity <= FLOW_NDB_JSON_MAX_CAPACITY) {
		char *resized = realloc(buffer, (size_t)capacity + 1);
		if (resized == NULL) {
			free(buffer);
			return NULL;
		}

		buffer = resized;
		written = ndb_note_json(note, buffer, capacity);
		if (written > 0) {
			buffer[written] = '\0';
			if (out_len != NULL) {
				*out_len = written;
			}
			return buffer;
		}

		capacity *= 2;
	}

	free(buffer);
	return NULL;
}

static int flow_ndb_json_escaped_length(const char *value)
{
	int length = 0;

	if (value == NULL) {
		return 0;
	}

	for (; *value != '\0'; value++) {
		switch (*value) {
		case '"':
		case '\\':
		case '\b':
		case '\f':
		case '\n':
		case '\r':
		case '\t':
			length += 2;
			break;
		default:
			length += 1;
			break;
		}
	}

	return length;
}

static char *flow_ndb_append_char(char *cursor, char value)
{
	*cursor = value;
	return cursor + 1;
}

static char *flow_ndb_append_bytes(char *cursor, const char *value, size_t length)
{
	memcpy(cursor, value, length);
	return cursor + length;
}

static char *flow_ndb_append_json_string(char *cursor, const char *value)
{
	const char *current = value;

	cursor = flow_ndb_append_char(cursor, '"');
	for (; *current != '\0'; current++) {
		switch (*current) {
		case '"':
			cursor = flow_ndb_append_bytes(cursor, "\\\"", 2);
			break;
		case '\\':
			cursor = flow_ndb_append_bytes(cursor, "\\\\", 2);
			break;
		case '\b':
			cursor = flow_ndb_append_bytes(cursor, "\\b", 2);
			break;
		case '\f':
			cursor = flow_ndb_append_bytes(cursor, "\\f", 2);
			break;
		case '\n':
			cursor = flow_ndb_append_bytes(cursor, "\\n", 2);
			break;
		case '\r':
			cursor = flow_ndb_append_bytes(cursor, "\\r", 2);
			break;
		case '\t':
			cursor = flow_ndb_append_bytes(cursor, "\\t", 2);
			break;
		default:
			cursor = flow_ndb_append_char(cursor, *current);
			break;
		}
	}
	return flow_ndb_append_char(cursor, '"');
}

static char *flow_ndb_append_uint64(char *cursor, uint64_t value)
{
	char buffer[32];
	int written = snprintf(buffer, sizeof(buffer), "%llu", (unsigned long long)value);
	if (written <= 0) {
		return cursor;
	}
	return flow_ndb_append_bytes(cursor, buffer, (size_t)written);
}

static void flow_ndb_hex_encode(const unsigned char *bytes, size_t length, char *out)
{
	static const char hex[] = "0123456789abcdef";
	size_t index;

	for (index = 0; index < length; index++) {
		out[index * 2] = hex[bytes[index] >> 4];
		out[index * 2 + 1] = hex[bytes[index] & 0x0F];
	}
	out[length * 2] = '\0';
}

static void flow_ndb_normalized_profile_query(const char *query, char *out, size_t out_size)
{
	size_t index = 0;

	if (out_size == 0) {
		return;
	}

	if (query == NULL) {
		out[0] = '\0';
		return;
	}

	while (*query != '\0' && isspace((unsigned char)*query)) {
		query++;
	}

	while (*query != '\0' && index + 1 < out_size) {
		out[index++] = (char)tolower((unsigned char)*query);
		query++;
	}

	while (index > 0 && isspace((unsigned char)out[index - 1])) {
		index--;
	}

	out[index] = '\0';
}

static int flow_ndb_search_key_matches_query(const struct ndb_search_key *key, const char *query)
{
	size_t query_len;

	if (key == NULL || query == NULL || query[0] == '\0') {
		return 0;
	}

	query_len = strlen(query);
	return strncmp(key->search, query, query_len) == 0;
}

static char *flow_ndb_copy_query_results_json(struct ndb *ndb,
					      const struct ndb_query_result *results,
					      int count,
					      int *out_len)
{
	int capacity = FLOW_NDB_JSON_INITIAL_CAPACITY;
	char *buffer = malloc((size_t)capacity + 1);
	char *cursor;
	int appended = 0;
	int index;

	if (buffer == NULL) {
		return NULL;
	}

	cursor = buffer;
	cursor = flow_ndb_append_char(cursor, '[');

	for (index = 0; index < count; index++) {
		int note_len = 0;
		int needed;
		ptrdiff_t cursor_offset;
		char *note_json;

		if (results[index].note == NULL) {
			continue;
		}

		note_json = flow_ndb_copy_note_json_inner(ndb, results[index].note, &note_len);
		if (note_json == NULL || note_len <= 0) {
			free(note_json);
			continue;
		}

		needed = (int)(cursor - buffer) + note_len + 2;
		if (appended > 0) {
			needed += 1;
		}

		cursor_offset = cursor - buffer;
		if (!flow_ndb_grow_buffer(&buffer, &capacity, needed)) {
			free(note_json);
			free(buffer);
			return NULL;
		}
		cursor = buffer + cursor_offset;
		if (appended > 0) {
			cursor = flow_ndb_append_char(cursor, ',');
		}
		cursor = flow_ndb_append_bytes(cursor, note_json, (size_t)note_len);
		appended += 1;
		free(note_json);
	}

	if (!flow_ndb_grow_buffer(&buffer, &capacity, (int)(cursor - buffer) + 2)) {
		free(buffer);
		return NULL;
	}

	cursor = flow_ndb_append_char(cursor, ']');
	*cursor = '\0';

	if (out_len != NULL) {
		*out_len = (int)(cursor - buffer);
	}

	return buffer;
}

static int flow_ndb_profile_json_length(const char *name,
					const char *display_name,
					const char *picture,
					const char *banner,
					const char *about,
					const char *nip05,
					const char *website,
					const char *lud06,
					const char *lud16)
{
	const struct {
		const char *key;
		const char *value;
	} fields[] = {
		{ "name", name },
		{ "display_name", display_name },
		{ "picture", picture },
		{ "banner", banner },
		{ "about", about },
		{ "nip05", nip05 },
		{ "website", website },
		{ "lud06", lud06 },
		{ "lud16", lud16 }
	};
	int count = sizeof(fields) / sizeof(fields[0]);
	int length = 2;
	int added = 0;
	int index;

	for (index = 0; index < count; index++) {
		if (fields[index].value == NULL || fields[index].value[0] == '\0') {
			continue;
		}

		if (added > 0) {
			length += 1;
		}

		length += 2 + (int)strlen(fields[index].key) + 1;
		length += 2 + flow_ndb_json_escaped_length(fields[index].value);
		added += 1;
	}

	return length;
}

static char *flow_ndb_copy_profile_table_json(NdbProfile_table_t profile, int *out_len)
{
	const char *name;
	const char *display_name;
	const char *picture;
	const char *banner;
	const char *about;
	const char *nip05;
	const char *website;
	const char *lud06;
	const char *lud16;
	char *json;
	char *cursor;
	int length;
	int added = 0;

	if (profile == NULL) {
		return NULL;
	}

	name = NdbProfile_name(profile);
	display_name = NdbProfile_display_name(profile);
	picture = NdbProfile_picture(profile);
	banner = NdbProfile_banner(profile);
	about = NdbProfile_about(profile);
	nip05 = NdbProfile_nip05(profile);
	website = NdbProfile_website(profile);
	lud06 = NdbProfile_lud06(profile);
	lud16 = NdbProfile_lud16(profile);

	length = flow_ndb_profile_json_length(
		name,
		display_name,
		picture,
		banner,
		about,
		nip05,
		website,
		lud06,
		lud16
	);

	json = malloc((size_t)length + 1);
	if (json == NULL) {
		return NULL;
	}

	cursor = json;
	cursor = flow_ndb_append_char(cursor, '{');

#define FLOW_NDB_APPEND_PROFILE_FIELD(KEY, VALUE) \
	do { \
		if ((VALUE) != NULL && (VALUE)[0] != '\0') { \
			if (added > 0) { \
				cursor = flow_ndb_append_char(cursor, ','); \
			} \
			cursor = flow_ndb_append_json_string(cursor, (KEY)); \
			cursor = flow_ndb_append_char(cursor, ':'); \
			cursor = flow_ndb_append_json_string(cursor, (VALUE)); \
			added += 1; \
		} \
	} while (0)

	FLOW_NDB_APPEND_PROFILE_FIELD("name", name);
	FLOW_NDB_APPEND_PROFILE_FIELD("display_name", display_name);
	FLOW_NDB_APPEND_PROFILE_FIELD("picture", picture);
	FLOW_NDB_APPEND_PROFILE_FIELD("banner", banner);
	FLOW_NDB_APPEND_PROFILE_FIELD("about", about);
	FLOW_NDB_APPEND_PROFILE_FIELD("nip05", nip05);
	FLOW_NDB_APPEND_PROFILE_FIELD("website", website);
	FLOW_NDB_APPEND_PROFILE_FIELD("lud06", lud06);
	FLOW_NDB_APPEND_PROFILE_FIELD("lud16", lud16);

#undef FLOW_NDB_APPEND_PROFILE_FIELD

	cursor = flow_ndb_append_char(cursor, '}');
	*cursor = '\0';

	if (out_len != NULL) {
		*out_len = (int)(cursor - json);
	}

	return json;
}

void *flow_ndb_open(const char *dbdir, int ingest_threads, size_t mapsize, int writer_scratch_buffer_size, int flags)
{
	struct ndb *ndb = NULL;
	struct ndb_config config;

	if (dbdir == NULL) {
		return NULL;
	}

	ndb_default_config(&config);
	if (ingest_threads > 0) {
		ndb_config_set_ingest_threads(&config, ingest_threads);
	}
	if (mapsize > 0) {
		ndb_config_set_mapsize(&config, mapsize);
	}
	if (writer_scratch_buffer_size > 0) {
		ndb_config_set_writer_scratch_buffer_size(&config, writer_scratch_buffer_size);
	}
	ndb_config_set_flags(&config, flags);

	if (!ndb_init(&ndb, dbdir, &config)) {
		return NULL;
	}

	return ndb;
}

void flow_ndb_close(void *handle)
{
	if (handle == NULL) {
		return;
	}

	ndb_destroy((struct ndb *)handle);
}

int flow_ndb_ingest_note_json(void *handle, const char *json, int len)
{
	struct ndb *ndb = (struct ndb *)handle;
	char *payload;
	int payload_len;
	int ok;

	if (ndb == NULL || json == NULL || len <= 0) {
		return 0;
	}

	payload_len = len + 10;
	payload = malloc((size_t)payload_len + 1);
	if (payload == NULL) {
		return 0;
	}

	memcpy(payload, "[\"EVENT\",", 9);
	memcpy(payload + 9, json, (size_t)len);
	payload[9 + len] = ']';
	payload[payload_len] = '\0';

	ok = ndb_process_client_event(ndb, payload, payload_len);
	free(payload);
	return ok;
}

char *flow_ndb_copy_note_json(void *handle, const unsigned char *id, int *out_len)
{
	struct ndb *ndb = (struct ndb *)handle;
	struct ndb_txn txn;
	struct ndb_note *note;
	uint64_t note_key = 0;
	size_t note_size = 0;
	char *json;

	if (ndb == NULL || id == NULL) {
		return NULL;
	}

	if (!ndb_begin_query(ndb, &txn)) {
		return NULL;
	}

	note = ndb_get_note_by_id(&txn, id, &note_size, &note_key);
	json = flow_ndb_copy_note_json_inner(ndb, note, out_len);

	ndb_end_query(&txn);
	return json;
}

char *flow_ndb_copy_note_json_by_key(void *handle, uint64_t note_key, int *out_len)
{
	struct ndb *ndb = (struct ndb *)handle;
	struct ndb_txn txn;
	struct ndb_note *note;
	size_t note_size = 0;
	char *json;

	if (ndb == NULL || note_key == 0) {
		return NULL;
	}

	if (!ndb_begin_query(ndb, &txn)) {
		return NULL;
	}

	note = ndb_get_note_by_key(&txn, note_key, &note_size);
	json = flow_ndb_copy_note_json_inner(ndb, note, out_len);

	ndb_end_query(&txn);
	return json;
}

char *flow_ndb_copy_note_json_array_for_filter_json(void *handle, const char *filter_json, int filter_json_len, int *out_len)
{
	struct ndb *ndb = (struct ndb *)handle;
	struct ndb_txn txn;
	struct ndb_filter filter;
	struct ndb_query_result *results = NULL;
	unsigned char *parse_buffer = NULL;
	char *json = NULL;
	int count = 0;
	int parse_buffer_size;
	int filter_initialized = 0;

	if (ndb == NULL || filter_json == NULL || filter_json_len <= 0) {
		return NULL;
	}

	if (!ndb_begin_query(ndb, &txn)) {
		return NULL;
	}

	if (!ndb_filter_init_with(&filter, 4)) {
		goto cleanup;
	}
	filter_initialized = 1;

	parse_buffer_size = filter_json_len * 16;
	if (parse_buffer_size < 64 * 1024) {
		parse_buffer_size = 64 * 1024;
	} else if (parse_buffer_size > 1024 * 1024) {
		parse_buffer_size = 1024 * 1024;
	}

	parse_buffer = malloc((size_t)parse_buffer_size);
	if (parse_buffer == NULL) {
		goto cleanup;
	}

	if (!ndb_filter_from_json(filter_json, filter_json_len, &filter, parse_buffer, parse_buffer_size)) {
		goto cleanup;
	}

	if (!filter.finalized && !ndb_filter_end(&filter)) {
		goto cleanup;
	}

	results = calloc(FLOW_NDB_QUERY_RESULT_CAPACITY, sizeof(*results));
	if (results == NULL) {
		goto cleanup;
	}

	if (!ndb_query(&txn, &filter, 1, results, FLOW_NDB_QUERY_RESULT_CAPACITY, &count)) {
		goto cleanup;
	}

	json = flow_ndb_copy_query_results_json(ndb, results, count, out_len);

cleanup:
	free(results);
	free(parse_buffer);
	if (filter_initialized) {
		ndb_filter_destroy(&filter);
	}
	ndb_end_query(&txn);
	return json;
}

char *flow_ndb_copy_latest_note_json_for_pubkey_kind(void *handle, const unsigned char *pubkey, uint32_t kind, int *out_len)
{
	struct ndb *ndb = (struct ndb *)handle;
	struct ndb_txn txn;
	struct ndb_filter filter;
	struct ndb_query_result result;
	int count = 0;
	int filter_initialized = 0;
	char *json = NULL;

	if (ndb == NULL || pubkey == NULL) {
		return NULL;
	}

	if (!ndb_begin_query(ndb, &txn)) {
		return NULL;
	}

	if (!ndb_filter_init_with(&filter, 1)) {
		goto cleanup;
	}
	filter_initialized = 1;

	if (!ndb_filter_start_field(&filter, NDB_FILTER_AUTHORS) ||
	    !ndb_filter_add_id_element(&filter, pubkey)) {
		goto cleanup;
	}
	ndb_filter_end_field(&filter);

	if (!ndb_filter_start_field(&filter, NDB_FILTER_KINDS) ||
	    !ndb_filter_add_int_element(&filter, kind)) {
		goto cleanup;
	}
	ndb_filter_end_field(&filter);

	if (!ndb_filter_start_field(&filter, NDB_FILTER_LIMIT) ||
	    !ndb_filter_add_int_element(&filter, 1)) {
		goto cleanup;
	}
	ndb_filter_end_field(&filter);

	if (!ndb_filter_end(&filter)) {
		goto cleanup;
	}

	if (!ndb_query(&txn, &filter, 1, &result, 1, &count) || count < 1 || result.note == NULL) {
		goto cleanup;
	}

	json = flow_ndb_copy_note_json_inner(ndb, result.note, out_len);

cleanup:
	if (filter_initialized) {
		ndb_filter_destroy(&filter);
	}
	ndb_end_query(&txn);
	return json;
}

uint64_t flow_ndb_profile_note_key(void *handle, const unsigned char *pubkey)
{
	struct ndb *ndb = (struct ndb *)handle;
	struct ndb_txn txn;
	size_t profile_size = 0;
	void *profile_data;
	NdbProfileRecord_table_t record;
	uint64_t note_key;

	if (ndb == NULL || pubkey == NULL) {
		return 0;
	}

	if (!ndb_begin_query(ndb, &txn)) {
		return 0;
	}

	profile_data = ndb_get_profile_by_pubkey(&txn, pubkey, &profile_size, &note_key);
	if (profile_data == NULL) {
		ndb_end_query(&txn);
		return 0;
	}

	record = NdbProfileRecord_as_root(profile_data);
	note_key = NdbProfileRecord_note_key(record);

	ndb_end_query(&txn);
	return note_key;
}

uint64_t flow_ndb_note_count(void *handle)
{
	struct ndb *ndb = (struct ndb *)handle;
	struct ndb_stat stat;

	if (ndb == NULL) {
		return 0;
	}

	if (!ndb_stat(ndb, &stat)) {
		return 0;
	}

	return stat.dbs[NDB_DB_NOTE].count;
}

uint64_t flow_ndb_profile_count(void *handle)
{
	struct ndb *ndb = (struct ndb *)handle;
	struct ndb_stat stat;

	if (ndb == NULL) {
		return 0;
	}

	if (!ndb_stat(ndb, &stat)) {
		return 0;
	}

	return stat.dbs[NDB_DB_PROFILE].count;
}

char *flow_ndb_copy_profile_json(void *handle, const unsigned char *pubkey, int *out_len)
{
	struct ndb *ndb = (struct ndb *)handle;
	struct ndb_txn txn;
	void *profile_data;
	uint64_t primary_key = 0;
	size_t profile_size = 0;
	NdbProfileRecord_table_t record;
	NdbProfile_table_t profile;
	char *json;

	if (ndb == NULL || pubkey == NULL) {
		return NULL;
	}

	if (!ndb_begin_query(ndb, &txn)) {
		return NULL;
	}

	profile_data = ndb_get_profile_by_pubkey(&txn, pubkey, &profile_size, &primary_key);
	if (profile_data == NULL) {
		ndb_end_query(&txn);
		return NULL;
	}

	record = NdbProfileRecord_as_root(profile_data);
	profile = NdbProfileRecord_profile(record);
	if (profile == NULL) {
		ndb_end_query(&txn);
		return NULL;
	}

	json = flow_ndb_copy_profile_table_json(profile, out_len);
	ndb_end_query(&txn);
	return json;
}

char *flow_ndb_copy_profile_search_json(void *handle, const char *query, int limit, int *out_len)
{
	struct ndb *ndb = (struct ndb *)handle;
	struct ndb_txn txn;
	struct ndb_search search;
	char normalized_query[FLOW_NDB_PROFILE_SEARCH_KEY_SIZE];
	int search_started = 0;
	int appended = 0;
	int capacity = FLOW_NDB_JSON_INITIAL_CAPACITY;
	char *buffer;
	char *cursor;

	if (out_len != NULL) {
		*out_len = 0;
	}

	if (ndb == NULL || query == NULL || limit <= 0) {
		return NULL;
	}

	flow_ndb_normalized_profile_query(query, normalized_query, sizeof(normalized_query));
	if (normalized_query[0] == '\0') {
		return NULL;
	}

	if (!ndb_begin_query(ndb, &txn)) {
		return NULL;
	}

	buffer = malloc((size_t)capacity + 1);
	if (buffer == NULL) {
		ndb_end_query(&txn);
		return NULL;
	}

	cursor = buffer;
	cursor = flow_ndb_append_char(cursor, '[');

	if (ndb_search_profile(&txn, &search, normalized_query)) {
		search_started = 1;

		do {
			void *profile_data;
			size_t profile_size = 0;
			NdbProfileRecord_table_t record;
			NdbProfile_table_t profile;
			char *profile_json;
			char pubkey_hex[65];
			int profile_json_len = 0;
			int needed;
			ptrdiff_t cursor_offset;

			if (!flow_ndb_search_key_matches_query(search.key, normalized_query)) {
				break;
			}

			profile_data = ndb_get_profile_by_key(&txn, search.profile_key, &profile_size);
			if (profile_data == NULL) {
				continue;
			}

			record = NdbProfileRecord_as_root(profile_data);
			profile = NdbProfileRecord_profile(record);
			if (profile == NULL) {
				continue;
			}

			profile_json = flow_ndb_copy_profile_table_json(profile, &profile_json_len);
			if (profile_json == NULL || profile_json_len <= 0) {
				free(profile_json);
				continue;
			}

			flow_ndb_hex_encode(search.key->id, 32, pubkey_hex);
			needed = (int)(cursor - buffer) + profile_json_len + 128;
			cursor_offset = cursor - buffer;
			if (!flow_ndb_grow_buffer(&buffer, &capacity, needed)) {
				free(profile_json);
				free(buffer);
				if (search_started) {
					ndb_search_profile_end(&search);
				}
				ndb_end_query(&txn);
				return NULL;
			}
			cursor = buffer + cursor_offset;

			if (appended > 0) {
				cursor = flow_ndb_append_char(cursor, ',');
			}

			cursor = flow_ndb_append_char(cursor, '{');
			cursor = flow_ndb_append_json_string(cursor, "pubkey");
			cursor = flow_ndb_append_char(cursor, ':');
			cursor = flow_ndb_append_json_string(cursor, pubkey_hex);
			cursor = flow_ndb_append_char(cursor, ',');
			cursor = flow_ndb_append_json_string(cursor, "created_at");
			cursor = flow_ndb_append_char(cursor, ':');
			cursor = flow_ndb_append_uint64(cursor, search.key->timestamp);
			cursor = flow_ndb_append_char(cursor, ',');
			cursor = flow_ndb_append_json_string(cursor, "profile");
			cursor = flow_ndb_append_char(cursor, ':');
			cursor = flow_ndb_append_bytes(cursor, profile_json, (size_t)profile_json_len);
			cursor = flow_ndb_append_char(cursor, '}');

			appended += 1;
			free(profile_json);
		} while (appended < limit && ndb_search_profile_next(&search));
	}

	if (!flow_ndb_grow_buffer(&buffer, &capacity, (int)(cursor - buffer) + 2)) {
		free(buffer);
		if (search_started) {
			ndb_search_profile_end(&search);
		}
		ndb_end_query(&txn);
		return NULL;
	}

	cursor = flow_ndb_append_char(cursor, ']');
	*cursor = '\0';

	if (out_len != NULL) {
		*out_len = (int)(cursor - buffer);
	}

	if (search_started) {
		ndb_search_profile_end(&search);
	}
	ndb_end_query(&txn);
	return buffer;
}

void flow_ndb_free_string(char *value)
{
	free(value);
}
