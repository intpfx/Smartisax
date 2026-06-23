// Copyright (c) 2026 Smartisax Authors.
//
// Uses Paddle Lite OCR pipeline code derived from Paddle-Lite-Demo, licensed
// under the Apache License, Version 2.0.

#include "pipeline.h"
#ifdef SMARTISAX_PADDLE_LITE_STATIC
#include "paddle_use_kernels.h" // NOLINT
#include "paddle_use_ops.h"     // NOLINT
#endif
#include <iomanip>
#include <jni.h>
#include <sstream>
#include <stdexcept>
#include <string>

namespace {

std::string JStringToString(JNIEnv *env, jstring value) {
  if (value == nullptr) {
    return "";
  }
  const char *chars = env->GetStringUTFChars(value, nullptr);
  if (chars == nullptr) {
    return "";
  }
  std::string out(chars);
  env->ReleaseStringUTFChars(value, chars);
  return out;
}

std::string JsonEscape(const std::string &value) {
  std::ostringstream out;
  for (unsigned char ch : value) {
    switch (ch) {
    case '"':
      out << "\\\"";
      break;
    case '\\':
      out << "\\\\";
      break;
    case '\b':
      out << "\\b";
      break;
    case '\f':
      out << "\\f";
      break;
    case '\n':
      out << "\\n";
      break;
    case '\r':
      out << "\\r";
      break;
    case '\t':
      out << "\\t";
      break;
    default:
      if (ch < 0x20) {
        out << "\\u" << std::hex << std::setw(4) << std::setfill('0')
            << static_cast<int>(ch) << std::dec << std::setfill(' ');
      } else {
        out << ch;
      }
      break;
    }
  }
  return out.str();
}

void AppendBoxJson(std::ostringstream *out,
                   const std::vector<std::vector<int>> &box) {
  *out << "[";
  for (size_t i = 0; i < box.size(); ++i) {
    if (i > 0) {
      *out << ",";
    }
    int x = box[i].empty() ? 0 : box[i][0];
    int y = box[i].size() < 2 ? 0 : box[i][1];
    *out << "[" << x << "," << y << "]";
  }
  *out << "]";
}

std::string ResultToJson(const OcrRunResult &result) {
  std::ostringstream out;
  out << std::fixed << std::setprecision(3);
  out << "{";
  out << "\"status\":\"" << JsonEscape(result.status) << "\",";
  out << "\"ok\":" << (result.ok ? "true" : "false") << ",";
  out << "\"image_width\":" << result.image_width << ",";
  out << "\"image_height\":" << result.image_height << ",";
  out << "\"det_ms\":" << result.det_ms << ",";
  out << "\"rec_ms\":" << result.rec_ms << ",";
  out << "\"total_ms\":" << result.total_ms << ",";
  if (!result.error.empty()) {
    out << "\"error\":\"" << JsonEscape(result.error) << "\",";
  }
  out << "\"lines\":[";
  for (size_t i = 0; i < result.lines.size(); ++i) {
    const OcrLine &line = result.lines[i];
    if (i > 0) {
      out << ",";
    }
    out << "{";
    out << "\"text\":\"" << JsonEscape(line.text) << "\",";
    out << "\"score\":" << line.score << ",";
    out << "\"box\":";
    AppendBoxJson(&out, line.box);
    out << "}";
  }
  out << "]}";
  return out.str();
}

std::string ErrorJson(const std::string &status, const std::string &error) {
  OcrRunResult result;
  result.status = status;
  result.error = error;
  return ResultToJson(result);
}

} // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_smartisax_ocrbench_MainActivity_nativeRunPpOcr(
    JNIEnv *env, jclass, jstring imagePath, jstring detModelPath,
    jstring clsModelPath, jstring recModelPath, jstring configPath,
    jstring labelPath, jint cpuThreadNum, jstring cpuPowerMode) {
  try {
    Pipeline pipeline(JStringToString(env, detModelPath),
                      JStringToString(env, clsModelPath),
                      JStringToString(env, recModelPath),
                      JStringToString(env, cpuPowerMode), cpuThreadNum,
                      JStringToString(env, configPath),
                      JStringToString(env, labelPath));
    return env->NewStringUTF(
        ResultToJson(pipeline.RunImage(JStringToString(env, imagePath)))
            .c_str());
  } catch (const std::exception &error) {
    return env->NewStringUTF(ErrorJson("PP_OCR_INIT_ERROR", error.what()).c_str());
  } catch (...) {
    return env->NewStringUTF(
        ErrorJson("PP_OCR_INIT_ERROR", "unknown native exception").c_str());
  }
}
