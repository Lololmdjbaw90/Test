// Shared framer-motion variants so pages animate consistently.
export const spring = { type: "spring", stiffness: 380, damping: 30 };
export const softSpring = { type: "spring", stiffness: 220, damping: 26 };

export const fadeUp = {
  hidden: { opacity: 0, y: 16 },
  show: { opacity: 1, y: 0, transition: { duration: 0.45, ease: [0.2, 0.8, 0.2, 1] } },
};

export const fadeIn = {
  hidden: { opacity: 0 },
  show: { opacity: 1, transition: { duration: 0.35 } },
};

export const popIn = {
  hidden: { opacity: 0, scale: 0.92 },
  show: { opacity: 1, scale: 1, transition: spring },
};

export const stagger = (delayChildren = 0.04, staggerChildren = 0.05) => ({
  hidden: {},
  show: { transition: { delayChildren, staggerChildren } },
});

// No `filter` here on purpose: a filter on the page wrapper would become the
// containing block for position:fixed descendants.
export const pageTransition = {
  initial: { opacity: 0, y: 12 },
  animate: { opacity: 1, y: 0, transition: { duration: 0.32, ease: [0.2, 0.8, 0.2, 1] } },
  exit: { opacity: 0, y: -8, transition: { duration: 0.15 } },
};
