// PassVault: KeePass AES-KDF（AES-256 ECB 多轮变换）原生实现。
// AES 加密部分为精简的 AES-256 软件实现（仅加密方向），结构参考公共领域的 tiny-AES-c。
#include <stdint.h>
#include <string.h>

#if defined(_WIN32)
#define PV_EXPORT __declspec(dllexport)
#else
#define PV_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#define NB 4
#define NK 8
#define NR 14

static const uint8_t sbox[256] = {
  0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
  0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
  0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
  0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
  0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
  0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
  0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
  0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
  0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
  0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
  0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
  0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
  0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
  0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
  0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
  0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16};

static const uint8_t rcon[11] = {0x8d,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36};

static void key_expansion(uint8_t *rk, const uint8_t *key) {
  unsigned i, j, k;
  uint8_t t[4];
  for (i = 0; i < NK; ++i) {
    rk[i * 4 + 0] = key[i * 4 + 0];
    rk[i * 4 + 1] = key[i * 4 + 1];
    rk[i * 4 + 2] = key[i * 4 + 2];
    rk[i * 4 + 3] = key[i * 4 + 3];
  }
  for (i = NK; i < NB * (NR + 1); ++i) {
    k = (i - 1) * 4;
    t[0] = rk[k + 0]; t[1] = rk[k + 1]; t[2] = rk[k + 2]; t[3] = rk[k + 3];
    if (i % NK == 0) {
      const uint8_t u = t[0];
      t[0] = sbox[t[1]] ^ rcon[i / NK];
      t[1] = sbox[t[2]];
      t[2] = sbox[t[3]];
      t[3] = sbox[u];
    } else if (i % NK == 4) {
      t[0] = sbox[t[0]]; t[1] = sbox[t[1]]; t[2] = sbox[t[2]]; t[3] = sbox[t[3]];
    }
    j = i * 4; k = (i - NK) * 4;
    rk[j + 0] = rk[k + 0] ^ t[0];
    rk[j + 1] = rk[k + 1] ^ t[1];
    rk[j + 2] = rk[k + 2] ^ t[2];
    rk[j + 3] = rk[k + 3] ^ t[3];
  }
}

static uint8_t xtime(uint8_t x) { return (uint8_t)((x << 1) ^ (((x >> 7) & 1) * 0x1b)); }

static void encrypt_block(uint8_t s[16], const uint8_t *rk) {
  uint8_t r, i, t, tmp, tm, a;
  for (i = 0; i < 16; ++i) s[i] ^= rk[i];
  for (r = 1;; ++r) {
    // SubBytes
    for (i = 0; i < 16; ++i) s[i] = sbox[s[i]];
    // ShiftRows（列主序：s[col*4+row]）
    t = s[1]; s[1] = s[5]; s[5] = s[9]; s[9] = s[13]; s[13] = t;
    t = s[2]; s[2] = s[10]; s[10] = t; t = s[6]; s[6] = s[14]; s[14] = t;
    t = s[3]; s[3] = s[15]; s[15] = s[11]; s[11] = s[7]; s[7] = t;
    if (r == NR) break;
    // MixColumns
    for (i = 0; i < 4; ++i) {
      uint8_t *c = s + i * 4;
      a = c[0];
      tmp = c[0] ^ c[1] ^ c[2] ^ c[3];
      tm = xtime(c[0] ^ c[1]); c[0] ^= tm ^ tmp;
      tm = xtime(c[1] ^ c[2]); c[1] ^= tm ^ tmp;
      tm = xtime(c[2] ^ c[3]); c[2] ^= tm ^ tmp;
      tm = xtime(c[3] ^ a);    c[3] ^= tm ^ tmp;
    }
    for (i = 0; i < 16; ++i) s[i] ^= rk[r * 16 + i];
  }
  for (i = 0; i < 16; ++i) s[i] ^= rk[NR * 16 + i];
}

/* ---------- 硬件加速：x86 AES-NI ---------- */
#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#define PV_HAVE_X86 1
#include <wmmintrin.h>
#include <emmintrin.h>
#if defined(_MSC_VER)
#include <intrin.h>
static int cpu_has_aes(void) {
  int info[4];
  __cpuid(info, 1);
  return (info[2] >> 25) & 1;
}
#define PV_TARGET_AES
#else
#include <cpuid.h>
static int cpu_has_aes(void) {
  unsigned a, b, c, d;
  if (!__get_cpuid(1, &a, &b, &c, &d)) return 0;
  return (c >> 25) & 1;
}
#define PV_TARGET_AES __attribute__((target("aes,sse2")))
#endif

PV_TARGET_AES
static void kdf_hw(const uint8_t *rk, uint8_t *data, uint64_t rounds) {
  __m128i k[NR + 1];
  int r;
  uint64_t n;
  __m128i b0 = _mm_loadu_si128((const __m128i *)data);
  __m128i b1 = _mm_loadu_si128((const __m128i *)(data + 16));
  for (r = 0; r <= NR; ++r) k[r] = _mm_loadu_si128((const __m128i *)(rk + r * 16));
  for (n = 0; n < rounds; ++n) {
    b0 = _mm_xor_si128(b0, k[0]);
    b1 = _mm_xor_si128(b1, k[0]);
    for (r = 1; r < NR; ++r) {
      b0 = _mm_aesenc_si128(b0, k[r]);
      b1 = _mm_aesenc_si128(b1, k[r]);
    }
    b0 = _mm_aesenclast_si128(b0, k[NR]);
    b1 = _mm_aesenclast_si128(b1, k[NR]);
  }
  _mm_storeu_si128((__m128i *)data, b0);
  _mm_storeu_si128((__m128i *)(data + 16), b1);
  for (r = 0; r <= NR; ++r) k[r] = _mm_setzero_si128();
}
#endif

/* ---------- 硬件加速：ARMv8 Crypto Extensions（安卓 arm64） ---------- */
#if defined(__aarch64__)
#define PV_HAVE_ARM 1
#include <arm_neon.h>
#if defined(__ANDROID__) || defined(__linux__)
#include <sys/auxv.h>
#ifndef HWCAP_AES
#define HWCAP_AES (1 << 3)
#endif
static int cpu_has_aes(void) { return (getauxval(AT_HWCAP) & HWCAP_AES) != 0; }
#else
static int cpu_has_aes(void) { return 1; }
#endif

__attribute__((target("aes")))
static void kdf_hw(const uint8_t *rk, uint8_t *data, uint64_t rounds) {
  uint8x16_t k[NR + 1];
  int r;
  uint64_t n;
  uint8x16_t b0 = vld1q_u8(data);
  uint8x16_t b1 = vld1q_u8(data + 16);
  for (r = 0; r <= NR; ++r) k[r] = vld1q_u8(rk + r * 16);
  for (n = 0; n < rounds; ++n) {
    for (r = 0; r < NR - 1; ++r) {
      b0 = vaesmcq_u8(vaeseq_u8(b0, k[r]));
      b1 = vaesmcq_u8(vaeseq_u8(b1, k[r]));
    }
    b0 = veorq_u8(vaeseq_u8(b0, k[NR - 1]), k[NR]);
    b1 = veorq_u8(vaeseq_u8(b1, k[NR - 1]), k[NR]);
  }
  vst1q_u8(data, b0);
  vst1q_u8(data + 16, b1);
}
#endif

/* 返回当前设备是否使用了硬件 AES（供界面显示/测试） */
PV_EXPORT int32_t pv_aes_hw_available(void) {
#if defined(PV_HAVE_X86) || defined(PV_HAVE_ARM)
  return cpu_has_aes();
#else
  return 0;
#endif
}

/* 软件路径，force_soft 用于测试两条路径结果一致 */
PV_EXPORT int32_t pv_aes_kdf_ex(const uint8_t *key, uint8_t *data, uint64_t rounds, int32_t force_soft) {
  uint8_t rk[NB * (NR + 1) * 4];
  uint64_t n;
  key_expansion(rk, key);
#if defined(PV_HAVE_X86) || defined(PV_HAVE_ARM)
  if (!force_soft && cpu_has_aes()) {
    kdf_hw(rk, data, rounds);
    memset(rk, 0, sizeof(rk));
    return 1;
  }
#endif
  for (n = 0; n < rounds; ++n) {
    encrypt_block(data, rk);
    encrypt_block(data + 16, rk);
  }
  memset(rk, 0, sizeof(rk));
  return 0;
}

// 对 32 字节 data 用 32 字节 key 执行 rounds 轮 AES-256-ECB，结果写回 data。
PV_EXPORT int32_t pv_aes_kdf(const uint8_t *key, uint8_t *data, uint64_t rounds) {
  return pv_aes_kdf_ex(key, data, rounds, 0);
}
