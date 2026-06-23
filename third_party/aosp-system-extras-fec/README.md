# AOSP FEC host tool

This directory contains a minimal host `fec` tool for Android AVB hashtree
footer work.

Sources:

- `android-11.0.0_r48/`: sparse checkout of
  `platform/system/extras` from Android's official Gitiles mirror, limited to
  `verity/fec` and `libfec`.
- `external-fec-android-11.0.0_r48/`: shallow checkout of
  `platform/external/fec` from Android's official Gitiles mirror.

The built `bin/fec` implements the raw-image subset used by `avbtool.py`:

```text
fec --print-fec-size <data-size> --roots <n>
fec --encode --roots <n> <raw-image> <output-fec>
```

It deliberately does not implement sparse image decode/repair modes.

Run `./build-fec.sh` to fetch the ignored AOSP source checkouts when missing and
rebuild `bin/fec`.
