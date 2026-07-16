/**
 * Impact Quest v0.11.2 — Shared Animation Layer
 * Scroll-reveal, mouse-tracked tilt, and an ambient ember particle field
 * (opt-in via an empty <div id="ember-field"> in a position:relative
 * container). Include on any page with a plain <script src="animations.js">
 * tag; it self-initializes and needs no other wiring. Fully respects
 * prefers-reduced-motion — JS-driven motion checks matchMedia directly,
 * since the global CSS reduced-motion rule can't stop a requestAnimationFrame
 * loop or a per-frame inline transform.
 */
(function () {
  "use strict";

  const reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---------- Scroll reveal ----------
  function initScrollReveal() {
    const selector = [
      ".glass-card", ".card-glass", ".quest-card", ".pillar-card", ".journey-card",
      ".profile-card", ".stat-card", ".card-achievement", ".card-reward",
      ".quest-form", ".empty-state", ".organizer-card", ".featured-quest",
    ].join(", ");
    const els = Array.from(document.querySelectorAll(selector));
    if (!els.length) return;

    if (reduceMotion || !("IntersectionObserver" in window)) {
      els.forEach((el) => el.classList.add("reveal-visible"));
      return;
    }

    els.forEach((el) => el.classList.add("reveal"));
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("reveal-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -40px 0px" }
    );
    els.forEach((el) => observer.observe(el));
  }

  // ---------- Tilt effect ----------
  function initTilt() {
    if (reduceMotion) return;
    document.querySelectorAll(".tilt-effect").forEach((el) => {
      el.addEventListener("mousemove", (e) => {
        const rect = el.getBoundingClientRect();
        const x = (e.clientX - rect.left) / rect.width - 0.5;
        const y = (e.clientY - rect.top) / rect.height - 0.5;
        el.style.transform = `perspective(800px) rotateX(${(-y * 8).toFixed(2)}deg) rotateY(${(x * 8).toFixed(2)}deg) translateY(-4px)`;
      });
      el.addEventListener("mouseleave", () => {
        el.style.transform = "";
      });
    });
  }

  // ---------- Ambient ember field ----------
  function initEmberField() {
    const container = document.getElementById("ember-field");
    if (!container || reduceMotion) return;

    const canvas = document.createElement("canvas");
    canvas.setAttribute("aria-hidden", "true");
    container.appendChild(canvas);
    const ctx = canvas.getContext("2d");
    let width, height, embers;

    function resize() {
      width = canvas.width = container.clientWidth;
      height = canvas.height = container.clientHeight;
    }

    function Ember() {
      this.reset();
    }
    Ember.prototype.reset = function () {
      this.x = Math.random() * width;
      this.y = height + Math.random() * 40;
      this.vy = -(Math.random() * 0.4 + 0.15);
      this.vx = (Math.random() - 0.5) * 0.2;
      this.size = Math.random() * 2 + 0.6;
      this.opacity = Math.random() * 0.5 + 0.2;
      this.flicker = Math.random() * Math.PI * 2;
    };
    Ember.prototype.update = function () {
      this.y += this.vy;
      this.x += this.vx + Math.sin(this.flicker) * 0.1;
      this.flicker += 0.03;
      if (this.y < -20) this.reset();
    };
    Ember.prototype.draw = function () {
      ctx.beginPath();
      ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2);
      const glow = 0.5 + 0.5 * Math.sin(this.flicker);
      ctx.fillStyle = `rgba(232,197,90,${(this.opacity * glow).toFixed(2)})`;
      ctx.fill();
    };

    resize();
    if (width <= 0 || height <= 0) return; // container not laid out yet / hidden
    embers = Array.from({ length: Math.min(40, Math.max(8, Math.floor(width / 24))) }, () => new Ember());
    window.addEventListener("resize", resize);

    let frameId;
    function frame() {
      ctx.clearRect(0, 0, width, height);
      embers.forEach((e) => {
        e.update();
        e.draw();
      });
      frameId = requestAnimationFrame(frame);
    }
    frame();

    document.addEventListener("visibilitychange", () => {
      if (document.hidden) cancelAnimationFrame(frameId);
      else frame();
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    initScrollReveal();
    initTilt();
    initEmberField();
  });
})();
