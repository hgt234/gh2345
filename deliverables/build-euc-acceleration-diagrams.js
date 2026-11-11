const pptxgen = require(process.env.CODEX_PPTXGENJS_PATH || 'pptxgenjs');

const OUT = __dirname;
const FONT = 'Aptos';
const S = { rect: 'rect', roundRect: 'roundRect', ellipse: 'ellipse', line: 'line', chevron: 'chevron', diamond: 'diamond' };
const C = {
  navy: '102A43', navy2: '243B53', ink: '17202A', gray: '5D6B78', gray2: '8492A0',
  line: 'D9E2EA', pale: 'F5F7FA', white: 'FFFFFF', blue: '246BFD', bluePale: 'EAF2FF',
  cyan: '16A6C9', cyanPale: 'E8F8FC', teal: '0D9B87', tealPale: 'E8F7F3',
  green: '278F61', greenPale: 'E9F6EF', purple: '6E5AC7', purplePale: 'F0EDFB',
  amber: 'E39B2E', amberPale: 'FFF4E0', red: 'D84E4B', redPale: 'FCECEB'
};

function makeDeck() {
  const p = new pptxgen();
  p.layout = 'LAYOUT_WIDE';
  p.author = 'EUC Transformation Program';
  p.company = 'Client';
  p.title = 'EUC Acceleration Plan — Execution Diagrams';
  p.subject = 'Reusable diagrams for the approved local-first workplace plan';
  p.lang = 'en-US';
  p.theme = { headFontFace: FONT, bodyFontFace: FONT, lang: 'en-US' };
  p.defineSlideMaster({
    title: 'BASE', background: { color: C.white },
    objects: [
      { rect: { x: 0, y: 0, w: 13.333, h: 0.08, fill: { color: C.blue }, line: { color: C.blue } } },
      { text: { text: 'EUC ACCELERATION PLAN  |  APPROVED SCOPE — EXECUTION VIEW', options: { x: 0.55, y: 7.15, w: 5.9, h: 0.14, fontFace: FONT, fontSize: 7.3, color: C.gray2, charSpacing: 1.0, margin: 0 } } }
    ],
    slideNumber: { x: 12.55, y: 7.13, w: 0.3, h: 0.15, fontFace: FONT, fontSize: 7.3, color: C.gray2, align: 'right', margin: 0 }
  });
  return p;
}

function heading(slide, kicker, headline, sub = '') {
  slide.addText(kicker.toUpperCase(), { x: 0.62, y: 0.2, w: 4.2, h: 0.16, fontFace: FONT, fontSize: 8, bold: true, color: C.blue, charSpacing: 1.6, margin: 0 });
  slide.addText(headline, { x: 0.62, y: 0.39, w: 12.0, h: 0.46, fontFace: FONT, fontSize: 24.5, bold: true, color: C.navy, margin: 0, fit: 'shrink' });
  if (sub) slide.addText(sub, { x: 0.64, y: 0.91, w: 11.85, h: 0.28, fontFace: FONT, fontSize: 11.2, color: C.gray, margin: 0, fit: 'shrink' });
}

function text(slide, value, x, y, w, h, opts = {}) {
  slide.addText(value, { x, y, w, h, fontFace: FONT, fontSize: opts.size || 10, bold: !!opts.bold, color: opts.color || C.ink, align: opts.align || 'left', valign: opts.valign || 'mid', margin: opts.margin === undefined ? 0.03 : opts.margin, fit: 'shrink', breakLine: false });
}

function box(slide, x, y, w, h, label, detail, accent, fill, opts = {}) {
  slide.addShape(S.roundRect, { x, y, w, h, rectRadius: 0.04, fill: { color: fill }, line: { color: accent, width: opts.lineWidth || 1 } });
  if (!opts.noBar) slide.addShape(S.rect, { x, y, w, h: 0.06, fill: { color: accent }, line: { color: accent } });
  text(slide, label, x + 0.16, y + 0.16, w - 0.32, opts.titleH || 0.27, { size: opts.titleSize || 11.5, bold: true, color: opts.titleColor || C.navy, align: opts.align || 'left' });
  if (detail) text(slide, detail, x + 0.16, y + (opts.detailY || 0.52), w - 0.32, h - (opts.detailY || 0.52) - 0.12, { size: opts.bodySize || 8.9, color: opts.bodyColor || C.ink, align: opts.align || 'left', valign: opts.valign || 'top' });
}

function arrow(slide, x, y, w, color = C.line) {
  slide.addShape(S.chevron, { x, y, w, h: 0.32, fill: { color }, line: { color } });
}

function taskBar(slide, x, y, w, label, color, fill, detail = '') {
  slide.addShape(S.roundRect, { x, y, w, h: 0.5, rectRadius: 0.035, fill: { color: fill }, line: { color, width: 1 } });
  text(slide, label, x + 0.1, y + 0.08, w - 0.2, 0.17, { size: 8.5, bold: true, color, align: 'center' });
  if (detail) text(slide, detail, x + 0.1, y + 0.27, w - 0.2, 0.13, { size: 6.9, color: C.gray, align: 'center' });
}

function milestone(slide, x, y, label, color) {
  slide.addShape(S.diamond, { x, y, w: 0.26, h: 0.26, fill: { color }, line: { color } });
  text(slide, label, x - 0.35, y + 0.33, 0.96, 0.28, { size: 7.5, bold: true, color, align: 'center', valign: 'top' });
}

async function build() {
  const p = makeDeck();

  // 1 — 90-day plan on a page
  {
    const s = p.addSlide('BASE');
    heading(s, 'Plan on a page', 'The first 90 days build the migration path, prove it, then increase volume', 'Workstreams run in parallel, but production volume only increases when endpoint, data, application and support readiness are all green.');
    const phases = [
      ['DAYS 1–10', 'Mobilize', C.navy2], ['DAYS 11–30', 'Prove the path', C.blue],
      ['DAYS 31–45', 'Prove workflows', C.cyan], ['DAYS 46–65', 'Run the factory', C.teal],
      ['DAYS 66–90', 'Increase volume', C.purple]
    ];
    const startX = 2.05, colW = 2.12;
    phases.forEach((ph, i) => {
      const x = startX + i * colW;
      s.addShape(S.rect, { x, y: 1.38, w: colW - 0.05, h: 0.55, fill: { color: ph[2] }, line: { color: ph[2] } });
      text(s, ph[0], x + 0.08, 1.47, colW - 0.21, 0.13, { size: 8, bold: true, color: C.white, align: 'center' });
      text(s, ph[1], x + 0.08, 1.65, colW - 0.21, 0.17, { size: 9.5, bold: true, color: C.white, align: 'center' });
      s.addShape(S.line, { x, y: 1.94, w: 0, h: 3.97, line: { color: C.line, width: 0.8 } });
    });
    s.addShape(S.line, { x: startX + 5 * colW - 0.05, y: 1.94, w: 0, h: 3.97, line: { color: C.line, width: 0.8 } });

    const lanes = [
      ['Endpoint + apps', C.blue, C.bluePale], ['User data', C.teal, C.tealPale],
      ['Business + change', C.cyan, C.cyanPale], ['Support', C.amber, C.amberPale],
      ['AVD + Citrix', C.purple, C.purplePale]
    ];
    lanes.forEach((l, i) => {
      const y = 2.08 + i * 0.76;
      s.addShape(S.roundRect, { x: 0.55, y, w: 1.35, h: 0.56, rectRadius: 0.03, fill: { color: l[2] }, line: { color: l[1], width: 1 } });
      text(s, l[0], 0.68, y + 0.13, 1.09, 0.25, { size: 8.7, bold: true, color: l[1], align: 'center' });
      s.addShape(S.line, { x: startX, y: y + 0.28, w: 10.55, h: 0, line: { color: C.line, width: 0.8 } });
    });

    taskBar(s, 2.16, 2.11, 1.82, 'Export + map policy', C.blue, C.bluePale, 'Canary + rollback');
    taskBar(s, 4.18, 2.11, 1.78, 'GlobalProtect + core apps', C.blue, C.bluePale, '10–20 devices');
    taskBar(s, 6.35, 2.11, 1.7, 'Champion validation', C.blue, C.bluePale, 'real workflows');
    taskBar(s, 8.38, 2.11, 1.83, 'Ring deployment', C.blue, C.bluePale, 'measured defects');
    taskBar(s, 10.55, 2.11, 1.78, 'Wave expansion', C.blue, C.bluePale, 'rate set by evidence');

    taskBar(s, 2.56, 2.87, 1.35, 'Manifest + scan', C.teal, C.tealPale);
    taskBar(s, 4.12, 2.87, 1.83, 'Pilot pre-stage + delta', C.teal, C.tealPale);
    taskBar(s, 6.24, 2.87, 1.94, 'Break redirect + KFM', C.teal, C.tealPale);
    taskBar(s, 8.43, 2.87, 3.90, 'Migration Manager waves + reconciliation', C.teal, C.tealPale);

    taskBar(s, 2.32, 3.63, 1.58, 'Owners + cohort roster', C.cyan, C.cyanPale);
    taskBar(s, 4.26, 3.63, 1.72, 'Champion schedule', C.cyan, C.cyanPale);
    taskBar(s, 6.28, 3.63, 1.96, '5-day local work test', C.cyan, C.cyanPale);
    taskBar(s, 8.43, 3.63, 3.90, 'Wave communications + business acceptance', C.cyan, C.cyanPale);

    taskBar(s, 2.55, 4.39, 1.38, 'Intake design', C.amber, C.amberPale);
    taskBar(s, 4.18, 4.39, 1.78, 'ServiceNow MVP', C.amber, C.amberPale, 'structured evidence');
    taskBar(s, 6.26, 4.39, 1.86, 'Daily pilot triage', C.amber, C.amberPale);
    taskBar(s, 8.38, 4.39, 3.95, 'L1/L2 runbooks + exception burn-down', C.amber, C.amberPale);

    taskBar(s, 2.20, 5.15, 1.72, 'Confirm AVD criteria', C.purple, C.purplePale);
    taskBar(s, 4.18, 5.15, 1.78, 'Validate host pools', C.purple, C.purplePale);
    taskBar(s, 6.26, 5.15, 1.84, 'Place exceptions', C.purple, C.purplePale);
    taskBar(s, 8.38, 5.15, 1.88, 'Monitor utilization', C.purple, C.purplePale);
    taskBar(s, 10.52, 5.15, 1.81, 'Retire Citrix paths', C.purple, C.purplePale);

    s.addShape(S.line, { x: 2.15, y: 6.14, w: 10.08, h: 0, line: { color: C.red, width: 2.2 } });
    milestone(s, 3.85, 6.01, 'CANARY GREEN', C.blue);
    milestone(s, 5.96, 6.01, 'FULL PATH PROVEN', C.teal);
    milestone(s, 8.08, 6.01, 'CHAMPION ACCEPTED', C.cyan);
    milestone(s, 10.20, 6.01, 'FACTORY STABLE', C.amber);
    milestone(s, 12.08, 6.01, 'RATE CONFIRMED', C.purple);
    text(s, 'Critical path', 0.62, 6.0, 1.28, 0.2, { size: 9.2, bold: true, color: C.red, align: 'right' });
    text(s, 'Planning range: 900–1,500 users in 90 days. The committed weekly rate is set after the complete path is proven—not before.', 2.2, 6.76, 10.2, 0.19, { size: 8.4, bold: true, color: C.navy, align: 'center' });
  }

  // 2 — dependencies and parallel work
  {
    const s = p.addSlide('BASE');
    heading(s, 'Dependency map', 'Volume can increase only after the complete path works for a real cohort', 'The top row is the critical path. The lower workstreams run in parallel and must join it before each production wave.');
    const chain = [
      ['1', 'Cohort + owners', 'named users\ncritical workflows'],
      ['2', 'Endpoint canary', 'policy + GP + apps\ngreen'],
      ['3', 'Data pilot', 'pre-stage, cutover\nKFM healthy'],
      ['4', 'Champion proof', '5 business days\nlocal-first'],
      ['5', 'Wave go / no-go', 'readiness score\nexceptions owned'],
      ['6', 'Production wave', 'migrate + hypercare\naccept']
    ];
    chain.forEach((n, i) => {
      const x = 0.48 + i * 2.12;
      const accent = [C.navy2, C.blue, C.teal, C.cyan, C.amber, C.purple][i];
      const fill = [C.pale, C.bluePale, C.tealPale, C.cyanPale, C.amberPale, C.purplePale][i];
      s.addShape(S.roundRect, { x, y: 1.45, w: 1.78, h: 1.36, rectRadius: 0.04, fill: { color: fill }, line: { color: accent, width: 1.1 } });
      s.addShape(S.ellipse, { x: x + 0.12, y: 1.62, w: 0.36, h: 0.36, fill: { color: accent }, line: { color: accent } });
      text(s, n[0], x + 0.12, 1.73, 0.36, 0.12, { size: 8.2, bold: true, color: C.white, align: 'center' });
      text(s, n[1], x + 0.55, 1.58, 1.08, 0.38, { size: 10.3, bold: true, color: C.navy, align: 'left' });
      text(s, n[2], x + 0.16, 2.15, 1.46, 0.4, { size: 8.1, color: C.gray, align: 'center', valign: 'top' });
      if (i < chain.length - 1) arrow(s, x + 1.82, 1.98, 0.23, C.line);
    });
    s.addShape(S.roundRect, { x: 0.62, y: 3.23, w: 12.05, h: 0.45, rectRadius: 0.03, fill: { color: C.navy }, line: { color: C.navy } });
    text(s, 'PARALLEL WORK THAT FEEDS THE CRITICAL PATH', 0.9, 3.37, 11.5, 0.14, { size: 8.7, bold: true, color: C.white, align: 'center' });

    const lanes = [
      ['Applications', C.blue, C.bluePale, ['Usage evidence', 'Close package gaps', 'Deploy / update'], 'joins endpoint canary + champion proof'],
      ['AVD exceptions', C.purple, C.purplePale, ['Classify reason', 'Placement record', 'Validate host pool'], 'joins wave go / no-go'],
      ['Support', C.amber, C.amberPale, ['Structured intake', 'Read-only evidence', 'L1/L2 handoff'], 'joins pilot + every production wave'],
      ['Teams / Webex', C.teal, C.tealPale, ['Platform + network', 'Workflow acceptance', 'Retirement schedule'], 'runs as a separate readiness track']
    ];
    lanes.forEach((l, i) => {
      const y = 3.95 + i * 0.7;
      text(s, l[0], 0.62, y + 0.11, 1.35, 0.21, { size: 9.5, bold: true, color: l[1] });
      l[3].forEach((step, j) => {
        const x = 2.05 + j * 2.23;
        s.addShape(S.roundRect, { x, y, w: 1.9, h: 0.45, rectRadius: 0.03, fill: { color: l[2] }, line: { color: l[1], width: 0.8 } });
        text(s, step, x + 0.1, y + 0.12, 1.7, 0.17, { size: 8.5, bold: true, color: l[1], align: 'center' });
        if (j < 2) arrow(s, x + 1.94, y + 0.07, 0.2, C.line);
      });
      s.addShape(S.line, { x: 8.62, y: y + 0.23, w: 0.55, h: 0, line: { color: l[1], width: 1.2, endArrowType: 'triangle' } });
      s.addShape(S.roundRect, { x: 9.22, y, w: 3.28, h: 0.45, rectRadius: 0.03, fill: { color: C.pale }, line: { color: C.line, width: 0.7 } });
      text(s, l[4], 9.38, y + 0.11, 2.96, 0.2, { size: 8.2, bold: true, color: C.navy, align: 'center' });
    });
  }

  // 3 — cohort migration flow
  {
    const s = p.addSlide('BASE');
    heading(s, 'Cohort workflow', 'Every cohort follows the same controlled path from discovery to acceptance', 'A cohort does not enter production because packaging is complete; it enters when the user workflow, data path, endpoint and support path have all been proven.');
    const nodes = [
      ['1', 'DISCOVER', 'users • personas • apps\ndata size • locations', C.navy2, C.pale],
      ['2', 'REMEDIATE', 'policy conflicts • GP/apps\nmigration errors', C.blue, C.bluePale],
      ['3', 'PROVE', 'champions work locally\nfor 5 business days', C.cyan, C.cyanPale],
      ['4', 'MIGRATE', 'pre-stage • delta • redirect\nKFM • communication', C.teal, C.tealPale],
      ['5', 'STABILIZE', '5-day hypercare\nissue burn-down', C.green, C.greenPale],
      ['6', 'ACCEPT', 'business sign-off\nAVD / hold exceptions', C.purple, C.purplePale]
    ];
    nodes.forEach((n, i) => {
      const x = 0.48 + i * 2.12;
      s.addShape(S.roundRect, { x, y: 1.65, w: 1.72, h: 1.55, rectRadius: 0.04, fill: { color: n[4] }, line: { color: n[3], width: 1.1 } });
      s.addShape(S.ellipse, { x: x + 0.59, y: 1.42, w: 0.54, h: 0.54, fill: { color: n[3] }, line: { color: n[3] } });
      text(s, n[0], x + 0.59, 1.60, 0.54, 0.14, { size: 9.5, bold: true, color: C.white, align: 'center' });
      text(s, n[1], x + 0.14, 2.08, 1.44, 0.23, { size: 10.5, bold: true, color: n[3], align: 'center' });
      text(s, n[2], x + 0.12, 2.51, 1.48, 0.43, { size: 8.1, color: C.ink, align: 'center', valign: 'top' });
      if (i < nodes.length - 1) arrow(s, x + 1.76, 2.26, 0.27, C.line);
    });

    text(s, 'READINESS DECISION', 4.75, 3.55, 1.72, 0.18, { size: 8, bold: true, color: C.gray2, align: 'center' });
    s.addShape(S.diamond, { x: 5.03, y: 3.8, w: 1.18, h: 1.18, fill: { color: C.amberPale }, line: { color: C.amber, width: 1.2 } });
    text(s, 'ALL FOUR\nDOMAINS\nGREEN?', 5.27, 4.12, 0.7, 0.43, { size: 8.7, bold: true, color: C.amber, align: 'center' });
    s.addShape(S.line, { x: 6.21, y: 4.39, w: 1.0, h: 0, line: { color: C.teal, width: 1.4, endArrowType: 'triangle' } });
    text(s, 'YES → continue to migrate', 7.3, 4.25, 2.05, 0.24, { size: 9.2, bold: true, color: C.teal });
    s.addShape(S.line, { x: 5.62, y: 4.98, w: 0, h: 0.65, line: { color: C.red, width: 1.4, endArrowType: 'triangle' } });
    s.addShape(S.roundRect, { x: 4.05, y: 5.78, w: 3.14, h: 0.66, rectRadius: 0.04, fill: { color: C.redPale }, line: { color: C.red, width: 1 } });
    text(s, 'NO → remediate, exclude the user, or create an owned AVD placement', 4.28, 5.96, 2.68, 0.26, { size: 8.8, bold: true, color: C.red, align: 'center' });

    const checks = [
      ['Endpoint', 'Intune • MDE • GP • apps', C.blue, C.bluePale],
      ['Applications', 'critical workflows pass', C.cyan, C.cyanPale],
      ['User data', 'reconciled • KFM healthy', C.teal, C.tealPale],
      ['Support', 'intake • owner • runbook', C.amber, C.amberPale]
    ];
    checks.forEach((c, i) => {
      const x = 0.72 + i * 3.12;
      s.addShape(S.roundRect, { x, y: 6.58, w: 2.8, h: 0.38, rectRadius: 0.03, fill: { color: c[3] }, line: { color: c[2], width: 0.8 } });
      text(s, `${c[0]}  |  ${c[1]}`, x + 0.1, 6.68, 2.6, 0.13, { size: 7.7, bold: true, color: c[2], align: 'center' });
    });
  }

  // 4 — first 15 business days
  {
    const s = p.addSlide('BASE');
    heading(s, 'Immediate acceleration', 'The first 15 business days should produce five tangible outputs', 'This is the mobilization sequence for next week: establish control, prove the riskiest path early and avoid waiting for every unknown to be resolved.');
    const periods = [
      ['DAYS 1–3', C.navy2], ['DAYS 4–7', C.blue], ['DAYS 8–10', C.cyan], ['DAYS 11–15', C.teal]
    ];
    periods.forEach((p0, i) => {
      const x = 2.25 + i * 2.27;
      s.addShape(S.rect, { x, y: 1.42, w: 2.19, h: 0.46, fill: { color: p0[1] }, line: { color: p0[1] } });
      text(s, p0[0], x + 0.1, 1.57, 1.99, 0.14, { size: 8.7, bold: true, color: C.white, align: 'center' });
      s.addShape(S.line, { x, y: 1.9, w: 0, h: 4.25, line: { color: C.line, width: 0.7 } });
    });
    s.addShape(S.line, { x: 11.33, y: 1.9, w: 0, h: 4.25, line: { color: C.line, width: 0.7 } });
    text(s, 'OUTPUTS', 11.58, 1.57, 1.05, 0.15, { size: 8.5, bold: true, color: C.gray2, align: 'center' });

    const rows = [
      ['Control', C.navy2, C.pale, [
        [0, 1, 'Confirm owners + gates'], [1, 1, 'Create cohort roster'], [2, 2, 'Set wave governance']
      ], 'Approved readiness contract'],
      ['Endpoint', C.blue, C.bluePale, [
        [0, 1, 'Export assignments + conflicts'], [1, 1, 'Canary + rollback'], [2, 2, 'GP/core app test']
      ], 'Canary deployment pack'],
      ['User data', C.teal, C.tealPale, [
        [0, 1, 'Build manifest + scan'], [1, 1, '10–20 user pre-stage'], [2, 2, 'Cutover + KFM report']
      ], 'Data pilot report'],
      ['Support', C.amber, C.amberPale, [
        [0, 1, 'Record producer fields'], [1, 1, 'Read-only evidence lookup'], [2, 2, 'Runbook + triage']
      ], 'ServiceNow support MVP'],
      ['Change', C.cyan, C.cyanPale, [
        [0, 1, 'Champion nominations'], [1, 1, 'Workflow checklist'], [2, 2, 'Schedule first cohort']
      ], '50–100 champion roster']
    ];
    rows.forEach((r, ri) => {
      const y = 2.1 + ri * 0.82;
      s.addShape(S.roundRect, { x: 0.55, y, w: 1.43, h: 0.55, rectRadius: 0.03, fill: { color: r[2] }, line: { color: r[1], width: 1 } });
      text(s, r[0], 0.69, y + 0.16, 1.15, 0.18, { size: 9.2, bold: true, color: r[1], align: 'center' });
      r[3].forEach(t => {
        const x = 2.31 + t[0] * 2.27;
        const w = t[1] * 2.27 - 0.18;
        s.addShape(S.roundRect, { x, y: y + 0.04, w, h: 0.47, rectRadius: 0.025, fill: { color: r[2] }, line: { color: r[1], width: 0.8 } });
        text(s, t[2], x + 0.1, y + 0.16, w - 0.2, 0.17, { size: 8.1, bold: true, color: r[1], align: 'center' });
      });
      s.addShape(S.roundRect, { x: 11.53, y, w: 1.2, h: 0.55, rectRadius: 0.03, fill: { color: C.pale }, line: { color: C.line, width: 0.8 } });
      text(s, r[4], 11.64, y + 0.09, 0.98, 0.34, { size: 7.5, bold: true, color: C.navy, align: 'center' });
    });
    s.addShape(S.roundRect, { x: 2.25, y: 6.38, w: 10.48, h: 0.46, rectRadius: 0.03, fill: { color: C.navy }, line: { color: C.navy } });
    text(s, 'Day-15 decision: begin the full champion proof, or hold only the failed domain while the other workstreams continue.', 2.55, 6.52, 9.88, 0.16, { size: 8.8, bold: true, color: C.white, align: 'center' });
  }

  // 5 — operating control loop
  {
    const s = p.addSlide('BASE');
    heading(s, 'Operating model', 'One control loop keeps migration work visible and prevents KTLO from absorbing the program', 'ServiceNow remains the support record; ADO holds engineering work; the weekly scorecard determines whether the next cohort proceeds.');
    const flow = [
      ['1', 'PLAN WAVE', 'ADO\ncohort + readiness'],
      ['2', 'EXECUTE', 'Intune / Migration\nManager / AVD'],
      ['3', 'INTAKE', 'ServiceNow\nstructured issue'],
      ['4', 'TRIAGE', 'support or\nengineering?'],
      ['5', 'REMEDIATE', 'policy • app • data\nor user guidance'],
      ['6', 'RETEST + ACCEPT', 'champion / BU\nscorecard']
    ];
    const colors = [C.navy2, C.blue, C.teal, C.amber, C.red, C.purple];
    const fills = [C.pale, C.bluePale, C.tealPale, C.amberPale, C.redPale, C.purplePale];
    flow.forEach((f, i) => {
      const x = 0.45 + i * 2.13;
      s.addShape(S.roundRect, { x, y: 1.62, w: 1.76, h: 1.42, rectRadius: 0.04, fill: { color: fills[i] }, line: { color: colors[i], width: 1.1 } });
      s.addShape(S.ellipse, { x: x + 0.61, y: 1.39, w: 0.54, h: 0.54, fill: { color: colors[i] }, line: { color: colors[i] } });
      text(s, f[0], x + 0.61, 1.57, 0.54, 0.14, { size: 9.3, bold: true, color: C.white, align: 'center' });
      text(s, f[1], x + 0.14, 2.08, 1.48, 0.22, { size: 9.7, bold: true, color: colors[i], align: 'center' });
      text(s, f[2], x + 0.14, 2.48, 1.48, 0.36, { size: 8.3, color: C.ink, align: 'center', valign: 'top' });
      if (i < flow.length - 1) arrow(s, x + 1.79, 2.16, 0.25, C.line);
    });
    s.addShape(S.line, { x: 12.02, y: 3.13, w: 0, h: 0.46, line: { color: C.purple, width: 1.4 } });
    s.addShape(S.line, { x: 1.32, y: 3.59, w: 10.7, h: 0, line: { color: C.purple, width: 1.4, beginArrowType: 'triangle' } });
    text(s, 'Accepted cohort feeds the next wave plan', 5.15, 3.69, 3.2, 0.19, { size: 8.3, bold: true, color: C.purple, align: 'center' });

    box(s, 0.62, 4.08, 5.85, 1.48, 'Evidence used in triage', 'Intune assignment and compliance • MDE device evidence • Citrix Director usage • Migration Manager results • champion workflow result', C.blue, C.bluePale, { titleSize: 11.7, bodySize: 9.2 });
    box(s, 6.84, 4.08, 5.85, 1.48, 'Engineering handoff rule', 'Create an ADO Bug only when policy, packaging, automation or platform engineering is required. Return status and resolution to the ServiceNow record.', C.teal, C.tealPale, { titleSize: 11.7, bodySize: 9.2 });

    const cadence = [
      ['DAILY', 'wave stand-up • Sev 1/2 review • blocker owner'],
      ['TWICE WEEKLY', 'engineering triage • exception decisions'],
      ['WEEKLY', 'readiness/go-no-go • sponsor scorecard'],
      ['PER WAVE', '5-day hypercare • business acceptance']
    ];
    cadence.forEach((c, i) => {
      const x = 0.72 + i * 3.05;
      s.addShape(S.roundRect, { x, y: 5.93, w: 2.75, h: 0.78, rectRadius: 0.03, fill: { color: i % 2 ? C.white : C.pale }, line: { color: C.line, width: 0.8 } });
      text(s, c[0], x + 0.14, 6.09, 0.83, 0.16, { size: 7.8, bold: true, color: C.blue, align: 'center' });
      text(s, c[1], x + 1.0, 6.04, 1.58, 0.3, { size: 7.8, bold: true, color: C.navy, align: 'left' });
    });
  }

  await p.writeFile({ fileName: `${OUT}/EUC-Acceleration-Plan-Diagrams.pptx` });
  console.log('Created EUC acceleration diagram pack.');
}

build().catch(err => { console.error(err); process.exit(1); });
