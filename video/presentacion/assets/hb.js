// Helpers compartidos: onda de la píldora y texto que se va escribiendo, todo función del tiempo.
window.HB = {
  // 11 barras como Flow.levels.
  bars(wave, n = 11) {
    wave.innerHTML = "";
    for (let i = 0; i < n; i++) wave.appendChild(document.createElement("i"));
    return [...wave.children];
  },
  // Nivel determinista por barra: voz con sílabas, nunca Math.random.
  setWave(bars, t, amp = 1) {
    const n = bars.length;
    bars.forEach((b, i) => {
      const shape = 1 - Math.abs(i - (n - 1) / 2) / n;
      const syl = 0.5 + 0.5 * Math.sin(t * 9.1 + i * 0.9) * Math.sin(t * 3.7 + i * 1.7);
      const l = Math.max(0, Math.min(1, (0.25 + 0.75 * Math.abs(syl)) * amp));
      b.style.height = Math.max(10, l * 55 * (0.5 + shape)) + "px";
    });
  },
  // Revela `full` por caracteres según p (0..1).
  type(el, full, p) {
    el.textContent = full.slice(0, Math.round(full.length * Math.max(0, Math.min(1, p))));
  },
  // Corre fn(t) sobre un tramo del timeline con el tiempo local del tramo.
  drive(tl, at, dur, fn) {
    const o = { t: 0 };
    fn(0);
    tl.fromTo(o, { t: 0 }, { t: dur, duration: dur, ease: "none", immediateRender: false, onUpdate: () => fn(o.t) }, at);
  },
  // Envuelve cada palabra en un span.word y devuelve los spans.
  words(el) {
    const parts = el.textContent.trim().split(/\s+/);
    // El espacio va dentro de cada caja: entre inline-blocks el renderer a veces lo pierde.
    el.innerHTML = parts.map((w, i) => `<span class="word">${w}${i < parts.length - 1 ? "&nbsp;" : ""}</span>`).join("");
    return [...el.querySelectorAll(".word")];
  },
  // Píldora completa por ids: graba (onda y texto en vivo), procesa y vuelve a la rayita.
  pill(tl, p) {
    const q = (s) => document.querySelector(s);
    const bars = HB.bars(q(p.wave));
    const dots = p.proc ? [...q(p.proc).querySelectorAll(".dots i")] : [];
    return function record(at, dur, o = {}) {
      if (p.dash) tl.fromTo(p.dash, { opacity: 1 }, { opacity: 0, duration: 0.12, immediateRender: false }, at);
      if (!o.held) tl.fromTo(p.rec, { opacity: 0, scale: 0.6 }, { opacity: 1, scale: 1, duration: 0.35, ease: "back.out(1.4)", immediateRender: false }, at);
      HB.drive(tl, at, dur, (t) => HB.setWave(bars, t + at, o.held ? 1 : Math.min(1, t / 0.15)));
      if (o.raw) {
        tl.fromTo(p.live, { opacity: 0, scale: 0.9 }, { opacity: 1, scale: 1, duration: 0.25, ease: "expo.out", immediateRender: false }, at + 0.05);
        HB.drive(tl, at + 0.1, dur - 0.2, (t) => HB.type(q(p.livetxt), o.raw, t / (dur - 0.35)));
        tl.to(p.live, { opacity: 0, duration: 0.15, ease: "power3.in" }, at + dur);
      }
      if (o.release === false) return;
      const end = at + dur, hold = o.proc || 0.42;
      tl.to(p.rec, { opacity: 0, scale: 0.8, duration: 0.12, ease: "power3.in" }, end);
      if (p.proc) {
        tl.fromTo(p.proc, { opacity: 0, scale: 0.8 }, { opacity: 1, scale: 1, duration: 0.15, ease: "expo.out", immediateRender: false }, end + 0.04);
        HB.drive(tl, end, hold + 0.1, (t) => dots.forEach((d, i) => (d.style.opacity = 0.35 + 0.65 * Math.max(0, Math.sin(t * 12 - i * 0.7)))));
        tl.to(p.proc, { opacity: 0, scale: 0.8, duration: 0.12, ease: "power3.in" }, end + hold);
      }
      if (p.dash && o.dash !== false) tl.to(p.dash, { opacity: 1, duration: 0.15 }, end + hold + 0.05);
    };
  },
};
