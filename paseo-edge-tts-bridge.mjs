#!/usr/bin/env node
import { createServer } from "node:http";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";

const HOST = process.env.HOST || "127.0.0.1";
const PORT = Number(process.env.PORT || 5055);
const DEFAULT_VOICE = process.env.EDGE_TTS_VOICE || "zh-CN-XiaoxiaoNeural";
const DEFAULT_ASR_ENGINE = process.env.ASR_ENGINE || "whisper";
const DEFAULT_WHISPER_MODEL = process.env.WHISPER_MODEL || "base";
const DEFAULT_ASR_LANGUAGE = process.env.ASR_LANGUAGE || "zh";

const OPENAI_VOICE_MAP = {
  alloy: "zh-CN-XiaoxiaoNeural",
  shimmer: "zh-CN-XiaoxiaoNeural",
  nova: "zh-CN-XiaoyiNeural",
  echo: "zh-CN-YunxiNeural",
  fable: "zh-CN-YunjianNeural",
  onyx: "zh-CN-YunyangNeural",
};

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"], ...options });
    let stderr = "";
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(`${command} exited with ${code}: ${stderr.trim()}`));
    });
  });
}

function runCapture(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"], ...options });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
        return;
      }
      reject(new Error(`${command} exited with ${code}: ${stderr.trim() || stdout.trim()}`));
    });
  });
}

async function readBodyBuffer(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function readJsonBody(req) {
  const raw = (await readBodyBuffer(req)).toString("utf8");
  return raw ? JSON.parse(raw) : {};
}

function resolveVoice(voice) {
  if (!voice) return DEFAULT_VOICE;
  return OPENAI_VOICE_MAP[String(voice).toLowerCase()] || String(voice);
}

function edgeTtsArgs({ text, voice, output }) {
  const args = ["--voice", voice, "--text", text, "--write-media", output];
  if (process.env.EDGE_TTS_RATE) args.push("--rate", process.env.EDGE_TTS_RATE);
  if (process.env.EDGE_TTS_VOLUME) args.push("--volume", process.env.EDGE_TTS_VOLUME);
  if (process.env.EDGE_TTS_PITCH) args.push("--pitch", process.env.EDGE_TTS_PITCH);
  return args;
}

async function synthesize({ input, voice, responseFormat }) {
  const text = String(input || "").trim();
  if (!text) {
    const error = new Error("input is required");
    error.statusCode = 400;
    throw error;
  }

  const tempDir = await mkdtemp(join(tmpdir(), "paseo-edge-tts-"));
  const mp3Path = join(tempDir, "speech.mp3");
  const resolvedVoice = resolveVoice(voice);
  const format = String(responseFormat || "mp3").toLowerCase();

  try {
    await run("edge-tts", edgeTtsArgs({ text, voice: resolvedVoice, output: mp3Path }));

    if (format === "pcm") {
      const pcmPath = join(tempDir, "speech.pcm");
      await run("ffmpeg", [
        "-y",
        "-v",
        "error",
        "-i",
        mp3Path,
        "-f",
        "s16le",
        "-acodec",
        "pcm_s16le",
        "-ac",
        "1",
        "-ar",
        "24000",
        pcmPath,
      ]);
      return {
        body: await readFile(pcmPath),
        contentType: "application/octet-stream",
        format: "pcm",
        voice: resolvedVoice,
      };
    }

    if (format === "wav") {
      const wavPath = join(tempDir, "speech.wav");
      await run("ffmpeg", ["-y", "-v", "error", "-i", mp3Path, wavPath]);
      return {
        body: await readFile(wavPath),
        contentType: "audio/wav",
        format: "wav",
        voice: resolvedVoice,
      };
    }

    return {
      body: await readFile(mp3Path),
      contentType: "audio/mpeg",
      format: "mp3",
      voice: resolvedVoice,
    };
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

function parseContentDisposition(value) {
  const result = {};
  for (const part of value.split(";")) {
    const [rawKey, ...rawRest] = part.trim().split("=");
    if (!rawKey || rawRest.length === 0) continue;
    const rawValue = rawRest.join("=");
    result[rawKey.toLowerCase()] = rawValue.replace(/^"|"$/g, "");
  }
  return result;
}

function parseMultipart(body, contentType) {
  const boundaryMatch = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(contentType || "");
  const boundary = boundaryMatch?.[1] || boundaryMatch?.[2];
  if (!boundary) {
    const error = new Error("multipart boundary is required");
    error.statusCode = 400;
    throw error;
  }

  const delimiter = Buffer.from(`--${boundary}`);
  const fields = {};
  const files = {};
  let cursor = body.indexOf(delimiter);

  while (cursor !== -1) {
    cursor += delimiter.length;
    if (body[cursor] === 45 && body[cursor + 1] === 45) break;
    if (body[cursor] === 13 && body[cursor + 1] === 10) cursor += 2;

    const next = body.indexOf(delimiter, cursor);
    if (next === -1) break;

    let part = body.subarray(cursor, next);
    if (part.length >= 2 && part[part.length - 2] === 13 && part[part.length - 1] === 10) {
      part = part.subarray(0, part.length - 2);
    }

    const headerEnd = part.indexOf(Buffer.from("\r\n\r\n"));
    if (headerEnd !== -1) {
      const headerText = part.subarray(0, headerEnd).toString("utf8");
      const content = part.subarray(headerEnd + 4);
      const headers = Object.fromEntries(
        headerText
          .split("\r\n")
          .map((line) => {
            const sep = line.indexOf(":");
            if (sep === -1) return null;
            return [line.slice(0, sep).trim().toLowerCase(), line.slice(sep + 1).trim()];
          })
          .filter(Boolean),
      );
      const disposition = parseContentDisposition(headers["content-disposition"] || "");
      if (disposition.name) {
        if (disposition.filename) {
          files[disposition.name] = {
            filename: disposition.filename,
            contentType: headers["content-type"] || "application/octet-stream",
            data: content,
          };
        } else {
          fields[disposition.name] = content.toString("utf8");
        }
      }
    }

    cursor = next;
  }

  return { fields, files };
}

function fileExtension(filename, contentType) {
  const fromName = /\.[A-Za-z0-9]+$/.exec(filename || "")?.[0];
  if (fromName) return fromName.toLowerCase();
  if ((contentType || "").includes("wav")) return ".wav";
  if ((contentType || "").includes("mpeg") || (contentType || "").includes("mp3")) return ".mp3";
  if ((contentType || "").includes("webm")) return ".webm";
  if ((contentType || "").includes("ogg")) return ".ogg";
  return ".wav";
}

function extractTranscriptText(result) {
  if (!result || typeof result !== "object") return "";
  if (typeof result.text === "string") return result.text;
  if (typeof result.transcript === "string") return result.transcript;
  if (typeof result.result === "string") return result.result;
  if (Array.isArray(result.segments)) {
    return result.segments
      .map((segment) => segment?.text)
      .filter((text) => typeof text === "string")
      .join("");
  }
  return "";
}

function resolveWhisperModel(model) {
  const requested = String(model || "").trim();
  if (!requested) return DEFAULT_WHISPER_MODEL;
  if (
    requested === "whisper-1" ||
    requested === "gpt-4o-transcribe" ||
    requested === "gpt-4o-mini-transcribe"
  ) {
    return DEFAULT_WHISPER_MODEL;
  }
  return requested;
}

async function transcribe({ audio, filename, contentType, model }) {
  if (!audio?.length) {
    const error = new Error("file is required");
    error.statusCode = 400;
    throw error;
  }

  const tempDir = await mkdtemp(join(tmpdir(), "paseo-asr-"));
  const inputPath = join(tempDir, `input${fileExtension(filename, contentType)}`);
  const asrEngine = DEFAULT_ASR_ENGINE;
  const asrModel =
    asrEngine === "coli" ? process.env.COLI_ASR_MODEL || model || "sensevoice" : resolveWhisperModel(model);

  try {
    await writeFile(inputPath, audio);

    let parsed;
    if (asrEngine === "coli") {
      const { stdout } = await runCapture("coli", ["asr", "-j", "--model", asrModel, inputPath], {
        env: { ...process.env, NO_COLOR: "1" },
      });
      const jsonStart = stdout.indexOf("{");
      const jsonText = jsonStart >= 0 ? stdout.slice(jsonStart) : stdout;
      parsed = JSON.parse(jsonText);
    } else {
      await run("whisper", [
        inputPath,
        "--model",
        asrModel,
        "--language",
        DEFAULT_ASR_LANGUAGE,
        "--output_format",
        "json",
        "--output_dir",
        tempDir,
        "--verbose",
        "False",
      ]);
      parsed = JSON.parse(await readFile(join(tempDir, "input.json"), "utf8"));
    }

    return {
      text: extractTranscriptText(parsed).trim(),
      raw: parsed,
      engine: asrEngine,
      model: asrModel,
    };
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

function sendJson(res, statusCode, payload) {
  const body = Buffer.from(JSON.stringify(payload, null, 2));
  res.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "content-length": body.length,
  });
  res.end(body);
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || `${HOST}:${PORT}`}`);

    if (req.method === "GET" && url.pathname === "/health") {
      sendJson(res, 200, {
        ok: true,
        provider: "edge-tts+local-asr",
        defaultVoice: DEFAULT_VOICE,
        asrEngine: DEFAULT_ASR_ENGINE,
        asrModel: DEFAULT_ASR_ENGINE === "coli" ? process.env.COLI_ASR_MODEL || "sensevoice" : DEFAULT_WHISPER_MODEL,
        asrLanguage: DEFAULT_ASR_LANGUAGE,
        endpoints: ["/v1/audio/speech", "/v1/audio/transcriptions"],
      });
      return;
    }

    if (req.method === "POST" && url.pathname === "/v1/audio/speech") {
      const body = await readJsonBody(req);
      const result = await synthesize({
        input: body.input,
        voice: body.voice,
        responseFormat: body.response_format || body.responseFormat,
      });
      res.writeHead(200, {
        "content-type": result.contentType,
        "x-edge-tts-voice": result.voice,
        "x-audio-format": result.format,
        "content-length": result.body.length,
      });
      res.end(result.body);
      console.log(`speech ${result.format} ${result.body.length} bytes voice=${result.voice}`);
      return;
    }

    if (req.method === "POST" && url.pathname === "/v1/audio/transcriptions") {
      const contentType = req.headers["content-type"] || "";
      const body = await readBodyBuffer(req);
      let request;

      if (String(contentType).includes("multipart/form-data")) {
        const parsed = parseMultipart(body, String(contentType));
        const file = parsed.files.file || Object.values(parsed.files)[0];
        request = {
          audio: file?.data,
          filename: file?.filename,
          contentType: file?.contentType,
          model: parsed.fields.model,
          responseFormat: parsed.fields.response_format,
        };
      } else if (String(contentType).includes("application/json")) {
        const parsed = JSON.parse(body.toString("utf8") || "{}");
        request = {
          audio: parsed.audio_base64 ? Buffer.from(parsed.audio_base64, "base64") : undefined,
          filename: parsed.filename || "audio.wav",
          contentType: parsed.content_type || "audio/wav",
          model: parsed.model,
          responseFormat: parsed.response_format,
        };
      } else {
        request = {
          audio: body,
          filename: req.headers["x-filename"] || "audio.wav",
          contentType: String(contentType || "audio/wav"),
        };
      }

      const result = await transcribe(request);
      console.log(`transcription ${result.text.length} chars engine=${result.engine} model=${result.model}`);

      if (request.responseFormat === "text") {
        const text = Buffer.from(result.text);
        res.writeHead(200, {
          "content-type": "text/plain; charset=utf-8",
          "content-length": text.length,
        });
        res.end(text);
        return;
      }

      sendJson(res, 200, { text: result.text });
      return;
    }

    sendJson(res, 404, { error: "not_found" });
  } catch (error) {
    sendJson(res, error.statusCode || 500, {
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`edge-tts + coli-asr bridge listening on http://${HOST}:${PORT}`);
  console.log(`POST http://${HOST}:${PORT}/v1/audio/speech`);
  console.log(`POST http://${HOST}:${PORT}/v1/audio/transcriptions`);
});
