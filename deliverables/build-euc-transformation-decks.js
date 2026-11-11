const pptxgen = require(process.env.CODEX_PPTXGENJS_PATH || 'pptxgenjs');
const fs = require('fs');
const path = require('path');

const OUT = path.resolve(__dirname);

const C = {
  navy: '0B1F33',
  navy2: '132F4C',
  blue: '1677FF',
  cyan: '22B8CF',
  teal: '0E9F8A',
  green: '2E9D65',
  amber: 'E9A23B',
  red: 'D9534F',
  purple: '725AC1',
  ink: '17202A',
  gray: '5E6B78',
  gray2: '88939E',
  line: 'D9E1E8',
  pale: 'F4F7FA',
  paleBlue: 'EAF3FF',
  paleTeal: 'E8F8F4',
  paleAmber: 'FFF5E5',
  paleRed: 'FCEDEC',
  white: 'FFFFFF'
};

const FONT = 'Aptos';

function makeDeck(title, subject) {
  const pptx = new pptxgen();
  pptx.layout = 'LAYOUT_WIDE';
  pptx.author = 'EUC Transformation Program';
  pptx.company = 'Client';
  pptx.subject = subject;
  pptx.title = title;
  pptx.lang = 'en-US';
  pptx.theme = {
    headFontFace: FONT,
    bodyFontFace: FONT,
    lang: 'en-US'
  };
  pptx.defineSlideMaster({
    title: 'CONTENT',
    background: { color: C.white },
    objects: [
      { rect: { x: 0, y: 0, w: 13.333, h: 0.13, fill: { color: C.blue }, line: { color: C.blue } } },
      { text: { text: 'EUC TRANSFORMATION', options: { x: 0.55, y: 7.14, w: 2.2, h: 0.18, fontFace: FONT, fontSize: 8, color: C.gray2, charSpacing: 1.4, margin: 0 } } },
      { text: { text: '90-DAY ROADMAP', options: { x: 10.5, y: 7.14, w: 2.25, h: 0.18, fontFace: FONT, fontSize: 8, color: C.gray2, align: 'right', charSpacing: 1.2, margin: 0 } } }
    ],
    slideNumber: { x: 12.8, y: 7.12, w: 0.25, h: 0.18, color: C.gray2, fontFace: FONT, fontSize: 8, align: 'right', margin: 0 }
  });
  return pptx;
}

function addTitle(slide, title, subtitle) {
  slide.addText(title, { x: 0.62, y: 0.38, w: 12.05, h: 0.46, fontFace: FONT, fontSize: 25, bold: true, color: C.navy, margin: 0, breakLine: false, fit: 'shrink' });
  if (subtitle) slide.addText(subtitle, { x: 0.64, y: 0.89, w: 11.85, h: 0.32, fontFace: FONT, fontSize: 11.5, color: C.gray, margin: 0, fit: 'shrink' });
}

function addKicker(slide, text, x = 0.62, y = 0.25, w = 4.0) {
  slide.addText(text.toUpperCase(), { x, y, w, h: 0.2, fontFace: FONT, fontSize: 8.5, bold: true, color: C.blue, charSpacing: 1.6, margin: 0 });
}

function addSectionSlide(pptx, num, title, subtitle, accent = C.blue) {
  const slide = pptx.addSlide();
  slide.background = { color: C.navy };
  slide.addShape(pptx.ShapeType.rect, { x: 0, y: 0, w: 0.18, h: 7.5, fill: { color: accent }, line: { color: accent } });
  slide.addText(String(num).padStart(2, '0'), { x: 0.75, y: 1.08, w: 1.3, h: 0.55, fontFace: FONT, fontSize: 24, bold: true, color: accent, margin: 0 });
  slide.addText(title, { x: 0.75, y: 1.72, w: 10.9, h: 1.05, fontFace: FONT, fontSize: 34, bold: true, color: C.white, margin: 0, fit: 'shrink' });
  slide.addText(subtitle, { x: 0.8, y: 3.0, w: 9.8, h: 0.85, fontFace: FONT, fontSize: 17, color: 'CBD6E2', margin: 0.02, breakLine: false, fit: 'shrink' });
  slide.addShape(pptx.ShapeType.line, { x: 0.8, y: 4.25, w: 3.6, h: 0, line: { color: accent, width: 3 } });
  slide.addText('LOCAL WINDOWS FIRST  |  AVD BY EXCEPTION', { x: 0.8, y: 6.6, w: 5.5, h: 0.23, fontFace: FONT, fontSize: 9, bold: true, color: '91A2B5', charSpacing: 1.15, margin: 0 });
  return slide;
}

function addDeckTitle(pptx, eyebrow, title, subtitle, tag, accent = C.blue) {
  const slide = pptx.addSlide();
  slide.background = { color: C.navy };
  slide.addShape(pptx.ShapeType.rect, { x: 0, y: 0, w: 13.333, h: 7.5, fill: { color: C.navy }, line: { color: C.navy } });
  slide.addShape(pptx.ShapeType.arc, { x: 9.0, y: -1.6, w: 5.7, h: 5.7, rotate: 25, adjustPoint: 0.18, fill: { color: C.navy2, transparency: 10 }, line: { color: C.cyan, transparency: 65, width: 1.5 } });
  slide.addShape(pptx.ShapeType.arc, { x: 10.0, y: 3.9, w: 4.2, h: 4.2, rotate: -35, fill: { color: C.navy2, transparency: 30 }, line: { color: accent, transparency: 55, width: 2 } });
  slide.addShape(pptx.ShapeType.rect, { x: 0, y: 0, w: 0.16, h: 7.5, fill: { color: accent }, line: { color: accent } });
  slide.addText(eyebrow.toUpperCase(), { x: 0.75, y: 0.75, w: 6.1, h: 0.25, fontFace: FONT, fontSize: 10, bold: true, color: accent, charSpacing: 2.0, margin: 0 });
  slide.addText(title, { x: 0.72, y: 1.33, w: 8.7, h: 1.75, fontFace: FONT, fontSize: 37, bold: true, color: C.white, margin: 0, fit: 'shrink', breakLine: false });
  slide.addText(subtitle, { x: 0.76, y: 3.45, w: 7.65, h: 1.0, fontFace: FONT, fontSize: 17, color: 'D3DEE9', margin: 0, fit: 'shrink' });
  slide.addShape(pptx.ShapeType.roundRect, { x: 0.75, y: 5.18, w: 4.4, h: 0.52, rectRadius: 0.06, fill: { color: C.navy2 }, line: { color: '36526E', width: 1 } });
  slide.addText(tag, { x: 0.98, y: 5.32, w: 3.95, h: 0.2, fontFace: FONT, fontSize: 10.5, bold: true, color: C.white, margin: 0, fit: 'shrink' });
  slide.addText('Prepared for leadership discussion  |  October 2026', { x: 0.76, y: 6.72, w: 5.7, h: 0.22, fontFace: FONT, fontSize: 9, color: '91A2B5', margin: 0 });
  return slide;
}

function addCard(slide, pptx, x, y, w, h, title, body, opts = {}) {
  const fill = opts.fill || C.pale;
  const line = opts.line || C.line;
  const accent = opts.accent || C.blue;
  slide.addShape(pptx.ShapeType.roundRect, { x, y, w, h, rectRadius: 0.06, fill: { color: fill }, line: { color: line, width: 1 } });
  if (opts.topBar !== false) slide.addShape(pptx.ShapeType.rect, { x, y, w, h: 0.07, fill: { color: accent }, line: { color: accent } });
  if (opts.badge) {
    slide.addShape(pptx.ShapeType.ellipse, { x: x + 0.22, y: y + 0.22, w: 0.42, h: 0.42, fill: { color: accent }, line: { color: accent } });
    slide.addText(opts.badge, { x: x + 0.22, y: y + 0.305, w: 0.42, h: 0.15, fontFace: FONT, fontSize: 9, bold: true, align: 'center', color: C.white, margin: 0 });
  }
  const tx = opts.badge ? x + 0.78 : x + 0.24;
  slide.addText(title, { x: tx, y: y + 0.2, w: w - (tx - x) - 0.22, h: 0.31, fontFace: FONT, fontSize: opts.titleSize || 13, bold: true, color: opts.titleColor || C.navy, margin: 0, fit: 'shrink' });
  if (Array.isArray(body)) {
    const runs = [];
    body.forEach((t, i) => {
      runs.push({ text: t, options: { bullet: { indent: 14 }, breakLine: i < body.length - 1 } });
    });
    slide.addText(runs, { x: x + 0.24, y: y + 0.68, w: w - 0.48, h: h - 0.84, fontFace: FONT, fontSize: opts.bodySize || 10.5, color: opts.bodyColor || C.ink, margin: 0.03, paraSpaceAfterPt: 7, breakLine: false, fit: 'shrink', valign: 'top' });
  } else {
    slide.addText(body, { x: x + 0.24, y: y + 0.65, w: w - 0.48, h: h - 0.82, fontFace: FONT, fontSize: opts.bodySize || 10.5, color: opts.bodyColor || C.ink, margin: 0.03, fit: 'shrink', valign: 'top', breakLine: false });
  }
}

function addMetric(slide, pptx, x, y, w, value, label, color = C.blue, note = '') {
  slide.addShape(pptx.ShapeType.roundRect, { x, y, w, h: 1.16, rectRadius: 0.06, fill: { color: C.white }, line: { color: C.line, width: 1 } });
  slide.addText(value, { x: x + 0.18, y: y + 0.15, w: w - 0.36, h: 0.38, fontFace: FONT, fontSize: 24, bold: true, color, margin: 0, fit: 'shrink' });
  slide.addText(label, { x: x + 0.18, y: y + 0.58, w: w - 0.36, h: 0.23, fontFace: FONT, fontSize: 10, bold: true, color: C.navy, margin: 0, fit: 'shrink' });
  if (note) slide.addText(note, { x: x + 0.18, y: y + 0.84, w: w - 0.36, h: 0.18, fontFace: FONT, fontSize: 8.5, color: C.gray, margin: 0, fit: 'shrink' });
}

function addPhase(slide, pptx, x, y, w, h, phase, days, title, items, color, arrow = true) {
  slide.addShape(pptx.ShapeType.roundRect, { x, y, w, h, rectRadius: 0.04, fill: { color: C.white }, line: { color: C.line, width: 1 } });
  slide.addShape(pptx.ShapeType.rect, { x, y, w, h: 0.56, fill: { color }, line: { color } });
  slide.addText(`${phase}  |  ${days}`, { x: x + 0.14, y: y + 0.17, w: w - 0.28, h: 0.2, fontFace: FONT, fontSize: 9.5, bold: true, color: C.white, margin: 0, fit: 'shrink' });
  slide.addText(title, { x: x + 0.16, y: y + 0.73, w: w - 0.32, h: 0.42, fontFace: FONT, fontSize: 13, bold: true, color: C.navy, margin: 0, fit: 'shrink' });
  const runs = [];
  items.forEach((t, i) => runs.push({ text: t, options: { bullet: { indent: 12 }, breakLine: i < items.length - 1 } }));
  slide.addText(runs, { x: x + 0.16, y: y + 1.24, w: w - 0.32, h: h - 1.42, fontFace: FONT, fontSize: 9.3, color: C.ink, margin: 0.02, paraSpaceAfterPt: 5, fit: 'shrink', valign: 'top' });
  if (arrow) slide.addShape(pptx.ShapeType.chevron, { x: x + w + 0.04, y: y + h / 2 - 0.17, w: 0.28, h: 0.34, fill: { color: C.line }, line: { color: C.line } });
}

function addSourceLine(slide, text) {
  slide.addText(text, { x: 0.64, y: 6.82, w: 11.95, h: 0.21, fontFace: FONT, fontSize: 7.5, italic: true, color: C.gray2, margin: 0, fit: 'shrink' });
}

function addDecision(slide, pptx, n, y, title, detail, owner) {
  slide.addShape(pptx.ShapeType.ellipse, { x: 0.8, y, w: 0.5, h: 0.5, fill: { color: C.blue }, line: { color: C.blue } });
  slide.addText(String(n), { x: 0.8, y: y + 0.14, w: 0.5, h: 0.18, fontFace: FONT, fontSize: 11, bold: true, align: 'center', color: C.white, margin: 0 });
  slide.addText(title, { x: 1.52, y: y + 0.01, w: 5.3, h: 0.27, fontFace: FONT, fontSize: 13, bold: true, color: C.navy, margin: 0, fit: 'shrink' });
  slide.addText(detail, { x: 1.52, y: y + 0.33, w: 8.65, h: 0.35, fontFace: FONT, fontSize: 9.8, color: C.gray, margin: 0, fit: 'shrink' });
  slide.addShape(pptx.ShapeType.roundRect, { x: 10.5, y: y + 0.03, w: 1.7, h: 0.4, rectRadius: 0.03, fill: { color: C.paleBlue }, line: { color: C.paleBlue } });
  slide.addText(owner, { x: 10.65, y: y + 0.15, w: 1.4, h: 0.14, fontFace: FONT, fontSize: 8.5, bold: true, color: C.blue, align: 'center', margin: 0, fit: 'shrink' });
}

function drawArrow(slide, pptx, x, y, w, color = C.blue) {
  slide.addShape(pptx.ShapeType.chevron, { x, y, w, h: 0.48, fill: { color }, line: { color } });
}

// ---------------- Executive deck ----------------

function buildExecutiveDeck() {
  const pptx = makeDeck('Local-First Workplace Transformation - Executive Summary', 'Executive 90-day Citrix exit roadmap');
  addDeckTitle(
    pptx,
    'Executive decision deck',
    'Local-First Workplace Transformation',
    'A 90-day plan to move work from Citrix to Windows 11 laptops while creating AVD as a governed exception service.',
    '3,000 endpoints  |  Financial services  |  Decision draft',
    C.cyan
  );

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Recommendation');
    addTitle(s, 'Set a clear direction: local Windows is the default', 'AVD is the exception path; Citrix becomes a time-bound transition platform.');
    s.addShape(pptx.ShapeType.roundRect, { x: 0.75, y: 1.48, w: 4.0, h: 4.55, rectRadius: 0.07, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('THE DECISION', { x: 1.08, y: 1.83, w: 2.1, h: 0.2, fontFace: FONT, fontSize: 9, bold: true, color: C.cyan, charSpacing: 1.4, margin: 0 });
    s.addText('Make the laptop the primary workplace.', { x: 1.05, y: 2.2, w: 3.35, h: 1.05, fontFace: FONT, fontSize: 27, bold: true, color: C.white, margin: 0, fit: 'shrink' });
    s.addText('Every remaining Citrix dependency receives an owner, an exception rationale, and a retirement date.', { x: 1.08, y: 3.62, w: 3.2, h: 1.0, fontFace: FONT, fontSize: 14, color: 'D4DFE9', margin: 0, fit: 'shrink' });
    s.addShape(pptx.ShapeType.line, { x: 1.08, y: 5.12, w: 2.85, h: 0, line: { color: C.cyan, width: 2.5 } });
    s.addText('Culture and decision latency are the largest program risks.', { x: 1.08, y: 5.32, w: 3.05, h: 0.42, fontFace: FONT, fontSize: 11, bold: true, color: C.white, margin: 0, fit: 'shrink' });

    addCard(s, pptx, 5.15, 1.48, 3.45, 2.05, 'What changes', [
      'VP-level mandate and business ownership',
      'Controlled migration waves with exit gates',
      'One source of truth for readiness and blockers'
    ], { accent: C.blue, fill: C.paleBlue, bodySize: 11 });
    addCard(s, pptx, 8.92, 1.48, 3.45, 2.05, 'What does not change', [
      'Security and regulatory controls',
      'Supported engineering practices',
      'AVD availability for justified exceptions'
    ], { accent: C.teal, fill: C.paleTeal, bodySize: 11 });
    addCard(s, pptx, 5.15, 3.88, 7.22, 2.15, 'Management principle', 'Do not drive this program by calendar alone. Promote each wave only when application, user-data, endpoint, security, and support readiness are green.', { accent: C.amber, fill: C.paleAmber, titleSize: 14, bodySize: 16 });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'North star');
    addTitle(s, 'Move from a Citrix-centric workplace to a local-first service', 'The end state simplifies the user experience while preserving controlled virtualization.');
    addCard(s, pptx, 0.72, 1.45, 3.45, 4.8, 'Today', [
      'Most work occurs inside Citrix',
      'User data redirected to a filer',
      'Application knowledge embedded in gold images',
      'Inconsistent Intune and legacy policy',
      'Webex remains the collaboration default',
      'Support and request work is highly manual'
    ], { accent: C.red, fill: C.paleRed, titleSize: 18, bodySize: 13 });
    drawArrow(s, pptx, 4.45, 3.5, 0.7, C.blue);
    addCard(s, pptx, 5.42, 1.45, 3.45, 4.8, '90-day transition state', [
      'Repeatable migration factory',
      'Production Intune baseline in rings',
      'OneDrive data path proven',
      'Champions validate real workflows',
      'ServiceNow intake and evidence automated',
      'Named AVD exception population'
    ], { accent: C.amber, fill: C.paleAmber, titleSize: 18, bodySize: 13 });
    drawArrow(s, pptx, 9.12, 3.5, 0.7, C.teal);
    addCard(s, pptx, 10.08, 1.45, 2.55, 4.8, 'Target', [
      'Laptop is primary',
      'Teams is standard',
      'AVD is governed',
      'Citrix declines by design',
      'Support is data-driven'
    ], { accent: C.teal, fill: C.paleTeal, titleSize: 18, bodySize: 13 });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Day 90 outcomes');
    addTitle(s, 'Build the factory, migrate safely, and establish the finish line', 'The full-estate commitment should be made after the day-30 readiness gate.');
    addMetric(s, pptx, 0.72, 1.5, 2.75, '900-1,500', 'users migrated', C.blue, '30-50% of the estate');
    addMetric(s, pptx, 3.66, 1.5, 2.75, '98%+', 'required app success', C.teal, 'per production wave');
    addMetric(s, pptx, 6.60, 1.5, 2.75, '<2%', 'policy conflict rate', C.purple, 'before broader promotion');
    addMetric(s, pptx, 9.54, 1.5, 2.75, '100%', 'exceptions owned', C.amber, 'reason, owner, end date');
    addCard(s, pptx, 0.72, 3.0, 3.72, 2.8, 'Operational foundation', [
      'Versioned Windows 11 / Intune baseline',
      'GlobalProtect and critical apps available',
      'Policy transition and reset exception process'
    ], { accent: C.blue, fill: C.paleBlue, titleSize: 15, bodySize: 11.5 });
    addCard(s, pptx, 4.70, 3.0, 3.72, 2.8, 'User and data readiness', [
      'Migration Manager plus KFM playbook',
      'Champion network and feedback intake',
      'Automated communications and hypercare'
    ], { accent: C.teal, fill: C.paleTeal, titleSize: 15, bodySize: 11.5 });
    addCard(s, pptx, 8.68, 3.0, 3.72, 2.8, 'Controlled virtualization', [
      'AVD for contractors and legacy workloads',
      'Isolated treatment for risky applications',
      'Citrix retirement forecast and cost view'
    ], { accent: C.amber, fill: C.paleAmber, titleSize: 15, bodySize: 11.5 });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Roadmap');
    addTitle(s, 'Five gated phases over 90 days', 'Move forward only when user productivity and platform health meet the agreed threshold.');
    const y = 1.55, h = 4.75, w = 2.22, gap = 0.29;
    addPhase(s, pptx, 0.58, y, w, h, 'PHASE 1', 'DAYS 1-15', 'Mobilize', ['Mandate and RACI', 'Inventory and personas', 'Champion recruitment', 'Policy source map'], C.navy2);
    addPhase(s, pptx, 0.58 + (w + gap), y, w, h, 'PHASE 2', 'DAYS 16-30', 'Prove', ['GlobalProtect', 'Intune canary', 'OneDrive pilot', 'Critical apps'], C.blue);
    addPhase(s, pptx, 0.58 + 2 * (w + gap), y, w, h, 'PHASE 3', 'DAYS 31-45', 'Champion pilot', ['50-100 users', 'Two business units', 'Daily hypercare', 'Workflow validation'], C.cyan);
    addPhase(s, pptx, 0.58 + 3 * (w + gap), y, w, h, 'PHASE 4', 'DAYS 46-65', 'Wave 1', ['250-400 users', 'ServiceNow evidence', 'Issue burn-down', 'Readiness scoring'], C.teal);
    addPhase(s, pptx, 0.58 + 4 * (w + gap), y, w, h, 'PHASE 5', 'DAYS 66-90', 'Scale', ['300-500 per week', 'Hold / exception path', 'AVD placement', 'Retirement forecast'], C.purple, false);
    s.addShape(pptx.ShapeType.roundRect, { x: 0.82, y: 6.47, w: 11.65, h: 0.44, rectRadius: 0.03, fill: { color: C.paleAmber }, line: { color: C.paleAmber } });
    s.addText('Day 30 decision: commit the final migration rate only after policy, data, app, and support evidence is available.', { x: 1.0, y: 6.60, w: 11.25, h: 0.16, fontFace: FONT, fontSize: 10, bold: true, color: '8A5B11', align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Program risk');
    addTitle(s, 'The largest risk is organizational friction, not technical feasibility', 'The plan converts cultural and operational risks into visible owners and gates.');
    const risks = [
      ['1', 'Leadership ambiguity', 'Citrix remains the perceived safe default.', 'VP mandate; BU-level accountability', C.red],
      ['2', 'Unknown dependencies', 'Legacy workflows surface late in a wave.', 'Champions + usage telemetry + hold ring', C.amber],
      ['3', 'Policy collision', 'GPO, Intune, ConfigMgr and scripts overlap.', 'Source map; explicit reversal; canary evidence', C.purple],
      ['4', 'Data cutover', 'Redirects are broken before reconciliation.', 'Pre-stage, reconcile, rollback retention', C.blue],
      ['5', 'Weak support model', 'L1/L2 cannot diagnose migration issues.', 'Automated evidence + KB + hypercare', C.teal]
    ];
    risks.forEach((r, i) => {
      const y = 1.44 + i * 1.02;
      s.addShape(pptx.ShapeType.roundRect, { x: 0.72, y, w: 11.92, h: 0.82, rectRadius: 0.03, fill: { color: i % 2 === 0 ? C.pale : C.white }, line: { color: C.line, width: 0.8 } });
      s.addShape(pptx.ShapeType.ellipse, { x: 0.93, y: y + 0.18, w: 0.45, h: 0.45, fill: { color: r[4] }, line: { color: r[4] } });
      s.addText(r[0], { x: 0.93, y: y + 0.31, w: 0.45, h: 0.14, fontFace: FONT, fontSize: 9, bold: true, align: 'center', color: C.white, margin: 0 });
      s.addText(r[1], { x: 1.60, y: y + 0.17, w: 2.18, h: 0.25, fontFace: FONT, fontSize: 12, bold: true, color: C.navy, margin: 0, fit: 'shrink' });
      s.addText(r[2], { x: 3.95, y: y + 0.17, w: 3.65, h: 0.34, fontFace: FONT, fontSize: 10, color: C.gray, margin: 0, fit: 'shrink' });
      s.addText(r[3], { x: 8.02, y: y + 0.17, w: 4.2, h: 0.34, fontFace: FONT, fontSize: 10, bold: true, color: r[4], margin: 0, fit: 'shrink' });
    });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Capacity');
    addTitle(s, 'Shift capacity from packaging to delivery, data, automation, and adoption', 'Packaging is nearing completion; coordination and KTLO are now the delivery constraints.');
    s.addShape(pptx.ShapeType.roundRect, { x: 0.72, y: 1.45, w: 4.1, h: 4.95, rectRadius: 0.06, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('Primary constraint', { x: 1.05, y: 1.82, w: 2.3, h: 0.25, fontFace: FONT, fontSize: 11, bold: true, color: C.cyan, margin: 0 });
    s.addText('One person currently spans product ownership, EUC architecture, AVD ownership, and escalation.', { x: 1.02, y: 2.3, w: 3.45, h: 1.25, fontFace: FONT, fontSize: 20, bold: true, color: C.white, margin: 0, fit: 'shrink' });
    s.addText('Protect architecture capacity by moving wave coordination, reporting, and ticket choreography to dedicated owners.', { x: 1.05, y: 4.08, w: 3.35, h: 1.15, fontFace: FONT, fontSize: 13, color: 'D1DDE8', margin: 0, fit: 'shrink' });
    s.addText('5-6 core resources + temporary hypercare', { x: 1.05, y: 5.73, w: 3.35, h: 0.32, fontFace: FONT, fontSize: 12, bold: true, color: C.white, margin: 0, fit: 'shrink' });
    const roles = [
      ['Change / wave lead', '1.0', C.blue],
      ['Intune / endpoint engineer', '1.0', C.purple],
      ['OneDrive / data engineer', '1.0', C.teal],
      ['Automation engineer', '1.0', C.cyan],
      ['Service desk / knowledge lead', '1.0', C.amber],
      ['Packaging maintenance', '0.5-1.0', C.gray]
    ];
    roles.forEach((r, i) => {
      const y = 1.52 + i * 0.79;
      s.addShape(pptx.ShapeType.roundRect, { x: 5.22, y, w: 7.05, h: 0.61, rectRadius: 0.03, fill: { color: i % 2 ? C.white : C.pale }, line: { color: C.line, width: 0.8 } });
      s.addShape(pptx.ShapeType.rect, { x: 5.22, y, w: 0.09, h: 0.61, fill: { color: r[2] }, line: { color: r[2] } });
      s.addText(r[0], { x: 5.55, y: y + 0.19, w: 4.75, h: 0.21, fontFace: FONT, fontSize: 11.5, bold: true, color: C.navy, margin: 0, fit: 'shrink' });
      s.addText(r[1], { x: 10.58, y: y + 0.18, w: 1.25, h: 0.22, fontFace: FONT, fontSize: 12, bold: true, color: r[2], align: 'right', margin: 0 });
    });
    s.addText('Plus 2-4 temporary analysts during broad deployment and named fractional support from network, identity, storage, security and application teams.', { x: 5.32, y: 6.32, w: 6.85, h: 0.36, fontFace: FONT, fontSize: 9.5, color: C.gray, italic: true, margin: 0, fit: 'shrink' });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Decisions required');
    addTitle(s, 'Leadership actions needed now', 'These decisions remove the organizational blockers that engineering alone cannot solve.');
    addDecision(s, pptx, 1, 1.38, 'Confirm local-first, AVD-by-exception', 'Set the target operating model and require a retirement rationale for each Citrix dependency.', 'Executive sponsor');
    addDecision(s, pptx, 2, 2.32, 'Assign business-unit owners', 'Each BU names champions, validates workflows, and accepts its production wave.', 'BU leadership');
    addDecision(s, pptx, 3, 3.26, 'Approve the temporary delivery team', 'Prioritize change, endpoint, data, automation and support capacity over additional packaging.', 'Program sponsor');
    addDecision(s, pptx, 4, 4.20, 'Approve exception and reset standards', 'Permit a small, documented reset pool when device state cannot be trusted or remediated.', 'Security + EUC');
    addDecision(s, pptx, 5, 5.14, 'Approve the data and automation guardrails', 'Authorize metadata-only profile analysis and bounded ServiceNow / AI assistance.', 'Risk + ITSM');
    s.addShape(pptx.ShapeType.roundRect, { x: 0.82, y: 6.24, w: 11.55, h: 0.48, rectRadius: 0.03, fill: { color: C.paleBlue }, line: { color: C.paleBlue } });
    s.addText('Required outcome: named decisions and owners within 10 business days.', { x: 1.0, y: 6.39, w: 11.2, h: 0.17, fontFace: FONT, fontSize: 11, bold: true, color: C.blue, align: 'center', margin: 0 });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Immediate next steps');
    addTitle(s, 'Start the evidence cycle in the next 10 business days', 'The plan becomes credible when the first canary, migration, and support evidence is visible.');
    const steps = [
      ['01', 'Sponsor alignment', 'Approve north star, outcomes, owners and decision gates.', C.blue],
      ['02', 'Platform baseline', 'Export Intune policy, device, app and conflict inventories.', C.purple],
      ['03', 'Data pilot', 'Pre-provision OneDrive and run a small Migration Manager pilot.', C.teal],
      ['04', 'Canary cohort', 'Select 20-30 representative IT devices and 50-100 champions.', C.cyan],
      ['05', 'Support MVP', 'Create structured ServiceNow intake and endpoint evidence lookup.', C.amber],
      ['06', 'Day-30 gate', 'Set the committed weekly rate from measured readiness.', C.green]
    ];
    steps.forEach((st, i) => {
      const col = i % 3, row = Math.floor(i / 3);
      const x = 0.72 + col * 4.12, y = 1.5 + row * 2.35;
      addCard(s, pptx, x, y, 3.7, 1.95, st[1], st[2], { accent: st[3], fill: row === 0 ? C.pale : C.white, badge: st[0], titleSize: 14, bodySize: 10.5 });
    });
    s.addText('Executive checkpoint: confirm whether the day-90 goal is full migration or a proven factory plus partial migration.', { x: 1.3, y: 6.38, w: 10.7, h: 0.28, fontFace: FONT, fontSize: 12, bold: true, color: C.navy, align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Appendix');
    addTitle(s, 'Key assumptions and source basis', 'Validate these assumptions during mobilization; they determine the final migration rate.');
    addCard(s, pptx, 0.72, 1.4, 5.8, 4.95, 'Working assumptions', [
      'Approximately 3,000 primarily Windows 11 laptops',
      'Laptops are Microsoft Entra joined and Intune managed',
      'Packaging is substantially complete',
      'MDE is deployed to laptops and Citrix hosts',
      'Citrix Director data is available',
      'SharePoint Migration Manager is the data movement tool',
      'AVD build is underway for contractors and legacy workloads'
    ], { accent: C.blue, fill: C.paleBlue, titleSize: 16, bodySize: 11.2 });
    addCard(s, pptx, 6.82, 1.4, 5.8, 4.95, 'Primary sources', [
      'Microsoft: Windows deployment ring guidance',
      'Microsoft: Intune profile removal and CSP tattooing',
      'Microsoft: OneDrive KFM and file-share transition',
      'Microsoft: OneDrive virtual-desktop support',
      'Microsoft: Autopilot Reset requirements',
      'ServiceNow: Intune spoke and Record Producers',
      'ServiceNow: Now Assist / AI Agent Studio'
    ], { accent: C.teal, fill: C.paleTeal, titleSize: 16, bodySize: 11.2 });
    addSourceLine(s, 'Detailed URLs and implementation notes are included in the technical plan deck.');
  }

  return pptx.writeFile({ fileName: path.join(OUT, 'EUC-Transformation-Executive-Summary.pptx') });
}

// ---------------- Technical deck ----------------

function buildTechnicalDeck() {
  const pptx = makeDeck('Local-First Workplace Transformation - Technical Plan', 'Technical implementation plan for Citrix exit, Windows 11, Intune, OneDrive, AVD and ServiceNow');
  addDeckTitle(
    pptx,
    'Technical implementation plan',
    'Citrix Exit and Local-First Workplace',
    'Architecture, migration sequencing, control gates, automation, support and delivery model for approximately 3,000 Windows endpoints.',
    'Technical working deck  |  Assumptions require validation',
    C.blue
  );

  addSectionSlide(pptx, 1, 'Target architecture and principles', 'Design the service around the local Windows endpoint; place only justified workloads into AVD.');

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Design principles');
    addTitle(s, 'Seven principles govern every technical decision', 'They prevent the program from recreating Citrix complexity on new platforms.');
    const principles = [
      ['Local first', 'Laptop is the default execution environment.', C.blue],
      ['AVD by exception', 'Contractors, legacy and isolated-risk workloads.', C.purple],
      ['One owner per setting', 'Eliminate duplicate policy sources.', C.cyan],
      ['Data before redirect', 'Pre-stage and reconcile before KFM cutover.', C.teal],
      ['Evidence before scale', 'Promote only when gates are green.', C.green],
      ['Automate the handoffs', 'Reduce KTLO and manual ticket tasks.', C.amber],
      ['AI assists; controls decide', 'No free-form or autonomous endpoint changes.', C.red]
    ];
    principles.forEach((p, i) => {
      const col = i % 4, row = Math.floor(i / 4);
      const x = 0.66 + col * 3.16, y = 1.42 + row * 2.38;
      addCard(s, pptx, x, y, 2.82, 2.02, p[0], p[1], { accent: p[2], fill: row === 0 ? C.pale : C.white, badge: String(i + 1), titleSize: 14, bodySize: 10.5 });
    });
    addCard(s, pptx, 10.14, 3.8, 2.82, 2.02, 'Security boundary', 'Supported controls and regulatory requirements remain non-negotiable throughout coexistence.', { accent: C.navy, fill: C.paleBlue, badge: '8', titleSize: 14, bodySize: 10.5 });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Target service');
    addTitle(s, 'Target operating model: three governed execution paths', 'Identity, device state, application need and data risk determine the route.');
    // Users
    s.addShape(pptx.ShapeType.roundRect, { x: 0.7, y: 2.0, w: 2.05, h: 3.1, rectRadius: 0.06, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('USER PERSONAS', { x: 1.02, y: 2.32, w: 1.4, h: 0.2, fontFace: FONT, fontSize: 9, bold: true, color: C.cyan, charSpacing: 1.2, align: 'center', margin: 0 });
    s.addText('Employees\nRemote users\nContractors\nLegacy app users', { x: 0.98, y: 2.86, w: 1.48, h: 1.6, fontFace: FONT, fontSize: 15, bold: true, color: C.white, align: 'center', valign: 'mid', margin: 0, breakLine: false, fit: 'shrink' });
    drawArrow(s, pptx, 2.95, 3.24, 0.65, C.blue);
    // Decision plane
    addCard(s, pptx, 3.83, 1.52, 2.65, 4.03, 'Decision plane', [
      'Entra identity and Conditional Access',
      'Intune compliance and endpoint health',
      'Persona and application entitlement',
      'Data and regulatory requirements',
      'Exception approval and expiry'
    ], { accent: C.blue, fill: C.paleBlue, titleSize: 16, bodySize: 11.5 });
    // paths
    const paths = [
      ['LOCAL WINDOWS 11', 'Primary workplace\nOneDrive KFM\nTeams + GlobalProtect\nIntune-managed apps', C.teal, C.paleTeal],
      ['AZURE VIRTUAL DESKTOP', 'Offshore contractors\nLegacy dependencies\nIsolated risky apps\nTime-bound exceptions', C.purple, 'F1ECFA'],
      ['CITRIX TRANSITION', 'Temporary coexistence\nFallback with owner\nDeclining population\nRetirement forecast', C.amber, C.paleAmber]
    ];
    paths.forEach((p, i) => {
      const y = 1.28 + i * 1.82;
      drawArrow(s, pptx, 6.73, y + 0.48, 0.55, p[2]);
      s.addShape(pptx.ShapeType.roundRect, { x: 7.5, y, w: 4.75, h: 1.42, rectRadius: 0.05, fill: { color: p[3] }, line: { color: p[2], width: 1.2 } });
      s.addText(p[0], { x: 7.8, y: y + 0.2, w: 4.15, h: 0.24, fontFace: FONT, fontSize: 12.5, bold: true, color: p[2], margin: 0, fit: 'shrink' });
      s.addText(p[1], { x: 7.8, y: y + 0.55, w: 4.05, h: 0.65, fontFace: FONT, fontSize: 10.5, color: C.ink, margin: 0, breakLine: false, fit: 'shrink' });
    });
    s.addText('The Citrix path has no permanent default membership.', { x: 7.65, y: 6.7, w: 4.5, h: 0.2, fontFace: FONT, fontSize: 9.5, bold: true, color: C.red, align: 'center', margin: 0 });
  }

  addSectionSlide(pptx, 2, '90-day delivery system', 'Parallel technical workstreams converge through explicit readiness gates and controlled migration waves.', C.cyan);

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Integrated plan');
    addTitle(s, 'Six parallel workstreams converge on the migration waves', 'The day-30 gate sets the committed production rate from measured evidence.');
    const weeksX = 3.1, weekW = 0.69;
    for (let i = 0; i < 13; i++) {
      s.addText(`W${i + 1}`, { x: weeksX + i * weekW, y: 1.25, w: weekW - 0.03, h: 0.18, fontFace: FONT, fontSize: 7.8, color: C.gray2, align: 'center', margin: 0 });
      s.addShape(pptx.ShapeType.line, { x: weeksX + i * weekW, y: 1.52, w: 0, h: 4.78, line: { color: 'E8EDF2', width: 0.5 } });
    }
    const lanes = [
      ['Leadership & change', [[1,2,'Mandate'],[3,13,'Champions + scorecard']], C.blue],
      ['Endpoint & policy', [[1,3,'Source map'],[4,6,'Canary'],[7,13,'Promote']], C.purple],
      ['Apps & connectivity', [[1,3,'Inventory + GP'],[4,7,'Critical apps'],[8,13,'Factory']], C.cyan],
      ['User data', [[1,3,'Pre-stage'],[4,6,'Pilot'],[7,13,'Migrate + KFM']], C.teal],
      ['Teams & AVD', [[1,4,'Personas'],[5,8,'Pilot'],[9,13,'Exception svc']], C.amber],
      ['Migration waves', [[3,4,'IT'],[5,6,'50-100'],[7,9,'250-400'],[10,13,'300-500/wk']], C.green]
    ];
    lanes.forEach((lane, i) => {
      const y = 1.62 + i * 0.77;
      s.addText(lane[0], { x: 0.68, y: y + 0.16, w: 2.12, h: 0.22, fontFace: FONT, fontSize: 10.5, bold: true, color: C.navy, margin: 0, fit: 'shrink' });
      s.addShape(pptx.ShapeType.rect, { x: weeksX, y, w: 13 * weekW, h: 0.53, fill: { color: 'F5F7F9' }, line: { color: 'F5F7F9' } });
      lane[1].forEach(seg => {
        const x = weeksX + (seg[0] - 1) * weekW + 0.03;
        const w = (seg[1] - seg[0] + 1) * weekW - 0.06;
        s.addShape(pptx.ShapeType.roundRect, { x, y: y + 0.06, w, h: 0.41, rectRadius: 0.02, fill: { color: lane[2], transparency: 8 }, line: { color: lane[2], transparency: 100 } });
        s.addText(seg[2], { x: x + 0.05, y: y + 0.18, w: w - 0.1, h: 0.16, fontFace: FONT, fontSize: 7.9, bold: true, color: C.white, align: 'center', margin: 0, fit: 'shrink' });
      });
    });
    const gates = [[2,'G1'],[4,'G2'],[6,'G3'],[9,'G4'],[13,'G5']];
    gates.forEach(g => {
      const x = weeksX + (g[0] - 0.5) * weekW;
      s.addShape(pptx.ShapeType.diamond, { x: x - 0.11, y: 6.38, w: 0.22, h: 0.22, fill: { color: C.navy }, line: { color: C.navy } });
      s.addText(g[1], { x: x - 0.25, y: 6.63, w: 0.5, h: 0.15, fontFace: FONT, fontSize: 7.8, bold: true, color: C.navy, align: 'center', margin: 0 });
    });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Readiness gates');
    addTitle(s, 'Every promotion is a decision supported by evidence', 'A red gate pauses only the affected persona or wave, not the entire program.');
    const gates = [
      ['G1', 'Scope', 'Owners, personas, top apps, data cohorts and exception criteria defined.', C.navy2],
      ['G2', 'Foundation', 'Canary baseline, GlobalProtect, OneDrive pilot and critical apps pass.', C.blue],
      ['G3', 'Champion pilot', '50-100 users productive; no unresolved severity 1/2 issue.', C.cyan],
      ['G4', 'Wave readiness', 'Required apps >=98%; conflicts <2%; support capacity ready.', C.teal],
      ['G5', 'Scale / handoff', 'Factory stable; exception population owned; forecast agreed.', C.purple]
    ];
    gates.forEach((g, i) => {
      const x = 0.66 + i * 2.52;
      s.addShape(pptx.ShapeType.diamond, { x: x + 0.78, y: 1.42, w: 0.75, h: 0.75, fill: { color: g[3] }, line: { color: g[3] } });
      s.addText(g[0], { x: x + 0.78, y: 1.69, w: 0.75, h: 0.18, fontFace: FONT, fontSize: 11, bold: true, align: 'center', color: C.white, margin: 0 });
      addCard(s, pptx, x, 2.48, 2.28, 3.25, g[1], g[2], { accent: g[3], fill: i % 2 ? C.white : C.pale, topBar: true, titleSize: 14, bodySize: 11 });
    });
    s.addShape(pptx.ShapeType.roundRect, { x: 1.05, y: 6.13, w: 11.22, h: 0.58, rectRadius: 0.04, fill: { color: C.paleAmber }, line: { color: C.paleAmber } });
    s.addText('Wave promotion rule: no unresolved data-loss condition, security control failure, or business-critical workflow blocker.', { x: 1.28, y: 6.31, w: 10.75, h: 0.19, fontFace: FONT, fontSize: 10.5, bold: true, color: '855610', align: 'center', margin: 0, fit: 'shrink' });
  }

  addSectionSlide(pptx, 3, 'Endpoint, data and application engineering', 'Transition existing devices without pretending there is a universal wipe-free policy reset.', C.purple);

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Intune transition');
    addTitle(s, 'There is no supported “clear all stale policy” operation', 'Build a controlled replacement process and reserve reset for defined exceptions.');
    const steps = [
      ['1', 'Inventory sources', 'Intune, GPO, ConfigMgr, security tools, scripts and image settings', C.navy2],
      ['2', 'Assign ownership', 'One authoritative setting owner; document intentional exclusions', C.blue],
      ['3', 'Unassign legacy', 'Canary scope; user sign-in, sync and restart where required', C.purple],
      ['4', 'Reverse tattooing', 'Explicitly remediate only confirmed persistent CSP settings', C.cyan],
      ['5', 'Validate effective state', 'MDM report, gpresult, registry, compliance and app behavior', C.teal],
      ['6', 'Promote or reset', 'Advance the ring or place device in the documented exception pool', C.green]
    ];
    steps.forEach((st, i) => {
      const x = 0.52 + i * 2.12;
      s.addShape(pptx.ShapeType.ellipse, { x: x + 0.65, y: 1.5, w: 0.64, h: 0.64, fill: { color: st[3] }, line: { color: st[3] } });
      s.addText(st[0], { x: x + 0.65, y: 1.72, w: 0.64, h: 0.18, fontFace: FONT, fontSize: 12, bold: true, color: C.white, align: 'center', margin: 0 });
      if (i < steps.length - 1) drawArrow(s, pptx, x + 1.47, 1.59, 0.4, C.line);
      addCard(s, pptx, x, 2.43, 1.94, 2.8, st[1], st[2], { accent: st[3], fill: i % 2 ? C.white : C.pale, titleSize: 12.5, bodySize: 9.5, topBar: false });
    });
    addCard(s, pptx, 0.72, 5.65, 5.8, 0.85, 'Do not do', 'Delete PolicyManager, enrollment, MDM or broad registry trees to “clean” a device.', { accent: C.red, fill: C.paleRed, topBar: false, titleSize: 11, bodySize: 9.5 });
    addCard(s, pptx, 6.82, 5.65, 5.8, 0.85, 'Reset exception', 'Use after failed controlled remediation or when device state cannot be trusted.', { accent: C.amber, fill: C.paleAmber, topBar: false, titleSize: 11, bodySize: 9.5 });
    addSourceLine(s, 'Microsoft Learn: Intune device-profile troubleshooting; Policy CSP ControlPolicyConflict; Windows Autopilot Reset.');
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'User data');
    addTitle(s, 'Pre-stage the filer data before breaking Folder Redirection', 'Migration Manager is the data movement plane; KFM is the final local-endpoint redirection.');
    const steps = [
      ['1', 'Inventory', 'Map users, size, file count, errors and ownership', C.navy2],
      ['2', 'Pre-provision', 'Create OneDrive libraries and migration mappings', C.blue],
      ['3', 'Pre-stage', 'Migration Manager copies into matching known folders', C.cyan],
      ['4', 'Reconcile', 'Counts, errors, deltas and business validation', C.teal],
      ['5', 'Cut over', 'Disable Folder Redirection; leave source content', C.amber],
      ['6', 'Enable KFM', 'Laptop takes the supported known-folder path', C.purple],
      ['7', 'Retain / retire', 'Read-only rollback window, archive and decommission', C.green]
    ];
    steps.forEach((st, i) => {
      const x = 0.47 + i * 1.81;
      s.addShape(pptx.ShapeType.ellipse, { x: x + 0.52, y: 1.45, w: 0.55, h: 0.55, fill: { color: st[3] }, line: { color: st[3] } });
      s.addText(st[0], { x: x + 0.52, y: 1.63, w: 0.55, h: 0.16, fontFace: FONT, fontSize: 10, bold: true, color: C.white, align: 'center', margin: 0 });
      if (i < steps.length - 1) drawArrow(s, pptx, x + 1.25, 1.5, 0.34, C.line);
      addCard(s, pptx, x, 2.22, 1.58, 2.46, st[1], st[2], { accent: st[3], fill: i % 2 ? C.white : C.pale, titleSize: 11.5, bodySize: 8.8, topBar: false });
    });
    addCard(s, pptx, 0.72, 5.08, 5.85, 1.18, 'Citrix coexistence', 'Keep filer access available during transition. Do not make OneDrive in Citrix a dependency until the persistent/non-persistent model and Server version are confirmed supported.', { accent: C.amber, fill: C.paleAmber, titleSize: 12, bodySize: 10 });
    addCard(s, pptx, 6.80, 5.08, 5.83, 1.18, 'FSLogix capacity', 'Validate IOPS, container growth, logon impact, backup behavior and VHD free-space thresholds - not capacity alone.', { accent: C.purple, fill: 'F1ECFA', titleSize: 12, bodySize: 10 });
    addSourceLine(s, 'Microsoft Learn: Redirect and move Windows known folders to OneDrive; Use the sync app on virtual desktops.');
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Application discovery');
    addTitle(s, 'Correlate four data sources; do not treat FSLogix as the app inventory', 'The output is a user-weighted packaging and exception backlog.');
    const srcs = [
      ['Gold image', 'HKLM uninstall data\nServices and drivers\nOffice / browser components', C.blue],
      ['Citrix Director', 'Published app launches\nUnique users and duration\nConcurrency and least-used apps', C.cyan],
      ['MDE telemetry', 'Actual process execution\nExecutable paths and signatures\nUser and host correlation', C.teal],
      ['FSLogix sample', 'HKCU installs and settings\nShortcuts and add-ins\nProfile-specific dependencies', C.purple]
    ];
    srcs.forEach((src, i) => {
      const x = 0.67 + i * 3.12;
      addCard(s, pptx, x, 1.45, 2.78, 2.68, src[0], src[1], { accent: src[3], fill: i % 2 ? C.white : C.pale, titleSize: 15, bodySize: 11 });
      drawArrow(s, pptx, x + 1.03, 4.3, 0.68, src[3]);
    });
    s.addShape(pptx.ShapeType.roundRect, { x: 1.05, y: 5.05, w: 11.2, h: 1.18, rectRadius: 0.05, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('Prioritized application backlog', { x: 1.35, y: 5.33, w: 3.0, h: 0.27, fontFace: FONT, fontSize: 16, bold: true, color: C.white, margin: 0 });
    s.addText('USER COUNT  x  ACTUAL USAGE  x  BUSINESS CRITICALITY  x  SECURITY RISK  x  PACKAGING EFFORT', { x: 4.15, y: 5.35, w: 7.55, h: 0.25, fontFace: FONT, fontSize: 11, bold: true, color: C.cyan, align: 'center', margin: 0, fit: 'shrink' });
    s.addText('FSLogix: sample 150-300 logged-off profiles; mount read-only; extract metadata only. Exclude content, credentials, tokens, browser history and caches.', { x: 1.4, y: 5.82, w: 10.6, h: 0.2, fontFace: FONT, fontSize: 9.3, color: 'D4DFE9', align: 'center', margin: 0, fit: 'shrink' });
    addSourceLine(s, 'Microsoft Learn: DeviceProcessEvents; Mount-DiskImage -Access ReadOnly. Citrix: application usage monitoring.');
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Rollout controls');
    addTitle(s, 'Use representative rings and a permanent hold path', 'The champion cohort must represent real workflows, locations, devices and application risk.');
    const rings = [
      ['LAB', '5-10 devices', 'Engineering validation', C.navy2, 1.8],
      ['IT CANARY', '20-30 devices', 'Five business days', C.blue, 2.2],
      ['CHAMPIONS', '50-100 users', 'Two or more business units', C.cyan, 2.7],
      ['WAVE 1', '250-400 users', 'Production evidence', C.teal, 3.2],
      ['BROAD', '300-500 / week', 'Scale while gates stay green', C.green, 3.7]
    ];
    rings.forEach((r, i) => {
      const x = 0.58 + i * 2.47;
      s.addShape(pptx.ShapeType.chevron, { x, y: 1.75, w: 2.25, h: 3.55, fill: { color: r[3], transparency: i === 0 ? 0 : 6 }, line: { color: C.white, width: 2 } });
      s.addText(r[0], { x: x + 0.2, y: 2.22, w: 1.64, h: 0.3, fontFace: FONT, fontSize: 14, bold: true, color: C.white, align: 'center', margin: 0, fit: 'shrink' });
      s.addText(r[1], { x: x + 0.2, y: 2.85, w: 1.64, h: 0.32, fontFace: FONT, fontSize: 16, bold: true, color: C.white, align: 'center', margin: 0, fit: 'shrink' });
      s.addText(r[2], { x: x + 0.18, y: 3.5, w: 1.64, h: 0.75, fontFace: FONT, fontSize: 10, color: C.white, align: 'center', margin: 0, fit: 'shrink', valign: 'mid' });
    });
    s.addShape(pptx.ShapeType.roundRect, { x: 0.9, y: 5.78, w: 11.5, h: 0.72, rectRadius: 0.04, fill: { color: C.paleAmber }, line: { color: C.amber, width: 1 } });
    s.addText('HOLD / EXCEPTION RING', { x: 1.22, y: 5.99, w: 2.2, h: 0.2, fontFace: FONT, fontSize: 11, bold: true, color: C.amber, margin: 0 });
    s.addText('Devices or users pause here without blocking healthy personas. Every item requires an owner, reason and next review date.', { x: 3.6, y: 5.98, w: 8.15, h: 0.23, fontFace: FONT, fontSize: 10.5, color: C.ink, margin: 0, fit: 'shrink' });
  }

  addSectionSlide(pptx, 4, 'AVD, ServiceNow and AI-enabled support', 'Use automation to remove repetitive handoffs while keeping endpoint actions explicit and auditable.', C.teal);

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'AVD exception service');
    addTitle(s, 'AVD is a governed placement decision, not the destination for every hard problem', 'Start with contractors, legacy dependencies and isolated-risk applications.');
    addCard(s, pptx, 0.72, 1.45, 3.65, 4.75, 'Entry criteria', [
      'Offshore or lower-trust contractor persona',
      'Legacy application cannot run locally',
      'Risky application needs network isolation',
      'Special dependency is time-bound',
      'Business owner accepts cost and limitations'
    ], { accent: C.purple, fill: 'F1ECFA', titleSize: 17, bodySize: 12 });
    drawArrow(s, pptx, 4.63, 3.35, 0.65, C.purple);
    addCard(s, pptx, 5.52, 1.45, 3.05, 4.75, 'Placement record', [
      'Persona and named owner',
      'Application and data access',
      'Host-pool isolation tier',
      'Peripheral and Teams needs',
      'Expected population and cost',
      'Expiry / modernization date'
    ], { accent: C.blue, fill: C.paleBlue, titleSize: 17, bodySize: 12 });
    drawArrow(s, pptx, 8.82, 3.35, 0.65, C.teal);
    addCard(s, pptx, 9.7, 1.45, 2.9, 4.75, 'Operating controls', [
      'Separate risky workloads',
      'Least-privilege connectivity',
      'MDE and Intune acceptance',
      'Teams media optimization',
      'Usage and cost monitoring',
      'Quarterly exception review'
    ], { accent: C.teal, fill: C.paleTeal, titleSize: 17, bodySize: 12 });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'ServiceNow MVP');
    addTitle(s, 'Automate three EUC workflows - and explicitly stop there', 'The objective is KTLO reduction, not a broad ServiceNow transformation.');
    addCard(s, pptx, 0.72, 1.45, 3.65, 3.72, '1  Structured intake', [
      'Replace the free-text form with a Record Producer',
      'Capture device, location, wave and symptom',
      'Auto-populate user and business context',
      'Confirm whether work can continue'
    ], { accent: C.blue, fill: C.paleBlue, titleSize: 16, bodySize: 11.5 });
    addCard(s, pptx, 4.83, 1.45, 3.65, 3.72, '2  Endpoint evidence', [
      'Look up user devices through the Intune spoke',
      'Attach last sync, compliance and app state',
      'Match known issues and active incidents',
      'Route with deterministic rules'
    ], { accent: C.teal, fill: C.paleTeal, titleSize: 16, bodySize: 11.5 });
    addCard(s, pptx, 8.94, 1.45, 3.65, 3.72, '3  Engineering escalation', [
      'Create ADO Bug only for real engineering work',
      'Link the ServiceNow incident and evidence',
      'Return status and resolution to the incident',
      'Preserve one user-facing SLA'
    ], { accent: C.purple, fill: 'F1ECFA', titleSize: 16, bodySize: 11.5 });
    s.addShape(pptx.ShapeType.roundRect, { x: 0.95, y: 5.55, w: 11.4, h: 0.78, rectRadius: 0.04, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('OUT OF SCOPE', { x: 1.24, y: 5.82, w: 1.25, h: 0.2, fontFace: FONT, fontSize: 10, bold: true, color: C.cyan, margin: 0 });
    s.addText('CMDB redesign  |  enterprise-wide workflow cleanup  |  autonomous remediation  |  free-form PowerShell  |  automatic closure', { x: 2.75, y: 5.81, w: 9.0, h: 0.22, fontFace: FONT, fontSize: 10.2, color: C.white, margin: 0, fit: 'shrink' });
    addSourceLine(s, 'ServiceNow: Record Producers; Microsoft Intune Spoke; Azure DevOps Boards Spoke.');
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'AI-assisted support');
    addTitle(s, 'AI improves intake and triage; deterministic controls own endpoint changes', 'Start read-only, measure quality, and add only allowlisted actions with approval.');
    // flow
    const flow = [
      ['User describes issue', C.navy2],
      ['AI asks focused questions', C.blue],
      ['Retrieve endpoint evidence', C.cyan],
      ['Search approved KB / known errors', C.teal],
      ['Resolve or create evidence-rich incident', C.purple]
    ];
    flow.forEach((f, i) => {
      const x = 0.55 + i * 2.52;
      s.addShape(pptx.ShapeType.roundRect, { x, y: 1.48, w: 2.14, h: 1.08, rectRadius: 0.04, fill: { color: f[1] }, line: { color: f[1] } });
      s.addText(f[0], { x: x + 0.18, y: 1.78, w: 1.78, h: 0.4, fontFace: FONT, fontSize: 11.2, bold: true, color: C.white, align: 'center', valign: 'mid', margin: 0, fit: 'shrink' });
      if (i < flow.length - 1) drawArrow(s, pptx, x + 2.19, 1.77, 0.25, C.line);
    });
    addCard(s, pptx, 0.72, 3.05, 5.78, 2.65, 'Allowed in the first 90 days', [
      'Questioning, classification and summarization',
      'Approved knowledge retrieval and safe guidance',
      'Related-incident and outage identification',
      'Draft escalation, response and resolution notes',
      'Managed-device sync only with approval and audit'
    ], { accent: C.teal, fill: C.paleTeal, titleSize: 15, bodySize: 11 });
    addCard(s, pptx, 6.82, 3.05, 5.78, 2.65, 'Prohibited or approval-gated', [
      'Delete, reset, retire or re-enroll devices',
      'Access approval or group-membership changes',
      'Free-form PowerShell or arbitrary Graph calls',
      'Use of credentials, tokens or profile content',
      'Automatic closure without validated outcome'
    ], { accent: C.red, fill: C.paleRed, titleSize: 15, bodySize: 11 });
    s.addText('Enable prompt-injection defenses, access tests, execution logs and human review before any agentic action.', { x: 1.1, y: 6.15, w: 11.1, h: 0.3, fontFace: FONT, fontSize: 10.5, bold: true, color: C.navy, align: 'center', margin: 0, fit: 'shrink' });
    addSourceLine(s, 'ServiceNow: Now Assist for ITSM; AI Agent Studio; Now Assist Guardian.');
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Work management');
    addTitle(s, 'Separate the user-support record from the engineering backlog', 'Integrate only at the escalation boundary to prevent duplicate work and status drift.');
    const cols = [
      ['SERVICENOW', 'User interaction\nIncident SLA\nApprovals and audit\nSupport ownership', C.teal, C.paleTeal],
      ['AZURE DEVOPS', 'Engineering backlog\nApps, policy and automation\nBlockers and readiness\nDelivery metrics', C.blue, C.paleBlue],
      ['CONFLUENCE', 'Published guidance\nRunbooks and FAQs\nArchitecture decisions\nTraining content', C.purple, 'F1ECFA']
    ];
    cols.forEach((c, i) => {
      const x = 0.72 + i * 4.1;
      s.addShape(pptx.ShapeType.roundRect, { x, y: 1.55, w: 3.65, h: 3.42, rectRadius: 0.06, fill: { color: c[3] }, line: { color: c[2], width: 1.2 } });
      s.addText(c[0], { x: x + 0.25, y: 1.88, w: 3.15, h: 0.29, fontFace: FONT, fontSize: 16, bold: true, color: c[2], align: 'center', margin: 0 });
      s.addShape(pptx.ShapeType.line, { x: x + 0.58, y: 2.42, w: 2.5, h: 0, line: { color: c[2], width: 1.5 } });
      s.addText(c[1], { x: x + 0.4, y: 2.72, w: 2.85, h: 1.6, fontFace: FONT, fontSize: 13, color: C.ink, align: 'center', valign: 'mid', margin: 0, breakLine: false, fit: 'shrink' });
    });
    s.addShape(pptx.ShapeType.roundRect, { x: 1.1, y: 5.48, w: 11.05, h: 0.78, rectRadius: 0.04, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('Integration rule', { x: 1.43, y: 5.73, w: 1.35, h: 0.2, fontFace: FONT, fontSize: 10.5, bold: true, color: C.cyan, margin: 0 });
    s.addText('Create an ADO work item only when engineering action is required; update the ServiceNow incident when engineering status changes.', { x: 3.0, y: 5.71, w: 8.6, h: 0.23, fontFace: FONT, fontSize: 10.3, color: C.white, margin: 0, fit: 'shrink' });
  }

  addSectionSlide(pptx, 5, 'Operating model, measures and next actions', 'Protect delivery capacity, make blockers visible and establish the day-30 throughput decision.', C.amber);

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Control dashboard');
    addTitle(s, 'Measure readiness, adoption and service quality - not activity volume', 'The scorecard should explain whether the next wave is safe.');
    const metrics = [
      ['Local-first adoption', '% users operating without Citrix; Citrix launches per user', C.blue],
      ['App readiness', 'User-weighted workflow coverage; required install success', C.cyan],
      ['Endpoint health', 'Compliance, policy conflicts, last check-in and VPN success', C.purple],
      ['Data quality', 'Migration errors, reconciliation and KFM success', C.teal],
      ['Support health', 'Incidents per 100 users, MTTR, reopen rate and aging', C.amber],
      ['Exception burn-down', 'Citrix / AVD population, owner, cost and expiry', C.red]
    ];
    metrics.forEach((m, i) => {
      const col = i % 3, row = Math.floor(i / 3);
      const x = 0.72 + col * 4.08, y = 1.45 + row * 2.38;
      addCard(s, pptx, x, y, 3.65, 1.95, m[0], m[1], { accent: m[2], fill: row === 0 ? C.pale : C.white, badge: String(i + 1), titleSize: 14, bodySize: 10.5 });
    });
    s.addShape(pptx.ShapeType.roundRect, { x: 1.35, y: 6.23, w: 10.65, h: 0.45, rectRadius: 0.03, fill: { color: C.paleBlue }, line: { color: C.paleBlue } });
    s.addText('One weekly scorecard: red conditions, owners, decisions required, and whether the next wave may proceed.', { x: 1.58, y: 6.37, w: 10.2, h: 0.17, fontFace: FONT, fontSize: 10.5, bold: true, color: C.blue, align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Delivery capacity');
    addTitle(s, 'Core team and accountability', 'Packaging capacity reduces; adoption, endpoint, data and automation capacity becomes critical.');
    const rows = [
      ['Product owner / EUC architect / AVD owner', 'A', 'Architecture, priorities, gates and exceptions', '1.0'],
      ['Change and wave lead', 'R', 'Champions, readiness, comms and BU coordination', '1.0'],
      ['Intune / endpoint engineer', 'R', 'Policy transition, rings and remediation', '1.0'],
      ['OneDrive / data engineer', 'R', 'Migration Manager, KFM and reconciliation', '1.0'],
      ['Automation engineer', 'R', 'ServiceNow, ADO, comms and evidence collection', '1.0'],
      ['Service desk / knowledge lead', 'R', 'L1/L2 runbooks, KB and issue patterns', '1.0'],
      ['Packaging engineer', 'C/R', 'Remaining packages, updates and exceptions', '0.5-1.0']
    ];
    // headers
    const xs = [0.72, 5.12, 6.12, 11.45], ws = [4.25, 0.8, 5.1, 0.85];
    ['ROLE', 'RACI', 'PRIMARY OUTCOME', 'FTE'].forEach((h, i) => {
      s.addShape(pptx.ShapeType.rect, { x: xs[i], y: 1.42, w: ws[i], h: 0.5, fill: { color: C.navy }, line: { color: C.white, width: 0.5 } });
      s.addText(h, { x: xs[i] + 0.12, y: 1.59, w: ws[i] - 0.24, h: 0.16, fontFace: FONT, fontSize: 8.8, bold: true, color: C.white, align: i === 1 || i === 3 ? 'center' : 'left', margin: 0 });
    });
    rows.forEach((r, ri) => {
      const y = 1.92 + ri * 0.63;
      const fill = ri % 2 ? C.white : C.pale;
      r.forEach((v, i) => {
        s.addShape(pptx.ShapeType.rect, { x: xs[i], y, w: ws[i], h: 0.63, fill: { color: fill }, line: { color: C.line, width: 0.5 } });
        s.addText(v, { x: xs[i] + 0.12, y: y + 0.18, w: ws[i] - 0.24, h: 0.25, fontFace: FONT, fontSize: i === 2 ? 9.2 : 9.8, bold: i === 0, color: i === 1 ? C.blue : C.ink, align: i === 1 || i === 3 ? 'center' : 'left', margin: 0, fit: 'shrink' });
      });
    });
    s.addText('Temporary surge: 2-4 hypercare analysts during broad deployment. Fractional named owners: network, security, identity, storage and application teams.', { x: 0.82, y: 6.55, w: 11.65, h: 0.3, fontFace: FONT, fontSize: 9.7, italic: true, color: C.gray, align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'First 10 business days');
    addTitle(s, 'Turn the plan into measurable evidence immediately', 'These activities establish the day-30 decision baseline.');
    const steps = [
      ['1', 'Confirm platform facts', 'Citrix persistence and exact Server versions; Entra / Intune state; licensing.', C.navy2],
      ['2', 'Export current state', 'Policy inventory, conflicts, devices, apps, Citrix usage and MDE activity.', C.blue],
      ['3', 'Define cohorts', 'Lab, IT canary, champions, production, hold and AVD exception groups.', C.cyan],
      ['4', 'Run data pilot', 'Pre-provision OneDrive; migrate and reconcile a representative filer cohort.', C.teal],
      ['5', 'Stand up support MVP', 'Structured intake, deterministic routing and read-only endpoint evidence.', C.purple],
      ['6', 'Lock the scorecard', 'Thresholds, owners, escalation process and the day-30 throughput decision.', C.amber]
    ];
    steps.forEach((st, i) => {
      const col = i % 2, row = Math.floor(i / 2);
      const x = 0.72 + col * 6.08, y = 1.38 + row * 1.65;
      addCard(s, pptx, x, y, 5.68, 1.37, st[1], st[2], { accent: st[3], fill: row % 2 ? C.white : C.pale, badge: st[0], titleSize: 14, bodySize: 9.8 });
    });
    s.addShape(pptx.ShapeType.roundRect, { x: 1.0, y: 6.42, w: 11.3, h: 0.45, rectRadius: 0.03, fill: { color: C.paleAmber }, line: { color: C.paleAmber } });
    s.addText('Open decision: is day 90 the full-estate deadline or the factory-plus-partial-migration milestone?', { x: 1.25, y: 6.56, w: 10.8, h: 0.17, fontFace: FONT, fontSize: 10.8, bold: true, color: '855610', align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = pptx.addSlide('CONTENT');
    addKicker(s, 'Appendix');
    addTitle(s, 'Sources and implementation references', 'Primary vendor guidance used to shape the plan; verify tenant-specific licensing and versions.');
    const refs = [
      ['Microsoft Intune', 'Profile removal / CSP tattooing', 'learn.microsoft.com/mem/intune/configuration/device-profile-troubleshoot'],
      ['Microsoft Windows', 'Policy conflict behavior', 'learn.microsoft.com/windows/client-management/mdm/policy-csp-controlpolicyconflict'],
      ['Microsoft Autopilot', 'Reset requirements and join limitations', 'learn.microsoft.com/autopilot/windows-autopilot-reset'],
      ['Microsoft OneDrive', 'KFM and network share transition', 'learn.microsoft.com/sharepoint/redirect-known-folders'],
      ['Microsoft OneDrive', 'Virtual desktop support', 'learn.microsoft.com/sharepoint/onedrive-in-citrix-virtual-apps-deployment-guide'],
      ['Microsoft Defender', 'DeviceProcessEvents telemetry', 'learn.microsoft.com/defender-xdr/advanced-hunting-deviceprocessevents-table'],
      ['Citrix Director', 'Application usage monitoring', 'docs.citrix.com/.../application-usage-monitoring.html'],
      ['ServiceNow', 'Record Producers and Workflow Studio', 'servicenow.com/docs - Record Producer / Service Catalog trigger'],
      ['ServiceNow', 'Microsoft Intune Spoke', 'servicenow.com/docs - Microsoft Intune Spoke'],
      ['ServiceNow', 'Now Assist and AI Agent Studio', 'servicenow.com/docs - Now Assist for ITSM / AI Agent Studio']
    ];
    refs.forEach((r, i) => {
      const col = i < 5 ? 0 : 1, row = i % 5;
      const x = 0.7 + col * 6.25, y = 1.38 + row * 1.02;
      s.addShape(pptx.ShapeType.roundRect, { x, y, w: 5.82, h: 0.82, rectRadius: 0.03, fill: { color: row % 2 ? C.white : C.pale }, line: { color: C.line, width: 0.7 } });
      s.addText(r[0], { x: x + 0.18, y: y + 0.14, w: 1.35, h: 0.18, fontFace: FONT, fontSize: 9, bold: true, color: C.blue, margin: 0, fit: 'shrink' });
      s.addText(r[1], { x: x + 1.55, y: y + 0.13, w: 3.9, h: 0.2, fontFace: FONT, fontSize: 9.4, bold: true, color: C.navy, margin: 0, fit: 'shrink' });
      s.addText(r[2], { x: x + 0.18, y: y + 0.47, w: 5.25, h: 0.16, fontFace: FONT, fontSize: 7.6, color: C.gray, margin: 0, fit: 'shrink' });
    });
    s.addText('Current-state automation accelerators are available in the workspace: Intune inventory, Endpoint Explorer, app triage, champion enrollment, phased rollout and AVD POC.', { x: 1.0, y: 6.58, w: 11.3, h: 0.24, fontFace: FONT, fontSize: 9.5, bold: true, color: C.navy, align: 'center', margin: 0, fit: 'shrink' });
  }

  return pptx.writeFile({ fileName: path.join(OUT, 'EUC-Transformation-Technical-Plan.pptx') });
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  await buildExecutiveDeck();
  await buildTechnicalDeck();
  console.log('Created PowerPoint decks in ' + OUT);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
