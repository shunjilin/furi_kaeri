window.addEventListener('click', (e) => {
    const path = e.composedPath();
    const target = path.find(el =>
        el.getAttribute && el.getAttribute('data-confirm')
    );

    if (target) {
        const msg = target.getAttribute('data-confirm');
        if (!confirm(msg)) {
            e.preventDefault();
            e.stopPropagation();
        }
    }
}, true);