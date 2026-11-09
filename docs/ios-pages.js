(() => {
  if (!window.IntersectionObserver || !Element.prototype.animate) return;

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  if (reducedMotion.matches) return;

  // [01] Keep all content visible and animate only the first time a section comes into view.
  const observer = new IntersectionObserver((entries) => {
    for (const { isIntersecting, target } of entries) {
      if (!isIntersecting) continue;
      observer.unobserve(target);
      if (reducedMotion.matches || target.matches(':focus-within, :target') || target.querySelector(':target')) continue;

      target.animate(
        [{ opacity: 0.88, transform: 'translateY(10px)' }, { opacity: 1, transform: 'none' }],
        { duration: 300, easing: 'ease-out' }
      );
    }
  }, { rootMargin: '0px 0px -24px 0px' });

  const sections = document.querySelectorAll('.site-content > .card, .policy-copy > section, .platform-previews');
  for (const section of sections) {
    if (section.getBoundingClientRect().top >= window.innerHeight) observer.observe(section);
  }
})();
