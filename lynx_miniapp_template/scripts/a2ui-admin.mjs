#!/usr/bin/env node
// 内置卡热更——轻量管理页：读写 OSS 上的 manifest.json 与发布记录，
// 提供发布状态查看 / 灰度调整 / 灰度转正 / 回滚 / 暂停下发。
//
// 用法（二选一存储后端）：
//   真实 OSS：A2UI_OSS_BUCKET=oss://<bucket>/<prefix>/a2ui \
//             A2UI_PUBLIC_BASE=https://<bucket>.oss-cn-x.aliyuncs.com/<prefix>/a2ui \
//             npm run a2ui:admin
//   本地演示：A2UI_OSS_STUB_DIR=/tmp/a2ui-admin-stub npm run a2ui:admin
//
// 启动后浏览器打开 http://127.0.0.1:8788（默认仅绑定本机；
// A2UI_ADMIN_BIND=0.0.0.0 对外暴露时务必配 A2UI_ADMIN_TOKEN）。
import http from "node:http";
import { execSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const STUB = process.env.A2UI_OSS_STUB_DIR; // 本地文件后端（演示/测试）
const BUCKET = process.env.A2UI_OSS_BUCKET;
const PUBLIC_BASE = (process.env.A2UI_PUBLIC_BASE ?? "").replace(/\/$/, "");
const OSSUTIL = process.env.A2UI_OSSUTIL ?? "ossutil";
const PORT = Number(process.env.A2UI_ADMIN_PORT ?? 8788);
const BIND = process.env.A2UI_ADMIN_BIND ?? "127.0.0.1";
const TOKEN = process.env.A2UI_ADMIN_TOKEN ?? "";

function ossRead(rel) {
  if (STUB) {
    const f = path.join(STUB, rel);
    return existsSync(f) ? readFileSync(f, "utf8") : null;
  }
  const tmp = mkdtempSync(path.join(tmpdir(), "a2ui-adm-"));
  try {
    execSync(`${OSSUTIL} cp ${BUCKET}/${rel} ${path.join(tmp, "f")} -f`, {
      stdio: "ignore",
    });
    return readFileSync(path.join(tmp, "f"), "utf8");
  } catch {
    return null;
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

function ossWrite(rel, content) {
  if (STUB) {
    const f = path.join(STUB, rel);
    mkdirSync(path.dirname(f), { recursive: true });
    writeFileSync(f, content);
    return;
  }
  const tmp = mkdtempSync(path.join(tmpdir(), "a2ui-adm-"));
  const tmpFile = path.join(tmp, "f");
  try {
    writeFileSync(tmpFile, content);
    execSync(`${OSSUTIL} cp ${tmpFile} ${BUCKET}/${rel} -f`, {
      stdio: "ignore",
    });
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

function loadState() {
  let manifest = null;
  try {
    manifest = JSON.parse(ossRead("manifest.json") ?? "null");
  } catch {
    manifest = null;
  }
  let releases = [];
  try {
    const list = JSON.parse(ossRead("releases/index.json") ?? "[]");
    if (Array.isArray(list)) releases = list;
  } catch {}
  return { manifest, releases, paused: manifest?.paused === true };
}

const validEntry = (e) =>
  e &&
  typeof e.url === "string" &&
  e.url.startsWith("http") &&
  typeof e.version === "string" &&
  e.version.length > 0 &&
  typeof e.md5 === "string" &&
  e.md5.length === 32;

function serveApi(req, res) {
  const send = (code, body) => {
    res.writeHead(code, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify(body));
  };
  if (TOKEN && (req.headers["x-admin-token"] ?? "") !== TOKEN) {
    return send(401, { error: "token 校验失败" });
  }
  if (req.method === "GET" && req.url === "/api/state") {
    return send(200, {
      ...loadState(),
      backend: STUB ? `stub:${STUB}` : BUCKET,
      publicBase: PUBLIC_BASE,
    });
  }
  if (req.method === "POST" && req.url === "/api/manifest") {
    let raw = "";
    req.on("data", (c) => (raw += c));
    req.on("end", () => {
      try {
        const { manifest } = JSON.parse(raw);
        if (manifest?.paused === true) {
          // 暂停下发：客户端 manifest 校验失败 → 全量回退内置（kill switch）
          ossWrite("manifest.json", JSON.stringify({ paused: true }, null, 2));
          return send(200, { ok: true, paused: true });
        }
        if (!validEntry(manifest?.stable)) {
          return send(400, {
            error: "stable 条目非法（需 http url/version/32位md5）",
          });
        }
        if (manifest.gray && !validEntry(manifest.gray)) {
          return send(400, { error: "gray 条目非法" });
        }
        ossWrite("manifest.json", JSON.stringify(manifest, null, 2));
        send(200, { ok: true });
      } catch (error) {
        send(400, { error: String(error.message ?? error) });
      }
    });
    return;
  }
  send(404, { error: "not found" });
}

const PAGE = `<!doctype html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>内置卡热更管理</title>
<style>
  :root { color-scheme: light; }
  body { font-family: system-ui, -apple-system, sans-serif; margin: 0; background: #f7f8fa; color: #171d1f; }
  .wrap { max-width: 760px; margin: 0 auto; padding: 24px 16px 48px; }
  h1 { font-size: 20px; } .sub { color: #747a76; font-size: 12px; margin-bottom: 16px; }
  .card { background: #fff; border-radius: 12px; padding: 16px; margin-bottom: 12px;
          box-shadow: 0 1px 4px rgba(23,29,31,.06); }
  .row { display: flex; gap: 12px; flex-wrap: wrap; }
  .kv { font-size: 13px; line-height: 1.7; }
  .tag { display: inline-block; padding: 1px 8px; border-radius: 999px; font-size: 11px; margin-right: 6px; }
  .tag.stable { background: #126652; color: #fff; }
  .tag.gray { background: #f2b66d; color: #171d1f; }
  .tag.off { background: #f4f4f5; color: #747a76; }
  button { border: 1px solid #d9dcd9; background: #fff; border-radius: 8px; padding: 6px 12px;
           font-size: 13px; cursor: pointer; }
  button.primary { background: #126652; border-color: #126652; color: #fff; }
  button.danger { color: #d92d20; border-color: #f0b4b0; }
  button:disabled { opacity: .45; cursor: not-allowed; }
  input[type=number] { width: 72px; padding: 5px 6px; border: 1px solid #d9dcd9; border-radius: 6px; }
  table { width: 100%; border-collapse: collapse; font-size: 12.5px; }
  th, td { text-align: left; padding: 7px 8px; border-bottom: 1px solid #edeeea; }
  th { color: #747a76; font-weight: 600; }
  #toast { position: fixed; left: 50%; bottom: 24px; transform: translateX(-50%);
           background: #171d1f; color: #fff; padding: 8px 16px; border-radius: 8px;
           font-size: 13px; opacity: 0; transition: opacity .25s; pointer-events: none; }
  #toast.on { opacity: .95; }
  .paused { background: #fff7ed; border: 1px solid #f2b66d; padding: 10px 12px;
            border-radius: 8px; font-size: 13px; margin-bottom: 12px; }
</style>
</head>
<body>
<div class="wrap">
  <h1>内置卡热更管理</h1>
  <div class="sub" id="backend"></div>
  <div id="pausedBox" class="paused" style="display:none">
    ⚠ 下发已暂停——所有客户端将回退 App 内置版本。
  </div>
  <div class="card" id="stableCard"></div>
  <div class="card" id="grayCard"></div>
  <div class="card">
    <div class="kv"><b>操作</b></div>
    <div class="row" style="margin-top:10px; align-items:center">
      <span style="font-size:13px">灰度比例</span>
      <input type="number" id="percent" min="0" max="100"> <span style="font-size:12px;color:#747a76">%</span>
      <button onclick="savePercent()">保存灰度</button>
      <button onclick="promote()">灰度转正</button>
      <button class="danger" onclick="pause()">暂停下发</button>
      <button onclick="location.reload()">刷新</button>
    </div>
  </div>
  <div class="card">
    <div class="kv"><b>发布记录</b>（点「设为 stable」即回滚到该版本）</div>
    <div style="margin-top:8px; overflow-x:auto"><table id="releases"></table></div>
  </div>
</div>
<div id="toast"></div>
<script>
let state = null;
const $ = (id) => document.getElementById(id);
function toast(msg) {
  const t = $("toast"); t.textContent = msg; t.classList.add("on");
  setTimeout(() => t.classList.remove("on"), 2200);
}
function fmtEntry(e, cls, label) {
  if (!e) return '<span class="tag off">' + label + '</span> <span class="kv">未配置</span>';
  return '<span class="tag ' + cls + '">' + label + '</span>' +
    '<span class="kv">v' + e.version + ' · ' + (e.md5 || "").slice(0, 8) +
    (e.percent != null ? ' · 灰度 ' + e.percent + '%' : '') + '</span>';
}
async function load() {
  state = await (await fetch("/api/state")).json();
  $("backend").textContent = "存储：" + state.backend + (state.publicBase ? " · 公网：" + state.publicBase : "");
  $("pausedBox").style.display = state.paused ? "" : "none";
  const m = state.manifest ?? {};
  $("stableCard").innerHTML = "<div class='kv'>" + fmtEntry(m.stable, "stable", "stable") + "</div>";
  $("grayCard").innerHTML = "<div class='kv'>" + fmtEntry(m.gray, "gray", "gray") +
    (m.gray ? " · 桶号<percent 的设备吃此版本" : "") + "</div>";
  $("percent").value = m.gray?.percent ?? 0;
  const rows = (state.releases ?? []).map((r) =>
    "<tr><td>" + r.version + "</td><td>" + r.channel + "</td><td>" +
    (r.note || "") + "</td><td>" + (r.date || "").slice(0, 16).replace("T", " ") +
    "</td><td>" + (r.bytes / 1024 | 0) + "KB</td>" +
    '<td><button onclick="rollback(\\'' + r.version + '\\',\\'' + r.md5 + '\\')">设为 stable</button></td></tr>');
  $("releases").innerHTML = "<tr><th>版本</th><th>通道</th><th>备注</th><th>时间</th><th>大小</th><th></th></tr>" + rows.join("");
}
async function post(manifest) {
  const res = await fetch("/api/manifest", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ manifest }),
  });
  const body = await res.json();
  if (!res.ok) { toast("✗ " + body.error); return false; }
  toast("✓ 已生效（客户端下次启动应用）");
  await load();
  return true;
}
function cur() { return state.manifest ? JSON.parse(JSON.stringify(state.manifest)) : {}; }
async function savePercent() {
  const m = cur();
  if (!m.gray) { toast("当前无 gray 版本，先 npm run a2ui:release 灰度发布"); return; }
  m.gray.percent = Math.max(0, Math.min(100, Number($("percent").value) | 0));
  await post(m);
}
async function promote() {
  const m = cur();
  if (!m.gray) { toast("无 gray 可转正"); return; }
  m.stable = { version: m.gray.version, url: m.gray.url, md5: m.gray.md5 };
  m.gray.percent = 0;
  await post(m);
}
async function pause() {
  if (!confirm("暂停后所有客户端回退 App 内置版本，确认？")) return;
  await post({ paused: true });
}
async function rollback(version, md5) {
  if (!confirm("stable 回滚到 v" + version + "？")) return;
  const m = cur();
  m.paused = undefined;
  m.stable = {
    version,
    url: state.publicBase + "/" + version + "/a2ui-card.lynx.bundle",
    md5,
  };
  await post(m);
}
load();
</script>
</body>
</html>`;

const server = http.createServer((req, res) => {
  if (req.url === "/" || req.url.startsWith("/?")) {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(PAGE);
    return;
  }
  if (req.url?.startsWith("/api/")) {
    if (!STUB && !BUCKET) {
      res.writeHead(500, { "Content-Type": "application/json; charset=utf-8" });
      res.end(
        JSON.stringify({
          error: "未配置存储（A2UI_OSS_BUCKET 或 A2UI_OSS_STUB_DIR）",
        }),
      );
      return;
    }
    serveApi(req, res);
    return;
  }
  res.writeHead(404);
  res.end();
});

server.listen(PORT, BIND, () => {
  console.log(`✓ 内置卡热更管理页: http://${BIND}:${PORT}`);
  console.log(`  存储: ${STUB ? `本地演示 ${STUB}` : BUCKET}`);
  if (BIND !== "127.0.0.1" && !TOKEN) {
    console.warn(
      "⚠ 对外暴露但未设置 A2UI_ADMIN_TOKEN，任何能访问者都可改 manifest！",
    );
  }
});
