(function () {
  "use strict";

  // ---------- Config ----------
  const LANES = 5;
  const RACE_TIME = 60;          // seconds to reach the finish line
  const FINISH_DISTANCE = 13000; // arbitrary distance units
  const ROAD_LENGTH = 260;       // "distance" a car covers between horizon and player row

  const BASE_SPEED_START = 150;
  const BASE_SPEED_RAMP = 3.2;   // added to base speed per second of race time
  const BASE_SPEED_MAX = 340;

  const COLLISION_PENALTY_MULT = 0.22;
  const COLLISION_RECOVER_TIME = 1.7;
  const BOOST_MULT = 1.28;
  const BOOST_TIME = 1.4;
  const TURBO_MULT = 1.9;
  const TURBO_GAUGE_MAX = 100;
  const TURBO_GAIN_PER_COIN = 20;
  const TURBO_DRAIN_PER_SEC = TURBO_GAUGE_MAX / 4.2; // turbo lasts ~4.2s

  const DANGER_ZONE = [0.83, 0.97];
  const COLLIDE_AT = 0.97;
  const PASS_AT = 1.08;   // logic cutoff: "has this obstacle been passed without hitting"
  const REMOVE_AT = 1.6;  // render cutoff: far enough past the player to be fully off-screen
  const FINISH_REVEAL_RANGE = ROAD_LENGTH * 2.5; // how early the finish tape scrolls into view

  const LANE_CHANGE_TIME = 0.14; // seconds to visually slide one lane over

  // ---------- Canvas / DOM ----------
  const canvas = document.getElementById("game");
  const ctx = canvas.getContext("2d");
  const el = {
    timer: document.getElementById("timerBox"),
    coin: document.getElementById("coinBox"),
    progressFill: document.getElementById("progressFill"),
    playerMarker: document.getElementById("playerMarker"),
    turboFill: document.getElementById("turboGaugeFill"),
    turboBanner: document.getElementById("turboBanner"),
    combo: document.getElementById("comboPopup"),
    overlay: document.getElementById("overlay"),
    overlayTitle: document.getElementById("overlayTitle"),
    overlaySubtitle: document.getElementById("overlaySubtitle"),
    overlayButton: document.getElementById("overlayButton"),
    overlayStats: document.getElementById("overlayStats"),
    btnLeft: document.getElementById("btnLeft"),
    btnRight: document.getElementById("btnRight"),
  };

  let W = 0, H = 0, DPR = 1;
  function resize() {
    DPR = Math.min(window.devicePixelRatio || 1, 2);
    W = canvas.parentElement.clientWidth;
    H = canvas.parentElement.clientHeight;
    canvas.style.width = W + "px";
    canvas.style.height = H + "px";
    canvas.width = Math.round(W * DPR);
    canvas.height = Math.round(H * DPR);
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  }
  window.addEventListener("resize", resize);

  // ---------- Helpers ----------
  const lerp = (a, b, t) => a + (b - a) * t;
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const easeP = (p) => Math.pow(clamp(p, 0, 2), 1.35);

  function horizonY() { return H * 0.14; }
  function playerRowY() { return H * 0.80; }
  function centerX() { return W * 0.5; }
  function halfWidthAt(p) {
    const topHalf = W * 0.10;
    const botHalf = W * 0.44;
    return lerp(topHalf, botHalf, easeP(p));
  }
  function laneFraction(laneIndex) {
    return (laneIndex - (LANES - 1) / 2) / ((LANES - 1) / 2);
  }
  function laneX(laneIndex, p) {
    return centerX() + laneFraction(laneIndex) * halfWidthAt(p);
  }
  function rowY(p) {
    return lerp(horizonY(), playerRowY(), easeP(p));
  }
  function scaleAt(p) {
    return lerp(0.28, 1.0, easeP(p));
  }

  // ---------- Game State ----------
  const STATE = { READY: "ready", PLAYING: "playing", WIN: "win", LOSE: "lose" };

  const game = {
    state: STATE.READY,
    time: 0,
    distance: 0,
    coins: 0,
    combo: 0,
    bestCombo: 0,
    playerLane: Math.floor((LANES - 1) / 2),
    playerLaneVisual: Math.floor((LANES - 1) / 2),
    laneAnimT: 1,
    laneAnimFrom: Math.floor((LANES - 1) / 2),
    turboGauge: 0,
    isTurbo: false,
    invincible: false,
    penaltyT: 0,     // remaining time of collision penalty recovery
    boostT: 0,       // remaining time of near-miss boost
    hitFlash: 0,
    winFlash: 0,
    roadScroll: 0,
    obstacles: [],
    coinsList: [],
    obstacleTimer: 0,
    coinTimer: 0,
  };
  window.__game = game; // debug hook for automated testing

  function resetGame() {
    game.state = STATE.PLAYING;
    game.time = 0;
    game.distance = 0;
    game.coins = 0;
    game.combo = 0;
    game.bestCombo = 0;
    game.playerLane = Math.floor((LANES - 1) / 2);
    game.playerLaneVisual = game.playerLane;
    game.laneAnimFrom = game.playerLane;
    game.laneAnimT = 1;
    game.turboGauge = 0;
    game.isTurbo = false;
    game.invincible = false;
    game.penaltyT = 0;
    game.boostT = 0;
    game.hitFlash = 0;
    game.winFlash = 0;
    game.roadScroll = 0;
    game.obstacles = [];
    game.coinsList = [];
    game.obstacleTimer = 0.6;
    game.coinTimer = 0.9;
    el.overlay.classList.add("hidden");
  }

  function baseSpeed() {
    return Math.min(BASE_SPEED_MAX, BASE_SPEED_START + BASE_SPEED_RAMP * game.time);
  }

  function currentSpeed() {
    let mult = 1;
    if (game.penaltyT > 0) {
      const t = 1 - game.penaltyT / COLLISION_RECOVER_TIME;
      mult *= lerp(COLLISION_PENALTY_MULT, 1, clamp(t, 0, 1));
    }
    if (game.boostT > 0) mult *= BOOST_MULT;
    if (game.isTurbo) mult *= TURBO_MULT;
    return baseSpeed() * mult;
  }

  function popupCombo(text, cls) {
    el.combo.textContent = text;
    el.combo.className = "show" + (cls ? " " + cls : "");
    clearTimeout(popupCombo._t);
    popupCombo._t = setTimeout(() => { el.combo.className = ""; }, 650);
  }

  // ---------- Input ----------
  let laneChangeLock = 0;
  function trySwerve(dir) {
    if (game.state !== STATE.PLAYING) return;
    const now = performance.now();
    if (now < laneChangeLock) return;
    laneChangeLock = now + 90;
    const target = clamp(game.playerLane + dir, 0, LANES - 1);
    if (target === game.playerLane) return;

    checkNearMissOnLeave(game.playerLane);

    game.laneAnimFrom = game.playerLaneVisual;
    game.playerLane = target;
    game.laneAnimT = 0;
  }

  function checkNearMissOnLeave(fromLane) {
    for (const o of game.obstacles) {
      if (o.resolved) continue;
      if (o.lane === fromLane && o.p >= DANGER_ZONE[0] && o.p < COLLIDE_AT) {
        o.dodged = true;
      }
    }
  }

  window.addEventListener("keydown", (e) => {
    if (e.key === "ArrowLeft" || e.key === "a" || e.key === "A") trySwerve(-1);
    if (e.key === "ArrowRight" || e.key === "d" || e.key === "D") trySwerve(1);
    if (e.key === " " || e.key === "Enter") {
      if (game.state !== STATE.PLAYING) resetGame();
    }
  });

  // Bind both pointerdown (low latency) and click (broad compatibility -
  // some mobile browsers/webviews handle Pointer Events unreliably). If a
  // single tap fires both, trySwerve's own lock (and resetGame's
  // idempotence) makes the duplicate harmless.
  function bindTap(elm, fn) {
    elm.addEventListener("pointerdown", (ev) => { ev.preventDefault(); fn(); });
    elm.addEventListener("click", (ev) => { ev.preventDefault(); fn(); });
  }
  bindTap(el.btnLeft, () => trySwerve(-1));
  bindTap(el.btnRight, () => trySwerve(1));
  bindTap(el.overlayButton, () => resetGame());

  // ---------- Spawning ----------
  function spawnObstacleWave() {
    const t = game.time;
    const openLanes = t < 8 ? LANES - 1 : t < 20 ? LANES - 2 : LANES - 2;
    let count = t < 8 ? 1 : t < 20 ? (Math.random() < 0.6 ? 1 : 2) : (Math.random() < 0.5 ? 2 : 3);
    count = clamp(count, 1, LANES - Math.max(1, LANES - openLanes));
    count = Math.min(count, LANES - 1);

    const lanes = [...Array(LANES).keys()];
    for (let i = lanes.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [lanes[i], lanes[j]] = [lanes[j], lanes[i]];
    }
    const chosen = lanes.slice(0, count);
    for (const lane of chosen) {
      game.obstacles.push({ lane, p: 0, resolved: false, dodged: false, kind: "car" });
    }
  }

  function spawnCoins() {
    const lane = Math.floor(Math.random() * LANES);
    const runLen = 1 + Math.floor(Math.random() * 3);
    for (let i = 0; i < runLen; i++) {
      game.coinsList.push({ lane, p: -i * 0.06, collected: false });
    }
  }

  // ---------- Update ----------
  function update(dt) {
    if (game.state !== STATE.PLAYING) return;

    game.time += dt;

    // lane slide animation
    if (game.laneAnimT < 1) {
      game.laneAnimT = clamp(game.laneAnimT + dt / LANE_CHANGE_TIME, 0, 1);
      game.playerLaneVisual = lerp(game.laneAnimFrom, game.playerLane, game.laneAnimT);
    }

    if (game.penaltyT > 0) game.penaltyT = Math.max(0, game.penaltyT - dt);
    if (game.boostT > 0) game.boostT = Math.max(0, game.boostT - dt);

    if (game.isTurbo) {
      game.turboGauge = Math.max(0, game.turboGauge - TURBO_DRAIN_PER_SEC * dt);
      if (game.turboGauge <= 0) {
        game.isTurbo = false;
        game.invincible = false;
        game.turboGauge = 0;
      }
    }

    const speed = currentSpeed();
    game.distance += speed * dt;
    const dp = (speed / ROAD_LENGTH) * dt;
    game.roadScroll += speed * dt;

    // obstacles
    for (const o of game.obstacles) {
      // Position always advances, even once resolved (hit or passed) -
      // otherwise a resolved car freezes in place forever instead of
      // continuing off-screen, and never becomes eligible for removal.
      o.p += dp;
      if (o.resolved) continue;

      if (o.lane === game.playerLane && o.p >= DANGER_ZONE[0] && o.p < COLLIDE_AT) {
        o.wasNear = true;
      }

      if (!o.resolved && o.p >= COLLIDE_AT && o.lane === game.playerLane) {
        if (game.invincible) {
          o.resolved = true;
        } else {
          o.resolved = true;
          game.penaltyT = COLLISION_RECOVER_TIME;
          game.boostT = 0;
          game.combo = 0;
          game.hitFlash = 0.25;
          popupCombo("HIT!", "danger");
        }
      } else if (!o.resolved && o.p >= PASS_AT) {
        o.resolved = true;
        if (o.dodged || o.wasNear) {
          game.boostT = BOOST_TIME;
          game.combo += 1;
          game.bestCombo = Math.max(game.bestCombo, game.combo);
          popupCombo(`NICE! x${game.combo}`, "");
        }
      }
    }
    game.obstacles = game.obstacles.filter((o) => o.p < REMOVE_AT);

    // coins
    for (const c of game.coinsList) {
      if (c.collected) continue;
      c.p += dp;
      if (c.lane === game.playerLane && c.p >= DANGER_ZONE[0] && c.p < COLLIDE_AT + 0.05) {
        c.collected = true;
        game.coins += 1;
        if (!game.isTurbo) {
          game.turboGauge = Math.min(TURBO_GAUGE_MAX, game.turboGauge + TURBO_GAIN_PER_COIN);
          if (game.turboGauge >= TURBO_GAUGE_MAX) {
            game.isTurbo = true;
            game.invincible = true;
            popupCombo("TURBO!", "turbo");
          }
        }
      }
    }
    game.coinsList = game.coinsList.filter((c) => !c.collected && c.p < REMOVE_AT);

    // spawning with difficulty ramp
    game.obstacleTimer -= dt;
    if (game.obstacleTimer <= 0) {
      spawnObstacleWave();
      const t = game.time;
      const interval = t < 8 ? 1.3 : t < 20 ? 1.0 : t < 40 ? 0.78 : 0.6;
      game.obstacleTimer = interval * (0.85 + Math.random() * 0.3);
    }
    game.coinTimer -= dt;
    if (game.coinTimer <= 0) {
      spawnCoins();
      game.coinTimer = 1.6 + Math.random() * 1.2;
    }

    if (game.hitFlash > 0) game.hitFlash = Math.max(0, game.hitFlash - dt);
    if (game.winFlash > 0) game.winFlash = Math.max(0, game.winFlash - dt);

    // win/lose
    if (game.distance >= FINISH_DISTANCE) {
      game.state = STATE.WIN;
      game.winFlash = 0.5;
      showEndScreen(true);
    } else if (game.time >= RACE_TIME) {
      game.state = STATE.LOSE;
      showEndScreen(false);
    }
  }

  function showEndScreen(won) {
    el.overlay.classList.remove("hidden");
    el.overlayTitle.textContent = won ? "FINISH!" : "TIME UP";
    el.overlaySubtitle.textContent = won
      ? "You crossed the finish line in time."
      : "You didn't reach the finish line before the clock ran out.";
    el.overlayButton.textContent = "PLAY AGAIN";
    const timeUsed = Math.min(game.time, RACE_TIME).toFixed(1);
    el.overlayStats.textContent =
      `Time: ${timeUsed}s\nDistance: ${Math.floor(game.distance)} / ${FINISH_DISTANCE}\n` +
      `Coins: ${game.coins}\nBest Combo: x${game.bestCombo}`;
  }

  // ---------- Render ----------
  function drawRoad() {
    ctx.fillStyle = "#0b1220";
    ctx.fillRect(0, 0, W, H);

    // sky
    const skyGrad = ctx.createLinearGradient(0, 0, 0, horizonY());
    skyGrad.addColorStop(0, "#1c2b4a");
    skyGrad.addColorStop(1, "#3a5a86");
    ctx.fillStyle = skyGrad;
    ctx.fillRect(0, 0, W, horizonY());

    // road trapezoid
    const hy = horizonY(), py = playerRowY();
    const topL = laneX(-0.5, 0), topR = laneX(LANES - 0.5, 0);
    const botL = centerX() - halfWidthAt(1) * (1 + 1 / (LANES - 1));
    const botR = centerX() + halfWidthAt(1) * (1 + 1 / (LANES - 1));

    ctx.fillStyle = "#33394a";
    ctx.beginPath();
    ctx.moveTo(centerX() - halfWidthAt(0) * (1 + 1 / (LANES - 1)), hy);
    ctx.lineTo(centerX() + halfWidthAt(0) * (1 + 1 / (LANES - 1)), hy);
    ctx.lineTo(botR, H);
    ctx.lineTo(botL, H);
    ctx.closePath();
    ctx.fill();

    // lane dividers (scrolling dash gives a sense of forward speed)
    ctx.strokeStyle = "rgba(255,255,255,0.55)";
    ctx.setLineDash([14, 16]);
    ctx.lineDashOffset = -(game.roadScroll % 30);
    for (let i = 1; i < LANES; i++) {
      const frac = laneFraction(i - 0.5);
      ctx.lineWidth = lerp(1, 3, easeP(1));
      ctx.beginPath();
      ctx.moveTo(centerX() + frac * halfWidthAt(0), hy);
      ctx.lineTo(centerX() + frac * halfWidthAt(1), H);
      ctx.stroke();
    }
    ctx.setLineDash([]);
    ctx.lineDashOffset = 0;

    // edges
    ctx.strokeStyle = "#ffcc33";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(centerX() - halfWidthAt(0) * (1 + 1 / (LANES - 1)), hy);
    ctx.lineTo(botL, H);
    ctx.moveTo(centerX() + halfWidthAt(0) * (1 + 1 / (LANES - 1)), hy);
    ctx.lineTo(botR, H);
    ctx.stroke();
  }

  function drawCar(x, y, scale, color, flip) {
    const w = 46 * scale, h = 74 * scale;
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = "rgba(0,0,0,0.35)";
    ctx.beginPath();
    ctx.ellipse(0, h * 0.42, w * 0.55, h * 0.14, 0, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = color;
    roundRect(-w / 2, -h / 2, w, h, w * 0.28);
    ctx.fill();

    ctx.fillStyle = "rgba(255,255,255,0.85)";
    roundRect(-w / 2 + w * 0.14, -h / 2 + h * 0.18, w * 0.72, h * 0.32, w * 0.16);
    ctx.fill();

    ctx.fillStyle = "#ffe066";
    ctx.fillRect(-w / 2 + w * 0.08, -h / 2 - 2, w * 0.18, 5 * scale);
    ctx.fillRect(w / 2 - w * 0.26, -h / 2 - 2, w * 0.18, 5 * scale);
    ctx.restore();
  }

  function roundRect(x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  function drawCoin(x, y, scale) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = "#ffd93d";
    ctx.strokeStyle = "#b8860b";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(0, 0, 13 * scale, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = "#b8860b";
    ctx.font = `${12 * scale}px sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText("$", 0, 1);
    ctx.restore();
  }

  function drawFinishTape(p) {
    const y = rowY(p);
    const scale = scaleAt(p);
    const hw = halfWidthAt(p) * (1 + 1 / (LANES - 1));
    const bandH = 24 * scale;
    const poleW = 6 * scale;
    const poleH = bandH * 2.6;

    ctx.save();
    ctx.fillStyle = "#c02c46";
    ctx.fillRect(centerX() - hw - poleW, y - poleH, poleW, poleH);
    ctx.fillRect(centerX() + hw, y - poleH, poleW, poleH);

    const cols = 16;
    const cw = (hw * 2) / cols;
    for (let i = 0; i < cols; i++) {
      ctx.fillStyle = i % 2 === 0 ? "#111318" : "#f5f5f5";
      ctx.fillRect(centerX() - hw + i * cw, y - bandH, cw, bandH);
    }
    ctx.strokeStyle = "rgba(0,0,0,0.5)";
    ctx.lineWidth = 2 * scale;
    ctx.strokeRect(centerX() - hw, y - bandH, hw * 2, bandH);

    ctx.fillStyle = "#fff";
    ctx.font = `800 ${14 * scale}px sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.strokeStyle = "rgba(0,0,0,0.6)";
    ctx.lineWidth = 3 * scale;
    ctx.strokeText("FINISH", centerX(), y - bandH / 2);
    ctx.fillText("FINISH", centerX(), y - bandH / 2);
    ctx.restore();
  }

  function drawSpeedLines(t) {
    const cx = centerX(), cy = horizonY();
    ctx.save();
    ctx.strokeStyle = "rgba(255,200,120,0.5)";
    const count = 14;
    for (let i = 0; i < count; i++) {
      const angle = (i / count) * Math.PI * 2 + t * 0.6;
      const wobble = 0.85 + 0.15 * Math.sin(t * 4 + i);
      const len = Math.max(W, H) * 0.75 * wobble;
      const x1 = cx + Math.cos(angle) * 18;
      const y1 = cy + Math.sin(angle) * 18 * 0.4;
      const x2 = cx + Math.cos(angle) * len;
      const y2 = cy + Math.sin(angle) * len * 0.4;
      ctx.lineWidth = 2 + 2 * wobble;
      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);
      ctx.stroke();
    }
    ctx.restore();
  }

  function drawFlameTrail(x, y, scale, t) {
    const flicker = 0.7 + 0.3 * Math.sin(t * 30);
    ctx.save();
    ctx.translate(x, y + 30 * scale);
    ctx.globalAlpha = flicker;
    const grad = ctx.createLinearGradient(0, 0, 0, 36 * scale);
    grad.addColorStop(0, "#fff2c4");
    grad.addColorStop(0.4, "#ff9a1a");
    grad.addColorStop(1, "rgba(255,60,0,0)");
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.moveTo(-12 * scale, 0);
    ctx.lineTo(12 * scale, 0);
    ctx.lineTo(0, 36 * scale * flicker);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  function render() {
    drawRoad();
    const t = performance.now() / 1000;

    if (game.isTurbo) drawSpeedLines(t);

    // Everything on the road — coins, traffic, the finish tape, and the
    // player — is drawn in a single depth-sorted pass so an obstacle the
    // player has just passed (p > 1, "closer to camera" than the player)
    // correctly renders in front of the player as it exits, instead of
    // being stuck behind it near the bottom of the screen.
    const drawList = [];
    for (const c of game.coinsList) {
      if (c.p < -0.1) continue;
      drawList.push({ p: c.p, draw: () => drawCoin(laneX(c.lane, c.p), rowY(c.p), scaleAt(c.p)) });
    }
    for (const o of game.obstacles) {
      drawList.push({
        p: o.p,
        draw: () => drawCar(laneX(o.lane, o.p), rowY(o.p), scaleAt(o.p), "#4d7cff"),
      });
    }
    const remaining = FINISH_DISTANCE - game.distance;
    if (remaining <= FINISH_REVEAL_RANGE && remaining > -FINISH_REVEAL_RANGE * 0.4) {
      const finishP = 1 - remaining / FINISH_REVEAL_RANGE;
      drawList.push({ p: finishP, draw: () => drawFinishTape(finishP) });
    }

    const px = laneX(game.playerLaneVisual, 1);
    const py = playerRowY();
    const pScale = scaleAt(1) * 1.05;
    const color = game.isTurbo ? "#ff7a1a" : game.penaltyT > 0 ? "#ff4d4d" : "#ff2d55";
    drawList.push({
      p: 1.001,
      draw: () => {
        if (game.isTurbo) drawFlameTrail(px, py, pScale, t);
        drawCar(px, py, pScale, color);
      },
    });

    drawList.sort((a, b) => a.p - b.p);
    for (const item of drawList) item.draw();

    if (game.hitFlash > 0) {
      ctx.fillStyle = `rgba(255,0,0,${game.hitFlash * 0.35})`;
      ctx.fillRect(0, 0, W, H);
    }
    if (game.winFlash > 0) {
      ctx.fillStyle = `rgba(255,255,255,${game.winFlash * 0.6})`;
      ctx.fillRect(0, 0, W, H);
    }
    if (game.isTurbo) {
      const pulse = 0.5 + 0.5 * Math.sin(t * 8);
      ctx.fillStyle = `rgba(255,140,20,${0.08 + pulse * 0.05})`;
      ctx.fillRect(0, 0, W, H);

      const vignette = ctx.createRadialGradient(
        centerX(), H * 0.6, Math.min(W, H) * 0.35,
        centerX(), H * 0.6, Math.max(W, H) * 0.75
      );
      vignette.addColorStop(0, "rgba(255,120,0,0)");
      vignette.addColorStop(1, `rgba(255,90,0,${0.35 + pulse * 0.25})`);
      ctx.fillStyle = vignette;
      ctx.fillRect(0, 0, W, H);
    }
  }

  function updateHud() {
    const remaining = Math.max(0, RACE_TIME - game.time);
    el.timer.textContent = remaining.toFixed(1);
    el.timer.style.color = remaining < 10 ? "#ff4d4d" : "";
    el.coin.textContent = `🪙 ${game.coins}`;

    const pct = clamp((game.distance / FINISH_DISTANCE) * 100, 0, 100);
    el.progressFill.style.width = pct + "%";
    el.playerMarker.style.left = pct + "%";

    const gaugePct = (game.turboGauge / TURBO_GAUGE_MAX) * 100;
    el.turboFill.style.width = gaugePct + "%";
    el.turboFill.classList.toggle("ready", game.turboGauge >= TURBO_GAUGE_MAX - 0.01 && !game.isTurbo);
    el.turboBanner.classList.toggle("show", game.isTurbo);
  }

  // ---------- Main loop ----------
  let lastT = performance.now();
  function frame(now) {
    const dt = clamp((now - lastT) / 1000, 0, 0.05);
    lastT = now;
    update(dt);
    render();
    updateHud();
    requestAnimationFrame(frame);
  }

  resize();
  render();
  requestAnimationFrame(frame);
})();
