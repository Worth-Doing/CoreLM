#ifndef CORELM_H
#define CORELM_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ──────────────────────────────────────────────
   Status codes
   ────────────────────────────────────────────── */

typedef enum {
    CLM_STATUS_OK               = 0,
    CLM_STATUS_ERROR            = 1,
    CLM_STATUS_INVALID_ARG      = 2,
    CLM_STATUS_FILE_ERROR       = 3,
    CLM_STATUS_UNSUPPORTED_ARCH = 4,
    CLM_STATUS_UNSUPPORTED_QUANT= 5,
    CLM_STATUS_MEMORY_ERROR     = 6,
    CLM_STATUS_BACKEND_ERROR    = 7,
    CLM_STATUS_CANCELLED        = 8,
    CLM_STATUS_INVALID_STATE    = 9,
    CLM_STATUS_MODEL_ERROR      = 10,
} clm_status_t;

/* ──────────────────────────────────────────────
   Opaque handles
   ────────────────────────────────────────────── */

typedef struct clm_context_impl*  clm_context_t;
typedef struct clm_model_impl*    clm_model_t;
typedef struct clm_session_impl*  clm_session_t;

/* ──────────────────────────────────────────────
   Context lifecycle
   ────────────────────────────────────────────── */

typedef struct {
    const char* backend;
    int         n_threads;
    bool        verbose_logging;
} clm_context_params_t;

clm_context_params_t clm_context_default_params(void);

clm_status_t clm_context_create(
    clm_context_params_t params,
    clm_context_t*       out_ctx
);

void clm_context_destroy(clm_context_t ctx);

const char* clm_get_last_error(clm_context_t ctx);

/* ──────────────────────────────────────────────
   Model loading
   ────────────────────────────────────────────── */

typedef struct {
    const char* architecture;
    const char* name;
    const char* quantization;
    uint64_t    parameter_count;
    uint64_t    file_size_bytes;
    uint32_t    context_length;
    uint32_t    embedding_length;
    uint32_t    num_layers;
    uint32_t    num_heads;
    uint32_t    num_kv_heads;
    uint32_t    vocab_size;
} clm_model_info_t;

clm_status_t clm_model_load(
    clm_context_t   ctx,
    const char*     file_path,
    clm_model_t*    out_model
);

clm_status_t clm_model_get_info(
    clm_model_t         model,
    clm_model_info_t*   out_info
);

void clm_model_unload(clm_model_t model);

clm_status_t clm_model_validate(
    const char*         file_path,
    clm_model_info_t*   out_info
);

/* ──────────────────────────────────────────────
   Session management
   ────────────────────────────────────────────── */

typedef struct {
    uint32_t context_size;
    uint32_t batch_size;
} clm_session_params_t;

clm_session_params_t clm_session_default_params(void);

clm_status_t clm_session_create(
    clm_context_t         ctx,
    clm_model_t           model,
    clm_session_params_t  params,
    clm_session_t*        out_session
);

void clm_session_destroy(clm_session_t session);

clm_status_t clm_session_reset(clm_session_t session);

/* ──────────────────────────────────────────────
   Generation
   ────────────────────────────────────────────── */

typedef struct {
    float    temperature;
    int32_t  top_k;
    float    top_p;
    float    repeat_penalty;
    int32_t  max_tokens;
    uint64_t seed;
} clm_generation_params_t;

clm_generation_params_t clm_generation_default_params(void);

typedef bool (*clm_token_callback_t)(
    const char* token_text,
    int32_t     token_id,
    void*       user_data
);

clm_status_t clm_generate(
    clm_session_t             session,
    const char*               prompt,
    clm_generation_params_t   params,
    clm_token_callback_t      on_token,
    void*                     user_data
);

clm_status_t clm_generate_cancel(clm_session_t session);

/* ──────────────────────────────────────────────
   Metrics
   ────────────────────────────────────────────── */

typedef struct {
    double   model_load_time_ms;
    double   prompt_eval_time_ms;
    int32_t  prompt_eval_tokens;
    double   prompt_eval_tok_per_sec;
    double   generation_time_ms;
    int32_t  generation_tokens;
    double   generation_tok_per_sec;
    double   time_to_first_token_ms;
    int64_t  memory_model_bytes;
    int64_t  memory_kv_cache_bytes;
    int64_t  memory_scratch_bytes;
    int32_t  context_tokens_used;
    int32_t  context_tokens_max;
    const char* active_backend;
} clm_metrics_t;

clm_status_t clm_get_metrics(
    clm_session_t   session,
    clm_metrics_t*  out_metrics
);

/* ──────────────────────────────────────────────
   Logging
   ────────────────────────────────────────────── */

typedef enum {
    CLM_LOG_TRACE = 0,
    CLM_LOG_DEBUG = 1,
    CLM_LOG_INFO  = 2,
    CLM_LOG_WARN  = 3,
    CLM_LOG_ERROR = 4,
} clm_log_level_t;

typedef void (*clm_log_callback_t)(
    clm_log_level_t level,
    const char*     message,
    void*           user_data
);

void clm_set_log_callback(
    clm_context_t        ctx,
    clm_log_callback_t   callback,
    void*                user_data,
    clm_log_level_t      min_level
);

#ifdef __cplusplus
}
#endif

#endif /* CORELM_H */
