#include "../include/corelm.h"
#include "../core/runtime/llama.h"
#include <string>
#include <memory>

using namespace corelm;

// ── Internal structures ─────────────────────────────────────

struct clm_context_impl {
    std::string backend = "cpu";
    int n_threads = 0;
    bool verbose = false;
    std::string last_error;

    clm_log_callback_t log_callback = nullptr;
    void* log_user_data = nullptr;
    clm_log_level_t log_min_level = CLM_LOG_INFO;
};

struct clm_model_impl {
    std::shared_ptr<LlamaModel> model;
    // Persistent strings for C API access
    std::string arch_str;
    std::string name_str;
    std::string quant_str;
};

struct clm_session_impl {
    clm_model_impl* model_ref = nullptr;
    uint32_t context_size = 0;
    uint32_t batch_size = 512;
};

// ── Context ─────────────────────────────────────────────────

clm_context_params_t clm_context_default_params(void) {
    clm_context_params_t p;
    p.backend = "auto";
    p.n_threads = 0;
    p.verbose_logging = false;
    return p;
}

clm_status_t clm_context_create(clm_context_params_t params, clm_context_t* out_ctx) {
    if (!out_ctx) return CLM_STATUS_INVALID_ARG;

    auto* ctx = new clm_context_impl();
    ctx->backend = params.backend ? params.backend : "auto";
    ctx->n_threads = params.n_threads;
    ctx->verbose = params.verbose_logging;
    *out_ctx = ctx;
    return CLM_STATUS_OK;
}

void clm_context_destroy(clm_context_t ctx) {
    delete ctx;
}

const char* clm_get_last_error(clm_context_t ctx) {
    if (!ctx) return "null context";
    return ctx->last_error.c_str();
}

// ── Model ───────────────────────────────────────────────────

clm_status_t clm_model_load(clm_context_t ctx, const char* file_path, clm_model_t* out_model) {
    if (!ctx || !file_path || !out_model) return CLM_STATUS_INVALID_ARG;

    auto* m = new clm_model_impl();
    m->model = std::make_shared<LlamaModel>();
    m->model->set_backend(ctx->backend);

    std::string error;
    if (!m->model->load(file_path, error)) {
        ctx->last_error = error;

        if (error.find("unsupported architecture") != std::string::npos) {
            delete m;
            return CLM_STATUS_UNSUPPORTED_ARCH;
        }
        if (error.find("unsupported quantization") != std::string::npos) {
            delete m;
            return CLM_STATUS_UNSUPPORTED_QUANT;
        }

        delete m;
        return CLM_STATUS_MODEL_ERROR;
    }

    // Cache strings for C API
    m->arch_str  = m->model->config().architecture;
    m->name_str  = m->model->config().name;
    m->quant_str = m->model->config().quantization;

    *out_model = m;
    return CLM_STATUS_OK;
}

clm_status_t clm_model_get_info(clm_model_t model, clm_model_info_t* out_info) {
    if (!model || !out_info) return CLM_STATUS_INVALID_ARG;

    auto& cfg = model->model->config();
    out_info->architecture    = model->arch_str.c_str();
    out_info->name            = model->name_str.c_str();
    out_info->quantization    = model->quant_str.c_str();
    out_info->parameter_count = 0; // computed from weights if needed
    out_info->file_size_bytes = model->model->metrics().memory_model;
    out_info->context_length  = cfg.max_context_length;
    out_info->embedding_length= cfg.hidden_size;
    out_info->num_layers      = cfg.num_layers;
    out_info->num_heads       = cfg.num_heads;
    out_info->num_kv_heads    = cfg.num_kv_heads;
    out_info->vocab_size      = cfg.vocab_size;

    return CLM_STATUS_OK;
}

void clm_model_unload(clm_model_t model) {
    delete model;
}

clm_status_t clm_model_validate(const char* file_path, clm_model_info_t* out_info) {
    if (!file_path) return CLM_STATUS_INVALID_ARG;

    auto result = gguf_validate(file_path);
    if (!result.valid) {
        return CLM_STATUS_MODEL_ERROR;
    }

    if (out_info) {
        // Minimal info from validation
        static std::string arch = result.architecture;
        static std::string name = result.model_name;
        static std::string quant = result.quantization;

        out_info->architecture = arch.c_str();
        out_info->name = name.c_str();
        out_info->quantization = quant.c_str();
        out_info->file_size_bytes = result.file_size;
    }

    return CLM_STATUS_OK;
}

// ── Session ─────────────────────────────────────────────────

clm_session_params_t clm_session_default_params(void) {
    clm_session_params_t p;
    p.context_size = 0;
    p.batch_size = 512;
    return p;
}

clm_status_t clm_session_create(clm_context_t ctx, clm_model_t model,
                                 clm_session_params_t params, clm_session_t* out_session) {
    if (!ctx || !model || !out_session) return CLM_STATUS_INVALID_ARG;
    if (!model->model || !model->model->is_loaded()) {
        ctx->last_error = "model not loaded";
        return CLM_STATUS_INVALID_STATE;
    }

    auto* s = new clm_session_impl();
    s->model_ref = model;
    s->context_size = params.context_size > 0 ? params.context_size : model->model->config().max_context_length;
    s->batch_size = params.batch_size > 0 ? params.batch_size : 512;

    *out_session = s;
    return CLM_STATUS_OK;
}

void clm_session_destroy(clm_session_t session) {
    delete session;
}

clm_status_t clm_session_reset(clm_session_t session) {
    if (!session || !session->model_ref) return CLM_STATUS_INVALID_STATE;
    session->model_ref->model->reset_session();
    return CLM_STATUS_OK;
}

// ── Generation ──────────────────────────────────────────────

clm_generation_params_t clm_generation_default_params(void) {
    clm_generation_params_t p;
    p.temperature = 0.7f;
    p.top_k = 40;
    p.top_p = 0.95f;
    p.repeat_penalty = 1.1f;
    p.max_tokens = 2048;
    p.seed = 0;
    return p;
}

clm_status_t clm_generate(clm_session_t session, const char* prompt,
                            clm_generation_params_t params,
                            clm_token_callback_t on_token, void* user_data) {
    if (!session || !session->model_ref || !prompt) return CLM_STATUS_INVALID_ARG;

    auto& model = session->model_ref->model;

    SamplerConfig sc;
    sc.temperature = params.temperature;
    sc.top_k = params.top_k;
    sc.top_p = params.top_p;
    sc.repeat_penalty = params.repeat_penalty;
    sc.seed = params.seed;

    // Bridge callback
    auto callback = [&](const char* text, int32_t token_id) -> bool {
        if (on_token) {
            return on_token(text, token_id, user_data);
        }
        return true;
    };

    std::string error;
    bool ok = model->generate(prompt, sc, params.max_tokens,
                               session->context_size, callback, error);

    if (!ok) {
        return CLM_STATUS_ERROR;
    }

    return CLM_STATUS_OK;
}

clm_status_t clm_generate_cancel(clm_session_t session) {
    if (!session || !session->model_ref) return CLM_STATUS_INVALID_STATE;
    session->model_ref->model->cancel();
    return CLM_STATUS_OK;
}

// ── Metrics ─────────────────────────────────────────────────

clm_status_t clm_get_metrics(clm_session_t session, clm_metrics_t* out_metrics) {
    if (!session || !session->model_ref || !out_metrics) return CLM_STATUS_INVALID_ARG;

    auto& m = session->model_ref->model->metrics();
    out_metrics->model_load_time_ms     = m.model_load_ms;
    out_metrics->prompt_eval_time_ms    = m.prompt_eval_ms;
    out_metrics->prompt_eval_tokens     = m.prompt_tokens;
    out_metrics->prompt_eval_tok_per_sec= m.prompt_tok_per_sec();
    out_metrics->generation_time_ms     = m.generation_ms;
    out_metrics->generation_tokens      = m.generation_tokens;
    out_metrics->generation_tok_per_sec = m.generation_tok_per_sec();
    out_metrics->time_to_first_token_ms = m.first_token_ms;
    out_metrics->memory_model_bytes     = m.memory_model;
    out_metrics->memory_kv_cache_bytes  = m.memory_cache;
    out_metrics->memory_scratch_bytes   = m.memory_scratch;
    out_metrics->context_tokens_used    = m.context_used;
    out_metrics->context_tokens_max     = m.context_max;
    // Get backend name from the model's active backend
    static std::string backend_str;
    backend_str = session->model_ref->model->backend_name();
    out_metrics->active_backend = backend_str.c_str();

    return CLM_STATUS_OK;
}

// ── Logging ─────────────────────────────────────────────────

void clm_set_log_callback(clm_context_t ctx, clm_log_callback_t callback,
                           void* user_data, clm_log_level_t min_level) {
    if (!ctx) return;
    ctx->log_callback = callback;
    ctx->log_user_data = user_data;
    ctx->log_min_level = min_level;
}
