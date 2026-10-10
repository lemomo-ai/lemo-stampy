/* 小章网站：中英文切换、小章的表情、动画按需加载、滚动出现、介绍视频、“试一试”盖章台、模板墙。没有依赖。 */
(() => {
  "use strict";

  const root = document.documentElement;
  const store = {
    get() { try { return localStorage.getItem("stampy-lang"); } catch (e) { return null; } },
    set(v) { try { localStorage.setItem("stampy-lang", v); } catch (e) { /* 无痕模式等：不记也照常显示 */ } },
  };
  let lang = root.lang === "en" ? "en" : "zh";
  const T = (zh, en) => (lang === "en" ? en : zh);

  // ---------- 英文文案（中文写在 index.html 里） ----------
  const EN = {
    title: "Stampy · A tiny stamp for your copies",
    description: "A little helper that lives in your Mac's menu bar. “For XX use only” — click once in Preview and it's stamped. Your original stays untouched; you get a stamped copy. Nothing is uploaded. Free, no sign-up, no ads.",
    skip: "Skip to content",
    brand: "Stampy",
    brandAria: "Stampy",
    navAria: "Page sections",
    navHow: "How it works",
    navTry: "Try it",
    navWorkshop: "Workshop",
    navFaq: "FAQ",
    navDownload: "Download",

    eyebrow: "A little helper that lives in your Mac's menu bar",
    h1: 'A <span class="squiggle">tiny</span> stamp<br>for your copies.',
    lead: "“For XX use only” — click once in Preview and it's stamped. Your original stays untouched; you get a stamped copy.",
    dlHero: "Download Stampy 1.0",
    tryLink: "Try it right here",
    heroMeta: "Free · macOS 14 or later · Apple silicon & Intel",
    aFlow: "Animation: click Stampy in the menu bar to pick up the stamp, move onto the file in Preview, click once, confirm, and a stamped copy is saved.",
    peekAria: "Stampy — tap to change its face",

    filmKicker: "Stampy in a minute",
    filmH2: "One copy, one purpose",
    filmP: "Visas, bank accounts, rental applications — they all ask for copies of your documents. But a copy can be reused for things you never agreed to. Stamp “For XX use only” on it, and that copy is good for one purpose only.",
    filmAria: "Stampy intro video",
    filmPlay: "Play the intro video",
    filmNote: "With narration and subtitles",

    howKicker: "Three steps",
    howH2: "Pick up, click, save",
    howP: "No exporting, no other apps — right in Preview, where you already read your files.",
    s1h: "Pick up the stamp",
    s1p: "Click Stampy in the menu bar and the stamp follows your pointer. Click again, or press Esc, to put it down.",
    s2h: "Click where it goes",
    s2p: "Move over a PDF or photo open in Preview, scroll to resize, and click. The stamp always stays fully on the page — never cut off at the edge.",
    s3h: "Save a copy",
    s3p: "Confirm, and it's saved as a “_stamped” copy. Your original doesn't change by a single pixel, so you can always start over.",
    aStep1: "Animation: click Stampy in the menu bar, a “Holding Rental” bubble appears, and the stamp follows the pointer.",
    aStep2: "Animation: the stamp moves onto the page, the scroll wheel sizes it to 125%, a click stamps it, and a confirm card appears.",
    aStep3: "Animation: click “Save As…”, “Stamped!” appears under the menu bar, and the stamped copy opens.",

    batchKicker: "Batch stamping",
    batchH2: "A whole stack<br>at once",
    batchP: "Need a dozen copies for a visa or a bank? Drag the files — or a whole folder — onto Stampy in the menu bar, pick a stamp and a spot, and stamp them all in one go. You don't even need to open Preview.",
    bp1: "<b>Just drag them in</b>Drop them on Stampy in the menu bar, or choose “Batch Stamp…” from the panel",
    bp2: "<b>One spot for all — or each its own</b>Tap the 3 × 3 grid or drag on the page; move any single file on its own",
    bp3: "<b>Every page, first page or last page</b>PDFs follow your choice; photos have just one page",
    bp4: "<b>One ID per batch</b>One entry in your history, with every file in it",
    aBatch: "Animation: four files are dragged into the Batch Stamp window, “Stamp 4” is clicked, each file gets a check mark, and “Stamped · 4 files” appears.",

    tryKicker: "Try it",
    tryH2: "Stamp this page",
    tryMouse: "Your pointer is the stamp: scroll to resize, click to stamp. ",
    tryTouch: "Tap the page to stamp; use − / + below to resize. ",
    tryEngine: "These stamps are drawn by the same engine as the app.",
    pickerAria: "Choose a stamp",
    deskAria: "Demo page: click to stamp, or press Enter to stamp somewhere on the page",
    paperTitle: "PROOF OF INCOME",
    toastTitle: "Stamped!",
    toastNote: "demo only, nothing is saved",
    smaller: "Smaller",
    larger: "Larger",
    undo: "Undo",
    clear: "Clear",

    featKicker: "Why Stampy",
    featH2: "A small job, done with care",
    f1h: "Every page of a long PDF",
    f1p: "A 12-page bank statement? Choose “Every page” and the stamp lands in the same spot on each one. Don't want a page? Tap its thumbnail to skip it.",
    aMulti: "Animation: the confirm card switches to “Every page · 6 pages”, then page 6 is tapped to skip it.",
    f2h: "Small and neat",
    f2p: "Long stamps are about 35 mm, round ones 22 mm, square seals 7 mm. They fit beside a signature without covering anything.",
    f3h: "Your original stays untouched",
    f3p: "The stamp goes on a copy. Your original never changes, so a mistake costs nothing.",
    fileA: "Payslip.pdf",
    fileB: "Payslip_stamped.pdf",
    rulerLabel: "37 mm",
    f4h: "Password-protected PDFs, too",
    f4p: "Enter the password once. The stamped copy is locked with the same password, and the password is never saved.",
    altPassword: "The password card, with Stampy looking at you hopefully.",
    f5h: "Every stamp has an ID",
    f5p: "A date and ID on every stamp. Stamp History shows when, for whom, and on which file.",
    altHistory: "The Stamp History window, listing IDs, dates and files.",
    f6h: "Nothing is uploaded",
    f6p: "Everything happens on your Mac. Your IDs and statements never go <span class=\"nw\">anywhere else.</span>",
    f6link: "Privacy →",

    wsKicker: "Stamp Workshop",
    wsH2: "Make your own",
    wsP: "Start from 17 templates: round, square or long, in Chinese or English. Change who it's for, what it's for, the font, border, color and ink texture.",
    aWorkshop: "Animation: the Stamp Workshop switches between a few stamps, and the large preview follows.",
    tabsAria: "Template categories",

    meetKicker: "Say hello",
    meetH2: "This is Stampy",
    meetP: "It lives in your menu bar. It looks eager when you pick up a stamp, happy when you're done, a bit worried when something's off — and when there's nothing to do… <span class=\"nw\">it dozes off.</span>",
    meetTip: "Go on, give it a tap.",
    mNormal: "Calm",
    mExpectant: "Eager",
    mHappy: "Happy",
    mTroubled: "Worried",
    mSleepy: "Sleepy",

    pvKicker: "Privacy",
    pvH2: "Nothing is uploaded",
    pvP: "Everything happens on your Mac — reading the page, drawing the stamp, saving the copy. Your files are never uploaded anywhere, and your stamp history stays on your own computer. Stampy only goes online when you click “Check for Updates…”, to see if there's a new version. It collects nothing and never installs anything by itself.",
    pv1: "<b>Stamping stays on your Mac</b>Reading, stamping and saving all happen locally",
    pv2: "<b>History stays on your Mac</b>Your stamp history is kept on your own computer",
    pv3: "<b>Update checks only when you click</b>It reads one public version.json file and sends no identifiers",

    faqKicker: "FAQ",
    faqH2: "Good questions",
    q1: "What files can I stamp?",
    a1: "Any PDF or photo (JPG, PNG, HEIC and more) open in Preview. For multi-page PDFs, stamp one page or every page. Password-protected PDFs work too — just enter the password once.",
    q2: "Will my original file change?",
    a2: "No. The stamp only goes on a copy, saved next to the original as “name_stamped” by default. A copy can never overwrite the original — not a single pixel of it changes.",
    q3: "Are my files uploaded?",
    a3: "No. Everything happens on your Mac — reading the page, drawing the stamp, saving the copy. Your files are never uploaded anywhere, and your stamp history stays on your own computer. Stampy only goes online when you click “Check for Updates…”, to see if there's a new version. It collects nothing and never installs anything by itself.",
    q4: "Why does it need Accessibility access?",
    a4: "To put the stamp in exactly the right spot on the copy, Stampy needs to know which file is open in Preview and where on the page you clicked — and macOS only shares that through Accessibility access. The first time you open Stampy, it walks you through turning it on in System Settings › Privacy & Security › Accessibility. It only uses this to see which file is open in Preview and where you clicked. You can turn it off in the same place any time.",
    q5: "Why only Preview?",
    a5: "Stampy reads Preview's accessibility info: which file, which page, and where the page sits on screen. Every viewer app exposes this differently, so we focused on making Preview — which comes with every Mac — rock solid. Rather not open Preview? Drag files onto Stampy in the menu bar and batch-stamp them.",
    q6: "Can I stamp lots of files at once?",
    a6: "Yes. Drag a stack of files, or a whole folder, onto Stampy in the menu bar to open Batch Stamp: pick the stamp, the spot and the pages once, and stamp them all. Copies are saved next to the originals by default, or together in one folder. Duplicate names get a number added — nothing is ever overwritten.",
    q7: "What exactly is the stamp?",
    a7: "It's your own note on the copy saying what it's for — usually “For XX use only”. Anyone can see at a glance who the copy is for and why, which makes it hard to reuse for anything else. It doesn't represent any organization, and Stampy doesn't offer styles that look like an organization's seal.",
    q8: "Is it free?",
    a8: 'Yes. Free. No sign-up, no ads. The source is on <a href="https://github.com/lemomo-ai/lemo-stampy">GitHub</a> too, under the MIT License.',
    q9: "What do I need?",
    a9: "macOS 14 Sonoma or later, on a Mac with Apple silicon or Intel.",
    q10: "How do I update?",
    a10: "Click Stampy in the menu bar and choose “Check for Updates…”. If there's a new version, it tells you and opens this page; download it and drag it into Applications to replace the old one. Your stamps and history stay put. Stampy never downloads or installs anything by itself.",
    q11: "Found a bug or have an idea?",
    a11: "Tell us on <a href=\"https://github.com/lemomo-ai/lemo-stampy/issues\">GitHub Issues</a>. Including your macOS version and what you did before the problem helps us find it faster. Ideas are welcome too.",

    dlH2: "Bring Stampy home",
    dlP: "Free. No sign-up, no ads.",
    dlBtn: "Download Stampy 1.0",
    dlReq: "macOS 14 Sonoma or later · Apple silicon & Intel",
    in1: "<b>1</b>Open Stampy.dmg and drag Stampy into Applications",
    in2: "<b>2</b>Open it — Stampy moves into your menu bar",
    in3: "<b>3</b>Follow the prompt to turn it on in Accessibility",

    tagline: "A small stamp, for peace of mind.",
    footerAria: "More",
    ftDownload: "Download",
    ftPrivacy: "Privacy",
    ftFeedback: "Feedback",
    license: 'Free to download and use. Stampy is open source under the <a href="https://github.com/lemomo-ai/lemo-stampy/blob/main/LICENSE">MIT License</a>, with <a href="https://github.com/lemomo-ai/lemo-stampy">source on GitHub</a>.',
  };

  // ---------- 切换语言 ----------
  const ZH = {}; // 第一次切到英文前，把页面上的中文原文存下来
  const textEls = [...document.querySelectorAll("[data-i18n]")];
  const attrEls = [...document.querySelectorAll("[data-i18n-aria], [data-i18n-alt]")];
  textEls.forEach((el) => { ZH["t:" + el.dataset.i18n] = el.innerHTML; });
  attrEls.forEach((el) => {
    if (el.dataset.i18nAria) ZH["a:" + el.dataset.i18nAria] = el.getAttribute("aria-label");
    if (el.dataset.i18nAlt) ZH["l:" + el.dataset.i18nAlt] = el.getAttribute("alt");
  });
  const zhTitle = document.title;
  const metaDesc = document.querySelector('meta[name="description"]');
  const zhDesc = metaDesc && metaDesc.content;
  const listeners = [];

  function applyLang(next, remember) {
    lang = next === "en" ? "en" : "zh";
    root.lang = lang === "en" ? "en" : "zh-CN";
    const en = lang === "en";
    textEls.forEach((el) => { const k = el.dataset.i18n; el.innerHTML = en && EN[k] != null ? EN[k] : ZH["t:" + k]; });
    attrEls.forEach((el) => {
      const a = el.dataset.i18nAria, l = el.dataset.i18nAlt;
      if (a) el.setAttribute("aria-label", en && EN[a] ? EN[a] : ZH["a:" + a]);
      if (l) el.setAttribute("alt", en && EN[l] ? EN[l] : ZH["l:" + l]);
    });
    document.title = en ? EN.title : zhTitle;
    if (metaDesc) metaDesc.content = en ? EN.description : zhDesc;
    document.querySelectorAll("[data-set-lang]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.setLang === lang)));
    document.querySelectorAll("img[data-en-src]").forEach((img) => {
      if (!img.dataset.zhSrc) img.dataset.zhSrc = img.getAttribute("src");
      const want = en ? img.dataset.enSrc : img.dataset.zhSrc;
      if (img.getAttribute("src") !== want) img.setAttribute("src", want);
    });
    showDmgSize();
    listeners.forEach((fn) => fn());
    if (remember) store.set(lang);
    root.classList.remove("i18n-wait");
  }

  document.querySelectorAll("[data-set-lang]").forEach((b) => b.addEventListener("click", () => {
    if (b.dataset.setLang === lang) return;
    applyLang(b.dataset.setLang, true);
    // 链接里带着 ?lang= 时去掉，免得刷新后又被它盖过去
    if (/[?&]lang=/.test(location.search) && history.replaceState) {
      const u = new URL(location.href);
      u.searchParams.delete("lang");
      history.replaceState(null, "", u.pathname + u.search + u.hash);
    }
  }));

  // DMG 大小：只在 <body data-dmg-size="…"> 里填一次
  function showDmgSize() {
    const size = (document.body.dataset.dmgSize || "").trim();
    document.querySelectorAll(".dmg-size").forEach((el) => { el.textContent = size ? " · " + size : ""; });
  }

  // ---------- 小章：按 App 里 36×36 的画法画成 SVG ----------
  const FACE = "#FFF6F0", BLUSH = "#FFB3A3";
  let clipSeq = 0;
  const eye = (x, y) => `<rect x="${x}" y="${y}" width="4" height="6" rx="2" fill="${FACE}"/>`;
  const blush = (x, y, w) => `<rect x="${x}" y="${y}" width="${w}" height="3" rx="1.5" fill="${BLUSH}"/>`;
  const line = (x, y, a = 0) => `<rect x="${x}" y="${y}" width="6" height="2" rx="1" fill="${FACE}" transform="rotate(${a} ${x + 3} ${y + 1})"/>`;
  const faces = {
    normal: () => `<g class="eyes">${eye(11, 14)}${eye(21, 14)}</g>${blush(6, 22, 6)}${blush(24, 22, 6)}`,
    expectant: () => `<g class="eyes">${eye(11, 16)}${eye(21, 16)}</g><circle cx="18" cy="26" r="1.25" fill="none" stroke="${FACE}" stroke-width="1.5"/>${blush(6, 23, 6)}${blush(24, 23, 6)}`,
    happy: () => `<g fill="none" stroke="${FACE}" stroke-width="2" stroke-linecap="round"><path d="M10 19C10 15.5 14 15.5 14 19"/><path d="M22 19C22 15.5 26 15.5 26 19"/><path d="M16.5 21.5C16.5 24 19.5 24 19.5 21.5"/></g>${blush(5, 21, 7)}${blush(24, 21, 7)}`,
    troubled: () => `${line(10, 16, 12)}${line(20, 16, -12)}${line(15, 23)}`,
    sleepy: () => `${line(10, 18)}${line(20, 18)}${blush(6, 23, 6)}${blush(24, 23, 6)}`,
  };
  const MOODS = Object.keys(faces);

  function mascotSVG(mood) {
    const id = `mclip${++clipSeq}`;
    return `<svg viewBox="0 0 36 36" aria-hidden="true" focusable="false"><defs><clipPath id="${id}"><rect width="36" height="36" rx="11"/></clipPath></defs>
      <g clip-path="url(#${id})"><rect width="36" height="36" fill="#C84936"/><rect y="-3" width="36" height="36" rx="11" fill="#E0533D"/>
      <ellipse cx="10.5" cy="7" rx="4.5" ry="2" fill="#fff" fill-opacity=".35"/></g>${(faces[mood] || faces.normal)()}</svg>`;
  }

  function paintMascot(el, mood) {
    el.dataset.mood = mood;
    const size = Number(el.dataset.size || 36);
    el.style.width = el.style.height = size + "px";
    el.innerHTML = mascotSVG(mood);
  }
  document.querySelectorAll(".mascot").forEach((el) => paintMascot(el, el.dataset.mood || "normal"));

  function boing(el) {
    el.classList.remove("boing");
    void el.offsetWidth;
    el.classList.add("boing");
    el.addEventListener("animationend", () => el.classList.remove("boing"), { once: true });
  }

  // 首屏探头的小章：点一下换个表情
  const peek = document.querySelector(".peek");
  if (peek) {
    peek.addEventListener("click", () => {
      const next = MOODS[(MOODS.indexOf(peek.dataset.mood) + 1) % MOODS.length];
      paintMascot(peek, next);
      boing(peek);
    });
  }

  // “认识一下”：点哪个表情，那只小章蹦一下，顶栏的小章也换成这个表情
  const brand = document.querySelector(".brand .mascot");
  document.querySelectorAll(".mood").forEach((btn) => {
    btn.addEventListener("click", () => {
      boing(btn.querySelector(".mascot"));
      if (brand) { paintMascot(brand, btn.dataset.mood); boing(brand); }
    });
  });

  // ---------- 动画视频：快滚到时才加载；英文页用 *-en 素材；减少动态效果时停在封面 ----------
  const reduceMotion = !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  const anims = [...document.querySelectorAll("video.anim")];
  const variant = (path) => (lang === "en" ? path.replace(/(\.\w+)$/, "-en$1") : path);
  const visible = new Set();

  function setAnimSource(v, load) {
    const poster = variant(v.dataset.poster);
    if (v.getAttribute("poster") !== poster) v.setAttribute("poster", poster);
    if (!load && !v.dataset.loaded) return;
    const src = variant(v.dataset.src);
    if (v.getAttribute("src") !== src) {
      v.setAttribute("src", src);
      v.dataset.loaded = "1";
      if (reduceMotion) return;
      v.load();
    }
    if (!reduceMotion && visible.has(v)) { const p = v.play(); if (p && p.catch) p.catch(() => {}); }
  }

  if ("IntersectionObserver" in window) {
    const near = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) { setAnimSource(e.target, true); near.unobserve(e.target); } });
    }, { rootMargin: "400px 0px" });
    const play = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) {
          visible.add(e.target);
          if (!reduceMotion && e.target.getAttribute("src")) { const p = e.target.play(); if (p && p.catch) p.catch(() => {}); }
        } else { visible.delete(e.target); e.target.pause(); }
      });
    }, { threshold: 0.15 });
    anims.forEach((v) => { setAnimSource(v, v.hasAttribute("data-eager")); near.observe(v); play.observe(v); });
  } else {
    anims.forEach((v) => { setAnimSource(v, true); if (!reduceMotion) { v.autoplay = true; v.play && v.play().catch(() => {}); } });
  }
  listeners.push(() => anims.forEach((v) => setAnimSource(v, false)));

  // ---------- 介绍视频：点了才播，带声音和控件 ----------
  const film = document.getElementById("intro");
  const filmBtn = document.querySelector(".film-play");
  if (film && filmBtn) {
    const dur = document.querySelector(".film-dur");
    const showDur = () => {
      const s = Math.round(film.duration);
      if (dur && isFinite(s) && s > 0) dur.textContent = ` · ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    };
    film.addEventListener("loadedmetadata", showDur);
    if (film.readyState >= 1) showDur();
    filmBtn.addEventListener("click", () => {
      film.controls = true;
      film.closest(".film").classList.add("playing");
      const p = film.play();
      if (p && p.catch) p.catch(() => {});
      film.focus({ preventScroll: true });
    });
    film.addEventListener("ended", () => {
      film.controls = false;
      film.closest(".film").classList.remove("playing");
      film.currentTime = 0;
      film.load(); // 回到封面
      filmBtn.focus({ preventScroll: true });
    });
  }

  // ---------- 顶栏、滚动出现 ----------
  const nav = document.querySelector(".nav");
  const onScroll = () => nav.classList.toggle("scrolled", window.scrollY > 8);
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  const io = "IntersectionObserver" in window
    ? new IntersectionObserver((entries) => {
        entries.forEach((e) => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
      }, { rootMargin: "0px 0px -6% 0px", threshold: 0.06 })
    : null;
  document.querySelectorAll(".reveal").forEach((el) => (io ? io.observe(el) : el.classList.add("in")));
  // 从别处点链接直接跳到某一节时，那一节立刻出现
  window.addEventListener("hashchange", () => {
    const t = location.hash && document.querySelector(location.hash);
    if (t) t.querySelectorAll(".reveal").forEach((el) => el.classList.add("in"));
  });

  // ---------- 盖章台 ----------
  const ID_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  const makeID = () => Array.from({ length: 6 }, () => ID_CHARS[Math.floor(Math.random() * ID_CHARS.length)]).join("");
  // 中文页：细框长章、胶囊签、圆章、方印·白文、签注、中英双语；英文页：英文长章、英文圆章、英文胶囊、中英双语、圆章、方印·白文
  const PICKS = { zh: [0, 1, 2, 3, 5, 7], en: [6, 13, 14, 7, 2, 3] };
  const MIN = 0.6, MAX = 2.5;

  const desk = document.querySelector(".desk");
  const paper = desk && desk.querySelector(".paper");
  const layer = desk && desk.querySelector(".paper-stamps");
  const ghost = desk && desk.querySelector(".ghost");
  const ghostImg = ghost && ghost.querySelector("img");
  const hint = ghost && ghost.querySelector(".hint");
  const toast = desk && desk.querySelector(".demo-toast");
  const sizeVal = document.querySelector(".size-val");
  const count = document.querySelector(".play-count");
  const picker = document.querySelector(".picker");

  let all = [];
  let stamps = [];
  let current = 0;
  let mult = 1;
  let sizeHintUntil = 0;
  let toastTimer = 0;
  const placed = [];
  let pointer = null; // 鼠标在桌面里的位置
  const cross = document.createElement("div");
  cross.className = "cross";
  desk && desk.appendChild(cross);

  const nameOf = (s) => (lang === "en" && s.name_en ? s.name_en : s.name);

  // 纸上的灰条：几段“正文”
  const lines = desk && desk.querySelector(".paper-lines");
  if (lines) {
    const paragraphs = [[100, 96, 98, 94, 55], [96, 98, 92, 40], [94, 97, 99, 95, 93, 70], [98, 35]];
    lines.innerHTML = paragraphs.map((p) => p.map((w, i) =>
      `<i style="width:${i === 0 ? w - 6 : w}%;${i === 0 ? "margin-left:6%;" : ""}"${i === p.length - 1 ? ' class="gap"' : ""}></i>`).join("")).join("");
  }

  const ppt = () => paper.clientWidth / 595; // 每个印章点在屏幕上多少像素
  const stampPx = (s, m = mult) => ({ w: s.w * ppt() * m, h: s.h * ppt() * m });

  function select(i, focus) {
    current = i;
    picker.querySelectorAll(".pick").forEach((p, j) => {
      p.setAttribute("aria-checked", String(j === i));
      p.tabIndex = j === i ? 0 : -1;
      if (j === i && focus) p.focus();
    });
    ghostImg.src = stamps[i].file;
    update();
  }

  function renderPicker() {
    stamps = PICKS[lang].map((i) => all[i]).filter(Boolean);
    current = Math.min(current, stamps.length - 1);
    picker.innerHTML = "";
    stamps.forEach((s, i) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "pick";
      b.setAttribute("role", "radio");
      b.innerHTML = `<span class="pick-img"><img src="${s.file}" alt=""></span><span>${nameOf(s)}</span>`;
      b.addEventListener("click", () => select(i));
      b.addEventListener("keydown", (e) => {
        const d = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
        if (!d) return;
        e.preventDefault();
        select((i + d + stamps.length) % stamps.length, true);
      });
      picker.appendChild(b);
    });
    select(current);
  }

  /// 章永远完整留在纸里：和 App 一样，贴边就停住。
  function keptInside(cx, cy, size, rect) {
    const hw = Math.min(size.w / 2, rect.width / 2), hh = Math.min(size.h / 2, rect.height / 2);
    return {
      x: Math.min(Math.max(cx, rect.left + hw), rect.right - hw),
      y: Math.min(Math.max(cy, rect.top + hh), rect.bottom - hh),
    };
  }

  function update() {
    if (!stamps.length) return;
    sizeVal.textContent = Math.round(mult * 100) + "%";
    if (!pointer) { ghost.classList.remove("show"); cross.style.display = "none"; return; }
    const d = desk.getBoundingClientRect();
    const p = paper.getBoundingClientRect();
    const size = stampPx(stamps[current]);
    const onPaper = pointer.x >= p.left && pointer.x <= p.right && pointer.y >= p.top && pointer.y <= p.bottom;
    const c = onPaper ? keptInside(pointer.x, pointer.y, size, p) : pointer;
    ghost.style.transform = `translate(${c.x - d.left}px, ${c.y - d.top}px)`;
    ghostImg.style.width = size.w + "px";
    ghost.classList.add("show");
    ghost.classList.toggle("on", onPaper);
    if (Date.now() < sizeHintUntil) {
      hint.innerHTML = `<span>${T("大小", "Size")}</span><span class="bar"><b style="width:${((mult - MIN) / (MAX - MIN)) * 100}%"></b></span><span class="pct">${Math.round(mult * 100)}%</span>`;
      hint.classList.add("sizing");
    } else {
      hint.innerHTML = `<span class="mini"></span><span>${onPaper ? T("点一下就盖", "Click to stamp") : T("移到纸上", "Move onto the page")}</span>`;
      hint.classList.remove("sizing");
    }
    // 提示条别跑出桌面：贴右边就往左挪，贴底就放到章上面
    const cx = c.x - d.left, cy = c.y - d.top, gap = size.h / 2 + 12;
    const hw = hint.offsetWidth, hh = hint.offsetHeight;
    hint.style.left = Math.max(8 - cx, Math.min(-24, d.width - 8 - hw - cx)) + "px";
    hint.style.top = (cy + gap + hh > d.height - 8 ? -(gap + hh) : gap) + "px";
    cross.style.display = "block";
    cross.style.transform = `translate(${pointer.x - d.left}px, ${pointer.y - d.top}px)`;
  }

  function stampAt(clientX, clientY) {
    const p = paper.getBoundingClientRect();
    const s = stamps[current];
    const size = stampPx(s);
    const c = keptInside(clientX, clientY, size, p);
    const rel = { x: (c.x - p.left) / p.width, y: (c.y - p.top) / p.height };
    const img = document.createElement("img");
    img.src = s.file;
    img.alt = "";
    img.style.left = rel.x * 100 + "%";
    img.style.top = rel.y * 100 + "%";
    img.style.width = (s.w * mult / 595) * 100 + "%";
    layer.appendChild(img);
    placed.push(img);

    const r = document.createElement("span");
    r.className = "ripple";
    r.style.left = img.style.left;
    r.style.top = img.style.top;
    r.style.width = size.w + 8 + "px";
    r.style.height = size.h + 8 + "px";
    r.style.borderRadius = Math.min((size.h + 8) / 2, 12) + "px";
    layer.appendChild(r);
    setTimeout(() => r.remove(), 500);

    desk.querySelector(".demo-id").textContent = makeID();
    toast.classList.toggle("low", rel.y < 0.5); // 盖在上半张就把提示放到下面，别挡住刚盖的章
    toast.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove("show"), 2200);
    refreshCount();
  }

  function refreshCount() {
    if (!count) return;
    const n = placed.length;
    count.textContent = n ? T(`盖了 ${n} 个`, n === 1 ? "1 stamp" : `${n} stamps`) : T("还没盖", "No stamps yet");
  }

  function setMult(m) {
    mult = Math.min(MAX, Math.max(MIN, m));
    sizeHintUntil = Date.now() + 1200;
    update();
    setTimeout(update, 1250);
  }

  if (desk) {
    refreshCount();
    fetch("stamps/stamps.json")
      .then((r) => { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then((list) => {
        all = list;
        renderPicker();
        renderGallery();
        listeners.push(() => { renderPicker(); renderGallery(); refreshCount(); });
      })
      .catch(() => {
        document.querySelector(".playground").innerHTML = `<p class="load-error">${T("印章图没加载出来，刷新一下试试。", "The stamps didn't load. Try refreshing the page.")}</p>`;
      });
    listeners.push(refreshCount);

    desk.addEventListener("pointermove", (e) => {
      if (e.pointerType !== "mouse") return;
      pointer = { x: e.clientX, y: e.clientY };
      update();
    });
    desk.addEventListener("pointerleave", () => { pointer = null; update(); });
    window.addEventListener("scroll", () => { if (pointer) update(); }, { passive: true });
    desk.addEventListener("click", (e) => {
      if (!stamps.length) return;
      const p = paper.getBoundingClientRect();
      if (e.clientX < p.left || e.clientX > p.right || e.clientY < p.top || e.clientY > p.bottom) return;
      stampAt(e.clientX, e.clientY);
    });
    desk.addEventListener("wheel", (e) => {
      if (!pointer) return;
      e.preventDefault();
      setMult(mult * (1 - Math.sign(e.deltaY) * Math.min(Math.abs(e.deltaY), 60) * 0.004));
    }, { passive: false });
    desk.addEventListener("keydown", (e) => {
      if (!stamps.length) return;
      if (e.key === "+" || e.key === "=") { e.preventDefault(); setMult(mult + 0.1); return; }
      if (e.key === "-") { e.preventDefault(); setMult(mult - 0.1); return; }
      if (e.key !== "Enter" && e.key !== " ") return;
      e.preventDefault();
      const p = paper.getBoundingClientRect();
      stampAt(p.left + p.width * (0.3 + Math.random() * 0.4), p.top + p.height * (0.25 + Math.random() * 0.5));
    });
    document.querySelectorAll(".icon-btn[data-step]").forEach((b) => b.addEventListener("click", () => setMult(mult + Number(b.dataset.step) * 0.1)));
    document.querySelector('[data-act="undo"]').addEventListener("click", () => { const img = placed.pop(); img && img.remove(); refreshCount(); });
    document.querySelector('[data-act="clear"]').addEventListener("click", () => { placed.splice(0).forEach((i) => i.remove()); refreshCount(); });
    window.addEventListener("resize", update);
  }

  // ---------- 模板墙 ----------
  let activeCat = null; // null = 全部
  function renderGallery() {
    const tabs = document.querySelector(".tabs");
    const grid = document.querySelector(".grid");
    if (!tabs || !grid || !all.length) return;
    const order = ["常用", "复印件", "英文", "方印"];
    const cats = order.filter((c) => all.some((t) => t.category === c));
    const label = (c) => { const t = all.find((x) => x.category === c); return lang === "en" && t.category_en ? t.category_en : c; };
    const esc = (s) => String(s).replace(/[&<>"]/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[ch]));
    const draw = () => {
      tabs.querySelectorAll(".tab").forEach((t) => t.setAttribute("aria-pressed", String((t.dataset.cat || null) === activeCat)));
      const list = all.filter((t) => !activeCat || t.category === activeCat);
      grid.innerHTML = list.map((t, i) => {
        const name = esc(nameOf(t)), blurb = esc(lang === "en" && t.blurb_en ? t.blurb_en : t.blurb);
        return `<div class="tpl" style="animation-delay:${i * 30}ms">
          <div class="tpl-img"><img src="${t.file}" alt="${name}" loading="lazy"></div>
          <b>${name}</b>
          <small>${blurb}</small>
          <small class="mm">${t.mm[0]} × ${t.mm[1]} mm</small>
        </div>`;
      }).join("");
    };
    tabs.innerHTML = [`<button type="button" class="tab" data-cat="">${T("全部", "All")} · ${all.length}</button>`,
      ...cats.map((c) => `<button type="button" class="tab" data-cat="${c}">${label(c)}</button>`)].join("");
    tabs.querySelectorAll(".tab").forEach((t) => t.addEventListener("click", () => { activeCat = t.dataset.cat || null; draw(); }));
    draw();
  }

  // ---------- 开始 ----------
  showDmgSize();
  if (lang === "en") applyLang("en", false);
  else { refreshCount(); root.classList.remove("i18n-wait"); }
})();
