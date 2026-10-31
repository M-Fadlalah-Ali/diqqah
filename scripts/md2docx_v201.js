// md2docx_v201.js — توليد docx عربي RTL كامل لوثائق دِقَّة v2.01 (الحزمة الـ11 + المدموج)
// مبني على سكربت الجيل السابق المجرب (md2docx_docs.js) بتوجيه المصادر والخط وفق هوية دِقَّة
// الاستخدام: node scripts/md2docx_v201.js
"use strict";
const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, PageNumber, AlignmentType, HeadingLevel, WidthType,
  BorderStyle, ShadingType, LevelFormat,
} = require("docx");

const ROOT = path.resolve(__dirname, "..");
const SRC = path.join(ROOT, "docs", "diqqah-v2.01");
const OUT = path.join(SRC, "word");
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

const PACKAGE = [
  "README-v2.01.md",
  "01-vision-and-scope-v2.01.md",
  "02-terminology-v2.01.md",
  "03-chart-of-accounts-v2.01.md",
  "04-srs-v2.01.md",
  "05-data-model-v2.01.md",
  "06-workflows-v2.01.md",
  "07-tryton-principles-v2.01.md",
  "08-sync-strategy-v2.01.md",
  "09-release-plan-v2.01.md",
  "10-test-plan-v2.01.md",
].map((f) => path.join(SRC, f));
const MERGED = [path.join(ROOT, "docs", "diqqah-docs-merged-v2.01.md")];
const DOCS = PACKAGE.concat(MERGED);

const AR_FONT = { ascii: "Amiri", hAnsi: "Amiri", cs: "Amiri", eastAsia: "Amiri" };
const CODE_FONT = { ascii: "DejaVu Sans Mono", hAnsi: "DejaVu Sans Mono", cs: "DejaVu Sans Mono" };
const ACCENT = "14625A";
const ACCENT_DARK = "0D4740";
const HEAD_FILL = "EAF2F0";
const QUOTE_FILL = "F2F7F6";

// ---------- inline parser -> segments ----------
function parseInline(s) {
  const parts = String(s).split(/`([^`]+)`/);
  const segs = [];
  for (let i = 0; i < parts.length; i++) {
    if (i % 2 === 1) { segs.push({ kind: "code", text: parts[i] }); continue; }
    const boldSplit = parts[i].split(/\*\*([^*]+)\*\*/);
    for (let j = 0; j < boldSplit.length; j++) {
      if (boldSplit[j] === "") continue;
      segs.push({ kind: j % 2 === 1 ? "bold" : "text", text: boldSplit[j] });
    }
  }
  return segs.length ? segs : [{ kind: "text", text: "—" }];
}

// ---------- run builders ----------
function runs(segs, opts = {}) {
  return segs.map((sg) => {
    if (sg.kind === "code") {
      return new TextRun({
        text: sg.text, font: CODE_FONT, size: 20, sizeComplexScript: 20,
        color: "0D3B36", rightToLeft: false,
      });
    }
    const bold = sg.kind === "bold" || opts.bold;
    return new TextRun({
      text: sg.text, font: AR_FONT,
      size: opts.size ?? 24, sizeComplexScript: opts.size ?? 24,
      bold: bold || undefined, boldComplexScript: bold || undefined,
      color: opts.color ?? "000000", rightToLeft: true,
    });
  });
}

// ---------- paragraph builders ----------
function para(segs, o = {}) {
  return new Paragraph({
    bidirectional: true,
    alignment: o.align ?? AlignmentType.JUSTIFIED,
    heading: o.heading,
    numbering: o.numbering,
    bullet: o.bullet,
    indent: o.indent,
    border: o.border,
    shading: o.shading,
    keepNext: o.keepNext || undefined,
    spacing: { line: 312, before: o.before ?? 0, after: o.after ?? 120 },
    children: runs(segs, o),
  });
}

function heading(text, level) {
  const conf = {
    1: { size: 36, color: ACCENT_DARK, before: 0, after: 200, align: AlignmentType.CENTER },
    2: { size: 30, color: ACCENT_DARK, before: 320, after: 140, align: AlignmentType.START },
    3: { size: 26, color: ACCENT, before: 240, after: 100, align: AlignmentType.START },
  }[level];
  const hl = { 1: HeadingLevel.HEADING_1, 2: HeadingLevel.HEADING_2, 3: HeadingLevel.HEADING_3 }[level];
  return para([{ kind: "bold", text }], {
    heading: hl, align: conf.align, size: conf.size, color: conf.color,
    before: conf.before, after: conf.after,
  });
}

function quotePara(text) {
  return para(parseInline(text), {
    align: AlignmentType.START,
    shading: { type: ShadingType.CLEAR, fill: QUOTE_FILL },
    border: { right: { style: BorderStyle.SINGLE, size: 24, color: ACCENT, space: 6 } },
    indent: { left: 200, right: 200 },
    after: 160,
  });
}

// ---------- tables ----------
function cellPara(text, opts = {}) {
  return para(parseInline(text), {
    align: AlignmentType.START,
    size: 21, after: 20,
    color: opts.header ? ACCENT_DARK : "000000",
    bold: opts.header || undefined,
  });
}

function buildTable(rows) {
  const nCols = rows[0].cells.length;
  const widths = nCols === 2 ? [28, 72] : Array(nCols).fill(Math.floor(100 / nCols));
  const borders = {
    top: { style: BorderStyle.SINGLE, size: 4, color: "9AA6B2" },
    bottom: { style: BorderStyle.SINGLE, size: 4, color: "9AA6B2" },
    left: { style: BorderStyle.SINGLE, size: 2, color: "D0D0D0" },
    right: { style: BorderStyle.SINGLE, size: 2, color: "D0D0D0" },
    insideHorizontal: { style: BorderStyle.SINGLE, size: 2, color: "D0D0D0" },
    insideVertical: { style: BorderStyle.SINGLE, size: 2, color: "D0D0D0" },
  };
  return new Table({
    visuallyRightToLeft: true,
    width: { size: 100, type: WidthType.PERCENTAGE },
    borders,
    rows: rows.map((r, ri) => new TableRow({
      tableHeader: ri === 0,
      cantSplit: true,
      children: r.cells.map((c, ci) => new TableCell({
        width: { size: widths[ci], type: WidthType.PERCENTAGE },
        shading: ri === 0 ? { type: ShadingType.CLEAR, fill: HEAD_FILL } : undefined,
        margins: { top: 60, bottom: 60, left: 100, right: 100 },
        children: [cellPara(c, { header: ri === 0 })],
      })),
    })),
  });
}

// ---------- block parser (shared shape with md2html) ----------
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
      const body = rows.filter((r) => !r.every((c) => /^:?-{2,}:?$/.test(c)));
      blocks.push({ type: "table", rows: body.map((r) => ({ cells: r })) });
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
    ) { buf.push(lines[i].trim()); i++; }
    blocks.push({ type: "p", text: buf.join(" ") });
  }
  return blocks;
}

// ---------- build one docx ----------
function buildDocx(srcPath) {
  const fileName = path.basename(srcPath);
  const md = fs.readFileSync(srcPath, "utf8").replace(/<!--[\s\S]*?-->/g, "");
  const blocks = parseBlocks(md);
  const h1 = blocks.find((b) => b.type === "h1");
  const title = h1 ? h1.text : fileName;

  // count ordered lists for unique numbering references
  let olCount = 0;
  for (const b of blocks) if (b.type === "ol") b.ref = `ol-${fileName.slice(0, 2)}-${olCount++}`;
  const numbering = {
    config: Array.from({ length: olCount }, (_, k) => ({
      reference: `ol-${fileName.slice(0, 2)}-${k}`,
      levels: [{
        level: 0, format: LevelFormat.DECIMAL, text: "%1.",
        alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } },
      }],
    })),
  };

  const children = [];
  let firstH1 = true;
  for (const b of blocks) {
    if (b.type === "h1") {
      if (firstH1) { firstH1 = false; children.push(heading(b.text, 1)); continue; }
      children.push(heading(b.text, 2));
    } else if (b.type === "h2") children.push(heading(b.text, 2));
    else if (b.type === "h3") children.push(heading(b.text, 3));
    else if (b.type === "p") children.push(para(parseInline(b.text)));
    else if (b.type === "quote") children.push(quotePara(b.text));
    else if (b.type === "hr") continue;
    else if (b.type === "ul") {
      for (const it of b.items) children.push(para(parseInline(it), { bullet: { level: 0 }, align: AlignmentType.START, after: 80 }));
    } else if (b.type === "ol") {
      for (const it of b.items) children.push(para(parseInline(it), { numbering: { reference: b.ref, level: 0 }, align: AlignmentType.START, after: 80 }));
    } else if (b.type === "table") {
      children.push(buildTable(b.rows));
      children.push(new Paragraph({ spacing: { after: 120, line: 312 }, children: [] }));
    }
  }

  const doc = new Document({
    title: `diqqah-doc ${fileName.replace(/\.md$/, "")}`,
    subject: "Diqqah Documentation Pack v2.01",
    creator: "Diqqah Project",
    description: "RTL Arabic specification document",
    styles: {
      default: {
        document: {
          run: { font: AR_FONT, size: 24, color: "000000" },
          paragraph: { spacing: { line: 312 } },
        },
        heading1: {
          run: { font: AR_FONT, size: 36, bold: true, color: ACCENT_DARK },
          paragraph: { spacing: { before: 0, after: 200, line: 312 } },
        },
        heading2: {
          run: { font: AR_FONT, size: 30, bold: true, color: ACCENT_DARK },
          paragraph: { spacing: { before: 320, after: 140, line: 312 } },
        },
        heading3: {
          run: { font: AR_FONT, size: 26, bold: true, color: ACCENT },
          paragraph: { spacing: { before: 240, after: 100, line: 312 } },
        },
      },
    },
    numbering,
    sections: [{
      properties: {
        page: {
          size: { width: 11906, height: 16838 },
          margin: { top: 1440, bottom: 1440, left: 1417, right: 1701 },
        },
      },
      headers: {
        default: new Header({
          children: [new Paragraph({
            bidirectional: true, alignment: AlignmentType.CENTER,
            spacing: { after: 0, line: 240 },
            children: [new TextRun({
              text: title, font: AR_FONT, size: 16, sizeComplexScript: 16,
              color: "888888", rightToLeft: true,
            })],
          })],
        }),
      },
      footers: {
        default: new Footer({
          children: [new Paragraph({
            alignment: AlignmentType.CENTER, spacing: { after: 0, line: 240 },
            children: [new TextRun({
              children: [PageNumber.CURRENT], font: AR_FONT,
              size: 18, sizeComplexScript: 18, color: "888888", rightToLeft: false,
            })],
          })],
        }),
      },
      children,
    }],
  });

  return Packer.toBuffer(doc).then((buf) => {
    const outPath = path.join(OUT, fileName.replace(/\.md$/, ".docx"));
    fs.writeFileSync(outPath, buf);
    console.log("WROTE", outPath, buf.length, "bytes");
  });
}

(async () => {
  for (const d of DOCS) await buildDocx(d);
  console.log("DONE", DOCS.length, "files");
})();
