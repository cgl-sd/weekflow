document.documentElement.classList.remove("no-js");
document.documentElement.classList.add("js");

const demo = document.querySelector("[data-product-demo]");

if (demo) {
  const tabs = Array.from(demo.querySelectorAll("[role='tab']"));
  const panels = Array.from(demo.querySelectorAll("[role='tabpanel']"));
  const caption = demo.querySelector("[data-demo-caption]");
  const toggle = demo.querySelector("[data-demo-toggle]");
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const messages = {
    home: "看清今天，把注意力留给眼前的一步。",
    weekly: "先定目标，再把行动分配到这一周。",
    daily: "把任务放进真实可用的工作时间。",
    focus: "进入专注，让实际投入被认真记录。",
    review: "回看完成与投入，为下一周留下依据。",
  };
  let activeIndex = 0;
  let autoplayTimer = null;
  let isPausedByUser = false;
  let isHovered = false;
  let containsFocus = false;

  function activateTab(nextIndex, moveFocus = false) {
    activeIndex = (nextIndex + tabs.length) % tabs.length;

    tabs.forEach((tab, index) => {
      const isActive = index === activeIndex;
      tab.setAttribute("aria-selected", String(isActive));
      tab.tabIndex = isActive ? 0 : -1;
      if (moveFocus && isActive) tab.focus();
    });

    panels.forEach((panel, index) => {
      const isActive = index === activeIndex;
      panel.classList.toggle("is-active", isActive);
      panel.hidden = !isActive;
    });

    const key = tabs[activeIndex].dataset.demoTab;
    if (caption && key) caption.textContent = messages[key];
  }

  function stopAutoplay() {
    if (autoplayTimer) window.clearInterval(autoplayTimer);
    autoplayTimer = null;
  }

  function startAutoplay() {
    stopAutoplay();
    if (
      reduceMotion.matches ||
      isPausedByUser ||
      isHovered ||
      containsFocus ||
      document.hidden
    ) return;
    autoplayTimer = window.setInterval(() => activateTab(activeIndex + 1), 6500);
  }

  function updateToggle() {
    if (!toggle) return;

    if (reduceMotion.matches) {
      toggle.disabled = true;
      toggle.textContent = "已减少动态";
      toggle.setAttribute("aria-pressed", "true");
      return;
    }

    toggle.disabled = false;
    toggle.textContent = isPausedByUser ? "继续轮播" : "暂停轮播";
    toggle.setAttribute("aria-pressed", String(isPausedByUser));
  }

  tabs.forEach((tab, index) => {
    tab.addEventListener("click", () => {
      activateTab(index);
      startAutoplay();
    });

    tab.addEventListener("keydown", (event) => {
      let nextIndex = null;

      if (event.key === "ArrowRight" || event.key === "ArrowDown") {
        nextIndex = activeIndex + 1;
      } else if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
        nextIndex = activeIndex - 1;
      } else if (event.key === "Home") {
        nextIndex = 0;
      } else if (event.key === "End") {
        nextIndex = tabs.length - 1;
      }

      if (nextIndex !== null) {
        event.preventDefault();
        activateTab(nextIndex, true);
        startAutoplay();
      }
    });
  });

  demo.addEventListener("mouseenter", () => {
    isHovered = true;
    stopAutoplay();
  });

  demo.addEventListener("mouseleave", () => {
    isHovered = false;
    startAutoplay();
  });

  demo.addEventListener("focusin", () => {
    containsFocus = true;
    stopAutoplay();
  });

  demo.addEventListener("focusout", (event) => {
    if (!demo.contains(event.relatedTarget)) {
      containsFocus = false;
      startAutoplay();
    }
  });

  toggle?.addEventListener("click", () => {
    isPausedByUser = !isPausedByUser;
    updateToggle();
    startAutoplay();
  });

  document.addEventListener("visibilitychange", startAutoplay);
  reduceMotion.addEventListener?.("change", () => {
    updateToggle();
    startAutoplay();
  });

  activateTab(0);
  updateToggle();
  startAutoplay();
}

document.querySelectorAll("[data-media-frame] img").forEach((image) => {
  const markAsMissing = () => {
    image.hidden = true;
    image.closest("[data-media-frame]")?.classList.add("is-missing");
  };

  image.addEventListener("error", markAsMissing);
  if (image.complete && image.naturalWidth === 0) markAsMissing();
});

const workflow = document.querySelector("[data-workflow]");

if (workflow) {
  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          workflow.classList.add("is-visible");
          observer.disconnect();
        }
      },
      { threshold: 0.25 },
    );
    observer.observe(workflow);
  } else {
    workflow.classList.add("is-visible");
  }
}
