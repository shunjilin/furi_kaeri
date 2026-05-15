window.addEventListener('click', (event) => {
    const path = event.composedPath();
    const target = path.find(el =>
        el.getAttribute && el.getAttribute('data-confirm')
    );

    if (target) {
        const msg = target.getAttribute('data-confirm');
        if (!confirm(msg)) {
            event.preventDefault();
            event.stopPropagation();
        }
    }
}, true);

window.addEventListener('drop', (event) => {
    const path = event.composedPath();
    const target = path.find(el =>
        el.getAttribute && el.getAttribute('data-confirm')
    );

    if (target) {
        const subjectId = event.dataTransfer.getData("text/plain");
        const targetId = target.id;

        if (subjectId == targetId) {
            return;
        }

        const msg = target.getAttribute('data-confirm');
        if (!confirm(msg)) {
            event.preventDefault();
            event.stopPropagation();
        }
    }
}, true);

window.addEventListener('dragstart', (event) => {
    const path = event.composedPath();
    const target = path.find(el =>
        el.getAttribute && el.getAttribute('data-confirm')
    );
    if (target) {
        event.dataTransfer.setData('text/plain', target.id);
        event.dataTransfer.dropEffect = 'move';
    }
});


window.addEventListener('dragover', (event) => {
    const path = event.composedPath();
    const target = path.find(el =>
        el.getAttribute && el.getAttribute('data-dropzone') == 'true'
    );

    if (target) {
        event.preventDefault();
    }
})
