#!/usr/bin/env node
// A2UI 渲染 bundle 一键发布到 OSS：构建 → 哈希 → 上传版本化产物 → 更新 manifest。
//
// 前置（一次性）：
//   1. 本机安装 ossutil（macOS: brew install aliyun-ossutil 或官方二进制）并配好 AK
//   2. export A2UI_OSS_BUCKET=oss://<bucket>/<prefix>/a2ui   （ossutil 操作路径，不带尾斜杠）
//   3. export A2UI_PUBLIC_BASE=https://<bucket>.oss-cn-x.aliyuncs.com/<prefix>/a2ui
//      （客户端可见的公网 HTTPS 基址——manifest 里的 url 用它拼接，App 端 dio 可直接下载）
//
// 常用命令：
//   npm run a2ui:release                                  # 发布 stable
//   A2UI_CHANNEL=gray A2UI_GRAY_PERCENT=10 npm run a2ui:release   # 发布灰度 10%
//   npm run a2ui:promote -- 6                              # 灰度 v6 提升为 stable
//   npm run a2ui:rollback -- 5                             # stable 回滚到 v5（版本化产物保留在 OSS）
//   npm run a2ui:status                                    # 查看远端 manifest
//   npm run a2ui:preview -- --kind confirm                 # 预览发布（不影响线上 manifest）
//
// 说明：产物按版本号归档（${bucket}/${version}/a2ui-card.lynx.bundle，永不覆盖），
// manifest.json 只是指针——回滚/提升都只是改指针，秒级生效。
//
// preview 模式是独立的开发/评审通道：产物落在 ${bucket}/preview/${version}/，
// 同时上传 bundle 与 messages 并生成 card-spec.json，供 koklam://card?spec= 扫码直开。
// 它不写 manifest.json、不写 releases/index.json，因此完全不影响线上灰度与回滚。
// 契约见 koklam-docs features/a2ui-card-qr-open/03_contract.md。
import { execSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const BUCKET = process.env.A2UI_OSS_BUCKET;
const PUBLIC_BASE = (process.env.A2UI_PUBLIC_BASE ?? "").replace(/\/$/, "");
const OSSUTIL = process.env.A2UI_OSSUTIL ?? "ossutil";
const CHANNEL = process.env.A2UI_CHANNEL ?? "stable"; // stable | gray
const GRAY_PERCENT = Number.parseInt(process.env.A2UI_GRAY_PERCENT ?? "0", 10);

const distDir = path.resolve("dist-a2ui-card");
const bundlePath = path.join(distDir, "a2ui-card.lynx.bundle");
const remoteManifest = BUCKET ? `${BUCKET}/manifest.json` : "";

// 预览产物：bundle 与 messages 都必须下发——卡片内容在 messages 里，
// 只换 bundle 等于没换卡片（契约见 koklam-docs features/a2ui-card-qr-open/03_contract.md §2）。
const PREVIEW_KINDS = {
  confirm: "../example/assets/a2ui/confirm-card-messages.json",
  display: "../example/assets/a2ui/display-card-messages.json",
};
const messagesPathFor = (kind) => path.resolve(PREVIEW_KINDS[kind]);

function fail(msg) {
  console.error(`✗ ${msg}`);
  process.exit(1);
}

function run(cmd, opts = {}) {
  return execSync(cmd, { stdio: ["ignore", "pipe", "inherit"], ...opts })
    .toString()
    .trim();
}

function requireBucket() {
  if (!BUCKET) fail("缺少 A2UI_OSS_BUCKET（例如 oss://my-bucket/cards/a2ui）");
  if (!PUBLIC_BASE) {
    fail("缺少 A2UI_PUBLIC_BASE（客户端可见的 HTTPS 基址，如 https://bucket.oss-cn-hangzhou.aliyuncs.com/cards/a2ui）");
  }
}

/// 发布记录索引（releases/index.json）：每次 release 追加一条，回滚/管理页查 md5 用。
function fetchReleaseIndex() {
  const tmp = mkdtempSync(path.join(tmpdir(), "a2ui-idx-"));
  try {
    run(`${OSSUTIL} cp ${BUCKET}/releases/index.json ${path.join(tmp, "i.json")} -f`);
    const list = JSON.parse(readFileSync(path.join(tmp, "i.json"), "utf8"));
    return Array.isArray(list) ? list : [];
  } catch {
    return [];
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

function pushReleaseIndex(list) {
  const tmp = path.join(distDir, "releases-index.json");
  writeFileSync(tmp, JSON.stringify(list, null, 2));
  run(`${OSSUTIL} cp ${tmp} ${BUCKET}/releases/index.json -f`);
}

function fetchRemoteManifest() {
  // 拉当前 manifest 到临时文件；不存在（首次发布）返回 null
  const tmp = mkdtempSync(path.join(tmpdir(), "a2ui-manifest-"));
  try {
    run(`${OSSUTIL} cp ${remoteManifest} ${path.join(tmp, "m.json")} -f`);
    return JSON.parse(readFileSync(path.join(tmp, "m.json"), "utf8"));
  } catch {
    return null;
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

function pushManifest(manifest) {
  const tmp = path.join(distDir, "manifest.json");
  writeFileSync(tmp, JSON.stringify(manifest, null, 2));
  run(`${OSSUTIL} cp ${tmp} ${remoteManifest} -f`);
}

function validEntry(entry) {
  return (
    entry &&
    typeof entry.url === "string" &&
    typeof entry.version === "string" &&
    typeof entry.md5 === "string" &&
    entry.md5.length === 32
  );
}

async function main() {
  const mode = process.argv[2] ?? "release";

  if (mode === "status") {
    requireBucket();
    const m = fetchRemoteManifest();
    console.log(m ? JSON.stringify(m, null, 2) : "（远端尚无 manifest）");
    return;
  }

  if (mode === "promote" || mode === "rollback") {
    requireBucket();
    const version = process.argv[3];
    if (!version) fail(`用法: npm run a2ui:${mode} -- <version>`);
    const current = fetchRemoteManifest();
    if (!current) fail("远端无 manifest，无从回滚/提升");

    let entry;
    if (mode === "promote") {
      // 灰度转正：取当前 gray 条目（去掉 percent），stable 指向它、灰度关闭
      if (!validEntry(current.gray)) fail("远端无有效 gray 条目可提升");
      entry = {
        version: current.gray.version,
        url: current.gray.url,
        md5: current.gray.md5,
      };
      console.log(`提升 gray v${entry.version} → stable（灰度关闭）`);
    } else {
      // 回滚：产物按版本归档永不覆盖，stable 重指历史版本即可。
      // md5 优先取发布记录索引，查不到再要求显式提供（防误指错产物）。
      const record = fetchReleaseIndex().find((r) => r.version === version);
      const md5 = process.env.A2UI_MD5 ?? record?.md5;
      if (!md5 || md5.length !== 32) {
        fail(
          `发布记录中无 v${version} 的 md5，请显式提供：A2UI_MD5=<32位> npm run a2ui:rollback -- ${version}`,
        );
      }
      entry = {
        version,
        url: `${PUBLIC_BASE}/${version}/a2ui-card.lynx.bundle`,
        md5,
      };
      console.log(`stable 回滚 → v${version}`);
    }
    pushManifest({ stable: entry });
    console.log(`✓ manifest 已更新：${remoteManifest}`);
    return;
  }

  // ---- preview：开发/评审预览通道，不触碰线上 manifest ----
  if (mode === "preview") {
    requireBucket();
    // --kind confirm|display，决定用哪份 messages 并写进 spec 的 kind 字段
    const kindArgIndex = process.argv.indexOf("--kind");
    const kind = kindArgIndex >= 0 ? process.argv[kindArgIndex + 1] : "confirm";
    if (!PREVIEW_KINDS[kind]) {
      fail(`非法 --kind ${kind}（可选：${Object.keys(PREVIEW_KINDS).join(" | ")}）`);
    }
    const messagesPath = messagesPathFor(kind);
    if (!existsSync(messagesPath)) {
      fail(`messages 源文件缺失：${messagesPath}`);
    }
    const skipBuild = process.argv.includes("--no-build");

    // 1. 构建（--no-build 跳过，便于同一 bundle 反复换 messages 预览）
    if (skipBuild) {
      console.log("▸ 跳过构建（--no-build）");
      if (!existsSync(bundlePath)) fail(`构建产物缺失：${bundlePath}`);
    } else {
      console.log("▸ 构建 bundle…");
      execSync(
        `MINIAPP_A2UI_CARD_OUTPUT_DIR=${distDir} ./node_modules/.bin/rspeedy build --config lynx.a2ui-card.config.ts --no-env`,
        { stdio: "inherit" },
      );
      if (!existsSync(bundlePath)) fail(`构建产物缺失：${bundlePath}`);
    }

    // 2. 两个产物各自哈希（spec 必须声明各自的 md5）
    const bundleBytes = readFileSync(bundlePath);
    const bundleMd5 = createHash("md5").update(bundleBytes).digest("hex");
    const messagesBytes = readFileSync(messagesPath);
    const messagesMd5 = createHash("md5").update(messagesBytes).digest("hex");

    // messages 必须是 JSON 数组——形状错了扫出来是白屏，发布前就拦住
    let messagesJson;
    try {
      messagesJson = JSON.parse(messagesBytes.toString("utf8"));
    } catch (error) {
      fail(`messages 不是合法 JSON：${error.message}`);
    }
    if (!Array.isArray(messagesJson)) {
      fail("messages 顶层必须是数组（a2ui v0.9 协议消息数组）");
    }
    if (bundleBytes.length > 10 * 1024 * 1024) {
      fail(`bundle 超过原生侧 10 MiB 上限：${bundleBytes.length} 字节`);
    }

    const gitSha = run("git rev-parse --short HEAD");
    const version = `preview-${gitSha}-${new Date()
      .toISOString()
      .replace(/[-:TZ]/g, "")
      .slice(0, 12)}`;

    // 3. 上传 bundle + messages 到 preview 命名空间
    const previewDir = `${BUCKET}/preview/${version}`;
    const messagesName = `${kind}-card-messages.json`;
    console.log(
      `▸ 上传预览产物 v${version}（bundle ${bundleBytes.length} 字节 / messages ${messagesJson.length} 条）…`,
    );
    run(`${OSSUTIL} cp ${bundlePath} ${previewDir}/a2ui-card.lynx.bundle -f`);
    run(`${OSSUTIL} cp ${messagesPath} ${previewDir}/${messagesName} -f`);

    // 4. 生成并上传 card-spec.json
    const title = process.env.A2UI_TITLE ?? "";
    const spec = {
      version,
      ...(title ? { title } : {}),
      kind,
      bundle: {
        url: `${PUBLIC_BASE}/preview/${version}/a2ui-card.lynx.bundle`,
        md5: bundleMd5,
      },
      messages: {
        url: `${PUBLIC_BASE}/preview/${version}/${messagesName}`,
        md5: messagesMd5,
      },
    };
    const specTmp = path.join(distDir, "card-spec.json");
    writeFileSync(specTmp, JSON.stringify(spec, null, 2));
    run(`${OSSUTIL} cp ${specTmp} ${previewDir}/card-spec.json -f`);

    const specUrl = `${PUBLIC_BASE}/preview/${version}/card-spec.json`;
    console.log("");
    console.log(`✓ 预览发布完成（kind=${kind}）`);
    console.log(`  版本   v${version}`);
    console.log(`  二维码  koklam://card?spec=${encodeURIComponent(specUrl)}`);
    console.log(`  spec   ${specUrl}`);
    console.log(`  白名单 ${PUBLIC_BASE}/preview/`);
    console.log("");
    console.log("  未写 manifest.json / releases/index.json——线上灰度与回滚不受影响。");
    return;
  }

  // ---- 默认：release ----
  requireBucket();
  if (CHANNEL !== "stable" && CHANNEL !== "gray") fail(`非法通道 ${CHANNEL}`);
  if (CHANNEL === "gray" && !(GRAY_PERCENT >= 1 && GRAY_PERCENT <= 99)) {
    fail("灰度发布需 A2UI_GRAY_PERCENT=1..99");
  }

  // 1. 构建
  console.log("▸ 构建 bundle…");
  execSync(
    `MINIAPP_A2UI_CARD_OUTPUT_DIR=${distDir} ./node_modules/.bin/rspeedy build --config lynx.a2ui-card.config.ts --no-env`,
    { stdio: "inherit" },
  );
  if (!existsSync(bundlePath)) fail(`构建产物缺失：${bundlePath}`);

  // 2. 哈希与版本号（git 短 SHA + 分钟级时间戳，可读且单调）
  const bytes = readFileSync(bundlePath);
  const md5 = createHash("md5").update(bytes).digest("hex");
  const gitSha = run("git rev-parse --short HEAD");
  const version = `${gitSha}-${new Date()
    .toISOString()
    .replace(/[-:TZ]/g, "")
    .slice(0, 12)}`;
  const size = bytes.length;

  // 3. 上传版本化产物（永不覆盖，回滚/提升的数据基础）
  console.log(`▸ 上传产物 v${version}（${size} 字节, md5=${md5}）…`);
  const remoteBundle = `${BUCKET}/${version}/a2ui-card.lynx.bundle`;
  run(`${OSSUTIL} cp ${bundlePath} ${remoteBundle} -f`);
  // 发布记录（管理页/回滚查 md5 的数据源）
  const index = fetchReleaseIndex();
  index.unshift({
    version,
    md5,
    bytes: size,
    channel: CHANNEL,
    percent: CHANNEL === "gray" ? GRAY_PERCENT : 0,
    note: process.env.A2UI_NOTE ?? "",
    date: new Date().toISOString(),
  });
  pushReleaseIndex(index);

  // 4. 更新 manifest（保留另一通道）
  const current = fetchRemoteManifest() ?? {};
  const entry = { version, url: `${PUBLIC_BASE}/${version}/a2ui-card.lynx.bundle`, md5 };
  const next = { ...current };
  if (CHANNEL === "stable") {
    next.stable = entry;
  } else {
    next.gray = { ...entry, percent: GRAY_PERCENT };
  }
  if (next.stable && !validEntry(next.stable)) {
    fail("远端 manifest 的 stable 条目非法，请先 npm run a2ui:status 检查");
  }
  pushManifest(next);

  console.log("");
  console.log(`✓ 发布完成（${CHANNEL}）`);
  console.log(`  版本   v${version}`);
  console.log(`  字节   ${size}`);
  console.log(`  md5    ${md5}`);
  console.log(`  产物   ${remoteBundle}`);
  console.log(`  清单   ${remoteManifest}`);
  if (CHANNEL === "gray") {
    console.log(`  灰度   ${GRAY_PERCENT}% 设备（设备分桶，同设备结果恒定）`);
    console.log(`  观察无异常后全量：npm run a2ui:promote -- ${version}`);
  }
}

main().catch((error) => fail(error.message));
