export const SITE_JS = String.raw`(() => {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const c = document.getElementById("sky");
  if (c && c.getContext) {
    const ctx = c.getContext("2d");
    const mobile = matchMedia("(pointer: coarse)").matches;
    const busyGap = mobile ? 1000 / 30 : 1000 / 60, idleGap = mobile ? 1000 / 12 : 1000 / 30;
    let gap = busyGap, lastInput = 0;
    const palette = ["#e8dcff", "#d6c2ff", "#f1dcff", "#ffd3ec", "#d2e2ff"];
    let W = 0, H = 0, stars = [], shots = [], orbs = [], sparks = [], rings = [];
    let mx = -9999, my = -9999, px = 0, py = 0, tx = 0, ty = 0, nextShot = 0, lastY = scrollY, vel = 0, last = 0, running = false;
    const sprite = (r, stops) => {
      const s = document.createElement("canvas");
      s.width = s.height = r * 2;
      const g = s.getContext("2d"), gr = g.createRadialGradient(r, r, 0, r, r, r);
      stops.forEach(([o, col]) => gr.addColorStop(o, col));
      g.fillStyle = gr;
      g.fillRect(0, 0, r * 2, r * 2);
      return s;
    };
    const glowStar = sprite(16, [[0, "rgba(255,240,255,1)"], [.14, "rgba(230,205,255,.85)"], [.4, "rgba(185,140,255,.16)"], [1, "rgba(185,140,255,0)"]]);
    const cursorGlow = sprite(200, [[0, "rgba(185,140,255,.11)"], [1, "rgba(185,140,255,0)"]]);
    const resize = () => {
      const dpr = Math.min(devicePixelRatio || 1, mobile ? 1 : 1.5);
      const nw = innerWidth, nh = Math.max(innerHeight, mobile ? screen.height : 0, document.documentElement.clientHeight);
      if (W === nw && H >= nh && stars.length) return;
      W = nw;
      H = nh;
      c.width = Math.round(W * dpr);
      c.height = Math.round(H * dpr);
      c.style.width = W + "px";
      c.style.height = H + "px";
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const n = Math.min(mobile ? 110 : 280, Math.round(W * H / 5000));
      stars = Array.from({ length: n }, () => {
        const z = Math.random() * .9 + .1, r = Math.random() * 1.3 + .25;
        return { x: Math.random() * W, y: Math.random() * H, z, r, size: r * (.6 + z * .6) * 1.7, big: r > 1.3 && z > .65, t: Math.random() * 6.28, s: Math.random() * .025 + .004, c: Math.random() * palette.length | 0, sx: 0, sy: 0 };
      });
      orbs = mobile ? [] : [270, 300, 250, 320, 285].map(hue => {
        const r = Math.round(Math.min(W, H) * (.18 + Math.random() * .16));
        return { x: Math.random() * W, y: Math.random() * H, r, ph: Math.random() * 6.28, sp: .0002 + Math.random() * .0003, img: sprite(r, [[0, "hsla(" + hue + ",90%,65%,.12)"], [1, "hsla(" + hue + ",90%,65%,0)"]]) };
      });
    };
    const burst = (x, y) => {
      for (let i = 0; i < 8; i++) {
        const a = Math.random() * 6.283, v = 1 + Math.random() * 2.2;
        sparks.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v - .5, life: 0, max: 22 + Math.random() * 14, col: "hsl(" + (260 + Math.random() * 80) + ",95%,75%)", r: 1 + Math.random() * 2 });
      }
      rings.push({ x, y, life: 0, max: 26 });
      start();
    };
    const frame = now => {
      const sy = scrollY;
      vel += ((sy - lastY) - vel) * .25;
      lastY = sy;
      const warp = Math.max(-70, Math.min(70, vel));
      const warping = Math.abs(warp) > 3;
      tx += (px - tx) * .05;
      ty += (py - ty) * .05;
      ctx.clearRect(0, 0, W, H);
      ctx.globalCompositeOperation = "lighter";
      for (const o of orbs) {
        const x = o.x + Math.sin(now * o.sp + o.ph) * 120 - tx * 60;
        const y = o.y + Math.cos(now * o.sp * 1.3 + o.ph) * 90 - ty * 60;
        ctx.drawImage(o.img, x - o.r, y - o.r);
      }
      if (mx > -999) ctx.drawImage(cursorGlow, mx - 200, my - 200);
      ctx.globalCompositeOperation = "source-over";
      for (const s of stars) {
        s.t += s.s;
        let x = ((s.x - tx * s.z * 40) % W + W) % W;
        let y = ((s.y - ty * s.z * 40 - sy * s.z * .25) % H + H) % H;
        if (mx > -999) {
          const dx = x - mx, dy = y - my, d2 = dx * dx + dy * dy;
          if (d2 < 9000) {
            const f = (1 - d2 / 9000) * 14 * s.z / (Math.sqrt(d2) || 1);
            x += dx * f;
            y += dy * f;
          }
        }
        s.sx = x;
        s.sy = y;
        ctx.globalAlpha = (.35 + .65 * Math.abs(Math.sin(s.t))) * (.35 + s.z * .65);
        if (s.big && !warping) {
          const k = s.size * 5;
          ctx.drawImage(glowStar, x - k, y - k, k * 2, k * 2);
        } else {
          ctx.fillStyle = palette[s.c];
          if (warping) ctx.fillRect(x - s.size / 2, y, s.size, warp * s.z * 1.2);
          else ctx.fillRect(x - s.size / 2, y - s.size / 2, s.size, s.size);
        }
      }
      ctx.globalAlpha = 1;
      if (mx > -999 && !warping) {
        const near = [];
        for (const s of stars) {
          if (s.z < .4) continue;
          const dx = s.sx - mx, dy = s.sy - my;
          if (dx * dx + dy * dy < 28900) {
            near.push(s);
            if (near.length > 18) break;
          }
        }
        ctx.lineWidth = .7;
        for (let i = 0; i < near.length; i++) {
          const A = near[i];
          ctx.globalAlpha = (1 - Math.hypot(A.sx - mx, A.sy - my) / 170) * .35;
          ctx.strokeStyle = "#c8a5ff";
          ctx.beginPath();
          ctx.moveTo(A.sx, A.sy);
          ctx.lineTo(mx, my);
          ctx.stroke();
          for (let j = i + 1; j < near.length; j++) {
            const B = near[j], d = Math.hypot(A.sx - B.sx, A.sy - B.sy);
            if (d < 95) {
              ctx.globalAlpha = (1 - d / 95) * .3;
              ctx.strokeStyle = "#ffaae1";
              ctx.beginPath();
              ctx.moveTo(A.sx, A.sy);
              ctx.lineTo(B.sx, B.sy);
              ctx.stroke();
            }
          }
        }
        ctx.globalAlpha = 1;
      }
      if (now > nextShot) {
        const ang = Math.PI * (.12 + Math.random() * .12), sp = 9 + Math.random() * 6;
        shots.push({ x: W * (.25 + Math.random() * .75), y: Math.random() * H * .45, vx: -Math.cos(ang) * sp, vy: Math.sin(ang) * sp, life: 0, max: 50 + Math.random() * 30 });
        nextShot = now + (mobile ? 5000 : 3000) + Math.random() * 5000;
      }
      if (shots.length) {
        shots = shots.filter(p => p.life < p.max);
        ctx.lineCap = "round";
        ctx.lineWidth = 1.6;
        for (const p of shots) {
          p.life++;
          p.x += p.vx;
          p.y += p.vy;
          const fade = 1 - p.life / p.max;
          const g = ctx.createLinearGradient(p.x, p.y, p.x - p.vx * 9, p.y - p.vy * 9);
          g.addColorStop(0, "rgba(255,235,255," + fade + ")");
          g.addColorStop(1, "rgba(185,140,255,0)");
          ctx.strokeStyle = g;
          ctx.beginPath();
          ctx.moveTo(p.x, p.y);
          ctx.lineTo(p.x - p.vx * 9, p.y - p.vy * 9);
          ctx.stroke();
          ctx.globalAlpha = fade;
          ctx.drawImage(glowStar, p.x - 6, p.y - 6, 12, 12);
          ctx.globalAlpha = 1;
        }
      }
      if (rings.length) {
        rings = rings.filter(r => r.life < r.max);
        ctx.strokeStyle = "#c8a0ff";
        for (const r of rings) {
          r.life++;
          const k = r.life / r.max;
          ctx.globalAlpha = (1 - k) * .35;
          ctx.lineWidth = 2 * (1 - k) + .5;
          ctx.beginPath();
          ctx.arc(r.x, r.y, 6 + k * 34, 0, 6.283);
          ctx.stroke();
        }
        ctx.globalAlpha = 1;
      }
      if (sparks.length) {
        sparks = sparks.filter(p => p.life < p.max);
        ctx.globalCompositeOperation = "lighter";
        for (const p of sparks) {
          p.life++;
          p.x += p.vx;
          p.y += p.vy;
          p.vx *= .97;
          p.vy = p.vy * .97 + .06;
          const f = 1 - p.life / p.max, sz = p.r * f * 1.3 + .5;
          ctx.globalAlpha = f;
          ctx.fillStyle = p.col;
          ctx.fillRect(p.x - sz / 2, p.y - sz / 2, sz, sz);
        }
        ctx.globalAlpha = 1;
        ctx.globalCompositeOperation = "source-over";
      }
    };
    const loop = now => {
      if (document.hidden) {
        running = false;
        return;
      }
      requestAnimationFrame(loop);
      gap = now - lastInput < 4000 || shots.length || sparks.length || rings.length || Math.abs(vel) > .5 ? busyGap : idleGap;
      if (now - last < gap) return;
      last = now;
      frame(now);
    };
    const start = () => {
      if (!running && !reduce) {
        running = true;
        requestAnimationFrame(loop);
      }
    };
    let rt;
    addEventListener("resize", () => {
      clearTimeout(rt);
      rt = setTimeout(() => {
        resize();
        if (reduce) frame(0);
      }, 150);
    });
    const poke = () => {
      lastInput = performance.now();
    };
    addEventListener("scroll", poke, { passive: true });
    addEventListener("pointermove", e => {
      poke();
      px = e.clientX / W - .5;
      py = e.clientY / H - .5;
      if (e.pointerType === "mouse") {
        mx = e.clientX;
        my = e.clientY;
      }
    }, { passive: true });
    document.addEventListener("pointerleave", () => {
      mx = my = -9999;
    });
    addEventListener("pointerdown", e => {
      poke();
      if (!reduce) burst(e.clientX, e.clientY);
    }, { passive: true });
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) start();
    });
    resize();
    if (reduce) frame(0);
    else start();
  }

  document.querySelectorAll(".button,form.search button,.tabs a").forEach(b => {
    b.addEventListener("pointermove", e => {
      if (e.pointerType !== "mouse") return;
      const r = b.getBoundingClientRect();
      b.style.setProperty("--bx", ((e.clientX - r.left - r.width / 2) * .25) + "px");
      b.style.setProperty("--by", ((e.clientY - r.top - r.height / 2) * .35) + "px");
    });
    b.addEventListener("pointerleave", () => {
      b.style.setProperty("--bx", "0px");
      b.style.setProperty("--by", "0px");
    });
  });

  document.querySelectorAll(".card,.section").forEach(card => card.addEventListener("pointermove", e => {
    const r = card.getBoundingClientRect();
    card.style.setProperty("--x", (e.clientX - r.left) + "px");
    card.style.setProperty("--y", (e.clientY - r.top) + "px");
  }));

  if (!reduce) {
    const glyphs = "!<>-_\\/[]{}=+*^?#$%&01";
    document.querySelectorAll(".card h3").forEach(el => {
      const host = el.closest("a") || el;
      const orig = el.textContent;
      let raf;
      host.addEventListener("pointerenter", () => {
        cancelAnimationFrame(raf);
        let f = 0;
        const step = () => {
          f++;
          const done = Math.floor(f / 2);
          el.textContent = orig.split("").map((ch, i) => i < done || ch === " " ? ch : glyphs[Math.random() * glyphs.length | 0]).join("");
          if (done < orig.length) raf = requestAnimationFrame(step);
          else el.textContent = orig;
        };
        step();
      });
    });
  }

  const reveal = [...document.querySelectorAll(".card,.section,.gallery")];
  reveal.forEach((el, i) => el.style.setProperty("--k", Math.min(i, 10)));
  if (reduce || !("IntersectionObserver" in window)) {
    reveal.forEach(el => el.classList.add("in"));
    return;
  }
  const io = new IntersectionObserver(entries => entries.forEach(e => {
    if (e.isIntersecting) {
      e.target.classList.add("in");
      io.unobserve(e.target);
    }
  }), { threshold: .08 });
  reveal.forEach(el => {
    el.classList.add("rv");
    io.observe(el);
  });
})();
`;
