/*
 * Minimal host fec tool for avbtool.py.
 *
 * It implements the raw-image subset of AOSP system/extras/verity/fec using
 * Android's external/fec Reed-Solomon encoder:
 *   fec --print-fec-size <data-size> --roots <n>
 *   fec --encode --roots <n> <raw-image> <output-fec>
 */

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <CommonCrypto/CommonDigest.h>
#define FEC_SHA256(buf, len, out) CC_SHA256((buf), (CC_LONG)(len), (out))
#else
#include <openssl/sha.h>
#define FEC_SHA256(buf, len, out) SHA256((buf), (len), (out))
#endif

#include "fec.h"

#define FEC_BLOCKSIZE 4096U
#define FEC_DEFAULT_ROOTS 2
#define FEC_RSM 255
#define FEC_MAGIC 0xFECFECFEU
#define FEC_VERSION 0
#define FEC_SHA256_DIGEST_LENGTH 32

#define FEC_PARAMS(roots) \
  8,                      \
      0x11d,              \
      0,                  \
      1,                  \
      (roots),            \
      0

struct fec_header {
  uint32_t magic;
  uint32_t version;
  uint32_t size;
  uint32_t roots;
  uint32_t fec_size;
  uint64_t inp_size;
  uint8_t hash[FEC_SHA256_DIGEST_LENGTH];
} __attribute__((packed));

static uint64_t div_round_up(uint64_t x, uint64_t y) {
  return (x / y) + ((x % y) ? 1 : 0);
}

static uint64_t fec_size_for(uint64_t file_size, int roots) {
  return div_round_up(div_round_up(file_size, FEC_BLOCKSIZE),
                      FEC_RSM - (uint64_t)roots) *
             (uint64_t)roots * FEC_BLOCKSIZE +
         FEC_BLOCKSIZE;
}

static uint64_t interleave_offset(uint64_t offset, int rsn, uint64_t rounds) {
  return (offset / (uint64_t)rsn) +
         (offset % (uint64_t)rsn) * rounds * FEC_BLOCKSIZE;
}

static void usage(FILE *stream) {
  fprintf(stream,
          "fec: minimal raw-image FEC tool for avbtool.py\n"
          "usage:\n"
          "  fec --print-fec-size <data-size> --roots <n>\n"
          "  fec --encode --roots <n> <raw-image> <output-fec>\n");
}

static bool parse_u64(const char *text, uint64_t *out) {
  char *end = NULL;
  errno = 0;
  unsigned long long value = strtoull(text, &end, 0);
  if (!text[0] || *end || errno) {
    return false;
  }
  *out = (uint64_t)value;
  return true;
}

static uint8_t *read_all(const char *path, uint64_t *size_out) {
  int fd = open(path, O_RDONLY);
  if (fd < 0) {
    fprintf(stderr, "failed to open %s: %s\n", path, strerror(errno));
    return NULL;
  }

  struct stat st;
  if (fstat(fd, &st) != 0) {
    fprintf(stderr, "failed to stat %s: %s\n", path, strerror(errno));
    close(fd);
    return NULL;
  }
  if (st.st_size <= 0 || ((uint64_t)st.st_size % FEC_BLOCKSIZE) != 0) {
    fprintf(stderr, "input size must be a positive multiple of %u bytes\n",
            FEC_BLOCKSIZE);
    close(fd);
    return NULL;
  }

  uint64_t size = (uint64_t)st.st_size;
  uint8_t *buf = (uint8_t *)malloc((size_t)size);
  if (!buf) {
    fprintf(stderr, "failed to allocate %" PRIu64 " input bytes\n", size);
    close(fd);
    return NULL;
  }

  uint64_t done = 0;
  while (done < size) {
    uint64_t remaining = size - done;
    size_t chunk = remaining > (64ULL * 1024ULL * 1024ULL)
                       ? (64U * 1024U * 1024U)
                       : (size_t)remaining;
    ssize_t rc = read(fd, buf + done, chunk);
    if (rc < 0) {
      if (errno == EINTR) {
        continue;
      }
      fprintf(stderr, "failed to read %s: %s\n", path, strerror(errno));
      free(buf);
      close(fd);
      return NULL;
    }
    if (rc == 0) {
      fprintf(stderr, "unexpected EOF in %s\n", path);
      free(buf);
      close(fd);
      return NULL;
    }
    done += (uint64_t)rc;
  }

  close(fd);
  *size_out = size;
  return buf;
}

static bool write_all(int fd, const void *buf, size_t size) {
  const uint8_t *p = (const uint8_t *)buf;
  size_t done = 0;
  while (done < size) {
    ssize_t rc = write(fd, p + done, size - done);
    if (rc < 0) {
      if (errno == EINTR) {
        continue;
      }
      return false;
    }
    if (rc == 0) {
      return false;
    }
    done += (size_t)rc;
  }
  return true;
}

static int encode_file(const char *input_path, const char *output_path,
                       int roots) {
  uint64_t input_size = 0;
  uint8_t *input = read_all(input_path, &input_size);
  if (!input) {
    return 1;
  }

  int rsn = FEC_RSM - roots;
  uint64_t blocks = div_round_up(input_size, FEC_BLOCKSIZE);
  uint64_t rounds = div_round_up(blocks, (uint64_t)rsn);
  uint64_t fec_data_size_u64 = rounds * (uint64_t)roots * FEC_BLOCKSIZE;
  if (fec_data_size_u64 > UINT32_MAX) {
    fprintf(stderr, "fec data too large: %" PRIu64 "\n", fec_data_size_u64);
    free(input);
    return 1;
  }
  uint32_t fec_data_size = (uint32_t)fec_data_size_u64;
  uint8_t *fec = (uint8_t *)calloc(1, fec_data_size);
  if (!fec) {
    fprintf(stderr, "failed to allocate %u FEC bytes\n", fec_data_size);
    free(input);
    return 1;
  }

  void *rs = init_rs_char(FEC_PARAMS(roots));
  if (!rs) {
    fprintf(stderr, "failed to initialize RS encoder\n");
    free(fec);
    free(input);
    return 1;
  }

  uint8_t data[FEC_RSM];
  uint64_t fec_pos = 0;
  uint64_t end = rounds * (uint64_t)rsn * FEC_BLOCKSIZE;
  for (uint64_t i = 0; i < end; i += (uint64_t)rsn) {
    for (int j = 0; j < rsn; ++j) {
      uint64_t offset = interleave_offset(i + (uint64_t)j, rsn, rounds);
      data[j] = offset >= input_size ? 0 : input[offset];
    }
    encode_rs_char(rs, data, &fec[fec_pos]);
    fec_pos += (uint64_t)roots;
  }
  free_rs_char(rs);
  free(input);

  if (fec_pos != fec_data_size) {
    fprintf(stderr, "internal FEC size mismatch: %" PRIu64 " != %u\n",
            fec_pos, fec_data_size);
    free(fec);
    return 1;
  }

  uint8_t header_block[FEC_BLOCKSIZE] = {0};
  struct fec_header *header = (struct fec_header *)header_block;
  header->magic = FEC_MAGIC;
  header->version = FEC_VERSION;
  header->size = sizeof(struct fec_header);
  header->roots = (uint32_t)roots;
  header->fec_size = fec_data_size;
  header->inp_size = input_size;
  FEC_SHA256(fec, fec_data_size, header->hash);
  memcpy(&header_block[FEC_BLOCKSIZE - sizeof(struct fec_header)], header,
         sizeof(struct fec_header));

  int out = open(output_path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
  if (out < 0) {
    fprintf(stderr, "failed to open output %s: %s\n", output_path,
            strerror(errno));
    free(fec);
    return 1;
  }

  bool ok = write_all(out, fec, fec_data_size) &&
            write_all(out, header_block, sizeof(header_block));
  if (!ok) {
    fprintf(stderr, "failed to write %s: %s\n", output_path, strerror(errno));
  }
  close(out);
  free(fec);
  return ok ? 0 : 1;
}

int main(int argc, char **argv) {
  bool encode = false;
  bool print_size = false;
  int roots = FEC_DEFAULT_ROOTS;
  uint64_t print_input_size = 0;
  const char *positionals[2] = {0};
  int positional_count = 0;

  for (int i = 1; i < argc; ++i) {
    if (!strcmp(argv[i], "--encode") || !strcmp(argv[i], "-e")) {
      encode = true;
    } else if (!strcmp(argv[i], "--print-fec-size") || !strcmp(argv[i], "-s")) {
      if (++i >= argc || !parse_u64(argv[i], &print_input_size)) {
        usage(stderr);
        return 2;
      }
      print_size = true;
    } else if (!strcmp(argv[i], "--roots") || !strcmp(argv[i], "-r")) {
      uint64_t parsed = 0;
      if (++i >= argc || !parse_u64(argv[i], &parsed) || parsed == 0 ||
          parsed >= FEC_RSM) {
        usage(stderr);
        return 2;
      }
      roots = (int)parsed;
    } else if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
      usage(stdout);
      return 0;
    } else if (argv[i][0] == '-') {
      usage(stderr);
      return 2;
    } else {
      if (positional_count >= 2) {
        usage(stderr);
        return 2;
      }
      positionals[positional_count++] = argv[i];
    }
  }

  if (print_size) {
    if (encode || positional_count != 0) {
      usage(stderr);
      return 2;
    }
    printf("%" PRIu64 "\n", fec_size_for(print_input_size, roots));
    return 0;
  }

  if (!encode || positional_count != 2) {
    usage(stderr);
    return 2;
  }

  return encode_file(positionals[0], positionals[1], roots);
}
