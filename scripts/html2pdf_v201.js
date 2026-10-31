// html2pdf_v201.js — تحويل HTML الوثائق إلى PDF عبر Chromium (للملفات الثقيلة على Writer)
// الاستخدام: node scripts/html2pdf_v201.js <in.html> <out.pdf>
"use strict";
const path = require("path");
const { chromium } = require("playwright");

(async () => {
  const [inFile, outFile] = process.argv.slice(2);
  if (!inFile || !outFile) { console.error("usage: html2pdf_v201.js <in.html> <out.pdf>"); process.exit(2); }
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto("file://" + path.resolve(inFile), { waitUntil: "load", timeout: 60000 });
  try {
    await page.evaluate(() => Promise.race([document.fonts.ready, new Promise((r) => setTimeout(r, 20000))]));
  } catch (e) { /* الخطوط اختيارية — fallback سليم */ }
  await page.emulateMedia({ media: "print" });
  await page.pdf({ path: outFile, preferCSSPageSize: true, printBackground: true });
  await browser.close();
  console.log("PDF WROTE", outFile);
})();
