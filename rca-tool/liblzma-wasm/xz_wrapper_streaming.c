#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <lzma.h>

// Streaming XZ decompressor that processes chunks without loading entire output
// Maximum chunk size for output (keeps memory bounded)
#define CHUNK_SIZE (1024 * 1024)  // 1MB chunks
#define INPUT_BUFFER_SIZE (256 * 1024)  // 256KB input buffer

// Opaque handle for streaming state
typedef struct {
    lzma_stream strm;
    int finished;
    int error_code;
    char error_msg[256];
} xz_stream_state;

// Initialize a streaming XZ decompressor
// Returns handle (opaque pointer) or NULL on failure
void* xz_stream_init(char *err_buf, size_t err_cap) {
    xz_stream_state *state = (xz_stream_state*) calloc(1, sizeof(xz_stream_state));
    if (!state) {
        if (err_buf && err_cap) strncpy(err_buf, "state alloc failed", err_cap-1);
        return NULL;
    }

    state->strm = (lzma_stream)LZMA_STREAM_INIT;
    lzma_ret ret = lzma_stream_decoder(&state->strm, UINT64_MAX, LZMA_CONCATENATED);
    if (ret != LZMA_OK) {
        if (err_buf && err_cap) strncpy(err_buf, "decoder init failed", err_cap-1);
        free(state);
        return NULL;
    }

    state->finished = 0;
    state->error_code = 0;
    state->error_msg[0] = '\0';
    return (void*)state;
}

// Process a chunk of compressed input
// Returns: allocated output buffer (caller must free via free()), or NULL if no output yet or error
// Sets *out_len to output size (0 if no output)
// Sets *status: 0=need more input, 1=stream finished, <0=error
uint8_t* xz_stream_process(void *handle, const uint8_t *in, size_t in_len, size_t *out_len, int *status) {
    if (!handle || !out_len || !status) {
        if (status) *status = -1;
        if (out_len) *out_len = 0;
        return NULL;
    }

    xz_stream_state *state = (xz_stream_state*)handle;
    *out_len = 0;
    *status = 0;

    if (state->finished) {
        *status = 1;
        return NULL;
    }

    if (state->error_code) {
        *status = state->error_code;
        return NULL;
    }

    // Allocate output buffer for this chunk (2MB to handle larger decompressed chunks)
    size_t out_capacity = CHUNK_SIZE * 2;
    uint8_t *out_buf = (uint8_t*) malloc(out_capacity);
    if (!out_buf) {
        state->error_code = -2;
        strncpy(state->error_msg, "output buffer alloc failed", sizeof(state->error_msg)-1);
        *status = -2;
        return NULL;
    }

    // Set input
    state->strm.next_in = in;
    state->strm.avail_in = in_len;

    // Set output
    state->strm.next_out = out_buf;
    state->strm.avail_out = out_capacity;

    size_t total_output = 0;

    // Keep decoding while we have input OR while the decoder produces output
    // This handles cases where one compressed chunk expands to multiple output chunks
    lzma_action action = (in_len == 0) ? LZMA_FINISH : LZMA_RUN;
    lzma_ret ret;
    
    do {
        size_t out_before = state->strm.avail_out;
        ret = lzma_code(&state->strm, action);
        size_t produced = out_before - state->strm.avail_out;
        total_output += produced;

        if (ret == LZMA_STREAM_END) {
            state->finished = 1;
            *out_len = total_output;
            *status = 1;  // finished
            if (total_output == 0) {
                free(out_buf);
                return NULL;
            }
            return out_buf;
        } else if (ret == LZMA_OK) {
            // Continue if output buffer is full (more data available)
            // or if we consumed input but haven't exhausted the internal buffers
            if (state->strm.avail_out == 0) {
                // Need to expand output buffer
                out_capacity *= 2;
                uint8_t *new_buf = (uint8_t*) realloc(out_buf, out_capacity);
                if (!new_buf) {
                    state->error_code = -2;
                    strncpy(state->error_msg, "output buffer realloc failed", sizeof(state->error_msg)-1);
                    *status = -2;
                    free(out_buf);
                    return NULL;
                }
                out_buf = new_buf;
                state->strm.next_out = out_buf + total_output;
                state->strm.avail_out = out_capacity - total_output;
            } else {
                // No more output available, need more input
                break;
            }
        } else {
            // Error
            state->error_code = -(int)ret;
            // Error
            state->error_code = -(int)ret;
            switch (ret) {
                case LZMA_MEM_ERROR: 
                    strncpy(state->error_msg, "memory error", sizeof(state->error_msg)-1); 
                    break;
                case LZMA_MEMLIMIT_ERROR: 
                    strncpy(state->error_msg, "memory limit", sizeof(state->error_msg)-1); 
                    break;
                case LZMA_FORMAT_ERROR: 
                    strncpy(state->error_msg, "format error", sizeof(state->error_msg)-1); 
                    break;
                case LZMA_OPTIONS_ERROR: 
                    strncpy(state->error_msg, "options error", sizeof(state->error_msg)-1); 
                    break;
                case LZMA_DATA_ERROR: 
                    strncpy(state->error_msg, "data error", sizeof(state->error_msg)-1); 
                    break;
                case LZMA_BUF_ERROR:
                    strncpy(state->error_msg, "buffer error", sizeof(state->error_msg)-1);
                    break;
                default: 
                    strncpy(state->error_msg, "decode error", sizeof(state->error_msg)-1); 
                    break;
            }
            *status = state->error_code;
            free(out_buf);
            return NULL;
        }
    } while (ret == LZMA_OK);

    // Return output if any
    *out_len = total_output;
    *status = 0;  // need more input
    if (total_output == 0) {
        free(out_buf);
        return NULL;
    }
    return out_buf;
}

// Get error message from state
const char* xz_stream_error(void *handle) {
    if (!handle) return "invalid handle";
    xz_stream_state *state = (xz_stream_state*)handle;
    return state->error_msg[0] ? state->error_msg : "no error";
}

// Clean up streaming state
void xz_stream_free(void *handle) {
    if (!handle) return;
    xz_stream_state *state = (xz_stream_state*)handle;
    lzma_end(&state->strm);
    free(state);
}

// Original non-streaming function (kept for backward compatibility)
int xz_decompress(const uint8_t *in, size_t in_len, uint8_t **out_ptr, size_t *out_len, char *err_buf, size_t err_cap) {
    if (!in || !out_ptr || !out_len) {
        if (err_buf && err_cap) strncpy(err_buf, "invalid arguments", err_cap-1);
        return 1;
    }
    *out_ptr = NULL;
    *out_len = 0;

    lzma_stream strm = LZMA_STREAM_INIT;
    lzma_ret ret = lzma_stream_decoder(&strm, UINT64_MAX, LZMA_CONCATENATED);
    if (ret != LZMA_OK) {
        if (err_buf && err_cap) strncpy(err_buf, "decoder init failed", err_cap-1);
        return 2;
    }

    strm.next_in = in;
    strm.avail_in = in_len;

    size_t cap = in_len * 4;
    if (cap < 1024 * 1024) cap = 1024 * 1024;
    if (cap > (2048ULL * 1024ULL * 1024ULL)) cap = (2048ULL * 1024ULL * 1024ULL);

    uint8_t *out = (uint8_t*) malloc(cap);
    if (!out) {
        if (err_buf && err_cap) strncpy(err_buf, "malloc failed", err_cap-1);
        lzma_end(&strm);
        return 3;
    }

    size_t written = 0;

    while (1) {
        strm.next_out = out + written;
        strm.avail_out = (cap - written);

        if (strm.avail_out == 0) {
            size_t new_cap = cap * 2;
            if (new_cap > (2048ULL * 1024ULL * 1024ULL)) {
                new_cap = (2048ULL * 1024ULL * 1024ULL);
            }
            if (new_cap <= cap) {
                if (err_buf && err_cap) strncpy(err_buf, "exceeded max output size", err_cap-1);
                free(out);
                lzma_end(&strm);
                return 4;
            }
            uint8_t *tmp = (uint8_t*) realloc(out, new_cap);
            if (!tmp) {
                if (err_buf && err_cap) strncpy(err_buf, "realloc failed", err_cap-1);
                free(out);
                lzma_end(&strm);
                return 5;
            }
            out = tmp;
            cap = new_cap;
            continue;
        }

        ret = lzma_code(&strm, LZMA_FINISH);
        if (ret == LZMA_STREAM_END) {
            written = cap - strm.avail_out;
            break;
        } else if (ret != LZMA_OK) {
            if (err_buf && err_cap) {
                switch (ret) {
                    case LZMA_MEM_ERROR: strncpy(err_buf, "mem error", err_cap-1); break;
                    case LZMA_MEMLIMIT_ERROR: strncpy(err_buf, "memlimit", err_cap-1); break;
                    case LZMA_FORMAT_ERROR: strncpy(err_buf, "format error", err_cap-1); break;
                    case LZMA_OPTIONS_ERROR: strncpy(err_buf, "options error", err_cap-1); break;
                    case LZMA_DATA_ERROR: strncpy(err_buf, "data error", err_cap-1); break;
                    default: strncpy(err_buf, "decode error", err_cap-1); break;
                }
            }
            free(out);
            lzma_end(&strm);
            return 6;
        }

        written = cap - strm.avail_out;
    }

    lzma_end(&strm);
    *out_ptr = out;
    *out_len = written;
    return 0;
}
