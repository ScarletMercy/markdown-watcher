import { renderMarkdown } from './render.js';
import { shouldRender } from './mermaid-cache.js';
window.renderMarkdown = renderMarkdown;
window.shouldRender = shouldRender;
