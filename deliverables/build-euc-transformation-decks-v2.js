const pptxgen = require(process.env.CODEX_PPTXGENJS_PATH || 'pptxgenjs');
const path = require('path');

const OUT = __dirname;
const pptxShape = {
  rect: 'rect', roundRect: 'roundRect', ellipse: 'ellipse', line: 'line',
  chevron: 'chevron', diamond: 'diamond'
};
const FONT = 'Aptos';

const C = {
  navy: '102A43', navy2: '243B53', ink: '17202A', blue: '246BFD', cyan: '16A6C9',
  teal: '0D9B87', green: '278F61', amber: 'E39B2E', red: 'D84E4B', purple: '6E5AC7',
  gray: '5D6B78', gray2: '8492A0', line: 'D9E2EA', pale: 'F5F7FA',
  paleBlue: 'EAF2FF', paleCyan: 'E8F8FC', paleTeal: 'E8F7F3', paleAmber: 'FFF4E0',
  paleRed: 'FCECEB', palePurple: 'F0EDFB', white: 'FFFFFF', black: '000000'
};

function deck(title, subject) {
  const p = new pptxgen();
  p.layout = 'LAYOUT_WIDE';
  p.author = 'EUC Transformation Program';
  p.company = 'Client';
  p.title = title;
  p.subject = subject;
  p.lang = 'en-US';
  p.theme = { headFontFace: FONT, bodyFontFace: FONT, lang: 'en-US' };
  p.defineSlideMaster({
    title: 'BASE', background: { color: C.white },
    objects: [
      { rect: { x: 0, y: 0, w: 13.333, h: 0.09, fill: { color: C.blue }, line: { color: C.blue } } },
      { text: { text: 'LOCAL-FIRST WORKPLACE PROGRAM', options: { x: 0.55, y: 7.16, w: 3.1, h: 0.14, fontFace: FONT, fontSize: 7.5, color: C.gray2, charSpacing: 1.2, margin: 0 } } }
    ],
    slideNumber: { x: 12.55, y: 7.13, w: 0.35, h: 0.16, fontFace: FONT, fontSize: 7.5, color: C.gray2, align: 'right', margin: 0 }
  });
  return p;
}

function title(slide, headline, sub = '') {
  slide.addText(headline, { x: 0.62, y: 0.37, w: 12.0, h: 0.53, fontFace: FONT, fontSize: 25, bold: true, color: C.navy, margin: 0, fit: 'shrink' });
  if (sub) slide.addText(sub, { x: 0.64, y: 0.94, w: 11.8, h: 0.32, fontFace: FONT, fontSize: 11.5, color: C.gray, margin: 0, fit: 'shrink' });
}

function eyebrow(slide, text) {
  slide.addText(text.toUpperCase(), { x: 0.62, y: 0.21, w: 4.5, h: 0.17, fontFace: FONT, fontSize: 8, bold: true, color: C.blue, charSpacing: 1.6, margin: 0 });
}

function source(slide, text) {
  slide.addText(text, { x: 0.66, y: 6.84, w: 11.75, h: 0.17, fontFace: FONT, fontSize: 7.2, italic: true, color: C.gray2, margin: 0, fit: 'shrink' });
}

function cover(p, label, headline, subtitle, meta, accent) {
  const s = p.addSlide();
  s.background = { color: C.navy };
  s.addShape(pptxShape.rect, { x: 0, y: 0, w: 0.16, h: 7.5, fill: { color: accent }, line: { color: accent } });
  s.addShape(pptxShape.ellipse, { x: 9.1, y: -1.35, w: 5.3, h: 5.3, fill: { color: C.navy2, transparency: 18 }, line: { color: accent, transparency: 72, width: 1.5 } });
  s.addShape(pptxShape.ellipse, { x: 10.45, y: 4.5, w: 3.5, h: 3.5, fill: { color: C.navy2, transparency: 26 }, line: { color: C.cyan, transparency: 70, width: 1.5 } });
  s.addText(label.toUpperCase(), { x: 0.78, y: 0.72, w: 6.4, h: 0.24, fontFace: FONT, fontSize: 9, bold: true, color: accent, charSpacing: 2.0, margin: 0 });
  s.addText(headline, { x: 0.75, y: 1.32, w: 8.7, h: 1.75, fontFace: FONT, fontSize: 37, bold: true, color: C.white, margin: 0, fit: 'shrink' });
  s.addText(subtitle, { x: 0.78, y: 3.48, w: 7.6, h: 1.0, fontFace: FONT, fontSize: 17, color: 'D9E4EE', margin: 0, fit: 'shrink' });
  s.addShape(pptxShape.roundRect, { x: 0.78, y: 5.23, w: 4.9, h: 0.5, rectRadius: 0.03, fill: { color: C.navy2 }, line: { color: '3D5871', width: 1 } });
  s.addText(meta, { x: 1.0, y: 5.38, w: 4.45, h: 0.17, fontFace: FONT, fontSize: 9.5, bold: true, color: C.white, margin: 0, fit: 'shrink' });
  s.addText('Prepared for working discussion | October 2026', { x: 0.78, y: 6.75, w: 5.5, h: 0.17, fontFace: FONT, fontSize: 8, color: '93A4B5', margin: 0 });
}

function section(p, number, headline, sub, accent) {
  const s = p.addSlide();
  s.background = { color: C.navy };
  s.addShape(pptxShape.rect, { x: 0, y: 0, w: 0.16, h: 7.5, fill: { color: accent }, line: { color: accent } });
  s.addText(String(number).padStart(2, '0'), { x: 0.8, y: 1.05, w: 1.0, h: 0.48, fontFace: FONT, fontSize: 24, bold: true, color: accent, margin: 0 });
  s.addText(headline, { x: 0.8, y: 1.78, w: 10.8, h: 0.95, fontFace: FONT, fontSize: 33, bold: true, color: C.white, margin: 0, fit: 'shrink' });
  s.addText(sub, { x: 0.82, y: 3.05, w: 9.4, h: 0.68, fontFace: FONT, fontSize: 16, color: 'CBD7E2', margin: 0, fit: 'shrink' });
  s.addShape(pptxShape.line, { x: 0.82, y: 4.22, w: 3.1, h: 0, line: { color: accent, width: 3 } });
  return s;
}

function pill(slide, text, x, y, w, fill, color = C.white) {
  slide.addShape(pptxShape.roundRect, { x, y, w, h: 0.34, rectRadius: 0.08, fill: { color: fill }, line: { color: fill } });
  slide.addText(text, { x: x + 0.09, y: y + 0.1, w: w - 0.18, h: 0.12, fontFace: FONT, fontSize: 8.2, bold: true, color, align: 'center', margin: 0, fit: 'shrink' });
}

function box(slide, x, y, w, h, headline, body, accent = C.blue, fill = C.white, opts = {}) {
  slide.addShape(pptxShape.roundRect, { x, y, w, h, rectRadius: 0.045, fill: { color: fill }, line: { color: opts.line || C.line, width: opts.lineWidth || 1 } });
  if (opts.bar !== false) slide.addShape(pptxShape.rect, { x, y, w, h: 0.06, fill: { color: accent }, line: { color: accent } });
  slide.addText(headline, { x: x + 0.22, y: y + 0.19, w: w - 0.44, h: 0.32, fontFace: FONT, fontSize: opts.titleSize || 13, bold: true, color: opts.titleColor || C.navy, margin: 0, fit: 'shrink' });
  if (Array.isArray(body)) {
    const runs = body.map((t, i) => ({ text: t, options: { bullet: { indent: 13 }, breakLine: i < body.length - 1 } }));
    slide.addText(runs, { x: x + 0.22, y: y + 0.68, w: w - 0.44, h: h - 0.86, fontFace: FONT, fontSize: opts.bodySize || 10.2, color: opts.bodyColor || C.ink, margin: 0.02, paraSpaceAfterPt: opts.para || 6, fit: 'shrink', valign: 'top' });
  } else {
    slide.addText(body, { x: x + 0.22, y: y + 0.66, w: w - 0.44, h: h - 0.84, fontFace: FONT, fontSize: opts.bodySize || 10.2, color: opts.bodyColor || C.ink, margin: 0.02, fit: 'shrink', valign: 'top' });
  }
}

function circleStep(slide, n, x, y, color, headline, detail, w = 1.65) {
  slide.addShape(pptxShape.ellipse, { x: x + w / 2 - 0.27, y, w: 0.54, h: 0.54, fill: { color }, line: { color } });
  slide.addText(String(n), { x: x + w / 2 - 0.27, y: y + 0.18, w: 0.54, h: 0.15, fontFace: FONT, fontSize: 10, bold: true, color: C.white, align: 'center', margin: 0 });
  slide.addText(headline, { x, y: y + 0.72, w, h: 0.32, fontFace: FONT, fontSize: 11.2, bold: true, color: C.navy, align: 'center', margin: 0, fit: 'shrink' });
  slide.addText(detail, { x, y: y + 1.12, w, h: 0.9, fontFace: FONT, fontSize: 8.8, color: C.gray, align: 'center', margin: 0, fit: 'shrink', valign: 'top' });
}

function arrow(slide, x, y, w, color = C.line) {
  slide.addShape(pptxShape.chevron, { x, y, w, h: 0.34, fill: { color }, line: { color } });
}

function labelValue(slide, x, y, w, label, value, color) {
  slide.addText(label.toUpperCase(), { x, y, w, h: 0.16, fontFace: FONT, fontSize: 7.7, bold: true, color: C.gray2, charSpacing: 1.0, margin: 0 });
  slide.addText(value, { x, y: y + 0.25, w, h: 0.42, fontFace: FONT, fontSize: 22, bold: true, color, margin: 0, fit: 'shrink' });
}

function addRow(slide, y, cols, widths, colors = {}) {
  let x = 0.68;
  cols.forEach((text, i) => {
    const fill = colors.fill || C.white;
    slide.addShape(pptxShape.rect, { x, y, w: widths[i], h: 0.58, fill: { color: fill }, line: { color: C.line, width: 0.6 } });
    slide.addText(text, { x: x + 0.11, y: y + 0.16, w: widths[i] - 0.22, h: 0.25, fontFace: FONT, fontSize: colors.size || 9.2, bold: colors.bold && i === 0, color: i === 0 && colors.firstColor ? colors.firstColor : C.ink, margin: 0, fit: 'shrink', align: colors.center && colors.center.includes(i) ? 'center' : 'left' });
    x += widths[i];
  });
}

// -----------------------------------------------------------------------------
// EXECUTIVE DECK
// -----------------------------------------------------------------------------

async function buildExecutive() {
  const p = deck('Moving Work Back to the Laptop', 'Leadership briefing for the 90-day Citrix exit program');
  cover(p, 'Leadership briefing', 'Moving Work Back to the Laptop', 'A practical 90-day plan to make Windows 11 the primary workplace and reduce Citrix dependency without disrupting the business.', '3,000 endpoints | Financial services | Draft for alignment', C.cyan);

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Why this is a program');
    title(s, 'We already own the laptops. The work still lives somewhere else.', 'The transformation is less about buying technology and more about moving work, data, habits and support to the endpoint.');
    const facts = [
      ['Windows 11 laptops', 'issued, but not the primary work surface', C.blue],
      ['Citrix', 'remains the place users trust to get work done', C.red],
      ['User data', 'is redirected to a filer, not protected through KFM', C.teal],
      ['Applications', 'were inherited from manually maintained gold images', C.amber],
      ['Support', 'is driven by free-text tickets and manual handoffs', C.purple]
    ];
    facts.forEach((f, i) => {
      const y = 1.47 + i * 0.89;
      s.addShape(pptxShape.ellipse, { x: 0.82, y: y + 0.08, w: 0.4, h: 0.4, fill: { color: f[2] }, line: { color: f[2] } });
      s.addText(f[0], { x: 1.5, y, w: 2.05, h: 0.25, fontFace: FONT, fontSize: 12.5, bold: true, color: C.navy, margin: 0 });
      s.addText(f[1], { x: 3.62, y, w: 4.2, h: 0.29, fontFace: FONT, fontSize: 11, color: C.gray, margin: 0, fit: 'shrink' });
    });
    s.addShape(pptxShape.roundRect, { x: 8.35, y: 1.47, w: 4.1, h: 4.36, rectRadius: 0.06, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('What happens if we treat this as a tool deployment?', { x: 8.72, y: 1.86, w: 3.36, h: 0.75, fontFace: FONT, fontSize: 19, bold: true, color: C.white, margin: 0, fit: 'shrink' });
    s.addText('Users keep Citrix as the fallback.\n\nThe new endpoint becomes another layer to support.\n\nTechnical teams absorb the migration through KTLO.\n\nThe exit date moves, but the operating model does not.', { x: 8.74, y: 2.92, w: 3.28, h: 2.35, fontFace: FONT, fontSize: 12.5, color: 'D6E0E9', margin: 0, fit: 'shrink' });
    s.addText('The real program outcome is confidence in the laptop.', { x: 8.72, y: 5.45, w: 3.3, h: 0.24, fontFace: FONT, fontSize: 11.5, bold: true, color: C.cyan, margin: 0, fit: 'shrink' });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Recommendation');
    title(s, 'Use three deliberate service paths—not one replacement platform', 'The goal is to reduce dependency, not to move every Citrix workload blindly into AVD.');
    const paths = [
      ['1', 'LOCAL WINDOWS 11', 'Default workplace', 'Employees run Teams, Office, browser, GlobalProtect and packaged business apps locally. User data follows through OneDrive KFM.', C.teal, C.paleTeal],
      ['2', 'AZURE VIRTUAL DESKTOP', 'Governed exception', 'Offshore contractors, legacy dependencies and isolated-risk applications receive a named, reviewable AVD placement.', C.purple, C.palePurple],
      ['3', 'CITRIX', 'Time-bound transition', 'Citrix remains available only while dependencies are being removed. Each exception has an owner and a retirement date.', C.amber, C.paleAmber]
    ];
    paths.forEach((r, i) => {
      const y = 1.47 + i * 1.68;
      s.addShape(pptxShape.roundRect, { x: 0.74, y, w: 11.86, h: 1.35, rectRadius: 0.05, fill: { color: r[5] }, line: { color: r[4], width: 1.1 } });
      s.addShape(pptxShape.ellipse, { x: 1.02, y: y + 0.38, w: 0.55, h: 0.55, fill: { color: r[4] }, line: { color: r[4] } });
      s.addText(r[0], { x: 1.02, y: y + 0.56, w: 0.55, h: 0.15, fontFace: FONT, fontSize: 10, bold: true, color: C.white, align: 'center', margin: 0 });
      s.addText(r[1], { x: 1.82, y: y + 0.27, w: 2.3, h: 0.24, fontFace: FONT, fontSize: 12, bold: true, color: r[4], margin: 0 });
      s.addText(r[2], { x: 1.82, y: y + 0.65, w: 2.3, h: 0.3, fontFace: FONT, fontSize: 15, bold: true, color: C.navy, margin: 0 });
      s.addShape(pptxShape.line, { x: 4.4, y: y + 0.25, w: 0, h: 0.85, line: { color: r[4], transparency: 45, width: 1.4 } });
      s.addText(r[3], { x: 4.72, y: y + 0.29, w: 7.35, h: 0.72, fontFace: FONT, fontSize: 11.7, color: C.ink, margin: 0, fit: 'shrink', valign: 'mid' });
    });
    s.addText('Policy statement for leaders: the laptop is the standard; virtual desktops require a documented reason.', { x: 1.0, y: 6.58, w: 11.25, h: 0.25, fontFace: FONT, fontSize: 11.5, bold: true, color: C.navy, align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, '90-day outcome');
    title(s, 'The first 90 days create a dependable migration engine', 'The program should promise evidence and repeatability first; the final completion rate follows from the day-30 results.');
    labelValue(s, 0.82, 1.55, 2.5, 'Production migration', '900–1,500 users', C.blue);
    labelValue(s, 3.58, 1.55, 2.4, 'Required apps', '≥98% success', C.teal);
    labelValue(s, 6.28, 1.55, 2.25, 'Policy health', '<2% conflict', C.purple);
    labelValue(s, 8.84, 1.55, 2.7, 'Exceptions', '100% owned', C.amber);
    s.addShape(pptxShape.line, { x: 0.82, y: 2.48, w: 10.95, h: 0, line: { color: C.line, width: 1.2 } });
    const outcomes = [
      ['Endpoint', 'A versioned Intune baseline, GlobalProtect and the critical app set are deployed through controlled rings.', C.blue],
      ['User data', 'Migration Manager and KFM are proven with reconciliation, rollback and source-retention steps.', C.teal],
      ['Business change', 'Champions validate real workflows and business units accept their own production wave.', C.cyan],
      ['Support', 'ServiceNow collects structured evidence and L1/L2 receive usable troubleshooting paths.', C.purple],
      ['Virtualization', 'The remaining population is assigned to AVD, held for remediation, or scheduled for Citrix retirement.', C.amber]
    ];
    outcomes.forEach((o, i) => {
      const col = i < 3 ? i : i - 3;
      const y = i < 3 ? 2.83 : 4.75;
      const x = i < 3 ? 0.75 + col * 4.08 : 2.8 + col * 4.08;
      box(s, x, y, 3.68, 1.55, o[0], o[1], o[2], i < 3 ? C.pale : C.white, { titleSize: 13.5, bodySize: 10.2 });
    });
    s.addText('Day 30 produces the first credible estimate for a full 3,000-user completion date.', { x: 3.32, y: 6.52, w: 6.7, h: 0.23, fontFace: FONT, fontSize: 10.8, bold: true, color: C.red, align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Delivery sequence');
    title(s, 'Start narrow, prove the path, then increase weekly volume', 'Each phase has a business outcome—not just a list of technology tasks.');
    const phases = [
      ['DAYS 1–15', 'Make the work visible', 'Named owners\nRepresentative champions\nCurrent-state inventory\nAgreed readiness gates', C.navy2],
      ['DAYS 16–30', 'Prove one complete path', 'GlobalProtect + apps\nIntune canary\nData migration pilot\nSupport intake MVP', C.blue],
      ['DAYS 31–45', 'Prove real user workflows', '50–100 champions\nTwo business units\nDaily issue review\nNo unresolved critical blocker', C.cyan],
      ['DAYS 46–65', 'Operate the factory', '250–400 users\nWave scorecard\nAutomated evidence\nBusiness acceptance', C.teal],
      ['DAYS 66–90', 'Scale what is working', '300–500 per week\nAVD placement\nException burn-down\nCompletion forecast', C.purple]
    ];
    phases.forEach((ph, i) => {
      const x = 0.52 + i * 2.54;
      s.addShape(pptxShape.roundRect, { x, y: 1.52, w: 2.28, h: 4.78, rectRadius: 0.04, fill: { color: C.white }, line: { color: C.line, width: 1 } });
      s.addShape(pptxShape.rect, { x, y: 1.52, w: 2.28, h: 0.57, fill: { color: ph[3] }, line: { color: ph[3] } });
      s.addText(ph[0], { x: x + 0.16, y: 1.72, w: 1.96, h: 0.17, fontFace: FONT, fontSize: 8.5, bold: true, color: C.white, align: 'center', margin: 0 });
      s.addText(ph[1], { x: x + 0.18, y: 2.36, w: 1.92, h: 0.75, fontFace: FONT, fontSize: 15, bold: true, color: C.navy, align: 'center', margin: 0, fit: 'shrink', valign: 'mid' });
      s.addText(ph[2], { x: x + 0.2, y: 3.42, w: 1.88, h: 1.85, fontFace: FONT, fontSize: 10.5, color: C.ink, align: 'center', margin: 0, fit: 'shrink' });
      if (i < phases.length - 1) arrow(s, x + 2.31, 3.63, 0.21, C.line);
    });
    s.addShape(pptxShape.roundRect, { x: 1.05, y: 6.45, w: 11.18, h: 0.42, rectRadius: 0.03, fill: { color: C.paleAmber }, line: { color: C.paleAmber } });
    s.addText('The day-30 gate determines the committed weekly migration rate.', { x: 1.35, y: 6.58, w: 10.55, h: 0.16, fontFace: FONT, fontSize: 10.5, bold: true, color: '875A13', align: 'center', margin: 0 });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Leadership job');
    title(s, 'Five decisions remove more risk than another month of engineering', 'Technical teams can build the path; leaders must make it the normal path.');
    const decisions = [
      ['1', 'Make local-first the policy', 'Citrix and AVD are exceptions with owners and review dates.', 'VP sponsor'],
      ['2', 'Name accountable business owners', 'Every business unit supplies champions and accepts its wave.', 'BU leaders'],
      ['3', 'Protect dedicated delivery capacity', 'Keep architecture and AVD ownership out of routine ticket choreography.', 'Program sponsor'],
      ['4', 'Approve reset and app-retirement rules', 'Do not let irrecoverable device state or unused apps stall the program.', 'Security + EUC'],
      ['5', 'Authorize bounded support automation', 'Use structured intake, endpoint evidence and AI assistance with clear guardrails.', 'ITSM + Risk']
    ];
    decisions.forEach((d, i) => {
      const y = 1.43 + i * 0.98;
      s.addShape(pptxShape.ellipse, { x: 0.8, y: y + 0.07, w: 0.48, h: 0.48, fill: { color: C.blue }, line: { color: C.blue } });
      s.addText(d[0], { x: 0.8, y: y + 0.22, w: 0.48, h: 0.15, fontFace: FONT, fontSize: 9.5, bold: true, color: C.white, align: 'center', margin: 0 });
      s.addText(d[1], { x: 1.55, y, w: 3.4, h: 0.27, fontFace: FONT, fontSize: 13, bold: true, color: C.navy, margin: 0, fit: 'shrink' });
      s.addText(d[2], { x: 1.55, y: y + 0.34, w: 7.2, h: 0.27, fontFace: FONT, fontSize: 10, color: C.gray, margin: 0, fit: 'shrink' });
      pill(s, d[3], 10.42, y + 0.08, 1.65, C.paleBlue, C.blue);
    });
    s.addText('Needed within 10 business days', { x: 4.7, y: 6.5, w: 3.9, h: 0.27, fontFace: FONT, fontSize: 13, bold: true, color: C.red, align: 'center', margin: 0 });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Capacity and control');
    title(s, 'The bottleneck is coordination and support—not packaging volume', 'Packaging is nearly complete. The resource plan should now protect delivery from KTLO.');
    s.addShape(pptxShape.roundRect, { x: 0.72, y: 1.42, w: 4.05, h: 4.85, rectRadius: 0.06, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('Current concentration risk', { x: 1.04, y: 1.79, w: 2.7, h: 0.26, fontFace: FONT, fontSize: 11, bold: true, color: C.cyan, margin: 0 });
    s.addText('One role currently owns product direction, EUC architecture, AVD delivery and escalation.', { x: 1.02, y: 2.28, w: 3.45, h: 1.35, fontFace: FONT, fontSize: 21, bold: true, color: C.white, margin: 0, fit: 'shrink' });
    s.addText('That is workable for design. It is not workable for a multi-wave migration with weak L1/L2 support.', { x: 1.05, y: 4.18, w: 3.3, h: 0.9, fontFace: FONT, fontSize: 13, color: 'D7E1EA', margin: 0, fit: 'shrink' });
    s.addText('Recommendation: 5–6 core resources + temporary hypercare', { x: 1.04, y: 5.61, w: 3.35, h: 0.35, fontFace: FONT, fontSize: 12, bold: true, color: C.white, margin: 0, fit: 'shrink' });
    const roles = [
      ['Change / wave lead', '1.0', C.blue], ['Intune / endpoint engineer', '1.0', C.purple],
      ['OneDrive / data engineer', '1.0', C.teal], ['Automation engineer', '1.0', C.cyan],
      ['Service desk / knowledge lead', '1.0', C.amber], ['Packaging maintenance', '0.5–1.0', C.gray]
    ];
    roles.forEach((r, i) => {
      const y = 1.46 + i * 0.78;
      s.addShape(pptxShape.roundRect, { x: 5.18, y, w: 7.12, h: 0.58, rectRadius: 0.025, fill: { color: i % 2 ? C.white : C.pale }, line: { color: C.line, width: 0.7 } });
      s.addShape(pptxShape.rect, { x: 5.18, y, w: 0.08, h: 0.58, fill: { color: r[2] }, line: { color: r[2] } });
      s.addText(r[0], { x: 5.52, y: y + 0.18, w: 4.7, h: 0.2, fontFace: FONT, fontSize: 11.2, bold: true, color: C.navy, margin: 0 });
      s.addText(r[1], { x: 10.72, y: y + 0.17, w: 1.1, h: 0.2, fontFace: FONT, fontSize: 11, bold: true, color: r[2], align: 'right', margin: 0 });
    });
    s.addText('Add 2–4 temporary hypercare analysts during broad deployment.', { x: 6.05, y: 6.35, w: 5.4, h: 0.22, fontFace: FONT, fontSize: 10, italic: true, color: C.gray, align: 'center', margin: 0 });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'What leaders will see');
    title(s, 'A weekly scorecard that answers one question: is the next wave safe?', 'Reporting should expose decisions, not drown leadership in delivery activity.');
    const metrics = [
      ['Adoption', 'Users working locally; Citrix launches per user', C.blue],
      ['Applications', 'Workflow coverage; required app install success', C.cyan],
      ['Endpoint health', 'Compliance, policy conflicts, VPN success', C.purple],
      ['User data', 'Migration errors, reconciliation, KFM health', C.teal],
      ['Support', 'Incidents per 100 users, MTTR, aging, repeat issues', C.amber],
      ['Exceptions', 'Population, owner, reason, cost and next review', C.red]
    ];
    metrics.forEach((m, i) => {
      const x = 0.72 + (i % 3) * 4.08, y = 1.46 + Math.floor(i / 3) * 2.05;
      box(s, x, y, 3.66, 1.65, m[0], m[1], m[2], Math.floor(i / 3) ? C.white : C.pale, { titleSize: 14, bodySize: 10.5 });
    });
    s.addShape(pptxShape.roundRect, { x: 0.92, y: 5.82, w: 11.48, h: 0.65, rectRadius: 0.04, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('Weekly decision line', { x: 1.22, y: 6.03, w: 1.75, h: 0.2, fontFace: FONT, fontSize: 10, bold: true, color: C.cyan, margin: 0 });
    s.addText('Proceed | proceed with exclusions | pause the affected persona | escalate a decision', { x: 3.18, y: 6.02, w: 8.55, h: 0.22, fontFace: FONT, fontSize: 11, bold: true, color: C.white, align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Immediate action');
    title(s, 'Use the next 10 business days to make the plan measurable', 'The first output is not a mass deployment—it is a complete, observable migration path.');
    const actions = [
      ['1', 'Confirm sponsor and owners', 'Approve local-first, AVD exception rules and business accountability.', C.blue],
      ['2', 'Baseline the estate', 'Export Intune policies, device health, app inventory, Director usage and MDE process evidence.', C.purple],
      ['3', 'Select representative cohorts', '20–30 IT canaries and 50–100 champions across real business workflows.', C.cyan],
      ['4', 'Run the first data pilot', 'Pre-provision OneDrive; scan, pre-stage, reconcile and cut over a small filer cohort.', C.teal],
      ['5', 'Launch the support MVP', 'Structured ServiceNow intake, read-only endpoint evidence and L1/L2 knowledge.', C.amber],
      ['6', 'Set the day-30 decision', 'Commit the production rate only when the end-to-end path is proven.', C.green]
    ];
    actions.forEach((a, i) => {
      const x = 0.72 + (i % 2) * 6.08, y = 1.42 + Math.floor(i / 2) * 1.68;
      s.addShape(pptxShape.roundRect, { x, y, w: 5.68, h: 1.38, rectRadius: 0.04, fill: { color: Math.floor(i / 2) % 2 ? C.white : C.pale }, line: { color: C.line, width: 0.8 } });
      s.addShape(pptxShape.ellipse, { x: x + 0.25, y: y + 0.37, w: 0.55, h: 0.55, fill: { color: a[3] }, line: { color: a[3] } });
      s.addText(a[0], { x: x + 0.25, y: y + 0.55, w: 0.55, h: 0.15, fontFace: FONT, fontSize: 10, bold: true, color: C.white, align: 'center', margin: 0 });
      s.addText(a[1], { x: x + 1.03, y: y + 0.27, w: 4.2, h: 0.27, fontFace: FONT, fontSize: 13.2, bold: true, color: C.navy, margin: 0, fit: 'shrink' });
      s.addText(a[2], { x: x + 1.03, y: y + 0.68, w: 4.28, h: 0.45, fontFace: FONT, fontSize: 9.7, color: C.gray, margin: 0, fit: 'shrink' });
    });
    s.addText('Leadership clarification still required: is day 90 the full-estate deadline, or the factory-plus-partial-migration milestone?', { x: 1.0, y: 6.52, w: 11.3, h: 0.24, fontFace: FONT, fontSize: 10.4, bold: true, color: C.red, align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Appendix');
    title(s, 'Planning assumptions to confirm in mobilization', 'The day-30 rate depends on these facts, not on a generic endpoint migration benchmark.');
    box(s, 0.72, 1.42, 5.82, 4.95, 'Known today', [
      'Approximately 3,000 primarily Windows 11 laptops',
      'Endpoints are Microsoft Entra joined and Intune managed',
      'MDE is deployed to laptops and Citrix hosts',
      'Citrix Director is available for application usage',
      'Packaging is substantially complete',
      'SharePoint Migration Manager is the planned data tool',
      'AVD build is underway for contractors and legacy workloads'
    ], C.blue, C.paleBlue, { titleSize: 16, bodySize: 11.3 });
    box(s, 6.8, 1.42, 5.82, 4.95, 'Must be confirmed', [
      'Exact Citrix Server versions and persistent/non-persistent model',
      'Day-90 completion expectation',
      'Filer cohort sizes, exceptions and source-retention period',
      'Business-critical peripherals and smart-card dependencies',
      'Teams/Webex coexistence and retirement dates',
      'ServiceNow IntegrationHub and Now Assist licensing',
      'Temporary hypercare and business-owner availability'
    ], C.amber, C.paleAmber, { titleSize: 16, bodySize: 11.3 });
  }

  await p.writeFile({ fileName: path.join(OUT, 'EUC-Transformation-Leadership-Briefing-v2.pptx') });
}

// -----------------------------------------------------------------------------
// TECHNICAL DECK
// -----------------------------------------------------------------------------

async function buildTechnical() {
  const p = deck('Local-First Workplace Technical Implementation Plan', 'Technical implementation blueprint for endpoint, data, applications, AVD, ServiceNow and support');
  cover(p, 'Technical implementation blueprint', 'Building the Local-First Workplace', 'The engineering plan, readiness controls and operating model required to move users from Citrix to Windows 11 safely.', '3,000 endpoints | Entra + Intune | Working architecture', C.blue);

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Scope and facts');
    title(s, 'Start with what is known—and make the unknowns explicit', 'These assumptions drive the technical sequence and must be resolved before broad deployment.');
    box(s, 0.72, 1.43, 5.78, 4.95, 'Confirmed inputs', [
      'Endpoints: Microsoft Entra joined Windows 11 laptops',
      'Management: Intune with a new policy set already built',
      'Security: MDE deployed to laptops and Citrix hosts',
      'Applications: packaging nearly complete; Citrix gold image was manually maintained',
      'Data: filer inventory exists; SharePoint Migration Manager is planned',
      'Telemetry: Citrix Director and MDE are available',
      'AVD: build in progress; initial populations are contractors and legacy/risky apps'
    ], C.blue, C.paleBlue, { titleSize: 16, bodySize: 11.2 });
    box(s, 6.82, 1.43, 5.78, 4.95, 'Blocking decisions / validation', [
      'Exact Citrix Server versions: 2019, 2022 or 2025',
      'Persistent versus non-persistent Citrix desktops',
      'Whether OneDrive must run inside Citrix at all',
      'Day-90 target: full estate or proven factory plus partial migration',
      'Teams/Webex migration dates and telephony scope',
      'AVD placement and approval criteria',
      'ServiceNow IntegrationHub / Now Assist entitlements'
    ], C.amber, C.paleAmber, { titleSize: 16, bodySize: 11.2 });
    source(s, 'Planning note: OneDrive support in Citrix depends on the desktop persistence model, operating system and current Microsoft support matrix.');
  }

  section(p, 1, 'Target service and migration factory', 'Build one repeatable path from readiness assessment to local-first acceptance; route only justified exceptions to AVD.', C.cyan);

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Target architecture');
    title(s, 'The laptop becomes the primary execution and data plane', 'Identity, compliance and application need decide whether a user stays local or receives a governed virtual exception.');
    // Identity and control plane
    s.addShape(pptxShape.roundRect, { x: 0.6, y: 1.45, w: 12.1, h: 0.78, rectRadius: 0.04, fill: { color: C.navy }, line: { color: C.navy } });
    const controls = [['Microsoft Entra ID', C.blue], ['Conditional Access', C.purple], ['Microsoft Intune', C.cyan], ['Microsoft Defender', C.teal], ['ServiceNow / ADO', C.amber]];
    controls.forEach((c, i) => pill(s, c[0], 0.92 + i * 2.32, 1.67, 2.0, c[1]));
    s.addText('IDENTITY, POLICY, SECURITY AND DELIVERY CONTROL PLANE', { x: 4.0, y: 1.2, w: 5.3, h: 0.17, fontFace: FONT, fontSize: 8, bold: true, color: C.gray2, charSpacing: 1.2, align: 'center', margin: 0 });
    // Personas
    s.addShape(pptxShape.roundRect, { x: 0.7, y: 2.8, w: 2.0, h: 2.78, rectRadius: 0.05, fill: { color: C.pale }, line: { color: C.line } });
    s.addText('USER PERSONAS', { x: 1.0, y: 3.1, w: 1.4, h: 0.18, fontFace: FONT, fontSize: 9, bold: true, color: C.gray, align: 'center', margin: 0 });
    s.addText('Employees\nRemote users\nOffshore contractors\nLegacy app users\nPrivileged / high-risk users', { x: 0.97, y: 3.55, w: 1.45, h: 1.45, fontFace: FONT, fontSize: 12.5, bold: true, color: C.navy, align: 'center', margin: 0, fit: 'shrink' });
    arrow(s, 2.9, 3.92, 0.55, C.blue);
    // decision
    s.addShape(pptxShape.diamond, { x: 3.73, y: 3.12, w: 2.18, h: 2.18, fill: { color: C.paleBlue }, line: { color: C.blue, width: 1.4 } });
    s.addText('READY FOR\nLOCAL WORK?', { x: 4.16, y: 3.84, w: 1.32, h: 0.55, fontFace: FONT, fontSize: 12.5, bold: true, color: C.blue, align: 'center', margin: 0, fit: 'shrink' });
    // local
    arrow(s, 6.15, 3.03, 0.45, C.teal);
    s.addShape(pptxShape.roundRect, { x: 6.83, y: 2.6, w: 5.1, h: 1.45, rectRadius: 0.05, fill: { color: C.paleTeal }, line: { color: C.teal, width: 1.2 } });
    s.addText('LOCAL WINDOWS 11 — DEFAULT', { x: 7.1, y: 2.9, w: 4.5, h: 0.24, fontFace: FONT, fontSize: 14, bold: true, color: C.teal, margin: 0 });
    s.addText('GlobalProtect | Teams | Office | Intune apps | OneDrive KFM | MDE', { x: 7.1, y: 3.38, w: 4.5, h: 0.2, fontFace: FONT, fontSize: 10.5, color: C.ink, margin: 0, fit: 'shrink' });
    // AVD
    arrow(s, 6.15, 4.58, 0.45, C.purple);
    s.addShape(pptxShape.roundRect, { x: 6.83, y: 4.33, w: 5.1, h: 1.45, rectRadius: 0.05, fill: { color: C.palePurple }, line: { color: C.purple, width: 1.2 } });
    s.addText('AZURE VIRTUAL DESKTOP — EXCEPTION', { x: 7.1, y: 4.63, w: 4.5, h: 0.24, fontFace: FONT, fontSize: 14, bold: true, color: C.purple, margin: 0 });
    s.addText('Contractors | legacy dependencies | isolated risky apps | time-bound access', { x: 7.1, y: 5.11, w: 4.5, h: 0.2, fontFace: FONT, fontSize: 10.5, color: C.ink, margin: 0, fit: 'shrink' });
    s.addText('Citrix remains a controlled fallback during transition—not a fourth steady-state architecture.', { x: 2.2, y: 6.36, w: 8.9, h: 0.24, fontFace: FONT, fontSize: 10.8, bold: true, color: C.red, align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Migration factory');
    title(s, 'Every user follows the same six-stage migration loop', 'The factory separates readiness work from wave execution and routes exceptions without stopping healthy users.');
    const stages = [
      ['1', 'Discover', 'Persona, apps, data, device, location', C.navy2],
      ['2', 'Remediate', 'Package gaps, policy conflicts, data errors', C.blue],
      ['3', 'Validate', 'Champion proves real business workflow', C.cyan],
      ['4', 'Migrate', 'Data cutover, local enablement, comms', C.teal],
      ['5', 'Stabilize', 'Hypercare, telemetry, issue burn-down', C.green],
      ['6', 'Accept', 'BU sign-off or named AVD / hold exception', C.purple]
    ];
    stages.forEach((st, i) => {
      const x = 0.42 + i * 2.12;
      circleStep(s, st[0], x, 1.5, st[3], st[1], st[2], 1.78);
      if (i < stages.length - 1) arrow(s, x + 1.8, 1.61, 0.25, C.line);
    });
    s.addShape(pptxShape.roundRect, { x: 0.8, y: 4.28, w: 11.75, h: 1.37, rectRadius: 0.05, fill: { color: C.pale }, line: { color: C.line } });
    const gates = [['Endpoint', 'Entra / Intune / MDE / BitLocker / GlobalProtect'], ['Applications', 'Required apps + workflow validation'], ['Data', 'Migration report clean + KFM healthy'], ['Support', 'Roster, comms, KB and incident route ready']];
    gates.forEach((g, i) => {
      const x = 1.08 + i * 2.86;
      s.addText(g[0], { x, y: 4.58, w: 1.2, h: 0.2, fontFace: FONT, fontSize: 11, bold: true, color: [C.blue, C.cyan, C.teal, C.amber][i], margin: 0 });
      s.addText(g[1], { x, y: 4.92, w: 2.45, h: 0.43, fontFace: FONT, fontSize: 8.8, color: C.gray, margin: 0, fit: 'shrink' });
    });
    s.addText('Promotion rule: all four readiness domains must be green; amber requires an explicit exclusion or owner.', { x: 1.15, y: 6.08, w: 11.05, h: 0.28, fontFace: FONT, fontSize: 11.3, bold: true, color: C.navy, align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, '90-day workplan');
    title(s, 'The first six weeks prove the path; the remaining seven weeks scale it', 'Deliverables are organized by workstream and decision gate.');
    const headers = ['Workstream', 'Days 1–15', 'Days 16–30', 'Days 31–45', 'Days 46–65', 'Days 66–90'];
    const widths = [2.05, 2.08, 2.08, 2.08, 2.08, 2.08];
    let x = 0.48;
    headers.forEach((h, i) => {
      s.addShape(pptxShape.rect, { x, y: 1.4, w: widths[i], h: 0.55, fill: { color: i === 0 ? C.navy : [C.navy2, C.blue, C.cyan, C.teal, C.purple][i - 1] }, line: { color: C.white, width: 0.6 } });
      s.addText(h, { x: x + 0.08, y: 1.59, w: widths[i] - 0.16, h: 0.17, fontFace: FONT, fontSize: 8.2, bold: true, color: C.white, align: 'center', margin: 0, fit: 'shrink' });
      x += widths[i];
    });
    const rows = [
      ['Endpoint', 'Policy/source map\nDevice cohorts', 'Canary baseline\nGlobalProtect', 'Champion promotion\nTattoo remediation', 'Wave health\nException pool', 'Scale + operational handoff'],
      ['User data', 'Mapping manifest\nPre-provision', 'Scan + pilot\nReconciliation', 'Champion pre-stage\nKFM cutover', 'Wave deltas\nRollback retention', 'Scale + retire source cohorts'],
      ['Applications', 'Usage correlation\nOwner validation', 'Critical app closure\nDetection tests', 'Workflow validation\nGap burn-down', 'Demand-driven fixes', 'Exception / retirement closure'],
      ['Teams / AVD', 'Personas\nNetwork readiness', 'Teams + AVD pilot', 'Contractor / legacy test', 'Exception service live', 'Placement review + cost'],
      ['Support / change', 'Champions\nRecord Producer', 'Evidence lookup\nComms pilot', 'Daily hypercare\nKB feedback', 'L1/L2 playbook\nWave office hours', 'Steady-state support handoff']
    ];
    rows.forEach((r, ri) => {
      let xx = 0.48, y = 1.95 + ri * 0.89;
      r.forEach((cell, ci) => {
        const fill = ci === 0 ? C.paleBlue : (ri % 2 ? C.white : C.pale);
        s.addShape(pptxShape.rect, { x: xx, y, w: widths[ci], h: 0.89, fill: { color: fill }, line: { color: C.line, width: 0.6 } });
        s.addText(cell, { x: xx + 0.09, y: y + 0.18, w: widths[ci] - 0.18, h: 0.51, fontFace: FONT, fontSize: ci === 0 ? 9.4 : 8.4, bold: ci === 0, color: ci === 0 ? C.navy : C.ink, align: ci === 0 ? 'left' : 'center', margin: 0, fit: 'shrink' });
        xx += widths[ci];
      });
    });
    s.addText('Gate 1: scope', { x: 2.42, y: 6.56, w: 1.5, h: 0.18, fontFace: FONT, fontSize: 8.2, bold: true, color: C.navy2, align: 'center', margin: 0 });
    s.addText('Gate 2: foundation', { x: 4.46, y: 6.56, w: 1.6, h: 0.18, fontFace: FONT, fontSize: 8.2, bold: true, color: C.blue, align: 'center', margin: 0 });
    s.addText('Gate 3: champion', { x: 6.58, y: 6.56, w: 1.5, h: 0.18, fontFace: FONT, fontSize: 8.2, bold: true, color: C.cyan, align: 'center', margin: 0 });
    s.addText('Gate 4: wave', { x: 8.66, y: 6.56, w: 1.5, h: 0.18, fontFace: FONT, fontSize: 8.2, bold: true, color: C.teal, align: 'center', margin: 0 });
    s.addText('Gate 5: scale', { x: 10.74, y: 6.56, w: 1.5, h: 0.18, fontFace: FONT, fontSize: 8.2, bold: true, color: C.purple, align: 'center', margin: 0 });
  }

  section(p, 2, 'Endpoint state transition', 'Move existing devices to the new baseline through evidence, explicit reversals and controlled exceptions—not registry deletion.', C.purple);

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Intune transition runbook');
    title(s, 'Replace policy in layers and prove the effective state at each step', 'Some CSP settings reverse when unassigned; others persist. The workflow must accommodate both behaviors.');
    const steps = [
      ['1', 'Freeze', 'Allow only approved break-fix changes to legacy policy.', C.navy2],
      ['2', 'Export', 'Policies, assignments, filters, overlaps and endpoint-security profiles.', C.blue],
      ['3', 'Map', 'Desired / duplicate / deprecated / unknown / tattoo-prone.', C.purple],
      ['4', 'Unassign', 'Canary only; require Entra sign-in, Intune sync and restart.', C.cyan],
      ['5', 'Measure', 'MDM diagnostics, gpresult, registry, compliance and user workflow.', C.teal],
      ['6', 'Reverse', 'Targeted remediation only for confirmed persistent state.', C.amber],
      ['7', 'Apply vNext', 'Assign the new baseline; validate effective configuration.', C.green],
      ['8', 'Promote / reset', 'Advance the ring or enter the documented reset pool.', C.red]
    ];
    steps.forEach((st, i) => {
      const x = 0.33 + i * 1.59;
      circleStep(s, st[0], x, 1.45, st[3], st[1], st[2], 1.34);
      if (i < steps.length - 1) arrow(s, x + 1.35, 1.56, 0.18, C.line);
    });
    s.addShape(pptxShape.roundRect, { x: 0.72, y: 4.2, w: 5.75, h: 1.55, rectRadius: 0.05, fill: { color: C.paleBlue }, line: { color: C.blue, width: 1 } });
    s.addText('Evidence collected on canary devices', { x: 1.0, y: 4.48, w: 2.85, h: 0.24, fontFace: FONT, fontSize: 13, bold: true, color: C.blue, margin: 0 });
    s.addText('Intune policy status | MDM diagnostic report | gpresult | local policy source | compliance | MDE state | required app behavior', { x: 1.0, y: 4.95, w: 5.18, h: 0.48, fontFace: FONT, fontSize: 9.7, color: C.ink, margin: 0, fit: 'shrink' });
    s.addShape(pptxShape.roundRect, { x: 6.8, y: 4.2, w: 5.8, h: 1.55, rectRadius: 0.05, fill: { color: C.paleRed }, line: { color: C.red, width: 1 } });
    s.addText('Never use as a generic cleanup', { x: 7.08, y: 4.48, w: 2.9, h: 0.24, fontFace: FONT, fontSize: 13, bold: true, color: C.red, margin: 0 });
    s.addText('Do not delete PolicyManager, MDM enrollment, broad registry trees or security configuration to simulate a reset.', { x: 7.08, y: 4.95, w: 5.18, h: 0.48, fontFace: FONT, fontSize: 9.7, color: C.ink, margin: 0, fit: 'shrink' });
    source(s, 'Microsoft Learn: Questions with policies and profiles in Intune; Policy CSP ControlPolicyConflict; Windows Autopilot Reset.');
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Device readiness contract');
    title(s, 'A device enters a production wave only when five domains are green', 'This contract becomes the same checklist for engineering, the champion, ServiceNow and wave reporting.');
    const cols = [2.4, 2.85, 2.85, 2.85];
    const headers = ['Domain', 'Green — migrate', 'Amber — owner required', 'Red — hold / remediate'];
    let x = 0.68;
    headers.forEach((h, i) => {
      s.addShape(pptxShape.rect, { x, y: 1.4, w: cols[i], h: 0.52, fill: { color: [C.navy, C.green, C.amber, C.red][i] }, line: { color: C.white, width: 0.6 } });
      s.addText(h, { x: x + 0.08, y: 1.57, w: cols[i] - 0.16, h: 0.18, fontFace: FONT, fontSize: 8.5, bold: true, color: C.white, align: 'center', margin: 0, fit: 'shrink' });
      x += cols[i];
    });
    const rows = [
      ['Identity & management', 'Entra joined; Intune check-in <24h; primary user known', 'Check-in 24–72h or shared-device exception', 'Not enrolled; duplicate identity; ownership unknown'],
      ['Security', 'MDE active; BitLocker escrowed; compliant', 'Approved temporary compliance exception', 'MDE inactive; encryption/key issue; critical control absent'],
      ['Connectivity', 'GlobalProtect installed; portal and required resources validated', 'Known nonblocking resource gap with owner', 'Cannot authenticate or reach critical resource'],
      ['Applications', 'Core app set installed; champion workflow passes', 'Noncritical app pending with documented workaround', 'Business-critical workflow blocked'],
      ['User data & support', 'OneDrive ready; migration clean; KFM healthy; support route ready', 'Minor migration exceptions reconciled', 'Unreconciled data; KFM failure; no rollback path']
    ];
    rows.forEach((r, ri) => {
      let xx = 0.68, y = 1.92 + ri * 0.83;
      r.forEach((cell, ci) => {
        s.addShape(pptxShape.rect, { x: xx, y, w: cols[ci], h: 0.83, fill: { color: ri % 2 ? C.white : C.pale }, line: { color: C.line, width: 0.6 } });
        s.addText(cell, { x: xx + 0.1, y: y + 0.14, w: cols[ci] - 0.2, h: 0.52, fontFace: FONT, fontSize: ci === 0 ? 9.3 : 8.3, bold: ci === 0, color: ci === 0 ? C.navy : C.ink, align: ci === 0 ? 'left' : 'center', margin: 0, fit: 'shrink' });
        xx += cols[ci];
      });
    });
    s.addText('Reset exception: two failed controlled remediation attempts, untrusted policy provenance, or an unresolved security control failure.', { x: 1.05, y: 6.35, w: 11.2, h: 0.28, fontFace: FONT, fontSize: 10.5, bold: true, color: C.red, align: 'center', margin: 0, fit: 'shrink' });
  }

  section(p, 3, 'User data and application readiness', 'Move data server-side, validate supported OneDrive behavior and close the application backlog with actual usage evidence.', C.teal);

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Data migration runbook');
    title(s, 'Move the data first; change the known-folder path second', 'Migration Manager provides the controlled data plane. KFM is enabled only after reconciliation and redirect removal.');
    const steps = [
      ['1', 'Manifest', 'User mapping\nsource path\nsize / file count\nowner', C.navy2],
      ['2', 'Pre-provision', 'OneDrive license\nlibrary exists\nquota validated', C.blue],
      ['3', 'Scan', 'Invalid names\nlong paths\nblocked types\npermissions', C.cyan],
      ['4', 'Pre-stage', 'T-7 initial copy\nMigration Manager\nreport retained', C.teal],
      ['5', 'Delta', 'T-1 changes\nerrors resolved\nuser notified', C.green],
      ['6', 'Cut over', 'Disable redirect\nleave source\nenable KFM', C.amber],
      ['7', 'Validate', 'Counts / errors\nsync health\nuser workflow', C.purple],
      ['8', 'Retain / retire', 'Source read-only\n14–30 days\narchive by policy', C.red]
    ];
    steps.forEach((st, i) => {
      const x = 0.34 + i * 1.57;
      s.addShape(pptxShape.roundRect, { x, y: 1.55, w: 1.36, h: 3.86, rectRadius: 0.04, fill: { color: i % 2 ? C.white : C.pale }, line: { color: C.line, width: 0.8 } });
      s.addShape(pptxShape.ellipse, { x: x + 0.42, y: 1.83, w: 0.52, h: 0.52, fill: { color: st[3] }, line: { color: st[3] } });
      s.addText(st[0], { x: x + 0.42, y: 2.0, w: 0.52, h: 0.15, fontFace: FONT, fontSize: 9.5, bold: true, color: C.white, align: 'center', margin: 0 });
      s.addText(st[1], { x: x + 0.12, y: 2.62, w: 1.12, h: 0.45, fontFace: FONT, fontSize: 10.5, bold: true, color: C.navy, align: 'center', margin: 0, fit: 'shrink' });
      s.addText(st[2], { x: x + 0.12, y: 3.4, w: 1.12, h: 1.25, fontFace: FONT, fontSize: 8.7, color: C.gray, align: 'center', margin: 0, fit: 'shrink' });
      if (i < steps.length - 1) arrow(s, x + 1.38, 3.13, 0.17, C.line);
    });
    s.addShape(pptxShape.roundRect, { x: 0.9, y: 5.72, w: 11.55, h: 0.68, rectRadius: 0.04, fill: { color: C.paleAmber }, line: { color: C.amber, width: 1 } });
    s.addText('Rollback condition', { x: 1.17, y: 5.94, w: 1.65, h: 0.2, fontFace: FONT, fontSize: 10.5, bold: true, color: C.amber, margin: 0 });
    s.addText('If data cannot be reconciled or OneDrive/KFM is unhealthy, keep the user on the redirected source and remove the user from the wave.', { x: 2.95, y: 5.92, w: 8.95, h: 0.24, fontFace: FONT, fontSize: 9.8, color: C.ink, margin: 0, fit: 'shrink' });
    source(s, 'Microsoft Learn: Redirect and move Windows known folders to OneDrive; Migration Manager guidance.');
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Citrix / OneDrive decision');
    title(s, 'Do not make OneDrive inside Citrix a dependency until support is confirmed', 'FSLogix storage capacity alone does not establish a supported or performant design.');
    // Decision tree
    s.addShape(pptxShape.roundRect, { x: 0.82, y: 2.72, w: 2.2, h: 0.86, rectRadius: 0.05, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('Must OneDrive run\ninside Citrix?', { x: 1.12, y: 2.95, w: 1.6, h: 0.36, fontFace: FONT, fontSize: 12, bold: true, color: C.white, align: 'center', margin: 0, fit: 'shrink' });
    arrow(s, 3.2, 2.96, 0.48, C.blue);
    s.addShape(pptxShape.diamond, { x: 3.95, y: 2.32, w: 1.72, h: 1.72, fill: { color: C.paleBlue }, line: { color: C.blue, width: 1.2 } });
    s.addText('NO?', { x: 4.38, y: 2.98, w: 0.86, h: 0.2, fontFace: FONT, fontSize: 12, bold: true, color: C.blue, align: 'center', margin: 0 });
    // no branch top
    s.addShape(pptxShape.line, { x: 4.82, y: 2.31, w: 0, h: -0.62, line: { color: C.teal, width: 1.5, endArrowType: 'triangle' } });
    s.addShape(pptxShape.roundRect, { x: 6.05, y: 1.38, w: 5.72, h: 1.2, rectRadius: 0.05, fill: { color: C.paleTeal }, line: { color: C.teal, width: 1.2 } });
    s.addText('Preferred path: migrate filer data server-side, enable KFM on laptops, and keep filer access available in Citrix during coexistence.', { x: 6.37, y: 1.75, w: 5.1, h: 0.45, fontFace: FONT, fontSize: 11.5, bold: true, color: C.teal, align: 'center', margin: 0, fit: 'shrink' });
    // yes branch
    s.addShape(pptxShape.line, { x: 5.68, y: 3.18, w: 0.65, h: 0, line: { color: C.purple, width: 1.5, endArrowType: 'triangle' } });
    s.addShape(pptxShape.diamond, { x: 6.55, y: 2.32, w: 1.72, h: 1.72, fill: { color: C.palePurple }, line: { color: C.purple, width: 1.2 } });
    s.addText('PERSISTENT?', { x: 6.91, y: 2.97, w: 1.0, h: 0.22, fontFace: FONT, fontSize: 10.5, bold: true, color: C.purple, align: 'center', margin: 0 });
    s.addShape(pptxShape.line, { x: 8.28, y: 3.18, w: 0.68, h: 0, line: { color: C.purple, width: 1.5, endArrowType: 'triangle' } });
    s.addShape(pptxShape.diamond, { x: 9.2, y: 2.32, w: 1.72, h: 1.72, fill: { color: C.paleAmber }, line: { color: C.amber, width: 1.2 } });
    s.addText('SUPPORTED OS +\nLATEST FSLOGIX?', { x: 9.52, y: 2.89, w: 1.08, h: 0.45, fontFace: FONT, fontSize: 9.5, bold: true, color: C.amber, align: 'center', margin: 0, fit: 'shrink' });
    s.addShape(pptxShape.line, { x: 10.92, y: 3.18, w: 0.55, h: 0, line: { color: C.teal, width: 1.5, endArrowType: 'triangle' } });
    pill(s, 'PILOT + LOAD TEST', 11.55, 3.0, 1.15, C.teal);
    // lower outcomes
    box(s, 1.0, 4.7, 3.45, 1.28, 'If Server 2019 / 2022 is non-persistent', 'Do not rely on OneDrive inside Citrix until Microsoft confirms the support position. Use the preferred server-side migration path.', C.red, C.paleRed, { titleSize: 12, bodySize: 9.5 });
    box(s, 4.95, 4.7, 3.45, 1.28, 'If the design is supported', 'Install OneDrive per-machine, use current FSLogix, test logon behavior, container growth, IOPS and backup impact.', C.teal, C.paleTeal, { titleSize: 12, bodySize: 9.5 });
    box(s, 8.9, 4.7, 3.45, 1.28, 'Acceptance evidence', 'OneDrive sign-in, sync health, KFM behavior, FSLogix free space, session logoff and recovery after host replacement.', C.blue, C.paleBlue, { titleSize: 12, bodySize: 9.5 });
    source(s, 'Microsoft Learn: Use the sync app on virtual desktops; FSLogix FAQ. Exact support must be checked against the deployed Citrix OS and topology.');
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Application closure');
    title(s, 'Finish the application backlog with usage evidence—not memory', 'The gold image tells us what exists; Director and MDE tell us what is actually used.');
    const srcs = [
      ['Gold image inventory', 'HKLM uninstall records\nservices / drivers\nOffice and browser components', C.blue],
      ['Citrix Director', 'published and local app launches\nunique users / duration\nleast-used apps', C.cyan],
      ['MDE process telemetry', 'executables actually run\nuser and host correlation\nsignature / path context', C.teal],
      ['FSLogix sample', 'HKCU installs\nshortcuts and add-ins\nprofile-specific config', C.purple]
    ];
    srcs.forEach((src, i) => {
      const x = 0.58 + i * 3.14;
      box(s, x, 1.42, 2.78, 2.25, src[0], src[1], src[2], i % 2 ? C.white : C.pale, { titleSize: 13, bodySize: 10 });
      arrow(s, x + 1.05, 3.9, 0.62, src[2]);
    });
    const decisions = [
      ['USED + LOCAL COMPATIBLE', 'Package / validate in Intune', C.teal],
      ['USED + NOT LOCAL', 'Place in AVD with owner and expiry', C.purple],
      ['NOT USED + NO OWNER', 'Retire after business sign-off', C.gray],
      ['UNKNOWN / HIGH RISK', 'Hold and test in isolated cohort', C.amber]
    ];
    decisions.forEach((d, i) => {
      const x = 0.72 + i * 3.05;
      s.addShape(pptxShape.roundRect, { x, y: 4.72, w: 2.72, h: 1.18, rectRadius: 0.04, fill: { color: [C.paleTeal, C.palePurple, C.pale, C.paleAmber][i] }, line: { color: d[2], width: 1 } });
      s.addText(d[0], { x: x + 0.18, y: 4.96, w: 2.36, h: 0.2, fontFace: FONT, fontSize: 8.8, bold: true, color: d[2], align: 'center', margin: 0, fit: 'shrink' });
      s.addText(d[1], { x: x + 0.18, y: 5.37, w: 2.36, h: 0.27, fontFace: FONT, fontSize: 10.2, bold: true, color: C.navy, align: 'center', margin: 0, fit: 'shrink' });
    });
    s.addText('FSLogix method: 150–300 representative logged-off profiles, read-only mount, metadata only; exclude credentials, content, browser history and caches.', { x: 1.0, y: 6.35, w: 11.3, h: 0.27, fontFace: FONT, fontSize: 9.6, bold: true, color: C.navy, align: 'center', margin: 0, fit: 'shrink' });
    source(s, 'Sources: Citrix Director application usage; Microsoft Defender DeviceProcessEvents; Mount-DiskImage -Access ReadOnly.');
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Endpoint foundation');
    title(s, 'Deploy GlobalProtect and the base app set as one readiness package', 'The champion should validate connectivity and core productivity before business applications are tested.');
    const stages = [
      ['1', 'Acquire', 'Approved MSI from the client portal; confirm version and dependencies.', C.navy2],
      ['2', 'Package', 'System context; portal configuration; approved SSO / pre-logon settings.', C.blue],
      ['3', 'Detect', 'Product/version plus service and portal health—not file existence alone.', C.cyan],
      ['4', 'Test', 'Clean install, upgrade, rollback, remote user and in-office scenarios.', C.teal],
      ['5', 'Ring deploy', 'Lab → IT canary → champions → production waves.', C.purple]
    ];
    stages.forEach((st, i) => {
      const x = 0.62 + i * 2.53;
      circleStep(s, st[0], x, 1.48, st[3], st[1], st[2], 2.05);
      if (i < stages.length - 1) arrow(s, x + 2.08, 1.59, 0.28, C.line);
    });
    s.addShape(pptxShape.roundRect, { x: 0.8, y: 4.15, w: 11.7, h: 1.72, rectRadius: 0.05, fill: { color: C.pale }, line: { color: C.line } });
    s.addText('Base readiness test executed by every champion', { x: 1.1, y: 4.45, w: 3.4, h: 0.26, fontFace: FONT, fontSize: 13.5, bold: true, color: C.navy, margin: 0 });
    const tests = ['Sign in and MFA', 'GlobalProtect connection', 'Internal web / file resource', 'Teams call + screen share', 'Office open/save', 'OneDrive sync + KFM', 'Company Portal install'];
    tests.forEach((t, i) => pill(s, t, 1.0 + (i % 4) * 2.85, 4.98 + Math.floor(i / 4) * 0.48, 2.55, [C.blue, C.teal, C.cyan, C.purple][i % 4]));
    s.addText('A failed base readiness test stops application validation; it is resolved as an endpoint issue first.', { x: 2.05, y: 6.33, w: 9.2, h: 0.25, fontFace: FONT, fontSize: 10.4, bold: true, color: C.red, align: 'center', margin: 0, fit: 'shrink' });
  }

  section(p, 4, 'Pilot, AVD and collaboration', 'Validate representative workflows, place exceptions deliberately and keep Teams/Webex migration from becoming hidden scope.', C.cyan);

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Champion design');
    title(s, 'A champion is a workflow witness—not simply an early adopter', 'Select champions to cover the application, location and business risks that broad deployment will encounter.');
    const criteria = [
      ['Business coverage', 'Every business unit and critical function represented', C.blue],
      ['Work pattern', 'Remote, office, hybrid and travel use cases', C.cyan],
      ['Application risk', 'Common, specialist, legacy and high-risk apps', C.purple],
      ['Device diversity', 'Major hardware models, peripherals and smart cards', C.teal],
      ['Support behavior', 'Users willing to test, document and escalate clearly', C.amber]
    ];
    criteria.forEach((c, i) => {
      const y = 1.43 + i * 0.85;
      s.addShape(pptxShape.ellipse, { x: 0.85, y: y + 0.06, w: 0.42, h: 0.42, fill: { color: c[2] }, line: { color: c[2] } });
      s.addText(String(i + 1), { x: 0.85, y: y + 0.2, w: 0.42, h: 0.13, fontFace: FONT, fontSize: 8.7, bold: true, color: C.white, align: 'center', margin: 0 });
      s.addText(c[0], { x: 1.5, y, w: 2.0, h: 0.24, fontFace: FONT, fontSize: 12, bold: true, color: C.navy, margin: 0 });
      s.addText(c[1], { x: 3.75, y, w: 4.1, h: 0.28, fontFace: FONT, fontSize: 10.3, color: C.gray, margin: 0, fit: 'shrink' });
    });
    s.addShape(pptxShape.roundRect, { x: 8.35, y: 1.43, w: 4.05, h: 4.42, rectRadius: 0.05, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('Champion acceptance', { x: 8.72, y: 1.8, w: 3.3, h: 0.28, fontFace: FONT, fontSize: 15, bold: true, color: C.cyan, margin: 0 });
    s.addText('1. Complete the base readiness test.\n\n2. Execute the team’s critical workflows.\n\n3. Record blockers through the structured intake.\n\n4. Operate locally for five business days.\n\n5. Confirm readiness—or name the exact exception.', { x: 8.72, y: 2.3, w: 3.25, h: 2.85, fontFace: FONT, fontSize: 12.3, color: C.white, margin: 0, fit: 'shrink' });
    s.addText('Pilot size: 50–100 users across at least two business units', { x: 8.72, y: 5.4, w: 3.2, h: 0.25, fontFace: FONT, fontSize: 10.4, bold: true, color: C.white, align: 'center', margin: 0, fit: 'shrink' });
    s.addText('Exit: no unresolved severity 1/2 issue; ≥95% of critical workflows pass; fallback reasons are categorized.', { x: 1.1, y: 6.37, w: 11.1, h: 0.28, fontFace: FONT, fontSize: 10.5, bold: true, color: C.red, align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'AVD placement');
    title(s, 'Route workloads into AVD only when the exception is understood', 'The placement record becomes the contract for security, cost, user experience and retirement.');
    s.addShape(pptxShape.roundRect, { x: 0.7, y: 2.35, w: 2.1, h: 1.0, rectRadius: 0.05, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('Can the workflow run\nsecurely on the laptop?', { x: 1.0, y: 2.64, w: 1.5, h: 0.4, fontFace: FONT, fontSize: 11.8, bold: true, color: C.white, align: 'center', margin: 0, fit: 'shrink' });
    arrow(s, 3.05, 2.67, 0.46, C.blue);
    s.addShape(pptxShape.diamond, { x: 3.78, y: 2.08, w: 1.55, h: 1.55, fill: { color: C.paleBlue }, line: { color: C.blue, width: 1.2 } });
    s.addText('YES?', { x: 4.17, y: 2.71, w: 0.78, h: 0.18, fontFace: FONT, fontSize: 11, bold: true, color: C.blue, align: 'center', margin: 0 });
    // local branch
    s.addShape(pptxShape.line, { x: 4.55, y: 2.07, w: 0, h: -0.62, line: { color: C.teal, width: 1.5, endArrowType: 'triangle' } });
    pill(s, 'LOCAL WINDOWS', 3.65, 1.1, 1.8, C.teal);
    // no -> criteria
    s.addShape(pptxShape.line, { x: 5.34, y: 2.85, w: 0.58, h: 0, line: { color: C.purple, width: 1.5, endArrowType: 'triangle' } });
    s.addShape(pptxShape.diamond, { x: 6.15, y: 2.08, w: 1.55, h: 1.55, fill: { color: C.palePurple }, line: { color: C.purple, width: 1.2 } });
    s.addText('VALID\nEXCEPTION?', { x: 6.49, y: 2.59, w: 0.87, h: 0.45, fontFace: FONT, fontSize: 10, bold: true, color: C.purple, align: 'center', margin: 0 });
    // exception -> AVD
    s.addShape(pptxShape.line, { x: 7.71, y: 2.85, w: 0.63, h: 0, line: { color: C.purple, width: 1.5, endArrowType: 'triangle' } });
    s.addShape(pptxShape.roundRect, { x: 8.58, y: 2.2, w: 3.55, h: 1.3, rectRadius: 0.05, fill: { color: C.palePurple }, line: { color: C.purple, width: 1.2 } });
    s.addText('AZURE VIRTUAL DESKTOP', { x: 8.92, y: 2.53, w: 2.87, h: 0.23, fontFace: FONT, fontSize: 13, bold: true, color: C.purple, align: 'center', margin: 0 });
    s.addText('Named host-pool tier + owner + expiry', { x: 8.92, y: 2.94, w: 2.87, h: 0.2, fontFace: FONT, fontSize: 9.5, color: C.ink, align: 'center', margin: 0 });
    // invalid exception down
    s.addShape(pptxShape.line, { x: 6.92, y: 3.63, w: 0, h: 0.62, line: { color: C.amber, width: 1.5, endArrowType: 'triangle' } });
    pill(s, 'HOLD / REMEDIATE / RETIRE', 5.72, 4.45, 2.42, C.amber);
    // entry criteria lower
    box(s, 0.72, 5.1, 3.72, 1.18, 'Valid AVD reasons', 'Offshore contractor, hard legacy dependency, high-risk app isolation, temporary modernization bridge.', C.purple, C.palePurple, { titleSize: 12, bodySize: 9.3 });
    box(s, 4.8, 5.1, 3.72, 1.18, 'Placement record', 'Business owner, user count, data access, network tier, Teams/peripherals, cost, expiry.', C.blue, C.paleBlue, { titleSize: 12, bodySize: 9.3 });
    box(s, 8.88, 5.1, 3.72, 1.18, 'Technical controls', 'MDE, Intune acceptance, least-privilege network, isolated host pool where required, usage monitoring.', C.teal, C.paleTeal, { titleSize: 12, bodySize: 9.3 });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Teams / Webex transition');
    title(s, 'Treat collaboration migration as a separate readiness track', 'Teams may be technically installed while meetings, telephony, rooms and user habits still depend on Webex.');
    const tracks = [
      ['Platform', 'Teams policies\nclient deployment\nmeeting add-in\nAVD media optimization', C.blue],
      ['Network', 'M365 reachability\nproxy bypass / QoS\nmedia path\nremote-user test', C.cyan],
      ['Compliance', 'retention\nrecording\neDiscovery\nexternal access', C.purple],
      ['User workflow', 'meeting scheduling\nrooms / peripherals\nscreen sharing\nfederation', C.teal],
      ['Change', 'coexistence dates\nchampion testing\ntraining\nWebex retirement', C.amber]
    ];
    tracks.forEach((t, i) => {
      const x = 0.52 + i * 2.55;
      s.addShape(pptxShape.roundRect, { x, y: 1.45, w: 2.28, h: 3.55, rectRadius: 0.05, fill: { color: i % 2 ? C.white : C.pale }, line: { color: C.line } });
      s.addShape(pptxShape.ellipse, { x: x + 0.83, y: 1.78, w: 0.62, h: 0.62, fill: { color: t[2] }, line: { color: t[2] } });
      s.addText(String(i + 1), { x: x + 0.83, y: 1.99, w: 0.62, h: 0.16, fontFace: FONT, fontSize: 10, bold: true, color: C.white, align: 'center', margin: 0 });
      s.addText(t[0], { x: x + 0.22, y: 2.7, w: 1.84, h: 0.35, fontFace: FONT, fontSize: 13.5, bold: true, color: C.navy, align: 'center', margin: 0 });
      s.addText(t[1], { x: x + 0.22, y: 3.37, w: 1.84, h: 1.1, fontFace: FONT, fontSize: 10.5, color: C.gray, align: 'center', margin: 0, fit: 'shrink' });
    });
    s.addShape(pptxShape.roundRect, { x: 1.03, y: 5.5, w: 11.25, h: 0.75, rectRadius: 0.04, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('Retirement rule', { x: 1.35, y: 5.75, w: 1.45, h: 0.2, fontFace: FONT, fontSize: 10.5, bold: true, color: C.cyan, margin: 0 });
    s.addText('Do not remove Webex from a cohort until meeting, room, peripheral, recording and external-collaboration workflows are accepted.', { x: 3.0, y: 5.73, w: 8.7, h: 0.24, fontFace: FONT, fontSize: 10, color: C.white, margin: 0, fit: 'shrink' });
  }

  section(p, 5, 'Support automation and delivery control', 'Reduce KTLO with structured intake, read-only endpoint evidence, clear engineering handoffs and bounded AI assistance.', C.amber);

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'ServiceNow automation');
    title(s, 'Automate the evidence and handoff—not the entire service desk', 'The MVP should resolve basic issues faster and create engineering-ready incidents when it cannot.');
    const lanes = [
      ['USER', C.navy2], ['SERVICENOW', C.teal], ['INTUNE / ENTRA', C.blue], ['KNOWLEDGE', C.cyan], ['ADO', C.purple]
    ];
    lanes.forEach((l, i) => {
      s.addText(l[0], { x: 0.42 + i * 2.52, y: 1.35, w: 2.1, h: 0.19, fontFace: FONT, fontSize: 8.5, bold: true, color: l[1], align: 'center', margin: 0 });
      s.addShape(pptxShape.line, { x: 1.47 + i * 2.52, y: 1.75, w: 0, h: 4.32, line: { color: C.line, width: 1, dash: 'dash' } });
    });
    const msgs = [
      [0,1,2.0,'Submit structured issue\n(device, location, wave, impact)', C.teal],
      [1,2,2.72,'Resolve user + device\nread-only lookup', C.blue],
      [2,1,3.42,'Return check-in, compliance,\napps and assignments', C.blue],
      [1,3,4.12,'Search approved KB, known\nerrors and active incidents', C.cyan],
      [3,1,4.82,'Suggested safe steps /\nknown outage result', C.cyan],
      [1,4,5.52,'Create ADO Bug only when\nengineering work is required', C.purple]
    ];
    msgs.forEach(m => {
      const x1 = 1.47 + m[0] * 2.52, x2 = 1.47 + m[1] * 2.52;
      const direction = m[0] > m[1] ? { beginArrowType: 'triangle' } : { endArrowType: 'triangle' };
      s.addShape(pptxShape.line, { x: Math.min(x1,x2), y: m[2], w: Math.abs(x2-x1), h: 0, line: { color: m[4], width: 1.5, ...direction } });
      s.addText(m[3], { x: Math.min(x1,x2) + 0.1, y: m[2] - 0.34, w: Math.abs(x2-x1) - 0.2, h: 0.3, fontFace: FONT, fontSize: 8.5, bold: true, color: m[4], align: 'center', margin: 0, fit: 'shrink' });
    });
    s.addShape(pptxShape.roundRect, { x: 0.85, y: 6.25, w: 11.65, h: 0.47, rectRadius: 0.03, fill: { color: C.paleAmber }, line: { color: C.paleAmber } });
    s.addText('Phase 1 actions: read-only lookup and guidance. Managed-device sync is the first optional action and requires user consent, least privilege and audit.', { x: 1.1, y: 6.4, w: 11.15, h: 0.18, fontFace: FONT, fontSize: 9.5, bold: true, color: '865A15', align: 'center', margin: 0, fit: 'shrink' });
    source(s, 'ServiceNow: Record Producers, Workflow Studio, Microsoft Intune Spoke and Azure DevOps Boards Spoke.');
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'AI-assisted L1 / L2');
    title(s, 'AI should improve the ticket before it is allowed to touch the endpoint', 'Use AI for conversation, retrieval and summarization; use deterministic workflows for actions.');
    // layered architecture
    const layers = [
      ['Conversation', 'Ask focused questions\nconfirm impact and device\ncollect missing facts', C.blue, C.paleBlue],
      ['Grounding', 'approved KB\nknown errors\nservice status\nendpoint evidence', C.cyan, C.paleCyan],
      ['Reasoning', 'classify\nmatch known issue\nsuggest safe next step\ndraft escalation', C.teal, C.paleTeal],
      ['Controlled action', 'user instructions\noptional device sync\ncreate incident / ADO Bug', C.purple, C.palePurple],
      ['Audit', 'inputs\nevidence\nrecommendation\nhuman decision\noutcome', C.amber, C.paleAmber]
    ];
    layers.forEach((l, i) => {
      const x = 0.58 + i * 2.55;
      s.addShape(pptxShape.roundRect, { x, y: 1.47, w: 2.27, h: 3.55, rectRadius: 0.05, fill: { color: l[3] }, line: { color: l[2], width: 1 } });
      s.addText(l[0], { x: x + 0.2, y: 1.8, w: 1.87, h: 0.32, fontFace: FONT, fontSize: 13.5, bold: true, color: l[2], align: 'center', margin: 0 });
      s.addText(l[1], { x: x + 0.2, y: 2.55, w: 1.87, h: 1.65, fontFace: FONT, fontSize: 10.7, color: C.ink, align: 'center', margin: 0, fit: 'shrink' });
      if (i < layers.length - 1) arrow(s, x + 2.28, 3.02, 0.22, C.line);
    });
    box(s, 0.82, 5.38, 5.65, 1.22, 'Allowed in phase 1', 'Focused questions • approved-KB retrieval • evidence summary • suggested steps • draft escalation', C.teal, C.paleTeal, { titleSize: 11.5, bodySize: 9.3 });
    box(s, 6.82, 5.38, 5.65, 1.22, 'Not allowed', 'Free-form PowerShell • delete/reset • access approvals • group changes • credentials • automatic closure', C.red, C.paleRed, { titleSize: 11.5, bodySize: 9.3 });
    source(s, 'ServiceNow: Now Assist for ITSM, AI Agent Studio, access testing, execution history and Now Assist Guardian.');
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Work management');
    title(s, 'Keep one support record and one engineering backlog', 'Integrate at the escalation boundary; do not synchronize every field or copy every incident into ADO.');
    const systems = [
      ['SERVICENOW', 'User-facing incident\nSLA and communications\nApprovals and audit\nL1/L2 ownership', C.teal, C.paleTeal],
      ['AZURE DEVOPS', 'Engineering backlog\nPolicy / app / automation defects\nMigration blockers\nDelivery metrics', C.blue, C.paleBlue],
      ['CONFLUENCE', 'Published runbooks\nFAQs and training\nArchitecture decisions\nSupport knowledge', C.purple, C.palePurple]
    ];
    systems.forEach((sys, i) => {
      const x = 0.72 + i * 4.1;
      s.addShape(pptxShape.roundRect, { x, y: 1.58, w: 3.65, h: 3.68, rectRadius: 0.06, fill: { color: sys[3] }, line: { color: sys[2], width: 1.2 } });
      s.addText(sys[0], { x: x + 0.3, y: 1.98, w: 3.05, h: 0.28, fontFace: FONT, fontSize: 16, bold: true, color: sys[2], align: 'center', margin: 0 });
      s.addShape(pptxShape.line, { x: x + 0.65, y: 2.55, w: 2.35, h: 0, line: { color: sys[2], width: 1.5 } });
      s.addText(sys[1], { x: x + 0.4, y: 2.94, w: 2.85, h: 1.55, fontFace: FONT, fontSize: 12.7, color: C.ink, align: 'center', margin: 0, fit: 'shrink' });
    });
    arrow(s, 4.45, 3.17, 0.25, C.line);
    arrow(s, 8.55, 3.17, 0.25, C.line);
    s.addShape(pptxShape.roundRect, { x: 1.05, y: 5.72, w: 11.2, h: 0.7, rectRadius: 0.04, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('Handoff rule', { x: 1.36, y: 5.95, w: 1.25, h: 0.2, fontFace: FONT, fontSize: 10.5, bold: true, color: C.cyan, margin: 0 });
    s.addText('Create an ADO work item only when code, policy, packaging or platform engineering is required. Return status and resolution to ServiceNow.', { x: 2.85, y: 5.93, w: 8.82, h: 0.23, fontFace: FONT, fontSize: 10, color: C.white, margin: 0, fit: 'shrink' });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'ADO operating model');
    title(s, 'Organize the backlog around capabilities and waves', 'The board should show what blocks user migration—not become a repository for every technical activity.');
    // hierarchy tree
    s.addShape(pptxShape.roundRect, { x: 0.8, y: 1.42, w: 2.5, h: 0.65, rectRadius: 0.04, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('EPIC  |  Exit Citrix', { x: 1.04, y: 1.65, w: 2.0, h: 0.2, fontFace: FONT, fontSize: 12, bold: true, color: C.white, align: 'center', margin: 0 });
    s.addShape(pptxShape.line, { x: 2.05, y: 2.08, w: 0, h: 0.45, line: { color: C.line, width: 1.3 } });
    const features = ['Endpoint baseline', 'Applications', 'User data', 'Teams / AVD', 'Change / support'];
    features.forEach((f, i) => {
      const x = 0.45 + i * 2.48;
      s.addShape(pptxShape.roundRect, { x, y: 2.55, w: 2.2, h: 0.68, rectRadius: 0.04, fill: { color: C.paleBlue }, line: { color: C.blue, width: 1 } });
      s.addText(f, { x: x + 0.15, y: 2.79, w: 1.9, h: 0.2, fontFace: FONT, fontSize: 10.5, bold: true, color: C.blue, align: 'center', margin: 0, fit: 'shrink' });
      s.addShape(pptxShape.line, { x: x + 1.1, y: 3.23, w: 0, h: 0.4, line: { color: C.line, width: 1 } });
      s.addShape(pptxShape.roundRect, { x: x + 0.12, y: 3.65, w: 1.96, h: 1.1, rectRadius: 0.03, fill: { color: C.pale }, line: { color: C.line } });
      s.addText('Stories by persona, app or data cohort\n\nTasks / Bugs by engineering action', { x: x + 0.27, y: 3.88, w: 1.66, h: 0.62, fontFace: FONT, fontSize: 8.8, color: C.ink, align: 'center', margin: 0, fit: 'shrink' });
    });
    box(s, 0.8, 5.2, 3.75, 1.0, 'Required fields', 'Business unit | persona | wave | app | data cohort | blocker | owner | exit criteria', C.teal, C.paleTeal, { titleSize: 11.5, bodySize: 8.7 });
    box(s, 4.78, 5.2, 3.75, 1.0, 'Dashboards', 'Readiness by wave | blocker aging | app coverage | incident trend | exception burn-down', C.purple, C.palePurple, { titleSize: 11.5, bodySize: 8.7 });
    box(s, 8.76, 5.2, 3.75, 1.0, 'Cadence', 'Daily engineering triage | twice-weekly wave review | weekly leadership decision', C.amber, C.paleAmber, { titleSize: 11.5, bodySize: 8.7 });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Delivery ownership');
    title(s, 'Protect architecture capacity with explicit ownership', 'The program needs dedicated coordination, endpoint, data and automation roles; packaging becomes maintenance capacity.');
    const widths = [4.15, 0.75, 5.0, 1.05];
    const heads = ['Role', 'RACI', 'Accountable output', 'FTE'];
    let x = 0.68;
    heads.forEach((h, i) => {
      s.addShape(pptxShape.rect, { x, y: 1.4, w: widths[i], h: 0.5, fill: { color: C.navy }, line: { color: C.white, width: 0.5 } });
      s.addText(h, { x: x + 0.1, y: 1.57, w: widths[i] - 0.2, h: 0.17, fontFace: FONT, fontSize: 8.6, bold: true, color: C.white, align: i === 1 || i === 3 ? 'center' : 'left', margin: 0 });
      x += widths[i];
    });
    const rows = [
      ['Product owner / EUC architect / AVD owner', 'A', 'Architecture, priority, gates, exception decisions', '1.0'],
      ['Change and wave lead', 'R', 'Champion network, BU readiness, comms, schedule', '1.0'],
      ['Intune / endpoint engineer', 'R', 'Policy transition, readiness, rings, remediation', '1.0'],
      ['OneDrive / data engineer', 'R', 'Migration Manager, KFM, reconciliation, rollback', '1.0'],
      ['Automation engineer', 'R', 'ServiceNow, ADO, comms and endpoint evidence', '1.0'],
      ['Service desk / knowledge lead', 'R', 'L1/L2 runbooks, KB, issue patterns and handoff', '1.0'],
      ['Packaging engineer', 'C/R', 'Remaining packages, upgrades and exceptions', '0.5–1.0']
    ];
    rows.forEach((r, ri) => {
      let xx = 0.68, y = 1.9 + ri * 0.63;
      r.forEach((cell, ci) => {
        s.addShape(pptxShape.rect, { x: xx, y, w: widths[ci], h: 0.63, fill: { color: ri % 2 ? C.white : C.pale }, line: { color: C.line, width: 0.55 } });
        s.addText(cell, { x: xx + 0.1, y: y + 0.17, w: widths[ci] - 0.2, h: 0.25, fontFace: FONT, fontSize: ci === 2 ? 9.0 : 9.7, bold: ci === 0, color: ci === 1 ? C.blue : C.ink, align: ci === 1 || ci === 3 ? 'center' : 'left', margin: 0, fit: 'shrink' });
        xx += widths[ci];
      });
    });
    s.addText('Surge capacity: 2–4 hypercare analysts during broad deployment; named fractional owners from network, identity, storage, security and app teams.', { x: 0.95, y: 6.55, w: 11.5, h: 0.24, fontFace: FONT, fontSize: 9.5, italic: true, color: C.gray, align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Sprint 1 backlog');
    title(s, 'The first two weeks should leave twelve tangible artifacts', 'This backlog is small enough to execute and complete enough to support the day-30 foundation gate.');
    const widths = [0.55, 3.35, 2.05, 5.55];
    const heads = ['#', 'Work item', 'Owner', 'Definition of done'];
    let x = 0.68;
    heads.forEach((h, i) => {
      s.addShape(pptxShape.rect, { x, y: 1.37, w: widths[i], h: 0.47, fill: { color: C.navy }, line: { color: C.white, width: 0.5 } });
      s.addText(h, { x: x + 0.08, y: 1.53, w: widths[i] - 0.16, h: 0.16, fontFace: FONT, fontSize: 8.4, bold: true, color: C.white, align: i === 0 ? 'center' : 'left', margin: 0 });
      x += widths[i];
    });
    const items = [
      ['1','Confirm Citrix OS + persistence','Citrix / EUC','Support position and coexistence design documented'],
      ['2','Export Intune policy and assignments','Endpoint','Overlap / owner / disposition matrix created'],
      ['3','Create Lab, Canary, Champion, Wave and Hold groups','Endpoint','Membership rules and exclusions approved'],
      ['4','Baseline active endpoint health','Endpoint + MDE','Entra / Intune / MDE / encryption population measured'],
      ['5','Close GlobalProtect package validation','Network + Endpoint','Install, upgrade, detection and rollback pass'],
      ['6','Select 20–30 IT canaries','Wave lead','Representative devices and users confirmed'],
      ['7','Select 50–100 champions','BU owners','Coverage matrix across BU, app, location and device'],
      ['8','Pre-provision OneDrive pilot cohort','Data','Libraries, quota and mappings validated'],
      ['9','Run Migration Manager scan','Data','Invalid items and remediation owners listed'],
      ['10','Correlate app evidence','Apps + MDE','Gold image + Director + MDE + FSLogix shortlist'],
      ['11','Build EUC Migration Help Record Producer','Automation + ITSM','Structured incident created with required fields'],
      ['12','Publish scorecard and gate thresholds','PO + Wave lead','Weekly report has owners, thresholds and decision line']
    ];
    items.forEach((r, ri) => {
      let xx = 0.68, y = 1.84 + ri * 0.39;
      r.forEach((cell, ci) => {
        s.addShape(pptxShape.rect, { x: xx, y, w: widths[ci], h: 0.39, fill: { color: ri % 2 ? C.white : C.pale }, line: { color: C.line, width: 0.45 } });
        s.addText(cell, { x: xx + 0.07, y: y + 0.105, w: widths[ci] - 0.14, h: 0.17, fontFace: FONT, fontSize: ci === 3 ? 7.6 : 7.9, bold: ci === 0 || ci === 1, color: ci === 0 ? C.blue : C.ink, align: ci === 0 ? 'center' : 'left', margin: 0, fit: 'shrink' });
        xx += widths[ci];
      });
    });
    s.addText('Sprint review output: a working canary path, a clean data pilot backlog, a champion roster, and a measurable day-30 gate.', { x: 1.15, y: 6.64, w: 11.0, h: 0.2, fontFace: FONT, fontSize: 9.7, bold: true, color: C.blue, align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Technical control tower');
    title(s, 'Use one scorecard to promote waves and burn down exceptions', 'A weekly view should connect platform telemetry to business readiness and support impact.');
    const metricGroups = [
      ['Endpoint readiness', ['Active / stale endpoints','MDE + encryption','Policy conflicts','GlobalProtect health'], C.blue, C.paleBlue],
      ['App readiness', ['Required install success','Workflow pass rate','Unowned apps','AVD candidates'], C.cyan, C.paleCyan],
      ['Data readiness', ['Scanned / staged / cut over','Migration errors','KFM health','Rollback cohorts'], C.teal, C.paleTeal],
      ['User experience', ['Local-first adoption','Citrix launches','Incidents / 100 users','MTTR + repeat issues'], C.amber, C.paleAmber]
    ];
    metricGroups.forEach((g, i) => {
      const x = 0.7 + i * 3.12;
      box(s, x, 1.45, 2.8, 3.4, g[0], g[1], g[2], g[3], { titleSize: 14, bodySize: 10.8, para: 8 });
    });
    s.addShape(pptxShape.roundRect, { x: 0.9, y: 5.25, w: 11.5, h: 1.0, rectRadius: 0.05, fill: { color: C.navy }, line: { color: C.navy } });
    s.addText('WEEKLY DECISION', { x: 1.23, y: 5.57, w: 1.75, h: 0.2, fontFace: FONT, fontSize: 10, bold: true, color: C.cyan, margin: 0 });
    const decisions = [['Proceed', C.green], ['Proceed with exclusions', C.blue], ['Pause affected persona', C.amber], ['Escalate decision', C.red]];
    decisions.forEach((d, i) => pill(s, d[0], 3.1 + i * 2.15, 5.48, 1.85, d[1]));
    s.addText('Exceptions are visible as a managed backlog with owner, reason, population, workaround, cost and next review date.', { x: 1.25, y: 6.42, w: 10.8, h: 0.22, fontFace: FONT, fontSize: 9.8, bold: true, color: C.navy, align: 'center', margin: 0, fit: 'shrink' });
  }

  {
    const s = p.addSlide('BASE');
    eyebrow(s, 'Reference');
    title(s, 'Primary implementation references', 'The plan relies on vendor-supported behavior; validate deployed versions and licensing before execution.');
    const refs = [
      ['Intune policy removal / tattooing','learn.microsoft.com/mem/intune/configuration/device-profile-troubleshoot'],
      ['Windows Policy CSP conflict control','learn.microsoft.com/windows/client-management/mdm/policy-csp-controlpolicyconflict'],
      ['Windows Autopilot Reset','learn.microsoft.com/autopilot/windows-autopilot-reset'],
      ['OneDrive KFM transition','learn.microsoft.com/sharepoint/redirect-known-folders'],
      ['OneDrive virtual desktop support','learn.microsoft.com/sharepoint/onedrive-in-citrix-virtual-apps-deployment-guide'],
      ['FSLogix command-line and FAQ','learn.microsoft.com/fslogix'],
      ['MDE DeviceProcessEvents','learn.microsoft.com/defender-xdr/advanced-hunting-deviceprocessevents-table'],
      ['Citrix application usage','docs.citrix.com/.../application-usage-monitoring.html'],
      ['ServiceNow Microsoft Intune Spoke','servicenow.com/docs - Microsoft Intune Spoke'],
      ['ServiceNow Now Assist / AI Agent Studio','servicenow.com/docs - Now Assist for ITSM / AI Agent Studio']
    ];
    refs.forEach((r, i) => {
      const x = 0.72 + (i % 2) * 6.08, y = 1.38 + Math.floor(i / 2) * 1.0;
      s.addShape(pptxShape.roundRect, { x, y, w: 5.7, h: 0.78, rectRadius: 0.03, fill: { color: Math.floor(i / 2) % 2 ? C.white : C.pale }, line: { color: C.line, width: 0.7 } });
      s.addText(r[0], { x: x + 0.18, y: y + 0.14, w: 2.2, h: 0.2, fontFace: FONT, fontSize: 9.3, bold: true, color: C.navy, margin: 0, fit: 'shrink' });
      s.addText(r[1], { x: x + 0.18, y: y + 0.46, w: 5.2, h: 0.15, fontFace: FONT, fontSize: 7.4, color: C.gray, margin: 0, fit: 'shrink' });
    });
    s.addText('Workspace accelerators already available: Intune policy inventory, Endpoint Explorer, app triage, champion enrollment, phased rollout and automated AVD POC.', { x: 1.0, y: 6.55, w: 11.3, h: 0.25, fontFace: FONT, fontSize: 9.6, bold: true, color: C.blue, align: 'center', margin: 0, fit: 'shrink' });
  }

  await p.writeFile({ fileName: path.join(OUT, 'EUC-Transformation-Technical-Implementation-Plan-v2.pptx') });
}

async function main() {
  await buildExecutive();
  await buildTechnical();
  console.log('Created revised executive and technical decks.');
}

main().catch(err => { console.error(err); process.exit(1); });
