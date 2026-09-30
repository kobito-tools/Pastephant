// demo.html をコマ撮りして PNG を並べる。使い方: node capture.mjs <出力フォルダ> [コマ/秒（既定 15）] [時刻…（指定するとその時刻だけ撮る）]
// Google Chrome を DevTools のプロトコルで動かす（追加のパッケージは要らない。Node 22 以降の WebSocket を使う）。
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const [out, fpsArg, ...times] = process.argv.slice(2);
const fps = Number(fpsArg || 15);
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const profile = mkdtempSync(join(tmpdir(), "pastephant-demo-"));
const port = 9333;
const proc = spawn(chrome, ["--headless=new", "--disable-gpu", "--hide-scrollbars", `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, "--allow-file-access-from-files", "about:blank"], { stdio: "ignore" });

try {
  let target;
  for (let i = 0; i < 50 && !target; i++) {
    await new Promise(r => setTimeout(r, 200));
    target = await fetch(`http://127.0.0.1:${port}/json/list`).then(r => r.json()).then(l => l.find(x => x.type === "page")).catch(() => null);
  }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener("open", r, { once: true }));
  let next = 0; const waiting = new Map();
  ws.addEventListener("message", e => { const m = JSON.parse(e.data); waiting.get(m.id)?.(m); waiting.delete(m.id); });
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++next; waiting.set(id, m => m.error ? reject(new Error(JSON.stringify(m.error))) : resolve(m.result));
    ws.send(JSON.stringify({ id, method, params }));
  });
  const evaluate = async expression => (await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true })).result.value;

  await send("Emulation.setDeviceMetricsOverride", { width: 960, height: 600, deviceScaleFactor: 2, mobile: false });
  const page = pathToFileURL(join(dirname(fileURLToPath(import.meta.url)), "demo.html")).href;
  await send("Page.navigate", { url: page });
  for (let i = 0; i < 50 && await evaluate("document.readyState").catch(() => "") !== "complete"; i++) await new Promise(r => setTimeout(r, 100));
  await evaluate("document.fonts.ready.then(() => true)");
  const duration = await evaluate("window.DURATION");

  const list = times.length ? times.map(Number) : Array.from({ length: Math.round(duration * fps) }, (_, i) => i / fps);
  for (const [i, t] of list.entries()) {
    await evaluate(`render(${t})`);
    const { data } = await send("Page.captureScreenshot", { format: "png" });
    writeFileSync(join(out, `frame${String(i).padStart(4, "0")}.png`), Buffer.from(data, "base64"));
  }
  console.log(`${list.length} コマ`);
  ws.close();
} finally {
  proc.kill();
  setTimeout(() => rmSync(profile, { recursive: true, force: true }), 500);
}
