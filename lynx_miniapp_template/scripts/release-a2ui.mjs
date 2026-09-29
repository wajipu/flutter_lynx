#!/usr/bin/env node
// A2UI 渲染 bundle 一键发布到 OSS：构建 → 哈希 → 上传版本化产物 → 更新 manifest。
//
// 前置（一次性）：
//   1. 本机安装 ossutil（macOS: brew install aliyun-ossutil 或官方二进制）并配好 AK
//   2. export A2UI_OSS_BUCKET=oss://<bucket>/<prefix>/a2ui   （不带尾斜杠）
//
// 常用命令：
//   npm run a2ui:release                                  # 发布 stable
//   A2UI_CHANNEL=gray A2UI_GRAY_PERCENT=10 npm run a2ui:release   # 发布灰度 10%
//   npm run a2ui:promote -- 6                              # 灰度 v6 提升为 stable
//   npm run a2ui:rollback -- 5                             # stable 回滚到 v5（版本化产物保留在 OSS）
//   npm run a2ui:status                                    # 查看远端 manifest
//
// 说明：产物按版本号归档（${bucket}/${version}/a2ui-card.lynx.bundle，永不覆盖），
// manifest.json 只是指针——回滚/提升都只是改指针，秒级生效。
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
const OSSUTIL = process.env.A2UI_OSSUTIL ?? "ossutil";
const CHANNEL = process.env.A2UI_CHANNEL ?? "stable"; // stable | gray
const GRAY_PERCENT = Number.parseInt(process.env.A2UI_GRAY_PERCENT ?? "0", 10);

const distDir = path.resolve("dist-a2ui-card");
const bundlePath = path.join(distDir, "a2ui-card.lynx.bundle");
const remoteManifest = BUCKET ? `${BUCKET}/manifest.json` : "";

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
      // 历史版本的 md5 需显式提供（发布日志/记录里有），防误指错产物。
      const md5 = process.env.A2UI_MD5;
      if (!md5 || md5.length !== 32) {
        fail(
          `回滚需提供发布时的 md5：A2UI_MD5=<32位> npm run a2ui:rollback -- ${version}`,
        );
      }
      entry = {
        version,
        url: `${BUCKET}/${version}/a2ui-card.lynx.bundle`,
        md5,
      };
      console.log(`stable 回滚 → v${version}`);
    }
    pushManifest({ stable: entry });
    console.log(`✓ manifest 已更新：${remoteManifest}`);
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

  // 4. 更新 manifest（保留另一通道）
  const current = fetchRemoteManifest() ?? {};
  const entry = { version, url: remoteBundle, md5 };
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
