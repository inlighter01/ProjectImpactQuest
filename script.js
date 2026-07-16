/* ============================================================
   IMPACT QUEST — MASTER SCRIPT (v0.5.1 Consolidation)
   v0.2.0 landing page logic + v0.3.0 design-system demo logic.
   ============================================================ */

/**
 * Impact Quest – Project Lighthouse v0.2.0
 * Cinematic intro, live activity feed, journey selection, map, enhanced interactions,
 * and a placeholder SoundManager for future use.
 */

document.addEventListener('DOMContentLoaded', () => {

  // ---------- Sound Manager Placeholder ----------
  class SoundManager {
    constructor() {
      this.sounds = {};
      this.enabled = false; // will be toggled by user preferences later
    }

    /**
     * Register a sound effect (no audio yet)
     * @param {string} name - e.g., 'questAccepted', 'achievement'
     * @param {string} src - future audio file path
     */
    register(name, src) {
      // Placeholder: In production, load an Audio object
      this.sounds[name] = { src, loaded: false };
    }

    /**
     * Play a registered sound if enabled
     * @param {string} name
     */
    play(name) {
      if (!this.enabled) return;
      const sound = this.sounds[name];
      if (sound && sound.loaded) {
        // Future: sound.audio.play()
        console.log(`[Sound] Playing ${name}`);
      }
    }

    /**
     * Enable/disable sound
     */
    toggle(enabled) {
      this.enabled = enabled;
    }
  }

  // Instantiate globally for future integration
  window.ImpactQuestSound = new SoundManager();
  // Pre-register future sound effects
  window.ImpactQuestSound.register('questAccepted', 'assets/sounds/quest-accepted.mp3');
  window.ImpactQuestSound.register('questCompleted', 'assets/sounds/quest-completed.mp3');
  window.ImpactQuestSound.register('achievement', 'assets/sounds/achievement.mp3');
  window.ImpactQuestSound.register('notification', 'assets/sounds/notification.mp3');
  window.ImpactQuestSound.register('levelUp', 'assets/sounds/level-up.mp3');

  // ---------- Cinematic Intro ----------
  const intro = document.getElementById('cinematic-intro');
  const introCanvas = document.getElementById('intro-canvas');
  const mainContent = document.getElementById('main-content');
  const skipBtn = document.getElementById('skip-intro');
  const msg1 = document.getElementById('intro-msg-1');
  const msg2 = document.getElementById('intro-msg-2');
  const final = document.getElementById('intro-final');

  // Check if user has visited before (localStorage)
  const hasVisited = localStorage.getItem('iq_intro_seen');
  if (hasVisited) {
    // Skip intro entirely
    intro.classList.add('cinematic-intro--hidden');
    mainContent.setAttribute('aria-hidden', 'false');
    mainContent.classList.add('main-content--visible');
    initTypewriter();
    initAfterIntro();
  } else {
    // Run intro sequence
    runIntro();
  }

  function runIntro() {
    // Canvas particles with connection lines
    const ctx = introCanvas.getContext('2d');
    let width, height;
    const particles = [];
    const maxParticles = 80;
    const connectionDistance = 100;

    function resizeIntroCanvas() {
      width = introCanvas.width = window.innerWidth;
      height = introCanvas.height = window.innerHeight;
    }
    window.addEventListener('resize', resizeIntroCanvas);
    resizeIntroCanvas();

    // Particle class
    class IntroParticle {
      constructor() {
        this.reset();
      }
      reset() {
        this.x = Math.random() * width;
        this.y = Math.random() * height;
        this.vx = (Math.random() - 0.5) * 0.6;
        this.vy = (Math.random() - 0.5) * 0.6;
        this.size = Math.random() * 3 + 1;
        this.opacity = Math.random() * 0.5 + 0.2;
      }
      update() {
        this.x += this.vx;
        this.y += this.vy;
        if (this.x < 0 || this.x > width) this.vx *= -1;
        if (this.y < 0 || this.y > height) this.vy *= -1;
      }
      draw() {
        ctx.beginPath();
        ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(201,162,39,${this.opacity})`;
        ctx.fill();
      }
    }

    // Init particles
    for (let i = 0; i < maxParticles; i++) {
      particles.push(new IntroParticle());
    }

    function drawConnections() {
      for (let i = 0; i < particles.length; i++) {
        for (let j = i + 1; j < particles.length; j++) {
          const dx = particles[i].x - particles[j].x;
          const dy = particles[i].y - particles[j].y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist < connectionDistance) {
            ctx.beginPath();
            ctx.moveTo(particles[i].x, particles[i].y);
            ctx.lineTo(particles[j].x, particles[j].y);
            ctx.strokeStyle = `rgba(201,162,39,${0.15 * (1 - dist / connectionDistance)})`;
            ctx.lineWidth = 0.5;
            ctx.stroke();
          }
        }
      }
    }

    function animateIntroCanvas() {
      if (intro.classList.contains('cinematic-intro--hidden')) return;
      ctx.clearRect(0, 0, width, height);
      particles.forEach(p => { p.update(); p.draw(); });
      drawConnections();
      requestAnimationFrame(animateIntroCanvas);
    }
    animateIntroCanvas();

    // Text sequence
    setTimeout(() => {
      msg1.classList.add('visible');
    }, 1000);

    setTimeout(() => {
      msg1.classList.remove('visible');
      setTimeout(() => {
        msg2.classList.add('visible');
      }, 400);
    }, 3500);

    setTimeout(() => {
      msg2.classList.remove('visible');
      setTimeout(() => {
        final.classList.add('visible');
        // After showing final, auto-fade after 2 seconds
        setTimeout(() => {
          endIntro();
        }, 2500);
      }, 400);
    }, 6500);

    // Skip button click
    skipBtn.addEventListener('click', endIntro);
  }

  function endIntro() {
    intro.classList.add('cinematic-intro--hidden');
    mainContent.setAttribute('aria-hidden', 'false');
    mainContent.classList.add('main-content--visible');
    // Mark as visited
    localStorage.setItem('iq_intro_seen', 'true');
    // Clean up canvas animation (will stop via check)
    initTypewriter();
    initAfterIntro();
  }

  // ---------- Typewriter Effect (unchanged) ----------
  function initTypewriter() {
    const el = document.querySelector('.typewriter');
    if (!el) return;
    const text = el.getAttribute('data-text') || '';
    el.textContent = '';
    let i = 0;
    const speed = 40;
    function type() {
      if (i < text.length) {
        el.textContent += text.charAt(i);
        i++;
        setTimeout(type, speed);
      }
    }
    type();
  }

  // ---------- After Intro Initializations ----------
  function initAfterIntro() {
    // Quest Demo (unchanged)
    const startDemoBtn = document.getElementById('start-quest-demo');
    const questDemoSection = document.getElementById('quest-demo');
    const closeDemoBtn = questDemoSection.querySelector('.quest-demo__close');
    const prevBtn = document.getElementById('prev-step');
    const nextBtn = document.getElementById('next-step');
    const steps = document.querySelectorAll('.step');
    const progressFill = document.querySelector('.progress-bar__fill');
    let currentStep = 1;
    const totalSteps = steps.length;

    function updateDemoUI() {
      steps.forEach(s => s.classList.remove('step--active'));
      document.querySelector(`.step[data-step="${currentStep}"]`).classList.add('step--active');
      progressFill.style.width = `${(currentStep / totalSteps) * 100}%`;
      prevBtn.disabled = currentStep === 1;
      nextBtn.textContent = currentStep === totalSteps ? 'Finish' : 'Next Step →';
    }

    startDemoBtn.addEventListener('click', () => {
      questDemoSection.classList.remove('hidden');
      questDemoSection.scrollIntoView({ behavior: 'smooth', block: 'center' });
      updateDemoUI();
    });

    closeDemoBtn.addEventListener('click', () => questDemoSection.classList.add('hidden'));
    prevBtn.addEventListener('click', () => { if (currentStep > 1) { currentStep--; updateDemoUI(); } });
    nextBtn.addEventListener('click', () => {
      if (currentStep < totalSteps) { currentStep++; updateDemoUI(); }
      else { questDemoSection.classList.add('hidden'); }
    });

    // Community Impact Counters (unchanged)
    const counterItems = document.querySelectorAll('.impact__item');
    const counterObserver = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          startCounter(entry.target);
          counterObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.5 });
    counterItems.forEach(item => counterObserver.observe(item));

    function startCounter(item) {
      const numberSpan = item.querySelector('.impact__number');
      const target = parseInt(numberSpan.getAttribute('data-target'), 10);
      if (isNaN(target)) return;
      let current = 0;
      const duration = 2000;
      const stepTime = 20;
      const increment = target / (duration / stepTime);
      const timer = setInterval(() => {
        current += increment;
        if (current >= target) {
          numberSpan.textContent = target.toLocaleString();
          clearInterval(timer);
          liveUpdate(numberSpan, target);
        } else {
          numberSpan.textContent = Math.floor(current).toLocaleString();
        }
      }, stepTime);
    }

    function liveUpdate(span, base) {
      setInterval(() => {
        const increase = Math.floor(Math.random() * 5) + 1;
        const currentVal = parseInt(span.textContent.replace(/,/g, ''), 10);
        if (!isNaN(currentVal)) {
          span.textContent = (currentVal + increase).toLocaleString();
          span.classList.add('pulse');
          setTimeout(() => span.classList.remove('pulse'), 300);
        }
      }, Math.random() * 7000 + 8000);
    }

    // Live Activity Feed (placeholder data)
    const feedContainer = document.getElementById('activity-feed');
    const activities = [
      { icon: '🌳', name: 'Maria', action: 'completed Tree Planting', time: 'Just now' },
      { icon: '🍱', name: 'John', action: 'donated meals', time: '2 minutes ago' },
      { icon: '📚', name: 'Anna', action: 'mentored a student', time: '1 hour ago' },
      { icon: '🐶', name: 'Kevin', action: 'rescued an animal', time: '3 hours ago' },
      { icon: '❤️', name: 'Sarah', action: 'donated blood', time: '5 hours ago' },
    ];

    activities.forEach(act => {
      const item = document.createElement('div');
      item.className = 'activity-item';
      item.innerHTML = `
        <span class="activity-item__icon">${act.icon}</span>
        <span class="activity-item__text">
          <span class="activity-item__name">${act.name}</span>
          <span class="activity-item__action">${act.action}</span>
        </span>
        <span class="activity-item__time">${act.time}</span>
      `;
      feedContainer.appendChild(item);
    });

    // Choose Your Journey – open modal with placeholder
    const journeyCards = document.querySelectorAll('.journey-card');
    const modal = document.getElementById('auth-modal');
    const closeModalBtn = modal.querySelector('.modal__close');
    const closeModalBtn2 = modal.querySelector('.modal__close-btn');

    function openModal(role) {
      const title = modal.querySelector('h2');
      title.textContent = role === 'helper' ? 'You want to help' :
                          role === 'seeker' ? 'You need support' :
                          'Welcome, Organization';
      modal.classList.remove('hidden');
    }

    journeyCards.forEach(card => {
      card.addEventListener('click', () => {
        const role = card.getAttribute('data-role');
        openModal(role);
      });
    });

    [closeModalBtn, closeModalBtn2].forEach(btn => {
      if (btn) btn.addEventListener('click', () => modal.classList.add('hidden'));
    });
    modal.addEventListener('click', (e) => {
      if (e.target === modal) modal.classList.add('hidden');
    });

    // Scroll-triggered animations (unchanged)
    const animatedElements = document.querySelectorAll(
      '.impact__item, .pillar-card, .philosophy__quote, .mission__text, .story__content, .map__container, .journey-card'
    );
    const scrollObserver = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          scrollObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.2 });
    animatedElements.forEach(el => {
      el.classList.add('animate-on-scroll');
      scrollObserver.observe(el);
    });

    // Smooth scroll for anchor links (unchanged)
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
      anchor.addEventListener('click', function(e) {
        const targetId = this.getAttribute('href');
        if (targetId === '#') return;
        const targetElement = document.querySelector(targetId);
        if (targetElement) {
          e.preventDefault();
          targetElement.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
      });
    });
  }
});
/* ---------- Additions from v0.3.0 (Design System demos) ---------- */

// ---------- Global Toast Function (used by components.html) ----------
function showToast(type, message) {
  const container = document.getElementById('toast-container');
  if (!container) return;
  const toast = document.createElement('div');
  toast.className = `toast toast--${type}`;
  toast.textContent = message;
  container.appendChild(toast);
  // Auto-remove after animation
  setTimeout(() => {
    if (toast.parentNode) toast.parentNode.removeChild(toast);
  }, 3000);
}

// Expose to global scope for inline onclick in components.html
window.showToast = showToast;

// ---------- Components Page Demo Logic (runs only if on that page) ----------
if (document.querySelector('.component-page')) {
  // Dialog demo
  const openDialog = document.getElementById('open-dialog');
  const demoDialog = document.getElementById('demo-dialog');
  if (openDialog && demoDialog) {
    openDialog.addEventListener('click', () => {
      demoDialog.classList.remove('hidden');
    });
    demoDialog.querySelectorAll('.modal__close-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        demoDialog.classList.add('hidden');
      });
    });
    // Close on backdrop click
    demoDialog.addEventListener('click', (e) => {
      if (e.target === demoDialog) demoDialog.classList.add('hidden');
    });
  }

  // Password visibility toggle demo
  const togglePassword = document.querySelector('.input-icon-toggle');
  if (togglePassword) {
    togglePassword.addEventListener('click', () => {
      const input = document.getElementById('password');
      const type = input.getAttribute('type') === 'password' ? 'text' : 'password';
      input.setAttribute('type', type);
      togglePassword.textContent = type === 'password' ? '👁️' : '🙈';
    });
  }
}