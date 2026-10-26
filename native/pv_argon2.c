// PassVault: 精简的 Argon2 FFI 导出，支持 Argon2d / Argon2i / Argon2id。
#include <stdint.h>
#include <stddef.h>
#include "argon2/argon2.h"

#if defined(_WIN32)
#define PV_EXPORT __declspec(dllexport)
#else
#define PV_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// type: 0 = Argon2d, 1 = Argon2i, 2 = Argon2id
// 返回 0 表示成功，其余为 argon2 错误码。
PV_EXPORT int32_t pv_argon2_hash(const uint8_t *pwd, uint32_t pwdlen,
                                 const uint8_t *salt, uint32_t saltlen,
                                 uint32_t m_cost, uint32_t t_cost,
                                 uint32_t parallelism, uint32_t version,
                                 uint32_t type, uint8_t *out,
                                 uint32_t outlen) {
  argon2_context ctx;
  ctx.out = out;
  ctx.outlen = outlen;
  ctx.pwd = (uint8_t *)pwd;
  ctx.pwdlen = pwdlen;
  ctx.salt = (uint8_t *)salt;
  ctx.saltlen = saltlen;
  ctx.secret = NULL;
  ctx.secretlen = 0;
  ctx.ad = NULL;
  ctx.adlen = 0;
  ctx.t_cost = t_cost;
  ctx.m_cost = m_cost;
  ctx.lanes = parallelism;
  ctx.threads = parallelism;
  ctx.allocate_cbk = NULL;
  ctx.free_cbk = NULL;
  ctx.flags = ARGON2_DEFAULT_FLAGS;
  ctx.version = version;
  argon2_type t = type == 0 ? Argon2_d : (type == 1 ? Argon2_i : Argon2_id);
  return argon2_ctx(&ctx, t);
}

PV_EXPORT int32_t pv_argon2_selftest(void) { return 42; }
