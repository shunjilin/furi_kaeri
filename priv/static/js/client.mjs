window.addEventListener('click', (event) => {
    const path = event.composedPath();
    const target = path.find(el =>
        el.getAttribute
        && el.getAttribute('data-confirm')
        && el.tagName == 'BUTTON'
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

let countdownInterval = null;
let currentSeconds = 0;

function updateDisplay(parentEl, seconds) {
    const root = parentEl.shadowRoot || parentEl;
    const timeTag = root.querySelector('#countdown-timer time');
    if (!timeTag) return;

    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    timeTag.innerText =
        `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
}

setInterval(() => {
    const serverComponent = document.querySelector('lustre-server-component');

    if (!serverComponent) return;

    const root = serverComponent.shadowRoot || serverComponent;
    const timerEl = root.querySelector("#countdown-timer");

    if (!timerEl) {
        if (countdownInterval) {
            clearInterval(countdownInterval);
            countdownInterval = null;
        }
        return;
    }

    const serverSeconds = parseInt(timerEl.getAttribute('data-seconds'), 10);

    // If timer not started or the server's timer drifts significantly
    if (!countdownInterval || Math.abs(currentSeconds - serverSeconds) > 2) {
        currentSeconds = serverSeconds;

        if (countdownInterval) {
            clearInterval(countdownInterval);
        }

        countdownInterval = setInterval(() => {
            if (currentSeconds > 0) {
                currentSeconds--;
                updateDisplay(serverComponent, currentSeconds);
            } else {
                clearInterval(countdownInterval);
            }
        }, 1000);
    }
}, 500);