(() => {
  if (!window.IntersectionObserver || !Element.prototype.animate) return;

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  if (reducedMotion.matches) return;

  const revealInset = 56;

  // [01] Keep content visible and play the entrance only as each block comes into view.
  const observer = new IntersectionObserver((entries) => {
    for (const { isIntersecting, target } of entries) {
      if (!isIntersecting) continue;
      observer.unobserve(target);
      if (reducedMotion.matches || target.matches(':focus-within, :target') || target.querySelector(':target')) continue;
      if (target.closest('.platform-previews > section')?.querySelector(':target')) continue;

      target.animate(
        [{ opacity: 0.56, transform: 'translateY(28px)' }, { opacity: 1, transform: 'none' }],
        { duration: 580, easing: 'ease-out' }
      );
    }
  }, { rootMargin: `0px 0px -${revealInset}px 0px` });

  // [02] Reveal each preview as it enters, even if the long download card is already in view.
  const sections = document.querySelectorAll(
    '.site-content > .card:not(#get-the-app), .policy-copy > section, .platform-previews figure'
  );
  for (const section of sections) {
    if (section.getBoundingClientRect().top >= window.innerHeight - revealInset) observer.observe(section);
  }
})();
