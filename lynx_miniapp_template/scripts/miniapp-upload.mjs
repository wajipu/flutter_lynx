import { spawn } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { lookup } from "node:dns/promises";
import { mkdtemp, readFile, realpath, rm, stat } from "node:fs/promises";
import { request } from "node:https";
import { createRequire } from "node:module";
import { isIP } from "node:net";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const configKeys = ["appCode", "platform", "bundlePath", "lynxSdkVersion", "bridgeApiVersion", "minHostVersion", "translations"];
const maxBundleBytes = 10 * 1024 * 1024;
const maxInt = 2147483647;
let requestStarted = false;
let session;

function check(condition, message) {
  if (!condition) throw new Error(message);
}

function fixedObject(value, keys, label) {
  check(value !== null && typeof value === "object" && !Array.isArray(value), `${label} 必须是 JSON 对象`);
  check(Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key)), `${label} 字段必须严格为：${keys.join(", ")}`);
}

function textField(value, label, maxLength) {
  check(typeof value === "string" && value.length > 0 && value === value.trim() && value.length <= maxLength, `${label} 必须填写有效文本（最多 ${maxLength} 字符）`);
}

function versionField(value, label, withBuild = false) {
  textField(value, label, withBuild ? 64 : 32);
  const pattern = withBuild ? /^\d+\.\d+\.\d+\+\d+$/ : /^\d+\.\d+\.\d+$/;
  check(typeof value === "string" && pattern.test(value) && value.split(/[.+]/).every((part) => Number(part) <= maxInt), `${label} 必须为 ${withBuild ? "x.y.z+build" : "x.y.z"}，整数组件不得超过 ${maxInt}`);
}

async function loadConfig() {
  let config;
  let pkg;
  try {
    config = JSON.parse(await readFile(path.join(projectRoot, "miniapp.config.json"), "utf8"));
    pkg = JSON.parse(await readFile(path.join(projectRoot, "package.json"), "utf8"));
  } catch {
    throw new Error("请先填写有效的 miniapp.config.json，并确保 package.json 是有效 JSON；不会使用示例配置或旧产物");
  }
  fixedObject(config, configKeys, "miniapp.config.json");
  textField(config.appCode, "appCode", 64);
  check(/^[A-Za-z0-9_-]+$/.test(config.appCode), "appCode 必须复制已有应用编码，不得包含空格或路径字符");
  check(config.platform === 1 || config.platform === 2, "platform 必须为 1（Android）或 2（iOS）");
  textField(config.bundlePath, "bundlePath", 255);
  check(!path.isAbsolute(config.bundlePath) && !config.bundlePath.includes("\\") && !config.bundlePath.includes(":") && config.bundlePath.split("/").every((part) => part && part !== "." && part !== "..") && config.bundlePath.endsWith(".lynx.bundle"), "bundlePath 必须是本次构建输出目录内的相对 .lynx.bundle 路径，不能指向现有 dist 或上级目录");
  textField(config.lynxSdkVersion, "lynxSdkVersion", 32);
  versionField(config.lynxSdkVersion, "lynxSdkVersion");
  check(Number.isInteger(config.bridgeApiVersion) && config.bridgeApiVersion > 0 && config.bridgeApiVersion <= maxInt, "bridgeApiVersion 必须是已实现的正整数能力版本");
  versionField(config.minHostVersion, "minHostVersion", true);
  versionField(pkg.version, "package.json.version");
  check(Array.isArray(config.translations) && config.translations.length > 0, "translations 至少填写一种语言的版本说明");
  const locales = new Set();
  for (const translation of config.translations) {
    fixedObject(translation, ["locale", "changelog"], "translations 项");
    textField(translation.locale, "locale", 20);
    textField(translation.changelog, "changelog", 4000);
    const locale = translation.locale.replaceAll("-", "_").toLowerCase();
    check(!locales.has(locale), "translations 不得重复语言；有效语言及完整性由后端校验");
    locales.add(locale);
  }
  return { config, versionName: pkg.version };
}

async function loadSession() {
  const args = process.argv.slice(2);
  check(args.length === 0 || (args.length === 1 && args[0] === "--session-stdin"), "仅支持 npm run miniapp:upload [-- --session-stdin]，不接受凭据命令行参数");
  let value;
  if (args[0] === "--session-stdin") {
    check(!process.stdin.isTTY, "--session-stdin 仅接受安全管道输入，不在终端回显会话信息");
    process.stdin.setEncoding("utf8");
    let input = "";
    for await (const chunk of process.stdin) {
      input += chunk.toString();
      check(Buffer.byteLength(input) <= 64 * 1024, "会话输入过大");
    }
    try {
      value = JSON.parse(input);
    } catch {
      throw new Error("会话标准输入必须是有效 JSON");
    }
    fixedObject(value, ["apiBaseUrl", "accessToken", "clientId"], "会话输入");
  } else {
    value = {
      apiBaseUrl: process.env.MINIAPP_API_BASE_URL,
      accessToken: process.env.MINIAPP_ACCESS_TOKEN,
      clientId: process.env.MINIAPP_CLIENT_ID,
    };
  }
  textField(value.apiBaseUrl, "API base URL", 2048);
  textField(value.accessToken, "现有登录 accessToken", 16384);
  textField(value.clientId, "现有登录 Clientid", 128);
  check(/^[\x21-\x7e]+$/.test(value.accessToken) && !/^Bearer$/i.test(value.accessToken), "accessToken 只填原始 Token，不含 Bearer 前缀或空白");
  check(/^[\x21-\x7e]+$/.test(value.clientId), "Clientid 不得包含空白或控制字符");
  return value;
}

function publicAddress(address) {
  if (isIP(address) === 4) {
    const [a, b, c] = address.split(".").map(Number);
    return !(a === 0 || a === 10 || a === 127 || a >= 224 || (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && (b === 168 || (b === 0 && (c === 0 || c === 2)))) || (a === 198 && (b === 18 || b === 19 || (b === 51 && c === 100))) || (a === 203 && b === 0 && c === 113));
  }
  // Only globally routed IPv6 unicast; exclude documentation/tunnelling ranges.
  return isIP(address) === 6 && /^[23][0-9a-f]{3}:/i.test(address) && !/^2001:(?:0*:|0*db8:)/i.test(address) && !/^2002:/i.test(address);
}

function uploadUrl(baseUrl) {
  let url;
  try {
    url = new URL(baseUrl);
  } catch {
    throw new Error("API base URL 无效；必须显式配置远端 HTTPS 地址");
  }
  check(url.protocol === "https:" && !url.username && !url.password && !url.search && !url.hash, "API base URL 仅允许不含凭据、查询参数或 fragment 的 HTTPS 地址");
  const hostname = url.hostname.replace(/^\[|\]$/g, "");
  check(!/(^|\.)(localhost|local|lan|internal|home)$/i.test(hostname) && (isIP(hostname) ? publicAddress(hostname) : hostname.includes(".")), "拒绝本机、监听地址或局域网 API 地址");
  url.pathname = `${url.pathname.replace(/\/+$/, "")}/system/mini-app-version/upload`;
  return url;
}

async function buildBundle(config) {
  const require = createRequire(import.meta.url);
  let rspeedy;
  try {
    const manifestPath = require.resolve("@lynx-js/rspeedy/package.json");
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    rspeedy = path.resolve(path.dirname(manifestPath), manifest.bin.rspeedy);
  } catch {
    throw new Error("未安装本工程的 Rspeedy；请先安装已确认的构建依赖，不会使用JSON演示产物");
  }
  const tempRoot = await mkdtemp(path.join(tmpdir(), "miniapp-upload-"));
  try {
    const outputRoot = path.join(tempRoot, "dist");
    const env = { ...process.env, MINIAPP_BUILD_OUTPUT_DIR: outputRoot };
    // Never expose this upload's session to the compiler or bundle environment.
    delete env.MINIAPP_ACCESS_TOKEN;
    delete env.MINIAPP_CLIENT_ID;
    delete env.MINIAPP_API_BASE_URL;
    console.log("正在执行真实 Rspeedy 构建（独立临时输出，不使用旧 dist）...");
    await new Promise((resolve, reject) => {
      const child = spawn(process.execPath, [rspeedy, "build", "--config", "lynx.upload.config.ts", "--no-env"], { cwd: projectRoot, env, stdio: ["ignore", "inherit", "inherit"] });
      child.once("error", () => reject(new Error("无法启动本工程 Rspeedy；未发起上传")));
      child.once("exit", (code) => code === 0 ? resolve() : reject(new Error("真实构建失败；未发起上传，不使用旧文件或演示包")));
    });
    let bundlePath;
    try {
      bundlePath = await realpath(path.join(outputRoot, config.bundlePath));
      const root = await realpath(outputRoot);
      check(bundlePath.startsWith(`${root}${path.sep}`), "构建产物不得通过符号链接越过本次输出目录");
      const info = await stat(bundlePath);
      check(info.isFile() && info.size > 8 && info.size <= maxBundleBytes, "bundle 必须是非空文件且不超过 10 MiB");
    } catch (error) {
      if (error.code === "ENOENT") throw new Error("真实构建未生成配置指定的本次 bundle；未发起上传");
      throw error;
    }
    const bundle = await readFile(bundlePath);
    check(bundle.length > 8 && bundle.length <= maxBundleBytes, "bundle 大小不符合上传限制");
    // Binary magic is only a structural precheck, not executable/signed validation.
    check(bundle.readUInt32LE(0) === bundle.length && [0x00241922, 0xdd737199].includes(bundle.readUInt32LE(4)), "拒绝 JSON、源码或非 Lynx 二进制包；不能用历史演示产物上传");
    return bundle;
  } finally {
    // Only this invocation's mkdtemp directory is removed; never clean project dist.
    await rm(tempRoot, { recursive: true, force: true });
  }
}

async function upload(url, bundle, metadata) {
  const hostname = url.hostname.replace(/^\[|\]$/g, "");
  const addresses = isIP(hostname) ? [{ address: hostname, family: isIP(hostname) }] : await lookup(hostname, { all: true });
  check(addresses.length > 0 && addresses.every(({ address }) => publicAddress(address)), "API 域名解析到本机、保留或局域网地址，拒绝发送会话凭据");
  const boundary = `miniapp-${randomUUID()}`;
  const body = Buffer.concat([
    Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="metadata"\r\nContent-Type: application/json\r\n\r\n${JSON.stringify(metadata)}\r\n--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="main.lynx.bundle"\r\nContent-Type: application/octet-stream\r\n\r\n`),
    bundle,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ]);
  return new Promise((resolve, reject) => {
    requestStarted = true;
    // Pin the checked DNS result; HTTPS does not follow redirects or retry.
    const req = request(url, {
      method: "POST", agent: false, autoSelectFamily: false,
      lookup: (_hostname, _options, callback) => callback(null, addresses[0].address, addresses[0].family),
      signal: AbortSignal.timeout(60000),
      headers: {
        Authorization: `Bearer ${session.accessToken}`,
        Clientid: session.clientId,
        "Content-Type": `multipart/form-data; boundary=${boundary}`,
        "Content-Length": body.length,
        Accept: "application/json",
      },
    }, (res) => {
      const chunks = [];
      let size = 0;
      res.on("data", (chunk) => {
        size += chunk.length;
        if (size > 1024 * 1024) req.destroy(new Error("响应过大"));
        else chunks.push(chunk);
      });
      res.on("error", reject);
      res.on("end", () => {
        try {
          check(res.statusCode >= 200 && res.statusCode < 300, `上传接口返回 HTTP ${res.statusCode}；不会跟随重定向或自动重试`);
          const response = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          check(response.code === 200, "后端未确认草稿创建成功，请检查现有账号会话、上传权限或版本参数");
          const result = response.data;
          fixedObject(result, ["appCode", "versionId", "versionName", "status", "validationStatus", "validationMessage"], "上传结果");
          check(result.appCode === metadata.appCode && result.versionName === metadata.versionName && typeof result.versionId === "string" && /^[1-9]\d*$/.test(result.versionId) && result.status === 0 && [0, 1, 2].includes(result.validationStatus) && (result.validationMessage === null || typeof result.validationMessage === "string"), "上传响应不符合草稿契约，请在 Web 版本列表确认结果");
          resolve(result);
        } catch {
          reject(new Error("未收到有效的草稿入库结果，请在 Web 版本列表确认；不会自动重试"));
        }
      });
    });
    req.on("error", () => reject(new Error("上传中断或超时，结果待确认；先检查 Web 版本列表，不要盲目重新上传")));
    req.end(body);
  });
}

try {
  const { config, versionName } = await loadConfig();
  session = await loadSession();
  const url = uploadUrl(session.apiBaseUrl);
  const bundle = await buildBundle(config);
  const { bundlePath: _bundlePath, ...metadata } = config;
  const result = await upload(url, bundle, { ...metadata, versionName, bundleSha256: createHash("sha256").update(bundle).digest("hex") });
  console.log("草稿已入库；未执行正式发布，也不代表 App 可运行。");
  console.log(JSON.stringify(result, null, 2).replaceAll(session.accessToken, "[REDACTED]"));
} catch (error) {
  const message = error.message || "上传命令失败";
  console.error(session ? message.replaceAll(session.accessToken, "[REDACTED]") : message);
  if (requestStarted) console.error("上传结果以 Web 版本列表为准；本命令不会自动重试或发布。");
  process.exitCode = 1;
}
