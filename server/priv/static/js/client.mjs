class ConfirmAction extends HTMLElement {
    connectedCallback() {
        this.addEventListener('click', this.handleEvent, true);
    }
    disconnectedCallback() {
        this.removeEventListener('click', this.handleEvent, true);
    }
    handleEvent(event) {
        const msg = this.getAttribute('message') || 'Are you sure?';
        if (!confirm(msg)) {
            event.preventDefault();
            event.stopPropagation();
        }
    }
}

customElements.define('confirm-action', ConfirmAction);

class DraggableItem extends HTMLElement {
    connectedCallback() {
        this.setAttribute('draggable', 'true');
        this.addEventListener('dragstart', this.handleDragStart);
    }

    handleDragStart = (event) => {
        if (!this.id) {
            throw new Error("id is required for draggable item")
        }
        event.dataTransfer.setData('text/plain', this.id);
        event.dataTransfer.dropEffect = 'move';
    }
}
customElements.define('draggable-item', DraggableItem);


class DropZone extends HTMLElement {
    connectedCallback() {
        this.addEventListener('dragover', this.handleDragOver);
    }

    handleDragOver = (event) => {
        event.preventDefault();
    }
}
customElements.define('drop-zone', DropZone);


class ConfirmDrop extends HTMLElement {
    connectedCallback() {
        this.addEventListener('drop', this.handleDrop, true);
    }

    disconnectedCallback() {
        this.removeEventListener('drop', this.handleDrop, true);
    }

    handleDrop = (event) => {
        const sourceId = event.dataTransfer.getData('text/plain');

        const target = event.target.closest('[id]');
        const targetId = target ? target.id : '';

        console.log(targetId)
        console.log(sourceId)

        if (sourceId === targetId) {
            event.preventDefault();
            event.stopPropagation();
            return;
        }

        const msg = this.getAttribute('message') || 'Are you sure?';
        if (!confirm(msg)) {
            event.preventDefault();
            event.stopPropagation();
        }

        console.log("Dispatch")

        this.dispatchEvent(new CustomEvent('card-merged', {
            bubbles: true,
            composed: true,
            detail: { sourceId, targetId }
        }));
    }
}
customElements.define('confirm-drop', ConfirmDrop);

class AppTimer extends HTMLElement {
    connectedCallback() {
        this.secondsLeft = parseInt(this.getAttribute('seconds'), 10) || 0;

        this.innerHTML = `
      <time datetime="PT${this.secondsLeft}S" aria-atomic="true"></time>
    `;
        this.timeEl = this.querySelector('time');

        this.updateDisplay();

        this.timer = setInterval(() => {
            if (this.secondsLeft > 0) {
                this.secondsLeft--;
                this.updateDisplay();
            } else {
                clearInterval(this.timer);
            }
        }, 1000);
    }

    disconnectedCallback() {
        clearInterval(this.timer);
    }

    updateDisplay() {
        const mins = Math.floor(this.secondsLeft / 60);
        const secs = this.secondsLeft % 60;
        this.timeEl.innerText = `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
    }
}

customElements.define('app-timer', AppTimer);

class LucideXIcon extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
    }

    connectedCallback() {
        this.shadowRoot.innerHTML = `
            <style>
                :host {
                    display: inline-flex;
                    align-items: center;
                    justify-content: center;
                    width: var(--icon-size, var(--space-4));
                    height: var(--icon-size, var(--space-4));
                    color: var(--icon-color, var(--color-text));
                }
                svg {
                    width: 100%;
                    height: 100%;
                }
            </style>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M18 6 6 18"/>
                <path d="m6 6 12 12"/>
            </svg>
        `;
    }
}

customElements.define('lucide-x', LucideXIcon);