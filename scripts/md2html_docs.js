// md2html_docs.js — Convert the 4 Arabic spec docs (Markdown) to RTL print-ready HTML (A4)
"use strict";
const fs = require("fs");
const path = require("path");

const SRC = "/home/z/my-project/download/heseb-docs";
const OUT = path.join(SRC, "html");
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

const DOCS = [
  "01-vision-and-scope.md",
  "05-data-model.md",
  "07-tryton-principles.md",
  "09-release-plan.md",
];

// ---------- helpers ----------
function esc(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
// inline: code spans first (dir=ltr), then **bold**
function inline(s) {
  const parts = String(s).split(/`([^`]+)`/);
  let out = "";
  for (let i = 0; i < parts.length; i++) {
    if (i % 2 === 1) out += `<code dir="ltr">${esc(parts[i])}</code>`;
    else out += esc(parts[i]).replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  }
  return out;
}

// ---------- block parser ----------
function parseBlocks(md) {
  const lines = md.split(/\r?\n/);
  const blocks = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (/^\s*$/.test(line)) { i++; continue; }
    if (/^---+\s*$/.test(line)) { blocks.push({ type: "hr" }); i++; continue; }
    let m = line.match(/^(#{1,3})\s+(.*)$/);
    if (m) { blocks.push({ type: "h" + m[1].length, text: m[2].trim() }); i++; continue; }
    if (/^\s*\|.*\|\s*$/.test(line)) {
      const rows = [];
      while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) {
        const raw = lines[i].trim().replace(/^\|/, "").replace(/\|$/, "");
        rows.push(raw.split("|").map((c) => c.trim()));
        i++;
      }
      // drop separator row(s) like ---
      const body = rows.filter((r) => !r.every((c) => /^:?-{2,}:?$/.test(c)));
      blocks.push({ type: "table", rows: body });
      continue;
    }
    if (/^\s*[-*]\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\s*[-*]\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*[-*]\s+/, "").trim());
        i++;
      }
      blocks.push({ type: "ul", items });
      continue;
    }
    if (/^\s*\d+[.)]\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\s*\d+[.)]\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*\d+[.)]\s+/, "").trim());
        i++;
      }
      blocks.push({ type: "ol", items });
      continue;
    }
    if (/^>\s?/.test(line)) {
      const items = [];
      while (i < lines.length && /^>\s?/.test(lines[i])) {
        items.push(lines[i].replace(/^>\s?/, "").trim());
        i++;
      }
      blocks.push({ type: "quote", text: items.filter(Boolean).join(" ") });
      continue;
    }
    // paragraph: gather until blank/structural
    const buf = [line.trim()];
    i++;
    while (
      i < lines.length &&
      !/^\s*$/.test(lines[i]) &&
      !/^(#{1,3})\s/.test(lines[i]) &&
      !/^\s*\|.*\|\s*$/.test(lines[i]) &&
      !/^\s*[-*]\s+/.test(lines[i]) &&
      !/^\s*\d+[.)]\s+/.test(lines[i]) &&
      !/^>\s?/.test(lines[i]) &&
      !/^---+\s*$/.test(lines[i])
    ) {
      buf.push(lines[i].trim());
      i++;
    }
    blocks.push({ type: "p", text: buf.join(" ") });
  }
  return blocks;
}

// ---------- cover meta extraction ----------
function extractDocMeta(blocks, fileName) {
  const h1 = blocks.find((b) => b.type === "h1");
  const fullTitle = h1 ? h1.text : fileName;
  const m = fullTitle.match(/^(\d+)\s*[—-]\s*(.*)$/);
  const num = m ? m[1] : "??";
  const title = m ? m[2] : fullTitle;
  const meta = {};
  const t = blocks.find((b) => b.type === "table");
  if (t) {
    for (let r = 1; r < t.rows.length; r++) {
      const k = t.rows[r][0].replace(/\*\*/g, "").trim();
      const v = t.rows[r][1].replace(/\*\*/g, "").trim();
      meta[k] = v;
    }
  }
  return { num, title, meta };
}

// ---------- HTML assembly ----------
const CSS = `
@page { size: 794px 1123px; margin: 0; }
:root{
  --c-text:#1a2332; --c-muted:#5b6b7c; --c-accent:#14625a; --c-accent-dark:#0d4740;
  --c-accent-light:#eaf2f0; --c-border:#d7e0dd; --c-bg:#ffffff; --c-code-bg:#f2f5f4;
  --f-head:'Cairo','DejaVu Sans',sans-serif;
  --f-body:'Noto Naskh Arabic','Cairo','DejaVu Sans',sans-serif;
}
html,body{margin:0;padding:0;width:794px;background:var(--c-bg);color:var(--c-text);
  font-family:var(--f-body),'Noto Naskh Arabic','Cairo','DejaVu Sans',sans-serif;font-size:15px;line-height:1.95;direction:rtl;}
@media screen{
  html{height:auto;display:flex;justify-content:center;background:#e8ecea;}
  body{margin:16px auto;box-shadow:0 2px 24px rgba(20,40,40,.18);}
}
/* ---------- cover ---------- */
.cover{width:794px;height:1123px;box-sizing:border-box;break-after:page;overflow:hidden;
  position:relative;display:flex;flex-direction:column;justify-content:center;
  padding:64px;background:#ffffff;}
.cover .deco1{position:absolute;top:70px;left:64px;width:120px;height:120px;border-radius:50%;
  background:var(--c-accent);opacity:.10;}
.cover .deco2{position:absolute;top:130px;left:130px;width:56px;height:56px;border-radius:50%;
  background:var(--c-accent);opacity:.16;}
.cover .deco3{position:absolute;bottom:150px;right:64px;width:180px;height:10px;border-radius:6px;
  background:var(--c-accent);opacity:.12;}
.badge{display:inline-block;font-family:var(--f-head),'Cairo','DejaVu Sans',sans-serif;font-weight:700;font-size:14px;
  color:#ffffff;background:var(--c-accent);padding:7px 20px;border-radius:999px;letter-spacing:.4px;}
.cover-kicker{font-family:var(--f-head),'Cairo','DejaVu Sans',sans-serif;font-size:16px;font-weight:600;color:var(--c-muted);
  margin-top:44px;letter-spacing:.3px;}
.cover-title{font-family:var(--f-head),'Cairo','DejaVu Sans',sans-serif;font-weight:800;font-size:44px;line-height:1.45;
  color:var(--c-accent-dark);margin:10px 0 0;}
.cover-rule{width:96px;height:5px;background:var(--c-accent);border-radius:3px;margin:44px 0 48px;}
.cover-meta{display:flex;flex-wrap:wrap;gap:10px;}
.chip{font-family:var(--f-head),'Cairo','DejaVu Sans',sans-serif;font-size:13px;font-weight:600;color:var(--c-accent-dark);
  background:var(--c-accent-light);border:1px solid var(--c-border);border-radius:8px;padding:6px 14px;}
.cover-related{margin-top:18px;font-size:13px;color:var(--c-muted);max-width:520px;}
.cover-bottom{position:absolute;bottom:64px;right:64px;left:64px;display:flex;
  justify-content:space-between;align-items:center;
  font-family:var(--f-head),'Cairo','DejaVu Sans',sans-serif;font-size:12.5px;color:var(--c-muted);}
/* ---------- content ---------- */
.main-content{padding:54px 58px 46px 58px;}
h2{font-family:var(--f-head),'Cairo','DejaVu Sans',sans-serif;font-size:21.5px;font-weight:800;color:var(--c-accent-dark);
  border-right:4px solid var(--c-accent);padding-right:12px;margin:26px 0 10px;
  break-after:avoid;break-inside:avoid;line-height:1.6;}
h3{font-family:var(--f-head),'Cairo','DejaVu Sans',sans-serif;font-size:17px;font-weight:700;color:var(--c-accent-dark);
  margin:18px 0 8px;break-after:avoid;break-inside:avoid;line-height:1.6;}
p{margin:0 0 9px;text-align:justify;}
strong{font-weight:700;color:var(--c-accent-dark);}
code{font-family:'DejaVu Sans Mono','Liberation Mono',monospace;font-size:12.5px;direction:ltr;
  unicode-bidi:embed;background:var(--c-code-bg);border:1px solid var(--c-border);
  border-radius:4px;padding:1px 5px;color:#0d3b36;}
ul,ol{margin:4px 0 12px;padding-right:26px;}
li{margin-bottom:5px;text-align:start;break-inside:avoid;}
blockquote{background:#f4f8f7;border-right:4px solid var(--c-accent);border-radius:6px 0 0 6px;
  padding:10px 16px;margin:12px 0;break-inside:avoid;text-align:start;}
blockquote p{margin:0;}
table{width:100%;border-collapse:collapse;margin:12px 0 16px;font-size:13.2px;line-height:1.75;}
tr{break-inside:avoid;}
th,td{border:1px solid var(--c-border);padding:6px 10px;text-align:start;vertical-align:top;}
thead th,th{background:var(--c-accent-light);font-family:var(--f-head),'Cairo','DejaVu Sans',sans-serif;font-weight:700;
  color:var(--c-accent-dark);font-size:13px;}
hr{border:none;border-top:1px solid var(--c-border);margin:16px 0;}
`;

function buildHtml(fileName) {
  const md = fs.readFileSync(path.join(SRC, fileName), "utf8");
  const blocks = parseBlocks(md);
  const { num, title, meta } = extractDocMeta(blocks, fileName);

  // cover chips
  const chips = [];
  if (meta["الإصدار"]) chips.push(`الإصدار ${meta["الإصدار"].replace(/\(.*?\)/g, "").trim()}`);
  if (meta["التاريخ"]) chips.push(`التاريخ ${meta["التاريخ"]}`);
  if (meta["الحالة"]) chips.push(`الحالة ${meta["الحالة"].replace(/\(.*?\)/g, "").trim()}`);
  const related = meta["الوثائق المرتبطة"] || "";

  let content = "";
  let firstH1 = true;
  for (const b of blocks) {
    if (b.type === "h1") {
      if (firstH1) { firstH1 = false; continue; } // title already on cover
      content += `<h2>${inline(b.text)}</h2>`;
    } else if (b.type === "h2") content += `<h2>${inline(b.text)}</h2>`;
    else if (b.type === "h3") content += `<h3>${inline(b.text)}</h3>`;
    else if (b.type === "p") content += `<p>${inline(b.text)}</p>`;
    else if (b.type === "quote") content += `<blockquote><p>${inline(b.text)}</p></blockquote>`;
    else if (b.type === "ul")
      content += `<ul>${b.items.map((it) => `<li>${inline(it)}</li>`).join("")}</ul>`;
    else if (b.type === "ol")
      content += `<ol>${b.items.map((it) => `<li>${inline(it)}</li>`).join("")}</ol>`;
    else if (b.type === "table") {
      const head = b.rows[0];
      const body = b.rows.slice(1);
      content += `<table><thead><tr>${head
        .map((c) => `<th>${inline(c)}</th>`)
        .join("")}</tr></thead><tbody>${body
        .map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join("")}</tr>`)
        .join("")}</tbody></table>`;
    }
  }

  const html = `<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="utf-8"/>
<title>${esc(title)}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&family=Noto+Naskh+Arabic:wght@400;600;700&display=swap" rel="stylesheet">
<style>${CSS}</style>
</head>
<body>
<div class="cover">
  <div class="deco1"></div><div class="deco2"></div><div class="deco3"></div>
  <div><span class="badge">وثيقة ${num}</span></div>
  <div class="cover-kicker">حزمة وثائق تطبيق المحاسبة الصغير</div>
  <h1 class="cover-title">${esc(title)}</h1>
  <div class="cover-rule"></div>
  <div class="cover-meta">${chips.map((c) => `<span class="chip">${esc(c)}</span>`).join("")}</div>
  ${related ? `<div class="cover-related">الوثائق المرتبطة: ${esc(related)}</div>` : ""}
  <div class="cover-bottom"><span>مشروع تطبيق المحاسبة الصغير</span><span>إصدار ${esc(meta["الإصدار"] || "0.1")}</span></div>
</div>
<div class="main-content">
${content}
</div>
</body>
</html>`;

  const outPath = path.join(OUT, fileName.replace(/\.md$/, ".html"));
  fs.writeFileSync(outPath, html, "utf8");
  console.log("WROTE", outPath, html.length, "bytes");
  // cover-only copy for cover_validate.js (tool is cover-only by design)
  const covHtml = html.replace(/<div class="main-content">[\s\S]*<\/div>\s*<\/body>/, "</body>");
  const covPath = path.join(OUT, fileName.replace(/\.md$/, ".cover.html"));
  fs.writeFileSync(covPath, covHtml, "utf8");
}

fs.mkdirSync(OUT, { recursive: true });
DOCS.forEach(buildHtml);
console.log("DONE");
